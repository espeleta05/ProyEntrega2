"""
conexion.py — Conexión a MongoDB para ImmuniCare

Usa variables de entorno:
  MONGO_URI  (default: mongodb://localhost:27017)
  MONGO_DB   (default: immunicare_nosql)
"""

import os
import logging

logger = logging.getLogger(__name__)

# Configuración desde variables de entorno
MONGO_URI = os.getenv("MONGO_URI", "mongodb://localhost:27017")
MONGO_DB  = os.getenv("MONGO_DB",  "immunicare_nosql")

_client = None
_db     = None


def get_db():
    """Devuelve la base de datos MongoDB. Crea la conexión si no existe."""
    global _client, _db

    if _db is not None:
        return _db

    try:
        from pymongo import MongoClient
        _client = MongoClient(MONGO_URI, serverSelectionTimeoutMS=3000)
        _client.admin.command("ping")  # verifica que el servidor responde
        _db = _client[MONGO_DB]

        # Índices para consultas frecuentes
        _db.eventos.create_index([("timestamp", -1)])
        _db.historial_vacunacion.create_index([("fecha_aplicacion", -1)])
        _db.historial_vacunacion.create_index([("pg_record_id", 1)], unique=True, sparse=True)
        _db.auditoria.create_index([("fecha", -1)])

        logger.info("MongoDB conectado: %s / %s", MONGO_URI, MONGO_DB)
        return _db

    except Exception as e:
        logger.warning("MongoDB no disponible: %s", e)
        return None


def ping():
    """Devuelve True si MongoDB responde."""
    db = get_db()
    return db is not None
