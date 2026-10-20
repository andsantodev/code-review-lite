# SQL Injection — Guia rápido (Supabase / Postgres / Next.js / Vue)

Objetivo: achar lugares onde entrada do usuário chega perto de uma query sem passar por
parametrização. Não é uma lista exaustiva de OWASP — é o recorte que importa para este
stack.

## Padrões perigosos (bloqueante se input de usuário alcançar)

- Interpolação de string direto em SQL, em qualquer client (`pg`, `postgres.js`,
  `node-postgres`, driver do Prisma via `$queryRawUnsafe`):
  ```ts
  // perigoso
  await sql`SELECT * FROM users WHERE email = '${email}'`
  await client.query(`SELECT * FROM orders WHERE id = ${orderId}`)
  prisma.$queryRawUnsafe(`SELECT * FROM ${table} WHERE id = ${id}`)
  ```
- Supabase `.rpc()` chamando uma função Postgres que monta SQL dinâmico internamente
  com `EXECUTE format(...)` usando parâmetro de texto não tipado.
- Filtros do PostgREST (`.or()`, `.filter()`, `.textSearch()`) construídos por
  concatenação de string vinda do usuário — a sintaxe do `.or()` usa vírgula e
  parênteses como delimitadores, e um valor de usuário com esses caracteres pode alterar
  a lógica do filtro:
  ```ts
  // perigoso: email vem do usuário sem escapar
  supabase.from('users').select().or(`email.eq.${email},name.eq.${email}`)
  ```
- Nome de tabela ou coluna vindo de input do usuário (nem parametrização resolve isso —
  precisa de allowlist).
- Queries dinâmicas de ordenação/paginação (`ORDER BY ${col}`, `LIMIT ${n}`) sem validar
  contra uma lista fixa de colunas/tipos permitidos.

## Padrões seguros (o que deve aparecer no lugar)

- Query builder do Supabase com filtros tipados — `.eq()`, `.match()`, `.in()`,
  `.gte()`/`.lte()` — em vez de montar string:
  ```ts
  supabase.from('users').select().eq('email', email)
  ```
- Placeholders numerados em queries cruas (`$1`, `$2`, ...) via driver, nunca
  interpolação:
  ```ts
  await client.query('SELECT * FROM orders WHERE id = $1', [orderId])
  ```
- Funções RPC do Postgres recebendo parâmetros tipados (`text`, `uuid`, `int`) em vez de
  montar SQL dentro da função a partir de texto livre; se precisar de SQL dinâmico
  dentro da função, usar `format('%I', ...)` para identificadores e `USING` para
  valores, nunca concatenação direta.
- Allowlist explícita quando o campo/coluna de ordenação vem do client:
  ```ts
  const ALLOWED_SORT = ['created_at', 'name', 'price'] as const
  const col = ALLOWED_SORT.includes(sort) ? sort : 'created_at'
  ```
- Para full-text search, usar `.textSearch()` do Supabase com o valor como parâmetro,
  não concatenado dentro da string de busca.

## Checklist ao revisar um diff

- [ ] Nenhuma query crua monta SQL por template string/concatenação com valor vindo de
      request, query param, body ou sessão do usuário.
- [ ] Todo `.or()`/`.filter()` do Supabase com valor de usuário está validado/escapado
      (ou trocado por `.eq()`/`.in()` explícitos).
- [ ] Nome de coluna/tabela dinâmico passa por allowlist, nunca vem direto do client.
- [ ] Funções RPC chamadas recebem parâmetros tipados, não uma string de SQL montada no
      frontend.
- [ ] `ORDER BY`/`LIMIT` dinâmicos são validados contra uma lista fixa.
