# XSS — Guia rápido (Next.js/React + Vue 3)

Objetivo: achar pontos onde conteúdo controlado por usuário (input, query param,
resposta de API externa, upload) é renderizado como HTML/JS sem passar por sanitização
ou escaping automático do framework.

## React / Next.js

- `dangerouslySetInnerHTML` com valor que não passou por um sanitizador (DOMPurify ou
  equivalente) — bloqueante se o valor vier, direta ou indiretamente, de usuário:
  ```tsx
  // perigoso
  <div dangerouslySetInnerHTML={{ __html: comment.body }} />
  // seguro
  <div dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(comment.body) }} />
  ```
- Renderização de Markdown de usuário direto para HTML sem sanitizador no pipeline
  (`marked`/`remark` sem `rehype-sanitize`, por exemplo).
- Construção de URL de redirect ou `href` a partir de query param/input sem validar
  esquema (`javascript:`, `data:`) — abre vetor de XSS via link:
  ```tsx
  // perigoso
  <a href={searchParams.get('next')}>continuar</a>
  ```
- JSON-LD ou `<script type="application/ld+json">` montado com `JSON.stringify` de dado
  de usuário sem escapar `</script>` embutido na string.
- Uso de `eval()`, `new Function()` ou `setTimeout(stringDeUsuário, ...)` com qualquer
  entrada externa.

Fora desses casos, o JSX do React já escapa texto interpolado por padrão
(`{variavel}`) — não precisa de sanitização extra para texto simples.

## Vue 3

- `v-html` com valor que não passou por sanitizador — mesmo risco do
  `dangerouslySetInnerHTML`:
  ```vue
  <!-- perigoso -->
  <div v-html="comment.body"></div>
  <!-- seguro -->
  <div v-html="sanitize(comment.body)"></div>
  ```
- Componente dinâmico (`<component :is="nomeVindoDeUsuario">`) resolvendo um nome que
  não está numa allowlist de componentes conhecidos.
- Binding de atributo `href`/`src` a partir de input sem validar esquema, mesmo padrão
  do React acima.

Interpolação normal (`{{ variavel }}`) e `:atributo="variavel"` já escapam por padrão —
não precisa de sanitização extra para texto simples.

## Geral (qualquer framework)

- CSP (`Content-Security-Policy`) configurado no `next.config`/`vercel.json` como
  camada extra, não como única defesa.
- Nenhum `postMessage` aceitando payload sem checar `event.origin`.
- Upload de arquivo SVG servido sem sanitização pode conter `<script>` embutido — tratar
  como HTML, não como imagem "segura" por padrão.

## Checklist ao revisar um diff

- [ ] Todo `dangerouslySetInnerHTML`/`v-html` com dado que pode vir de usuário passa por
      sanitizador antes de renderizar.
- [ ] Nenhum `href`/redirect é montado direto de query param/input sem checar esquema.
- [ ] Markdown de usuário passa por pipeline com sanitização (não só o parser cru).
- [ ] Nenhum `eval`/`new Function`/`setTimeout` recebe string vinda de fora.
- [ ] Upload de SVG (se houver) é sanitizado ou convertido, não servido cru.
