#!/usr/bin/env bash
# scripts/tooling.sh - (Opcional) Editores y navegador. Se ejecuta con `make tooling`.
# Idempotente: solo configura repositorios e instala paquetes ausentes.
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "ERROR: Ejecutá este script como usuario normal (sin sudo)." >&2
  exit 1
fi

export PATH="$HOME/.local/bin:$PATH"

# 1. Visual Studio Code (repositorio oficial de Microsoft)
VSCODE_REPO="/etc/yum.repos.d/vscode.repo"
if [[ ! -f "$VSCODE_REPO" ]]; then
  echo "==> Configurando repositorio oficial de Visual Studio Code..."
  sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
  printf '%s\n' \
    "[code]" \
    "name=Visual Studio Code" \
    "baseurl=https://packages.microsoft.com/yumrepos/vscode" \
    "enabled=1" \
    "autorefresh=1" \
    "type=rpm-md" \
    "gpgcheck=1" \
    "gpgkey=https://packages.microsoft.com/keys/microsoft.asc" |
    sudo tee "$VSCODE_REPO" >/dev/null
else
  echo "==> Repositorio de Visual Studio Code ya configurado."
fi

if rpm -q code &>/dev/null; then
  echo "==> Visual Studio Code ya está instalado."
else
  echo "==> Instalando Visual Studio Code..."
  sudo dnf install -y code
fi

# 2. Google Chrome (repositorio oficial de Google)
#    Fedora Workstation trae el repo 'google-chrome' deshabilitado (fedora-workstation-repositories);
#    si no existe se crea, y en ambos casos se habilita solo para esta instalación.
CHROME_REPO="/etc/yum.repos.d/google-chrome.repo"
if rpm -q google-chrome-stable &>/dev/null; then
  echo "==> Google Chrome ya está instalado."
else
  if [[ ! -f "$CHROME_REPO" ]]; then
    echo "==> Configurando repositorio oficial de Google Chrome..."
    printf '%s\n' \
      "[google-chrome]" \
      "name=google-chrome" \
      "baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64" \
      "enabled=1" \
      "gpgcheck=1" \
      "gpgkey=https://dl.google.com/linux/linux_signing_key.pub" |
      sudo tee "$CHROME_REPO" >/dev/null
  fi
  echo "==> Instalando Google Chrome..."
  sudo dnf install -y --enablerepo=google-chrome google-chrome-stable
fi

# 3. Zed (instalador oficial, en ~/.local)
if command -v zed &>/dev/null || [[ -x "$HOME/.local/bin/zed" ]]; then
  echo "==> Zed ya está instalado."
else
  echo "==> Instalando Zed mediante el instalador oficial..."
  curl -fsSL https://zed.dev/install.sh | sh
fi

echo "==> Editores y navegador verificados y listos."
