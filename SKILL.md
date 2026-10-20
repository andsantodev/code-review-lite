---
name: code-review-lite
description: Faz um gate de segurança e review leve ANTES de um git push ou deploy, verificando dependências com CVE real (npm/pnpm/yarn audit), segredos e credenciais expostas (.env, API keys, tokens, service keys, chaves privadas), URLs privadas hardcoded, arquivos .md/notas que não deveriam ir para o repositório, logs com dados sensíveis, padrões de SQL injection, XSS, IDOR/autorização (Server Actions, Route Handlers, RPC), autenticação e sessão (token em storage, logout que não invalida, @supabase/ssr e getClaims no servidor, CSRF) e configuração de produção (CORS, headers/CSP, source maps, open redirect, SSRF, SRI); e — para stacks com Supabase — uma checklist de "banco como se fosse produção" (RLS, policies, escopo da service_role key). Use sempre que o usuário perguntar se pode subir/commitar/dar push, pedir uma revisão de segurança, um "code review" ou "security review" antes do deploy ou de publicar uma release, mencionar code-review-lite, ou finalizar uma feature e estar prestes a integrar/publicar o código. Não use para escrever, depurar ou revisar código por qualidade/estilo em geral — isso é code-review-skill ou revisão manual. Não use para gerar PRD ou pacote Harness — isso é harness-engineering-prd.
---

# Code Review Lite — Gate de Segurança Pré-Push

Checklist curta e objetiva para rodar **antes de `git push` ou deploy**, focada só em
segurança e vazamento de dados — não é um code review de qualidade/estilo completo.
Feita para o stack **Next.js / React (primeiro plano)**, com suporte a Vue 3, TypeScript,
Supabase e Vercel; os padrões de segredos, dependências, SQL injection, XSS, IDOR,
autenticação/sessão e configuração de produção valem para qualquer stack.

Esta skill **reporta e sugere correção** — nunca edita ou faz commit sozinha. Toda
correção só é aplicada depois de aprovação explícita do usuário, do mesmo jeito que o
resto do fluxo de harness.

## Princípio: evidência > padrão

Antes de reportar qualquer achado nas 10 checagens abaixo — não só nos de código —
confirme que as quatro perguntas seguintes são "sim":

1. Existe um caminho de exploração plausível, não só um padrão que parece arriscado?
2. A entrada chega até ali controlada por quem ataca (request, upload, header, query
   param, body, param de rota)?
3. Não existe sanitização, validação ou auth no meio do caminho (mesmo arquivo,
   wrapper importado, RLS, middleware)?
4. O código está em caminho de produção — não é teste, mock, storybook, ou a própria
   pasta desta skill?

Se qualquer resposta for "não" ou "incerto": não reporte como 🔴/🟠. No máximo uma nota
informativa, ou descarte e liste em "falsos positivos descartados" no relatório final.
Isso vale especialmente para `dangerouslySetInnerHTML`/`v-html` com conteúdo constante,
e para "falta auth" quando ela pode estar num wrapper importado — rastreie antes de
reportar.

## Quando rodar

