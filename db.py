"""
Módulo centralizado para todas las operaciones con PostgreSQL.
- execute_sp(): Llama un Stored Procedure
- execute_view(): Consulta una vista
- execute_raw(): Ejecuta SQL directo (fallback)
"""

import logging
from typing import List, Dict, Any, Optional
from config import get_db_connection, DATABASE_URL
import psycopg

logger = logging.getLogger(__name__)


class DatabaseError(Exception):
    """Excepción personalizada para errores de base de datos."""
    pass


def execute_sp(sp_name: str, params: Optional[Dict[str, Any]] = None) -> List[Dict]:
    """
    Ejecuta un Stored Procedure y retorna los resultados.

    Args:
        sp_name: Nombre del SP (ej: 'sp_get_patients')
        params: Diccionario de parámetros nombrados

    Returns:
        List[Dict]: Resultado como lista de diccionarios

    Raises:
        DatabaseError: Si hay error en la ejecución
    """
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        # Construir llamada al SP
        if params:
            param_names = ', '.join(params.keys())
            param_values = ', '.join(['%s'] * len(params))
            query = f"SELECT * FROM {sp_name}({param_values})"
            param_list = list(params.values())
            logger.debug(f"Ejecutando: {sp_name}({param_names})")
            cursor.execute(query, param_list)
        else:
            query = f"SELECT * FROM {sp_name}()"
            logger.debug(f"Ejecutando: {sp_name}()")
            cursor.execute(query)

        results = cursor.fetchall()
        logger.debug(f"SP {sp_name} retornó {len(results)} filas")
        return results

    except psycopg.DatabaseError as e:
        error_msg = f"Error ejecutando SP {sp_name}: {str(e)}"
        logger.error(error_msg)
        raise DatabaseError(error_msg)
    finally:
        if conn:
            conn.close()


def execute_view(view_name: str, where: Optional[str] = None) -> List[Dict]:
    """
    Consulta una vista (vista = tabla lógica con JOINs precompilados).

    Args:
        view_name: Nombre de la vista (ej: 'vw_patients_full')
        where: Cláusula WHERE opcional (ej: "patient_id = %s")

    Returns:
        List[Dict]: Resultado como lista de diccionarios

    Raises:
        DatabaseError: Si hay error
    """
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        query = f"SELECT * FROM {view_name}"
        if where:
            query += f" WHERE {where}"

        logger.debug(f"Consultando vista: {view_name}")
        cursor.execute(query)
        results = cursor.fetchall()
        logger.debug(f"Vista {view_name} retornó {len(results)} filas")
        return results

    except psycopg.DatabaseError as e:
        error_msg = f"Error consultando vista {view_name}: {str(e)}"
        logger.error(error_msg)
        raise DatabaseError(error_msg)
    finally:
        if conn:
            conn.close()


def execute_raw(query: str, params: Optional[tuple] = None) -> List[Dict]:
    """
    Ejecuta SQL directo (fallback para queries especiales).
    ⚠️ SOLO para queries que no pueden hacerse con SPs/Views.

    Args:
        query: Consulta SQL
        params: Tupla de parámetros (para evitar SQL injection)

    Returns:
        List[Dict]: Resultado como lista de diccionarios

    Raises:
        DatabaseError: Si hay error
    """
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        logger.debug(f"Ejecutando SQL directo: {query[:80]}...")
        if params:
            cursor.execute(query, params)
        else:
            cursor.execute(query)

        results = cursor.fetchall()
        logger.debug(f"Query retornó {len(results)} filas")
        return results

    except psycopg.DatabaseError as e:
        error_msg = f"Error ejecutando SQL directo: {str(e)}"
        logger.error(error_msg)
        raise DatabaseError(error_msg)
    finally:
        if conn:
            conn.close()


def execute_sp_modify(sp_name: str, params: Optional[Dict[str, Any]] = None) -> int:
    """
    Ejecuta un Stored Procedure que modifica datos (INSERT/UPDATE/DELETE).
    Realiza COMMIT automático.

    Args:
        sp_name: Nombre del SP
        params: Diccionario de parámetros

    Returns:
        int: Número de filas afectadas

    Raises:
        DatabaseError: Si hay error
    """
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()

        if params:
            param_values = ', '.join(['%s'] * len(params))
            query = f"SELECT * FROM {sp_name}({param_values})"
            param_list = list(params.values())
            logger.debug(f"Ejecutando (MODIFY): {sp_name}")
            cursor.execute(query, param_list)
        else:
            query = f"SELECT * FROM {sp_name}()"
            logger.debug(f"Ejecutando (MODIFY): {sp_name}()")
            cursor.execute(query)

        conn.commit()
        rows_affected = cursor.rowcount
        logger.debug(f"SP {sp_name} modificó {rows_affected} filas")
        return rows_affected

    except psycopg.DatabaseError as e:
        if conn:
            conn.rollback()
        error_msg = f"Error ejecutando SP {sp_name}: {str(e)}"
        logger.error(error_msg)
        raise DatabaseError(error_msg)
    finally:
        if conn:
            conn.close()


def table_exists(table_name: str) -> bool:
    """
    Verifica si una tabla existe en PostgreSQL.

    Args:
        table_name: Nombre de la tabla

    Returns:
        bool: True si existe, False si no
    """
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT 1 FROM information_schema.tables WHERE table_name = %s",
            (table_name,)
        )
        return cursor.fetchone() is not None
    finally:
        if conn:
            conn.close()


def sp_exists(sp_name: str) -> bool:
    """
    Verifica si un Stored Procedure existe.

    Args:
        sp_name: Nombre del SP

    Returns:
        bool: True si existe, False si no
    """
    conn = None
    try:
        conn = get_db_connection()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT 1 FROM information_schema.routines WHERE routine_name = %s",
            (sp_name,)
        )
        return cursor.fetchone() is not None
    finally:
        if conn:
            conn.close()


def execute_sql_file(file_path: str):
    """
    Ejecuta un archivo SQL completo (para inicialización de schema/SPs/triggers).

    Args:
        file_path: Ruta al archivo .sql

    Raises:
        DatabaseError: Si hay error
    """
    conn = None
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            sql_content = f.read()

        conn = get_db_connection()
        cursor = conn.cursor()

        # Dividir por punto y coma para ejecutar statements múltiples
        statements = sql_content.split(';')
        for statement in statements:
            statement = statement.strip()
            if statement:  # Saltar líneas vacías
                logger.debug(f"Ejecutando: {statement[:60]}...")
                cursor.execute(statement)

        conn.commit()
        logger.info(f"✓ Archivo SQL ejecutado: {file_path}")

    except Exception as e:
        if conn:
            conn.rollback()
        error_msg = f"Error ejecutando archivo SQL {file_path}: {str(e)}"
        logger.error(error_msg)
        raise DatabaseError(error_msg)
    finally:
        if conn:
            conn.close()
