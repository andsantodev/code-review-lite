# Autenticação e sessão — Guia rápido (cookies, storage, Supabase SSR, CSRF)

Objetivo: achar onde a sessão do usuário é tratada de um jeito que dá para: roubar o
token (XSS → storage), continuar usando a sessão depois do logout, ou disparar uma
mutação em nome do usuário sem o navegador dele querer (CSRF). Não é um checklist de
"auth bem feita" em geral — é o recorte que gera achado de segurança de verdade.

## Onde isso costuma vazar

- **Token/sessão em `localStorage` ou `sessionStorage`** — qualquer XSS no mesmo domínio
  lê o token e o reusa fora do navegador. Em app com SSR, o correto é cookie (para o
  servidor conseguir ler) em vez de storage acessível só pelo client.
- **Logout que só limpa estado local** (`localStorage.clear()`, reset do store, redirect
  para `/login`) sem chamar o `signOut()`/endpoint que invalida a sessão no servidor — o
  refresh token continua válido e reutilizável.
- **Sessão sem expiração/refresh** — token de vida longa sem renovação nem revogação.
- **CSRF** — mutação por `GET`, ou cookie de sessão enviado em request cross-site sem
  nenhuma checagem de origem.

## Supabase + Next.js: qual método usar no servidor

A documentação atual do Supabase define três métodos com papéis diferentes
([Choosing an auth method](https://supabase.com/docs/guides/auth/server-side/nextjs#choosing-an-auth-method)):

- **`getClaims()`** — método recomendado para proteger páginas e dados. Lê o access token
  e **verifica a assinatura do JWT a cada chamada**: localmente contra o JWKS em cache
  quando o projeto usa chave assimétrica (padrão em projetos novos), ou chamando o Auth
  server quando a chave é simétrica. Quando o token está perto de expirar, renova a
  sessão antes de verificar.
- **`getUser()`** — faz chamada de rede ao Auth server e devolve o registro mais atual do
  usuário. É o único que confirma que a sessão ainda existe: `getClaims()` valida
  assinatura e expiração, mas **não** verifica no Auth server se o usuário deslogou ou se
  a sessão foi revogada ([FAQ de cookies](https://supabase.com/docs/guides/auth/server-side/advanced-guide#how-do-i-make-the-cookies-httponly)).
- **`getSession()`** — devolve a sessão crua (access token, refresh token, expiração) lida
  do storage/cookie, **sem revalidar**. Serve para encaminhar o access token a outro
  serviço, nunca para decidir autorização.

Resultado prático para o gate:

| Situação | Classificação |
|---|---|
| `getClaims()` protegendo página/dado no servidor | ✅ padrão recomendado |
| `getUser()` em ação sensível ou onde importa garantir que a sessão não foi revogada | ✅ esperado |
| `getSession()` no servidor alimentando decisão de acesso (`if (session) ...`) | 🟠/🔴 conforme o dado atrás |
| `supabase-js` puro no server de um projeto Next (sem `@supabase/ssr`) | 🟠 config divergente do recomendado |

> "Anyone can forge the session cookie, so trusting it without verification lets an
> attacker render another user's page. Always use `supabase.auth.getClaims()` to protect
> pages and user data. *Never* trust `supabase.auth.getSession()` inside server code."
> — [Supabase, Next.js SSR](https://supabase.com/docs/guides/auth/server-side/nextjs)

### Padrão perigoso

```ts
// Route Handler: getSession() lê o cookie sem revalidar e vira a decisão de acesso
export async function GET() {
  const supabase = await createClient()
  const { data: { session } } = await supabase.auth.getSession()
  if (!session) return new Response('unauthorized', { status: 401 })

  return Response.json(await getPrivateData(session.user.id))
}
```

### Padrão seguro

```ts
// Verifica o JWT no servidor; erro/null significa não autenticado
export async function GET() {
  const supabase = await createClient()
  const { data, error } = await supabase.auth.getClaims()
  if (error || !data?.claims?.sub) return new Response('unauthorized', { status: 401 })

  return Response.json(await getPrivateData(data.claims.sub))
}
```

Em ação destrutiva/sensível (trocar e-mail, excluir conta, pagamento), chamar
`getUser()` antes: é o que garante que a sessão não foi revogada desde a emissão do
token.

## CSRF

- **Mutação por `GET`** (link que deleta, `href` que aprova) é bloqueante quando a rota
  muda estado: qualquer `<img>`/prefetch de terceiro dispara.
- **Cookie de sessão com `SameSite=None`** sem token anti-CSRF e sem checagem de origem
  deixa o navegador enviar credencial em request cross-site.
- **Auth por cookie implementada à mão** (não Supabase, não Next Auth) precisa de token
  anti-CSRF ou de origem verificada no servidor.
- **Server Actions do Next.js não são achado de CSRF por padrão.** A doc atual diz que
  elas só aceitam `POST` e comparam o header `Origin` com `Host`/`X-Forwarded-Host`,
  abortando quando não batem
  ([Allowed origins](https://nextjs.org/docs/app/guides/data-security#allowed-origins-advanced)).
  Só reportar se: `serverActions.allowedOrigins` estiver com curinga amplo demais, se
  houver Route Handler próprio sem checagem de origem, ou se a mutação estiver exposta em
  `GET`.

## Cookies

- `HttpOnly` + `Secure` + `SameSite=Lax`/`Strict` é o padrão sensato para **cookie de
  sessão próprio** (auth implementada no projeto).
- `SameSite=Lax` é o default recomendado pelo próprio Supabase para os cookies de auth
  ([FAQ](https://supabase.com/docs/guides/auth/server-side/advanced-guide#what-should-i-use-for-the-samesite-property)).
- **Não imponha Access + Refresh token como regra universal.** Se o projeto usa
  `@supabase/ssr`, refresh e rotação já são gerenciados pelo pacote — exigir
  implementação manual é falso positivo.
- **Cookie do `@supabase/ssr` sem `HttpOnly` não é achado.** O pacote é explícito: o lado
  browser precisa ler o refresh token para manter a sessão, então marcar `HttpOnly`
  quebraria o fluxo. A mitigação real é não ter XSS (ver `references/xss-prevention.md`)
  e ter CSP.
- `Max-Age` curto em cookie de refresh token também não é achado — só piora a UX sem
  encerrar a sessão de fato.

## Antes de reportar (evidência > padrão)

Aplicar o princípio geral do `SKILL.md`, com foco extra em:

1. **Rastrear onde o token é lido no servidor.** `getSession()` num arquivo de helper só é
   achado se o resultado dele chegar a uma decisão de acesso ou a uma query. Se só
   encaminha o token para outro serviço, não é.
2. **Confirmar que a mutação é alcançável.** Logout que "só limpa local" precisa ter o
   endpoint/`signOut()` ausente em todo o fluxo — às vezes ele está num hook importado ou
   no `onAuthStateChange`.
3. **Confirmar que o dado atrás é privado.** Sessão lida de forma frouxa numa página
   pública não vira 🔴.
4. **Confirmar o vetor de CSRF.** Server Action do Next: não reportar sem uma das
   exceções acima. Cookie próprio: confirmar `SameSite` real configurado, não o default
   presumido.

## Quando NÃO é achado

- `localStorage` usado para preferência de UI (tema, idioma, último filtro) — não é token.
- Token em memória (variável/React state) sem persistência — não sobrevive a reload e não
  é o vetor clássico.
- Ausência de "Access + Refresh token" explícitos em projeto com `@supabase/ssr`.
- Cookie de sessão do Supabase sem `HttpOnly`.
- Server Action do Next sem token anti-CSRF (proteção embutida, ver acima).
- `getClaims()` usado no lugar de `getUser()` numa leitura comum — é o recomendado, não
  uma fragilidade. Só vira achado quando a ação é sensível e a revogação importa.

## Checklist ao revisar um diff

- [ ] Token de sessão não é gravado em `localStorage`/`sessionStorage`; em app com SSR,
      está em cookie.
- [ ] Logout invalida a sessão no servidor (`signOut()`/endpoint), não só limpa estado
      local.
- [ ] No servidor, autorização usa `getClaims()` (ou `getUser()` em ação sensível) —
      `getSession()` não decide acesso.
- [ ] Projeto Next + Supabase usa `@supabase/ssr` com clients separados para server e
      browser.
- [ ] Nenhuma mutação de estado é disparada por `GET`.
- [ ] Cookie de sessão próprio tem `Secure` e `SameSite` coerente; `SameSite=None` só com
      proteção anti-CSRF.
