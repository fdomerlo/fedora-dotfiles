#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "ERROR: Ejecutá este script como usuario normal (sin sudo)." >&2
  exit 1
fi

export PATH="$HOME/.local/bin:$HOME/.local/share/fnm:$PATH"

echo "==> Verificando e instalando gestores de toolchains (uv, fnm, SDKMAN)..."

if ! command -v curl &>/dev/null; then
  echo "==> Instalando dependencia requerida (curl)..."
  sudo dnf install -y curl
fi

# 1. uv (Python toolchain manager)
if command -v uv &>/dev/null || [[ -x "$HOME/.local/bin/uv" ]]; then
  echo "==> uv ya está instalado."
else
  echo "==> Instalando uv mediante el instalador oficial..."
  curl -LsSf https://astral.sh/uv/install.sh | env UV_NO_MODIFY_PATH=1 sh
fi

# 2. fnm (Fast Node Manager)
if command -v fnm &>/dev/null || [[ -x "$HOME/.local/share/fnm/fnm" ]]; then
  echo "==> fnm ya está instalado."
else
  if ! command -v unzip &>/dev/null; then
    echo "==> Instalando dependencia requerida para fnm (unzip)..."
    sudo dnf install -y unzip
  fi
  echo "==> Instalando fnm mediante el instalador oficial..."
  curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
fi

# 3. SDKMAN (Java / JVM toolchain manager)
if [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] || [[ -d "$HOME/.sdkman" ]]; then
  echo "==> SDKMAN ya está instalado en $HOME/.sdkman."
else
  if ! command -v unzip &>/dev/null || ! command -v zip &>/dev/null; then
    echo "==> Instalando dependencias requeridas para SDKMAN (zip, unzip)..."
    sudo dnf install -y zip unzip
  fi
  echo "==> Instalando SDKMAN mediante el instalador oficial..."
  export SDKMAN_DIR="$HOME/.sdkman"
  curl -fsSL "https://get.sdkman.io?rcupdate=false" | bash
fi

echo "==> Toolchains (uv, fnm, SDKMAN) verificados y listos."
