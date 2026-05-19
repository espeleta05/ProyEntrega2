#!/usr/bin/env bash
set -e

cd "$(dirname "$0")"

if [ -f ".env" ]; then
    export $(grep -v '^#' .env | grep -v '^$' | xargs)
fi

# Liberar puerto 5000 si está ocupado
fuser -k 5000/tcp 2>/dev/null || true
sleep 1

export FLASK_APP=app_2daE:app
export FLASK_DEBUG="${FLASK_DEBUG:-1}"

echo "[1/2] Inicializando base de datos (flask init-db)..."
.venv/bin/python -m flask init-db

echo "[2/2] Servidor Flask en http://0.0.0.0:5000"
echo "      Accede desde tu PC en: http://$(hostname -I | awk '{print $1}'):5000"
.venv/bin/python -m flask run --host=0.0.0.0 --port=5000
