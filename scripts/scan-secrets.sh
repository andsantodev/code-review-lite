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
  PATTERN+='|(-----BEGIN (RSA |EC |OPENSSH |)PRIVATE KEY-----)'
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
