#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }

echo "==> Configuring Snapper for / (root)"

if [ ! -f /etc/snapper/configs/root ]; then
  snapper -c root create-config /
fi

# Cuotas BTRFS deshabilitadas deliberadamente para evitar I/O stalls
btrfs quota disable / 2>/dev/null || true

# Políticas conservadoras para no ahogar SSDs chicos
snapper -c root set-config \
  TIMELINE_CREATE=yes \
  TIMELINE_LIMIT_HOURLY=3 \
  TIMELINE_LIMIT_DAILY=3 \
  TIMELINE_LIMIT_WEEKLY=1 \
  TIMELINE_LIMIT_MONTHLY=0 \
  NUMBER_CLEANUP=yes \
  NUMBER_LIMIT=6 \
  NUMBER_LIMIT_IMPORTANT=2

systemctl enable --now snapper-timeline.timer
systemctl enable --now snapper-cleanup.timer

echo "==> Snapper configured safely"
