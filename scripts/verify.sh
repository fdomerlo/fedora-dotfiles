#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

export PATH="$HOME/.local/bin:$HOME/.opencode/bin:$HOME/.local/share/fnm:/usr/local/bin:$PATH"

ERRORS=0

pass() { printf '  [OK]   %s\n' "$1"; }
warn() { printf '  [WARN] %s\n' "$1"; }
fail() { printf '  [FAIL] %s\n' "$1"; ERRORS=$((ERRORS + 1)); }

echo "=================================================================="
echo "1. Validación estática del repositorio"
echo "=================================================================="

# 1.1 Verificar existencia de todos los archivos referenciados por Makefile y scripts
REQUIRED_FILES=(
  "$REPO_DIR/Makefile"
  "$REPO_DIR/host/setup.sh"
  "$REPO_DIR/host/snapper.sh"
  "$REPO_DIR/boxes/debian-work.sh"
  "$REPO_DIR/scripts/ohmyzsh.sh"
  "$REPO_DIR/scripts/devtools.sh"
  "$REPO_DIR/scripts/setup_gh.sh"
  "$REPO_DIR/scripts/setup_git.sh"
  "$REPO_DIR/scripts/devai.sh"
  "$REPO_DIR/scripts/setup_agy.sh"
  "$REPO_DIR/scripts/verify.sh"
  "$REPO_DIR/shell/zshrc"
  "$REPO_DIR/shell/devctl"
  "$REPO_DIR/templates/django/manage.sh"
  "$REPO_DIR/.envrc.template"
  "$REPO_DIR/README.md"
)

for f in "${REQUIRED_FILES[@]}"; do
  if [[ -f "$f" ]]; then
    pass "Archivo presente: ${f#"$REPO_DIR/"}"
  else
    fail "Archivo faltante: ${f#"$REPO_DIR/"}"
  fi
done

# 1.2 Validar sintaxis Bash (bash -n) en todos los scripts
BASH_SCRIPTS=(
  "$REPO_DIR/host/setup.sh"
  "$REPO_DIR/host/snapper.sh"
  "$REPO_DIR/boxes/debian-work.sh"
  "$REPO_DIR/scripts/ohmyzsh.sh"
  "$REPO_DIR/scripts/devtools.sh"
  "$REPO_DIR/scripts/setup_gh.sh"
  "$REPO_DIR/scripts/setup_git.sh"
  "$REPO_DIR/scripts/devai.sh"
  "$REPO_DIR/scripts/setup_agy.sh"
  "$REPO_DIR/scripts/verify.sh"
  "$REPO_DIR/scripts/desktop.sh"
  "$REPO_DIR/scripts/tooling.sh"
  "$REPO_DIR/shell/devctl"
  "$REPO_DIR/templates/django/manage.sh"
)

for s in "${BASH_SCRIPTS[@]}"; do
  if [[ -f "$s" ]]; then
    if bash -n "$s"; then
      pass "Sintaxis bash -n correcta: ${s#"$REPO_DIR/"}"
    else
      fail "Error de sintaxis bash -n: ${s#"$REPO_DIR/"}"
    fi
  fi
done

if command -v zsh &>/dev/null; then
  if zsh -n "$REPO_DIR/shell/zshrc"; then
    pass "Sintaxis zsh -n correcta: shell/zshrc"
  else
    fail "Error de sintaxis zsh -n: shell/zshrc"
  fi
fi

# 1.3 Ejecutar ShellCheck si está disponible
if command -v shellcheck &>/dev/null; then
  if shellcheck -x "${BASH_SCRIPTS[@]}"; then
    pass "ShellCheck sin observaciones"
  else
    fail "ShellCheck reportó advertencias o errores"
  fi
else
  warn "ShellCheck no está instalado en este entorno (omitido)"
fi

