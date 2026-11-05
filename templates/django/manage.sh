#!/usr/bin/env bash
set -euo pipefail

if [[ ! -d .venv ]]; then
  uv venv
fi
# shellcheck source=/dev/null
source .venv/bin/activate

if ! python -c "import django" &>/dev/null; then
  uv pip install django
fi

if [[ ! -f manage.py ]]; then
  django-admin startproject config .
fi

python manage.py migrate
