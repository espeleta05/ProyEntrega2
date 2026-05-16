"""
repositorios.py — Operaciones de inserción y consulta sobre MongoDB

Tres colecciones:
  - eventos              → logs y eventos en tiempo real
  - historial_vacunacion → histórico masivo desnormalizado desde PostgreSQL
  - auditoria            → cambios con esquema flexible (datos semi-estructurados)

Relación con PostgreSQL:
  El campo 'pg_record_id' en historial_vacunacion es la clave compartida:
  corresponde a vaccination_records.record_id en PG. Esto permite hacer
  upsert idempotente (insertar o actualizar sin duplicar).
"""

from datetime import datetime, timedelta
from .conexion import get_db


# ──────────────────────────────────────────────────────────────
# EventosRepo — eventos en tiempo real (logins, NFC, acciones)
# ──────────────────────────────────────────────────────────────

class EventosRepo:

    @staticmethod
    def registrar(tipo, paciente_id=None, trabajador_id=None, clinica_id=None,
                  payload=None, ip=None, resultado="ok"):
        """
        Inserta un evento en MongoDB.
        Falla silenciosamente si Mongo no está disponible.
        """
        db = get_db()
        if db is None:
            return None
        try:
            doc = {
                "tipo":          tipo,
                "timestamp":     datetime.utcnow(),
                "paciente_id":   paciente_id,
                "trabajador_id": trabajador_id,
                "clinica_id":    clinica_id,
                "payload":       payload or {},
                "ip":            ip,
                "resultado":     resultado,
            }
            res = db.eventos.insert_one(doc)
            return str(res.inserted_id)
        except Exception:
            return None

    @staticmethod
    def por_dia(dias=30):
        """
        Serie de tiempo: conteo de eventos agrupados por día.
        Usado en el reporte de serie de tiempo (Highcharts).
        """
        db = get_db()
        if db is None:
            return []
        desde = datetime.utcnow() - timedelta(days=dias)
        pipeline = [
            {"$match": {"timestamp": {"$gte": desde}}},
            {"$group": {
                "_id":   {"$dateToString": {"format": "%Y-%m-%d", "date": "$timestamp"}},
                "total": {"$sum": 1},
            }},
            {"$sort": {"_id": 1}},
        ]
        return list(db.eventos.aggregate(pipeline))

    @staticmethod
    def distribucion_por_tipo(dias=30):
        """Conteo por tipo de evento — para gráfica de barras."""
        db = get_db()
        if db is None:
            return []
        desde = datetime.utcnow() - timedelta(days=dias)
        pipeline = [
            {"$match": {"timestamp": {"$gte": desde}}},
            {"$group": {"_id": "$tipo", "total": {"$sum": 1}}},
            {"$sort": {"total": -1}},
        ]
        return list(db.eventos.aggregate(pipeline))

    @staticmethod
    def recientes(limite=20):
        """Últimos N eventos para tabla en vivo."""
        db = get_db()
        if db is None:
            return []
        return list(db.eventos.find({}, {"_id": 0}).sort("timestamp", -1).limit(limite))


# ──────────────────────────────────────────────────────────────
# HistorialRepo — histórico masivo de vacunaciones (PG → Mongo)
# ──────────────────────────────────────────────────────────────