- Antes de `git push` de uma feature terminada (fecha o WIP=1 da feature).
- Antes de um deploy (Vercel ou outro).
- Sob pedido explícito ("roda o code-review-lite", "posso subir isso?", "revisa antes
  de commitar").

## Fluxo — 10 checagens, nesta ordem

Rode todas, mesmo que uma pareça óbvia de pular — o valor do gate é ser sempre o mesmo
checklist, não um julgamento caso a caso.

### 1. Stack e dependências (CVE real)

- Detecte o stack real do projeto pelo `package.json`/lockfile (Next.js, Vue/Nuxt,
  Vite) antes de aplicar os passos seguintes — isso decide quais referências valem
  (ex.: XSS de React não é igual ao de Vue).
- Rode `npm audit --omit=dev` (ou `pnpm audit`/`yarn audit`, conforme o lockfile) e
  reporte só vulnerabilidade com CVE/GHSA confirmado **na versão instalada**.
- "Tem versão mais nova" sem CVE associado não é achado — vira nota informativa fora
  dos níveis 🔴/🟠, no máximo um lembrete no fim do relatório.

### 2. Segredos, tokens, API keys, service keys

- Rode `scripts/scan-secrets.sh` na raiz do repositório (via bash). O script tenta
  `gitleaks` e depois `trufflehog` se estiverem instalados, e cai para um scan por
  regex (sem dependência) se nenhum dos dois existir.
- Confira se algum `.env` real (não `.env.example`/`.env.sample`) está rastreado pelo
  Git: `git ls-files | grep -E '\.env($|\.[^.]+$)'` — qualquer resultado que não seja
  `.example`/`.sample`/`.template` é bloqueante.
- Confira o `.gitignore` na raiz: precisa cobrir `.env`, `.env.*` (exceto os exemplos),
  `*.pem`, `*.key`, `*.p12`.
- **Variável pública com nome secret-like** é bloqueante: qualquer coisa em
  `NEXT_PUBLIC_*`, `VITE_*` ou `NUXT_PUBLIC_*` vai para o bundle do browser por
  definição. O script sinaliza nome secret-like nesses prefixos e ignora chaves
  publicáveis (`PUBLISHABLE`, `_ANON_KEY`) e placeholders — se o achado for um valor
  real, é 🔴.
- **Separação server/client**: módulo que lê segredo, `service_role` ou client admin
  deve ter `import 'server-only'` (Next) — assim um import acidental no client quebra o
  build em vez de vazar. Em Vue/Nuxt, a regra equivalente é o módulo viver fora do que
  o client importa (e nunca usar prefixo público para ele).
- `.env.example`/`.env.sample` deve existir e listar **apenas nomes** com valor vazio ou
  placeholder — um valor real no exemplo é o mesmo que commitar o `.env`.
- **Opcional, só antes de deploy**: rodar o build e procurar padrões de segredo no bundle
  (`grep -RInE '(SERVICE_ROLE|sk_live|-----BEGIN)' .next/static dist 2>/dev/null`). Não é
  obrigatório no gate de push — build é caro e o scan de fonte já cobre o caso comum.
- Reporte cada achado com arquivo, linha (quando o scanner der) e severidade.

### 3. Arquivos `.md` e notas que não deveriam ir para o GitHub

- Leia `references/sensitive-files-checklist.md`.
- Não trate como problema os arquivos canônicos do harness (`AGENTS.md`,
  `feature_list.json`, `progress.md`, `session-handoff.md`, `docs/PRD.md`, adaptadores
  de IDE) — esses são estado do projeto e devem ir para o Git por design.
- Flagre: notas soltas de trabalho (`NOTES*.md`, `SCRATCH*.md`, `*.local.md`,
  `*.private.md`, rascunhos de design/briefs colados com respostas de ferramenta) e
  qualquer `.md`/`.txt` cujo conteúdo bata nos mesmos padrões de segredo da checagem 2.

### 4. SQL Injection

- Leia `references/sql-injection.md`.
- Aplique só nos arquivos alterados que tocam banco (queries, RPCs, filtros dinâmicos).

### 5. XSS

- Leia `references/xss-prevention.md`.
- Aplique nos arquivos alterados que renderizam conteúdo dinâmico
  (`dangerouslySetInnerHTML`, `v-html`, redirects, markdown de usuário).

### 6. Autorização / IDOR

- Leia `references/idor-authz.md`.
- Aplique em toda Server Action, Route Handler, API route ou RPC que faça leitura ou
  escrita de dado que pertence a um usuário específico.

### 7. Banco de dados como se fosse produção (Supabase)

- Leia `references/supabase-production-checklist.md`.
- Cheque RLS, policies, escopo da `service_role` key, buckets de storage e Edge
  Functions — mesmo em ambiente de desenvolvimento, trate como se já estivesse exposto.
- Se o projeto não usa Supabase, pule esta checagem e diga isso no relatório.

### 8. Logs com dados sensíveis

- Busque `console.log`/`console.error`/`print` (ou equivalente) próximos de variáveis
  chamadas `password`, `token`, `secret`, `apiKey`, `key`, `authorization`, `session`.
- Confira se alguma lib de log em produção despeja corpo completo de request/response
  sem redação.

### 9. Autenticação e sessão

- Leia `references/auth-session.md`.
- Aplique no fluxo de login/logout, no storage do token e em todo código server-side que
  decide acesso (Route Handler, Server Action, proxy/middleware).
- Em Next + Supabase, confirme o uso de `@supabase/ssr` e o método de verificação no
  servidor: `getClaims()` para proteger página/dado, `getUser()` em ação sensível,
  `getSession()` nunca como decisão de autorização.
- CSRF só vira achado quando a mutação sai por `GET`, há cookie `SameSite=None` sem
  proteção, ou a auth por cookie é implementada à mão — Server Actions do Next têm
  proteção embutida (POST + `Origin`/`Host`), não reporte por padrão.

### 10. Configuração de produção e URLs externas

- Leia `references/security-config.md`.
- Aplique em `next.config`/`vercel.json`/`vite.config`, em Route Handlers que definem CORS
  ou fazem `fetch` com URL recebida, e em qualquer `redirect`/`href`/`src` que venha de
  query, props ou API.
- Fique no lado certo da fronteira: no front o risco é open redirect/esquema perigoso
  (`javascript:`, `data:`); no servidor é SSRF. Source maps e SRI entram como 🟠/nota,
  nunca como bloqueio por si só.

## Relatório final

Feche sempre com um resumo por severidade, sem misturar (as checagens puladas ficam
separadas dos três níveis):

- 🔴 **Bloqueante** — segredo real exposto, `.env` rastreado, RLS ausente em tabela
  pública, SQL injection explorável, CORS refletindo qualquer origem com credenciais,
  requisição server-side para URL arbitrária devolvendo dado interno (SSRF), sessão
  confiada a `getSession()` com dado privado atrás. Não deve ir para o GitHub assim.
- 🟠 **Importante** — padrão arriscado mas não confirmado como explorável (ex.: log
  perto de dado sensível, XSS em campo que hoje não recebe input de usuário, open
  redirect sem entrega de token, source maps em produção, CSP ausente).
- ✅ **OK** — checagem passou.
- **Pulado** — checagem não se aplica ao stack (ex.: Supabase em projeto sem Supabase).
  Diga explicitamente qual foi pulada e por quê; não deixe implícito.

Termine perguntando explicitamente se o usuário quer que você aplique as correções
sugeridas (uma por vez, com o diff) ou só deixar o relatório para ele revisar. Nunca
edite arquivos nesta etapa sem essa confirmação.

## Fora de escopo

- Isto não é o `claude-security` (plugin oficial multi-agente da Anthropic, exclusivo
  do Claude Code) — aquele mapeia arquitetura, verifica achados contra falso-positivo e
  gera patches, mas roda em Claude Code, consome tokens do plano pago e pode ficar caro
  em repositórios grandes. Para uma auditoria mais profunda/verificada, rode aquele
  separadamente; esta skill é o gate rápido de todo dia, portável para qualquer
  ambiente (inclusive OpenCode).
- Não faz code review de qualidade, arquitetura ou performance — isso é
  `code-review-skill`/revisão manual.
- Não gera nem edita os documentos do harness — isso é `harness-engineering-prd`.
- Para um projeto 100% React/Next.js/Prisma sem Vue nem Supabase, a skill
  `security-audit` (devfraga/skills-sujeito-programador) vai mais fundo em CVE por
  versão instalada e IDOR em Auth.js — vale considerar como complemento pontual nesses
  casos específicos, não como substituta desta.
