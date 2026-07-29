#!/usr/bin/env bash
set -euo pipefail

echo "==> Installing DevManagers (gh, uv, fnm, sdkman)..."

if ! command -v gh &> /dev/null; then
    echo "Instalando GitHub CLI (gh)..."
    sudo dnf install -y gh
fi

if ! command -v uv &> /dev/null && [ ! -f "$HOME/.local/bin/uv" ]; then
    echo "Instalando uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi

if ! command -v fnm &> /dev/null && [ ! -d "$HOME/.local/share/fnm" ]; then
    echo "Instalando fnm..."
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
fi

if [ ! -d "$HOME/.sdkman" ]; then
    echo "Instalando sdkman..."
    if ! command -v unzip &> /dev/null || ! command -v zip &> /dev/null; then
        echo "Instalando dependencias para sdkman (zip/unzip)..."
        sudo dnf install -y zip unzip
    fi
    export SDKMAN_DIR="$HOME/.sdkman"
    curl -s "https://get.sdkman.io" | bash

    # source "$SDKMAN_DIR/bin/sdkman-init.sh"
fi

echo "==> DevManagers ready"
