#!/usr/bin/env bash
# host/snapper.sh - (Opcional) Snapshots Btrfs de / con Snapper, retención conservadora
# e integración automática pre/post transacción de DNF (DNF5 y DNF4).
# Se ejecuta con `make snapper`; no forma parte de `make install`.
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

# 1. Snapper solo tiene sentido si / está en Btrfs
ROOT_FS="$(findmnt -n -o FSTYPE -T / 2>/dev/null || echo "unknown")"
if [[ "$ROOT_FS" != "btrfs" ]]; then
  echo "==> / está en '${ROOT_FS}', no en Btrfs. Snapper omitido."
  exit 0
fi

# 2. Detectar versión de DNF (DNF5 en Fedora 41+ vs DNF4) e instalar paquetes faltantes
IS_DNF5=0
if command -v dnf5 &>/dev/null || dnf --version 2>/dev/null | head -1 | grep -q 'dnf5'; then
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

# 3. Crear la configuración 'root' solo si no existe
if sudo test -f /etc/snapper/configs/root; then
  echo "==> La configuración de Snapper 'root' ya existe."
else
  echo "==> Creando configuración de Snapper 'root' para /..."
  sudo snapper -c root create-config /
fi

# 4. Políticas conservadoras para no saturar SSDs chicos (solo se escriben si difieren).
#    No se habilitan cuotas Btrfs (qgroups) para evitar bloqueos de I/O.
declare -A DESIRED=(
  [TIMELINE_CREATE]=yes
  [TIMELINE_CLEANUP]=yes
  [TIMELINE_LIMIT_HOURLY]=3
  [TIMELINE_LIMIT_DAILY]=3
  [TIMELINE_LIMIT_WEEKLY]=1
  [TIMELINE_LIMIT_MONTHLY]=0
  [TIMELINE_LIMIT_YEARLY]=0
  [NUMBER_CLEANUP]=yes
  [NUMBER_LIMIT]=6
  [NUMBER_LIMIT_IMPORTANT]=2
)

CHANGES=()
for key in "${!DESIRED[@]}"; do
  current="$(sudo snapper -c root get-config 2>/dev/null | awk -F'│|\\|' -v k="$key" '{gsub(/[ \t]+/, "", $1); gsub(/^[ \t]+|[ \t]+$/, "", $2); if ($1 == k) print $2}')"
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

# 5. Configurar snapshots automáticos pre/post transacción de DNF de forma idempotente
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

# 6. Habilitar timers de timeline y limpieza solo si no están activos
for timer in snapper-timeline.timer snapper-cleanup.timer; do
  if systemctl is-enabled --quiet "$timer" 2>/dev/null && systemctl is-active --quiet "$timer" 2>/dev/null; then
    echo "==> $timer ya está habilitado."
  else
    echo "==> Habilitando $timer..."
    sudo systemctl enable --now "$timer"
  fi
done

echo "==> Snapper configurado. Listar snapshots: sudo snapper -c root list"
