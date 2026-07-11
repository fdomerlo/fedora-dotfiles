# ---------------------------------------------------------------------------
# ZSH y Oh My Zsh - Configuración Principal
# ---------------------------------------------------------------------------

# Path a tu instalación de Oh My Zsh.
export ZSH="$HOME/.oh-my-zsh"

# Tema de Oh My Zsh.
ZSH_THEME=""

# Plugins de Oh My Zsh a cargar.
plugins=(
  git
  common-aliases
  extract
  colored-man-pages
  zsh-autosuggestions
  zsh-syntax-highlighting
)

# Cargar Oh My Zsh. Esto debe hacerse antes de las personalizaciones del usuario.
source "$ZSH/oh-my-zsh.sh"

# ---------------------------------------------------------------------------
# CONFIGURACIÓN DEL USUARIO
# ---------------------------------------------------------------------------

# --- PATH (Variable de Entorno Crítica) ---
# Asegura que las rutas básicas del sistema y las locales del usuario siempre estén presentes.
export PATH="/usr/local/bin:$HOME/.local/bin:$HOME/bin:$PATH"

# --- UV (Python) ---
export PATH="$HOME/.local/bin:$PATH"

# --- FNM (Node.js) ---
export PATH="$HOME/.local/share/fnm:$PATH"

if command -v fnm &> /dev/null; then
    eval "$(fnm env --use-on-cd)"
fi

# --- SDKMAN (Java) ---
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"

# Cargar funciones y alias personalizados
if [ -f ~/.functions.sh ]; then
    source ~/.functions.sh
fi

# --- Prompt personalizado ---
setopt prompt_subst

autoload -Uz vcs_info
zstyle ':vcs_info:*' enable git
zstyle ':vcs_info:git:*' formats ' (%b)' # Limpiamos el espacio inicial aquí

precmd() {
    vcs_info
}
PROMPT='%F{cyan}%n%f %1~%F{yellow}${vcs_info_msg_0_}%f '

# --- Antigravity CLI y opencode (si existen) ---
[ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"
[ -d "$HOME/.opencode/bin" ] && export PATH="$HOME/.opencode/bin:$PATH"

. "$HOME/.local/bin/env"

# opencode
export PATH=/home/fdomerlo/.opencode/bin:$PATH


# Added by Antigravity CLI installer
export PATH="/home/fdomerlo/.local/bin:$PATH"
