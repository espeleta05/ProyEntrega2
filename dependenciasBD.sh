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
# ──────────────────────────────────────────────
echo "[3/5] Creando entorno virtual e instalando dependencias Python..."
if [ ! -f ".venv/bin/python" ]; then
    python3 -m venv .venv
fi
.venv/bin/python -m pip install --upgrade pip -q
.venv/bin/python -m pip install -r requirements.txt -q
echo "[OK] Dependencias Python instaladas."

# ──────────────────────────────────────────────
# 4. CONFIGURAR POSTGRESQL
# ──────────────────────────────────────────────
echo "[4/5] Configurando PostgreSQL..."

# Asegurarse que el servicio esté corriendo
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Cambiar password del usuario postgres
sudo -u postgres psql -c "ALTER USER postgres PASSWORD 'lt9128221d24';"

# Eliminar BD anterior si existe (modo prueba: empezar limpio)
sudo -u postgres psql -c "DROP DATABASE IF EXISTS sistemavacunacion;"
sudo -u postgres psql -c "DROP USER IF EXISTS vaccine_user;"

export PGPASSWORD="lt9128221d24"
PG="psql -U postgres -h localhost"

echo "  → Ejecutando esquema.sql (tablas, usuario, BD)..."
$PG -f sql/esquema.sql

echo "  → Ejecutando SP.sql (stored procedures)..."
$PG -d sistemavacunacion -f sql/SP.sql

echo "  → Ejecutando triggers.sql..."
$PG -d sistemavacunacion -f sql/triggers.sql

echo "  → Ejecutando datos.sql (datos iniciales)..."
$PG -d sistemavacunacion -f sql/datos.sql

echo "  → Ejecutando migracion_almacen.sql..."
$PG -d sistemavacunacion -f sql/migracion_almacen.sql

echo "  → Ejecutando migraciones incrementales..."
$PG -d sistemavacunacion -f sql/migrations/add_vaccine_lot_status.sql
$PG -d sistemavacunacion -f sql/migrations/add_clinical_flow.sql
$PG -d sistemavacunacion -f sql/migrations/add_nfc_relations.sql
$PG -d sistemavacunacion -f sql/migrations/clear_nfc_data.sql
$PG -d sistemavacunacion -f sql/migrations/add_recepcionista_sps.sql
$PG -d sistemavacunacion -f sql/migrations/fix_lot_number_unique.sql

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
