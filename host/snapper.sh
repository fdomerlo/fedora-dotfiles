#!/usr/bin/env bash
# host/snapper.sh - Snapshots Btrfs de / con Snapper, retención conservadora,
# integración con DNF5/DNF4 y arranque de snapshots desde GRUB con grub-btrfs.
#
# Layout:
#   - Subvolumen top-level 'snapshots' montado en /.snapshots.
#   - Subvolumen top-level 'swap' (creado por host/power.sh) montado en /swap.
#   De este modo, un reemplazo del subvolumen 'root' no afecta snapshots ni swap.
#
# Se ejecuta con `make snapper`; no forma parte de `make install`.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ $EUID -eq 0 ]]; then
  echo "ERROR: Ejecutá este script como usuario normal (sin sudo)." >&2
  echo "       El script solicitará privilegios con sudo cuando sea necesario." >&2
  exit 1
fi

if [[ -r /etc/os-release ]]; then
  # shellcheck source=/dev/null
  source /etc/os-release
  if [[ "${ID:-}" != "fedora" ]]; then
    echo "ERROR: Este script está diseñado para Fedora (detectado: ${ID:-desconocido})." >&2
    exit 1
  fi
fi

ROOT_FS="$(findmnt -n -o FSTYPE -T / 2>/dev/null || echo unknown)"
if [[ "$ROOT_FS" != "btrfs" ]]; then
  echo "==> / está en '${ROOT_FS}', no en Btrfs. Snapper omitido."
  exit 0
fi

ROOT_UUID="$(findmnt -n -o UUID -T / 2>/dev/null || true)"
ROOT_SOURCE="$(findmnt -n -o SOURCE -T / 2>/dev/null | sed 's/\[.*//' || true)"
if [[ -z "$ROOT_UUID" && -n "$ROOT_SOURCE" ]]; then
  ROOT_UUID="$(sudo blkid -s UUID -o value "$ROOT_SOURCE" 2>/dev/null || true)"
fi
if [[ -z "$ROOT_UUID" ]]; then
  echo "ERROR: no se pudo determinar el UUID del filesystem raíz." >&2
  exit 1
fi

# 1. Dependencias de Snapper y DNF
IS_DNF5=0
if command -v dnf5 &>/dev/null || dnf --version 2>/dev/null | grep 'dnf5' >/dev/null; then
  IS_DNF5=1
fi

REQUIRED_PACKAGES=(snapper btrfs-progs)
if [[ $IS_DNF5 -eq 1 ]]; then
  REQUIRED_PACKAGES+=(libdnf5-plugin-actions)
else
  REQUIRED_PACKAGES+=(python3-dnf-plugin-snapper)
fi

MISSING_PACKAGES=()
for pkg in "${REQUIRED_PACKAGES[@]}"; do
  rpm -q "$pkg" &>/dev/null || MISSING_PACKAGES+=("$pkg")
done

if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
  echo "==> Instalando paquetes faltantes: ${MISSING_PACKAGES[*]}"
  sudo dnf install -y "${MISSING_PACKAGES[@]}"
else
  echo "==> Paquetes de Snapper y plugin de DNF ya instalados."
fi

# 2. grub-btrfs desde COPR (paquete noarch; el build de Fedora 45 es oldstable
#    pero suficiente: el parámetro de overlayfs se agrega por configuración).
if ! rpm -q grub-btrfs &>/dev/null; then
  echo "==> Instalando grub-btrfs desde COPR kylegospo/grub-btrfs..."
  if ! dnf copr --help &>/dev/null; then
    if command -v dnf5 &>/dev/null; then
      sudo dnf install -y dnf5-plugins
    else
      sudo dnf install -y dnf-plugins-core
    fi
  fi
  sudo dnf -y copr enable kylegospo/grub-btrfs
  sudo dnf install -y grub-btrfs
else
  echo "==> grub-btrfs ya está instalado."
fi

# 3. Configuración inicial de Snapper (crea .snapshots anidado; se migra abajo)
if ! sudo test -f /etc/snapper/configs/root; then
  # Si quedó un /.snapshots como directorio vacío de un intento previo,
  # Snapper no puede crear el subvolumen. Se elimina solo si está vacío.
  if [[ -e /.snapshots ]] && ! sudo btrfs subvolume show /.snapshots >/dev/null 2>&1; then
    if [[ -d /.snapshots && -z "$(sudo ls -A /.snapshots)" ]]; then
      sudo rmdir /.snapshots
    else
      echo "ERROR: /.snapshots existe, no es un subvolumen y no está vacío." >&2
      echo "       Movelo o vacialo antes de ejecutar 'make snapper'." >&2
      exit 1
    fi
  fi

  echo "==> Creando configuración de Snapper 'root' para /..."
  sudo snapper -c root create-config /
