#!/usr/bin/env python
"""run_migration_all.py
Script único para aplicar la migración NFC y comprobar el UID usando las credenciales en .env o config.py.
- Lee DATABASE_URL desde config.py o .env (PG_USER/PG_PASSWORD/PG_HOST/PG_PORT/PG_DB)
- Hace backup del procedimiento sp_assign_nfc_card en sql/backup/
- (Opcional) aplica sql/esquema.sql si APPLY_SCHEMA=1
- Aplica sql/migrations/add_nfc_relations.sql
- Consulta nfc_cards para TEST_UID
- Opcional: POST a /assign_nfc_card si TEST_PATIENT_ID está definido
- No fuerza creation de roles; si hay errores de permisos, usar grant_privileges.py con PG_SUPERUSER_URL

Uso:
  (Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned) ; (& .\.venv\Scripts\Activate.ps1) ; python .\run_migration_all.py

Variables de entorno (opcional):
  TEST_UID (por defecto 1028712993)
  TEST_PATIENT_ID
  TEST_FORCE (true/1)
  APPLY_SCHEMA (true/1)
  PG_SUPERUSER_URL (si quieres que migración/esquema se ejecuten con superuser)
  SELF_DELETE (true/1 para eliminar este archivo al final)
"""

from pathlib import Path
import os
import sys
from pprint import pprint

# --- helper: read .env
def read_env_file(path='.env'):
    p = Path(path)
    if not p.exists():
        return {}
    data = {}
    for line in p.read_text(encoding='utf-8').splitlines():
        line = line.strip()
        if not line or line.startswith('#') or '=' not in line:
            continue
        k, v = line.split('=', 1)
        data[k.strip()] = v.strip()
    return data

# --- build DATABASE_URL
DATABASE_URL = None
# try config.py
try:
    import config
    DATABASE_URL = getattr(config, 'DATABASE_URL', None)
except Exception:
    pass

if not DATABASE_URL:
    env = read_env_file('.env')
    if env.get('PG_USER') and env.get('PG_DB'):
        host = env.get('PG_HOST', 'localhost')
        port = env.get('PG_PORT', '5432')
        user = env.get('PG_USER')
        password = env.get('PG_PASSWORD','')
        if password:
            DATABASE_URL = f"postgresql://{user}:{password}@{host}:{port}/{env.get('PG_DB')}"
        else:
            DATABASE_URL = f"postgresql://{user}@{host}:{port}/{env.get('PG_DB')}"

if not DATABASE_URL:
    print('[ERROR] No se pudo determinar DATABASE_URL. Asegura config.py o .env con PG_USER/PG_DB/etc.')
    sys.exit(1)

print('[INFO] DATABASE_URL =', DATABASE_URL)

# --- imports runtime
try:
    import psycopg
except Exception:
    print('[ERROR] Falta la librería psycopg. Instala en tu venv: pip install psycopg[binary]')
    sys.exit(1)

try:
    import requests
except Exception:
    requests = None

sql_dir = Path('sql')
migration_file = sql_dir / 'migrations' / 'add_nfc_relations.sql'
schema_file = sql_dir / 'esquema.sql'
backup_dir = sql_dir / 'backup'
backup_dir.mkdir(parents=True, exist_ok=True)
backup_file = backup_dir / 'sp_assign_nfc_card_backup.sql'

# clean SQL helper
def strip_psql_meta(sql_text):
    lines = []
    for ln in sql_text.splitlines():
        s = ln.strip()
        if not s:
            lines.append(ln)
            continue
        if s.startswith('\\'):
            continue
        lines.append(ln)
    return '\n'.join(lines)

# connect helper
def try_connect(url):
    try:
        c = psycopg.connect(url)
        c.autocommit = True
        return c
    except Exception as e:
        return e

# connect with app user
print('[INFO] Conectando a la base de datos con credenciales de app...')
conn = try_connect(DATABASE_URL)
if isinstance(conn, Exception):
    print('[ERROR] No se pudo conectar con DATABASE_URL:', conn)
    print('[HINT] Si la conexión falla por permisos de role, usa grant_privileges.py con PG_SUPERUSER_URL')
    sys.exit(1)

# backup existing sp_assign_nfc_card if present
with conn.cursor() as cur:
    cur.execute("SELECT COALESCE(pg_get_functiondef(p.oid), '') FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid WHERE p.proname = 'sp_assign_nfc_card';")
    row = cur.fetchone()
    if row and row[0] and row[0].strip():
        backup_file.write_text(row[0], encoding='utf-8')
        print('[OK] Backup del SP guardado en:', backup_file)
    else:
        print('[WARN] No se encontró sp_assign_nfc_card previo; no se escribió backup (se usará migración).')

