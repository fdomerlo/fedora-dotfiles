#!/bin/bash
set -e

REPO_URL="https://github.com/fdomerlo/fedora-dotfiles.git"
TARGET_DIR="$HOME/.dotfiles"

echo "==> Asegurando que 'git' esté instalado..."
sudo dnf curl git make -y

echo "==> Clonando el repositorio de configuración..."
rm -rf "$TARGET_DIR"
git clone "$REPO_URL" "$TARGET_DIR"
cd "$TARGET_DIR"

echo "==> Ejecutando el script de post-instalación..."
make help
