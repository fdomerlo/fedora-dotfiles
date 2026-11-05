#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "ERROR: Ejecutá este script como usuario normal para operar con Podman rootless." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

BOX_NAME="${BOX_NAME:-debian-work}"
BOX_IMAGE="${BOX_IMAGE:-docker.io/library/debian:13}"

for cmd in podman distrobox; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "ERROR: Falta la dependencia requerida '$cmd'. Ejecutá 'make host' primero." >&2
    exit 1
  fi
done

# 1. Instalar devctl en ~/.local/bin de forma idempotente y sin escrituras innecesarias
DEVCTL_SRC="$REPO_DIR/shell/devctl"
DEVCTL_DST="$HOME/.local/bin/devctl"

if [[ ! -x "$DEVCTL_SRC" ]]; then
  chmod +x "$DEVCTL_SRC"
fi

mkdir -p "$HOME/.local/bin"
if [[ ! -L "$DEVCTL_DST" ]] || [[ "$(readlink -f "$DEVCTL_DST" 2>/dev/null || true)" != "$DEVCTL_SRC" ]]; then
  ln -sfn "$DEVCTL_SRC" "$DEVCTL_DST"
  echo "==> Enlace simbólico actualizado: $DEVCTL_DST -> $DEVCTL_SRC"
else
  echo "==> devctl ya está enlazado en $DEVCTL_DST"
fi

# 2. Garantizar ejecución de Distrobox mediante Podman rootless
export DBX_CONTAINER_MANAGER=podman

PODMAN_ROOTLESS="$(podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null || echo "false")"
if [[ "$PODMAN_ROOTLESS" != "true" ]]; then
  echo "ERROR: Podman debe ejecutarse en modo rootless para Distrobox." >&2
  exit 1
fi

# 3. Crear el contenedor persistente debian-work solo si no existe
container_exists() {
  local name="$1"
  if podman container exists "$name" 2>/dev/null; then
    return 0
  fi
  if distrobox list --no-color 2>/dev/null | awk -F'|' 'NR>1 {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' | grep -Fxq "$name"; then
    return 0
  fi
  return 1
}

if container_exists "$BOX_NAME"; then
  echo "==> El entorno Distrobox '$BOX_NAME' ya existe. No se recrea ni modifica."
else
  echo "==> Creando entorno Distrobox persistente '$BOX_NAME' con imagen oficial '$BOX_IMAGE'..."
  distrobox create \
    --name "$BOX_NAME" \
    --image "$BOX_IMAGE" \
    --yes
  echo "==> Contenedor '$BOX_NAME' creado correctamente."
fi

echo "==> Comandos disponibles:"
echo "    distrobox list"
echo "    distrobox enter $BOX_NAME"
