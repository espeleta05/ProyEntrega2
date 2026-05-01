"""
Módulo de inicialización automática de la base de datos.
- Verifica conexión a PostgreSQL
- Crea schema si no existen las tablas
- Crea SPs, vistas, triggers si no existen
- Realiza data seeding
"""

import os
import logging
from db import execute_sql_file, table_exists, get_db_connection, DatabaseError
from config import DATABASE_URL, _database_url_hint

logger = logging.getLogger(__name__)

# Rutas a archivos SQL
SQL_DIR = os.path.join(os.path.dirname(__file__), 'sql')
SCHEMA_FILE = os.path.join(SQL_DIR, 'esquema_postgres_2daE.sql')
SEED_FILE = os.path.join(SQL_DIR, 'datos_postgres_2daE.sql')
SP_FILE = os.path.join(SQL_DIR, 'SP.sql')
VIEWS_FILE = os.path.join(SQL_DIR, 'vistas.sql')
TRIGGERS_FILE = os.path.join(SQL_DIR, 'triggers.sql')


def init_database():
    """
    Inicializa la base de datos:
    1. Valida conexión
    2. Crea schema si no existen tablas
    3. Crea SPs, vistas, triggers
    4. Realiza seeding si está vacío

    Raises:
        DatabaseError: Si hay errores críticos
    """
    logger.info("=" * 60)
    logger.info("INICIALIZANDO BASE DE DATOS")
    logger.info(f"Conexión: {_database_url_hint()}")
    logger.info("=" * 60)

    # 1. Verificar conexión
    try:
        conn = get_db_connection()
        conn.close()
        logger.info("✓ Conexión a PostgreSQL OK")
    except Exception as e:
        logger.error(f"❌ Error de conexión: {e}")
        raise

    # 2. Crear schema si no existen las tablas
    if not table_exists('countries'):
        logger.info("Tablas no existen. Creando schema...")
        if os.path.exists(SCHEMA_FILE):
            try:
                execute_sql_file(SCHEMA_FILE)
                logger.info("✓ Schema creado exitosamente")
            except DatabaseError as e:
                logger.error(f"Error creando schema: {e}")
                raise
        else:
            logger.warning(f"Archivo schema no encontrado: {SCHEMA_FILE}")
    else:
        logger.info("✓ Tablas ya existen")

    # 3. Crear SPs
    logger.info("Creando/actualizando Stored Procedures...")
    if os.path.exists(SP_FILE):
        try:
            execute_sql_file(SP_FILE)
            logger.info("✓ Stored Procedures creados/actualizados")
        except DatabaseError as e:
            logger.warning(f"Error en SPs (continuando): {e}")
    else:
        logger.warning(f"Archivo SPs no encontrado: {SP_FILE}")

    # 4. Crear Vistas
    logger.info("Creando/actualizando Vistas...")
    if os.path.exists(VIEWS_FILE):
        try:
            execute_sql_file(VIEWS_FILE)
            logger.info("✓ Vistas creadas/actualizadas")
        except DatabaseError as e:
            logger.warning(f"Error en vistas (continuando): {e}")
    else:
        logger.warning(f"Archivo vistas no encontrado: {VIEWS_FILE}")

    # 5. Crear Triggers
    logger.info("Creando/actualizando Triggers...")
    if os.path.exists(TRIGGERS_FILE):
        try:
            execute_sql_file(TRIGGERS_FILE)
            logger.info("✓ Triggers creados/actualizados")
        except DatabaseError as e:
            logger.warning(f"Error en triggers (continuando): {e}")
    else:
        logger.warning(f"Archivo triggers no encontrado: {TRIGGERS_FILE}")

    # 6. Seeding si está vacío
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) as cnt FROM countries")
        result = cursor.fetchone()
        conn.close()

        country_count = result['cnt'] if result else 0
        if country_count == 0:
            logger.info("Base de datos vacía. Ejecutando seeding...")
            if os.path.exists(SEED_FILE):
                try:
                    execute_sql_file(SEED_FILE)
                    logger.info("✓ Data seeding completado")
                except DatabaseError as e:
                    logger.warning(f"Error en seeding (continuando): {e}")
            else:
                logger.warning(f"Archivo seed no encontrado: {SEED_FILE}")
        else:
            logger.info(f"✓ Base de datos contiene datos ({country_count} países)")

    except Exception as e:
        logger.warning(f"Error verificando datos: {e}")

    logger.info("=" * 60)
    logger.info("✓ INICIALIZACIÓN COMPLETA")
    logger.info("=" * 60)
