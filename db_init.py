"""
Módulo de inicialización de la base de datos.
Solo verifica que la conexión a PostgreSQL esté activa.
El schema, SPs, vistas, triggers y datos se gestionan
directamente desde psql por el administrador.
"""

import logging
import os
from db import get_db_connection, DatabaseError, execute_sql_file
from config import DB_ENGINE, _database_url_hint

_MIGRATIONS_DIR = os.path.join(os.path.dirname(__file__), "sql", "migrations")

logger = logging.getLogger(__name__)


_MIGRATIONS = [
    "ALTER TABLE audit_log ADD COLUMN IF NOT EXISTS changed_data JSONB",
]


_MIGRATION_FILES = [
    "fix_reception_realtime.sql",
]


def _run_migrations(conn):
    with conn.cursor() as cur:
        for sql in _MIGRATIONS:
            try:
                cur.execute(sql)
                logger.info(f"✓ Migración aplicada: {sql[:60]}")
            except Exception as e:
                logger.warning(f"⚠ Migración omitida ({sql[:60]}): {e}")
    conn.commit()

    for fname in _MIGRATION_FILES:
        path = os.path.join(_MIGRATIONS_DIR, fname)
        try:
            execute_sql_file(path)
            logger.info(f"✓ Archivo de migración aplicado: {fname}")
        except Exception as e:
            logger.warning(f"⚠ Archivo de migración omitido ({fname}): {e}")


def init_database():
    """
    Verifica que la conexión a la base de datos esté disponible
    y aplica migraciones pendientes.
    """
    logger.info("=" * 60)
    logger.info("VERIFICANDO CONEXIÓN A BASE DE DATOS")
    logger.info(f"Motor: {DB_ENGINE}")
    logger.info(f"Conexión: {_database_url_hint()}")
    logger.info("=" * 60)

    try:
        conn = get_db_connection()
        logger.info("✓ Conexión a base de datos OK")
        _run_migrations(conn)
        conn.close()
    except Exception as e:
        logger.error(f"❌ Error de conexión: {e}")
        raise DatabaseError(f"No se pudo conectar a la base de datos: {e}") from e

    logger.info("=" * 60)
    logger.info("✓ LISTO — corre tu app con: flask run")
    logger.info("=" * 60)