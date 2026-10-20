# Arquivos `.md`/notas que não deveriam ir para o GitHub

Objetivo: separar documentação de estado do projeto (que **deve** ir para o Git) de
rascunhos/notas de trabalho que só existem para uso local e às vezes acabam com dado
sensível colado dentro.

## Nunca flagrar só por existir (são estado do harness, vão para o Git por design)

- `AGENTS.md`
- `feature_list.json`
- `progress.md`
- `session-handoff.md`
- `docs/PRD.md`
- Adaptadores de IDE (`CLAUDE.md`, `.cursor/rules/*.mdc`, etc.)

Esses arquivos só entram no relatório se o conteúdo bater em algum padrão de segredo da
checagem 1 (ex.: alguém colou uma URL de banco com senha dentro de uma nota do
`session-handoff.md` sem perceber) — nunca pela existência do arquivo.

## Flagrar por nome (padrão de arquivo local/rascunho)

- `NOTES*.md`, `SCRATCH*.md`, `*.local.md`, `*.private.md`, `DRAFT*.md`
- Briefs de ferramenta externa colados manualmente (ex.: export de design tool, resposta
  de API, log de terminal colado num `.md` para referência) — comum acontecer de vir
  junto uma chave ou URL interna sem querer.
- Qualquer `.md`/`.txt` fora de `docs/` que pareça anotação pessoal de sessão, não
  documentação do produto.

## Flagrar por conteúdo (independente do nome)

Rodar o mesmo scan de segredos da checagem 1 (`scripts/scan-secrets.sh`) também sobre
`.md`/`.txt`, não só sobre código — é o vetor mais comum: alguém cola um erro, uma
resposta de API ou uma connection string numa nota "só para lembrar depois" e esquece
que aquilo vai para o commit.

## O que fazer com o que for flagrado

1. Confirmar com o usuário se o arquivo é necessário no repositório.
2. Se não for: sugerir mover para fora do repo ou adicionar ao `.gitignore` — nunca
   apagar o arquivo sozinho sem confirmação.
3. Se for necessário mas tiver segredo colado dentro: sugerir remover só o trecho
   sensível, mantendo o resto da nota.

## Checklist ao revisar um diff

- [ ] Nenhum `.md`/`.txt` novo no diff bate em padrão de nome de rascunho/local sem
      estar no `.gitignore`.
- [ ] Nenhum `.md`/`.txt` (incluindo os canônicos do harness) contém segredo/credencial
      colada no texto.
- [ ] `.gitignore` cobre os padrões de nota local que o projeto de fato usa (se o
      usuário tiver convenção própria, por exemplo `*.scratch.md`).
