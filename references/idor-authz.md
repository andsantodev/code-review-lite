# Autorização / IDOR — Guia rápido (Server Actions, Route Handlers, RPC)

Objetivo: achar onde uma ação que devia checar "esse recurso é do usuário logado?" não
checa — o clássico IDOR/BOLA. RLS do Supabase ajuda, mas **não cobre tudo**: qualquer
código que rode com a `service_role` key (Edge Function, cron, Server Action que usa o
client admin) ignora RLS por definição — a checagem de dono vira responsabilidade do
código, não do banco. Na mesma família entram a falta de autenticação e a falta de
validação de schema dentro do handler — ver a seção "Server Actions e Route Handlers são
endpoints públicos".

## Onde isso costuma vazar

- **Server Actions** (`'use server'`) e **Route Handlers** (`app/api/**/route.ts`) que
  recebem um `id` do client (body, query, param de rota) e usam esse `id` direto numa
  query, sem comparar com o usuário da sessão.
- **RPC do Supabase chamada com a `service_role` key** (bypassa RLS) sem checagem
  explícita de dono dentro da função ou antes de chamá-la.
- **Edge Functions** que recebem `user_id` no payload do request em vez de derivar da
  sessão/token validado.
- Rotas de **update/delete** em geral são o ponto mais comum — leitura (`select`)
  costuma ter RLS mais testada, escrita é onde o "esquecimento" acontece.

## Server Actions e Route Handlers são endpoints públicos

