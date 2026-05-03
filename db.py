"""Capa única de conexión DB para PostgreSQL o MariaDB."""

import logging
import re
from contextlib import contextmanager
from typing import Any, Dict, List, Optional

from config import (
    DB_ENGINE,
    MYSQL_DB,
    MYSQL_HOST,
    MYSQL_PASSWORD,
    MYSQL_PORT,
    MYSQL_USER,
    PG_DB,
    PG_HOST,
    PG_PASSWORD,
    PG_PORT,
    PG_USER,
)

logger = logging.getLogger(__name__)
_IDENTIFIER_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")

if DB_ENGINE == "postgres":
    import psycopg
    from psycopg.rows import dict_row

    DBError = psycopg.DatabaseError
    OperationalError = psycopg.OperationalError
else:
    import pymysql
    from pymysql.cursors import DictCursor

    DBError = pymysql.MySQLError
    OperationalError = pymysql.err.OperationalError


class DatabaseError(Exception):
    pass


def quote_identifier(identifier: str) -> str:
    if not _IDENTIFIER_RE.match(identifier or ""):
        raise DatabaseError(f"Identificador SQL inválido: {identifier}")
    if DB_ENGINE == "postgres":
        return f'"{identifier}"'
    return f"`{identifier}`"


def _build_call_query(function_name: str, params: Optional[List[Any]]) -> str:
    if not _IDENTIFIER_RE.match(function_name or ""):
        raise DatabaseError(f"Nombre de rutina inválido: {function_name}")
    placeholders = ", ".join(["%s"] * len(params or []))
    if DB_ENGINE == "postgres":
        return f"SELECT * FROM {quote_identifier(function_name)}({placeholders})"
    return f"CALL {quote_identifier(function_name)}({placeholders})"


def get_connection():
    try:
        if DB_ENGINE == "postgres":
            return psycopg.connect(
                host=PG_HOST,
                port=int(PG_PORT),
                user=PG_USER,
                password=PG_PASSWORD,
                dbname=PG_DB,
                row_factory=dict_row,
            )
        return pymysql.connect(
            host=MYSQL_HOST,
            port=int(MYSQL_PORT),
            user=MYSQL_USER,
            password=MYSQL_PASSWORD,
            database=MYSQL_DB,
            cursorclass=DictCursor,
            autocommit=False,
        )
    except Exception as exc:
        raise DatabaseError(f"No se pudo abrir conexión ({DB_ENGINE}): {exc}") from exc


def get_db_connection():
    return get_connection()


@contextmanager
def connection_scope():
    conn = get_connection()
    try:
        yield conn
    finally:
        conn.close()


def execute_sp(sp_name: str, params: Optional[Dict[str, Any]] = None) -> List[Dict]:
    conn = None
    try:
        conn = get_connection()
        with conn.cursor() as cursor:
            ordered_values = list((params or {}).values())
            query = _build_call_query(sp_name, ordered_values)
            cursor.execute(query, tuple(ordered_values))
            results = cursor.fetchall() or []
        conn.commit()
        return results
    except DBError as exc:
        if conn:
            conn.rollback()
        raise DatabaseError(f"Error ejecutando rutina {sp_name}: {exc}") from exc
    finally:
        if conn:
            conn.close()


def execute_view(view_name: str, where: Optional[str] = None) -> List[Dict]:
    conn = None
    try:
        conn = get_connection()
        with conn.cursor() as cursor:
            query = f"SELECT * FROM {quote_identifier(view_name)}"
            if where:
                query += f" WHERE {where}"
            cursor.execute(query)
            return cursor.fetchall() or []
    except DBError as exc:
        raise DatabaseError(f"Error consultando vista {view_name}: {exc}") from exc
    finally:
        if conn:
            conn.close()


def execute_raw(query: str, params: Optional[tuple] = None) -> List[Dict]:
    conn = None
    try:
        conn = get_connection()
        with conn.cursor() as cursor:
            cursor.execute(query, params or ())
            if cursor.description:
                return cursor.fetchall() or []
            conn.commit()
            return []
    except DBError as exc:
        if conn:
            conn.rollback()
        raise DatabaseError(f"Error ejecutando SQL: {exc}") from exc
    finally:
        if conn:
            conn.close()


def execute_sp_modify(sp_name: str, params: Optional[Dict[str, Any]] = None) -> int:
    rows = execute_sp(sp_name, params=params)
    return len(rows)


def table_exists(table_name: str) -> bool:
    result = execute_raw(
        "SELECT 1 FROM information_schema.tables WHERE table_schema = %s AND table_name = %s LIMIT 1",
        ("public" if DB_ENGINE == "postgres" else MYSQL_DB, table_name),
    )
    return bool(result)


def sp_exists(sp_name: str) -> bool:
    if DB_ENGINE == "postgres":
        rows = execute_raw(
            "SELECT 1 FROM pg_proc WHERE proname = %s LIMIT 1",
            (sp_name,),
        )
    else:
        rows = execute_raw(
            "SELECT 1 FROM information_schema.routines WHERE routine_schema = %s AND routine_name = %s LIMIT 1",
            (MYSQL_DB, sp_name),
        )
    return bool(rows)


def execute_sql_file(file_path: str):
    conn = None
    try:
        with open(file_path, "r", encoding="utf-8") as file:
            sql_content = file.read()
        conn = get_connection()
        with conn.cursor() as cursor:
            for statement in sql_content.split(";"):
                stmt = statement.strip()
                if stmt:
                    cursor.execute(stmt)
        conn.commit()
        logger.info("SQL ejecutado: %s", file_path)
    except Exception as exc:
        if conn:
            conn.rollback()
        raise DatabaseError(f"Error ejecutando archivo {file_path}: {exc}") from exc
    finally:
        if conn:
            conn.close()
