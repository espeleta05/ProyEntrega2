#!/usr/bin/env bash
set -e

cd "$(dirname "$0")"

if [ ! -f ".venv/bin/python" ]; then
    python3 -m venv .venv
fi

if [ ! -f ".venv/bin/python" ]; then
    echo "[ERROR] No se pudo crear el entorno virtual."
    exit 1
fi

.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install -r requirements.txt

echo "[OK] Dependencias instaladas."
