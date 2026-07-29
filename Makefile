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
	@echo "  make install    - Aprovisiona la estación de trabajo completa (host + shell + devtools + devai + containers)"
	@echo "  make host       - Configura repositorios, DNF, paquetes base, Snapper y devtools"
	@echo "  make shell      - Configura Zsh, Oh My Zsh y copia dotfiles"
	@echo "  make devtools   - Instala herramientas de desarrollo y gestores de paquetes"
	@echo "  make devai      - Instala herramientas de inteligencia artificial"
	@echo "  make containers - Prepara el entorno de contenedores (Distrobox/Podman)"
	@echo "  make clean      - Elimina archivos temporales de la instalación"

# El comando maestro (Se ejecuta como usuario NORMAL)
install: host shell devtools devai containers clean
	@echo -e "\n✅ Instalación finalizada. Reinicia la terminal o el equipo para aplicar todos los cambios."

# Sistema y Host (Pedirá sudo de manera selectiva)
host:
	@echo "==> Configurando Host (Fedora)..."
	sudo bash host/setup.sh
	sudo bash host/snapper.sh
	sudo bash host/swap.sh 

# Entorno de usuario (Shell y Dotfiles)
shell:
	@echo "==> Configurando Zsh y Dotfiles..."
	bash scripts/ohmyzsh.sh
	ln -sf $(PWD)/shell/zshrc $(HOME)/.zshrc
	ln -sf $(PWD)/shell/gitconfig $(HOME)/.gitconfig

# Entorno de desarrollo
devtools:
	@echo "==> Instalando devtools..."
	bash scripts/devtools.sh
	bash scripts/setup_gh.sh
		
# Entornos AI 
devai:
	@echo "==> Instalando herramientas de AI..."
	curl -fsSL https://opencode.ai/install | bash
	curl -fsSL https://antigravity.google/cli/install.sh | bash
	bash scripts/setup_agy.sh

# Tooling y Contenedores
containers:
	@echo "==> Preparando entorno de contenedores..."
	chmod +x shell/devctl
	mkdir -p $(HOME)/.local/bin
	ln -sf $(PWD)/shell/devctl $(HOME)/.local/bin/devctl

	@echo "Devctl listo. Usa:"
	@echo "  ./devctl box create php"
	@echo "  ./devctl box create python"

# Utilidad para limpiar restos si algo falla
clean:
	@echo "==> Limpiando caches y residuales..."
	sudo dnf autoremove -y
	sudo dnf clean all
	rm -rf $(HOME)/.oh-my-zsh.tmp || true
