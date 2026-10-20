# Autorização / IDOR — Guia rápido (Server Actions, Route Handlers, RPC)

Objetivo: achar onde uma ação que devia checar "esse recurso é do usuário logado?" não
checa — o clássico IDOR/BOLA. RLS do Supabase ajuda, mas **não cobre tudo**: qualquer
código que rode com a `service_role` key (Edge Function, cron, Server Action que usa o
client admin) ignora RLS por definição — a checagem de dono vira responsabilidade do
código, não do banco.

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
