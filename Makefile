# ==============================================================================
# Fedora Workstation - Aprovisionamiento Idempotente y Reproducible
# ==============================================================================

SHELL := /bin/bash
REPO_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# Variables de entorno para instalaciones desatendidas de Oh My Zsh
export RUNZSH=no
export CHSH=no
export KEEP_ZSHRC=yes

.PHONY: help install host shell containers devtools devai gitconfig github-auth desktop tooling snapper verify

help:
	@echo "Uso: make <target>"
	@echo ""
	@echo "Targets principales:"
	@echo "  make install      - Aprovisiona la workstation completa (host + shell + containers + devtools + devai)"
	@echo "  make host         - Verifica Btrfs, zRAM y Podman rootless; instala paquetes base (incl. podman-compose/docker)"
	@echo "  make shell        - Instala y configura Zsh, Oh My Zsh, plugins y enlace de ~/.zshrc"
	@echo "  make containers   - Instala devctl y crea el entorno Distrobox persistente 'debian-box' (Debian 13)"
	@echo "  make devtools     - Instala uv, fnm, SDKMAN, prepara GitHub CLI (SSH) e identidad de Git"
	@echo "  make devai        - Instala OpenCode CLI, Antigravity CLI y Antigravity desktop (opcional)"
	@echo "  make gitconfig    - Configura user.name/user.email globales (GIT_USER_NAME/GIT_USER_EMAIL o interactivo)"
	@echo "  make github-auth  - Ejecuta el flujo interactivo oficial de autenticación en GitHub CLI (gh auth login)"
	@echo "  make verify       - Ejecuta validaciones estáticas del repositorio y diagnóstico del entorno"
	@echo ""
	@echo "Targets opcionales (fuera de make install):"
	@echo "  make desktop      - Fuentes (JetBrains Mono, Noto Sans) y extensiones GNOME"
	@echo "  make tooling      - Editores (VS Code, Zed) y navegador"
	@echo "  make snapper      - Snapshots Btrfs de / con Snapper (solo si / es Btrfs)"

install: host shell containers devtools devai
	@echo ""
	@echo "==> Aprovisionamiento completado."
	@echo "    - Para autenticar GitHub CLI:   make github-auth"
	@echo "    - Para ingresar a Debian 13:    distrobox enter debian-box"
	@echo "    - Para verificar la estación:   make verify"

host:
	@echo "==> [1/5] Verificando y configurando paquetes base del host (Fedora)..."
	bash "$(REPO_DIR)/host/setup.sh"

shell:
	@echo "==> [2/5] Configurando Zsh, Oh My Zsh y dotfiles..."
	bash "$(REPO_DIR)/scripts/ohmyzsh.sh"

containers:
	@echo "==> [3/5] Configurando contenedores (Podman rootless + Distrobox debian-box)..."
	bash "$(REPO_DIR)/boxes/debian-box.sh"

devtools:
	@echo "==> [4/5] Configurando toolchains (uv, fnm, SDKMAN), GitHub CLI e identidad de Git..."
	bash "$(REPO_DIR)/scripts/devtools.sh"
	bash "$(REPO_DIR)/scripts/setup_gh.sh"
	bash "$(REPO_DIR)/scripts/setup_git.sh"

devai:
	@echo "==> [5/5] Configurando herramientas de IA (OpenCode, Antigravity)..."
	bash "$(REPO_DIR)/scripts/devai.sh"

gitconfig:
	@echo "==> Configurando identidad global de Git..."
	bash "$(REPO_DIR)/scripts/setup_git.sh"

github-auth:
	@echo "==> Autenticación interactiva con GitHub CLI..."
	bash "$(REPO_DIR)/scripts/setup_gh.sh" --auth

desktop:
	@echo "==> [Opcional] Configurando escritorio GNOME (fuentes y extensiones)..."
	bash "$(REPO_DIR)/scripts/desktop.sh"

tooling:
	@echo "==> [Opcional] Instalando editores y navegador..."
	bash "$(REPO_DIR)/scripts/tooling.sh"

snapper:
	@echo "==> [Opcional] Configurando Snapper para / (Btrfs)..."
	bash "$(REPO_DIR)/host/snapper.sh"

verify:
	@echo "==> Verificando repositorio y entorno..."
	bash "$(REPO_DIR)/scripts/verify.sh"
