#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "ERROR: Ejecutá este script como usuario normal (sin sudo)." >&2
  exit 1
fi

MODE="${1:-check}"

# 1. Verificar que GitHub CLI (gh) esté instalado
if ! command -v gh &>/dev/null; then
  echo "==> Instalando GitHub CLI (gh) desde repositorios oficiales de Fedora..."
  sudo dnf install -y gh
else
  echo "==> GitHub CLI (gh) ya está instalado."
fi

# 2. Configurar protocolo Git preferido como SSH de forma idempotente
CURRENT_PROTO="$(gh config get git_protocol 2>/dev/null || true)"
if [[ "$CURRENT_PROTO" != "ssh" ]]; then
  echo "==> Configurando protocolo Git preferido en gh como SSH..."
  gh config set git_protocol ssh
else
  echo "==> Protocolo Git preferido en gh ya está configurado como SSH."
fi

# 3. Verificar estado de autenticación (o iniciar flujo interactivo en make github-auth)
if [[ "$MODE" == "--auth" || "$MODE" == "auth" ]]; then
  if gh auth status &>/dev/null; then
    echo "==> Sesión activa detectada en GitHub CLI:"
    gh auth status
  else
    echo "==> Iniciando flujo oficial interactivo de autenticación en GitHub CLI (SSH)..."
    gh auth login -h github.com -p ssh
  fi
else
  if gh auth status &>/dev/null; then
    echo "==> GitHub CLI: sesión autenticada activa."
  else
    echo "==> GitHub CLI preparado (protocolo SSH). Sesión aún no autenticada."
    echo "    Ejecutá 'make github-auth' cuando desees iniciar sesión interactivamente."
  fi
fi
