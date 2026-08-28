# ==============================================================================
# Fedora Workstation - Dev Environment Setup
# ==============================================================================

# Forzar bash como shell para la ejecución
SHELL := /bin/bash

# Variables de entorno para instalaciones desatendidas
export RUNZSH=no
export CHSH=no

.PHONY: help install host shell containers devtools tooling devai clean

# Target por defecto: mostrar ayuda
help:
	@echo "Opciones de instalación:"
	@echo "  make install    - Aprovisiona la estación de trabajo completa (host + shell + devtools + devai + containers)"
	@echo "  make host       - Configura repositorios, DNF, paquetes base, Snapper y devtools"
	@echo "  make shell      - Configura Zsh, Oh My Zsh y copia dotfiles"
	@echo "  make containers - Prepara el entorno de contenedores (Distrobox/Podman)"
	@echo "  make devtools   - Instala herramientas de desarrollo y gestores de paquetes"
	@echo "  make tooling    - Instala navegadores y editores de código"
	@echo "  make devai      - Instala herramientas de inteligencia artificial"
	@echo "  make clean      - Elimina archivos temporales de la instalación"

# El comando maestro (Se ejecuta como usuario NORMAL)
install: host shell devtools devai containers tooling clean
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

# Tooling y Contenedores
containers:
	@echo "==> Preparando entorno de contenedores..."
	chmod +x shell/devctl
	mkdir -p $(HOME)/.local/bin
	ln -sf $(PWD)/shell/devctl $(HOME)/.local/bin/devctl

	@echo "Devctl listo. Usa:"
	@echo "  ./devctl box create php"
	@echo "  ./devctl box create python"

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
	curl -fsSL https://claude.ai/install.sh | bash
	bash scripts/setup_agy.sh

# Tooling
tooling:
	sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc &&
	echo -e "[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\nautorefresh=1\ntype=rpm-md\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc" | sudo tee /etc/yum.repos.d/vscode.repo > /dev/null
	sudo dnf check-update
	sudo dnf install code
	curl -f https://zed.dev/install.sh | sh
	sudo dnf install google-chrome-stable	

# Utilidad para limpiar restos si algo falla
clean:
	@echo "==> Limpiando caches y residuales..."
	sudo dnf autoremove -y
	sudo dnf clean all
	rm -rf $(HOME)/.oh-my-zsh.tmp || true
