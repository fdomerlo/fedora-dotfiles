#!/usr/bin/env bash
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }

# Nota: Fedora usa zram nativo, 
# esto se usa para evitar un eventual OOM
# ---------------------------------------

SWAPFILE="/swapfile"
SIZE="4G"   # ajustable según RAM

echo "==> Creating swapfile ($SIZE)"

if [ ! -f "$SWAPFILE" ]; then
  fallocate -l "$SIZE" "$SWAPFILE" || dd if=/dev/zero of="$SWAPFILE" bs=1M count=8192
  chmod 600 "$SWAPFILE"
  mkswap "$SWAPFILE"
else
  echo "Swapfile already exists"
fi

echo "==> Enabling swapfile"
swapon "$SWAPFILE" || true

if ! grep -q "$SWAPFILE" /etc/fstab; then
  echo "$SWAPFILE none swap defaults 0 0" >> /etc/fstab
fi

echo "==> Adjusting swappiness (favor zram first)"
sysctl vm.swappiness=10

if ! grep -q "vm.swappiness" /etc/sysctl.conf; then
  echo "vm.swappiness=10" >> /etc/sysctl.conf
fi

echo "==> Swap ready (zram still primary)"
