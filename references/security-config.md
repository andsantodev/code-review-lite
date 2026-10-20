# Configuração de produção e URLs externas — Guia rápido

Objetivo: achar configuração que só faz diferença depois do deploy — CORS permissivo,
headers/CSP ausentes, source maps e mensagens de erro expostas, URL de destino controlada
pelo usuário (open redirect) e requisição server-side para URL arbitrária (SSRF). Nada
aqui é "hardening genérico": cada item precisa de um caminho de exploração plausível.

## CORS

- **Origem refletida + credenciais sem allowlist** é o achado grave: o servidor devolve
  `Access-Control-Allow-Origin: <Origin recebido>` e
  `Access-Control-Allow-Credentials: true`, então qualquer site lê resposta autenticada
  do usuário logado.
  ```ts
  // perigoso: qualquer origem é aceita e a resposta vem com cookie
  headers: {
    'Access-Control-Allow-Origin': req.headers.get('origin') ?? '*',
    'Access-Control-Allow-Credentials': 'true',
  }
  ```
- **`Access-Control-Allow-Origin: *` junto de credenciais** é inválido pela spec — o
  navegador rejeita a resposta. Sozinho não é explorável; no máximo indica config
  copiada/errada. Só vira achado se, na prática, a origem estiver sendo refletida.
- **Allowlist**: a origem precisa ser comparada com uma lista fixa (domínio de prod e de
  preview), não com `origin.startsWith(...)` nem regex frouxa (`/meusite/` aceita
  `meusite.com.evil.net`).
- **`Vary: Origin` ausente** quando a origem é dinâmica e a resposta pode ser cacheada —
  CDN/proxy guarda a resposta com o `ACAO` de um usuário e serve para outro (cache
  poisoning). Em Next, `fetch`/Route Handler com `Cache-Control` público + origem
  refletida é o cenário a checar.
- CORS não é controle de acesso: ele protege o browser, não impede `curl`. Endpoint que
  devolve dado privado precisa de auth própria, não só de CORS restrito.

## Headers de segurança e CSP

- **CSP ausente** é 🟠 no máximo — é camada extra contra XSS, não a única defesa (ver
  `references/xss-prevention.md`). CSP com `unsafe-inline`/`unsafe-eval` em produção
  também é 🟠, não bloqueio.
- **`frame-ancestors`/`X-Frame-Options` ausentes** só importa se houver ação sensível
  clicável (excluir conta, aprovar pagamento) — aí vira 🟠 por clickjacking.
- `X-Content-Type-Options: nosniff`, `Referrer-Policy`, HSTS: nota informativa, não
  bloqueio. Não transformar ausência de hardening em lista de achados.
- Em Next, verificar onde os headers são definidos de fato (`next.config` `headers()`,
  `proxy.ts`/`middleware.ts`, `vercel.json`) antes de afirmar que não existem.

## Source maps e mensagens de erro em produção

- **Next**: `productionBrowserSourceMaps: true` no `next.config` publica os `.map` junto
  dos JS e o Next os serve — a doc diz explicitamente que o default é desligado "to
  prevent you leaking your source on the client".
- **Vite**: `build.sourcemap: true` ou `'inline'` expõe o fonte no bundle; `'hidden'`
  gera o `.map` sem referência no arquivo (não linkado, mas acessível se o nome for
  descoberto).
- Classificação: 🟠 — expõe estrutura interna, nomes de rota e lógica de negócio; **não**
  é 🔴 por si só. Só sobe de nível se o bundle contiver segredo real (aí o achado é da
  checagem 2, não desta).
- **Erro verboso exposto ao client**: stack trace na resposta, `error.message` cru do
  banco/ORM, objeto de erro inteiro em `Response.json(error)`, `detail` de RPC do
  Supabase repassado sem tratamento. 🟠 quando revela schema/consulta; 🔴 se vazar
  credencial/connection string.

## URLs externas no front (open redirect e esquemas perigosos)

Entrada: `redirect`/`next`/`returnTo` de query, `href`/`src` vindo de props ou de resposta
de API, `window.location = param`.

```tsx
// perigoso: destino arbitrário, inclusive javascript:
<a href={searchParams.get('next')}>continuar</a>
router.push(searchParams.get('next')!)

// perigoso: só checa que "tem http", aceita qualquer domínio de atacante
if (!url.startsWith('http')) throw new Error('invalid')
```

