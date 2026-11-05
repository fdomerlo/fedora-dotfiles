#!/usr/bin/env bash
set -euo pipefail

uv venv
# shellcheck source=/dev/null
source .venv/bin/activate

uv pip install django

django-admin startproject config .
python manage.py migrate
