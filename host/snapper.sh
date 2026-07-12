#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }

# En Fedora, habilitar las cuotas de BTRFS degrada drásticamente 
# el rendimiento del sistema a medida que se acumulan snapshots. 
# Cada vez que Snapper borra un snapshot antiguo, BTRFS recalcula los árboles de cuotas, 
# provocando bloqueos temporales de E/S y picos masivos de CPU.
# --------------------------------------------------------------
# echo "==> Enabling BTRFS quota"
# btrfs quota enable / || true

echo "==> Configuring snapper (root)"

if [ ! -f /etc/snapper/configs/root ]; then
  snapper -c root create-config /
fi

snapper -c root set-config \
  TIMELINE_CREATE=yes \
  TIMELINE_LIMIT_HOURLY=5 \
  TIMELINE_LIMIT_DAILY=7 \
  TIMELINE_LIMIT_WEEKLY=4 \
  TIMELINE_LIMIT_MONTHLY=0 \
  NUMBER_CLEANUP=yes \
  NUMBER_LIMIT=50 \
  NUMBER_LIMIT_IMPORTANT=10

systemctl enable --now snapper-timeline.timer
systemctl enable --now snapper-cleanup.timer

echo "==> Snapper ready"