else
  echo "==> La configuración de Snapper 'root' ya existe."
fi

# 4. Detener timers y desmontar /.snapshots antes de mover subvolúmenes
for timer in snapper-timeline.timer snapper-cleanup.timer; do
  if systemctl is-active --quiet "$timer" 2>/dev/null; then
    sudo systemctl stop "$timer"
  fi
done

if findmnt -rn /.snapshots >/dev/null 2>&1; then
  sudo umount /.snapshots
fi

# 5. Migrar /.snapshots anidado a un subvolumen top-level
TOP_MNT=""
cleanup_top() {
  if [[ -n "$TOP_MNT" && -d "$TOP_MNT" ]]; then
    sudo umount "$TOP_MNT" 2>/dev/null || true
    sudo rmdir "$TOP_MNT" 2>/dev/null || true
  fi
}
trap cleanup_top EXIT

mount_top() {
  if [[ -n "$TOP_MNT" ]]; then
    return 0
  fi
  TOP_MNT="$(mktemp -d /tmp/dotfiles-snapper.XXXXXX)"
  sudo mount -o subvolid=5 "/dev/disk/by-uuid/${ROOT_UUID}" "$TOP_MNT"
}

unmount_top() {
  if [[ -n "$TOP_MNT" ]]; then
    sudo umount "$TOP_MNT"
    sudo rmdir "$TOP_MNT"
    TOP_MNT=""
  fi
}

ensure_fstab_line() {
  local line="$1"
  local regex="$2"

  if sudo grep -qE "$regex" /etc/fstab; then
    return 0
  fi

  if [[ ! -f /etc/fstab.bak.dotfiles ]]; then
    sudo cp -a /etc/fstab /etc/fstab.bak.dotfiles
    echo "    Respaldo de fstab: /etc/fstab.bak.dotfiles"
  fi
  printf '%s\n' "$line" | sudo tee -a /etc/fstab >/dev/null
  echo "    fstab actualizado: $line"
}

mount_top
NESTED_SNAPSHOTS="${TOP_MNT}/root/.snapshots"
TOP_SNAPSHOTS="${TOP_MNT}/snapshots"

if sudo btrfs subvolume show "$NESTED_SNAPSHOTS" >/dev/null 2>&1; then
  if sudo btrfs subvolume show "$TOP_SNAPSHOTS" >/dev/null 2>&1; then
    if [[ -z "$(sudo ls -A "$TOP_SNAPSHOTS")" ]]; then
      sudo btrfs subvolume delete "$TOP_SNAPSHOTS"
    else
      echo "ERROR: existen a la vez 'root/.snapshots' y el subvolumen top-level 'snapshots' con datos." >&2
      echo "       Resolvé el conflicto manualmente antes de continuar." >&2
      exit 1
    fi
  elif sudo test -e "$TOP_SNAPSHOTS"; then
    echo "ERROR: '${TOP_SNAPSHOTS}' existe y no es un subvolumen Btrfs." >&2
    exit 1
  fi

  echo "==> Migrando 'root/.snapshots' a subvolumen top-level 'snapshots'..."
  sudo mv "$NESTED_SNAPSHOTS" "$TOP_SNAPSHOTS"
  sudo mkdir -p "${TOP_MNT}/root/.snapshots"
elif sudo btrfs subvolume show "$TOP_SNAPSHOTS" >/dev/null 2>&1; then
  echo "==> El subvolumen top-level 'snapshots' ya existe."
  sudo mkdir -p "${TOP_MNT}/root/.snapshots"
elif sudo test -e "$TOP_SNAPSHOTS"; then
  echo "ERROR: '${TOP_SNAPSHOTS}' existe y no es un subvolumen Btrfs." >&2
  exit 1
else
  echo "==> Creando subvolumen top-level 'snapshots'..."
  sudo btrfs subvolume create "$TOP_SNAPSHOTS"
  sudo mkdir -p "${TOP_MNT}/root/.snapshots"
fi
unmount_top

# 6. Montar /.snapshots desde el subvolumen top-level
ensure_fstab_line \
  "UUID=${ROOT_UUID} /.snapshots btrfs subvol=snapshots,noatime 0 0" \
  "^[^#].*[[:space:]]/\.snapshots[[:space:]]+btrfs[[:space:]]+.*subvol=snapshots(,|[[:space:]])"

