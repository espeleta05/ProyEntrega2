#!/usr/bin/env bash
set -e

cd "$(dirname "$0")"

if [ -f ".env" ]; then
    export $(grep -v '^#' .env | grep -v '^$' | xargs)
fi

export FLASK_APP=app_2daE:app
export FLASK_DEBUG="${FLASK_DEBUG:-1}"

echo "[1/2] Inicializando base de datos (flask init-db)..."
.venv/bin/python -m flask init-db

echo "[2/2] Servidor Flask (flask run) en http://127.0.0.1:5000"
xdg-open http://127.0.0.1:5000 2>/dev/null &
.venv/bin/python -m flask run --host=127.0.0.1 --port=5000
