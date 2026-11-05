#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "ERROR: Ejecutá este script como usuario normal (sin sudo)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

OMZ_DIR="$HOME/.oh-my-zsh"
PLUGINS_DIR="${ZSH_CUSTOM:-$OMZ_DIR/custom}/plugins"
ZSHRC_SRC="$REPO_DIR/shell/zshrc"
ZSHRC_DST="$HOME/.zshrc"

# 1. Instalar Zsh únicamente si no está disponible
if ! command -v zsh &>/dev/null; then
  echo "==> Instalando Zsh..."
  sudo dnf install -y zsh
else
  echo "==> Zsh ya está instalado."
fi

# 2. Cambiar el shell predeterminado solo si es necesario
CURRENT_USER="${USER:-$(id -un)}"
CURRENT_SHELL="$(getent passwd "$CURRENT_USER" | cut -d: -f7)"
ZSH_PATH="$(command -v zsh)"

if [[ "$CURRENT_SHELL" != "$ZSH_PATH" ]]; then
  echo "==> Configurando Zsh como shell predeterminado para $CURRENT_USER..."
  if command -v chsh &>/dev/null; then
    sudo chsh -s "$ZSH_PATH" "$CURRENT_USER"
  else
    sudo usermod --shell "$ZSH_PATH" "$CURRENT_USER"
  fi
else
  echo "==> Zsh ya es el shell predeterminado ($ZSH_PATH)."
fi

# 3. Instalar Oh My Zsh de forma idempotente (sin sobrescribir ni actualizar)
if [[ ! -d "$OMZ_DIR" ]]; then
  echo "==> Instalando Oh My Zsh..."
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  echo "==> Oh My Zsh ya está instalado en $OMZ_DIR."
fi

# 4. Instalar plugins de Zsh de forma idempotente (sin git pull automático)
mkdir -p "$PLUGINS_DIR"

if [[ ! -d "$PLUGINS_DIR/zsh-autosuggestions" ]]; then
  echo "==> Instalando plugin zsh-autosuggestions..."
  git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions \
    "$PLUGINS_DIR/zsh-autosuggestions"
else
  echo "==> Plugin zsh-autosuggestions ya está instalado."
fi

if [[ ! -d "$PLUGINS_DIR/zsh-syntax-highlighting" ]]; then
  echo "==> Instalando plugin zsh-syntax-highlighting..."
  git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting \
    "$PLUGINS_DIR/zsh-syntax-highlighting"
else
  echo "==> Plugin zsh-syntax-highlighting ya está instalado."
fi

# 5. Enlazar ~/.zshrc al archivo versionado en el repositorio de forma idempotente
if [[ -L "$ZSHRC_DST" ]] && [[ "$(readlink -f "$ZSHRC_DST" 2>/dev/null || true)" == "$ZSHRC_SRC" ]]; then
  echo "==> $ZSHRC_DST ya apunta a $ZSHRC_SRC."
else
  if [[ -f "$ZSHRC_DST" && ! -L "$ZSHRC_DST" && ! -f "${ZSHRC_DST}.pre-dotfiles" ]]; then
    echo "==> Respaldando ~/.zshrc previo en ~/.zshrc.pre-dotfiles..."
    mv "$ZSHRC_DST" "${ZSHRC_DST}.pre-dotfiles"
  fi
  ln -sfn "$ZSHRC_SRC" "$ZSHRC_DST"
  echo "==> Enlace simbólico configurado: $ZSHRC_DST -> $ZSHRC_SRC"
fi

echo "==> Configuración de Zsh y Oh My Zsh completada."
