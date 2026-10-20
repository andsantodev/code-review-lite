# Changelog

Todas as mudanças relevantes desta skill. Formato baseado em
[Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [0.2.0] - 2026-10-20

### Adicionado

- Checagem **9 — Autenticação e sessão** (`references/auth-session.md`): token em
  `localStorage`/`sessionStorage`, logout sem invalidação no servidor, sessão sem
  expiração/refresh, `@supabase/ssr` em Next, verificação no servidor com `getClaims()`
  (`getUser()` em ação sensível, `getSession()` nunca como autorização) e CSRF.
- Checagem **10 — Configuração de produção e URLs externas**
  (`references/security-config.md`): CORS/allowlist/`Vary: Origin`, headers e CSP, source
  maps em produção, erros verbosos, open redirect/`javascript:`/`data:`, SSRF server-side
  e SRI como nota.
- Scan de **nome secret-like em variável pública** (`NEXT_PUBLIC_*`, `VITE_*`,
  `NUXT_PUBLIC_*`), com filtro para chaves publicáveis e placeholders.
- Documentação de `import 'server-only'`, `.env.example` sem valor real e verificação
  opcional do bundle antes do deploy (checagem 2).
- README e este CHANGELOG.

### Alterado

- `references/idor-authz.md`: Server Actions/Route Handlers explicitados como endpoints
  públicos (autenticação + dono + schema da entrada) e regra para guarda só no cliente.
- `references/supabase-production-checklist.md`: `@supabase/ssr`, `getClaims()`/
  `getUser()`/`getSession()` e chaves privadas em variável com prefixo público.
- Arquivos canônicos do harness aceitos em `docs/` **e** na raiz.
- Fora de escopo explicitado: qualidade/estilo e a11y ficam com a Definition of Done do
  harness; a skill pode ser chamada pela inspeção de release do harness, sem depender
  dele.
- Stack: Next.js/React em primeiro plano; conteúdo de Vue mantido sem expansão.

### Corrigido

- Regex do fallback de segredos com alternativa vazia (`(RSA |EC |OPENSSH |)`), que fazia
  o `grep -E` do macOS falhar com "empty (sub)expression" e silenciava o fallback.
- Referências cruzadas que citavam "checagem 1" para segredos (é a checagem 2).
