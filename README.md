![status](https://img.shields.io/badge/status-active-success)
![platform](https://img.shields.io/badge/platform-fedora-blue)
![shell](https://img.shields.io/badge/shell-zsh-green)

# Fedora Workstation Dotfiles

Aprovisionamiento **simple, idempotente, seguro y reproducible** para una estación de trabajo Fedora Workstation orientada a desarrollo de software, administración de sistemas y trabajo con herramientas de IA.

## Instalación rápida

En una instalación limpia de Fedora Workstation:

```bash
sudo dnf install -y git make
git clone https://github.com/fdomerlo/fedora-dotfiles.git ~/.dotfiles
cd ~/.dotfiles
GIT_USER_NAME="Tu Nombre" GIT_USER_EMAIL="tu@email" make install
```

Si no definís `GIT_USER_NAME` / `GIT_USER_EMAIL`, `make install` pregunta la identidad de Git de forma interactiva (o la omite con una advertencia si no hay terminal). Nunca sobrescribe valores ya configurados.

Pasos posteriores (separados para no bloquear `make install`):

```bash
make github-auth   # Inicia sesión en GitHub CLI (SSH)
make verify        # Valida el repositorio y diagnostica la estación
```

Pasos opcionales:

```bash
make desktop       # Fuentes y extensiones GNOME
make tooling       # VS Code, Google Chrome y Zed
make snapper       # Snapshots Btrfs de / con Snapper
```

---

## Targets del Makefile

### Flujo principal (`make install`)

| Target | Descripción |
|--------|-------------|
| `make install` | Ejecuta `host` → `shell` → `containers` → `devtools` → `devai` |
| `make host` | Verifica Fedora, Btrfs, zRAM y Podman rootless; instala los paquetes base faltantes (`git`, `curl`, `wget`, `jq`, `zip`, `unzip`, `podman`, `podman-compose`, `podman-docker`, `distrobox` y `btrfs-progs` si corresponde) y habilita el socket rootless de Podman |
| `make shell` | Instala Zsh, Oh My Zsh, `zsh-autosuggestions` y `zsh-syntax-highlighting`; enlaza `~/.zshrc` (respalda el previo en `~/.zshrc.pre-dotfiles`) |
| `make containers` | Enlaza `devctl` en `~/.local/bin` y crea `debian-box` (Debian 13) si no existe |
| `make devtools` | Instala `uv`, `fnm` y SDKMAN; prepara GitHub CLI (`git_protocol=ssh`) y la identidad global de Git |
| `make devai` | Instala OpenCode CLI y Antigravity CLI si faltan; despliega Antigravity desktop si hay un paquete local |

### Utilidades

| Target | Descripción |
|--------|-------------|
| `make help` | Muestra la ayuda |
| `make gitconfig` | Configura `user.name` / `user.email` y `init.defaultBranch=main` si faltan |
| `make github-auth` | Ejecuta `gh auth login -h github.com -p ssh` si no hay sesión activa |
| `make verify` | Validación estática (`bash -n`, `zsh -n`, ShellCheck si está instalado, datos personales, comandos prohibidos) y diagnóstico no destructivo del entorno |

### Opcionales (fuera de `make install`)

| Target | Descripción |
|--------|-------------|
| `make desktop` | Instala JetBrains Mono y Noto Sans si faltan, configura las tipografías e instala/habilita las extensiones GNOME |
| `make tooling` | Configura los repositorios oficiales e instala Visual Studio Code y Google Chrome; instala Zed con su instalador oficial |
| `make snapper` | Configura Snapper para `/` (solo en Btrfs) con retención conservadora, sin cuotas Btrfs y con snapshots automáticos pre/post transacción de DNF |

---

## Estructura del repositorio

```text
host/
├── setup.sh              # Fedora, Btrfs, zRAM, Podman rootless, paquetes base y socket de Podman
└── snapper.sh            # Opcional (make snapper): snapshots Btrfs de /

boxes/
└── debian-box.sh         # Creación idempotente del Distrobox 'debian-box' (Debian 13)

shell/
├── zshrc                 # Zsh + Oh My Zsh, PATH deduplicado, fnm, SDKMAN y prompt con indicador de contenedor
└── devctl                # CLI para Distrobox y diagnóstico

scripts/
├── ohmyzsh.sh            # Zsh, Oh My Zsh, plugins y enlace de ~/.zshrc
├── devtools.sh           # uv, fnm y SDKMAN
├── setup_gh.sh           # GitHub CLI (SSH) y autenticación interactiva (--auth)
├── setup_git.sh          # Identidad global de Git sin datos versionados
├── devai.sh              # OpenCode CLI y Antigravity CLI
├── setup_agy.sh          # Despliegue seguro de Antigravity desktop en /opt
├── verify.sh             # Validación del repositorio y diagnóstico del sistema
├── desktop.sh            # Opcional (make desktop): fuentes y extensiones GNOME
├── tooling.sh            # Opcional (make tooling): VS Code, Google Chrome y Zed
└── antigravity.png       # Ícono de la entrada de escritorio de Antigravity

.gitattributes            # Fuerza finales de línea LF
Makefile                  # Orquestación del aprovisionamiento
```

---

## Contenedores

### Distrobox `debian-box`

Usa la imagen oficial `docker.io/library/debian:13` sobre Podman rootless y comparte `$HOME`, de modo que los repositorios y toolchains del host están disponibles sin duplicarlos.

```bash
distrobox list
distrobox enter debian-box
```

`make install` nunca destruye, recrea ni actualiza `debian-box`. Para actualizarlo explícitamente:

```bash
distrobox upgrade debian-box
```

### Compatibilidad con Docker

- `podman-docker` provee el comando `docker` (redirige a Podman).
- `podman-compose` ejecuta archivos `compose.yaml` / `docker-compose.yml`.
- El socket rootless (`systemctl --user` → `podman.socket`) se activa por demanda. Para herramientas que lo requieren:

```bash
export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/podman/podman.sock"
```

> **Nota:** `podman-docker` entra en conflicto con Docker CE (`docker-ce` / `moby-engine`); no instales ambos.

---

## CLI `devctl`

Se enlaza en `~/.local/bin/devctl` con `make containers`.

```bash
devctl box create [nombre]     # Crea el Distrobox (por defecto: debian-box) si no existe
devctl box enter [nombre]      # Ingresa al Distrobox
devctl box list                # Lista los Distrobox
devctl doctor                  # Ejecuta scripts/verify.sh
```

---

## Toolchains y runtimes

Los gestores se instalan una sola vez (versión estable vigente) y se integran en `shell/zshrc` sin que sus instaladores modifiquen `~/.zshrc`:

- **Python (`uv`):** `uv python install <versión>` / `uv venv`
- **Node.js (`fnm`):** `fnm install --lts` / `fnm use --lts` (cambio automático por directorio con `--use-on-cd`)
- **Java / JVM (`SDKMAN`):** `sdk list java` / `sdk install java <identificador>`

---

## Herramientas de IA

- **OpenCode CLI** y **Antigravity CLI** se instalan solo si no están presentes. Si un instalador intenta agregar rutas a `~/.zshrc`, el cambio se revierte (el `PATH` ya está gestionado en `shell/zshrc`).
- **Antigravity desktop (`scripts/setup_agy.sh`)** es opcional. Si existe `~/Descargas/Antigravity.tar.gz` (o `~/Downloads/Antigravity.tar.gz`), valida el archivo, lo extrae en un directorio temporal, verifica el binario y reemplaza `/opt/Antigravity-x64` conservando un respaldo hasta completar el reemplazo. No borra el archivo descargado. Si no hay paquete, `make install` continúa.

---

## Git y GitHub CLI

- `scripts/setup_git.sh` completa `user.name`, `user.email` e `init.defaultBranch` solo si faltan.
- `scripts/setup_gh.sh` instala `gh` si falta y configura `git_protocol=ssh`. No genera claves SSH, no desactiva `StrictHostKeyChecking` y no modifica la identidad de Git.
- `make github-auth` inicia el flujo oficial de login; `gh` ofrece generar y subir una clave SSH durante ese proceso.

---

## Escritorio GNOME (`make desktop`)

- **Tipografías:** interfaz Adwaita Sans 11, documentos Noto Sans 12, monoespaciada JetBrains Mono 11 (las fuentes se instalan si faltan).
- **Extensiones:** Alphabetical App Grid, Vitals, Dash to Dock y Tiling Shell. Se instalan desde extensions.gnome.org si no están presentes y se habilitan; Pop Shell se deshabilita para evitar conflictos de tiling.

Puede ser necesario cerrar sesión para que GNOME Shell cargue extensiones nuevas.

---

## Snapper (`make snapper`)

Solo actúa si `/` está en Btrfs. Crea la configuración `root` si no existe, aplica una retención conservadora (3 horarias, 3 diarias, 1 semanal, 6 por número, 2 importantes), no habilita cuotas Btrfs y activa `snapper-timeline.timer` y `snapper-cleanup.timer`.

Además, integra **snapshots automáticos pre/post transacción de DNF**:
- **DNF5 (Fedora 41+):** instala `libdnf5-plugin-actions` y escribe `/etc/dnf/libdnf5-plugins/actions.d/snapper.actions` con el algoritmo de limpieza `number` (`-c number`) para que `NUMBER_LIMIT` los depure automáticamente.
- **DNF4:** instala `python3-dnf-plugin-snapper`.

```bash
sudo snapper -c root list
```