class HistorialRepo:

    @staticmethod
    def upsert(doc):
        """
        Inserta o actualiza un registro de vacunación.
        Idempotente: se identifica por pg_record_id (ID de PostgreSQL).
        Flujo: PostgreSQL → MongoDB
        """
        db = get_db()
        if db is None:
            return False
        if "pg_record_id" not in doc:
            return False
        try:
            doc["sincronizado_en"] = datetime.utcnow()
            db.historial_vacunacion.update_one(
                {"pg_record_id": doc["pg_record_id"]},
                {"$set": doc},
                upsert=True,
            )
            return True
        except Exception:
            return False

    @staticmethod
    def dosis_por_mes(meses=12):
        """
        Agrupación mensual de dosis aplicadas.
        Consulta MongoDB → Flask → Highcharts (serie de tiempo / barras).
        """
        db = get_db()
        if db is None:
            return []
        desde = datetime.utcnow() - timedelta(days=30 * meses)
        pipeline = [
            {"$match": {"fecha_aplicacion": {"$gte": desde}}},
            {"$group": {
                "_id":       "$anio_mes",
                "dosis":     {"$sum": 1},
                "pacientes": {"$addToSet": "$paciente_id"},
            }},
            {"$project": {
                "_id":              1,
                "dosis":            1,
                "pacientes_unicos": {"$size": "$pacientes"},
            }},
            {"$sort": {"_id": 1}},
        ]
        return list(db.historial_vacunacion.aggregate(pipeline))

    @staticmethod
    def dosis_por_vacuna(meses=6):
        """Top vacunas aplicadas — barras comparativas."""
        db = get_db()
        if db is None:
            return []
        desde = datetime.utcnow() - timedelta(days=30 * meses)
        pipeline = [
            {"$match": {"fecha_aplicacion": {"$gte": desde}}},
            {"$group": {"_id": "$vacuna_nombre", "total": {"$sum": 1}}},
            {"$sort": {"total": -1}},
            {"$limit": 10},
        ]
        return list(db.historial_vacunacion.aggregate(pipeline))

    @staticmethod
    def dosis_por_clinica(meses=6):
        """Dosis aplicadas por clínica — barras comparativas."""
        db = get_db()
        if db is None:
            return []
        from datetime import timedelta
        desde = datetime.utcnow() - timedelta(days=30 * meses)
        pipeline = [
            {"$match": {"fecha_aplicacion": {"$gte": desde}}},
            {"$group": {"_id": "$clinica_nombre", "total": {"$sum": 1}}},
            {"$sort": {"total": -1}},
        ]
        return list(db.historial_vacunacion.aggregate(pipeline))

    @staticmethod
    def tasa_reaccion_por_vacuna(meses=12):
        """
        Tasa de reacción adversa por vacuna — indicadores dinámicos.
        Usa $cond para contar sólo registros con reacción.
        """
        db = get_db()
        if db is None:
            return []
        desde = datetime.utcnow() - timedelta(days=30 * meses)
        pipeline = [
            {"$match": {"fecha_aplicacion": {"$gte": desde}}},
            {"$group": {
                "_id":          "$vacuna_nombre",
                "total":        {"$sum": 1},
                "con_reaccion": {"$sum": {"$cond": ["$tuvo_reaccion", 1, 0]}},
            }},
            {"$project": {
                "total":        1,
                "con_reaccion": 1,
                "tasa_pct": {
                    "$cond": [
                        {"$eq": ["$total", 0]}, 0,
                        {"$multiply": [{"$divide": ["$con_reaccion", "$total"]}, 100]}
                    ]
                },
            }},
            {"$sort": {"tasa_pct": -1}},
        ]
        return list(db.historial_vacunacion.aggregate(pipeline))

    @staticmethod
    def total():
        db = get_db()
        if db is None:
            return 0
        return db.historial_vacunacion.estimated_document_count()


# ──────────────────────────────────────────────────────────────
# AuditoriaRepo — cambios con esquema flexible (semi-estructurado)
# ──────────────────────────────────────────────────────────────

class AuditoriaRepo:

    @staticmethod
    def registrar_cambio(tabla, record_id, accion, cambios=None,
                         trabajador_id=None, trabajador_nombre=None, ip=None):
        """
        Guarda un cambio de auditoría.
        El campo 'cambios' es libre (semi-estructurado): puede ser un diff
        de campos, metadatos de sesión, info del dispositivo, etc.
        """
        db = get_db()
        if db is None:
            return None
        if accion.upper() not in ("INSERT", "UPDATE", "DELETE"):
            return None
        try:
            doc = {
                "tabla":              tabla,
                "record_id":          record_id,
                "accion":             accion.upper(),
                "cambios":            cambios or {},
                "trabajador_id":      trabajador_id,
                "trabajador_nombre":  trabajador_nombre,
                "fecha":              datetime.utcnow(),
                "ip":                 ip,
            }
            res = db.auditoria.insert_one(doc)
            return str(res.inserted_id)
        except Exception:
            return None

    @staticmethod
    def cambios_por_dia(dias=30):
        """Serie de tiempo de cambios — gráfica de área apilada."""
        db = get_db()
        if db is None:
            return []
        desde = datetime.utcnow() - timedelta(days=dias)
        pipeline = [
            {"$match": {"fecha": {"$gte": desde}}},
            {"$group": {
                "_id":   {"$dateToString": {"format": "%Y-%m-%d", "date": "$fecha"}},
                "total": {"$sum": 1},
            }},
            {"$sort": {"_id": 1}},
        ]
        return list(db.auditoria.aggregate(pipeline))

    @staticmethod
    def por_tabla(dias=30):
        """Distribución de cambios por tabla — barras."""
        db = get_db()
        if db is None:
            return []
        desde = datetime.utcnow() - timedelta(days=dias)
        pipeline = [
            {"$match": {"fecha": {"$gte": desde}}},
            {"$group": {"_id": "$tabla", "total": {"$sum": 1}}},
            {"$sort": {"total": -1}},
        ]
        return list(db.auditoria.aggregate(pipeline))
