#!/usr/bin/env bash
set -euo pipefail

OMZ_DIR="$HOME/.oh-my-zsh"
PLUGINS_DIR="$OMZ_DIR/custom/plugins"

# 1. Verificar e instalar Zsh si no existe
if ! rpm -q zsh &>/dev/null; then
  echo "==> Installing Zsh..."
  sudo dnf install -y zsh
else
  echo "==> Zsh is already installed"
fi

# 2. Cambiar el shell por defecto al usuario actual si no es Zsh
CURRENT_SHELL=$(getent passwd "$USER" | cut -d: -f7)
ZSH_PATH=$(command -v zsh)

if [ "$CURRENT_SHELL" != "$ZSH_PATH" ]; then
  echo "==> Changing default shell to Zsh..."
  sudo chsh -s "$ZSH_PATH" "$USER"
else
  echo "==> Zsh is already the default shell"
fi

# 3. Instalar Oh My Zsh de forma desatendida
if [ ! -d "$OMZ_DIR" ]; then
  echo "==> Installing Oh My Zsh..."
  RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  echo "==> Oh My Zsh is already installed"
fi

# 4. Instalar plugins de forma idempotente (sin romper por carpetas existentes)
mkdir -p "$PLUGINS_DIR"

if [ ! -d "$PLUGINS_DIR/zsh-autosuggestions" ]; then
  echo "==> Cloning zsh-autosuggestions..."
  git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions "$PLUGINS_DIR/zsh-autosuggestions"
fi

if [ ! -d "$PLUGINS_DIR/zsh-syntax-highlighting" ]; then
  echo "==> Cloning zsh-syntax-highlighting..."
  git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting "$PLUGINS_DIR/zsh-syntax-highlighting"
fi

echo "✅ Oh My Zsh environment configuration completed"