sudo mkdir -p /.snapshots
sudo systemctl daemon-reload
SNAP_MOUNT_UNIT="$(systemd-escape -p --suffix=mount /.snapshots)"
if ! systemctl is-active --quiet "$SNAP_MOUNT_UNIT" 2>/dev/null; then
  sudo systemctl start "$SNAP_MOUNT_UNIT"
fi

SNAP_MNT_OPTS="$(findmnt -n -o OPTIONS /.snapshots 2>/dev/null || true)"
if [[ "$SNAP_MNT_OPTS" != *"subvol=/snapshots"* && "$SNAP_MNT_OPTS" != *"subvol=snapshots"* ]]; then
  echo "ADVERTENCIA: /.snapshots no parece montado desde el subvolumen 'snapshots'." >&2
  echo "             Opciones actuales: ${SNAP_MNT_OPTS:-ninguna}" >&2
fi

# 7. Políticas de retención (solo se escriben si difieren)
declare -A DESIRED=(
  [TIMELINE_CREATE]=yes
  [TIMELINE_CLEANUP]=yes
  [TIMELINE_LIMIT_HOURLY]=3
  [TIMELINE_LIMIT_DAILY]=3
  [TIMELINE_LIMIT_WEEKLY]=1
  [TIMELINE_LIMIT_MONTHLY]=0
  [TIMELINE_LIMIT_YEARLY]=0
  [NUMBER_CLEANUP]=yes
  [NUMBER_LIMIT]=10
  [NUMBER_LIMIT_IMPORTANT]=2
  [EMPTY_PRE_POST_CLEANUP]=yes
  [BACKGROUND_COMPARISON]=no
)

CHANGES=()
SNAPPER_CONFIG_FILE="/etc/snapper/configs/root"
for key in "${!DESIRED[@]}"; do
  # El archivo de configuración usa líneas KEY="VALUE"; parsearlo es más
  # estable que depender del formato de tabla de `snapper get-config`.
  current="$(sudo awk -F= -v k="$key" '$1 == k {v = $2; gsub(/"/, "", v); print v}' "$SNAPPER_CONFIG_FILE" 2>/dev/null || true)"
  if [[ "$current" != "${DESIRED[$key]}" ]]; then
    CHANGES+=("$key=${DESIRED[$key]}")
  fi
done

