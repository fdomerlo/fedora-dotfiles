#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }

USER_NAME="${SUDO_USER:-$(logname)}"

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

echo "==> Enabling podman socket"
systemctl enable --now podman.socket

echo "==> Done"
