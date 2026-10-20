#!/usr/bin/env bash
# scan-secrets.sh — varredura de segredos para o gate code-review-lite.
#
# Ordem de preferência:
#   1. gitleaks (se instalado)      -> https://github.com/gitleaks/gitleaks
#   2. trufflehog (se instalado)    -> https://github.com/trufflesecurity/trufflehog
#   3. fallback por regex (grep)    -> sem dependência, cobertura menor
#
# Uso:
#   ./scan-secrets.sh [caminho]      # default: diretório atual
#
# Saída: texto para humano. Código de saída != 0 se algo foi encontrado.

set -uo pipefail

TARGET="${1:-.}"
FOUND=0

echo "== code-review-lite: scan de segredos em '$TARGET' =="
echo

# --- 1) .env real rastreado pelo Git -----------------------------------
if command -v git >/dev/null 2>&1 && git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  TRACKED_ENV=$(git -C "$TARGET" ls-files | grep -E '(^|/)\.env(\.[^.]+)?$' | grep -Ev '\.(example|sample|template)$' || true)
  if [ -n "$TRACKED_ENV" ]; then
    echo "🔴 BLOQUEANTE — arquivo .env real rastreado pelo Git:"
    echo "$TRACKED_ENV" | sed 's/^/   /'
    echo
    FOUND=1
  fi
fi

# --- 2) gitleaks, se disponível ------------------------------------------
if command -v gitleaks >/dev/null 2>&1; then
  echo "-- rodando gitleaks --"
  if ! gitleaks detect --no-banner --source "$TARGET" --no-git -v; then
    FOUND=1
  fi
  echo
elif command -v trufflehog >/dev/null 2>&1; then
  echo "-- rodando trufflehog --"
  if ! trufflehog filesystem "$TARGET" --no-update --fail; then
    FOUND=1
  fi
  echo
else
  echo "-- gitleaks/trufflehog não encontrados, usando fallback por regex --"
  echo "   (recomendado instalar gitleaks para cobertura melhor: brew install gitleaks"
  echo "   ou veja https://github.com/gitleaks/gitleaks#installing)"
  echo

  # Padrões cobertos pelo fallback (best-effort, não substitui gitleaks):
  #   - AWS access key
  #   - chave privada PEM
  #   - JWT-like (usado por Supabase para anon/service_role) atribuído a variável
  #   - atribuição genérica de secret/token/apikey/password com valor literal
  PATTERN='(AKIA[0-9A-Z]{16})'
  PATTERN+='|(-----BEGIN ((RSA|EC|OPENSSH) )?PRIVATE KEY-----)'
  PATTERN+='|((SUPABASE_SERVICE_ROLE|SERVICE_ROLE)_KEY[[:space:]]*[:=][[:space:]]*["'"'"']?eyJ)'
  PATTERN+='|((secret|token|apikey|api_key|password|passwd)[[:space:]]*[:=][[:space:]]*["'"'"'][A-Za-z0-9_\-]{12,}["'"'"'])'

  MATCHES=$(grep -RInE --exclude-dir='.git' --exclude-dir='node_modules' --exclude-dir='dist' --exclude-dir='.next' \
    "$PATTERN" "$TARGET" 2>/dev/null || true)

  if [ -n "$MATCHES" ]; then
    echo "🔴 Possíveis segredos encontrados (revisar manualmente, fallback tem falso-positivo):"
    echo "$MATCHES" | sed 's/^/   /'
    echo
    FOUND=1
  else
    echo "✅ Nenhum padrão óbvio encontrado pelo fallback."
    echo
  fi
fi

# --- 2b) nome secret-like em variável pública -----------------------------
# Roda sempre (não só no fallback): gitleaks/trufflehog não conhecem a convenção
# NEXT_PUBLIC_/VITE_/NUXT_PUBLIC_, e qualquer valor com esses prefixos vai para o
# bundle do browser por definição.
PUB_PAT='(NEXT_PUBLIC_|VITE_|NUXT_PUBLIC_|PUBLIC_)[A-Za-z0-9_]*(SECRET|SERVICE_ROLE|PRIVATE|PASSWORD|PASSWD|TOKEN|API_?KEY)[A-Za-z0-9_]*[[:space:]]*[:=][[:space:]]*["'"'"']?[^"'"'"'[:space:]]{8,}'
PUB_HITS=$(grep -RInE -i --exclude-dir='.git' --exclude-dir='node_modules' --exclude-dir='dist' --exclude-dir='.next' \
  "$PUB_PAT" "$TARGET" 2>/dev/null || true)

# Chaves públicas/anon são publicáveis por design; placeholders não são segredo.
if [ -n "$PUB_HITS" ]; then
  PUB_HITS=$(echo "$PUB_HITS" | grep -Eiv '(PUBLISHABLE|_ANON_KEY|_PUBLIC_KEY)[A-Za-z0-9_]*[[:space:]]*[:=]' || true)
fi
if [ -n "$PUB_HITS" ]; then
  PUB_HITS=$(echo "$PUB_HITS" | grep -Eiv '[:=][[:space:]]*["'"'"']?(your[-_]|example|changeme|change-me|placeholder|xxx|<|\$\{|\.\.\.)' || true)
fi

if [ -n "$PUB_HITS" ]; then
  echo "🔴 BLOQUEANTE — nome secret-like em variável pública (vai para o bundle do browser):"
  echo "$PUB_HITS" | sed 's/^/   /'
  echo
  FOUND=1
fi

# --- 3) checagem de .gitignore -------------------------------------------
GITIGNORE="$TARGET/.gitignore"
echo "-- checando .gitignore --"
if [ -f "$GITIGNORE" ]; then
  for pattern in '.env' '*.pem' '*.key'; do
    if ! grep -qF "$pattern" "$GITIGNORE"; then
      echo "🟠 IMPORTANTE — '.gitignore' não cobre '$pattern' explicitamente."
      FOUND=1
    fi
  done
else
  echo "🔴 BLOQUEANTE — não existe .gitignore em '$TARGET'."
  FOUND=1
fi
echo

if [ "$FOUND" -eq 0 ]; then
  echo "✅ Scan concluído sem achados."
fi

exit "$FOUND"
