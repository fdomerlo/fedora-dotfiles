#!/usr/bin/env bash
# host/snapper-rollback.sh - Rollback permanente a un snapshot de Snapper.
#
# Fedora arranca con rootflags=subvol=root, por lo que `snapper rollback` no
# cambia el subvolumen real. Este helper:
#   1. Crea un subvolumen escribible 'root.new' a partir del snapshot elegido.
#   2. Conserva del root actual la configuración crítica (fstab, cuentas, SSH,
#      machine-id, configuración de Snapper y de hibernación).
#   3. Renombra el root actual a 'root.broken-<timestamp>'.
#   4. Renombra 'root.new' a 'root'.
#
# Se instala como /usr/local/sbin/snapper-rollback con `make snapper`.
# Recomendado: ejecutarlo desde un snapshot arrancado por GRUB. También sirve
# desde un live USB si se monta el filesystem Btrfs raíz.
set -euo pipefail

TOP_MNT=""
DRY_RUN=0
FORCE=0
ASSUME_YES=0
ACTION=""
SNAP_ID=""

usage() {
  cat <<'EOF'
Uso: snapper-rollback --list
     snapper-rollback --commit <id> [--dry-run] [--force]
     snapper-rollback --cleanup [--yes]

Opciones:
  --list          Lista snapshots disponibles y roots rotos.
  --commit <id>   Reemplaza el subvolumen root por el snapshot <id>.
  --dry-run       Muestra lo que haría --commit sin ejecutar cambios.
  --cleanup       Elimina subvolúmenes root.broken-* antiguos.
  --yes           No pregunta confirmación en --cleanup.
  --force         Permite ejecutar --commit desde el root normal.
  -h, --help      Muestra esta ayuda.

Notas:
  - El root anterior se conserva como root.broken-<timestamp>.
  - El snapshot elegido no se modifica; se clona en root.new.
  - Después de --commit hay que reiniciar.
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }
info() { echo "==> $*"; }
warn() { echo "ADVERTENCIA: $*" >&2; }

cleanup_top() {
  if [[ -n "$TOP_MNT" && -d "$TOP_MNT" ]]; then
    umount "$TOP_MNT" 2>/dev/null || true
    rmdir "$TOP_MNT" 2>/dev/null || true
  fi
}
trap cleanup_top EXIT