Não é porque a função só é chamada por um botão dentro do app que ela só pode ser chamada
dali. A doc do Next é explícita: ao exportar uma Server Action, ela fica alcançável por
`POST` direto, mesmo que não esteja importada em nenhum componente — "you should still
treat Server Actions as reachable via direct POST requests and verify authentication and
authorization inside each one"
([Data Security](https://nextjs.org/docs/app/guides/data-security#built-in-server-actions-security-features)).
O mesmo vale para `app/api/**/route.ts`.

Por isso cada um deles precisa das três checagens, **no próprio handler**:

1. **Autenticação** — quem está chamando? (`getClaims()`/`auth()`/sessão validada.)
2. **Autorização do dono** — esse usuário pode agir sobre *este* recurso?
3. **Schema/tipo da entrada** — o payload tem o formato esperado? `orderId` é string,
   `amount` é número positivo, campo desconhecido é rejeitado? (zod, valibot, TypeScript
   em runtime — tipo estático não valida nada em runtime.)

Checagem de página/rota não cobre a action: um `redirect('/login')` no Server Component
controla o que renderiza, não quem chama a action.

```ts
// perigoso: sem schema, sem auth — e ainda aceita qualquer campo do body
'use server'
export async function updateProfile(formData: FormData) {
  await supabaseAdmin
    .from('profiles')
    .update(Object.fromEntries(formData))
    .eq('id', formData.get('id'))
}
```

```ts
// seguro: auth + schema + dono derivado da sessão
'use server'
const schema = z.object({ displayName: z.string().min(1).max(80) })

export async function updateProfile(formData: FormData) {
  const parsed = schema.safeParse({ displayName: formData.get('displayName') })
  if (!parsed.success) throw new Error('invalid input')

  const { data, error } = await supabase.auth.getClaims()
  if (error || !data?.claims?.sub) throw new Error('unauthorized')

  await supabaseAdmin
    .from('profiles')
    .update(parsed.data)
    .eq('id', data.claims.sub) // id vem da sessão verificada, não do FormData
}
```

## Guarda só no cliente (ProtectedRoute, `v-if`, router guard)

`<ProtectedRoute>`, `v-if="isLoggedIn"`, `beforeEnter` do Vue Router e afins controlam
**renderização**, não acesso. O dado por trás continua existindo no endpoint.

Só reporte quando o dado ou a mutação for alcançável sem checagem no servidor — ou seja,
quando o endpoint que alimenta aquela tela responde a um request direto sem auth. Se o
Route Handler/Server Action/RPC já valida no servidor, o guard de cliente é UX e **não é
achado**.

E não crie um check do tipo "todas as rotas privadas têm `ProtectedRoute`": isso é padrão
de organização de front, não controle de segurança — gera ruído e falso positivo em
projetos que resolvem auth no layout ou no proxy/middleware.

## Padrão perigoso

```ts
// Server Action — recebe orderId do client e não confirma que é do usuário logado
export async function cancelOrder(orderId: string) {
  await supabaseAdmin.from('orders').update({ status: 'cancelled' }).eq('id', orderId)
}
```

```ts
// Route Handler — usa user_id do body em vez da sessão
export async function POST(req: Request) {
  const { userId, amount } = await req.json()
  await supabaseAdmin.from('wallets').update({ balance: amount }).eq('user_id', userId)
}
```

## Padrão seguro

```ts
// Deriva o dono da sessão, não do payload — e ainda filtra pelo dono na query
export async function cancelOrder(orderId: string) {
  const session = await auth()
  if (!session?.user?.id) throw new Error('unauthorized')

  const { data, error } = await supabaseAdmin
    .from('orders')
    .update({ status: 'cancelled' })
    .eq('id', orderId)
    .eq('user_id', session.user.id) // dono checado explicitamente, RLS bypassada de propósito
}
```

Se o client usado for o **anon** (não admin) e a tabela tiver RLS com policy baseada em
`auth.uid()`, o banco já recusa a atualização de recurso alheio — nesse caso o achado
só é real se a RLS estiver ausente/mal configurada (ver
`references/supabase-production-checklist.md`), não pela ausência do `.eq('user_id', ...)`
no código.

## Antes de reportar (evidência > padrão)

Aplicar o princípio geral do `SKILL.md`, com foco extra em:

- **Rastrear imports** — "sem auth visível no arquivo" não é achado se a checagem está
  num wrapper/helper importado (`requireAuth()`, `canPermission()`, etc.). Abrir o
  import antes de reportar.
- Se o client usado é o **anon** e a tabela tem RLS testada, o risco já está mitigado
  no banco — não duplicar o achado nos dois lugares.
- Recurso público por regra de negócio (ex.: perfil público, listagem pública) não é
  IDOR — confirmar se o dado exposto por design bate com o que a rota expõe.
- **Server Action/Route Handler é endpoint público**: não aceite "só o botão chama isso"
  como justificativa. Mas também não reporte falta de auth sem confirmar que a rota é
  realmente invocável (middleware/proxy que bloqueia antes, `matcher` do proxy, auth no
  layout que cobre a action importada).
- **Validação de tipo em TypeScript não é validação de runtime** — não conta como schema
  validado.
- Guard de cliente (`ProtectedRoute`, `v-if`, router guard) não é achado por si: só vira
  quando o endpoint por trás responde sem checagem server-side.

## Checklist ao revisar um diff

- [ ] Toda mutação sensível (delete, pagamento, alterar dado de outro usuário) deriva o
      dono do recurso da sessão/token validado — nunca de `id`/`userId` vindo do
      body/query/param sem comparar.
- [ ] Toda chamada que usa a `service_role` key (bypassa RLS) tem checagem de dono
      explícita no código antes ou dentro da query.
- [ ] Toda RPC/Edge Function que recebe `user_id` no payload valida contra a sessão, não
      confia cegamente no valor recebido.
- [ ] Auth ausente no arquivo foi checada contra wrappers/helpers importados antes de
      virar achado.
- [ ] Toda Server Action/Route Handler valida **schema/tipo da entrada** em runtime
      (zod ou equivalente), não só o tipo do TypeScript.
- [ ] Nenhum handler usa campo do payload (`id`, `userId`, `role`) para decidir
      permissão — nem para escolher o registro, nem para checar dono.
- [ ] Guard de cliente só foi reportado quando o endpoint por trás responde sem
      checagem no servidor.
