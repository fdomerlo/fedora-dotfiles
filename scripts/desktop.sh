#!/usr/bin/env bash
set -euo pipefail

echo "================================================================="
echo "==> Configurando entorno de escritorio GNOME (Fuentes y Extensiones)"
echo "================================================================="

# ------------------------------------------------------------------------------
# 1. Configuración de Tipografías
# ------------------------------------------------------------------------------
echo "==> Aplicando configuración de fuentes..."

# Interfaces: Mantenemos Adwaita (Adwaita Sans 11)
gsettings set org.gnome.desktop.interface font-name 'Adwaita Sans 11'

# Documentos: Noto Sans Regular 12
gsettings set org.gnome.desktop.interface document-font-name 'Noto Sans 12'

# Monoespaciada: Fira Code 11
gsettings set org.gnome.desktop.interface monospace-font-name 'Fira Code 11'

# Título de ventanas (mantenemos coherencia con Adwaita Sans Bold 11)
gsettings set org.gnome.desktop.wm.preferences titlebar-font 'Adwaita Sans Bold 11' || true

echo "    ✔ Interfaz:     $(gsettings get org.gnome.desktop.interface font-name)"
echo "    ✔ Documentos:   $(gsettings get org.gnome.desktop.interface document-font-name)"
echo "    ✔ Monoespacio:  $(gsettings get org.gnome.desktop.interface monospace-font-name)"

# ------------------------------------------------------------------------------
# 2. Deshabilitar validación estricta de versión de extensiones en GNOME
# ------------------------------------------------------------------------------
# Permite que extensiones funcionales sigan cargando aunque la versión mayor de GNOME
# avance más rápido que las etiquetas en extensions.gnome.org.
gsettings set org.gnome.shell disable-extension-version-validation true 2>/dev/null || true

# ------------------------------------------------------------------------------
# 3. Instalación de Extensiones
# ------------------------------------------------------------------------------
USER_EXT_DIR="$HOME/.local/share/gnome-shell/extensions"
SYS_EXT_DIR="/usr/share/gnome-shell/extensions"
mkdir -p "$USER_EXT_DIR"

GNOME_VER=$(gnome-shell --version 2>/dev/null | grep -oP '[0-9]+' | head -1 || echo "47")
echo "==> Versión detectada de GNOME Shell: $GNOME_VER"

