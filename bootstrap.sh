#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/fdomerlo/fedora-dev-env.git"
TARGET="$HOME/.dev-env"

echo "==> Bootstrapping infra-dev-env"

detect_pkg_manager() {
  if command -v dnf &>/dev/null; then
    echo "dnf"
  elif command -v apt &>/dev/null; then
    echo "apt"
  else
    echo "unknown"
  fi
}

PKG=$(detect_pkg_manager)

case "$PKG" in
  dnf) sudo dnf install -y git ;;
  apt) sudo apt update && sudo apt install -y git ;;
  *)
    echo "Install git manually"
    exit 1
    ;;
esac

# deps mínimos
if ! command -v git &>/dev/null; then
  echo "Installing git..."
  sudo dnf install -y git || {
    echo "❌ Could not install git automatically"
    exit 1
  }
fi

# clone/update
if [ -d "$TARGET" ]; then
  echo "==> Repo exists, updating..."
  git -C "$TARGET" pull
else
  echo "==> Cloning repo..."
  git clone "$REPO_URL" "$TARGET"
fi

cd "$TARGET"

# ejecutar installer real
bash install.sh
