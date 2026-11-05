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

# Ejecuta un instalador remoto resguardando shell/zshrc solo cuando realmente se instala algo
run_with_zshrc_guard() {
  local snapshot=""
  if [[ -f "$ZSHRC_REPO" ]]; then
    snapshot="$(mktemp)"
    cp "$ZSHRC_REPO" "$snapshot"
  fi

  "$@"

  if [[ -n "$snapshot" ]]; then
    if [[ -f "$ZSHRC_REPO" ]] && ! cmp -s "$snapshot" "$ZSHRC_REPO"; then
      cp "$snapshot" "$ZSHRC_REPO"
    fi
    rm -f "$snapshot"
  fi
}

install_opencode() {
  curl -fsSL https://opencode.ai/v2/install | bash
}

install_antigravity_cli() {
  curl -fsSL https://antigravity.google/cli/install.sh | bash
}

# 1. OpenCode CLI
if command -v opencode &>/dev/null || [[ -x "$HOME/.opencode/bin/opencode" ]] || [[ -x "$HOME/.local/bin/opencode" ]]; then
  echo "==> OpenCode CLI ya está instalado."
else
  echo "==> Instalando OpenCode CLI mediante el instalador oficial..."
  run_with_zshrc_guard install_opencode
fi

# 2. Antigravity CLI
if [[ -x "$HOME/.local/bin/antigravity" ]] || [[ -x "$HOME/.local/bin/agy" ]] || command -v agy &>/dev/null || command -v antigravity &>/dev/null; then
  echo "==> Antigravity CLI ya está instalado."
else
  echo "==> Instalando Antigravity CLI mediante el instalador oficial..."
  run_with_zshrc_guard install_antigravity_cli
fi

# 3. Antigravity Desktop (componente local opcional)
bash "$SCRIPT_DIR/setup_agy.sh"
