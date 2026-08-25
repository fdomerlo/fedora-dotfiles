#!/bin/bash

# Terminar inmediatamente si ocurre un error, falla un pipe, o si hay variables sin definir
set -euo pipefail

# --- CONFIGURACIÓN ---
DIR_DESCARGAS="$HOME/Descargas"
ARCHIVO_APP="$DIR_DESCARGAS/Antigravity.tar.gz"
#ARCHIVO_IDE="$DIR_DESCARGAS/Antigravity IDE.tar.gz"

SUBDIR_APP="Antigravity-x64"
#SUBDIR_IDE="Antigravity IDE"

BIN_APP="antigravity"
#BIN_IDE="antigravity-ide"

# Capturar el usuario actual para la corrección de permisos
USUARIO_ACTUAL=$(whoami)
GRUPO_ACTUAL=$(id -g -n)
# --------------------------------------------

echo "=== Iniciando despliegue local de Antigravity ==="

# 1. Validar existencia de archivos locales
#if [[ ! -f "$ARCHIVO_APP" ]] || [[ ! -f "$ARCHIVO_IDE" ]]; then
if [[ ! -f "$ARCHIVO_APP" ]]; then
    echo "[-] Error: Los archivos comprimidos no se encuentran en $DIR_DESCARGAS."
    exit 1
fi

# Banderas de estado
ACTUALIZAR_APP=false
#ACTUALIZAR_IDE=false

# 2. Lógica de Idempotencia Local
if [[ ! -d "/opt/$SUBDIR_APP" ]] || [[ "$ARCHIVO_APP" -nt "/opt/$SUBDIR_APP" ]]; then
    ACTUALIZAR_APP=true
fi

#if [[ ! -d "/opt/$SUBDIR_IDE" ]] || [[ "$ARCHIVO_IDE" -nt "/opt/$SUBDIR_IDE" ]]; then
#    ACTUALIZAR_IDE=true
#fi

# 3. Extracción y Permisos
#if [[ "$ACTUALIZAR_APP" == false ]] && [[ "$ACTUALIZAR_IDE" == false ]]; then
if [[ "$ACTUALIZAR_APP" == false ]]; then
    echo "[1/4] La instalación en /opt/ está actualizada. Omitiendo extracción."
else
    echo "[1/4] Extrayendo y corrigiendo permisos de las aplicaciones principales..."
    
    if [[ "$ACTUALIZAR_APP" == true ]]; then
        echo "  -> Procesando Antigravity Core..."
        sudo rm -rf "/opt/$SUBDIR_APP"
        sudo tar -xzf "$ARCHIVO_APP" -C /opt/
        sudo chown -R "$USUARIO_ACTUAL:$GRUPO_ACTUAL" "/opt/$SUBDIR_APP"
        sudo touch "/opt/$SUBDIR_APP"
    fi

    #if [[ "$ACTUALIZAR_IDE" == true ]]; then
    #    echo "  -> Procesando Antigravity IDE..."
    #    sudo rm -rf "/opt/$SUBDIR_IDE"
    #    sudo tar -xzf "$ARCHIVO_IDE" -C /opt/
    #    sudo chown -R "$USUARIO_ACTUAL:$GRUPO_ACTUAL" "/opt/$SUBDIR_IDE"
    #    sudo touch "/opt/$SUBDIR_IDE"
    #fi
fi

# 4. Instalación / Actualización del CLI remoto
echo "[2/4] Ejecutando script de instalación remoto para Antigravity CLI..."
# Se asume que install.sh maneja su propia idempotencia y permisos.
curl -fsSL https://antigravity.google/cli/install.sh | bash

# 5. Reparación/Creación de Enlaces Simbólicos
echo "[3/4] Verificando enlaces simbólicos globales en /usr/local/bin/..."
sudo ln -sf "/opt/$SUBDIR_APP/$BIN_APP" /usr/local/bin/antigravity
#sudo ln -sf "/opt/$SUBDIR_IDE/$BIN_IDE" /usr/local/bin/antigravity-ide

# 6. Entradas de Escritorio (Desktop Entries)
echo "[4/4] Garantizando integridad de archivos .desktop y Dash..."

sudo bash -c "cat <<EOF > /usr/share/applications/antigravity.desktop
[Desktop Entry]
Name=Antigravity 2.0
Comment=Orquestación asíncrona de agentes autónomos
Exec=/usr/local/bin/antigravity
Icon=$HOME/.dotfiles/scripts/antigravity.png
Type=Application
Terminal=false
Categories=Development;
EOF"

#sudo bash -c "cat <<EOF > /usr/share/applications/antigravity-ide.desktop
#[Desktop Entry]
#Name=Antigravity IDE
#Comment=Entorno de desarrollo tradicional
#Exec=/usr/local/bin/antigravity-ide
#Icon=$HOME/.dotfiles/scripts/antigravity-ide.png
#Type=Application
#Terminal=false
#Categories=Development;IDE;
#EOF"

sudo update-desktop-database /usr/share/applications/

echo "=== Proceso finalizado ==="
