# ==============================================================================
# Fedora Workstation - Dev Environment Setup
# ==============================================================================

# Forzar bash como shell para la ejecución
SHELL := /bin/bash

# Variables de entorno para instalaciones desatendidas
export RUNZSH=no
export CHSH=no

.PHONY: help install host shell containers clean

# Target por defecto: mostrar ayuda
help:
	@echo "Opciones de instalación:"
	@echo "  make install    - Aprovisiona la estación de trabajo completa (Host + Shell + Dev)"
	@echo "  make host       - Configura repositorios, DNF, paquetes base y Snapper"
	@echo "  make shell      - Configura Zsh, Oh My Zsh y copia dotfiles"
	@echo "  make containers - Prepara el entorno de contenedores (Distrobox/Podman)"
	@echo "  make clean      - Elimina archivos temporales de la instalación"

# El comando maestro
install: host shell containers
	@echo -e "\n✅ Instalación finalizada. Reinicia la terminal o el equipo para aplicar todos los cambios."

# Fase 1: Sistema y Host
host:
	@echo "==> Configurando Host (Fedora)..."
	bash host/setup.sh
	bash host/snapper.sh
	# Nota: Fedora usa zram nativo, esto se usa para evitar un eventual OOM
	bash host/swap.sh 

# Fase 2: Entorno de usuario (Shell y Dotfiles)
shell:
	@echo "==> Configurando Zsh y Dotfiles..."
	bash shell/ohmyzsh.sh
	# Crear enlaces simbólicos (symlinks) en lugar de copiar
	ln -sf $(PWD)/shell/zshrc $(HOME)/.zshrc
	ln -sf $(PWD)/shell/functions.sh $(HOME)/.functions.sh
	ln -sf $(PWD)/shell/gitconfig $(HOME)/.gitconfig

# Fase 3: Tooling y Contenedores
containers:
	@echo "==> Configurando contenedores y Devctl..."
	# Asumiendo que devctl gestiona los boxes
	chmod +x devctl
	./devctl setup
	# Instalación de uv
	curl -LsSf https://astral.sh/uv/install.sh | sh

# Utilidad para limpiar restos si algo falla
clean:
	@echo "==> Limpiando..."
	rm -rf $(HOME)/.oh-my-zsh.tmp || true
