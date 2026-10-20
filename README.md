# code-review-lite

Gate rápido de segurança para rodar **antes de `git push` ou deploy**. É uma skill para
agentes (OpenCode, Claude Code e afins) que revisa só o que gera risco real de vazamento
ou exploração — não é um code review de qualidade, estilo ou arquitetura.

Princípio central: **evidência > padrão**. Antes de reportar, a skill confirma que existe
caminho de exploração plausível, que a entrada é controlada por quem ataca, que não há
sanitização/auth no meio e que o código está em caminho de produção. O que não passa
nesse filtro vira nota ou "falso positivo descartado", nunca 🔴/🟠.

Versão atual: **0.2.0** — 10 checagens.

## As 10 checagens

| # | Checagem | Referência |
|---|---|---|
| 1 | Stack e dependências (CVE real, `npm/pnpm/yarn audit`) | — |
| 2 | Segredos, tokens, API keys, service keys | `scripts/scan-secrets.sh` |
| 3 | Arquivos `.md` e notas que não deveriam ir para o Git | `references/sensitive-files-checklist.md` |
| 4 | SQL Injection | `references/sql-injection.md` |
| 5 | XSS | `references/xss-prevention.md` |
| 6 | Autorização / IDOR | `references/idor-authz.md` |
| 7 | Banco como se fosse produção (Supabase) | `references/supabase-production-checklist.md` |
| 8 | Logs com dados sensíveis | — |
| 9 | **Autenticação e sessão** | `references/auth-session.md` |
| 10 | **Configuração de produção e URLs externas** | `references/security-config.md` |

### Novas na 0.2.0

- **9. Autenticação e sessão** — token em `localStorage`/`sessionStorage`, logout que só
  limpa estado local, sessão sem expiração/refresh, `@supabase/ssr` em Next, `getClaims()`
  como verificação no servidor (com `getUser()` em ação sensível e `getSession()` nunca
  como autorização) e CSRF (mutação por `GET`, `SameSite=None`, token anti-CSRF quando a
  auth é por cookie próprio). Inclui os falsos positivos conhecidos: cookie do
  `@supabase/ssr` sem `HttpOnly` e Server Action do Next sem token anti-CSRF.
- **10. Configuração de produção e URLs externas** — CORS com origem refletida e
  credenciais, ausência de allowlist/`Vary: Origin`, headers/CSP, source maps em produção
  (`productionBrowserSourceMaps`, `build.sourcemap`), mensagens de erro verbosas, open
  redirect e esquemas `javascript:`/`data:` no front, SSRF no servidor e SRI como nota de
  baixa severidade.

## Como rodar

A skill é acionada pelo agente quando você pergunta "posso subir isso?", "revisa antes de
commitar" ou pede uma revisão de segurança/deploy. Ela **reporta e sugere correção** —
nunca edita nem commita sozinha.

O scan de segredos também roda isolado:

```bash
bash scripts/scan-secrets.sh              # diretório atual
bash scripts/scan-secrets.sh caminho/     # outro diretório
```

Ordem de preferência: `gitleaks` → `trufflehog` → fallback por regex (sem dependência).
Além dos padrões de segredo, o script sinaliza **nome secret-like em variável pública**
(`NEXT_PUBLIC_*`, `VITE_*`, `NUXT_PUBLIC_*`), porque esse valor vai para o bundle do
browser por definição — ignorando chaves publicáveis (`PUBLISHABLE`, `_ANON_KEY`) e
placeholders. Código de saída diferente de zero = achado.

## Estrutura do repositório

```
code-review-lite/
├── SKILL.md
├── README.md
├── CHANGELOG.md
├── references/
│   ├── auth-session.md
│   ├── idor-authz.md
│   ├── security-config.md
│   ├── sensitive-files-checklist.md
│   ├── sql-injection.md
│   ├── supabase-production-checklist.md
│   └── xss-prevention.md
└── scripts/
    └── scan-secrets.sh
```

## Stacks cobertos

- **Next.js / React — primeiro plano**: Server Actions, Route Handlers, `@supabase/ssr`,
  `proxy.ts`/`middleware.ts`, `next.config`, source maps.
- **Supabase** (Auth, RLS, Storage, Edge Functions) — quando o projeto usa.
- **Vue 3 / Nuxt** — cobertura existente mantida (`v-html`, guard de rota, `NUXT_PUBLIC_*`),
  sem expansão.
- **TypeScript + Vercel** no fluxo de build/deploy.
- Os padrões de segredos, dependências, SQL injection, XSS, IDOR, sessão e configuração
  de produção valem para qualquer stack.

## O que fica explicitamente fora de escopo

- Qualidade e estilo: `console.log` de debug, imports não usados, `any`, estados de UI
  (loading/error/empty), acessibilidade, `onAuthStateChange`. Isso é responsabilidade da
  **Definition of Done do harness**, não desta skill. (Log que despeja dado sensível
  continua sendo achado — checagem 8.)
- `npm outdated`/versão mais nova sem CVE associado — no máximo nota informativa.
- "Todas as rotas privadas têm `ProtectedRoute`" — guard de cliente não é controle de
  acesso; o check é se o endpoint por trás valida no servidor.
- Arquitetura, performance e refactor.
- Gerar ou editar documentos de harness (PRD, `feature_list.json` etc.).

## Relação com o harness (opcional)

A skill **não depende** do harness e roda em qualquer repositório. Quando existe um pacote
Harness, a feature final de inspeção de release **pode** chamá-la como um dos passos do
gate. Os arquivos canônicos do harness (`AGENTS.md`, `feature_list.json`, `progress.md`,
`session-handoff.md`, `PRD.md`, notas de verificação) são aceitos tanto em `docs/` quanto
na raiz — e nunca são flagrados pela existência, só pelo conteúdo.
