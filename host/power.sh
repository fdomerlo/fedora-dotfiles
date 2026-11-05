#!/usr/bin/env bash
# host/power.sh - Swapfile Btrfs, hibernación y ajustes de respuesta bajo presión.
#
# - Mantiene zRAM como swap L1 (prioridad 100) y agrega un swapfile en disco L2
#   (prioridad 10) para hibernar y absorber picos de memoria.
# - Calcula el tamaño del swapfile a partir de la RAM instalada; se puede forzar
#   con SWAP_GIB=<n>.
# - Usa el mecanismo de systemd/UEFI para recordar la ubicación de hibernación,
#   sin agregar resume=/resume_offset= al cmdline.
# - Ajusta swappiness, page-cluster y systemd-oomd para preservar respuesta.
#
# Se ejecuta con `make host` (o `make power`). No forma parte de `make snapper`.
set -euo pipefail

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

RESIZE_SWAP=0
FORCE_INITRAMFS=0
CHECK_ONLY=0

usage() {
  cat <<'EOF'
Uso: host/power.sh [opciones]

Opciones:
  --resize-swap      Recrea el swapfile si es más chico que el tamaño calculado.
  --force-initramfs  Regenera el initramfs aunque la configuración no haya cambiado.
  --check            Solo verifica el estado; no modifica el sistema.
  -h, --help         Muestra esta ayuda.
EOF
}

for arg in "$@"; do
  case "$arg" in
    --resize-swap) RESIZE_SWAP=1 ;;
    --force-initramfs) FORCE_INITRAMFS=1 ;;
    --check) CHECK_ONLY=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: opción desconocida: $arg" >&2; usage >&2; exit 1 ;;
  esac
done

ROOT_FS="$(findmnt -n -o FSTYPE -T / 2>/dev/null || echo unknown)"
if [[ "$ROOT_FS" != "btrfs" ]]; then
  echo "==> / está en '${ROOT_FS}', no en Btrfs. Swapfile/hibernación omitidos."
  exit 0
fi

if [[ ! -d /sys/firmware/efi ]]; then
  echo "ERROR: se requiere UEFI para el mecanismo de hibernación de systemd." >&2
  exit 1
fi

if ! grep -qw 'disk' /sys/power/state 2>/dev/null; then
  echo "ERROR: el kernel no soporta hibernación ('disk' ausente en /sys/power/state)." >&2
  exit 1
fi

if ! grep -Eq '\[?(platform|shutdown)\]?' /sys/power/disk 2>/dev/null; then
  echo "ERROR: /sys/power/disk no ofrece platform ni shutdown." >&2
  exit 1
fi

MEM_TOTAL_KB="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
if [[ -z "$MEM_TOTAL_KB" ]]; then
  echo "ERROR: no se pudo leer MemTotal de /proc/meminfo." >&2
  exit 1
fi
RAM_GIB="$(awk -v kb="$MEM_TOTAL_KB" 'BEGIN {printf "%.3f", kb / 1024 / 1024}')"

if [[ -n "${SWAP_GIB:-}" ]]; then
  if ! [[ "$SWAP_GIB" =~ ^[0-9]+$ ]] || (( SWAP_GIB < 1 )); then
    echo "ERROR: SWAP_GIB debe ser un entero positivo (recibido: ${SWAP_GIB})." >&2
    exit 1
  fi
else
  SWAP_GIB="$(
    awk -v kb="$MEM_TOTAL_KB" 'BEGIN {
      g = kb / 1024 / 1024;
      if (g >= 8) {
        base = g;
        extra = 1;
      } else if (g >= 2) {
        base = 1.5 * g;
        extra = 0;
      } else {
        base = 2 * g;
        extra = 0;
      }
      rounded = int(base);
      if (base > rounded) rounded++;
      target = rounded + extra;
      if (target < 1) target = 1;
      print target;
    }'
  )"
fi

