"""
rutas.py — Blueprint Flask con las APIs de MongoDB para los reportes NoSQL

Los datos se consumen desde la página reportesPublicos_2daE.html.
Flujo: MongoDB → estas APIs → Highcharts (frontend)

Endpoints:
  GET /api/mongo/estado                Estado de conexión + conteos
  GET /api/mongo/eventos/serie         Serie de tiempo de eventos por día
  GET /api/mongo/eventos/tipos         Distribución por tipo de evento
  GET /api/mongo/historial/mes         Dosis aplicadas por mes
  GET /api/mongo/historial/vacuna      Top vacunas aplicadas
  GET /api/mongo/historial/reaccion    Tasa de reacción por vacuna
"""

from flask import Blueprint, jsonify, request, session

from .conexion import ping, get_db
from .repositorios import EventosRepo, HistorialRepo

mongo_bp = Blueprint("mongo_bp", __name__)


def _sin_mongo():
    return jsonify({"error": "MongoDB no disponible. Verifica que mongod esté corriendo."}), 503


def _entero(nombre, default, lo=1, hi=365):
    try:
        v = int(request.args.get(nombre, default))
    except (TypeError, ValueError):
        v = default
    return max(lo, min(hi, v))


# ── Estado ───────────────────────────────────────────────────

@mongo_bp.route("/api/mongo/estado")
def api_estado():
    if not ping():
        return jsonify({"conectado": False}), 503
    db = get_db()
    conteos = {
        "eventos":             db.eventos.estimated_document_count(),
        "historial_vacunacion":db.historial_vacunacion.estimated_document_count(),
        "auditoria":           db.auditoria.estimated_document_count(),
    }
    return jsonify({"conectado": True, "conteos": conteos})


# ── Reporte 1: Serie de tiempo de eventos ────────────────────

@mongo_bp.route("/api/mongo/eventos/serie")
def api_eventos_serie():
    if not ping():
        return _sin_mongo()
    dias = _entero("dias", 30, 7, 180)
    filas = EventosRepo.por_dia(dias=dias)
    return jsonify({
        "categorias": [r["_id"] for r in filas],
        "datos":      [r["total"] for r in filas],
    })


@mongo_bp.route("/api/mongo/eventos/tipos")
def api_eventos_tipos():
    if not ping():
        return _sin_mongo()
    dias = _entero("dias", 30, 7, 180)
    filas = EventosRepo.distribucion_por_tipo(dias=dias)
    return jsonify({
        "categorias": [r["_id"] for r in filas if r["_id"]],
        "datos":      [r["total"] for r in filas if r["_id"]],
    })


# ── Reporte 2: Histórico de vacunación ───────────────────────

@mongo_bp.route("/api/mongo/historial/mes")
def api_historial_mes():
    if not ping():
        return _sin_mongo()
    meses = _entero("meses", 12, 1, 36)
    filas = HistorialRepo.dosis_por_mes(meses=meses)
    return jsonify({
        "categorias":     [r["_id"] for r in filas],
        "dosis":          [r["dosis"] for r in filas],
        "pacientes":      [r["pacientes_unicos"] for r in filas],
    })


@mongo_bp.route("/api/mongo/historial/clinica")
def api_historial_clinica():
    if not ping():
        return _sin_mongo()
    meses = _entero("meses", 6, 1, 36)
    filas = HistorialRepo.dosis_por_clinica(meses=meses)
    return jsonify({
        "categorias": [r["_id"] for r in filas if r["_id"]],
        "datos":      [r["total"] for r in filas if r["_id"]],
    })


@mongo_bp.route("/api/mongo/historial/vacuna")
def api_historial_vacuna():
    if not ping():
        return _sin_mongo()
    meses = _entero("meses", 6, 1, 36)
    filas = HistorialRepo.dosis_por_vacuna(meses=meses)
    return jsonify({
        "categorias": [r["_id"] for r in filas if r["_id"]],
        "datos":      [r["total"] for r in filas if r["_id"]],
    })


@mongo_bp.route("/api/mongo/historial/reaccion")
def api_historial_reaccion():
    if not ping():
        return _sin_mongo()
    meses = _entero("meses", 12, 1, 36)
    filas = HistorialRepo.tasa_reaccion_por_vacuna(meses=meses)
    return jsonify({
        "items": [
            {
                "vacuna":    r["_id"],
                "total":     r["total"],
                "reacciones":r["con_reaccion"],
                "tasa":      round(r["tasa_pct"], 2),
            }
            for r in filas if r["_id"]
        ]
    })
