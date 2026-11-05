![status](https://img.shields.io/badge/status-active-success)
![platform](https://img.shields.io/badge/platform-fedora-blue)
![shell](https://img.shields.io/badge/shell-zsh-green)

# Fedora Workstation Dotfiles

Aprovisionamiento **simple, idempotente, seguro y reproducible** para una estación de trabajo Fedora Workstation orientada a desarrollo de software, administración de sistemas y trabajo con herramientas de IA.

## Principios de diseño

1. **Cero escrituras innecesarias en almacenamiento:** no se ejecutan `dnf upgrade`, `dnf autoremove`, `dnf clean all` ni `git pull` automáticos en cada aprovisionamiento; solo se instalan paquetes o herramientas ausentes.
2. **Respeto por los valores predeterminados de Fedora:** se conserva la configuración nativa de **zRAM** (`zram-generator`) sin crear swapfiles de disco ni alterar parámetros `vm.*` de `sysctl`, y se mantiene **Podman rootless** con su driver y compresión Btrfs nativa (`zstd:1` y checksums activos) sin aplicar `chattr +C` ni cambios recursivos de permisos sobre `~/.local`.
3. **Compatibilidad con servidores Debian mediante Distrobox:** se aprovisiona un contenedor persistente `debian-work` basado en la imagen oficial `docker.io/library/debian:13` ejecutado sobre Podman rootless.
4. **Idempotencia y portabilidad:** todas las rutas se basan en `$HOME`, `PATH` se deduplica en Zsh (`typeset -U path PATH`) y se fija la versión estable disponible al momento de la primera instalación sin sobrescribir ni actualizar instalaciones existentes durante `make install`.

---

## Instalación rápida

En una instalación limpia de Fedora Workstation:

```bash
sudo dnf install -y git make
git clone https://github.com/fdomerlo/fedora-dotfiles.git ~/.dotfiles
cd ~/.dotfiles
GIT_USER_NAME="Tu Nombre" GIT_USER_EMAIL="tu@email" make install
```

Si no definís `GIT_USER_NAME` / `GIT_USER_EMAIL`, `make install` pregunta la identidad de Git de forma interactiva (o la omite con una advertencia si no hay terminal). Nunca sobrescribe valores ya configurados.

Para autenticar GitHub CLI de forma interactiva (paso separado que no bloquea `make install`):

```bash
make github-auth
```

Para verificar la estación de trabajo y validar el repositorio:

```bash
make verify
```

---

## Targets del Makefile

| Target | Descripción |
|--------|-------------|
| `make help` | Muestra la ayuda con los targets disponibles |
| `make install` | Aprovisiona la workstation completa (`host` + `shell` + `containers` + `devtools` + `devai`) |
| `make host` | Verifica Fedora, Btrfs, zRAM y Podman rootless; instala únicamente los paquetes base faltantes |
| `make shell` | Instala y configura Zsh, Oh My Zsh, `zsh-autosuggestions`, `zsh-syntax-highlighting` y enlaza `~/.zshrc` |
| `make containers` | Instala `devctl` en `~/.local/bin` y crea el contenedor Distrobox persistente `debian-work` (Debian 13) si no existe |
| `make devtools` | Instala `uv`, `fnm`, SDKMAN, configura GitHub CLI (`gh`) con protocolo SSH y la identidad global de Git |
| `make devai` | Instala OpenCode CLI, Antigravity CLI y (opcionalmente) Antigravity desktop si existe el paquete local |
| `make gitconfig` | Configura `user.name` / `user.email` globales si faltan (desde `GIT_USER_NAME` / `GIT_USER_EMAIL` o de forma interactiva) |
| `make github-auth` | Ejecuta el flujo interactivo oficial `gh auth login -h github.com -p ssh` |
| `make verify` | Ejecuta validaciones estáticas (`bash -n`, referencias, portabilidad) y diagnóstico no destructivo del entorno |
| `make desktop` | *(Opcional)* Instala fuentes faltantes (Fira Code, Noto Sans), las aplica y configura extensiones GNOME |
| `make tooling` | *(Opcional)* Instala VS Code, Zed y navegador |

> **Nota:** `make install` no ejecuta actualizaciones masivas del sistema (`dnf upgrade`), limpiezas de caché (`dnf autoremove` / `dnf clean all`), Snapper, creación de swapfiles, ni personalizaciones cosméticas de escritorio GNOME.

---

## Estructura del repositorio

```text
host/
└── setup.sh              # Verificación de Fedora, Btrfs, zRAM, Podman rootless y paquetes base

boxes/
└── debian-work.sh        # Creación idempotente del entorno Distrobox persistente 'debian-work' (Debian 13)

shell/
├── zshrc                 # Configuración portable de Zsh, Oh My Zsh, PATH deduplicado y toolchains
└── devctl                # Utilidad CLI para contenedores Distrobox, diagnóstico y plantillas

scripts/
├── ohmyzsh.sh            # Instalación idempotente de Zsh, Oh My Zsh y plugins
├── devtools.sh           # Instalación idempotente de uv, fnm y SDKMAN
├── setup_git.sh          # Identidad global de Git (user.name / user.email) sin datos versionados
├── setup_gh.sh           # Preparación de GitHub CLI (SSH) y autenticación interactiva separada
├── devai.sh              # Instalación idempotente de OpenCode CLI y Antigravity CLI
├── setup_agy.sh          # Despliegue local seguro (staging + validación) de Antigravity desktop en /opt
├── verify.sh             # Validación estática del repositorio y diagnóstico del sistema
├── desktop.sh            # Opcional (make desktop): fuentes y extensiones GNOME
└── tooling.sh            # Opcional (make tooling): editores y navegador

templates/django/
└── manage.sh             # Inicializador de proyectos Django con uv

.envrc.template           # Plantilla direnv para entornos virtuales Python
Makefile                  # Orquestación principal del aprovisionamiento
```

---

## Uso de Distrobox (`debian-work`)

El contenedor `debian-work` utiliza la imagen oficial de Debian estable (`docker.io/library/debian:13`) sobre Podman rootless y comparte el directorio `$HOME` del usuario, permitiendo acceder a los repositorios de trabajo y a los toolchains administrados en el host sin duplicarlos dentro del contenedor.

### Listar contenedores Distrobox

```bash
distrobox list
```

### Ingresar al entorno Debian

```bash
distrobox enter debian-work
```

### Actualizar el entorno Debian manualmente

`make install` nunca destruye, recrea ni actualiza automáticamente `debian-work`. Cuando desees actualizar los paquetes internos del contenedor Debian de forma explícita:

```bash
distrobox upgrade debian-work
# o desde dentro del contenedor:
distrobox enter debian-work -- sudo apt update && sudo apt upgrade -y
```

---

## Toolchains y Runtimes

Los gestores de versiones se instalan en su versión estable disponible al momento del primer aprovisionamiento y quedan integrados en `shell/zshrc`:

- **Python (`uv`):** `uv python install <version>` / `uv venv`
- **Node.js (`fnm`):** `fnm install --lts` / `fnm use --lts`
- **Java / JVM (`SDKMAN`):** `sdk list java` / `sdk install java <identifier>`

---

## Herramientas de IA

- **OpenCode CLI** y **Antigravity CLI** se instalan únicamente si no están presentes en el sistema.
- **Antigravity Desktop (`scripts/setup_agy.sh`):** componente opcional. Si `~/Descargas/Antigravity.tar.gz` (o `~/Downloads/Antigravity.tar.gz`) está presente, valida la integridad del archivo, extrae en un directorio temporal en `/opt`, verifica el binario ejecutable y realiza un reemplazo controlado en `/opt/Antigravity-x64` sin eliminar el archivo descargado por el usuario. Si el archivo no existe, `make install` continúa sin bloquearse.

---

## GitHub CLI (`gh`)

Durante `make install`, `scripts/setup_gh.sh` verifica que `gh` esté instalado, configura `git_protocol=ssh` y comprueba el estado de la sesión sin generar claves SSH automáticamente, sin desactivar `StrictHostKeyChecking` y sin sobrescribir `user.name` o `user.email` en la configuración global de Git (la identidad se gestiona en `scripts/setup_git.sh`, que solo completa valores ausentes).

Para iniciar sesión cuando sea necesario:

```bash
make github-auth
```