run() {
  if (( DRY_RUN )); then
    printf '  [dry-run]'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

detect_root_dev() {
  local target src opts

  src="$(findmnt -n -o SOURCE -T / 2>/dev/null | sed 's/\[.*//' || true)"
  if [[ -n "$src" && -b "$src" ]] && blkid -s TYPE -o value "$src" 2>/dev/null | grep -qx btrfs; then
    printf '%s\n' "$src"
    return 0
  fi

  while read -r target src opts; do
    src="${src%%[*}"
    [[ -b "$src" ]] || continue
    blkid -s TYPE -o value "$src" 2>/dev/null | grep -qx btrfs || continue
    if [[ "$target" == "/" || "$opts" == *"subvol=/root"* || "$opts" == *"subvol=/snapshots/"* ]]; then
      printf '%s\n' "$src"
      return 0
    fi
  done < <(findmnt -rn -t btrfs -o TARGET,SOURCE,OPTIONS 2>/dev/null)

  # Último recurso (por ejemplo, desde un live USB con el filesystem montado
  # en otro punto): usar el primer dispositivo Btrfs disponible.
  while read -r target src opts; do
    src="${src%%[*}"
    [[ -b "$src" ]] || continue
    blkid -s TYPE -o value "$src" 2>/dev/null | grep -qx btrfs || continue
    printf '%s\n' "$src"
    return 0
  done < <(findmnt -rn -t btrfs -o TARGET,SOURCE,OPTIONS 2>/dev/null)

  return 1
}

current_subvol() {
  local opts

  opts="$(findmnt -n -o OPTIONS -T / 2>/dev/null || true)"
  if [[ "$opts" == *"subvol="* ]]; then
    sed -n 's/.*subvol=\([^,]*\).*/\1/p' <<< "$opts"
    return 0
  fi

  local target src mount_opts
  while read -r target src mount_opts; do
    if [[ "$mount_opts" == *"subvol=/root"* || "$mount_opts" == *"subvol=/snapshots/"* ]]; then
      sed -n 's/.*subvol=\([^,]*\).*/\1/p' <<< "$mount_opts"
      return 0
    fi
  done < <(findmnt -rn -t btrfs -o TARGET,SOURCE,OPTIONS 2>/dev/null)

  return 1
}

mount_top() {
  local root_dev

  if [[ -n "${ROOT_UUID:-}" ]]; then
    root_dev="/dev/disk/by-uuid/${ROOT_UUID}"
  else
    root_dev="$(detect_root_dev)" || die "no se pudo detectar el dispositivo Btrfs raíz. Definí ROOT_UUID=<uuid>."
  fi

  TOP_MNT="$(mktemp -d /tmp/snapper-rollback.XXXXXX)"
  mount -o subvolid=5 "$root_dev" "$TOP_MNT" || die "no se pudo montar el nivel superior de Btrfs en ${TOP_MNT}."
}

xml_value() {
  local file="$1"
  local tag="$2"
  awk -F'[<>]' -v t="$tag" '$2 == t {print $3; exit}' "$file" 2>/dev/null || true
}

list_snapshots() {
  local dir id info date type desc

  echo "Snapshots disponibles en ${TOP_MNT}/snapshots:"
  printf '  %-6s %-20s %-8s %s\n' "ID" "FECHA" "TIPO" "DESCRIPCIÓN"

  local found=0
  for dir in "${TOP_MNT}"/snapshots/*; do
    [[ -d "$dir/snapshot" ]] || continue
    id="$(basename "$dir")"
    [[ "$id" =~ ^[0-9]+$ ]] || continue
    found=1
    info="${dir}/info.xml"
    if [[ -r "$info" ]]; then
      date="$(xml_value "$info" date)"
      type="$(xml_value "$info" type)"
      desc="$(xml_value "$info" description)"
    else
      date="?"
      type="?"
      desc="?"
    fi
    printf '  %-6s %-20s %-8s %s\n' "$id" "${date:0:19}" "${type:-single}" "${desc:-sin descripción}"
  done

  if (( ! found )); then
    echo "  (no hay snapshots)"
  fi

  echo ""
  echo "Roots anteriores conservados:"
  local broken_found=0
  for dir in "${TOP_MNT}"/root.broken-*; do
    [[ -e "$dir" ]] || continue
    broken_found=1
    echo "  $(basename "$dir")"
  done
  if (( ! broken_found )); then
    echo "  (ninguno)"
  fi
}

validate_snapshot() {
  [[ "$SNAP_ID" =~ ^[0-9]+$ ]] || die "el ID de snapshot debe ser numérico."
  local snap="${TOP_MNT}/snapshots/${SNAP_ID}/snapshot"
  [[ -d "$snap" ]] || die "no existe el snapshot ${SNAP_ID}."
  btrfs subvolume show "$snap" >/dev/null 2>&1 || die "el snapshot ${SNAP_ID} no es un subvolumen Btrfs."
}

copy_path() {
  local rel="$1"
  local src="${TOP_MNT}/root/${rel}"
  local dst="${TOP_MNT}/root.new/${rel}"

  if [[ ! -e "$src" && ! -L "$src" ]]; then
    return 0
  fi

  if (( DRY_RUN )); then
    echo "  [dry-run] conservar ${rel}"
    return 0
  fi

  mkdir -p "$(dirname "$dst")"
  if [[ -d "$src" && ! -L "$src" ]]; then
    mkdir -p "$dst"
    cp -a "${src}/." "$dst/"
  else
    cp -a "$src" "$dst"
  fi
}

copy_kernel_modules() {
  local src_dir="${TOP_MNT}/root/usr/lib/modules"
  local dst_dir="${TOP_MNT}/root.new/usr/lib/modules"
  local mod name

  [[ -d "$src_dir" ]] || return 0

  for mod in "$src_dir"/*; do
    [[ -d "$mod" ]] || continue
    name="$(basename "$mod")"
    [[ -e "${dst_dir}/${name}" ]] && continue

    if (( DRY_RUN )); then
      echo "  [dry-run] conservar usr/lib/modules/${name}"
      continue
    fi

    echo "  conservando módulos del kernel ${name}"
    mkdir -p "$dst_dir"
    cp -a "$mod" "$dst_dir/"
  done
}

ensure_new_root_fstab() {
  local fstab="${TOP_MNT}/root.new/etc/fstab"
  local root_dev uuid

  [[ -f "$fstab" ]] || return 0

  if [[ -n "${ROOT_UUID:-}" ]]; then
    uuid="$ROOT_UUID"
  else
    root_dev="$(detect_root_dev)" || return 0
    uuid="$(blkid -s UUID -o value "$root_dev" 2>/dev/null || true)"
  fi
  [[ -n "$uuid" ]] || return 0

  if btrfs subvolume show "${TOP_MNT}/snapshots" >/dev/null 2>&1 &&
     ! grep -qE '^[^#].*[[:space:]]/\.snapshots[[:space:]]+btrfs[[:space:]]+.*subvol=snapshots' "$fstab"; then
    printf 'UUID=%s /.snapshots btrfs subvol=snapshots,noatime 0 0\n' "$uuid" >> "$fstab"
  fi
  if btrfs subvolume show "${TOP_MNT}/swap" >/dev/null 2>&1 &&
     ! grep -qE '^[^#].*[[:space:]]/swap[[:space:]]+btrfs[[:space:]]+.*subvol=swap' "$fstab"; then
    printf 'UUID=%s /swap btrfs subvol=swap,noatime,compress=no 0 0\n' "$uuid" >> "$fstab"
  fi
  if [[ -e "${TOP_MNT}/swap/swapfile" ]] &&
     ! grep -qE '^[^#].*[[:space:]]/swap/swapfile[[:space:]]+none[[:space:]]+swap' "$fstab"; then
    printf '/swap/swapfile none swap defaults,pri=10 0 0\n' >> "$fstab"
  fi
}

commit_snapshot() {
  local snap="${TOP_MNT}/snapshots/${SNAP_ID}/snapshot"
  local current
  current="$(current_subvol || true)"
  current="${current#/}"

  if [[ "$current" == "root" && $FORCE -eq 0 ]]; then
    die "estás arrancado desde el root normal. Reiniciá un snapshot desde GRUB o usá --force."
  fi
  if [[ -z "$current" ]]; then
    warn "no se pudo determinar el subvolumen actual; continuando."
  fi

  [[ -e "${TOP_MNT}/root" ]] || die "no existe el subvolumen 'root'."
  btrfs subvolume show "${TOP_MNT}/root" >/dev/null 2>&1 || die "'root' no es un subvolumen Btrfs."
  if [[ -e "${TOP_MNT}/root.new" ]]; then
    die "'root.new' ya existe. Eliminalo o completá el rollback anterior."
  fi

  validate_snapshot

  local ts old_root
  ts="$(date +%Y%m%d-%H%M%S)"
  old_root="root.broken-${ts}"
  while [[ -e "${TOP_MNT}/${old_root}" ]]; do
    old_root="root.broken-${ts}-$$"
  done

  info "Snapshot elegido: ${SNAP_ID}"
  info "Root anterior: ${old_root}"
  (( DRY_RUN )) && info "Modo dry-run: no se ejecutarán cambios."

  run btrfs subvolume snapshot "$snap" "${TOP_MNT}/root.new"

  # Conservar configuración y estado que no debería retroceder.
  local rel
  for rel in \
    etc/fstab \
    etc/machine-id \
    etc/hostname \
    etc/hosts \
    etc/localtime \
    etc/adjtime \
    etc/vconsole.conf \
    etc/locale.conf \
    etc/passwd \
    etc/shadow \
    etc/group \
    etc/gshadow \
    etc/subuid \
    etc/subgid \
    etc/sudoers \
    etc/sudoers.d \
    etc/ssh \
    etc/NetworkManager/system-connections \
    etc/NetworkManager/conf.d \
    etc/snapper/configs/root \
    etc/default/grub \
    etc/default/grub-btrfs/config \
    etc/kernel/cmdline \
    etc/crypttab \
    etc/dracut.conf.d/99-dotfiles-power.conf \
    etc/sysctl.d/99-dotfiles-zram.conf \
    etc/systemd/oomd.conf.d/99-dotfiles.conf \
    etc/tmpfiles.d/99-dotfiles-hibernation.conf
  do
    copy_path "$rel"
  done
  copy_kernel_modules

  if (( ! DRY_RUN )); then
    ensure_new_root_fstab
  else
    echo "  [dry-run] asegurar entradas de /.snapshots, /swap y swapfile en fstab"
  fi

  run mv "${TOP_MNT}/root" "${TOP_MNT}/${old_root}"
  run mv "${TOP_MNT}/root.new" "${TOP_MNT}/root"

  if (( ! DRY_RUN )); then
    if ! grep -qE '^[^#].*[[:space:]]/[[:space:]]+btrfs[[:space:]]+.*subvol=root' "${TOP_MNT}/root/etc/fstab"; then
      warn "el fstab restaurado no contiene subvol=root para /. Revisalo antes de reiniciar."
    fi

    if command -v grub2-editenv >/dev/null 2>&1 && [[ -f /boot/grub2/grubenv ]]; then
      grub2-editenv /boot/grub2/grubenv unset saved_entry || warn "no se pudo limpiar saved_entry de GRUB."
    fi

    sync
  fi

  echo ""
  info "Rollback preparado."
  echo "    Reiniciá para arrancar el nuevo root."
  echo "    Root anterior conservado en: ${old_root}"
  if (( DRY_RUN )); then
    echo "    (dry-run: no se modificó nada)"
  fi
}

cleanup_broken() {
  local dir found=0
  local -a targets=()

  for dir in "${TOP_MNT}"/root.broken-* "${TOP_MNT}"/root.new; do
    [[ -e "$dir" ]] || continue
    targets+=("$dir")
    found=1
  done

  if (( ! found )); then
    info "No hay roots anteriores para limpiar."
    return 0
  fi

  echo "Se eliminarán:"
  for dir in "${targets[@]}"; do
    echo "  $(basename "$dir")"
  done

  if (( ! ASSUME_YES )); then
    if [[ ! -t 0 ]]; then
      die "para limpiar sin interacción usá --yes."
    fi
    read -r -p "¿Continuar? [y/N] " answer
    [[ "$answer" =~ ^[yY]$ ]] || { echo "Cancelado."; return 0; }
  fi

  for dir in "${targets[@]}"; do
    if btrfs subvolume show "$dir" >/dev/null 2>&1; then
      btrfs subvolume delete "$dir" || warn "no se pudo eliminar $(basename "$dir")."
    else
      warn "$(basename "$dir") no es un subvolumen; no se elimina."
    fi
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --list) ACTION="list"; shift ;;
    --commit)
      ACTION="commit"
      [[ $# -ge 2 ]] || die "--commit requiere un ID."
      SNAP_ID="$2"
      shift 2
      ;;
    --commit=*)
      ACTION="commit"
      SNAP_ID="${1#*=}"
      shift
      ;;
    --cleanup) ACTION="cleanup"; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --force) FORCE=1; shift ;;
    --yes) ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "opción desconocida: $1" ;;
  esac
done

[[ -n "$ACTION" ]] || { usage; exit 1; }

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: ejecutá este helper con sudo (requiere root)." >&2
  exit 1
fi

mount_top

case "$ACTION" in
  list)
    list_snapshots
    ;;
  commit)
    [[ -n "$SNAP_ID" ]] || die "--commit requiere un ID."
    commit_snapshot
    ;;
  cleanup)
    cleanup_broken
    ;;
esac
