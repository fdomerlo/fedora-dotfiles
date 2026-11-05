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
make snapper       # Snapshots Btrfs, arranque desde GRUB y rollback permanente
```

---

## Targets del Makefile

### Flujo principal (`make install`)

| Target | Descripción |
|--------|-------------|
| `make install` | Ejecuta `host` → `shell` → `containers` → `devtools` → `devai` |
| `make host` | Verifica Fedora, Btrfs, zRAM y Podman rootless; instala los paquetes base faltantes (`git`, `curl`, `wget`, `jq`, `zip`, `unzip`, `podman`, `podman-compose`, `podman-docker`, `distrobox`, `policycoreutils-python-utils` y `btrfs-progs` si corresponde), habilita el socket rootless de Podman y ejecuta la configuración de swap/hibernación/oomd |
| `make power` | Reconfigura de forma idempotente el swapfile Btrfs, la hibernación, los módulos de dracut, swappiness y systemd-oomd |
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
| `make snapper` | Configura Snapper para `/` (solo en Btrfs) con layout top-level, retención conservadora, snapshots automáticos pre/post transacción de DNF, arranque de snapshots desde GRUB con grub-btrfs y el helper de rollback permanente |

---

## Estructura del repositorio

```text
host/
├── setup.sh              # Fedora, Btrfs, zRAM, Podman rootless, paquetes base y socket de Podman
├── power.sh              # Swapfile Btrfs, hibernación, dracut, swappiness y systemd-oomd
├── snapper.sh            # Opcional (make snapper): snapshots, grub-btrfs y helper de rollback
└── snapper-rollback.sh   # Rollback permanente a un snapshot (se instala en /usr/local/sbin)

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

## Swap, hibernación y presión de memoria (`make power`)

`make host` ejecuta `host/power.sh` después de los paquetes base. El script:

- Mantiene **zRAM como swap L1** (prioridad 100) y agrega **`/swap/swapfile` como L2** (prioridad 10) sobre el subvolumen top-level `swap`.
- Calcula el tamaño del swapfile según la RAM instalada:
  - `≥ 8 GiB`: `ceil(RAM_GiB) + 1`.
  - `2–8 GiB`: `ceil(1.5 × RAM_GiB)`.
  - `< 2 GiB`: `2 × RAM_GiB`.
  - Se puede forzar con `SWAP_GIB=<n> make power`.
- Configura la hibernación con el mecanismo UEFI de systemd (sin `resume=`/`resume_offset=` manuales), agrega los módulos `resume` y `overlayfs` a dracut y ajusta `/sys/power/image_size`.
- Etiqueta SELinux: `/swap` como `var_t` y `/swap/swapfile` como `swapfile_t`. `systemd-logind` necesita permiso de `search` sobre el directorio; si queda `unlabeled_t`, la hibernación falla con `Access denied` incluso como root.
- Aplica `vm.swappiness=100`, `vm.page-cluster=0` y ajusta `systemd-oomd` (`SwapUsedLimit=50%`, presión sostenida 10 s).

Para probar la hibernación:

```bash
sudo systemctl hibernate
# Al volver:
journalctl -b -u systemd-hibernate.service
```

Si el swapfile ya existe pero es más chico que el calculado, el script avisa y no lo toca. Para recrearlo:

```bash
make power SWAP_GIB=16   # o el tamaño deseado
# o, si querés conservar el tamaño calculado:
bash host/power.sh --resize-swap
```

Si `sudo systemctl hibernate` devuelve `Access denied`:

```bash
# ¿Qué contexto tienen el directorio y el archivo?
stat -c '%n %C' /swap /swap/swapfile
# ¿Qué opina systemd-logind?
busctl call org.freedesktop.login1 /org/freedesktop/login1 \
  org.freedesktop.login1.Manager CanHibernate
# AVC recientes
journalctl -b -t audit --no-pager | grep -i swapfile | tail
```

La causa habitual es que `/swap` haya quedado como `unlabeled_t` o `swapfile_t`. `make power` vuelve a aplicar las etiquetas (`/swap` → `var_t`, `/swap/swapfile` → `swapfile_t`).

