"""
Módulo de inicialización de la base de datos.
Solo verifica que la conexión a PostgreSQL esté activa.
El schema, SPs, vistas, triggers y datos se gestionan
directamente desde psql por el administrador.
"""

import logging
from db import get_db_connection, DatabaseError
from config import DB_ENGINE, _database_url_hint

logger = logging.getLogger(__name__)


def init_database():
    """
    Verifica que la conexión a la base de datos esté disponible.
    No ejecuta ningún archivo SQL automáticamente.
    """
    logger.info("=" * 60)
    logger.info("VERIFICANDO CONEXIÓN A BASE DE DATOS")
    logger.info(f"Motor: {DB_ENGINE}")
    logger.info(f"Conexión: {_database_url_hint()}")
    logger.info("=" * 60)

    try:
        conn = get_db_connection()
        conn.close()
        logger.info("✓ Conexión a base de datos OK")
    except Exception as e:
        logger.error(f"❌ Error de conexión: {e}")
        raise DatabaseError(f"No se pudo conectar a la base de datos: {e}") from e

    logger.info("=" * 60)
    logger.info("✓ LISTO — corre tu app con: flask run")
    logger.info("=" * 60)