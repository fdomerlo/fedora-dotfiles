#!/usr/bin/env bash
set -euo pipefail

if [ ! -f "/etc/yum.repos.d/vscode.repo" ]; then
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc && \
    echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
else
    echo "==> vscode.repo already configured"
fi

sudo dnf check-update || true

sudo dnf install -y code

if ! command -v zed &> /dev/null; then
    curl -f https://zed.dev/install.sh | sh
else
    echo "==> zed is already installed"
fi

sudo dnf install -y google-chrome-stable
