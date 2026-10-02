#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }

TARGET_USER="${SUDO_USER:-$(logname)}"
USER_HOME=$(getent passwd "$TARGET_USER" | cut -d: -f6)

echo "==> Updating system"
dnf upgrade --refresh -y

echo "==> Installing base packages"
dnf install -y \
  git curl wget jq \
  fira-code-fonts google-noto-sans-vf-fonts zip unzip \
  gnome-shell-extension-dash-to-dock \
  podman podman-compose podman-docker \
  distrobox \
  btrfs-progs btrfs-assistant \
  snapper python3-dnf-plugin-snapper

echo "==> Mitigating CoW for Containers (Wear Leveling Protection)"
# Desactivar CoW antes de escribir datos (chattr +C solo afecta archivos nuevos)
mkdir -p /var/lib/containers
chattr +C /var/lib/containers || true

mkdir -p "$USER_HOME/.local/share/containers"
chattr +C "$USER_HOME/.local/share/containers" || true
chown -R "$TARGET_USER:$TARGET_USER" "$USER_HOME/.local"

echo "==> Enabling Rootless Podman Socket for $TARGET_USER"
loginctl enable-linger "$TARGET_USER"
sudo -u "$TARGET_USER" XDG_RUNTIME_DIR="/run/user/$(id -u "$TARGET_USER")" \
  systemctl --user enable --now podman.socket

echo "==> Setup completed"