# 1.4 Comprobar ausencia de rutas absolutas de usuario y StrictHostKeyChecking=no
if grep -rnE '/home/fdomerlo|merlof@' "$REPO_DIR" --exclude-dir=.git --exclude=verify.sh >/dev/null 2>&1; then
  fail "Se detectaron rutas o datos personales hardcodeados del usuario"
else
  pass "Sin rutas absolutas ni datos personales hardcodeados"
fi

if grep -rn 'StrictHostKeyChecking=no' "$REPO_DIR" --exclude-dir=.git --exclude=verify.sh >/dev/null 2>&1; then
  fail "Se detectó desactivación de StrictHostKeyChecking"
else
  pass "Validación de claves SSH preservada (sin StrictHostKeyChecking=no)"
fi

# 1.5 Comprobar que el flujo principal no invoque dnf upgrade/autoremove/clean ni git pull
MAIN_FLOW_FILES=(
  "$REPO_DIR/Makefile"
  "$REPO_DIR/host/setup.sh"
  "$REPO_DIR/boxes/debian-work.sh"
  "$REPO_DIR/scripts/ohmyzsh.sh"
  "$REPO_DIR/scripts/devtools.sh"
  "$REPO_DIR/scripts/setup_gh.sh"
  "$REPO_DIR/scripts/setup_git.sh"
  "$REPO_DIR/scripts/devai.sh"
  "$REPO_DIR/scripts/setup_agy.sh"
)

FORBIDDEN_CMDS=0
for mf in "${MAIN_FLOW_FILES[@]}"; do
  if grep -v '^[[:space:]]*#' "$mf" | grep -E 'dnf[[:space:]]+(upgrade|autoremove|clean)|git[[:space:]].*pull' >/dev/null 2>&1; then
    FORBIDDEN_CMDS=1
  fi
done

if [[ $FORBIDDEN_CMDS -eq 1 ]]; then
  fail "El flujo principal contiene actualizaciones o limpiezas automáticas prohibidas"
else
  pass "Flujo principal libre de dnf upgrade/autoremove/clean y git pull"
fi

echo ""
echo "=================================================================="
echo "2. Estado del entorno local (diagnóstico no destructivo)"
echo "=================================================================="

# 2.1 Sistema y almacenamiento
ROOT_FS="$(findmnt -n -o FSTYPE -T / 2>/dev/null || echo "unknown")"
HOME_FS="$(findmnt -n -o FSTYPE -T "$HOME" 2>/dev/null || echo "unknown")"
echo "  [INFO] Filesystem: / (${ROOT_FS}), \$HOME (${HOME_FS})"

if command -v zramctl &>/dev/null && zramctl --output NAME --noheadings 2>/dev/null | grep -q 'zram'; then
  pass "zRAM activo"
else
  warn "zRAM no detectado como activo en este entorno"
fi

if [[ "$ROOT_FS" == "btrfs" ]]; then
  if command -v snapper &>/dev/null; then
    pass "Snapper instalado"
    if [[ -f /etc/dnf/libdnf5-plugins/actions.d/snapper.actions ]] || rpm -q python3-dnf-plugin-snapper &>/dev/null; then
      pass "Snapshots automáticos pre/post transacción de DNF configurados"
    else
      warn "Snapshots pre/post DNF no configurados aún (opcional: 'make snapper')"
    fi
  else
    warn "Snapper no instalado (opcional: 'make snapper')"
  fi
fi

# 2.2 Podman y Distrobox
if command -v podman &>/dev/null; then
  PODMAN_ROOTLESS="$(podman info --format '{{.Host.Security.Rootless}}' 2>/dev/null || echo "unknown")"
  PODMAN_DRIVER="$(podman info --format '{{.Store.GraphDriverName}}' 2>/dev/null || echo "unknown")"
  PODMAN_GRAPHROOT="$(podman info --format '{{.Store.GraphRoot}}' 2>/dev/null || echo "unknown")"
  pass "Podman disponible (rootless=${PODMAN_ROOTLESS}, driver=${PODMAN_DRIVER}, graphroot=${PODMAN_GRAPHROOT})"
