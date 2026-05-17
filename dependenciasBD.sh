#!/usr/bin/env bash
# dependenciasBD.sh — Instala todo y levanta la BD desde cero (para pruebas)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# ──────────────────────────────────────────────
# 1. ESCRIBIR .env
# ──────────────────────────────────────────────
echo "[1/5] Escribiendo .env..."
cat > .env <<'EOF'
SECRET_KEY=segunda-entrega-demo
DEBUG=False

DB_ENGINE=postgres

PG_HOST=localhost
PG_PORT=5432
PG_USER=postgres
PG_PASSWORD=lt9128221d24
PG_DB=sistemavacunacion

MYSQL_HOST=localhost
MYSQL_PORT=3306
MYSQL_USER=root
MYSQL_PASSWORD=root
MYSQL_DB=sistemavacunacion
EOF

# ──────────────────────────────────────────────
# 2. INSTALAR DEPENDENCIAS DEL SISTEMA
# ──────────────────────────────────────────────
echo "[2/5] Instalando dependencias del sistema..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    python3 python3-venv python3-pip \
    postgresql postgresql-contrib \
    libpq-dev

# ──────────────────────────────────────────────
# 3. INSTALAR DEPENDENCIAS PYTHON
# Detecta automáticamente cuál requirements existe
# ──────────────────────────────────────────────
echo "[3/5] Creando entorno virtual e instalando dependencias Python..."
if [ ! -f ".venv/bin/python" ]; then
    python3 -m venv .venv
fi
.venv/bin/python -m pip install --upgrade pip -q

if [ -f "requirements_2daE.txt" ]; then
    REQS="requirements_2daE.txt"
elif [ -f "requirements.txt" ]; then
    REQS="requirements.txt"
else
    echo "[ERROR] No se encontró requirements.txt ni requirements_2daE.txt"
    exit 1
fi
echo "  → Usando $REQS"
.venv/bin/python -m pip install -r "$REQS" -q
echo "[OK] Dependencias Python instaladas."

# ──────────────────────────────────────────────
# 4. CONFIGURAR POSTGRESQL
# Detecta automáticamente la estructura de archivos SQL
# ──────────────────────────────────────────────
echo "[4/5] Configurando PostgreSQL..."

sudo systemctl start postgresql
sudo systemctl enable postgresql

sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'lt9128221d24';"
sudo -u postgres psql -c "DROP DATABASE IF EXISTS sistemavacunacion;"
sudo -u postgres psql -c "DROP USER IF EXISTS vaccine_user;"

export PGPASSWORD="lt9128221d24"
PG="psql -U postgres -h localhost"

# ── Detectar estructura de archivos SQL ──────
if [ -f "sql/esquema.sql" ]; then
    # Estructura local con carpeta sql/
    echo "  → Estructura detectada: sql/"

    echo "  → esquema.sql..."
    $PG -f sql/esquema.sql

    echo "  → SP.sql..."
    $PG -d sistemavacunacion -f sql/SP.sql

    echo "  → triggers.sql..."
    $PG -d sistemavacunacion -f sql/triggers.sql

    echo "  → datos.sql..."
    $PG -d sistemavacunacion -f sql/datos.sql

    [ -f "sql/migracion_almacen.sql" ] && \
        $PG -d sistemavacunacion -f sql/migracion_almacen.sql

    for mig in sql/migrations/add_vaccine_lot_status.sql \
               sql/migrations/add_clinical_flow.sql \
               sql/migrations/add_nfc_relations.sql \
               sql/migrations/clear_nfc_data.sql \
               sql/migrations/add_recepcionista_sps.sql \
               sql/migrations/fix_lot_number_unique.sql; do
        [ -f "$mig" ] && $PG -d sistemavacunacion -f "$mig"
    done

elif [ -f "esquema_postgres_2daE.sql" ]; then
    # Estructura de la VM (archivos en raíz con sufijo _2daE)
    echo "  → Estructura detectada: archivos _2daE en raíz"

    # esquema crea la BD, se corre contra postgres
    echo "  → esquema_postgres_2daE.sql..."
    $PG -f esquema_postgres_2daE.sql

    echo "  → datos_postgres_2daE.sql..."
    $PG -d sistemavacunacion -f datos_postgres_2daE.sql

    [ -f "queries.sql" ] && \
        $PG -d sistemavacunacion -f queries.sql

else
    echo "[ERROR] No se encontró ningún archivo SQL de esquema conocido."
    exit 1
fi

unset PGPASSWORD
echo "[OK] Base de datos lista."

# ──────────────────────────────────────────────
# 5. VERIFICAR CONEXIÓN (flask init-db)
# ──────────────────────────────────────────────
echo "[5/5] Verificando conexión con Flask..."
export FLASK_APP=app_2daE:app
export FLASK_DEBUG=1
.venv/bin/python -m flask init-db

echo ""
echo "============================================"
echo " TODO LISTO. Para iniciar la app ejecuta:"
echo "   ./iniciar.sh"
echo "============================================"
