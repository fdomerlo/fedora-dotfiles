#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }

# El swapfile de disco debe usarse como respaldo (fallback) con menor prioridad que zRAM
SWAP_DIR="/var/swap"
SWAPFILE="$SWAP_DIR/swapfile"
SIZE="4G"

echo "==> Setting up dedicated Non-CoW subvolume for swap"
if [ ! -d "$SWAP_DIR" ]; then
  btrfs subvolume create "$SWAP_DIR"
  chattr +C "$SWAP_DIR"
fi

if [ ! -f "$SWAPFILE" ]; then
  echo "==> Creating BTRFS swapfile ($SIZE)"
  btrfs filesystem mkswapfile --size "$SIZE" "$SWAPFILE"
fi

echo "==> Configuring swap entry in /etc/fstab with lower priority than zRAM"
# zRAM tiene prioridad ~100/32767 por defecto; asignamos prioridad 10 al swap en disco
if ! grep -q "$SWAPFILE" /etc/fstab; then
  echo "$SWAPFILE none swap defaults,pri=10 0 0" >> /etc/fstab
fi

swapon -a

echo "==> Setting swappiness to favor zRAM aggressive caching"
cat <<EOF > /etc/sysctl.d/99-zram-priority.conf
vm.swappiness=150
vm.page-cluster=0
EOF
sysctl --system > /dev/null

echo "==> Swap ready: zRAM acts as L1, Disk Swapfile acts as L2 fallback"
