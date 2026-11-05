#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
    echo "ERROR: Ejecutá este script como usuario normal (sin sudo)." >&2
    exit 1
fi

gsettings_set_if_needed() {
    local schema="$1" key="$2" expected="$3" raw="$4"
    local current
    current="$(gsettings get "$schema" "$key" 2>/dev/null || true)"
    if [[ "$current" != "$expected" ]]; then
        gsettings set "$schema" "$key" "$raw" 2>/dev/null || true
    fi
}

echo "================================================================="
echo "==> Configurando entorno de escritorio GNOME (Fuentes y Extensiones)"
echo "================================================================="

# ------------------------------------------------------------------------------
# 1. Configuración de Tipografías
# ------------------------------------------------------------------------------
echo "==> Aplicando configuración de fuentes..."

# Instalar únicamente las fuentes ausentes requeridas por esta configuración
FONT_PACKAGES=(jetbrains-mono-fonts google-noto-sans-vf-fonts)
MISSING_FONTS=()
for pkg in "${FONT_PACKAGES[@]}"; do
    rpm -q "$pkg" &>/dev/null || MISSING_FONTS+=("$pkg")
done
if [[ ${#MISSING_FONTS[@]} -gt 0 ]]; then
    echo "==> Instalando fuentes faltantes: ${MISSING_FONTS[*]}"
    sudo dnf install -y "${MISSING_FONTS[@]}"
fi

# Interfaces: Mantenemos Adwaita (Adwaita Sans 11)
gsettings_set_if_needed org.gnome.desktop.interface font-name "'Adwaita Sans 11'" "Adwaita Sans 11"

# Documentos: Noto Sans Regular 12
gsettings_set_if_needed org.gnome.desktop.interface document-font-name "'Noto Sans 12'" "Noto Sans 12"

# Monoespaciada: JetBrains Mono 11
gsettings_set_if_needed org.gnome.desktop.interface monospace-font-name "'JetBrains Mono 11'" "JetBrains Mono 11"

# Título de ventanas (mantenemos coherencia con Adwaita Sans Bold 11)
gsettings_set_if_needed org.gnome.desktop.wm.preferences titlebar-font "'Adwaita Sans Bold 11'" "Adwaita Sans Bold 11"

echo "    ✔ Interfaz:     $(gsettings get org.gnome.desktop.interface font-name)"
echo "    ✔ Documentos:   $(gsettings get org.gnome.desktop.interface document-font-name)"
echo "    ✔ Monoespacio:  $(gsettings get org.gnome.desktop.interface monospace-font-name)"

# ------------------------------------------------------------------------------
# 2. Deshabilitar validación estricta de versión de extensiones en GNOME
# ------------------------------------------------------------------------------
# Permite que extensiones funcionales sigan cargando aunque la versión mayor de GNOME
# avance más rápido que las etiquetas en extensions.gnome.org.
gsettings_set_if_needed org.gnome.shell disable-extension-version-validation "true" "true"

# ------------------------------------------------------------------------------
# 3. Instalación de Extensiones GNOME
# ------------------------------------------------------------------------------
echo "==> Verificando e instalando extensiones de GNOME Shell..."

# Dependencias requeridas para la descarga e instalación segura
EXT_DEPS=()
for bin in curl jq unzip; do
    if ! command -v "$bin" &>/dev/null; then
        EXT_DEPS+=("$bin")
    fi
done

if [[ ${#EXT_DEPS[@]} -gt 0 ]]; then
    echo "==> Instalando dependencias necesarias para gestionar extensiones: ${EXT_DEPS[*]}"
    sudo dnf install -y "${EXT_DEPS[@]}"
fi

GNOME_VERSION="$(gnome-shell --version 2>/dev/null | awk '{print $3}' | cut -d'.' -f1 || echo "")"
if [[ -z "$GNOME_VERSION" ]]; then
    echo "ADVERTENCIA: No se pudo determinar la versión mayor de GNOME Shell. Se asume compatibilidad."
fi

install_gnome_extension() {
    local uuid="$1"
    local pk="$2"
    local ext_dir="$HOME/.local/share/gnome-shell/extensions/$uuid"

    if [[ -d "$ext_dir" ]]; then
        echo "    ✔ Extensión ya instalada: $uuid"
        return 0
    fi

    echo "    ➜ Descargando e instalando extensión: $uuid (pk: $pk)..."

    local info_url="https://extensions.gnome.org/extension-info/?pk=${pk}"
    local json
    json="$(curl -sSL "$info_url" 2>/dev/null || true)"

    local download_url=""
    if [[ -n "$json" && "$json" != "null" ]]; then
        download_url="$(echo "$json" | jq -r '.download_url // empty' 2>/dev/null || true)"
    fi

    # Si la API por pk no devolvió la URL de descarga directa, consultar por UUID
    if [[ -z "$download_url" ]]; then
        local query_url="https://extensions.gnome.org/extension-query/?search=${uuid}"
        local query_json
        query_json="$(curl -sSL "$query_url" 2>/dev/null || true)"

        if [[ -n "$query_json" && "$query_json" != "null" ]]; then
            # Buscar coincidencia exacta por UUID y luego la versión compatible o la última disponible
            if [[ -n "$GNOME_VERSION" ]]; then
                download_url="$(echo "$query_json" | jq -r --arg uuid "$uuid" --arg gver "$GNOME_VERSION" '
                    .extensions[] | select(.uuid == $uuid) |
                    .shell_version_map[$gver].download_url // empty
                ' 2>/dev/null || true)"
            fi

            if [[ -z "$download_url" ]]; then
                # Tomar la versión más reciente registrada
                download_url="$(echo "$query_json" | jq -r --arg uuid "$uuid" '
                    .extensions[] | select(.uuid == $uuid) |
                    .shell_version_map | to_entries | last | .value.download_url // empty
                ' 2>/dev/null || true)"
            fi
        fi
    fi

    if [[ -z "$download_url" ]]; then
        echo "      ADVERTENCIA: No se pudo obtener la URL de descarga oficial para $uuid. Omitiendo." >&2
        return 0
    fi

    local full_url="https://extensions.gnome.org${download_url}"
    local tmp_zip
    tmp_zip="$(mktemp /tmp/gnome_ext_XXXXXX.zip)"

    if ! curl -sSL "$full_url" -o "$tmp_zip"; then
        echo "      ERROR: Falló la descarga de $full_url" >&2
        rm -f "$tmp_zip"
        return 0
    fi

    mkdir -p "$ext_dir"
    if unzip -q -o "$tmp_zip" -d "$ext_dir"; then
        echo "      ✔ Instalada correctamente en $ext_dir"
    else
        echo "      ERROR: Falló al descomprimir $tmp_zip en $ext_dir" >&2
        rm -rf "$ext_dir"
    fi
    rm -f "$tmp_zip"

    # Si la extensión incluye esquemas gsettings, compilarlos localmente
    if [[ -d "$ext_dir/schemas" ]]; then
        glib-compile-schemas "$ext_dir/schemas" 2>/dev/null || true
    fi
}

# Lista de extensiones requeridas por la estación
# UUIDs oficiales de extensions.gnome.org:
# - Alphabetical App Grid: AlphabeticalAppGrid@stuarthayhurst
# - Vitals: vitals@corecoding.com
# - Dash to Dock: dash-to-dock@micxgx.gmail.com
# - Tiling Shell: tilingshell@ferrarodomenico.com

install_gnome_extension "AlphabeticalAppGrid@stuarthayhurst" "11267"
install_gnome_extension "vitals@corecoding.com" "7419"
install_gnome_extension "dash-to-dock@micxgx.gmail.com" "4994"
install_gnome_extension "tilingshell@ferrarodomenico.com" "37573"

# ------------------------------------------------------------------------------
# 4. Habilitar extensiones deseadas y deshabilitar conflictivas
# ------------------------------------------------------------------------------
echo "==> Gestionando estado de extensiones habilitadas..."

enable_extension() {
    local uuid="$1"
    if command -v gnome-extensions &>/dev/null; then
        gnome-extensions enable "$uuid" 2>/dev/null || true
    fi

    # Asegurar que esté presente en enabled-extensions de gsettings
    local current
    current="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo "[]")"
    if [[ "$current" != *"$uuid"* ]]; then
        python3 -c "
import ast, subprocess
curr_str = '''$current'''
try:
    arr = ast.literal_eval(curr_str)
    if '$uuid' not in arr:
        arr.append('$uuid')
        subprocess.run(['gsettings', 'set', 'org.gnome.shell', 'enabled-extensions', str(arr)], check=True)
except Exception:
    pass
" 2>/dev/null || true
    fi
}

disable_extension() {
    local uuid="$1"
    if command -v gnome-extensions &>/dev/null; then
        gnome-extensions disable "$uuid" 2>/dev/null || true
    fi

    local current
    current="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo "[]")"
    if [[ "$current" == *"$uuid"* ]]; then
        python3 -c "
import ast, subprocess
curr_str = '''$current'''
try:
    arr = ast.literal_eval(curr_str)
    if '$uuid' in arr:
        arr = [x for x in arr if x != '$uuid']
        subprocess.run(['gsettings', 'set', 'org.gnome.shell', 'enabled-extensions', str(arr)], check=True)
except Exception:
    pass
" 2>/dev/null || true
    fi
}

# Habilitar extensiones principales
for ext in "AlphabeticalAppGrid@stuarthayhurst" "vitals@corecoding.com" "dash-to-dock@micxgx.gmail.com" "tilingshell@ferrarodomenico.com"; do
    enable_extension "$ext"
done

# Deshabilitar pop-shell si estuviera instalada/activa para evitar conflictos de tiling
disable_extension "pop-shell@system76.com"

# ------------------------------------------------------------------------------
# 5. Configuración de Dash to Dock
# ------------------------------------------------------------------------------
echo "==> Aplicando ajustes recomendados para Dash to Dock..."
D2D_SCHEMA="org.gnome.shell.extensions.dash-to-dock"

if gsettings list-schemas | grep -q "^${D2D_SCHEMA}$"; then
    gsettings_set_if_needed "$D2D_SCHEMA" dock-position "'BOTTOM'" "BOTTOM"
    gsettings_set_if_needed "$D2D_SCHEMA" dock-fixed "false" "false"
    gsettings_set_if_needed "$D2D_SCHEMA" autohide "true" "true"
    gsettings_set_if_needed "$D2D_SCHEMA" intellihide "true" "true"
    gsettings_set_if_needed "$D2D_SCHEMA" extend-height "false" "false"
    gsettings_set_if_needed "$D2D_SCHEMA" dash-max-icon-size "40" "40"
    gsettings_set_if_needed "$D2D_SCHEMA" show-trash-icon "false" "false"
    gsettings_set_if_needed "$D2D_SCHEMA" show-mounts "false" "false"
    echo "    ✔ Parámetros de Dash to Dock aplicados."
else
    echo "    (Esquema Dash to Dock aún no registrado en gsettings. Se aplicará al iniciar sesión con la extensión)."
fi

# ------------------------------------------------------------------------------
# 6. Configuración de Vitals
# ------------------------------------------------------------------------------
echo "==> Aplicando ajustes recomendados para Vitals..."
VITALS_SCHEMA="org.gnome.shell.extensions.vitals"

if gsettings list-schemas | grep -q "^${VITALS_SCHEMA}$"; then
    gsettings_set_if_needed "$VITALS_SCHEMA" update-time "3" "3"
    gsettings_set_if_needed "$VITALS_SCHEMA" show-battery "true" "true"
    gsettings_set_if_needed "$VITALS_SCHEMA" show-storage "true" "true"
    echo "    ✔ Parámetros de Vitals aplicados."
else
    echo "    (Esquema Vitals aún no registrado en gsettings. Se aplicará al iniciar sesión con la extensión)."
fi

echo "================================================================="
echo "==> Configuración de escritorio GNOME finalizada correctamente."
echo "    Nota: En extensiones recién instaladas, puede requerirse reiniciar"
echo "    la sesión gráfica para que GNOME Shell las active completamente."
echo "================================================================="