DESIRED_BYTES=$(( SWAP_GIB * 1024 * 1024 * 1024 ))
ROOT_UUID="$(findmnt -n -o UUID -T / 2>/dev/null || true)"
ROOT_SOURCE="$(findmnt -n -o SOURCE -T / 2>/dev/null | sed 's/\[.*//' || true)"
if [[ -z "$ROOT_UUID" && -n "$ROOT_SOURCE" ]]; then
  ROOT_UUID="$(sudo blkid -s UUID -o value "$ROOT_SOURCE" 2>/dev/null || true)"
fi
if [[ -z "$ROOT_UUID" ]]; then
  echo "ERROR: no se pudo determinar el UUID del filesystem raíz." >&2
  exit 1
fi

SWAPFILE="/swap/swapfile"
SWAP_SUBVOL="swap"

echo "==> RAM detectada: ${RAM_GIB} GiB"
echo "==> Swapfile objetivo: ${SWAP_GIB} GiB (${DESIRED_BYTES} bytes)"

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
  TOP_MNT="$(mktemp -d /tmp/dotfiles-btrfs.XXXXXX)"
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

install_root_file() {
  local dest="$1"
  local mode="$2"
  local tmp
  tmp="$(mktemp)"

  cat > "$tmp"
  if sudo test -f "$dest" && sudo cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"
    return 1
  fi

  sudo install -D -m "$mode" "$tmp" "$dest"
  rm -f "$tmp"
  return 0
}