Validação esperada: caminho interno começando com `/` e **não** `//` (senão é
protocol-relative para outro domínio), ou parse com `new URL()` + allowlist de host +
allowlist de protocolo (`https:`). `javascript:`/`data:` em `href`/`src` é XSS —
cruzar com `references/xss-prevention.md` em vez de duplicar o achado.

Classificação: 🟠 para open redirect comum; 🔴 se o destino receber token/credencial na
URL ou se o redirect acontecer imediatamente após login/OAuth (entrega de sessão para
domínio do atacante).

## SSRF no servidor (URL controlada pelo usuário)

Só vale para código que roda no **servidor** — Route Handler, Server Action, Edge
Function, cron. No browser, `fetch` para URL do usuário é o próprio usuário navegando; não
é SSRF, é no máximo open redirect/CORS.

```ts
// perigoso: proxy de imagem/PDF/webhook com URL arbitrária
export async function GET(req: Request) {
  const target = new URL(req.url).searchParams.get('url')!
  const res = await fetch(target) // alcança localhost, rede interna, metadata da cloud
  return new Response(await res.text())
}
```

Sinais de exploração: resposta do alvo é repassada (mesmo que parcialmente), o servidor
segue redirects, aceita esquemas além de `https:`, ou não bloqueia IP privado/loopback/
`169.254.169.254` (metadata de cloud). Mitigação esperada: allowlist de hosts, resolver o
DNS e bloquear faixas privadas, `redirect: 'manual'`, timeout e limite de tamanho.

Classificação: 🟠 se só permite requisição sem retorno de conteúdo; 🔴 se devolve o corpo
ou permite alcançar metadata/rede interna.

## SRI (Subresource Integrity)

- `<script src="https://cdn.externo/...">` sem `integrity` — **apenas nota de baixa
  severidade**, nunca bloqueio. Só é relevante se o CDN for comprometido ou o domínio
  mudar de dono.
- Não reportar SRI ausente para asset servido pelo próprio domínio.

## Antes de reportar (evidência > padrão)

Aplicar o princípio geral do `SKILL.md`, com foco extra em:

1. **Confirmar o ambiente real do achado.** CORS permissivo, source map ligado e erro
   verboso precisam estar no caminho de produção (config de prod, não de dev/test).
   `productionBrowserSourceMaps` só tem efeito no build de produção; `build.sourcemap`
   pode estar num `vite.config` de storybook.
2. **Confirmar que a origem é refletida, não apenas `*`.** `*` com credenciais é rejeitado
   pelo navegador — não reportar como exploração.
3. **Rastrear a URL até o `fetch`/redirect final.** Param de query que nunca chega no
   destino não é achado. Abrir o helper/wrapper importado.
4. **Confirmar que o dado atrás é privado.** Open redirect para a home pública não é 🟠;
   SSRF que só busca favicon público não é 🔴.
5. **Ficar no lado certo da fronteira.** Front → open redirect/XSS; server → SSRF. Não
   chamar de SSRF o que acontece no browser.

## Quando NÃO é achado

- `Access-Control-Allow-Origin: *` em endpoint realmente público (CDN de asset, API
  aberta) sem credenciais.
- Ausência de CSP/HSTS/Referrer-Policy em app interno sem input de usuário — no máximo
  nota.
- Source map ligado em ambiente de preview/staging, ou `sourcemap: false` (default).
- `href`/`redirect` apontando para caminho interno fixo (`/dashboard`), ou para URL
  construída no servidor a partir de allowlist.
- `fetch` com URL constante ou vinda de env var do servidor.
- `<script>` do próprio domínio sem `integrity`.
- SRI, HSTS e `nosniff` ausentes: nota, nunca 🔴/🟠.

## Checklist ao revisar um diff

- [ ] CORS com credenciais usa allowlist de origem — nunca origem refletida nem
      `startsWith`/regex frouxa; `Vary: Origin` presente quando a origem é dinâmica.
- [ ] Endpoint que devolve dado privado tem auth própria, não depende de CORS.
- [ ] Headers de segurança definidos no caminho de produção (CSP, `frame-ancestors`,
      `nosniff`); ausência classificada como 🟠/nota, não bloqueio.
- [ ] Source maps desligados em produção (`productionBrowserSourceMaps` ausente/false,
      `build.sourcemap` false).
- [ ] Erro devolvido ao client é mensagem genérica, sem stack/consulta/schema.
- [ ] `redirect`/`href`/`src` com entrada externa validam caminho interno ou protocolo +
      host em allowlist.
- [ ] `fetch` server-side com URL de usuário tem allowlist de host e bloqueio de
      IP privado/metadata — e não repassa o corpo cru.
