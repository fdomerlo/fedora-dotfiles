#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "ERROR: Ejecutá este script como usuario normal (sin sudo)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ZSHRC_REPO="$REPO_DIR/shell/zshrc"

export PATH="$HOME/.local/bin:$HOME/.opencode/bin:/usr/local/bin:$PATH"

# Resguardar shell/zshrc por si un instalador remoto intenta agregar rutas absolutas a ~/.zshrc
ZSHRC_SNAPSHOT="$(mktemp)"
cleanup() {
  rm -f "$ZSHRC_SNAPSHOT"
}
trap cleanup EXIT

if [[ -f "$ZSHRC_REPO" ]]; then
  cp "$ZSHRC_REPO" "$ZSHRC_SNAPSHOT"
fi

restore_zshrc_if_modified() {
  if [[ -f "$ZSHRC_REPO" ]] && ! cmp -s "$ZSHRC_SNAPSHOT" "$ZSHRC_REPO"; then
    cp "$ZSHRC_SNAPSHOT" "$ZSHRC_REPO"
  fi
}

# 1. OpenCode CLI
if command -v opencode &>/dev/null || [[ -x "$HOME/.opencode/bin/opencode" ]] || [[ -x "$HOME/.local/bin/opencode" ]]; then
  echo "==> OpenCode CLI ya está instalado."
else
  echo "==> Instalando OpenCode CLI mediante el instalador oficial..."
  curl -fsSL https://opencode.ai/v2/install | bash
  restore_zshrc_if_modified
fi

# 2. Antigravity CLI
if [[ -x "$HOME/.local/bin/antigravity" ]] || [[ -x "$HOME/.local/bin/agy" ]] || command -v agy &>/dev/null || command -v antigravity &>/dev/null; then
  echo "==> Antigravity CLI ya está instalado."
else
  echo "==> Instalando Antigravity CLI mediante el instalador oficial..."
  curl -fsSL https://antigravity.google/cli/install.sh | bash
  restore_zshrc_if_modified
fi

# 3. Antigravity Desktop (componente local opcional)
bash "$SCRIPT_DIR/setup_agy.sh"