check_state() {
  local errors=0

  if swapon --show=NAME --noheadings 2>/dev/null | grep -Fxq "$SWAPFILE"; then
    local swap_size_kb swap_prio
    swap_size_kb="$(awk -v f="$SWAPFILE" '$1 == f {print $3}' /proc/swaps)"
    swap_prio="$(awk -v f="$SWAPFILE" '$1 == f {print $5}' /proc/swaps)"
    echo "    Swapfile activo: ${swap_size_kb} KiB, prioridad ${swap_prio}"
    if (( swap_size_kb < MEM_TOTAL_KB )); then
      echo "    ADVERTENCIA: el swapfile es menor que la RAM; la hibernación puede fallar." >&2
    fi
    if [[ "$swap_prio" != "10" ]]; then
      echo "    ADVERTENCIA: se esperaba prioridad 10 para el swapfile." >&2
    fi
  else
    echo "    ADVERTENCIA: ${SWAPFILE} no está activo." >&2
    errors=$((errors + 1))
  fi

  local image_size
  image_size="$(cat /sys/power/image_size 2>/dev/null || echo 0)"
  echo "    /sys/power/image_size: ${image_size} bytes"
  if (( image_size < MEM_TOTAL_KB * 1024 )); then
    echo "    ADVERTENCIA: image_size es menor que la RAM; revisá la hibernación." >&2
  fi

  if command -v lsinitrd &>/dev/null; then
    local initramfs="/boot/initramfs-$(uname -r).img"
    local -a lscmd=()

    if [[ -r "$initramfs" ]]; then
      lscmd=(lsinitrd)
    elif sudo -n test -r "$initramfs" 2>/dev/null; then
      lscmd=(sudo -n lsinitrd)
    fi

    if (( ${#lscmd[@]} == 0 )); then
      echo "    (initramfs no legible sin sudo; comprobación omitida)"
    else
      local initramfs_mods
      initramfs_mods="$("${lscmd[@]}" -m "$initramfs" 2>/dev/null || true)"
      if grep -qx 'resume' <<< "$initramfs_mods" && grep -qx 'overlayfs' <<< "$initramfs_mods"; then
        echo "    initramfs contiene los módulos resume y overlayfs"
      elif "${lscmd[@]}" "$initramfs" 2>/dev/null | grep -E 'overlayfs-lib\.sh|systemd-hibernate-resume' >/dev/null; then
        echo "    initramfs contiene overlayfs/resume"
      else
        echo "    ADVERTENCIA: no se encontraron overlayfs/resume en el initramfs." >&2
      fi
    fi
  fi

  return "$errors"
}

if (( CHECK_ONLY )); then
  echo "==> Verificación (--check) sin cambios..."
  check_state || true
  exit 0
fi

# 1. Subvolumen top-level 'swap' y punto de montaje /swap
echo "==> Asegurando subvolumen top-level '${SWAP_SUBVOL}'..."
mount_top
if sudo btrfs subvolume show "${TOP_MNT}/${SWAP_SUBVOL}" >/dev/null 2>&1; then
  echo "    Subvolumen '${SWAP_SUBVOL}' ya existe."
else
  sudo btrfs subvolume create "${TOP_MNT}/${SWAP_SUBVOL}"
  echo "    Subvolumen '${SWAP_SUBVOL}' creado."
fi
unmount_top

ensure_fstab_line \
  "UUID=${ROOT_UUID} /swap btrfs subvol=${SWAP_SUBVOL},noatime,compress=no 0 0" \
  "^[^#].*[[:space:]]/swap[[:space:]]+btrfs[[:space:]]+.*subvol=${SWAP_SUBVOL}(,|[[:space:]])"

sudo systemctl daemon-reload
sudo mkdir -p /swap
SWAP_MOUNT_UNIT="$(systemd-escape -p --suffix=mount /swap)"
if ! systemctl is-active --quiet "$SWAP_MOUNT_UNIT" 2>/dev/null; then
  sudo systemctl start "$SWAP_MOUNT_UNIT"
fi

# 2. Swapfile con tamaño derivado de la RAM
CURRENT_BYTES=0
if sudo test -e "$SWAPFILE"; then
  CURRENT_BYTES="$(sudo stat -c %s "$SWAPFILE")"
fi

CREATE_SWAPFILE=0
if (( CURRENT_BYTES == 0 )); then
  CREATE_SWAPFILE=1
elif (( CURRENT_BYTES < DESIRED_BYTES )); then
  if (( RESIZE_SWAP )); then
    echo "==> El swapfile actual es más chico que el objetivo; se recreará (--resize-swap)."
    if swapon --show=NAME --noheadings 2>/dev/null | grep -Fxq "$SWAPFILE"; then
      sudo swapoff "$SWAPFILE"
    fi
    CREATE_SWAPFILE=1
  else
    echo "ADVERTENCIA: ${SWAPFILE} mide $((CURRENT_BYTES / 1024 / 1024)) MiB y el objetivo es ${SWAP_GIB} GiB." >&2
    echo "           La hibernación puede fallar. Reejecutá con --resize-swap para recrearlo." >&2
  fi
elif (( CURRENT_BYTES > DESIRED_BYTES )); then
  echo "    El swapfile existente ya es mayor o igual al objetivo; se conserva."
fi

if (( CREATE_SWAPFILE )); then
  AVAIL_BYTES="$(df -B1 --output=avail /swap | tail -1 | tr -d ' ')"
  if (( AVAIL_BYTES < DESIRED_BYTES + 1073741824 )); then
    echo "ERROR: espacio insuficiente en /swap (disponible: ${AVAIL_BYTES} bytes, necesario: $((DESIRED_BYTES + 1073741824)))." >&2
    exit 1
  fi

  if swapon --show=NAME --noheadings 2>/dev/null | grep -Fxq "$SWAPFILE"; then
    sudo swapoff "$SWAPFILE"
  fi
  sudo rm -f "$SWAPFILE"
  echo "==> Creando swapfile de ${SWAP_GIB} GiB en ${SWAPFILE}..."
  sudo btrfs filesystem mkswapfile --size "${SWAP_GIB}g" --uuid clear "$SWAPFILE"
fi

sudo chmod 600 "$SWAPFILE"

# 3. Etiqueta SELinux: directorio buscable + archivo swapfile_t
if command -v semanage &>/dev/null; then
  # systemd-logind/systemd-sleep necesitan "search" sobre el directorio que
  # contiene el swapfile. Si el directorio queda unlabeled_t (o swapfile_t en
  # políticas con la regresión de Fedora 44/45), la hibernación falla con
  # "Access denied" incluso como root. Se etiqueta el directorio como var_t y
  # el archivo como swapfile_t.
  # Sin -q en los grep: deben consumir toda la salida para no provocar SIGPIPE
  # en semanage (pipefail lo convertiría en un falso negativo).
  if ! sudo semanage fcontext -l 2>/dev/null | grep -E '^/swap[[:space:]]' >/dev/null; then
    sudo semanage fcontext -a -t var_t "/swap"
    echo "    Regla SELinux agregada para /swap (var_t)."
  fi
  if ! sudo semanage fcontext -l 2>/dev/null | grep -F "$SWAPFILE" >/dev/null; then
    sudo semanage fcontext -a -t swapfile_t "$SWAPFILE"
    echo "    Regla SELinux agregada para ${SWAPFILE} (swapfile_t)."
  fi
  sudo restorecon -RF /swap
else
  echo "ADVERTENCIA: semanage no está disponible; no se pudo etiquetar el swapfile." >&2
fi

ensure_fstab_line \
  "${SWAPFILE} none swap defaults,pri=10 0 0" \
  "^[^#].*[[:space:]]${SWAPFILE}[[:space:]]+none[[:space:]]+swap[[:space:]]"

sudo systemctl daemon-reload
if ! swapon --show=NAME --noheadings 2>/dev/null | grep -Fxq "$SWAPFILE"; then
  sudo swapon -p 10 "$SWAPFILE"
fi

# 4. Módulos de dracut para reanudar desde swapfile y arrancar snapshots
DRACUT_CONF="/etc/dracut.conf.d/99-dotfiles-power.conf"
DRACUT_CHANGED=0
if install_root_file "$DRACUT_CONF" 0644 <<'EOF'
# Archivos de configuración gestionados por dotfiles (make host).
# resume: reanudar desde el swapfile usando la ubicación UEFI de systemd.
# overlayfs: permitir arrancar snapshots Btrfs read-only con una capa escribible en RAM.
add_dracutmodules+=" resume overlayfs "
EOF
then
  DRACUT_CHANGED=1
fi

if (( DRACUT_CHANGED || FORCE_INITRAMFS )); then
  echo "==> Regenerando initramfs (resume + overlayfs)..."
  sudo dracut -f --regenerate-all
else
  echo "    Configuración de dracut sin cambios."
fi

# 5. Respuesta bajo presión de memoria
SYSCTL_CONF="/etc/sysctl.d/99-dotfiles-zram.conf"
if install_root_file "$SYSCTL_CONF" 0644 <<'EOF'
# Archivos de configuración gestionados por dotfiles (make host).
# zRAM es L1 y el swapfile Btrfs es L2; favorecer el intercambio temprano.
vm.swappiness = 100
vm.page-cluster = 0
EOF
then
  echo "    sysctl actualizado: ${SYSCTL_CONF}"
fi
sudo sysctl --system >/dev/null

OOMD_CONF="/etc/systemd/oomd.conf.d/99-dotfiles.conf"
OOMD_CHANGED=0
if install_root_file "$OOMD_CONF" 0644 <<'EOF'
# Archivos de configuración gestionados por dotfiles (make host).
[OOM]
SwapUsedLimit=50%
DefaultMemoryPressureDurationSec=10s
EOF
then
  OOMD_CHANGED=1
fi

if systemctl is-enabled --quiet systemd-oomd 2>/dev/null; then
  if (( OOMD_CHANGED )) || ! systemctl is-active --quiet systemd-oomd 2>/dev/null; then
    sudo systemctl restart systemd-oomd
  fi
else
  echo "ADVERTENCIA: systemd-oomd no está habilitado; revisá el estado del servicio." >&2
fi

# 6. Límite de imagen de hibernación: el default (2/5 de RAM) puede ser insuficiente.
TMPFILES_CONF="/etc/tmpfiles.d/99-dotfiles-hibernation.conf"
if install_root_file "$TMPFILES_CONF" 0644 <<EOF
# Archivos de configuración gestionados por dotfiles (make host).
# Permite que la imagen de hibernación use todo el swapfile disponible.
w /sys/power/image_size - - - - ${DESIRED_BYTES}
EOF
then
  echo "    Límite de imagen de hibernación actualizado."
fi

# Aplicar ya mismo (sin depender de que systemd-tmpfiles tenga permiso sobre sysfs).
echo "$DESIRED_BYTES" | sudo tee /sys/power/image_size >/dev/null
sudo systemd-tmpfiles --create "$TMPFILES_CONF" >/dev/null 2>&1 || true

# 7. Hook de hibernación: liberar FUSE de GVFS antes de congelar procesos
# Los montajes GVFS (SFTP, SMB, etc.) pueden dejar hilos en estado D esperando
# una respuesta FUSE; el freezer del kernel no puede congelarlos y la
# hibernación falla con "Device or resource busy". Detener GVFS antes de
# hibernar libera esas peticiones. Los montajes se pueden reabrir al volver.
SLEEP_HOOK="/etc/systemd/system-sleep/50-dotfiles-gvfs"
if install_root_file "$SLEEP_HOOK" 0755 <<'EOF'
#!/usr/bin/env bash
# Instalado por dotfiles (make power). Libera FUSE de GVFS antes de hibernar.
set -u

phase="${1:-}"
operation="${2:-}"

case "$phase:$operation" in
  pre:hibernate|pre:hybrid-sleep) ;;
  post:hibernate|post:hybrid-sleep) ;;
  *) exit 0 ;;