else
  warn "Podman no está instalado aún"
fi

if command -v distrobox &>/dev/null; then
  pass "Distrobox instalado"
  if podman container exists debian-work 2>/dev/null || distrobox list --no-color 2>/dev/null | awk -F'|' 'NR>1 {gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2}' | grep -Fxq "debian-work"; then
    pass "Contenedor Distrobox 'debian-work' presente"
  else
    warn "Contenedor Distrobox 'debian-work' aún no creado"
  fi
else
  warn "Distrobox no está instalado aún"
fi

# 2.3 Shell y Oh My Zsh
if command -v zsh &>/dev/null; then
  pass "Zsh instalado ($(command -v zsh))"
else
  warn "Zsh no instalado aún"
fi

if [[ -d "$HOME/.oh-my-zsh" ]]; then
  pass "Oh My Zsh instalado en ~/.oh-my-zsh"
else
  warn "Oh My Zsh no instalado aún"
fi

for plugin in zsh-autosuggestions zsh-syntax-highlighting; do
  if [[ -d "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$plugin" ]]; then
    pass "Plugin Zsh presente: $plugin"
  else
    warn "Plugin Zsh ausente: $plugin"
  fi
done

if [[ -L "$HOME/.zshrc" ]] && [[ "$(readlink -f "$HOME/.zshrc" 2>/dev/null || true)" == "$REPO_DIR/shell/zshrc" ]]; then
  pass "~/.zshrc apunta a shell/zshrc del repositorio"
else
  warn "~/.zshrc aún no apunta a $REPO_DIR/shell/zshrc"
fi

# 2.4 Toolchains
for tool in uv fnm; do
  if command -v "$tool" &>/dev/null; then
    pass "Toolchain disponible: $tool ($(command -v "$tool"))"
  else
    warn "Toolchain aún no instalado: $tool"
  fi
done

if [[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]]; then
  pass "Toolchain disponible: SDKMAN ($HOME/.sdkman)"
else
  warn "Toolchain aún no instalado: SDKMAN"
fi

# 2.5 Herramientas de IA
if command -v opencode &>/dev/null || [[ -x "$HOME/.opencode/bin/opencode" ]]; then
  pass "OpenCode CLI instalado"
else
  warn "OpenCode CLI aún no instalado"
fi

if command -v antigravity &>/dev/null || command -v agy &>/dev/null || [[ -x "$HOME/.local/bin/antigravity" ]] || [[ -x "$HOME/.local/bin/agy" ]]; then
  pass "Antigravity CLI instalado"
else
  warn "Antigravity CLI aún no instalado"
fi

if [[ -x "/opt/Antigravity-x64/antigravity" ]]; then
  pass "Antigravity desktop instalado en /opt/Antigravity-x64"
else
  warn "Antigravity desktop no instalado (componente opcional)"
fi

# 2.6 GitHub CLI
if command -v gh &>/dev/null; then
  GH_PROTO="$(gh config get git_protocol 2>/dev/null || true)"
  if [[ "$GH_PROTO" == "ssh" ]]; then
    pass "GitHub CLI instalado con git_protocol=ssh"
  else
    warn "GitHub CLI instalado (git_protocol=${GH_PROTO:-default})"
  fi
  if gh auth status &>/dev/null; then
    pass "GitHub CLI autenticado"
  else
    warn "GitHub CLI sin sesión iniciada (ejecutar 'make github-auth')"
  fi
else
  warn "GitHub CLI (gh) aún no instalado"
fi

echo ""
if [[ $ERRORS -gt 0 ]]; then
  echo "ERROR: Fallaron $ERRORS comprobaciones estáticas." >&2
  exit 1
fi

echo "==> Verificación completada sin errores estáticos."