install_extension() {
    local uuid="$1"
    local rpm_pkg="${2:-}"

    echo "--> Procesando extensión: $uuid"

    # Verificar si ya está instalada a nivel sistema o usuario
    if [ -d "$SYS_EXT_DIR/$uuid" ] || [ -d "$USER_EXT_DIR/$uuid" ]; then
        echo "    ✔ Ya instalada en el sistema o directorio de usuario."
        return 0
    fi

    # Si hay un paquete RPM oficial en Fedora y contamos con sudo/dnf, intentamos instalarlo
    if [ -n "$rpm_pkg" ] && command -v dnf &>/dev/null; then
        if sudo dnf list --available "$rpm_pkg" &>/dev/null; then
            echo "    Instalando paquete RPM del sistema: $rpm_pkg..."
            if sudo dnf install -y "$rpm_pkg"; then
                echo "    ✔ Instalado exitosamente via DNF."
                return 0
            fi
        fi
    fi

    # Si no es RPM o falló, descargamos desde la API oficial de extensions.gnome.org
    echo "    Descargando desde extensions.gnome.org..."
    local info_json
    info_json=$(curl -sL "https://extensions.gnome.org/extension-info/?uuid=${uuid}" 2>/dev/null || echo "{}")

    local pk
    pk=$(echo "$info_json" | jq -r '
        .shell_version_map as $map |
        if $map == null then
            empty
        else
            ($map["'"${GNOME_VER}"'"].pk // ($map | to_entries | max_by(.value.version).value.pk))
        end
    ' 2>/dev/null || true)

    if [ -z "$pk" ] || [ "$pk" = "null" ]; then
        echo "    ⚠️ No se pudo obtener información de versión para $uuid desde la API de GNOME."
        return 1
    fi

    local tmp_zip="/tmp/${uuid}.shell-extension.zip"
    echo "    Descargando paquete (version tag: $pk)..."
    curl -sL "https://extensions.gnome.org/download-extension/${uuid}.shell-extension.zip?version_tag=${pk}" -o "$tmp_zip"

    local target_dir="$USER_EXT_DIR/$uuid"
    mkdir -p "$target_dir"
    unzip -oq "$tmp_zip" -d "$target_dir"
    rm -f "$tmp_zip"

    # Compilar esquemas si están presentes
    if [ -d "$target_dir/schemas" ] && command -v glib-compile-schemas &>/dev/null; then
        glib-compile-schemas "$target_dir/schemas" 2>/dev/null || true
    fi

    # Asegurar que la versión actual de GNOME esté listada en metadata.json
    local metadata="$target_dir/metadata.json"
    if [ -f "$metadata" ] && command -v jq &>/dev/null; then
        if ! jq -e '.["shell-version"] | index("'"${GNOME_VER}"'")' "$metadata" >/dev/null 2>&1; then
            jq '.["shell-version"] += ["'"${GNOME_VER}"'"]' "$metadata" > "${metadata}.tmp" && \
            mv "${metadata}.tmp" "$metadata"
        fi
    fi

    echo "    ✔ Extensión $uuid instalada correctamente en $target_dir"
}

# 1) Alphabetical App Grid
install_extension "AlphabeticalAppGrid@stuarthayhurst" ""

# 2) Vitals
install_extension "Vitals@CoreCoding.com" ""

# 3) Dash to Dock (paquete oficial gnome-shell-extension-dash-to-dock)
install_extension "dash-to-dock@micxgx.gmail.com" "gnome-shell-extension-dash-to-dock"

# 4) Tiling Shell (de domferr)
install_extension "tilingshell@ferrarodomenico.com" ""

# ------------------------------------------------------------------------------
# 4. Habilitar extensiones requeridas en GNOME
# ------------------------------------------------------------------------------
echo "==> Habilitando extensiones requeridas..."

python3 - << 'EOF'
import ast
import subprocess
import sys

schema = "org.gnome.shell"
key = "enabled-extensions"
required = [
    "AlphabeticalAppGrid@stuarthayhurst",
    "Vitals@CoreCoding.com",
    "dash-to-dock@micxgx.gmail.com",
    "tilingshell@ferrarodomenico.com"
]

try:
    proc = subprocess.run(["gsettings", "get", schema, key], capture_output=True, text=True, check=True)
    val = proc.stdout.strip()
    current = ast.literal_eval(val) if val else []
    if not isinstance(current, list):
        current = []
except Exception:
    current = []

updated = list(current)

# Remover pop-shell si estuviera en la lista activa para evitar conflictos de tiling
if "pop-shell@system76.com" in updated:
    updated.remove("pop-shell@system76.com")

for ext in required:
    if ext not in updated:
        updated.append(ext)

if updated != current:
    val_str = str(updated)
    subprocess.run(["gsettings", "set", schema, key, val_str], check=True)
    print(f"    ✔ Lista de extensiones habilitadas actualizada en GSettings.")
else:
    print(f"    ✔ Todas las extensiones ya estaban registradas en GSettings.")
EOF

# Deshabilitar pop-shell para evitar conflictos si estuviera activa
gnome-extensions disable "pop-shell@system76.com" 2>/dev/null || true

# También invocar `gnome-extensions enable` para activación en caliente si la sesión está abierta
for uuid in "AlphabeticalAppGrid@stuarthayhurst" "Vitals@CoreCoding.com" "dash-to-dock@micxgx.gmail.com" "tilingshell@ferrarodomenico.com"; do
    gnome-extensions enable "$uuid" 2>/dev/null || true
done

echo "==> Estado actual de extensiones habilitadas:"
gsettings get org.gnome.shell enabled-extensions

echo "================================================================="
echo "✅ Configuración de escritorio y fuentes completada con éxito."
echo "Nota: Si acabas de instalar nuevas extensiones, puede ser necesario"
echo "cerrar sesión y volver a iniciarla para que GNOME Shell las cargue."
echo "================================================================="