esac

for runtime in /run/user/[0-9]*; do
  [[ -d "$runtime" ]] || continue
  uid="${runtime##*/}"
  user="$(getent passwd "$uid" 2>/dev/null | cut -d: -f1)"
  [[ -n "$user" ]] || continue

  if [[ "$phase" == "pre" ]]; then
    # findmnt lee /proc/self/mountinfo; no hacer stat sobre el mountpoint FUSE
    # porque podría bloquearse si el backend está colgado.
    findmnt -rn "$runtime/gvfs" >/dev/null 2>&1 || continue
    if [[ -x /usr/sbin/runuser ]]; then
      /usr/bin/timeout 15 /usr/sbin/runuser -u "$user" -- env XDG_RUNTIME_DIR="$runtime" \
        systemctl --user stop gvfs-daemon.service 2>/dev/null || \
      /usr/bin/timeout 5 /usr/sbin/runuser -u "$user" -- env XDG_RUNTIME_DIR="$runtime" \
        systemctl --user kill --signal=SIGKILL gvfs-daemon.service 2>/dev/null || true
    fi
    for fm in fusermount3 fusermount; do
      if command -v "$fm" >/dev/null 2>&1; then
        "$fm" -uz "$runtime/gvfs" 2>/dev/null || true
        break
      fi
    done
  else
    # Al volver, reactivar GVFS; los montajes se reabren desde las apps.
    if [[ -x /usr/sbin/runuser ]]; then
      /usr/sbin/runuser -u "$user" -- env XDG_RUNTIME_DIR="$runtime" \
        systemctl --user start gvfs-daemon.service 2>/dev/null || true
    fi
  fi
done

exit 0
EOF
then
  echo "    Hook de hibernación instalado: ${SLEEP_HOOK}"
fi

echo ""
echo "==> Estado final:"
check_state || true
echo ""
echo "==> Swap y hibernación configurados."
echo "    Probá la hibernación con: sudo systemctl hibernate"
echo "    Luego verificá: journalctl -b -u systemd-hibernate.service"
