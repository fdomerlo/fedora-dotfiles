#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "ERROR: Ejecutá este script como usuario normal (sin sudo)." >&2
  echo "       El script solicitará privilegios con sudo únicamente si falta instalar paquetes." >&2
  exit 1
fi

if [[ -r /etc/os-release ]]; then
  # shellcheck source=/dev/null
  source /etc/os-release
  if [[ "${ID:-}" != "fedora" ]]; then
    echo "ERROR: Este aprovisionamiento de host está diseñado para Fedora (detectado: ${ID:-desconocido})." >&2
    exit 1
  fi
else
  echo "ERROR: No se pudo leer /etc/os-release." >&2
  exit 1
fi

# 1. Detectar el filesystem real antes de evaluar cualquier consideración de Btrfs
ROOT_FS="$(findmnt -n -o FSTYPE -T / 2>/dev/null || echo "unknown")"
HOME_FS="$(findmnt -n -o FSTYPE -T "$HOME" 2>/dev/null || echo "unknown")"
HOME_OPTS="$(findmnt -n -o OPTIONS -T "$HOME" 2>/dev/null || echo "")"

echo "==> Filesystem detectado: / (${ROOT_FS}), \$HOME (${HOME_FS})"
if [[ "$HOME_FS" == "btrfs" ]]; then
  echo "    Opciones de montaje en \$HOME: ${HOME_OPTS}"
fi

# 2. Instalar únicamente los paquetes base ausentes (sin dnf upgrade ni paquetes fuera de alcance)
BASE_PACKAGES=(
  git
  curl
  wget
  jq
  zip
  unzip
  podman
  podman-compose
  podman-docker
  distrobox
)

if [[ "$ROOT_FS" == "btrfs" || "$HOME_FS" == "btrfs" ]]; then
  BASE_PACKAGES+=(btrfs-progs)
fi

MISSING_PACKAGES=()
for pkg in "${BASE_PACKAGES[@]}"; do
  if ! rpm -q "$pkg" &>/dev/null; then
    MISSING_PACKAGES+=("$pkg")
  fi
done

if [[ ${#MISSING_PACKAGES[@]} -gt 0 ]]; then
  echo "==> Instalando paquetes base faltantes: ${MISSING_PACKAGES[*]}"
  sudo dnf install -y "${MISSING_PACKAGES[@]}"
else
  echo "==> Todos los paquetes base ya están instalados. Sin escrituras de DNF."
fi

# 3. Verificar zRAM nativo de Fedora (sin crear swapfiles ni alterar sysctl)
echo "==> Verificando configuración nativa de zRAM..."
if command -v zramctl &>/dev/null && zramctl --output NAME --noheadings 2>/dev/null | grep -q 'zram'; then
  zramctl
elif swapon --show=NAME --noheadings 2>/dev/null | grep -q 'zram'; then
  swapon --show
else
  echo "ADVERTENCIA: No se detectó un dispositivo zRAM activo. Revisá zram-generator-defaults en Fedora." >&2
fi

# 4. Verificar Podman rootless y almacenamiento de contenedores
echo "==> Verificando Podman rootless y almacenamiento de contenedores..."
if ! command -v podman &>/dev/null; then
  echo "ERROR: Podman no está disponible tras la verificación de paquetes." >&2
  exit 1
fi

PODMAN_ROOTLESS="$(podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null || echo "unknown")"
PODMAN_DRIVER="$(podman info --format '{{.Store.GraphDriverName}}' 2>/dev/null || echo "unknown")"
PODMAN_GRAPHROOT="$(podman info --format '{{.Store.GraphRoot}}' 2>/dev/null || echo "unknown")"

if [[ "$PODMAN_ROOTLESS" != "true" ]]; then
  echo "ERROR: Podman no está operando en modo rootless (Rootless=${PODMAN_ROOTLESS})." >&2
  exit 1
fi

echo "    Modo rootless:  ${PODMAN_ROOTLESS}"
echo "    Storage driver: ${PODMAN_DRIVER}"
echo "    GraphRoot:      ${PODMAN_GRAPHROOT}"

if [[ "$PODMAN_GRAPHROOT" != "unknown" && -d "$PODMAN_GRAPHROOT" ]]; then
  GRAPHROOT_FS="$(findmnt -n -o FSTYPE -T "$PODMAN_GRAPHROOT" 2>/dev/null || echo "$HOME_FS")"
  echo "    Filesystem en GraphRoot: ${GRAPHROOT_FS}"
fi

# Nota técnica: Se conserva la configuración predeterminada de Podman rootless en Fedora
# (overlay sobre Btrfs con compresión transparente zstd:1 y checksums de datos activos).
# No se aplica chattr +C (NOCOW desactiva checksums y compresión zstd incrementando escrituras)
# ni chown recursivo sobre ~/.local, ni se activa loginctl enable-linger.

# 5. Compatibilidad Docker: socket rootless de Podman (activado por demanda, sin linger)
#    Necesario para herramientas que usan la API de Docker (DOCKER_HOST, devcontainers, testcontainers).
#    El CLI 'docker' lo provee podman-docker y 'podman-compose' no requiere el socket.
if systemctl --user is-enabled --quiet podman.socket 2>/dev/null && systemctl --user is-active --quiet podman.socket 2>/dev/null; then
  echo "==> Socket rootless de Podman ya habilitado."
elif systemctl --user show-environment &>/dev/null; then
  echo "==> Habilitando socket rootless de Podman (compatibilidad API Docker)..."
  systemctl --user enable --now podman.socket
else
  echo "ADVERTENCIA: No hay sesión systemd de usuario; habilitá luego: systemctl --user enable --now podman.socket" >&2
fi

echo "==> Host Fedora verificado y listo."
