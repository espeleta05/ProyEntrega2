import os
import sys
from pathlib import Path
from urllib.parse import urlparse

import psycopg

ROOT = Path(__file__).resolve().parents[1]
SQL_DIR = ROOT / "sql"

SQL_ORDER = [
    "esquema_postgres_2daE.sql",
    "vistas.sql",
    "SP.sql",
    "triggers.sql",
    "datos_postgres_2daE.sql",
]


def get_database_url() -> str:
    return os.getenv(
        "DATABASE_URL",
        "postgresql://postgres:postgres@localhost:5432/sistemaVacunacion",
    )


def parse_db_parts(database_url: str) -> tuple[str, str]:
    parsed = urlparse(database_url)
    db_name = parsed.path.lstrip("/") or "postgres"
    maintenance_path = "/postgres"
    maintenance_url = parsed._replace(path=maintenance_path).geturl()
    return db_name, maintenance_url


def create_database_if_missing(database_url: str) -> None:
    db_name, maintenance_url = parse_db_parts(database_url)
    with psycopg.connect(maintenance_url, autocommit=True) as conn:
        with conn.cursor() as cur:
            cur.execute("SELECT 1 FROM pg_database WHERE datname = %s", (db_name,))
            exists = cur.fetchone() is not None
            if not exists:
                cur.execute(f'CREATE DATABASE "{db_name}"')
                print(f"[OK] Database creada: {db_name}")
            else:
                print(f"[OK] Database ya existe: {db_name}")


def read_sql_file(path: Path) -> str:
    for encoding in ("utf-8", "latin-1"):
        try:
            return path.read_text(encoding=encoding)
        except UnicodeDecodeError:
            continue
    raise UnicodeDecodeError("utf-8", b"", 0, 1, f"No se pudo leer {path.name}")


def reset_public_schema(database_url: str) -> None:
    with psycopg.connect(database_url, autocommit=True) as conn:
        with conn.cursor() as cur:
            cur.execute("DROP SCHEMA IF EXISTS public CASCADE;")
            cur.execute("CREATE SCHEMA public;")
            cur.execute("GRANT ALL ON SCHEMA public TO postgres;")
            cur.execute("GRANT ALL ON SCHEMA public TO public;")
    print("[OK] Schema public reiniciado")


def schema_has_user_tables(database_url: str) -> bool:
    with psycopg.connect(database_url, autocommit=True) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT EXISTS (
                    SELECT 1
                    FROM information_schema.tables
                    WHERE table_schema = 'public'
                      AND table_type = 'BASE TABLE'
                ) AS has_tables
                """
            )
            row = cur.fetchone()
            return bool(row and row[0])


def run_sql_scripts(database_url: str) -> None:
    with psycopg.connect(database_url, autocommit=True) as conn:
        with conn.cursor() as cur:
            for file_name in SQL_ORDER:
                sql_path = SQL_DIR / file_name
                if not sql_path.exists():
                    raise FileNotFoundError(f"No existe archivo SQL: {sql_path}")
                script = read_sql_file(sql_path)
                cur.execute(script)
                print(f"[OK] Ejecutado: {file_name}")


def main() -> int:
    database_url = get_database_url()
    force_reset = "--force-reset" in sys.argv
    print(f"[INFO] DATABASE_URL: {database_url}")

    try:
        create_database_if_missing(database_url)
        if force_reset:
            reset_public_schema(database_url)
            run_sql_scripts(database_url)
        else:
            if schema_has_user_tables(database_url):
                print("[OK] Base de datos ya inicializada. No se realizaron cambios.")
            else:
                print("[INFO] Base de datos vacia. Inicializando estructura y datos...")
                run_sql_scripts(database_url)
    except Exception as ex:
        print(f"[ERROR] Fallo inicializando PostgreSQL: {ex}")
        return 1

    print("[OK] Base de datos lista")
    return 0


if __name__ == "__main__":
    sys.exit(main())
