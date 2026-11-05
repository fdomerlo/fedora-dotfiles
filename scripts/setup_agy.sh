#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "ERROR: Ejecutá este script como usuario normal (sin sudo)." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SUBDIR_APP="Antigravity-x64"
BIN_APP="antigravity"
INSTALL_DIR="/opt/$SUBDIR_APP"
ICON_SRC="$SCRIPT_DIR/antigravity.png"
ICON_DST="$INSTALL_DIR/antigravity.png"
SYMLINK_BIN="/usr/local/bin/antigravity"
DESKTOP_FILE="/usr/share/applications/antigravity.desktop"

# Detectar directorio de descargas del usuario sin asumir idioma único
DIR_DESCARGAS="${XDG_DOWNLOAD_DIR:-$HOME/Descargas}"
if [[ ! -f "$DIR_DESCARGAS/Antigravity.tar.gz" && -f "$HOME/Downloads/Antigravity.tar.gz" ]]; then
  DIR_DESCARGAS="$HOME/Downloads"
fi
ARCHIVO_APP="$DIR_DESCARGAS/Antigravity.tar.gz"

ensure_desktop_integration() {
  # Garantizar que el ícono exista en el directorio de instalación (p. ej. si se instaló con una versión previa)
  if [[ -f "$ICON_SRC" ]] && { [[ ! -f "$ICON_DST" ]] || ! cmp -s "$ICON_SRC" "$ICON_DST"; }; then
    sudo install -m 0644 "$ICON_SRC" "$ICON_DST"
  fi

  # Enlace simbólico en /usr/local/bin solo si no apunta ya al destino correcto
  if [[ ! -L "$SYMLINK_BIN" ]] || [[ "$(readlink -f "$SYMLINK_BIN" 2>/dev/null || true)" != "$INSTALL_DIR/$BIN_APP" ]]; then
    sudo ln -sfn "$INSTALL_DIR/$BIN_APP" "$SYMLINK_BIN"
  fi

  local expected_desktop
  expected_desktop="[Desktop Entry]
Name=Antigravity 2.0
Comment=Orquestación asíncrona de agentes autónomos
Exec=$SYMLINK_BIN
Icon=$ICON_DST
Type=Application
Terminal=false
Categories=Development;"

  if [[ ! -f "$DESKTOP_FILE" ]] || [[ "$(cat "$DESKTOP_FILE" 2>/dev/null || true)" != "$expected_desktop" ]]; then
    printf '%s\n' "$expected_desktop" | sudo tee "$DESKTOP_FILE" >/dev/null
    if command -v update-desktop-database &>/dev/null; then
      sudo update-desktop-database /usr/share/applications/
    fi
  fi
}

# 1. Si no existe el archivo local, tratar Antigravity desktop como opcional
if [[ ! -f "$ARCHIVO_APP" ]]; then
  if [[ -x "$INSTALL_DIR/$BIN_APP" ]]; then
    echo "==> Antigravity desktop ya está instalado en $INSTALL_DIR."
    ensure_desktop_integration
  else
    echo "==> [Opcional] No se encontró $ARCHIVO_APP y Antigravity desktop no está instalado en $INSTALL_DIR. Omitiendo."
  fi
  exit 0
fi

# 2. Comprobar si la instalación existente ya está actualizada respecto al paquete local
if [[ -x "$INSTALL_DIR/$BIN_APP" && ! "$ARCHIVO_APP" -nt "$INSTALL_DIR" ]]; then
  echo "==> Antigravity desktop en $INSTALL_DIR ya está actualizado. Omitiendo reextracción."
  ensure_desktop_integration
  exit 0
fi

# 3. Validar integridad del archivo antes de tocar /opt
echo "==> Validando paquete local $ARCHIVO_APP..."
if ! tar -tzf "$ARCHIVO_APP" >/dev/null 2>&1; then
  echo "ERROR: El archivo $ARCHIVO_APP está corrupto o no es un tar.gz válido. No se modificó $INSTALL_DIR." >&2
  exit 1
fi

# 4. Extracción temporal, validación del binario y reemplazo controlado en /opt
STAGE_DIR="$(sudo mktemp -d "/opt/.${SUBDIR_APP}.staging.XXXXXX")"
cleanup_stage() {
  if [[ -n "${STAGE_DIR:-}" ]] && sudo test -d "$STAGE_DIR"; then
    sudo rm -rf "$STAGE_DIR"
  fi
}
trap cleanup_stage EXIT

echo "==> Extrayendo Antigravity desktop en directorio temporal de validación..."
sudo tar -xzf "$ARCHIVO_APP" -C "$STAGE_DIR"

if ! sudo test -f "$STAGE_DIR/$SUBDIR_APP/$BIN_APP" || ! sudo test -x "$STAGE_DIR/$SUBDIR_APP/$BIN_APP"; then
  echo "ERROR: El archivo extraído no contiene un ejecutable válido en $SUBDIR_APP/$BIN_APP. Se conserva la instalación previa." >&2
  exit 1
fi

if [[ -f "$ICON_SRC" ]]; then
  sudo install -m 0644 "$ICON_SRC" "$STAGE_DIR/$SUBDIR_APP/antigravity.png"
fi

sudo chown -R root:root "$STAGE_DIR/$SUBDIR_APP"
sudo chmod -R a+rX "$STAGE_DIR/$SUBDIR_APP"

BACKUP_DIR="/opt/.${SUBDIR_APP}.backup.$$"
if sudo test -d "$INSTALL_DIR"; then
  sudo mv "$INSTALL_DIR" "$BACKUP_DIR"
fi

if sudo mv "$STAGE_DIR/$SUBDIR_APP" "$INSTALL_DIR"; then
  sudo touch "$INSTALL_DIR"
  if sudo test -d "$BACKUP_DIR"; then
    sudo rm -rf "$BACKUP_DIR"
  fi
  echo "==> Antigravity desktop desplegado y validado en $INSTALL_DIR."
else
  echo "ERROR: Falló el reemplazo de $INSTALL_DIR. Restaurando versión anterior..." >&2
  if sudo test -d "$BACKUP_DIR"; then
    sudo mv "$BACKUP_DIR" "$INSTALL_DIR"
  fi
  exit 1
fi

ensure_desktop_integration
echo "==> Integración de escritorio de Antigravity completada."