if [[ ${#CHANGES[@]} -gt 0 ]]; then
  echo "==> Aplicando políticas de retención: ${CHANGES[*]}"
  sudo snapper -c root set-config "${CHANGES[@]}"
else
  echo "==> Políticas de retención de Snapper ya aplicadas."
fi

# 8. Snapshots automáticos pre/post transacción de DNF (DNF5 y DNF4)
if [[ $IS_DNF5 -eq 1 ]]; then
  ACTIONS_DIR="/etc/dnf/libdnf5-plugins/actions.d"
  ACTIONS_FILE="$ACTIONS_DIR/snapper.actions"
  EXPECTED_ACTIONS='# Snapshots automáticos pre/post transacción de DNF5 con Snapper (config root)
# Se asigna el algoritmo de limpieza "number" (-c number) para que NUMBER_LIMIT los depure.
pre_transaction::::/usr/bin/sh -c echo\ "tmp.cmd=$(ps\ -o\ command\ --no-headers\ -p\ '\''${pid}'\'')"
pre_transaction::::/usr/bin/sh -c echo\ "tmp.snapper_pre_number=$(snapper\ -c\ root\ create\ -c\ number\ -t\ pre\ -p\ -d\ '\''${tmp.cmd}'\'')"
post_transaction::::/usr/bin/sh -c [\ -n\ "${tmp.snapper_pre_number}"\ ]\ &&\ snapper\ -c\ root\ create\ -c\ number\ -t\ post\ --pre-number\ "${tmp.snapper_pre_number}"\ -d\ "${tmp.cmd}"\ ;\ echo\ tmp.snapper_pre_number\ ;\ echo\ tmp.cmd'

  if sudo test -f "$ACTIONS_FILE" && [[ "$(sudo cat "$ACTIONS_FILE" 2>/dev/null || true)" == "$EXPECTED_ACTIONS" ]]; then
    echo "==> Integración DNF5 + Snapper ya configurada en $ACTIONS_FILE."
  else
    echo "==> Configurando snapshots pre/post transacción de DNF5 en $ACTIONS_FILE..."
    sudo mkdir -p "$ACTIONS_DIR"
    printf '%s\n' "$EXPECTED_ACTIONS" | sudo tee "$ACTIONS_FILE" >/dev/null
    sudo chmod 0644 "$ACTIONS_FILE"
  fi
else
  echo "==> Integración DNF4 + Snapper activa mediante python3-dnf-plugin-snapper."
fi

# 9. Baseline importante (solo una vez)
if sudo snapper --csvout --no-headers -c root list --columns description 2>/dev/null | grep -Fx 'baseline dotfiles' >/dev/null; then
  echo "==> El snapshot baseline ya existe."
else
  echo "==> Creando snapshot baseline marcado como importante..."
  sudo snapper -c root create \
    --cleanup-algorithm number \
    --description "baseline dotfiles" \
    --userdata important=yes
fi

# 10. grub-btrfs: overlayfs solo para las entradas de snapshot
GRUB_BTRFS_CONFIG="/etc/default/grub-btrfs/config"
if sudo test -f "$GRUB_BTRFS_CONFIG"; then
  if ! sudo grep -q 'rd.live.overlay.overlayfs=1' "$GRUB_BTRFS_CONFIG"; then
    # El script 41_snapshots-btrfs lee este archivo antes que /etc/default/grub.
    # Fedora no define GRUB_CMDLINE_LINUX_DEFAULT, así que el parámetro no afecta
    # el arranque normal, solo las entradas de snapshot.
    {
      echo ""
      echo "# Archivos de configuración gestionados por dotfiles (make snapper)."
      echo "# Capa overlayfs en RAM para arrancar snapshots Btrfs read-only."
      echo 'GRUB_CMDLINE_LINUX_DEFAULT="rd.live.overlay.overlayfs=1"'
    } | sudo tee -a "$GRUB_BTRFS_CONFIG" >/dev/null
    echo "==> Parámetro overlayfs agregado a ${GRUB_BTRFS_CONFIG}."
  fi

  if ! sudo grep -q '^GRUB_BTRFS_LIMIT=' "$GRUB_BTRFS_CONFIG"; then
    echo 'GRUB_BTRFS_LIMIT="10"' | sudo tee -a "$GRUB_BTRFS_CONFIG" >/dev/null
  fi
else
  echo "ADVERTENCIA: no existe ${GRUB_BTRFS_CONFIG}; revisá la instalación de grub-btrfs." >&2
fi

echo "==> Regenerando /boot/grub2/grub.cfg con las entradas de snapshot..."
sudo grub2-mkconfig -o /boot/grub2/grub.cfg

# El monitor se habilita después de regenerar, para no competir por
# grub-btrfs.cfg mientras corre grub2-mkconfig.
if systemctl is-enabled --quiet grub-btrfs.path 2>/dev/null; then
  echo "==> grub-btrfs.path ya está habilitado."
  if ! systemctl is-active --quiet grub-btrfs.path 2>/dev/null; then
    sudo systemctl start grub-btrfs.path
  fi
else
  echo "==> Habilitando grub-btrfs.path..."
  sudo systemctl enable --now grub-btrfs.path
fi

if sudo test -s /boot/grub2/grub-btrfs.cfg; then
  if sudo grep -q 'rd.live.overlay.overlayfs=1' /boot/grub2/grub-btrfs.cfg &&
     sudo grep -q 'subvol=.*snapshots/' /boot/grub2/grub-btrfs.cfg; then
    echo "==> Entradas de snapshot generadas con overlayfs y subvolumen top-level."
  else
    echo "ADVERTENCIA: grub-btrfs.cfg no contiene los parámetros esperados." >&2
  fi
else
  echo "ADVERTENCIA: /boot/grub2/grub-btrfs.cfg no existe o está vacío." >&2
fi

# 11. Helper de rollback permanente
if [[ -f "${REPO_DIR}/host/snapper-rollback.sh" ]]; then
  sudo install -D -m 0755 "${REPO_DIR}/host/snapper-rollback.sh" /usr/local/sbin/snapper-rollback
  echo "==> Helper instalado: /usr/local/sbin/snapper-rollback"
else
  echo "ADVERTENCIA: no se encontró host/snapper-rollback.sh; helper no instalado." >&2
fi

# 12. Habilitar timers de timeline y limpieza
for timer in snapper-timeline.timer snapper-cleanup.timer; do
  if systemctl is-enabled --quiet "$timer" 2>/dev/null && systemctl is-active --quiet "$timer" 2>/dev/null; then
    echo "==> $timer ya está habilitado."
  else
    echo "==> Habilitando $timer..."
    sudo systemctl enable --now "$timer"
  fi
done

echo ""
echo "==> Snapper, grub-btrfs y rollback configurados."
echo "    Listar snapshots:      sudo snapper -c root list"
echo "    Ver rollback:          sudo snapper-rollback --list"
echo "    Próximo reinicio:      elegí 'Fedora snapshots' en GRUB para arrancar un snapshot."
