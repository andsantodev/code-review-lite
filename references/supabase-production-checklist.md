# Banco como se fosse produção — Checklist Supabase

Objetivo: revisar o schema/config do Supabase como se já estivesse exposto publicamente
— porque, com a `anon key` no client, ele efetivamente já está. Use o MCP do Supabase
(se disponível no projeto) para ler schema, policies e config real, em vez de assumir
pelo código do frontend.

## Row Level Security (RLS)

- [ ] Toda tabela que recebe leitura/escrita via client (browser) tem
      `ALTER TABLE ... ENABLE ROW LEVEL SECURITY` — tabela sem RLS e com `anon key` de
      acesso é leitura/escrita pública, mesmo sem policy nenhuma escrita.
- [ ] Toda tabela com RLS habilitado tem pelo menos uma policy por operação usada
      (`select`/`insert`/`update`/`delete`) — RLS habilitado sem policy bloqueia tudo,
      o que quebra a feature, então geralmente vem acompanhado de uma policy
      `USING (true)` esquecida ali para "só fazer funcionar".
- [ ] Nenhuma policy usa `USING (true)`/`WITH CHECK (true)` numa tabela que não deveria
      ser pública, só porque foi mais rápido no momento do teste.
- [ ] Policies de escrita usam `auth.uid()` (ou equivalente) para checar dono do
      registro — não confiam num campo `user_id` enviado no payload pelo client.

## Chaves e escopo

- [ ] `service_role` key (ou a nova secret key `sb_secret_...`) **nunca** aparece em
      código que roda no browser — nem em variável de prefixo público
      (`NEXT_PUBLIC_*`/`VITE_*`/`NUXT_PUBLIC_*`), nem hardcoded, nem em resposta de API
      que o client lê. Ela só pode existir em código server-side (route handler, Edge
      Function, cron) — e esse módulo deve ter `import 'server-only'` quando o projeto é
      Next. A checagem 2 (`scripts/scan-secrets.sh`) já sinaliza nome secret-like em
      variável pública.
- [ ] `anon` key pode estar no client normalmente — mas só é segura na medida em que a
      RLS acima está correta; ela não é, por si, um controle de acesso.
- [ ] Nenhuma Edge Function lê segredo hardcoded — tudo via `Deno.env.get(...)`.

## Storage

- [ ] Buckets marcados como `public` são realmente para conteúdo público (avatar,
      asset estático) — nada de dado sensível num bucket público "por conveniência".
- [ ] Buckets privados usam signed URL com expiração, não link direto reaproveitado.
- [ ] Policy de storage (`storage.objects`) segue o mesmo padrão de RLS acima — dono do
      arquivo checado por `auth.uid()`, não por caminho previsível.

## Auth

- [ ] Redirect URLs de auth (`Site URL`/`Redirect URLs` no painel) restritas aos
      domínios reais do projeto — nada de wildcard amplo demais.
- [ ] Nenhuma rota de API confia em `user_id`/`role` vindo do body/query para decidir
      permissão — sempre deriva da sessão/token validado no servidor.
- [ ] Em projeto **Next.js**, o client de Supabase é criado com `@supabase/ssr`
      (`createServerClient` no server, `createBrowserClient` no browser), não com
      `supabase-js` puro lendo cookie na mão — é o que mantém a sessão em cookie e
      permite renovação no proxy/middleware.
- [ ] No servidor, a decisão de acesso usa `getClaims()` (verifica a assinatura do JWT a
      cada chamada; método recomendado pela doc atual) — e `getUser()` quando a ação é
      sensível ou quando é preciso garantir que a sessão não foi revogada, já que
      `getClaims()` não consulta o Auth server sobre logout/revogação.
- [ ] `getSession()` no servidor não alimenta autorização: o cookie pode ser forjado e o
      método não revalida. Uso legítimo é só encaminhar o access token.
- [ ] Detalhamento e casos de falso positivo em `references/auth-session.md`.

## Migrations e schema

- [ ] Migration não tem `DROP TABLE`/`TRUNCATE` sem confirmação explícita do usuário —
      trate como mudança destrutiva, mesmo em projeto solo.
- [ ] Colunas que guardam dado sensível (documento, telefone, endereço) não estão
      expostas por padrão numa view/`select *` usada no client sem necessidade.

## Se o projeto não usa Supabase

Pule esta checagem inteira e diga isso no relatório final — não adapte o checklist para
outro backend "na mão"; se precisar, isso vira uma nova referência dedicada depois.
