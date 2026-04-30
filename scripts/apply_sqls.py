"""Aplica los scripts SQL del proyecto en orden evitando fallos por duplicados.
Usar desde el venv: python scripts/apply_sqls.py
"""
import os
import sys
import psycopg
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SQL_DIR = ROOT / 'sql'
FILES = [
    SQL_DIR / 'esquema_postgres_2daE.sql',
    SQL_DIR / 'vistas.sql',
    SQL_DIR / 'SP.sql',
    SQL_DIR / 'datos_postgres_2daE.sql',
]


def get_db_url():
    # Load project config if available
    try:
        sys.path.insert(0, str(ROOT))
        import app_2daE
        return app_2daE.app.config.get('DATABASE_URL')
    except Exception:
        return os.environ.get('DATABASE_URL')


def apply_files(url):
    if not url:
        print('No DATABASE_URL found; set DATABASE_URL env var or ensure app_2daE.py exists')
        return 2

    conn = psycopg.connect(url)
    conn.autocommit = True
    cur = conn.cursor()

    for f in FILES:
        if not f.exists():
            print('SKIP (missing):', f)
            continue
        print('\n---- Applying', f.name, '----')
        raw = f.read_text(encoding='utf-8')

        # Transform INSERT statements to add ON CONFLICT DO NOTHING when missing.
        parts = raw.split(';')
        transformed_parts = []
        for p in parts:
            sp = p.strip()
            if not sp:
                continue
            low = sp.lower()
            if low.startswith('insert into') and 'on conflict' not in low:
                # ensure we append before semicolon when executing
                sp = sp + ' ON CONFLICT DO NOTHING'
            transformed_parts.append(sp)

        content = ';\n'.join(transformed_parts) + ';'

        try:
            cur.execute(content)
            print('OK')
        except Exception as e:
            # Log and continue; many seed inserts will conflict on PKs or other issues
            print('ERROR (ignored):', repr(e))

    cur.close()
    conn.close()
    return 0


if __name__ == '__main__':
    url = get_db_url()
    code = apply_files(url)
    sys.exit(code)
