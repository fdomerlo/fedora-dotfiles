![status](https://img.shields.io/badge/status-active-success)
![platform](https://img.shields.io/badge/platform-linux-blue)
![shell](https://img.shields.io/badge/shell-zsh-green)

# Dotfiles

Aprovisionamiento automatizado de una estación de trabajo Fedora para desarrollo, con contenedores Distrobox, tooling de IA y configuración de Zsh.

## Instalación (one-command)

```bash
sudo dnf install -y git make && rm -r ~/.dotfiles \
git clone https://github.com/fdomerlo/fedora-dotfiles.git ~/.dotfiles && \
cd ~/.dotfiles \
make -C help
```

## Makefile Targets

| Target | Descripción |
|--------|-------------|
| `make install` | Aprovisionamiento completo (host + shell + devtools + devai + containers) |
| `make host` | Paquetes base, Podman, Distrobox, BTRFS, Snapper, swap |
| `make shell` | Zsh, Oh My Zsh, plugins, `.zshrc`, `.gitconfig` |
| `make devtools` | gh, uv, fnm, SDKMAN |
| `make devai` | OpenCode CLI, Antigravity CLI, Antigravity Core + IDE |
| `make containers` | Instala `devctl` en `~/.local/bin` |
| `make clean` | Limpieza de caches y residuales |

## Estructura del repositorio

```
host/              # Scripts de sistema (requieren sudo)
├── setup.sh       #   Paquetes base: git, podman, distrobox, snapper, btrfs
├── snapper.sh     #   Configura Snapper con timeline BTRFS
└── swap.sh        #   Swapfile de 4GB + swappiness 10

shell/             # Dotfiles y CLI
├── zshrc          #   Configuración Zsh con Oh My Zsh, fnm, SDKMAN, prompt
├── gitconfig      #   Configuración global de git
└── devctl         #   CLI para boxes Distrobox y proyectos

scripts/           # Instaladores
├── ohmyzsh.sh     #   Instala Zsh, Oh My Zsh y plugins
├── devtools.sh    #   Instala gh, uv, fnm, SDKMAN
├── setup_gh.sh    #   Configura SSH con GitHub (clave + login automático)
└── setup_agy.sh   #   Despliega Antigravity Core + IDE en /opt/

boxes/python/      # Definición del contenedor Python
├── Dockerfile     #   Basado en Debian testing con Python + uv
└── init.sh        #   Init: Node.js LTS + CLIs de IA (claude, gemini, opencode)

templates/django/  # Template de proyecto Django
└── manage.sh      #   Crea venv, instala Django, startproject + migrate

.envrc.template    # Template direnv para proyectos Python
```

## CLI devctl

`devctl` se instala via `make containers` como symlink en `~/.local/bin/devctl`.

```bash
devctl box build python      # Construye imagen Podman desde boxes/python/Dockerfile
devctl box create python     # Crea contenedor Distrobox
devctl box enter python      # Entra al contenedor
devctl box rebuild python    # Reconstruye imagen y contenedor desde cero
devctl box export python     # Exporta imagen a tarball
devctl box import file.tar   # Importa imagen desde tarball

devctl project init django   # Inicializa proyecto Django con template

devctl doctor                # Diagnóstico: dependencias, swap, zram, boxes
devctl upgrade               # Pull + rebuild de boxes
```

## Scripts de aprovisionamiento destacados

### `host/setup.sh`
Instala los paquetes base del sistema: git, curl, wget, Fira Code fonts, Podman, Podman Compose, Distrobox, herramientas BTRFS y Snapper. Habilita `podman.socket`.

### `host/snapper.sh`
Configura Snapper para el subvolumen `/` con timeline: 5 hourly, 7 daily, 4 weekly snapshots. Habilita los timers de timeline y cleanup.

### `host/swap.sh`
Crea un swapfile de 4GB, lo activa, lo añade a `/etc/fstab`, y ajusta `vm.swappiness=10` para favorecer zram como swap primario.

### `scripts/ohmyzsh.sh`
Instala Zsh (si falta), cambia el shell por defecto a Zsh via `chsh`, instala Oh My Zsh y los plugins `zsh-autosuggestions` y `zsh-syntax-highlighting`.

### `scripts/devtools.sh`
Instala GitHub CLI (`gh`), uv (gestor de Python), fnm (gestor de Node.js) y SDKMAN (gestor de Java/JVM).

### `scripts/setup_gh.sh`
Automatiza la configuración SSH con GitHub:
1. Autentica `gh` con scope `admin:public_key`
2. Detecta usuario y email vía API de GitHub
3. Genera clave ed25519 (idempotente)
4. Sube la clave pública a GitHub si no está registrada
5. Configura `git config --global user` automáticamente
6. Verifica conexión SSH

### `scripts/setup_agy.sh`
Despliega Antigravity Core y Antigravity IDE desde tarballs en `~/Descargas`:
1. Extrae a `/opt/` con permisos correctos
2. Instala Antigravity CLI via script remoto
3. Crea symlinks en `/usr/local/bin/`
4. Genera entradas `.desktop` y actualiza la base de datos

## Box: Python

Entorno de desarrollo Python basado en Debian testing con:
- Python 3, pip, venv
- uv (gestor de paquetes Python)
- fnm + Node.js LTS
- CLIs de IA: Claude Code, Gemini CLI, OpenCode

```bash
make containers
devctl box build python
devctl box create python
devctl box enter python
```

## Template: Django

Inicializa un proyecto Django dentro del directorio actual:

```bash
devctl project init django
direnv allow
```

Esto copia `manage.sh`, que crea un virtualenv con uv, instala Django y ejecuta `startproject` + `migrate`.