### Proyectos remotos y GVFS

Si la hibernación falla con `Device or resource busy` y en el journal aparece una tarea en estado `D` dentro de `fuse_readdir` (por ejemplo, el watcher de Zed sobre un proyecto SFTP/SMB de GVFS), el freezer del kernel no puede congelar esa tarea.

`make power` instala `/etc/systemd/system-sleep/50-dotfiles-gvfs`, que antes de hibernar detiene `gvfs-daemon.service` del usuario y desmonta `/run/user/<uid>/gvfs`. Al reanudar vuelve a iniciar GVFS. Los montajes remotos se reabren desde la aplicación.

> Secure Boot habilitado puede bloquear la hibernación por lockdown. En esta estación se mantiene deshabilitado.

---

## Snapper y rollback (`make snapper`)

Solo actúa si `/` está en Btrfs. Crea la configuración `root` si no existe y migra `/.snapshots` a un subvolumen top-level `snapshots`, de modo que sobreviva a un reemplazo del subvolumen `root`. El subvolumen top-level `swap` lo crea y monta `make power`.

- Retención: 3 horarias, 3 diarias, 1 semanal, 10 por número, 2 importantes, limpieza de pre/post vacíos y comparación en segundo plano deshabilitada. No habilita cuotas Btrfs.
- Activa `snapper-timeline.timer` y `snapper-cleanup.timer`.
- Integra **snapshots automáticos pre/post transacción de DNF**:
  - **DNF5 (Fedora 41+):** instala `libdnf5-plugin-actions` y escribe `/etc/dnf/libdnf5-plugins/actions.d/snapper.actions` con el algoritmo de limpieza `number`.
  - **DNF4:** instala `python3-dnf-plugin-snapper`.
- Instala `grub-btrfs` desde el COPR `kylegospo/grub-btrfs`, habilita `grub-btrfs.path` y agrega `rd.live.overlay.overlayfs=1` **solo a las entradas de snapshot**. Esto permite arrancar un snapshot read-only con una capa escribible en RAM.
- Crea un snapshot `baseline dotfiles` marcado como importante.
- Instala `/usr/local/sbin/snapper-rollback`.

```bash
sudo snapper -c root list
```

### Arrancar un snapshot desde GRUB

Al reiniciar, elegí el submenú **Fedora snapshots** y luego el snapshot y el kernel. Los cambios hechos en ese arranque se pierden al reiniciar.

Limitaciones:

- `/boot` es ext4: kernel, initramfs y GRUB **no** están dentro de los snapshots. Si falla el kernel o GRUB, hace falta un rescue USB.
- Al elegir un snapshot, usá un kernel cuyos módulos existan en ese snapshot. Si el snapshot es anterior a la última actualización de kernel, elegí el kernel anterior.
- `/home` es un subvolumen separado y no se revierte.
- Los datos de contenedores rootless, libvirt y `/var` dentro de `root` sí se revierten.
- Los snapshots no son backups.

### Rollback permanente

`snapper rollback` no funciona con el layout de Fedora (`rootflags=subvol=root`). El helper hace el reemplazo real de subvolúmenes:

```bash
sudo snapper-rollback --list
sudo snapper-rollback --commit 42 --dry-run
sudo snapper-rollback --commit 42
sudo reboot
```

- El snapshot elegido no se modifica: se clona en `root.new`.
- El root anterior se conserva como `root.broken-<timestamp>`.
- Se conservan del root anterior: `fstab`, cuentas locales, claves SSH, `machine-id`, hostname, configuración de Snapper y de hibernación.
- También se copian los módulos de kernel presentes en el root anterior que falten en el snapshot, para que el kernel de `/boot` siga siendo utilizable.
- Recomendado ejecutarlo desde un snapshot arrancado por GRUB. Desde el root normal requiere `--force`.
- Para limpiar roots anteriores:

```bash
sudo snapper-rollback --cleanup
```
