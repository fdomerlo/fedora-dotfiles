#!/usr/bin/env bash
# scripts/setup_git.sh - Configura la identidad global de Git (user.name / user.email)
# de forma idempotente, sin datos personales versionados en el repositorio.
#
# Orden de resolución:
#   1. Valores ya presentes en la configuración global de Git (nunca se sobrescriben).
#   2. Variables de entorno GIT_USER_NAME / GIT_USER_EMAIL.
#   3. Pregunta interactiva (solo si hay una terminal disponible).
# Si no hay valores ni terminal, se informa y se continúa sin bloquear `make install`.
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "ERROR: Ejecutá este script como usuario normal (sin sudo)." >&2
  exit 1
fi

if ! command -v git &>/dev/null; then
  echo "ERROR: git no está instalado. Ejecutá 'make host' primero." >&2
  exit 1
fi

configure_key() {
  local key="$1" env_value="$2" prompt="$3"
  local current value=""

  current="$(git config --global --get "$key" 2>/dev/null || true)"
  if [[ -n "$current" ]]; then
    echo "==> git $key ya configurado: $current"
    return 0
  fi

  if [[ -n "$env_value" ]]; then
    value="$env_value"
  elif [[ -t 0 ]]; then
    read -r -p "    $prompt: " value
  fi

  if [[ -n "$value" ]]; then
    git config --global "$key" "$value"
    echo "==> git $key configurado: $value"
  else
    echo "ADVERTENCIA: git $key sin configurar. Definí GIT_USER_NAME/GIT_USER_EMAIL y ejecutá 'make gitconfig'." >&2
  fi
}

echo "==> Verificando identidad global de Git..."
configure_key user.name "${GIT_USER_NAME:-}" "Nombre para los commits (user.name)"
configure_key user.email "${GIT_USER_EMAIL:-}" "Email para los commits (user.email)"

# Valores predeterminados no personales, solo si no existen
if [[ -z "$(git config --global --get init.defaultBranch 2>/dev/null || true)" ]]; then
  git config --global init.defaultBranch main
  echo "==> git init.defaultBranch configurado: main"
fi