# ensure minimal nfc_cards if missing
with conn.cursor() as cur:
    try:
        cur.execute('SELECT 1 FROM nfc_cards LIMIT 1')
        print('[INFO] Tabla nfc_cards existe.')
    except Exception:
        print('[WARN] Tabla nfc_cards no existe. Creando tabla mínima...')
        create_minimal = '''
CREATE TABLE IF NOT EXISTS nfc_cards (
    nfc_card_id SERIAL PRIMARY KEY,
    patient_id INT,
    uid VARCHAR(30) UNIQUE,
    card_type VARCHAR(30),
    issued_date DATE,
    issued_by INT,
    status VARCHAR(20) NOT NULL DEFAULT 'Activa',
    last_scanned_at TIMESTAMP,
    nfc_card_notes TEXT
);
'''
        try:
            cur.execute(create_minimal)
            print('[OK] Tabla nfc_cards creada (mínima) con el usuario de la app.')
        except Exception as e:
            print('[ERROR] No se pudo crear tabla nfc_cards con el usuario de la app:', e)
            print('[INFO] Si no tienes permisos para crear tablas, usa PG_SUPERUSER_URL y grant_privileges.py')
            sys.exit(1)

# optionally apply schema first
apply_schema = str(os.environ.get('APPLY_SCHEMA','')).lower() in ('1','true')
pg_super = os.environ.get('PG_SUPERUSER_URL')
if apply_schema and schema_file.exists():
    schema_sql = strip_psql_meta(schema_file.read_text(encoding='utf-8'))
    print('[INFO] APPLY_SCHEMA requested; applying schema from', schema_file)
    if pg_super:
        sconn = try_connect(pg_super)
        if isinstance(sconn, Exception):
            print('[ERROR] No se pudo conectar con PG_SUPERUSER_URL:', sconn)
            sys.exit(1)
        with sconn.cursor() as scur:
            scur.execute(schema_sql)
        sconn.close()
        print('[OK] Esquema aplicado por superuser.')
    else:
        with conn.cursor() as cur:
            cur.execute(schema_sql)
        print('[OK] Esquema aplicado con usuario de app.')

# apply migration
if not migration_file.exists():
    print('[ERROR] No se encontró migración en:', migration_file)
    sys.exit(1)

mig_sql = strip_psql_meta(migration_file.read_text(encoding='utf-8'))
print('[INFO] Aplicando migración desde:', migration_file)
if pg_super:
    sconn = try_connect(pg_super)
    if isinstance(sconn, Exception):
        print('[ERROR] No se pudo conectar con PG_SUPERUSER_URL:', sconn)
        sys.exit(1)
    with sconn.cursor() as scur:
        scur.execute(mig_sql)
    sconn.close()
    print('[OK] Migración aplicada por superuser.')
else:
    with conn.cursor() as cur:
        cur.execute(mig_sql)
    print('[OK] Migración aplicada con usuario de app.')

# query TEST_UID
uid = os.environ.get('TEST_UID', '1028712993')
print(f'[INFO] Consultando nfc_cards para uid={uid}')
with conn.cursor() as cur:
    cur.execute('SELECT nfc_card_id, patient_id, uid, status, issued_date, issued_by FROM nfc_cards WHERE uid = %s', (uid,))
    rows = cur.fetchall()
    if not rows:
        print('[INFO] No se encontraron filas para ese UID')
    else:
        pprint(rows)

# optional HTTP test
test_patient = os.environ.get('TEST_PATIENT_ID')
if test_patient:
    if not requests:
        print('[WARN] requests no instalado; instala pip install requests para probar la API')
    else:
        payload = {
            'patient_id': int(test_patient),
            'uid': uid,
            'card_type': 'Fisica',
            'notes': 'reasignacion-automatica',
            'force': str(os.environ.get('TEST_FORCE','')).lower() in ('1','true')
        }
        try:
            print('[INFO] POSTing to http://localhost:5000/assign_nfc_card with payload:', payload)
            r = requests.post('http://localhost:5000/assign_nfc_card', json=payload, timeout=10)
            print('[INFO] Status', r.status_code)
            try:
                print(r.json())
            except Exception:
                print(r.text)
        except Exception as e:
            print('[WARN] HTTP request failed:', e)

conn.close()
print('[DONE]')

# self-delete
if str(os.environ.get('SELF_DELETE','')).lower() in ('1','true'):
    me = Path(__file__).resolve()
    try:
        me.unlink()
        print('[INFO] Self-deleted', me)
    except Exception as e:
        print('[WARN] Could not self-delete:', e)
