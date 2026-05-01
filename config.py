"""
Configuración centralizada para la aplicación Flask + PostgreSQL.
- Carga variables de entorno desde .env
- Exporta DATABASE_URL, SECRET_KEY, etc.
- Proporciona funciones para conexión a PostgreSQL
"""

import os
import logging
from urllib.parse import urlparse
from dotenv import load_dotenv

# Cargar variables de .env
load_dotenv()

# Configuración
DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://postgres:postgres@localhost:5432/sistemaVacunacion"
)

SECRET_KEY = os.getenv("SECRET_KEY", "segunda-entrega-demo")

DEBUG = os.getenv("DEBUG", "False").lower() in ("true", "1", "yes")

# Logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger(__name__)


def _database_url_hint():
    """Retorna una representación legible de la conexión DB para debugging."""
    parsed = urlparse(DATABASE_URL)
    host = parsed.hostname or "localhost"
    port = parsed.port or 5432
    db_name = parsed.path.lstrip("/") or "<database>"
    user = parsed.username or "<user>"
    return f"{user}@{host}:{port}/{db_name}"


def get_db_connection():
    """
    Abre una conexión a PostgreSQL usando DATABASE_URL.

    Returns:
        psycopg.connection: Conexión a la base de datos

    Raises:
        psycopg.OperationalError: Si no puede conectarse
    """
    import psycopg
    from psycopg.rows import dict_row

    try:
        logger.debug(f"Intentando conectar a {_database_url_hint()}...")
        conn = psycopg.connect(DATABASE_URL, row_factory=dict_row)
        logger.info(f"✓ Conexión exitosa a {_database_url_hint()}")
        return conn
    except psycopg.OperationalError as e:
        error_msg = f"❌ No se pudo conectar a PostgreSQL ({_database_url_hint()}): {str(e)}"
        logger.error(error_msg)
        raise psycopg.OperationalError(error_msg)


def validate_database_connection():
    """
    Valida que la conexión a PostgreSQL funcione al startup.

    Returns:
        bool: True si la conexión es exitosa

    Raises:
        psycopg.OperationalError: Si la conexión falla
    """
    try:
        conn = get_db_connection()
        conn.close()
        logger.info("✓ Database connection validated")
        return True
    except Exception as e:
        logger.error(f"Database validation failed: {e}")
        raise
