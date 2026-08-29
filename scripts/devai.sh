#!/usr/bin/env bash
set -euo pipefail

if ! command -v opencode &> /dev/null; then
    curl -fsSL https://opencode.ai/install | bash
else
    echo "==> opencode is already installed"
fi

if ! command -v antigravity &> /dev/null; then
    curl -fsSL https://antigravity.google/cli/install.sh | bash
else
    echo "==> antigravity CLI is already installed"
fi

if ! command -v claude &> /dev/null; then
    curl -fsSL https://claude.ai/install.sh | bash
else
    echo "==> claude is already installed"
fi

bash scripts/setup_agy.sh
