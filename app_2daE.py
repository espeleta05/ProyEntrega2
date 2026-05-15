import math
import psycopg
from psycopg.rows import dict_row
import os
from datetime import date, datetime, timedelta
from flask import Flask, flash, jsonify, redirect, render_template, request, session, url_for, g, has_request_context
from werkzeug.utils import secure_filename
import bcrypt
import logging

from config import DATABASE_URL, DB_ENGINE, SECRET_KEY
from db import OperationalError, get_db_connection, quote_identifier

app = Flask(__name__)

app.config["DATABASE_URL"] = DATABASE_URL
app.config["DB_ENGINE"] = DB_ENGINE
app.secret_key = SECRET_KEY
app.config['JSON_AS_ASCII'] = False

logger = logging.getLogger(__name__)
try:
    test_conn = get_db_connection()
    test_conn.close()
    print(f"[OK] {DB_ENGINE} conectado correctamente")
    print(f"[INFO] DATABASE_URL: {DATABASE_URL}")
except Exception as e:
    print("[ERROR] No se pudo conectar a la base de datos")
    print(e)


@app.errorhandler(OperationalError)
def handle_database_operational_error(error):
    return (
        f"Error conectando a {app.config['DB_ENGINE']}:<br><br>{str(error)}<br><br>"
        f"URL usada: {app.config['DATABASE_URL']}",
        500,
    )


# =============================================================================
# HELPERS — conexión y utilidades básicas (sin lógica de negocio)
# =============================================================================

TABLE_ALIASES = {}

def _db_connect():
    return get_db_connection()

def _conn_is_closed(conn):
    if conn is None:
        return True
    if hasattr(conn, "closed"):
        return bool(conn.closed)
    if hasattr(conn, "open"):
        return not bool(conn.open)
    return False

def _get_conn():
    if has_request_context():
        conn = getattr(g, "db_conn", None)
        if conn is None or _conn_is_closed(conn):
            conn = _db_connect()
            g.db_conn = conn
        return conn, False
    return _db_connect(), True

def _get_req_cache():
    if not has_request_context():
        return None
    cache = getattr(g, "req_cache", None)
    if cache is None:
        cache = {}
        g.req_cache = cache
    return cache

def _safe_rollback(conn):
    try:
        if conn is not None and not _conn_is_closed(conn):
            conn.rollback()
    except Exception:
        pass

@app.teardown_appcontext
def _close_request_db(_exc):
    conn = getattr(g, "db_conn", None)
    if conn is not None and not _conn_is_closed(conn):
        conn.close()

def _safe_table_name(table):
    return TABLE_ALIASES.get(table, table)

def _cur_fetchall(table):
    physical  = _safe_table_name(table)
    cache     = _get_req_cache()
    cache_key = ("all", physical)
    if cache is not None and cache_key in cache:
        return cache[cache_key]
    conn, should_close = _get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(f"SELECT * FROM {quote_identifier(physical)}")
            rows = cur.fetchall()
            if cache is not None:
                cache[cache_key] = rows
            return rows
    except Exception:
        _safe_rollback(conn)
        return []
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

def _cur_fetchone(table, pk_field, pk_value):
    physical  = _safe_table_name(table)
    cache     = _get_req_cache()
    cache_key = ("one", physical, pk_field, pk_value)
    if cache is not None and cache_key in cache:
        return cache[cache_key]
    conn, should_close = _get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                f"SELECT * FROM {quote_identifier(physical)} WHERE {quote_identifier(pk_field)} = %s LIMIT 1",
                (pk_value,),
            )
            row = cur.fetchone()
            if cache is not None:
                cache[cache_key] = row
            return row
    except Exception:
        _safe_rollback(conn)
        return None
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

def _cur_fetchall_where(table, field, value):
    physical  = _safe_table_name(table)
    cache     = _get_req_cache()
    cache_key = ("where", physical, field, value)
    if cache is not None and cache_key in cache:
        return cache[cache_key]
    conn, should_close = _get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                f"SELECT * FROM {quote_identifier(physical)} WHERE {quote_identifier(field)} = %s",
                (value,),
            )
            rows = cur.fetchall()
            if cache is not None:
                cache[cache_key] = rows
            return rows
    except Exception:
        _safe_rollback(conn)
        return []
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()


# =============================================================================
# HELPERS — sesión y formato (sin lógica de DB)
# =============================================================================

def _require_login():
    if "user_name" not in session:
        flash("Debes iniciar sesión para continuar.", "warning")
        return redirect(url_for("login"))
    return None

def _require_role(*allowed_roles):
    """Para rutas que devuelven HTML. Retorna redirect o None."""
    locked = _require_login()
    if locked:
        return locked
    if session.get("role", "") not in allowed_roles:
        flash("No tienes permisos para acceder a esta sección.", "danger")
        return redirect(_home_url_for_role(session.get("role", "")))
    return None

def _check_role(*allowed_roles):
    """Para endpoints JSON. Retorna True si el usuario tiene el rol requerido."""
    return "user_name" in session and session.get("role", "") in allowed_roles

def _home_url_for_role(role):
    """Retorna la URL del dashboard correspondiente al rol."""
    if role == "Recepcionista":
        return url_for("recepcionista_dashboard")
    if role == "Medico":
        return url_for("medico_dashboard")
    return url_for("dashboard")

def _session_vars():
    first    = session.get("user_name", "")
    last     = session.get("user_lastname", "")
    initials = ((first[:1] + last[:1]).upper()) or "AD"
    return {
        "name":      first,
        "lastname":  last,
        "role":      session.get("role", "Administrador"),
        "worker_id": session.get("worker_id"),
        "initials":  initials,
    }

def _temporal_text(value):
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.isoformat(sep=" ")
    if isinstance(value, date):
        return value.isoformat()
    return str(value)

def _age_years(birth_date_str):
    try:
        b = datetime.strptime(str(birth_date_str), "%Y-%m-%d").date()
    except (ValueError, TypeError):
        return 0
    today = date.today()
    years = today.year - b.year
    if (today.month, today.day) < (b.month, b.day):
        years -= 1
    return max(years, 0)

def _distance_meters(lat1, lon1, lat2, lon2):
    r = 6371000.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi    = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


# =============================================================================
# AUTENTICACIÓN (sin SP — bcrypt en Python)
# =============================================================================

def _authenticate_user(login_value, password):
    login_value = (login_value or "").strip()
    password    = password or ""
    if not login_value or not password:
        return None
    try:
        conn = get_db_connection()
        cur  = conn.cursor()
        cur.execute("""
            SELECT u.user_id, u.password_hash, u.is_active,
                   w.worker_id, w.first_name, w.last_name, r.name
            FROM users u
            JOIN workers w ON u.worker_id = w.worker_id
            LEFT JOIN roles r ON w.role_id = r.role_id
            LEFT JOIN worker_emails we ON w.worker_id = we.worker_id
            WHERE u.username = %s OR we.email = %s
            LIMIT 1;
        """, (login_value, login_value))
        row = cur.fetchone()
        if not row or not row["is_active"]:
            return None
        stored_hash = row["password_hash"]
        if not stored_hash or not bcrypt.checkpw(
            password.encode("utf-8"), stored_hash.encode("utf-8")
        ):
            return None
        # Obtener la clínica principal del trabajador desde su horario
        worker_id = row["worker_id"]
        clinic_id = None
        try:
            cur.execute("""
                SELECT clinic_id FROM worker_schedules
                WHERE worker_id = %s
                ORDER BY clinic_id LIMIT 1
            """, (worker_id,))
            clinic_row = cur.fetchone()
            if clinic_row:
                clinic_id = clinic_row["clinic_id"]
        except Exception:
            pass  # clinic_id queda en None; el SP acepta NULL
        return {
            "worker_id": worker_id,
            "name":      (row.get("first_name") or "").strip(),
            "lastname":  (row.get("last_name")  or "").strip(),
            "role":      row.get("name") or "Administrador",
            "clinic_id": clinic_id,
        }
    except Exception as e:
        logger.warning("Error en autenticación: %s", e)
        return None
    finally:
        try:
            cur.close()
            conn.close()
        except Exception:
            pass


def _authenticate_tutor(email, password):
    """Autentica un tutor contra guardian_accounts (email + bcrypt)."""
    email    = (email or "").strip().lower()
    password = password or ""
    if not email or not password:
        return None
    try:
        conn = get_db_connection()
        cur  = conn.cursor()
        cur.execute("""
            SELECT ga.guardian_account_id,
                   ga.guardian_id,
                   ga.password_hash,
                   g.first_name,
                   g.last_name
            FROM   guardian_accounts ga
            JOIN   guardians g ON g.guardian_id = ga.guardian_id
            WHERE  LOWER(ga.email) = %s
            LIMIT  1;
        """, (email,))
        row = cur.fetchone()
        if not row:
            return None
        stored_hash = row["password_hash"]
        if not stored_hash or not bcrypt.checkpw(
            password.encode("utf-8"), stored_hash.encode("utf-8")
        ):
            return None
        return {
            "guardian_account_id": row["guardian_account_id"],
            "guardian_id":         row["guardian_id"],
            "name":                (row.get("first_name") or "").strip(),
            "lastname":            (row.get("last_name")  or "").strip(),
        }
    except Exception as e:
        logger.warning("Error en autenticación de tutor: %s", e)
        return None
    finally:
        try:
            cur.close()
            conn.close()
        except Exception:
            pass


def _require_tutor():
    """Para rutas del portal del tutor. Redirige a /tutor/login si no hay sesión."""
    if "tutor_id" not in session:
        flash("Debes iniciar sesión para acceder al portal del tutor.", "warning")
        return redirect(url_for("tutor_login"))
    return None


def _tutor_session_vars():
    """Equivalente a _session_vars() pero para la sesión del tutor."""
    first    = session.get("tutor_name", "")
    last     = session.get("tutor_lastname", "")
    initials = ((first[:1] + last[:1]).upper()) or "TU"
    return {
        "tutor_name":     first,
        "tutor_lastname": last,
        "guardian_id":    session.get("guardian_id"),
        "tutor_id":       session.get("tutor_id"),
        "tutor_initials": initials,
    }


# =============================================================================
# RUTAS — páginas públicas
# =============================================================================

@app.route("/")
def pagina_inicio():
    return render_template("pages/inicioPP.html")

@app.route("/servicios")
def pagina_servicios():
    return render_template("pages/serviciosPP.html")

@app.route("/nosotros")
def pagina_nosotros():
    return render_template("pages/nosotrosPP.html")

@app.route("/contacto")
def pagina_contacto():
    return render_template("pages/contactoPP.html")


# =============================================================================
# RUTAS — login / logout
# =============================================================================

@app.route("/login", methods=["GET", "POST"])
def login():
    error = None
    if "user_name" in session:
        return redirect(_home_url_for_role(session.get("role", "")))
    if request.method == "POST":
        mail     = (request.form.get("mail") or "").strip()
        password = request.form.get("password") or ""
        user     = _authenticate_user(mail, password)
        if user:
            session["user_name"]     = user["name"]
            session["user_lastname"] = user["lastname"]
            session["role"]          = user["role"]
            session["worker_id"]     = user["worker_id"]
            session["clinic_id"]     = user.get("clinic_id")  # None si sin horario registrado
            flash(f"Bienvenido, {user['name']}.", "success")
            return redirect(_home_url_for_role(user["role"]))
        error = "Credenciales inválidas."
        flash(error, "danger")
    return render_template("pages/login_2daE.html", error=error)


@app.route("/logout")
def logout():
    nombre = session.get("user_name", "")
    session.clear()
    flash(f"Sesión de {nombre} cerrada correctamente.", "info")
    return redirect(url_for("pagina_inicio"))


# =============================================================================
# RUTAS — portal del tutor
# =============================================================================

@app.route("/tutor/login", methods=["GET", "POST"])
def tutor_login():
    error = None
    if request.method == "POST":
        email    = (request.form.get("email") or "").strip()
        password = request.form.get("password") or ""
        tutor    = _authenticate_tutor(email, password)
        if tutor:
            for key in ("tutor_id", "guardian_id", "tutor_name", "tutor_lastname"):
                session.pop(key, None)
            session["tutor_id"]       = tutor["guardian_account_id"]
            session["guardian_id"]    = tutor["guardian_id"]
            session["tutor_name"]     = tutor["name"]
            session["tutor_lastname"] = tutor["lastname"]
            flash(f"Bienvenido/a, {tutor['name']}.", "success")
            return redirect(url_for("tutor_dashboard"))
        error = "Correo o contraseña incorrectos."
        flash(error, "danger")
    elif "tutor_id" in session:
        return redirect(url_for("tutor_dashboard"))
    return render_template("tutor/login.html", error=error)


@app.route("/tutor/logout")
def tutor_logout():
    nombre = session.get("tutor_name", "")
    for key in ("tutor_id", "guardian_id", "tutor_name", "tutor_lastname"):
        session.pop(key, None)
    flash(f"Sesión de {nombre} cerrada correctamente.", "info")
    return redirect(url_for("tutor_login"))


@app.route("/tutor")
@app.route("/tutor/dashboard")
def tutor_dashboard():
    # [REFACTORED] Reemplaza loop N+1 (1 query por hijo) + inline SQL por una
    #              sola llamada a sp_dashboard_tutor que devuelve todas las
    #              dosis pendientes/atrasadas de todos los hijos del tutor.
    #              Eliminada lógica de tutor_accepted / pending_accept_count.
    locked = _require_tutor()
    if locked:
        return locked

    vars_       = _tutor_session_vars()
    guardian_id = vars_["guardian_id"]
    rows        = []

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("CALL sp_dashboard_tutor(%s, %s)",
                        (guardian_id, "cur_dash_tutor"))
            cur.execute('FETCH ALL FROM "cur_dash_tutor"')
            rows = [dict(r) for r in cur.fetchall()]
        conn.commit()
    except Exception as e:
        _safe_rollback(conn)
        logger.error("Error en tutor_dashboard: %s", e)
        flash("Error al cargar el panel familiar. Intente de nuevo.", "danger")
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    # ── Agrupar filas por paciente ─────────────────────────────────────────
    patients_map: dict = {}
    for r in rows:
        pid = r["patient_id"]
        if pid not in patients_map:
            fn    = r.get("full_name", "")
            parts = fn.split()
            patients_map[pid] = {
                "patient_id":    pid,
                "full_name":     fn,
                "age_years":     r.get("age_years", 0),
                "birth_date":    _temporal_text(r.get("birth_date")),
                "photo_url":     (f"/static/uploads/patients/{r['photo']}"
                                  if r.get("photo") else None),
                "initials":      (fn[:1] + (parts[-1][:1]
                                  if len(parts) > 1 else "")).upper(),
                "total_applied": r.get("total_applied", 0),
                "total_pending": r.get("total_pending", 0),
                "total_doses":   r.get("total_doses", 0),
                "pct":           r.get("pct", 0),
                "delayed_count": r.get("delayed_count", 0),
                "doses":         [],
                "alerts_delayed": [],
            }

        # Acumular dosis del hijo (excluyendo filas de estado FUTURA para no saturar)
        action_state = r.get("action_state", "")
        due_dt       = r.get("due_date")
        dias         = r.get("dias_retraso") or 0

        # [CORREGIDO] Calcular alerta_retraso (el SP de dashboard no la devuelve)
        alerta = None
        if isinstance(due_dt, date):
            if dias > 0:
                alerta = f"Retraso de {dias} días"
            else:
                remaining = (due_dt - date.today()).days
                alerta = f"Programada en {remaining} días"

        # [CORREGIDO] Calcular edad_ideal legible desde ideal_age_months
        months = r.get("ideal_age_months") or 0
        if months == 0:
            edad_label = "Al nacer"
        elif months >= 12:
            edad_label = f"{months // 12} año(s)"
        else:
            edad_label = f"{months} meses"

        # [CORREGIDO] Claves alineadas con lo que usa la template (name, dose, estado, etc.)
        dose_entry = {
            "name":           r.get("vaccine_name"),
            "dose":           r.get("dose_label"),
            "due_date":       _temporal_text(due_dt),
            "dias_retraso":   dias,
            "dose_status":    r.get("dose_status"),
            "estado":         ("Pendiente con retraso" if r.get("dose_status") == "Atrasada"
                               else r.get("dose_status") or "Pendiente"),
            "alerta_retraso": alerta,
            "edad_ideal":     edad_label,
            "action_state":   action_state,
            "appointment_id": r.get("appointment_id"),
            "fecha_cita":     _temporal_text(r.get("scheduled_at")),
            "appt_status":    r.get("appointment_status"),
        }
        patients_map[pid]["doses"].append(dose_entry)

        if action_state in ("ATRASADA_SIN_CITA", "ATRASADA_CON_CITA"):
            if len(patients_map[pid]["alerts_delayed"]) < 3:
                # [CORREGIDO] Claves name/dose (template usa a.name, a.dose, a.dias)
                patients_map[pid]["alerts_delayed"].append({
                    "name": r.get("vaccine_name"),
                    "dose": r.get("dose_label"),
                    "dias": dias,
                })

    children_data = list(patients_map.values())

    # ── KPIs globales ──────────────────────────────────────────────────────
    total_applied_all = sum(c["total_applied"] for c in children_data)
    total_doses_all   = sum(c["total_doses"]   for c in children_data)
    total_pending_all = sum(c["total_pending"] for c in children_data)
    pct_global        = (int(total_applied_all / total_doses_all * 100)
                         if total_doses_all > 0 else 0)
    total_alerts      = sum(c["delayed_count"] for c in children_data)

    return render_template(
        "tutor/dashboard.html",
        today=date.today().strftime("%A, %d de %B de %Y"),
        children=children_data,
        pct_global=pct_global,
        total_pending_all=total_pending_all,
        total_alerts=total_alerts,
        chart_applied=total_applied_all,
        chart_pending=total_pending_all,
        **vars_,
    )


def _tutor_owns_patient(guardian_id, patient_id):
    """Devuelve True si patient_id está vinculado al guardian_id."""
    conn, should_close = _get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT 1 FROM patient_guardian_relations
                WHERE  guardian_id = %s AND patient_id = %s
                LIMIT  1;
            """, (guardian_id, patient_id))
            return cur.fetchone() is not None
    except Exception:
        return False
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()


@app.route("/tutor/paciente/<int:patient_id>")
def tutor_esquema(patient_id):
    locked = _require_tutor()
    if locked:
        return locked

    vars_       = _tutor_session_vars()
    guardian_id = vars_["guardian_id"]

    if not _tutor_owns_patient(guardian_id, patient_id):
        flash("No tienes acceso a este paciente.", "danger")
        return redirect(url_for("tutor_dashboard"))

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("CALL sp_get_patient_scheme(%s, %s)",
                        (patient_id, "cur_tutor_esq"))
            cur.execute('FETCH ALL FROM "cur_tutor_esq"')
            esquema_rows = [dict(r) for r in cur.fetchall()]
        conn.commit()
    except Exception as e:
        _safe_rollback(conn)
        logger.error("Error en tutor_esquema: %s", e)
        flash("Error al cargar el esquema del paciente.", "danger")
        return redirect(url_for("tutor_dashboard"))
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    if not esquema_rows:
        flash("Paciente no encontrado o sin esquema.", "danger")
        return redirect(url_for("tutor_dashboard"))

    first  = esquema_rows[0]
    _photo = first.get("photo")
    fn     = first.get("full_name") or ""
    parts  = fn.split()
    patient = {
        "patient_id": first.get("patient_id"),
        "full_name":  fn,
        "birth_date": _temporal_text(first.get("birth_date")),
        "age":        first.get("age_years"),
        "photo_url":  f"/static/uploads/patients/{_photo}" if _photo else None,
        "initials":   (fn[:1] + (parts[-1][:1] if len(parts) > 1 else "")).upper(),
    }

    applications = [
        {
            "name":      r.get("name"),
            "dose":      r.get("dose"),
            "date":      _temporal_text(r.get("date")),
            "record_id": r.get("record_id"),
        }
        for r in esquema_rows if r.get("estado") == "Aplicada"
    ]

    # [REFACTORED] Eliminado cita_aceptada_tutor (flujo deprecado).
    next_vaccines = [
        {
            "name":           r.get("name"),
            "dose":           r.get("dose"),
            "edad_ideal":     r.get("edad_ideal_label"),
            "dias_retraso":   r.get("dias_retraso") or 0,
            "alerta_retraso": r.get("alerta_retraso"),
            "estado":         r.get("estado"),
            "schedule_id":    r.get("schedule_id"),
            "fecha_cita":     _temporal_text(r.get("fecha_cita")),
            "cita_estado":    r.get("cita_estado"),
            "appointment_id": r.get("appointment_id"),
        }
        for r in esquema_rows
        if r.get("estado") in ("Pendiente", "Pendiente con retraso")
    ]

    total_applied = len(applications)
    total_pending = len(next_vaccines)
    total_doses   = total_applied + total_pending
    pct           = int(total_applied / total_doses * 100) if total_doses > 0 else 0

    return render_template(
        "tutor/esquema.html",
        today=date.today().strftime("%A, %d de %B de %Y"),
        patient=patient,
        applications=applications,
        next_vaccines=next_vaccines,
        total_applied=total_applied,
        total_pending=total_pending,
        total_doses=total_doses,
        pct=pct,
        **vars_,
    )


@app.route("/tutor/citas")
def tutor_citas():
    # [REFACTORED] sp_get_tutor_pending_citas y sp_get_tutor_citas_history
    #              deprecados (usaban tutor_accepted IS NULL).
    #              Ahora consulta v_appointments_full directamente:
    #              - pending  → Programada / Confirmada
    #              - history  → Completada / Cancelada / No Show
    locked = _require_tutor()
    if locked:
        return locked

    vars_       = _tutor_session_vars()
    guardian_id = vars_["guardian_id"]
    all_citas   = []                         # inicializar siempre antes del try

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT af.appointment_id,
                       af.scheduled_at,
                       af.appointment_status,
                       af.reason,
                       af.appointment_notes,
                       af.cancel_reason,
                       af.patient_name,
                       af.clinic_name,
                       af.area_name,
                       af.worker_name,
                       af.vaccine_name,
                       af.dose_label,
                       af.dose_due_date,
                       af.patient_id
                FROM   v_appointments_full af
                JOIN   patient_guardian_relations pgr
                       ON pgr.patient_id = af.patient_id
                WHERE  pgr.guardian_id = %s
                ORDER  BY af.scheduled_at DESC;
            """, (guardian_id,))
            all_citas = [dict(r) for r in cur.fetchall()]
        conn.commit()
    except Exception as e:
        _safe_rollback(conn)
        logger.error("Error en tutor_citas: %s", e)
        flash("Error al cargar las citas.", "danger")
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    ACTIVE_STATES  = {"Programada", "Confirmada"}
    HISTORY_STATES = {"Completada", "Cancelada", "No Show"}

    def _fmt_cita(c):
        return {**c, "scheduled_at": _temporal_text(c.get("scheduled_at")),
                "dose_due_date": _temporal_text(c.get("dose_due_date"))}

    pending_citas = [_fmt_cita(c) for c in all_citas
                     if c.get("appointment_status") in ACTIVE_STATES]
    history_citas = [_fmt_cita(c) for c in all_citas
                     if c.get("appointment_status") in HISTORY_STATES]

    return render_template(
        "tutor/citas.html",
        today=date.today().strftime("%A, %d de %B de %Y"),
        pending_citas=pending_citas,
        history_citas=history_citas,
        **vars_,
    )


# [ELIMINADO] tutor_cita_responder — Ruta eliminada.
# La lógica de tutor_accepted (aceptar/rechazar citas auto-generadas) fue
# deprecada junto con el Trigger 11. Las citas ahora se crean manualmente
# a través de tutor_agendar y se cancelan a través de tutor_cancelar_cita.


@app.route("/tutor/agendar", methods=["GET", "POST"])
def tutor_agendar():
    """Permite al tutor crear una cita manualmente para uno de sus hijos."""
    locked = _require_tutor()
    if locked:
        return locked

    vars_       = _tutor_session_vars()
    guardian_id = vars_["guardian_id"]

    # ── GET: mostrar formulario ────────────────────────────────────────────
    if request.method == "GET":
        conn, should_close = _get_conn()
        _safe_rollback(conn)
        try:
            with conn.cursor() as cur:
                # Hijos del tutor
                cur.execute("""
                    SELECT p.patient_id,
                           TRIM(p.first_name || ' ' || p.last_name) AS full_name
                    FROM   patient_guardian_relations pgr
                    JOIN   patients p ON p.patient_id = pgr.patient_id
                    WHERE  pgr.guardian_id = %s AND p.is_active = TRUE
                    ORDER  BY p.first_name;
                """, (guardian_id,))
                children = [dict(r) for r in cur.fetchall()]

                # Clínicas activas
                cur.execute("""
                    SELECT clinic_id, name
                    FROM   clinics
                    WHERE  is_active = TRUE
                    ORDER  BY name;
                """)
                clinics = [dict(r) for r in cur.fetchall()]
            conn.commit()
        except Exception as e:
            _safe_rollback(conn)
            logger.error("Error en tutor_agendar GET: %s", e)
            flash("Error al cargar el formulario.", "danger")
            return redirect(url_for("tutor_citas"))
        finally:
            if should_close and not _conn_is_closed(conn):
                conn.close()

        return render_template(
            "tutor/agendar.html",
            today=date.today().strftime("%A, %d de %B de %Y"),
            today_iso=date.today().isoformat(),   # para min del datetime-local
            children=children,
            clinics=clinics,
            **vars_,
        )

    # ── POST: crear cita vía sp_create_appointment ─────────────────────────
    patient_id          = request.form.get("patient_id", type=int)
    clinic_id           = request.form.get("clinic_id", type=int)
    scheduled_at_str    = request.form.get("scheduled_at", "").strip()
    reason              = request.form.get("reason", "").strip() or None
    patient_schedule_id = request.form.get("patient_schedule_id", type=int)   # opcional

    if not all([patient_id, clinic_id, scheduled_at_str]):
        flash("Paciente, clínica y fecha son obligatorios.", "warning")
        return redirect(url_for("tutor_agendar"))

    if not _tutor_owns_patient(guardian_id, patient_id):
        flash("No tienes acceso a este paciente.", "danger")
        return redirect(url_for("tutor_agendar"))

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute(
                "CALL sp_create_appointment(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
                (
                    patient_id,
                    clinic_id,
                    None,           # area_id (opcional)
                    None,           # worker_id (el tutor no asigna médico)
                    scheduled_at_str,
                    reason,
                    patient_schedule_id,
                    "Tutor",        # created_by_role
                    None,           # created_by_worker_id
                    guardian_id,    # created_by_guardian_id
                    "cur_agendar",
                ),
            )
            cur.execute('FETCH ALL FROM "cur_agendar"')
            result = cur.fetchone()
        conn.commit()
        flash("Cita agendada correctamente.", "success")
    except Exception as e:
        _safe_rollback(conn)
        logger.error("Error en tutor_agendar POST: %s", e)
        flash(f"No se pudo agendar la cita: {e}", "danger")
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    return redirect(url_for("tutor_citas"))


@app.route("/tutor/cita/<int:appointment_id>/cancelar", methods=["POST"])
def tutor_cancelar_cita(appointment_id):
    """Cancela una cita que pertenece a un hijo del tutor autenticado."""
    locked = _require_tutor()
    if locked:
        return locked

    guardian_id = session.get("guardian_id")
    cancel_reason = request.form.get("cancel_reason", "Cancelada por tutor").strip()

    # Verificar propiedad usando patient_id directo en appointments
    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT 1
                FROM   appointments a
                JOIN   patient_guardian_relations pgr
                       ON pgr.patient_id = a.patient_id
                WHERE  a.appointment_id = %s
                  AND  pgr.guardian_id  = %s
                LIMIT  1;
            """, (appointment_id, guardian_id))
            if not cur.fetchone():
                flash("Cita no encontrada o sin permiso.", "danger")
                return redirect(url_for("tutor_citas"))

            cur.execute("CALL sp_cancel_appointment(%s, %s, %s)",
                        (appointment_id, cancel_reason, "cur_cancel"))
            cur.execute('FETCH ALL FROM "cur_cancel"')
        conn.commit()
        flash("Cita cancelada.", "info")
    except Exception as e:
        _safe_rollback(conn)
        logger.error("Error en tutor_cancelar_cita: %s", e)
        flash(f"No se pudo cancelar la cita: {e}", "danger")
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    return redirect(url_for("tutor_citas"))


# ── Helpers PDF / QR ──────────────────────────────────────────────────────────

def _verification_token(record_id, patient_id):
    """Genera un token corto para el QR de verificación."""
    import hashlib
    raw = f"{record_id}:{patient_id}:{app.secret_key}"
    return hashlib.sha256(raw.encode()).hexdigest()[:16].upper()


def _generate_qr_png(data, fill_color="#6B007C"):
    """Devuelve un BytesIO con la imagen PNG del QR, o None si qrcode no está."""
    try:
        import qrcode as _qr
        import io as _io
        q = _qr.QRCode(version=1, box_size=8, border=3,
                        error_correction=_qr.constants.ERROR_CORRECT_M)
        q.add_data(data)
        q.make(fit=True)
        img = q.make_image(fill_color=fill_color, back_color="white")
        buf = _io.BytesIO()
        img.save(buf, format="PNG")
        buf.seek(0)
        return buf
    except Exception:
        return None


def _generate_comprobante_pdf(record):
    """Genera PDF de comprobante. Devuelve (BytesIO, None) o (None, error_str)."""
    try:
        import io as _io
        from reportlab.lib.pagesizes import A4
        from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer,
                                         Table, TableStyle, HRFlowable)
        from reportlab.platypus import Image as RLImage
        from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
        from reportlab.lib                import colors
        from reportlab.lib.units          import cm
        from reportlab.lib.enums          import TA_CENTER, TA_LEFT
    except ImportError:
        return None, "Librería reportlab no instalada. Ejecuta: pip install reportlab"

    PRIMARY   = colors.HexColor("#6B007C")
    SECONDARY = colors.HexColor("#4B1535")
    SUCCESS   = colors.HexColor("#1D7B00")
    GRAY      = colors.HexColor("#49454f")
    LIGHT     = colors.HexColor("#f4eff8")
    WHITE     = colors.white

    styles = getSampleStyleSheet()

    def _sty(name, **kw):
        return ParagraphStyle(name, parent=styles["Normal"], **kw)

    S_TITLE    = _sty("T", fontSize=18, fontName="Helvetica-Bold",  textColor=PRIMARY,   alignment=TA_CENTER)
    S_SUB      = _sty("S", fontSize=10, fontName="Helvetica",       textColor=GRAY,      alignment=TA_CENTER)
    S_SEC_HDR  = _sty("H", fontSize=9,  fontName="Helvetica-Bold",  textColor=WHITE)
    S_LABEL    = _sty("L", fontSize=8,  fontName="Helvetica",       textColor=GRAY,      spaceBefore=0, spaceAfter=1)
    S_VALUE    = _sty("V", fontSize=10, fontName="Helvetica-Bold",  textColor=colors.HexColor("#1a1a1a"), spaceAfter=3)
    S_FOOTER   = _sty("F", fontSize=7,  fontName="Helvetica",       textColor=GRAY,      alignment=TA_CENTER)

    buf = _io.BytesIO()
    doc = SimpleDocTemplate(
        buf, pagesize=A4,
        rightMargin=2*cm, leftMargin=2*cm,
        topMargin=2*cm,   bottomMargin=2*cm,
        title=f"Comprobante — {record.get('patient_name', '')}",
    )
    story = []

    # ── Logo + título ────────────────────────────────────────────────────
    logo_path = os.path.join(app.root_path, "static", "css", "img", "logo.png")
    hdr_cells = []
    if os.path.exists(logo_path):
        hdr_cells.append(RLImage(logo_path, width=1.1*cm, height=1.1*cm))
    hdr_cells.append(Paragraph("ImmuniCare", S_TITLE))

    hdr_tbl = Table([hdr_cells],
                    colWidths=([1.4*cm] if os.path.exists(logo_path) else []) + ["*"])
    hdr_tbl.setStyle(TableStyle([
        ("VALIGN",       (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING",  (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
    ]))
    story.append(hdr_tbl)
    story.append(Paragraph("Comprobante de Vacunación", S_SUB))
    story.append(Spacer(1, 0.35*cm))
    story.append(HRFlowable(width="100%", thickness=2, color=PRIMARY))
    story.append(Spacer(1, 0.4*cm))

    def _section_header(text, color=PRIMARY):
        t = Table([[Paragraph(f"  {text}", S_SEC_HDR)]], colWidths=["*"])
        t.setStyle(TableStyle([
            ("BACKGROUND",     (0, 0), (-1, -1), color),
            ("TOPPADDING",     (0, 0), (-1, -1), 4),
            ("BOTTOMPADDING",  (0, 0), (-1, -1), 4),
            ("LEFTPADDING",    (0, 0), (-1, -1), 6),
        ]))
        return t

    def _row(label, value):
        return [Paragraph(label, S_LABEL), Paragraph(str(value or "—"), S_VALUE)]

    # ── Datos del paciente ────────────────────────────────────────────────
    story.append(_section_header("Datos del Paciente"))
    story.append(Spacer(1, 0.25*cm))

    pat_rows = [
        _row("Nombre completo",       record.get("patient_name")),
        _row("CURP",                  record.get("curp")),
        _row("Fecha de nacimiento",   str(record.get("birth_date") or "—")[:10]),
        _row("Edad",                  f"{record.get('age_years', '—')} año(s)"),
    ]

    # QR para embeber junto a los datos del paciente
    token   = _verification_token(record["record_id"], record["patient_id"])
    qr_data = f"IMMUNICARE://VERIFY/{record['record_id']}/{token}"
    qr_buf  = _generate_qr_png(qr_data, fill_color="#6B007C")

    if qr_buf:
        qr_img  = RLImage(qr_buf, width=2.8*cm, height=2.8*cm)
        qr_cell = Table(
            [[Paragraph("Código de verificación", S_LABEL)], [qr_img]],
            colWidths=[3.2*cm],
        )
        pat_tbl = Table([[
            Table(pat_rows, colWidths=[3.5*cm, 8.3*cm]),
            qr_cell,
        ]], colWidths=["*", 3.2*cm])
        pat_tbl.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP")]))
    else:
        pat_tbl = Table(pat_rows, colWidths=[3.5*cm, "*"])

    pat_tbl.setStyle(TableStyle([
        ("VALIGN",      (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING",  (0, 0), (-1, -1), 2),
        ("BOTTOMPADDING",(0, 0), (-1, -1), 1),
    ]))
    story.append(pat_tbl)
    story.append(Spacer(1, 0.4*cm))

    # ── Datos de la vacuna ────────────────────────────────────────────────
    story.append(_section_header("Información de la Vacuna", color=SECONDARY))
    story.append(Spacer(1, 0.25*cm))

    app_date = str(record.get("applied_date") or "—")[:10]

    vac_data = [
        [Paragraph("Vacuna",             S_LABEL), Paragraph(str(record.get("vaccine_name") or "—"), S_VALUE),
         Paragraph("Dosis",              S_LABEL), Paragraph(str(record.get("dose_label")   or "—"), S_VALUE)],
        [Paragraph("Fecha de aplicación",S_LABEL), Paragraph(app_date, S_VALUE),
         Paragraph("Médico",             S_LABEL), Paragraph(str(record.get("worker_name")  or "—"), S_VALUE)],
        [Paragraph("Clínica",            S_LABEL), Paragraph(str(record.get("clinic_name")  or "—"), S_VALUE),
         Paragraph("Lote",               S_LABEL), Paragraph(str(record.get("lot_number")   or "—"), S_VALUE)],
        [Paragraph("Sitio de aplicación",S_LABEL), Paragraph(str(record.get("application_site") or "—"), S_VALUE),
         Paragraph("Temperatura",        S_LABEL),
         Paragraph(f"{record['patient_temp_c']}°C" if record.get("patient_temp_c") else "—", S_VALUE)],
    ]

    vac_tbl = Table(vac_data, colWidths=[3.5*cm, 6.3*cm, 2.8*cm, 4.4*cm])
    vac_tbl.setStyle(TableStyle([
        ("VALIGN",        (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING",    (0, 0), (-1, -1), 3),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
        ("ROWBACKGROUNDS",(0, 0), (-1, -1), [WHITE, LIGHT]),
    ]))
    story.append(vac_tbl)
    story.append(Spacer(1, 0.8*cm))

    # ── Footer ────────────────────────────────────────────────────────────
    story.append(HRFlowable(width="100%", thickness=0.5, color=GRAY))
    story.append(Spacer(1, 0.2*cm))
    story.append(Paragraph(
        f"Generado el {date.today().strftime('%d/%m/%Y')}  ·  "
        f"ImmuniCare — Sistema Clínico de Vacunación  ·  "
        f"ID de registro: {record['record_id']}  ·  "
        f"Token: {token}",
        S_FOOTER,
    ))

    doc.build(story)
    buf.seek(0)
    return buf, None


# ── Rutas Sprint 4 ────────────────────────────────────────────────────────────

@app.route("/tutor/comprobante/<int:record_id>")
def tutor_comprobante(record_id):
    locked = _require_tutor()
    if locked:
        return locked

    guardian_id = session.get("guardian_id")

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    vr.record_id,
                    vr.patient_id,
                    vr.applied_date,
                    vr.patient_temp_c,
                    vr.had_reaction,
                    TRIM(p.first_name || ' ' || p.last_name) AS patient_name,
                    p.curp,
                    p.birth_date,
                    DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT AS age_years,
                    v.name                                    AS vaccine_name,
                    v.commercial_name,
                    COALESCE(TRIM(w.first_name||' '||w.last_name), '—') AS worker_name,
                    COALESCE(sd.dose_label, '—')              AS dose_label,
                    COALESCE(aps.application_site, '—')       AS application_site,
                    c.name                                    AS clinic_name,
                    COALESCE(vl.lot_number, '—')              AS lot_number
                FROM   vaccination_records vr
                JOIN   patients p   ON p.patient_id  = vr.patient_id
                JOIN   vaccines v   ON v.vaccine_id  = vr.vaccine_id
                JOIN   workers  w   ON w.worker_id   = vr.worker_id
                JOIN   clinics  c   ON c.clinic_id   = vr.clinic_id
                LEFT JOIN scheme_doses     sd  ON sd.dose_id              = vr.scheme_dose_id
                LEFT JOIN application_sites aps ON aps.application_site_id = vr.application_site_id
                LEFT JOIN vaccine_lots     vl  ON vl.lot_id               = vr.lot_id
                WHERE  vr.record_id = %s
                LIMIT  1;
            """, (record_id,))
            row = cur.fetchone()
        conn.commit()
    except Exception as e:
        _safe_rollback(conn)
        logger.error("Error en tutor_comprobante: %s", e)
        flash("Error al cargar el comprobante.", "danger")
        return redirect(url_for("tutor_dashboard"))
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    if not row:
        flash("Registro de vacunación no encontrado.", "danger")
        return redirect(url_for("tutor_dashboard"))

    # Verificar propiedad
    if not _tutor_owns_patient(guardian_id, row["patient_id"]):
        flash("No tienes acceso a este comprobante.", "danger")
        return redirect(url_for("tutor_dashboard"))

    record = dict(row)

    pdf_buf, error = _generate_comprobante_pdf(record)
    if error:
        flash(f"No se pudo generar el PDF: {error}", "danger")
        return redirect(url_for("tutor_esquema", patient_id=record["patient_id"]))

    from flask import send_file as _send_file
    safe_name = record["patient_name"].replace(" ", "_")[:30]
    filename  = f"comprobante_{safe_name}_{record_id}.pdf"
    return _send_file(
        pdf_buf,
        mimetype="application/pdf",
        as_attachment=True,
        download_name=filename,
    )


@app.route("/tutor/qr/<int:patient_id>")
def tutor_qr(patient_id):
    locked = _require_tutor()
    if locked:
        return locked

    vars_       = _tutor_session_vars()
    guardian_id = vars_["guardian_id"]

    if not _tutor_owns_patient(guardian_id, patient_id):
        flash("No tienes acceso a este paciente.", "danger")
        return redirect(url_for("tutor_dashboard"))

    # Datos básicos del paciente para mostrar en la página
    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT p.patient_id,
                       TRIM(p.first_name || ' ' || p.last_name) AS full_name,
                       p.birth_date,
                       p.curp,
                       p.photo,
                       DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT AS age_years,
                       COALESCE(bt.blood_type, '—') AS blood_type
                FROM patients p
                LEFT JOIN blood_types bt ON bt.blood_type_id = p.blood_type_id
                WHERE p.patient_id = %s AND p.is_active = TRUE
                LIMIT 1;
            """, (patient_id,))
            row = cur.fetchone()
        conn.commit()
    except Exception as e:
        _safe_rollback(conn)
        logger.error("Error en tutor_qr: %s", e)
        row = None
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    if not row:
        flash("Paciente no encontrado.", "danger")
        return redirect(url_for("tutor_dashboard"))

    patient = dict(row)
    fn      = patient.get("full_name", "")
    parts   = fn.split()
    patient["initials"] = (fn[:1] + (parts[-1][:1] if len(parts) > 1 else "")).upper()
    patient["photo_url"] = (
        f"/static/uploads/patients/{patient['photo']}" if patient.get("photo") else None
    )
    patient["birth_date"] = _temporal_text(patient.get("birth_date"))

    # Generar QR como base64 para embeberlo en el HTML
    qr_data = f"IMMUNICARE://PACIENTE/{patient_id}/CURP/{patient.get('curp') or 'N/A'}"
    qr_buf  = _generate_qr_png(qr_data, fill_color="#6B007C")

    import base64
    qr_b64 = (
        base64.b64encode(qr_buf.read()).decode("utf-8")
        if qr_buf else None
    )

    return render_template(
        "tutor/qr.html",
        today=date.today().strftime("%A, %d de %B de %Y"),
        patient=patient,
        qr_b64=qr_b64,
        qr_data=qr_data,
        **vars_,
    )


@app.route("/tutor/qr/<int:patient_id>/imagen")
def tutor_qr_imagen(patient_id):
    """Devuelve el QR como PNG descargable."""
    locked = _require_tutor()
    if locked:
        return redirect(url_for("tutor_login"))

    guardian_id = session.get("guardian_id")
    if not _tutor_owns_patient(guardian_id, patient_id):
        return ("Acceso denegado", 403)

    qr_data = f"IMMUNICARE://PACIENTE/{patient_id}"
    qr_buf  = _generate_qr_png(qr_data)
    if not qr_buf:
        return ("qrcode no instalado", 503)

    from flask import send_file as _send_file
    return _send_file(
        qr_buf,
        mimetype="image/png",
        as_attachment=True,
        download_name=f"qr_paciente_{patient_id}.png",
    )


# =============================================================================
# RUTAS — dashboard
# =============================================================================

@app.route("/dashboard")
def dashboard():
    locked = _require_role("Administrador", "Recepcionista", "Medico", "Almacen")
    if locked:
        return locked

    try:
        conn, should_close = _get_conn()
        _safe_rollback(conn)
        kpis         = {}
        top_patients = []
        chart_rows   = []
        try:
            with conn.cursor() as cur:

                # 1. KPIs y alertas
                cur.execute("CALL sp_dashboard_kpis(%s)", ("cur_kpis",))
                cur.execute('FETCH ALL FROM "cur_kpis"')
                kpis = dict(cur.fetchone() or {})

                # 2. Últimos 10 pacientes (reutiliza sp_get_patients con límite)
                cur.execute("CALL sp_get_patients_full(%s, %s)", (10, "cur_top_patients"))
                cur.execute('FETCH ALL FROM "cur_top_patients"')
                top_patients = [dict(r) for r in cur.fetchall()]

                # 3. Datos para las 3 gráficas

                #cur.execute("CALL sp_dashboard_charts(%s)", ("cur_charts",))
                #cur.execute('FETCH ALL FROM "cur_charts"')
                #chart_rows = cur.fetchall()

            conn.commit()
        except Exception:
            import traceback
            logger.error(f"[SP ERROR] dashboard:\n{traceback.format_exc()}")
            _safe_rollback(conn)
        finally:
            if should_close and not _conn_is_closed(conn):
                conn.close()

        # Separar filas de gráficas por tipo
        coverage_by_age  = [
            {"label": r["label"], "value": float(r["value"] or 0)}
            for r in chart_rows if r.get("chart") == "coverage"
        ]
        doses_by_month   = [
            {"label": r["label"], "value": float(r["value"] or 0)}
            for r in chart_rows if r.get("chart") == "monthly"
        ]
        delay_by_vaccine = [
            {"label": r["label"], "value": float(r["value"] or 0)}
            for r in chart_rows if r.get("chart") == "delay"
        ]

        context = {
            **_session_vars(),
            "today":              date.today().strftime("%d/%m/%Y"),
            # KPIs
            "total_patients":     kpis.get("total_patients",     0),
            "coverage_pct":       kpis.get("coverage_pct",       0),
            "coverage_trend":     kpis.get("coverage_trend",     0),
            "delayed_patients":   kpis.get("delayed_patients",   0),
            "applications_today": kpis.get("applications_today", 0),
            "doses_this_week":    kpis.get("doses_this_week",    0),
            "doses_this_month":   kpis.get("doses_this_month",   0),
            "monthly_trend":      kpis.get("monthly_trend",      0),
            "expired_doses":      kpis.get("expired_doses",      0),
            "new_patients_month": kpis.get("new_patients_month", 0),
            # Alertas
            "pending_alerts":     kpis.get("pending_alerts",     0),
            "patients_critical":  kpis.get("patients_critical",  0),
            "expiring_lots_week": kpis.get("expiring_lots_week", 0),
            "low_stock_count":    kpis.get("low_stock_count",    0),
            # Tabla
            "top_patients":       top_patients,
            # Gráficas
            "coverage_by_age":    coverage_by_age,
            "doses_by_month":     doses_by_month,
            "delay_by_vaccine":   delay_by_vaccine,
        }

        session["last_visit"] = date.today().isoformat()
        return render_template("pages/index_2daE.html", **context)

    except Exception as e:
        logger.error(f"Error en /dashboard: {e}")
        flash("Error al cargar dashboard", "danger")
        return redirect(url_for("login"))


# =============================================================================
# RUTAS — pacientes
# =============================================================================

@app.route("/pacientes")
def pacientes():
    locked = _require_role("Administrador", "Recepcionista", "Medico", "Enfermero")
    if locked:
        return locked

    try:
        conn, should_close = _get_conn()
        _safe_rollback(conn)
        try:
            with conn.cursor() as cur:
                cur.execute("CALL sp_get_patients_full(%s, %s)", (None, "cur_patients_full"))
                cur.execute('FETCH ALL FROM "cur_patients_full"')
                patients = [dict(r) for r in cur.fetchall()]
            conn.commit()
        except Exception as sp_err:
            import traceback
            logger.error(f"[SP ERROR] sp_get_patients_full falló:\n{traceback.format_exc()}")
            _safe_rollback(conn)
            patients = []
        finally:
            if should_close and not _conn_is_closed(conn):
                conn.close()

        return render_template(
            "pages/pacientes_2daE.html",
            **_session_vars(),
            total_patients=len(patients),
            patients=patients,
        )
    except Exception as e:
        import traceback
        logger.error(f"Error en /pacientes: {e}\n{traceback.format_exc()}")
        flash("Error al cargar pacientes", "danger")
        return redirect(url_for("dashboard"))


# ---------------------------------------------------------------------------
# Mapa de mensajes de error del SP → mensajes amigables en español
# ---------------------------------------------------------------------------
_PATIENT_ERROR_MAP = {
    "El nombre es obligatorio":
        "El nombre del paciente es obligatorio.",
    "El apellido es obligatorio":
        "El apellido del paciente es obligatorio.",
    "La fecha de nacimiento no puede ser futura":
        "La fecha de nacimiento no puede ser una fecha futura.",
    "El paciente excede la edad pediatrica permitida":
        "El paciente supera la edad máxima permitida (10 años) para este sistema pediátrico.",
    "Genero invalido":
        "El género seleccionado no es válido. Selecciona Masculino o Femenino.",
    "CURP invalida":
        "La CURP debe tener exactamente 18 caracteres.",
    "El CURP ya existe":
        "Ya existe un paciente registrado con ese CURP.",
    "El CURP ingresado ya esta registrado":
        "Ya existe un paciente registrado con ese CURP.",
    "Peso fuera de rango pediatrico":
        "El peso debe estar entre 0.1 y 80 kg para pacientes pediátricos.",
    "Tipo sanguineo inexistente":
        "El tipo de sangre seleccionado no es válido.",
    "Telefono invalido":
        "El teléfono del tutor debe tener al menos 10 dígitos.",
    "Ya existe un registro con esos datos. Verifique el CURP o el tutor":
        "Ya existe un registro con esos datos. Verifica el CURP o los datos del tutor.",
    "Referencia invalida: tipo de sangre o clinica no encontrada":
        "El tipo de sangre o la clínica seleccionada no existe en el sistema.",
    "Faltan datos obligatorios":
        "Faltan campos obligatorios. Revisa el formulario.",
}

def _translate_patient_error(msg: str) -> str:
    """Traduce un mensaje de error del SP a un mensaje amigable en español."""
    msg = (msg or "").strip()
    # Coincidencia exacta primero
    friendly = _PATIENT_ERROR_MAP.get(msg)
    if friendly:
        return friendly
    # Coincidencia parcial para errores crudos de PostgreSQL
    msg_lower = msg.lower()
    if "duplicate key" in msg_lower or "unique" in msg_lower:
        return "Ya existe un registro con esos datos. Verifica el CURP o los datos del tutor."
    if "foreign key" in msg_lower or "violates foreign" in msg_lower:
        return "Dato de referencia no válido. Verifica el tipo de sangre seleccionado."
    if "not null" in msg_lower:
        return "Faltan campos obligatorios. Revisa el formulario."
    return msg


@app.route("/register_patient", methods=["POST"])
def register_patient():
    if not _check_role("Administrador", "Recepcionista"):
        return jsonify({"error": "Sin permisos"}), 403

    payload = request.get_json(silent=True) or {}
    tutor   = payload.get("tutor") or {}

    # ── Validaciones de formato básico (responsabilidad de Flask) ────────────

    first_name = (payload.get("first_name") or "").strip()
    last_name  = (payload.get("last_name")  or "").strip()
    if not first_name:
        return jsonify({"error": "El nombre del paciente es obligatorio."}), 400
    if not last_name:
        return jsonify({"error": "El apellido del paciente es obligatorio."}), 400

    # Género — el frontend manda "M" o "F" (ya convertido en el JS)
    gender_raw  = (payload.get("gender") or "").strip().upper()
    gender_code = {"M": "M", "F": "F"}.get(gender_raw)
    if not gender_code:
        return jsonify({"error": "El género seleccionado no es válido."}), 400

    # Fecha de nacimiento — debe estar presente
    birth_date_raw = (payload.get("birth_date") or "").strip()
    if not birth_date_raw:
        return jsonify({"error": "La fecha de nacimiento es obligatoria."}), 400

    # CURP — si se proporciona, debe tener exactamente 18 caracteres
    curp_raw = (payload.get("curp") or "").strip().upper()
    curp     = curp_raw or None
    if curp and len(curp) != 18:
        return jsonify({"error": "La CURP debe tener exactamente 18 caracteres."}), 400

    # Peso — debe ser numérico si se proporciona
    weight_raw = payload.get("weight") or payload.get("weight_kg")
    try:
        weight_kg = float(weight_raw) if weight_raw not in (None, "") else None
    except (ValueError, TypeError):
        return jsonify({"error": "El peso debe ser un número válido (ej: 25.5)."}), 400

    # ── Tipo de sangre — convertir string "O+" a blood_type_id ─────────────
    blood_type_str = (payload.get("blood_type") or "").strip()
    blood_type_id  = None
    if blood_type_str:
        blood_types = _cur_fetchall("blood_types")
        match = next(
            (bt for bt in blood_types
             if (bt.get("blood_type") or "").upper() == blood_type_str.upper()),
            None,
        )
        blood_type_id = match["blood_type_id"] if match else None

    rfc = (payload.get("rfc") or "").strip().upper() or None

    # Tutor existente (si el usuario lo seleccionó del dropdown)
    guardian_id_existing = None
    raw_gid = payload.get("guardian_id")
    if raw_gid:
        try:
            guardian_id_existing = int(raw_gid)
        except (ValueError, TypeError):
            pass

    # ── Llamada al SP (valida reglas de negocio/clínicas/integridad) ─────────
    conn, should_close = _get_conn()
    _safe_rollback(conn)
    row = None
    try:
        with conn.cursor() as cur:

            if guardian_id_existing:
                guardian_name = guardian_last = guardian_curp = None
                guardian_phone = guardian_email = None
            else:
                guardian_name  = (tutor.get("name")    or "").strip() or None
                guardian_last  = (tutor.get("lastname") or "").strip() or None
                guardian_curp  = (tutor.get("curp")     or "").strip() or None
                guardian_phone = (tutor.get("number")   or "").strip() or None
                guardian_email = (tutor.get("mail")     or "").strip() or None

            cur.execute(
                "CALL sp_register_patient(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
                (
                    first_name, last_name, curp, birth_date_raw,
                    gender_code, blood_type_id, weight_kg,
                    payload.get("premature") or False,
                    guardian_name, guardian_last, guardian_curp,
                    guardian_phone, guardian_email,
                    "cur_reg_patient",
                ),
            )
            cur.execute('FETCH ALL FROM "cur_reg_patient"')
            row = cur.fetchone()

            # Continuar solo si el SP confirmó éxito
            if row and row.get("success"):
                patient_id = row.get("patient_id")

                if guardian_id_existing and patient_id:
                    cur.execute(
                        """
                        INSERT INTO patient_guardian_relations
                            (patient_id, guardian_id, relation_type, is_primary, has_custody)
                        VALUES (%s, %s, 'Tutor', TRUE, TRUE)
                        ON CONFLICT DO NOTHING
                        """,
                        (patient_id, guardian_id_existing),
                    )

                if rfc and patient_id:
                    cur.execute(
                        "UPDATE patients SET rfc = %s WHERE patient_id = %s",
                        (rfc, patient_id),
                    )

        conn.commit()

    except psycopg.DatabaseError as ex:
        # Solo errores inesperados llegan aquí (el SP tiene EXCEPTION WHEN OTHERS)
        _safe_rollback(conn)
        logger.error(f"[register_patient] DB error inesperado: {ex}")
        return jsonify({"error": "Error interno de base de datos. Intenta de nuevo."}), 500

    except Exception as ex:
        _safe_rollback(conn)
        logger.error(f"[register_patient] Error inesperado: {ex}")
        return jsonify({"error": "Error inesperado al registrar el paciente."}), 500

    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    if not row:
        return jsonify({"error": "No se recibió respuesta del servidor."}), 500

    # El SP devuelve success=False con el mensaje de error de negocio
    if not row.get("success"):
        raw = (row.get("message") or "Error al registrar el paciente.").split("\n")[0].strip()
        return jsonify({"error": _translate_patient_error(raw)}), 400

    flash(f"Paciente {first_name} {last_name} registrado correctamente.", "success")
    return jsonify({
        "message":    row.get("message", "Paciente registrado"),
        "patient_id": row.get("patient_id"),
    })


_PHOTO_UPLOAD_FOLDER   = os.path.join("static", "uploads", "patients")
_PHOTO_ALLOWED_EXTS    = {"png", "jpg", "jpeg", "webp"}


@app.route("/api/patients/<int:id>")
def api_patient_detail(id):
    if not _check_role("Administrador", "Recepcionista", "Medico", "Enfermero"):
        return jsonify({"error": "Sin permisos"}), 403

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    p.patient_id, p.first_name, p.last_name,
                    p.curp, p.birth_date, p.gender, p.weight_kg,
                    p.nfc_id,
                    COALESCE(bt.blood_type, '')  AS blood_type,
                    g.guardian_id,
                    g.first_name                 AS guardian_first_name,
                    g.last_name                  AS guardian_last_name,
                    g.curp                       AS guardian_curp,
                    (SELECT gp.phone FROM guardian_phones gp
                     WHERE gp.guardian_id = g.guardian_id
                     ORDER BY gp.is_primary DESC LIMIT 1) AS guardian_phone,
                    (SELECT ge.email FROM guardian_emails ge
                     WHERE ge.guardian_id = g.guardian_id
                     ORDER BY ge.is_primary DESC LIMIT 1) AS guardian_email
                FROM patients p
                LEFT JOIN blood_types bt ON bt.blood_type_id = p.blood_type_id
                LEFT JOIN LATERAL (
                    SELECT pgr.guardian_id
                    FROM   patient_guardian_relations pgr
                    WHERE  pgr.patient_id = p.patient_id
                    ORDER  BY pgr.is_primary DESC LIMIT 1
                ) rel ON TRUE
                LEFT JOIN guardians g ON g.guardian_id = rel.guardian_id
                WHERE p.patient_id = %s AND p.is_active = TRUE
            """, (id,))
            row = cur.fetchone()
        conn.commit()
    except Exception as ex:
        _safe_rollback(conn)
        logger.error(f"Error en /api/patients/{id}: {ex}")
        return jsonify({"error": "Error al obtener datos del paciente"}), 500
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    if not row:
        return jsonify({"error": "Paciente no encontrado"}), 404

    data = dict(row)
    if data.get("birth_date"):
        data["birth_date"] = data["birth_date"].isoformat()
    return jsonify(data)


@app.route("/api/paciente/<int:patient_id>/dosis")
def api_patient_doses(patient_id):
    """Devuelve las dosis pendientes/atrasadas de un paciente para el select de 'Vacuna/Dosis'."""
    # Accesible por personal clínico Y tutores.
    is_staff  = _check_role("Administrador", "Recepcionista", "Medico", "Enfermero")
    is_tutor  = "tutor_id" in session
    if not is_staff and not is_tutor:
        return jsonify({"error": "Sin permisos"}), 403

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    pvs.schedule_id        AS patient_schedule_id,
                    v.name                 AS vaccine_name,
                    sd.dose_label,
                    pvs.due_date,
                    pvs.status
                FROM patient_vaccine_schedule pvs
                JOIN scheme_doses sd ON sd.dose_id   = pvs.scheme_dose_id
                JOIN vaccines     v  ON v.vaccine_id = sd.vaccine_id
                WHERE pvs.patient_id = %s
                  AND pvs.status NOT IN ('Aplicada')
                ORDER BY pvs.due_date ASC NULLS LAST, v.name, sd.dose_label
            """, (patient_id,))
            rows = cur.fetchall()
        conn.commit()
    except Exception as e:
        _safe_rollback(conn)
        logger.error("Error en api_patient_doses: %s", e)
        return jsonify({"error": str(e)}), 500
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    dosis = []
    for r in rows:
        d = dict(r)
        if d.get("due_date"):
            d["due_date"] = d["due_date"].isoformat()
        dosis.append(d)

    return jsonify(dosis)


@app.route("/api/guardians")
def api_guardians():
    """Devuelve todos los tutores registrados para el dropdown del modal."""
    if not _check_role("Administrador", "Recepcionista", "Medico"):
        return jsonify({"error": "Sin permisos"}), 403

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    g.guardian_id,
                    g.first_name,
                    g.last_name,
                    g.curp,
                    (SELECT gp.phone
                     FROM   guardian_phones gp
                     WHERE  gp.guardian_id = g.guardian_id
                     ORDER  BY gp.is_primary DESC LIMIT 1) AS phone,
                    (SELECT ge.email
                     FROM   guardian_emails ge
                     WHERE  ge.guardian_id = g.guardian_id
                     ORDER  BY ge.is_primary DESC LIMIT 1) AS email
                FROM guardians g
                ORDER BY g.last_name, g.first_name
            """)
            rows = cur.fetchall()
        conn.commit()
    except Exception as e:
        _safe_rollback(conn)
        logger.error(f"Error en /api/guardians: {e}")
        return jsonify([])
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    return jsonify([dict(r) for r in rows])

@app.route("/patients/<int:id>/photo", methods=["POST"])
def upload_patient_photo(id):
    if not _check_role("Administrador", "Recepcionista"):
        return jsonify({"error": "Sin permisos"}), 403

    if "photo" not in request.files:
        return jsonify({"error": "No se envió ningún archivo"}), 400

    file = request.files["photo"]
    if not file or file.filename == "":
        return jsonify({"error": "No se seleccionó archivo"}), 400

    ext = file.filename.rsplit(".", 1)[-1].lower() if "." in file.filename else ""
    if ext not in _PHOTO_ALLOWED_EXTS:
        return jsonify({"error": "Formato no permitido. Usa JPG, PNG o WEBP"}), 400

    filename = f"P{id}.{ext}"
    os.makedirs(_PHOTO_UPLOAD_FOLDER, exist_ok=True)

    # Eliminar foto anterior con cualquier extensión
    for old_ext in _PHOTO_ALLOWED_EXTS:
        old_path = os.path.join(_PHOTO_UPLOAD_FOLDER, f"P{id}.{old_ext}")
        if os.path.exists(old_path):
            os.remove(old_path)

    file.save(os.path.join(_PHOTO_UPLOAD_FOLDER, filename))

    conn, should_close = _get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE patients SET photo = %s WHERE patient_id = %s",
                (filename, id),
            )
        conn.commit()
    except Exception as ex:
        return jsonify({"error": f"No se pudo guardar la foto: {ex}"}), 500
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    return jsonify({"message": "Foto actualizada", "photo_url": f"/static/uploads/patients/{filename}"})


@app.route("/delete_patient/<int:id>", methods=["POST"])
def delete_patient(id):
    if not _check_role("Administrador"):
        return jsonify({"error": "Sin permisos"}), 403

    patient = _cur_fetchone("patients", "patient_id", id)
    if not patient:
        return jsonify({"error": "Paciente no encontrado"}), 404

    nombre = f"{patient['first_name']} {patient['last_name']}"
    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("CALL sp_delete_patient(%s, %s)", (id, "cur_del_patient"))
            cur.execute('FETCH ALL FROM "cur_del_patient"')
            result = cur.fetchone()
        conn.commit()
    except Exception as ex:
        _safe_rollback(conn)
        logger.error(f"Error en /delete_patient/{id}: {ex}")
        return jsonify({"error": f"No se pudo eliminar el paciente: {ex}"}), 400
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    if result and not result.get("success"):
        return jsonify({"error": result.get("message", "Error al eliminar el paciente")}), 400

    flash(f"Paciente {nombre} eliminado.", "warning")
    return jsonify({"message": "Paciente eliminado"})


@app.route("/update_patient/<int:id>", methods=["POST"])
def update_patient(id):
    if not _check_role("Administrador", "Recepcionista"):
        return jsonify({"error": "Sin permisos"}), 403

    payload        = request.get_json(silent=True) or {}
    first_name     = (payload.get("first_name")  or "").strip() or None
    last_name      = (payload.get("last_name")   or "").strip() or None
    curp           = (payload.get("curp")        or "").strip().upper() or None
    birth_date_raw = (payload.get("birth_date")  or "").strip() or None

    weight_kg = None
    weight_raw = payload.get("weight_kg")
    if weight_raw not in (None, ""):
        try:
            weight_kg = float(str(weight_raw).replace(",", "."))
        except ValueError:
            return jsonify({"error": "El peso debe ser un número válido (ej: 25.5)."}), 400

    blood_type_id = None
    blood_type_str = (payload.get("blood_type") or "").strip()
    if blood_type_str:
        blood_types = _cur_fetchall("blood_types")
        match = next(
            (bt for bt in blood_types
             if (bt.get("blood_type") or "").upper() == blood_type_str.upper()),
            None,
        )
        blood_type_id = match["blood_type_id"] if match else None

    # ── Tutor ────────────────────────────────────────────────────────────────
    tutor_mode           = payload.get("tutor_mode") or "none"
    guardian_id_existing = None
    if tutor_mode == "existing":
        try:
            guardian_id_existing = int(payload.get("guardian_id") or 0) or None
        except (ValueError, TypeError):
            guardian_id_existing = None
    tutor          = payload.get("tutor") or {}
    guardian_name  = (tutor.get("name")     or "").strip() or None
    guardian_last  = (tutor.get("lastname") or "").strip() or None
    guardian_curp  = (tutor.get("curp")     or "").strip().upper() or None
    guardian_phone = (tutor.get("number")   or "").strip() or None
    guardian_email = (tutor.get("mail")     or "").strip() or None

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            # 1. Actualizar datos del paciente via SP
            cur.execute(
                "CALL sp_update_patient(%s::int, %s, %s, %s, %s::date, %s::int, %s::numeric, %s)",
                (id, first_name, last_name, curp, birth_date_raw,
                 blood_type_id, weight_kg, "cur_upd_patient"),
            )
            cur.execute('FETCH ALL FROM "cur_upd_patient"')
            result = cur.fetchone()

            if result and not result.get("success"):
                _safe_rollback(conn)
                raw = (result.get("message") or "Error al actualizar.").split("\n")[0].strip()
                return jsonify({"error": _translate_patient_error(raw)}), 400

            # 2. Vincular tutor existente
            if tutor_mode == "existing" and guardian_id_existing:
                cur.execute("""
                    UPDATE patient_guardian_relations SET is_primary = FALSE
                    WHERE patient_id = %s
                """, (id,))
                cur.execute("""
                    INSERT INTO patient_guardian_relations
                        (patient_id, guardian_id, relation_type, is_primary, has_custody)
                    VALUES (%s, %s, 'Tutor', TRUE, TRUE)
                    ON CONFLICT (patient_id, guardian_id)
                    DO UPDATE SET is_primary = TRUE, has_custody = TRUE
                """, (id, guardian_id_existing))

            # 3. Crear / actualizar tutor nuevo y vincularlo
            elif tutor_mode == "new" and guardian_name:
                new_guardian_id = None

                if guardian_curp:
                    cur.execute(
                        "SELECT guardian_id FROM guardians WHERE curp = %s LIMIT 1",
                        (guardian_curp,)
                    )
                    row = cur.fetchone()
                    if row:
                        new_guardian_id = row["guardian_id"]

                if new_guardian_id is None and guardian_name and guardian_last:
                    cur.execute(
                        "SELECT guardian_id FROM guardians WHERE first_name = %s AND last_name = %s LIMIT 1",
                        (guardian_name, guardian_last)
                    )
                    row = cur.fetchone()
                    if row:
                        new_guardian_id = row["guardian_id"]

                if new_guardian_id is None:
                    cur.execute(
                        "INSERT INTO guardians (first_name, last_name, curp) VALUES (%s, %s, %s) RETURNING guardian_id",
                        (guardian_name, guardian_last or "", guardian_curp)
                    )
                    new_guardian_id = cur.fetchone()["guardian_id"]
                    if guardian_phone:
                        cur.execute(
                            "INSERT INTO guardian_phones (guardian_id, phone, phone_type, is_primary) VALUES (%s, %s, 'Movil', TRUE)",
                            (new_guardian_id, guardian_phone)
                        )
                    if guardian_email:
                        cur.execute(
                            "INSERT INTO guardian_emails (guardian_id, email, is_primary) VALUES (%s, %s, TRUE)",
                            (new_guardian_id, guardian_email)
                        )
                else:
                    cur.execute("""
                        UPDATE guardians SET
                            first_name = COALESCE(NULLIF(%s, ''), first_name),
                            last_name  = COALESCE(NULLIF(%s, ''), last_name),
                            curp       = COALESCE(NULLIF(%s, ''), curp)
                        WHERE guardian_id = %s
                    """, (guardian_name, guardian_last or "", guardian_curp or "", new_guardian_id))
                    if guardian_phone:
                        cur.execute("""
                            INSERT INTO guardian_phones (guardian_id, phone, phone_type, is_primary)
                            VALUES (%s, %s, 'Movil', TRUE)
                            ON CONFLICT DO NOTHING
                        """, (new_guardian_id, guardian_phone))
                    if guardian_email:
                        cur.execute("""
                            INSERT INTO guardian_emails (guardian_id, email, is_primary)
                            VALUES (%s, %s, TRUE)
                            ON CONFLICT DO NOTHING
                        """, (new_guardian_id, guardian_email))

                cur.execute("""
                    UPDATE patient_guardian_relations SET is_primary = FALSE
                    WHERE patient_id = %s
                """, (id,))
                cur.execute("""
                    INSERT INTO patient_guardian_relations
                        (patient_id, guardian_id, relation_type, is_primary, has_custody)
                    VALUES (%s, %s, 'Tutor', TRUE, TRUE)
                    ON CONFLICT (patient_id, guardian_id)
                    DO UPDATE SET is_primary = TRUE, has_custody = TRUE
                """, (id, new_guardian_id))

        conn.commit()
    except Exception as ex:
        _safe_rollback(conn)
        logger.error(f"Error en /update_patient/{id}: {ex}")
        return jsonify({"error": _translate_patient_error(str(ex))}), 400
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    return jsonify({"message": "Paciente actualizado correctamente"})


# =============================================================================
# RUTAS — historial
# =============================================================================

@app.route("/historial")
def historial():
    locked = _require_role("Administrador", "Recepcionista", "Medico", "Enfermero")
    if locked:
        return locked

    try:
        conn, should_close = _get_conn()
        _safe_rollback(conn)
        try:
            with conn.cursor() as cur:
                # Lista de pacientes
                cur.execute("CALL sp_get_patients_full(%s, %s)", (None, "cur_patients_full"))
                cur.execute('FETCH ALL FROM "cur_patients_full"')
                patients = [dict(r) for r in cur.fetchall()]

                # Registros de vacunación
                cur.execute("CALL sp_get_vaccination_records_full(%s)", ("cur_vaccination_records",))
                cur.execute('FETCH ALL FROM "cur_vaccination_records"')
                all_records = cur.fetchall()

            conn.commit()
        except Exception:
            _safe_rollback(conn)
            patients    = []
            all_records = []
        finally:
            if should_close and not _conn_is_closed(conn):
                conn.close()

        patient = patients[0] if patients else None
        records = []
        next_vaccines = []

        if patient:
            pid = patient["patient_id"]
            records = [
                {**dict(r), "date": _temporal_text(r.get("applied_date"))}
                for r in all_records
                if r.get("patient_id") == pid
            ]

            # Próximas vacunas pendientes
            conn2, should_close2 = _get_conn()
            _safe_rollback(conn2)
            try:
                with conn2.cursor() as cur2:
                    cur2.execute("CALL sp_get_pending_scheme_doses(%s, %s)", (pid, "cur_pending_doses"))
                    cur2.execute('FETCH ALL FROM "cur_pending_doses"')
                    pending_rows = cur2.fetchall()
                conn2.commit()
                next_vaccines = [
                    {
                        "name": r.get("vaccine_name") or "—",
                        "dose": r.get("dose_label") or "—",
                        "date": f"A los {r['ideal_age_months']} meses"
                                if r.get("ideal_age_months") is not None else "—",
                    }
                    for r in pending_rows[:3]
                ]
            except Exception:
                _safe_rollback(conn2)
                next_vaccines = []
            finally:
                if should_close2 and not _conn_is_closed(conn2):
                    conn2.close()

        return render_template(
            "pages/historial_2daE.html",
            **_session_vars(),
            patients=patients,
            patient=patient,
            applications=records,
            next_vaccines=next_vaccines,
        )
    except Exception as e:
        logger.error(f"Error en /historial: {e}")
        flash("Error al cargar historial", "danger")
        return redirect(url_for("dashboard"))


@app.route("/historial/<int:id>")
def historial_paciente(id):
    locked = _require_role("Administrador", "Recepcionista", "Medico", "Enfermero")
    if locked:
        return locked

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            # Lista de pacientes (sidebar)
            cur.execute("CALL sp_get_patients_full(%s, %s)", (None, "cur_patients_full"))
            cur.execute('FETCH ALL FROM "cur_patients_full"')
            patients = [dict(r) for r in cur.fetchall()]

            # Registros del paciente específico
            cur.execute("CALL sp_get_vaccination_records_full(%s)", ("cur_vaccination_records",))
            cur.execute('FETCH ALL FROM "cur_vaccination_records"')
            all_records = cur.fetchall()

            # Vacunas pendientes
            cur.execute("CALL sp_get_pending_scheme_doses(%s, %s)", (id, "cur_pending_doses"))
            cur.execute('FETCH ALL FROM "cur_pending_doses"')
            pending_rows = cur.fetchall()

        conn.commit()
    except Exception as e:
        _safe_rollback(conn)
        logger.error(f"Error en /historial/{id}: {e}")
        flash("Error al cargar historial del paciente.", "danger")
        return redirect(url_for("historial"))
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    patient = next((p for p in patients if p.get("patient_id") == id), None)
    if not patient:
        flash("Paciente no encontrado.", "danger")
        return redirect(url_for("historial"))

    session["last_patient_viewed"] = id

    records = [
        {**dict(r), "date": _temporal_text(r.get("applied_date"))}
        for r in all_records
        if r.get("patient_id") == id
    ]
    next_vaccines = [
        {
            "name": r.get("vaccine_name") or "—",
            "dose": r.get("dose_label") or "—",
            "date": f"A los {r['ideal_age_months']} meses"
                    if r.get("ideal_age_months") is not None else "—",
        }
        for r in pending_rows[:3]
    ]

    return render_template(
        "pages/historial_2daE.html",
        **_session_vars(),
        patients=patients,
        patient=patient,
        applications=records,
        next_vaccines=next_vaccines,
    )


# =============================================================================
# RUTAS — esquema paciente / esquema vacunación
# =============================================================================

@app.route("/esquema_paciente/<int:id>")
def esquema_paciente(id):

    locked = _require_role("Administrador", "Medico", "Enfermero")
    if locked:
        return locked

    conn, should_close = _get_conn()
    _safe_rollback(conn)

    try:
        with conn.cursor() as cur:
            cur.execute("CALL sp_get_patient_scheme(%s, %s)", (id, "cur_esquema_paciente"))
            cur.execute('FETCH ALL FROM "cur_esquema_paciente"')
            esquema_rows = [dict(r) for r in cur.fetchall()]
        conn.commit()

    except Exception as e:
        _safe_rollback(conn)
        logger.error(f"Error en /esquema_paciente/{id}: {e}")
        flash("Error al cargar el esquema del paciente.", "danger")
        return redirect(url_for("historial"))

    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    # ============================================================
    # VALIDAR RESULTADOS
    # ============================================================

    if not esquema_rows:

        flash("Paciente no encontrado o sin esquema.", "danger" )
        return redirect(url_for("historial"))


    # ============================================================
    # DATOS DEL PACIENTE
    # ============================================================

    first = esquema_rows[0]

    patient = {
        "patient_id": first.get("patient_id"),
        "full_name": first.get("full_name"),
        "birth_date": first.get("birth_date"),
        "age": first.get("age_years"),
        "initials":
            (
                (first.get("full_name") or "")[:1].upper()
                +
                ((first.get("full_name") or " ").split(" ")[-1][:1].upper())
            ),
    }


    # ============================================================
    # DOSIS APLICADAS
    # ============================================================

    # sp_get_patient_scheme ahora devuelve aliases: name, dose, date, estado,
    # fecha_cita, cita_estado  (antes: vaccine_name, dose_label, applied_date,
    # vaccination_status, appointment_date, appointment_status)
    applications = [
        {
            "record_id":        r.get("record_id"),
            "name":             r.get("name"),
            "dose":             r.get("dose"),
            "date":             _temporal_text(r.get("date")),
            "doctor":           r.get("doctor"),
            "application_site": r.get("application_site"),
            "had_reaction":     r.get("had_reaction"),
            "estado":           r.get("estado"),
        }
        for r in esquema_rows
        if r.get("estado") == "Aplicada"
    ]

    # ============================================================
    # DOSIS PENDIENTES
    # ============================================================
    # "estado" ahora devuelve: "Pendiente", "Pendiente con retraso", "Aplicada"
    pending_rows = [
        r for r in esquema_rows
        if r.get("estado") in ("Pendiente", "Pendiente con retraso")
    ]

    pending_doses = [
        {
            "name":             r.get("name"),
            "dose":             r.get("dose"),
            "edad_ideal":       r.get("edad_ideal_label"),
            "ideal_age_months": r.get("ideal_age_months"),
            "schedule_id":      r.get("schedule_id"),
            "dias_retraso":     r.get("dias_retraso"),
            "alerta_retraso":   r.get("alerta_retraso"),
            "estado":           r.get("estado"),
            "appointment_id":   r.get("appointment_id"),
            "fecha_cita":       _temporal_text(r.get("fecha_cita")),
            "cita_estado":      r.get("cita_estado"),
        }
        for r in pending_rows
    ]

    total_doses   = len(esquema_rows)
    applied_doses = len(applications)
    n_pending     = len(pending_doses)
    progress = round((applied_doses / total_doses) * 100) if total_doses > 0 else 0

    return render_template(
        "pages/esquemaPaciente_2daE.html",
        **_session_vars(),
        patient=patient,
        patient_name=patient.get("full_name", ""),
        applications=applications,
        next_vaccines=pending_doses,
        pending_doses=pending_doses,
        suggested_appointments=[],   # deprecado; siempre vacío
        total_doses=total_doses,
        applied_doses=applied_doses,
        pending_doses_count=n_pending,
        progress=progress,
    )


@app.route("/esquema")
def esquema_vacunacion():
    locked = _require_role("Administrador", "Medico", "Enfermero")
    if locked:
        return locked

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("CALL sp_get_esquema_vacunacion(%s)", ("cur_esquema_vacunacion",))
            cur.execute('FETCH ALL FROM "cur_esquema_vacunacion"')
            rows = cur.fetchall()
        conn.commit()
    except Exception as e:
        _safe_rollback(conn)
        logger.error(f"Error en /esquema: {e}")
        rows = []
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    # Mantener estructura (dose, vaccine) que espera el template
    esquema = [
        (
            row,
            {
                "name":              row.get("vaccine_name", "—"),
                "commercial_name":   row.get("commercial_name", "—"),
                "disease_prevented": row.get("disease_prevented", "—"),
            },
        )
        for row in rows
    ]

    return render_template(
        "pages/esquemaVacunacion_2daE.html",
        **_session_vars(),
        esquema=esquema,
    )


# =============================================================================
# RUTAS — vacunas
# =============================================================================

@app.route("/vacunas")
def vacunas_page():
    locked = _require_role("Administrador", "Medico", "Enfermero", "Almacen")
    if locked:
        return locked

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("CALL sp_get_vaccines_full(%s)", ("cur_vaccines_full",))
            cur.execute('FETCH ALL FROM "cur_vaccines_full"')
            vaccines = [dict(r) for r in cur.fetchall()]
        conn.commit()
    except Exception as e:
        _safe_rollback(conn)
        logger.error(f"Error en /vacunas: {e}")
        vaccines = []
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    lots    = _cur_fetchall("vaccine_lots")
    clinics = _cur_fetchall("clinics")

    return render_template(
        "pages/vacunas_2daE.html",
        **_session_vars(),
        total_vaccines=len(vaccines),
        vaccines=vaccines,
        lots=lots,
        clinics=clinics,
        today=date.today().isoformat(),
    )


@app.route("/register_vaccine", methods=["POST"])
def register_vaccine():
    if not _check_role("Administrador", "Almacen"):
        return jsonify({"error": "Sin permisos"}), 403

    payload = request.get_json(silent=True) or {}
    name    = (payload.get("name") or "").strip()
    if not name:
        return jsonify({"error": "El nombre de vacuna es requerido"}), 400

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute(
                "CALL sp_register_vaccine(%s,%s,%s,%s,%s,%s,%s)",
                (
                    name,
                    payload.get("commercial_name"),
                    payload.get("manufacturer_id"),
                    payload.get("via_id"),
                    payload.get("ideal_age_months"),
                    payload.get("disease_prevented") or payload.get("descripcion") or "No especificado",
                    "cur_reg_vaccine",
                ),
            )
            cur.execute('FETCH ALL FROM "cur_reg_vaccine"')
            row = cur.fetchone()
        conn.commit()
    except Exception as ex:
        _safe_rollback(conn)
        return jsonify({"error": f"No se pudo registrar la vacuna: {ex}"}), 500
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    if not row:
        return jsonify({"error": "No se pudo registrar la vacuna en la base de datos"}), 500

    if not row.get("success"):
        return jsonify({"error": row.get("message", "Error al registrar la vacuna")}), 400

    flash(f"Vacuna '{name}' registrada.", "success")
    return jsonify({"message": row.get("message", "Vacuna registrada"), "vaccine_id": row.get("vaccine_id")})


@app.route("/delete_vaccine/<int:id>", methods=["POST"])
def delete_vaccine(id):
    if not _check_role("Administrador"):
        return jsonify({"error": "Sin permisos"}), 403

    vaccine = _cur_fetchone("vaccines", "vaccine_id", id)
    if not vaccine:
        return jsonify({"error": "Vacuna no encontrada"}), 404

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("CALL sp_delete_vaccine(%s, %s)", (id, "cur_del_vaccine"))
            cur.execute('FETCH ALL FROM "cur_del_vaccine"')
            result = cur.fetchone()
        conn.commit()
    except Exception as ex:
        _safe_rollback(conn)
        return jsonify({"error": f"No se pudo eliminar la vacuna: {ex}"}), 400
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    if result and not result.get("success"):
        return jsonify({"error": result.get("message", "Error al eliminar la vacuna")}), 400

    flash(f"Vacuna '{vaccine['name']}' eliminada.", "warning")
    return jsonify({"message": "Vacuna eliminada"})


@app.route("/create_vaccine_lot", methods=["POST"])
def create_vaccine_lot():
    if not _check_role("Administrador", "Almacen"):
        return jsonify({"error": "Sin permisos"}), 403

    payload      = request.get_json(silent=True) or {}
    vaccine_id   = payload.get("vaccine_id")
    clinic_id    = payload.get("clinic_id")
    lot_number   = (payload.get("lot_number") or "").strip()
    qty_received = payload.get("quantity_received")
    exp_date     = payload.get("expiration_date")

    if not all([vaccine_id, clinic_id, lot_number, qty_received, exp_date]):
        return jsonify({"error": "Todos los campos son requeridos"}), 400

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute(
                "CALL sp_create_vaccine_lot(%s,%s,%s,%s,%s,%s)",
                (vaccine_id, clinic_id, lot_number, int(qty_received), exp_date, "cur_create_lot"),
            )
            cur.execute('FETCH ALL FROM "cur_create_lot"')
            row = cur.fetchone()
        conn.commit()
    except Exception as ex:
        _safe_rollback(conn)
        return jsonify({"error": f"No se pudo crear el lote: {ex}"}), 500
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    if not row:
        return jsonify({"error": "No se pudo crear el lote"}), 500

    flash(f"Lote '{lot_number}' agregado al inventario.", "success")
    return jsonify({"message": "Lote creado", "lot_id": row.get("lot_id")})


@app.route("/update_vaccine_lot_stock", methods=["POST"])
def update_vaccine_lot_stock():
    if not _check_role("Administrador", "Almacen"):
        return jsonify({"error": "Sin permisos"}), 403

    payload   = request.get_json(silent=True) or {}
    lot_id    = payload.get("lot_id")
    qty_avail = payload.get("quantity_available")

    if lot_id is None or qty_avail is None:
        return jsonify({"error": "lot_id y quantity_available son requeridos"}), 400

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute(
                "CALL sp_update_vaccine_lot_stock(%s,%s,%s)",
                (int(lot_id), int(qty_avail), "cur_upd_stock"),
            )
            cur.execute('FETCH ALL FROM "cur_upd_stock"')
            row = cur.fetchone()
        conn.commit()
    except Exception as ex:
        _safe_rollback(conn)
        return jsonify({"error": f"No se pudo actualizar el stock: {ex}"}), 500
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    if row and not row.get("success", True):
        return jsonify({"error": "Lote no encontrado"}), 404

    return jsonify({"message": "Stock actualizado"})


@app.route("/delete_vaccine_lot/<int:lot_id>", methods=["POST"])
def delete_vaccine_lot(lot_id):
    if not _check_role("Administrador", "Almacen"):
        return jsonify({"error": "Sin permisos"}), 403

    lot = _cur_fetchone("vaccine_lots", "lot_id", lot_id)
    if not lot:
        return jsonify({"error": "Lote no encontrado"}), 404

    today = date.today()
    exp   = lot.get("expiration_date")
    if exp and (exp if isinstance(exp, type(today)) else date.fromisoformat(str(exp))) > today:
        return jsonify({"error": "Solo se pueden desactivar lotes vencidos"}), 400

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute(
                "CALL sp_deactivate_vaccine_lot(%s,%s)",
                (lot_id, "cur_deact_lot"),
            )
            cur.execute('FETCH ALL FROM "cur_deact_lot"')
            row = cur.fetchone()
        conn.commit()
    except Exception as ex:
        _safe_rollback(conn)
        return jsonify({"error": f"No se pudo desactivar el lote: {ex}"}), 500
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    if row and not row.get("success", True):
        return jsonify({"error": "No se pudo desactivar el lote"}), 400

    flash(f"Lote '{lot['lot_number']}' desactivado.", "warning")
    return jsonify({"message": "Lote desactivado"})


@app.route("/edit_vaccine_lot/<int:lot_id>", methods=["POST"])
def edit_vaccine_lot(lot_id):
    if not _check_role("Administrador", "Almacen"):
        return jsonify({"error": "Sin permisos"}), 403

    payload      = request.get_json(silent=True) or {}
    clinic_id    = payload.get("clinic_id")
    lot_number   = (payload.get("lot_number") or "").strip()
    qty_received = payload.get("quantity_received")
    exp_date     = payload.get("expiration_date")

    if not all([clinic_id, lot_number, qty_received, exp_date]):
        return jsonify({"error": "Todos los campos son requeridos"}), 400

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute(
                "CALL sp_edit_vaccine_lot(%s,%s,%s,%s,%s,%s)",
                (lot_id, int(clinic_id), lot_number, int(qty_received), exp_date, "cur_edit_lot"),
            )
            cur.execute('FETCH ALL FROM "cur_edit_lot"')
            row = cur.fetchone()
        conn.commit()
    except Exception as ex:
        _safe_rollback(conn)
        return jsonify({"error": f"No se pudo editar el lote: {ex}"}), 500
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    if not row or not row.get("success"):
        return jsonify({"error": "Lote no encontrado"}), 404

    return jsonify({"message": "Lote actualizado"})


# =============================================================================
# RUTAS — aplicaciones (vaccination records)
# =============================================================================

@app.route("/aplicaciones")
def aplicaciones():
    locked = _require_role("Administrador", "Medico", "Enfermero")
    if locked:
        return locked

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("CALL sp_get_vaccination_records_full(%s)", ("cur_vaccination_records",))
            cur.execute('FETCH ALL FROM "cur_vaccination_records"')
            raw_records = cur.fetchall()
        conn.commit()
    except Exception as e:
        _safe_rollback(conn)
        logger.error(f"Error en /aplicaciones: {e}")
        raw_records = []
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    records = [
        {
            "id":               r.get("record_id"),
            "record_id":        r.get("record_id"),
            "patient_id":       r.get("patient_id"),
            "vaccine_id":       r.get("vaccine_id"),
            "name":             r.get("vaccine_name"),
            "vaccine_name":     r.get("vaccine_name"),
            "patient_name":     r.get("patient_name"),
            "doctor":           r.get("worker_name"),
            "dose":             r.get("dose_label") or "—",
            "date":             _temporal_text(r.get("applied_date")),
            "next_date":        None,
            "application_site": r.get("application_site") or "—",
            "had_reaction":     r.get("had_reaction", False),
            "patient_temp_c":   r.get("patient_temp_c"),
            "notes":            r.get("notes") or "Sin reacciones",
        }
        for r in raw_records
    ]

    records_raw = _cur_fetchall("vaccination_records")
    unique_patients    = len(set(r["patient_id"] for r in records_raw))
    unique_vaccines    = len(set(r["vaccine_id"]  for r in records_raw))
    today_str          = date.today().isoformat()
    applications_today = sum(
        1 for r in records_raw
        if str(r.get("applied_date") or "")[:10] == today_str
    )

    return render_template(
        "pages/aplicaciones_2daE.html",
        **_session_vars(),
        total_applications=len(records),
        total_patients_attended=unique_patients,
        total_unique_vaccines=unique_vaccines,
        applications_today=applications_today,
        applications=records,
    )


@app.route("/agregar_aplicacion", methods=["GET", "POST"])
def agregar_aplicacion():
    # [REFACTORED] Reemplaza sp_register_vaccination_record por sp_apply_vaccine.
    #   - sp_apply_vaccine incluye validaciones clínicas (edad, intervalo, lote).
    #   - No acepta applied_date (usa CURRENT_DATE internamente).
    #   - Acepta appointment_id opcional para cerrar la cita automáticamente
    #     (via Trigger 15).
    #   - Stock se descuenta via Trigger 4 (no en el SP).
    #   - schedule se marca Aplicada via Trigger 12 (no en el SP).
    locked = _require_role("Administrador", "Medico", "Enfermero")
    if locked:
        return locked

    form  = {}
    error = None

    if request.method == "POST":
        form = dict(request.form)
        try:
            patient_id     = int(request.form.get("patient_id", "0"))
            vaccine_id     = int(request.form.get("vaccine_id", "0"))
            worker_id      = int(request.form.get("worker_id",  "0"))
            scheme_dose_id = request.form.get("scheme_dose_id")
            scheme_dose_id = int(scheme_dose_id) if scheme_dose_id else None
            app_site_id    = request.form.get("application_site_id")
            app_site_id    = int(app_site_id) if app_site_id else None
            appointment_id = request.form.get("appointment_id")
            appointment_id = int(appointment_id) if appointment_id else None
        except ValueError:
            error = "IDs inválidos"
        else:
            patient = _cur_fetchone("patients", "patient_id", patient_id)
            vaccine = _cur_fetchone("vaccines",  "vaccine_id", vaccine_id)
            if not patient or not vaccine:
                error = "Paciente o vacuna no encontrados"
            else:
                clinic_id = int(request.form.get("clinic_id") or session.get("clinic_id") or 1)
                lot_id    = request.form.get("lot_id")
                lot_id    = int(lot_id) if lot_id else None

                conn, should_close = _get_conn()
                _safe_rollback(conn)
                try:
                    with conn.cursor() as cur:
                        cur.execute(
                            "CALL sp_apply_vaccine(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
                            (
                                patient_id,
                                vaccine_id,
                                worker_id or session.get("worker_id", 1),
                                clinic_id,
                                lot_id,
                                scheme_dose_id,
                                appointment_id,
                                app_site_id,
                                request.form.get("patient_temp_c") or None,
                                request.form.get("had_reaction") == "true",
                                "cur_apply_vaccine",
                            ),
                        )
                        cur.execute('FETCH ALL FROM "cur_apply_vaccine"')
                        row = cur.fetchone()
                    conn.commit()

                except psycopg.DatabaseError as ex:
                    _safe_rollback(conn)
                    db_error = str(ex).strip()
                    if "duplicate key value" in db_error:
                        error = "Esta dosis ya fue registrada para el paciente."
                    elif "foreign key constraint" in db_error:
                        error = "Referencia inválida (lote, clínica o paciente)."
                    elif "no tiene stock" in db_error.lower():
                        error = "El lote seleccionado no tiene stock disponible."
                    elif "vacuna vencida" in db_error.lower():
                        error = "No se puede aplicar: el lote está vencido."
                    else:
                        error = db_error
                    row = None
                finally:
                    if should_close and not _conn_is_closed(conn):
                        conn.close()

                if row and not row.get("success"):
                    error = row.get("message", "Error al registrar la aplicación")
                elif row:
                    p_name = f"{patient['first_name']} {patient['last_name']}".strip()
                    flash(f"Aplicación de {vaccine['name']} registrada para {p_name}.", "success")
                    next_url = request.form.get("next") or url_for("aplicaciones")
                    return redirect(next_url)
                elif not error:
                    error = "No se pudo registrar la aplicación en base de datos"

    return render_template(
        "agregarAplicacion_2daE.html",
        **_session_vars(),
        patients=_cur_fetchall("patients"),
        vaccines=_cur_fetchall("vaccines"),
        workers=_cur_fetchall("workers"),
        clinics=_cur_fetchall("clinics"),
        lots=_cur_fetchall("vaccine_lots"),
        scheme_doses=_cur_fetchall("scheme_doses"),
        application_sites=_cur_fetchall("application_sites"),
        form=form,
        error=error,
    )


# =============================================================================
# RUTAS — personal
# =============================================================================

@app.route("/personal")
def personal():
    locked = _require_role("Administrador")
    if locked:
        return locked

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("CALL sp_get_workers_full(%s)", ("cur_workers_full",))
            cur.execute('FETCH ALL FROM "cur_workers_full"')
            workers = [dict(r) for r in cur.fetchall()]
        conn.commit()
    except Exception as e:
        _safe_rollback(conn)
        logger.error(f"Error en /personal: {e}")
        workers = []
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    return render_template(
        "pages/personal_2daE.html",
        **_session_vars(),
        workers=workers,
        total_workers=len(workers),
        roles=_cur_fetchall("roles"),
    )


@app.route("/personal/agregar", methods=["GET", "POST"])
def add_user():
    locked = _require_role("Administrador")
    if locked:
        return locked

    form  = {}
    error = None

    if request.method == "POST":
        form       = dict(request.form)
        password   = request.form.get("password") or ""
        confirm    = request.form.get("password_confirm") or ""
        mail       = (request.form.get("mail") or "").strip()
        first_name = (request.form.get("first_name") or request.form.get("name") or "").strip()
        last_name  = (request.form.get("last_name")  or request.form.get("lastname") or "").strip()
        role_raw   = request.form.get("role_id") or request.form.get("role")

        role_id = 3
        if role_raw:
            try:
                role_id = int(role_raw)
            except ValueError:
                match   = next((r for r in _cur_fetchall("roles") if r["name"].lower() == role_raw.lower()), None)
                role_id = match["role_id"] if match else 3

        email_exists = any(
            (e.get("email") or "").lower() == mail.lower()
            for e in _cur_fetchall("worker_emails")
        )

        if password != confirm:
            error = "Las contraseñas no coinciden"
            flash(error, "danger")
        elif not first_name or not last_name:
            error = "Nombre y apellidos son obligatorios"
            flash(error, "danger")
        elif email_exists:
            error = "El email ya existe en el sistema"
            flash(error, "danger")
        else:
            conn, should_close = _get_conn()
            _safe_rollback(conn)
            try:
                with conn.cursor() as cur:
                    cur.execute(
                        "CALL sp_register_worker(%s,%s,%s,%s,%s,%s,%s,%s)",
                        (
                            role_id,
                            first_name,
                            last_name,
                            date.today().isoformat(),
                            f"hash:{password}",
                            mail,
                            (request.form.get("phone") or "").strip() or None,
                            "cur_reg_worker",
                        ),
                    )
                    cur.execute('FETCH ALL FROM "cur_reg_worker"')
                    row = cur.fetchone()
                conn.commit()
            except Exception as ex:
                _safe_rollback(conn)
                error = f"No se pudo registrar el usuario: {ex}"
                row   = None
            finally:
                if should_close and not _conn_is_closed(conn):
                    conn.close()

            if row and not row.get("success"):
                error = row.get("message", "Error al registrar el usuario")
                flash(error, "danger")
            elif row:
                session["last_registered_worker"] = row.get("worker_id")
                flash(f"Usuario {first_name} registrado correctamente.", "success")
                return redirect(url_for("personal"))
            elif not error:
                error = "No se pudo registrar el usuario"
                flash(error, "danger")

    return render_template(
        "add_user_2daE.html",
        **_session_vars(),
        form=form,
        error=error,
        roles=_cur_fetchall("roles"),
    )


@app.route("/personal/editar/<int:worker_id>", methods=["GET", "POST"])
def edit_user(worker_id):
    locked = _require_role("Administrador")
    if locked:
        return locked

    worker = _cur_fetchone("workers", "worker_id", worker_id)
    if not worker:
        flash("Usuario no encontrado", "danger")
        return redirect(url_for("personal"))

    roles         = _cur_fetchall("roles") or []
    emails        = _cur_fetchall_where("worker_emails", "worker_id", worker_id)
    primary_email = next((e for e in emails if e.get("is_primary")), emails[0] if emails else None)
    role_row      = _cur_fetchone("roles", "role_id", worker.get("role_id"))

    if request.method == "POST":
        first_name  = (request.form.get("first_name") or request.form.get("name") or "").strip()
        last_name   = (request.form.get("last_name")  or request.form.get("lastname") or "").strip()
        mail        = (request.form.get("mail") or "").strip()
        role_id_raw = request.form.get("role_id") or request.form.get("role")

        if not first_name or not last_name:
            flash("Nombre y apellidos son obligatorios", "danger")
        else:
            try:
                role_id = int(role_id_raw) if role_id_raw is not None else worker.get("role_id")
            except ValueError:
                match   = next((r for r in roles if r["name"].lower() == (role_id_raw or "").lower()), None)
                role_id = match["role_id"] if match else None

            if role_id is None:
                flash("Selecciona un rol válido", "danger")
            else:
                conn, should_close = _get_conn()
                try:
                    with conn.cursor() as cur:
                        cur.execute(
                            "SELECT * FROM sp_update_worker(%s,%s,%s,%s,%s)",
                            (worker_id, first_name, last_name, role_id, mail or None),
                        )
                        result = cur.fetchone()
                    conn.commit()
                except Exception as ex:
                    _safe_rollback(conn)
                    result = None
                    flash(f"Error al actualizar: {ex}", "danger")
                finally:
                    if should_close and not _conn_is_closed(conn):
                        conn.close()

                if result is not None:
                    flash("Usuario actualizado correctamente", "success")
                    return redirect(url_for("personal"))
                else:
                    flash("No se pudo actualizar el usuario", "danger")

    worker_view = {
        "worker_id": worker["worker_id"],
        "name":      worker["first_name"],
        "lastname":  worker["last_name"],
        "role":      role_row["name"] if role_row else "",
        "role_id":   worker.get("role_id"),
        "mail":      primary_email["email"] if primary_email else "",
    }

    return render_template(
        "edit_user_2daE.html",
        worker=worker_view,
        roles=roles,
        **_session_vars(),
    )


# =============================================================================
# RUTAS — otras secciones
# =============================================================================

@app.route("/reportes-publicos")
def reportes_publicos():
    locked = _require_role("Administrador", "Medico")
    if locked:
        return locked
    return render_template("pages/reportesPublicos_2daE.html", **_session_vars())


@app.route("/inventario")
def inventario():
    locked = _require_role("Administrador", "Almacen")
    if locked:
        return locked

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("CALL sp_get_inventory_status(%s)", ("cur_inventory_status",))
            cur.execute('FETCH ALL FROM "cur_inventory_status"')
            inventory = [dict(r) for r in cur.fetchall()]
        conn.commit()
    except Exception as e:
        _safe_rollback(conn)
        logger.error(f"Error en /inventario: {e}")
        inventory = []
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    if any(i.get("low_stock") for i in inventory):
        flash("⚠ Hay insumos con stock por debajo del mínimo.", "warning")

    session["last_section"] = "inventario"
    return render_template(
        "pages/inventario_2daE.html",
        **_session_vars(),
        inventory=inventory,
        supply_catalog=_cur_fetchall("supply_catalog"),
        clinics=_cur_fetchall("clinics"),
    )


@app.route("/citas")
def citas():
    # Usa sp_get_citas_admin: rango de fechas, todas las columnas de v_appointments_full
    # + tutor principal. Sin SQL embebido.
    locked = _require_role("Administrador", "Recepcionista", "Medico", "Enfermero")
    if locked:
        return locked

    clinic_id = session.get("clinic_id")
    # Si la sesión no tiene clinic_id (login anterior al fix), intentar resolverlo
    if clinic_id is None:
        worker_id = session.get("worker_id")
        if worker_id:
            try:
                _conn_tmp = get_db_connection()
                with _conn_tmp.cursor() as _cur:
                    _cur.execute(
                        "SELECT clinic_id FROM worker_schedules WHERE worker_id=%s ORDER BY clinic_id LIMIT 1",
                        (worker_id,)
                    )
                    _row = _cur.fetchone()
                    if _row:
                        clinic_id = _row["clinic_id"]
                        session["clinic_id"] = clinic_id
                _conn_tmp.close()
            except Exception:
                pass  # clinic_id queda en None; el SP devuelve todas las clínicas

    date_from = date.today()
    date_to   = date.today() + timedelta(days=30)
    rows      = []

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("CALL sp_get_citas_admin(%s, %s, %s, %s)",
                        (clinic_id,
                         date_from.isoformat(),
                         date_to.isoformat(),
                         "cur_citas_admin"))
            cur.execute('FETCH ALL FROM "cur_citas_admin"')
            rows = [dict(r) for r in cur.fetchall()]
        conn.commit()
    except Exception as e:
        _safe_rollback(conn)
        logger.error("Error en /citas: %s", e)
        flash("Error al cargar las citas.", "danger")
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    ACTIVE_STATES  = {"Programada", "Confirmada"}
    HISTORY_STATES = {"Completada", "Cancelada", "No Show"}

    def _fmt(r):
        return {**r,
                "scheduled_at":  _temporal_text(r.get("scheduled_at")),
                "dose_due_date": _temporal_text(r.get("dose_due_date"))}

    all_fmt        = [_fmt(r) for r in rows]
    upcoming_citas = [r for r in all_fmt if r.get("appointment_status") in ACTIVE_STATES]
    history_citas  = [r for r in all_fmt if r.get("appointment_status") in HISTORY_STATES]

    session["last_section"] = "citas"
    return render_template(
        "pages/citas_2daE.html",
        **_session_vars(),
        upcoming_citas=upcoming_citas,
        history_citas=history_citas,
        date_from=date_from.strftime("%d/%m/%Y"),
        date_to=date_to.strftime("%d/%m/%Y"),
    )


@app.route("/citas/nueva", methods=["GET", "POST"])
def admin_nueva_cita():
    """Agendar una cita manualmente desde el portal admin."""
    locked = _require_role("Administrador", "Recepcionista", "Medico", "Enfermero")
    if locked:
        return locked

    clinic_id = session.get("clinic_id")

    if request.method == "GET":
        conn, should_close = _get_conn()
        _safe_rollback(conn)
        patients, workers, areas = [], [], []
        try:
            with conn.cursor() as cur:
                cur.execute(
                    "CALL sp_get_agenda_form_data(%s, %s, %s, %s)",
                    (clinic_id, "cur_pat", "cur_wrk", "cur_area"),
                )
                cur.execute('FETCH ALL FROM "cur_pat"')
                patients = [dict(r) for r in cur.fetchall()]
                cur.execute('FETCH ALL FROM "cur_wrk"')
                workers  = [dict(r) for r in cur.fetchall()]
                cur.execute('FETCH ALL FROM "cur_area"')
                areas    = [dict(r) for r in cur.fetchall()]
            conn.commit()
        except Exception as e:
            _safe_rollback(conn)
            logger.error("Error cargando form nueva cita: %s", e)
            flash("Error al cargar el formulario.", "danger")
        finally:
            if should_close and not _conn_is_closed(conn):
                conn.close()

        return render_template(
            "pages/nueva_cita.html",
            **_session_vars(),
            patients=patients,
            workers=workers,
            areas=areas,
            today_iso=date.today().isoformat(),
        )

    # POST — crear cita
    patient_id          = request.form.get("patient_id",          type=int)
    worker_id           = request.form.get("worker_id",           type=int)  or None
    area_id             = request.form.get("area_id",             type=int)  or None
    scheduled_at_str    = request.form.get("scheduled_at",        "").strip()
    reason              = request.form.get("reason",              "").strip() or None
    patient_schedule_id = request.form.get("patient_schedule_id", type=int)  or None

    if not patient_id or not scheduled_at_str:
        flash("Paciente y fecha/hora son obligatorios.", "warning")
        return redirect(url_for("admin_nueva_cita"))

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute(
                "CALL sp_create_appointment(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
                (patient_id, clinic_id, area_id, worker_id,
                 scheduled_at_str, reason, patient_schedule_id,
                 session.get("role"), session.get("worker_id"), None,
                 "cur_nueva_cita"),
            )
            cur.execute('FETCH ALL FROM "cur_nueva_cita"')
            result = dict(cur.fetchone() or {})
        conn.commit()
        if result.get("success"):
            flash("Cita creada correctamente.", "success")
        else:
            flash(f"No se pudo crear la cita: {result.get('message')}", "danger")
    except Exception as e:
        _safe_rollback(conn)
        logger.error("Error en admin_nueva_cita POST: %s", e)
        flash(f"Error al agendar la cita: {e}", "danger")
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    return redirect(url_for("citas"))


@app.route("/citas/<int:appointment_id>/cancelar", methods=["POST"])
def admin_cancelar_cita(appointment_id):
    """Cancela una cita desde el portal admin."""
    locked = _require_role("Administrador", "Recepcionista", "Medico", "Enfermero")
    if locked:
        return locked

    cancel_reason = request.form.get("cancel_reason", "Cancelada por staff").strip()

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("CALL sp_cancel_appointment(%s, %s, %s)",
                        (appointment_id, cancel_reason, "cur_cancel"))
            cur.execute('FETCH ALL FROM "cur_cancel"')
            result = dict(cur.fetchone() or {})
        conn.commit()
        if result.get("success"):
            flash("Cita cancelada correctamente.", "info")
        else:
            flash(f"No se pudo cancelar: {result.get('message')}", "danger")
    except Exception as e:
        _safe_rollback(conn)
        logger.error("Error en admin_cancelar_cita: %s", e)
        flash(f"Error al cancelar la cita: {e}", "danger")
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    next_url = request.form.get("next") or url_for("citas")
    return redirect(next_url)


@app.route("/citas/<int:appointment_id>/no-show", methods=["POST"])
def admin_no_show(appointment_id):
    """Marca una cita como No Show."""
    locked = _require_role("Administrador", "Medico", "Enfermero")
    if locked:
        return locked

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("CALL sp_mark_no_show(%s, %s)",
                        (appointment_id, "cur_ns"))
            cur.execute('FETCH ALL FROM "cur_ns"')
        conn.commit()
        flash("Cita marcada como No Show.", "warning")
    except Exception as e:
        _safe_rollback(conn)
        logger.error("Error en admin_no_show: %s", e)
        flash(f"Error al marcar No Show: {e}", "danger")
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    next_url = request.form.get("next") or url_for("citas")
    return redirect(next_url)


@app.route("/citas/<int:appointment_id>/reagendar", methods=["POST"])
def admin_reagendar_cita(appointment_id):
    """Reagenda una cita a una nueva fecha."""
    locked = _require_role("Administrador", "Recepcionista", "Medico", "Enfermero")
    if locked:
        return locked

    new_scheduled_at = request.form.get("new_scheduled_at", "").strip()
    reschedule_reason = request.form.get("reschedule_reason", "").strip() or None

    if not new_scheduled_at:
        flash("La nueva fecha es obligatoria.", "warning")
        return redirect(url_for("citas"))

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("CALL sp_reschedule_appointment(%s, %s, %s, %s)",
                        (appointment_id, new_scheduled_at, reschedule_reason,
                         "cur_reagendar"))
            cur.execute('FETCH ALL FROM "cur_reagendar"')
            result = dict(cur.fetchone() or {})
        conn.commit()
        if result.get("success"):
            flash("Cita reagendada correctamente.", "success")
        else:
            flash(f"No se pudo reagendar: {result.get('message')}", "danger")
    except Exception as e:
        _safe_rollback(conn)
        logger.error("Error en admin_reagendar_cita: %s", e)
        flash(f"Error al reagendar: {e}", "danger")
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    return redirect(url_for("citas"))


@app.route("/citas/<int:appointment_id>/editar", methods=["GET", "POST"])
def admin_editar_cita(appointment_id):
    """Edición completa de una cita existente (admin)."""
    locked = _require_role("Administrador", "Recepcionista", "Medico", "Enfermero")
    if locked:
        return locked

    clinic_id = session.get("clinic_id")

    if request.method == "GET":
        cita      = {}
        workers   = []
        areas     = []
        conn, should_close = _get_conn()
        _safe_rollback(conn)
        try:
            with conn.cursor() as cur:
                # Datos actuales de la cita
                cur.execute("CALL sp_get_appointment_detail(%s, %s)",
                            (appointment_id, "cur_appt_detail"))
                cur.execute('FETCH ALL FROM "cur_appt_detail"')
                row = cur.fetchone()
                cita = dict(row) if row else {}

                # Workers y areas del form (reutiliza sp_get_agenda_form_data)
                cur.execute("CALL sp_get_agenda_form_data(%s, %s, %s, %s)",
                            (clinic_id, "cur_pat2", "cur_wrk2", "cur_area2"))
                cur.execute('FETCH ALL FROM "cur_pat2"')
                cur.fetchall()  # descartar pacientes (no se edita)
                cur.execute('FETCH ALL FROM "cur_wrk2"')
                workers = [dict(r) for r in cur.fetchall()]
                cur.execute('FETCH ALL FROM "cur_area2"')
                areas   = [dict(r) for r in cur.fetchall()]
            conn.commit()
        except Exception as e:
            _safe_rollback(conn)
            logger.error("Error cargando editar cita %s: %s", appointment_id, e)
            flash("Error al cargar la cita.", "danger")
            return redirect(url_for("citas"))
        finally:
            if should_close and not _conn_is_closed(conn):
                conn.close()

        if not cita:
            flash("Cita no encontrada.", "warning")
            return redirect(url_for("citas"))

        # Formatear scheduled_at para datetime-local input (YYYY-MM-DDTHH:MM)
        sched = cita.get("scheduled_at")
        if sched:
            if hasattr(sched, "strftime"):
                cita["scheduled_at_local"] = sched.strftime("%Y-%m-%dT%H:%M")
            else:
                sched_str = str(sched)
                cita["scheduled_at_local"] = sched_str[:16].replace(" ", "T")
        else:
            cita["scheduled_at_local"] = ""

        return render_template(
            "pages/editar_cita.html",
            **_session_vars(),
            cita=cita,
            workers=workers,
            areas=areas,
            statuses=["Programada", "Confirmada", "Completada", "Cancelada", "No Show"],
            today_iso=date.today().isoformat(),
        )

    # ── POST — guardar cambios ────────────────────────────────────
    worker_id    = request.form.get("worker_id",    type=int) or None
    area_id      = request.form.get("area_id",      type=int) or None
    scheduled_at = request.form.get("scheduled_at", "").strip() or None
    reason       = request.form.get("reason",       "").strip() or None
    notes        = request.form.get("notes",        "").strip() or None
    status       = request.form.get("status",       "").strip() or None
    duration_min = request.form.get("duration_min", type=int)  or None

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute(
                "CALL sp_update_appointment(%s,%s,%s,%s,%s,%s,%s,%s,%s)",
                (appointment_id, worker_id, area_id, scheduled_at,
                 reason, notes, status, duration_min, "cur_edit_appt"),
            )
            cur.execute('FETCH ALL FROM "cur_edit_appt"')
            result = dict(cur.fetchone() or {})
        conn.commit()
        if result.get("success"):
            flash("Cita actualizada correctamente.", "success")
        else:
            flash(f"No se pudo actualizar: {result.get('message')}", "danger")
    except Exception as e:
        _safe_rollback(conn)
        logger.error("Error en admin_editar_cita POST %s: %s", appointment_id, e)
        flash(f"Error al guardar: {e}", "danger")
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    return redirect(url_for("citas"))


@app.route("/assign_nfc_card", methods=["POST"])
def assign_nfc_card():
    if not _check_role("Administrador", "Recepcionista", "Enfermero"):
        return jsonify({"error": "Sin permisos"}), 403

    body       = request.get_json(force=True) or {}
    patient_id = body.get("patient_id")
    uid        = (body.get("uid") or "").strip()
    card_type  = (body.get("card_type") or "").strip()
    notes      = (body.get("notes") or "").strip()
    worker_id  = session.get("worker_id")

    if not patient_id or not uid:
        return jsonify({"error": "patient_id y uid son obligatorios"}), 400

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute(
                "CALL sp_assign_nfc_card(%s, %s, %s, %s, %s, %s)",
                (patient_id, uid, card_type or None, worker_id, notes or None, "cur_assign_nfc"),
            )
            cur.execute('FETCH ALL FROM "cur_assign_nfc"')
            row = dict(cur.fetchone())
        conn.commit()
        if row.get("success"):
            return jsonify({"message": row["message"], "nfc_card_id": row["nfc_card_id"]}), 200
        return jsonify({"error": row.get("message", "Error al asignar NFC")}), 400
    except Exception as e:
        _safe_rollback(conn)
        logger.error(f"Error en /assign_nfc_card: {e}")
        return jsonify({"error": str(e)}), 500
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()


@app.route("/nfc")
def nfc():
    locked = _require_role("Administrador")
    if locked:
        return locked

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("CALL sp_get_nfc_cards_full(%s)", ("cur_nfc_cards",))
            cur.execute('FETCH ALL FROM "cur_nfc_cards"')
            cards = [dict(r) for r in cur.fetchall()]

            cur.execute("CALL sp_get_nfc_scans_full(%s)", ("cur_nfc_scans",))
            cur.execute('FETCH ALL FROM "cur_nfc_scans"')
            scans = [dict(r) for r in cur.fetchall()]
        conn.commit()
    except Exception as e:
        _safe_rollback(conn)
        logger.error(f"Error en /nfc: {e}")
        cards = []
        scans = []
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    session["last_section"] = "nfc"
    return render_template(
        "pages/nfc_2daE.html",
        **_session_vars(),
        cards=cards,
        scans=scans,
        total_cards=len(cards),
        active_cards=sum(1 for c in cards if c.get("status") == "Activa"),
    )

@app.route("/clinicas")
def clinicas():
    locked = _require_role("Administrador")
    if locked:
        return locked

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("CALL sp_get_clinics_full(%s)", ("cur_clinics_full",))
            cur.execute('FETCH ALL FROM "cur_clinics_full"')
            clinics = [dict(r) for r in cur.fetchall()]
        conn.commit()
    except Exception as e:
        _safe_rollback(conn)
        logger.error(f"Error en /clinicas: {e}")
        clinics = []
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    session["last_section"] = "clinicas"
    return render_template(
        "pages/clinicas_2daE.html",
        **_session_vars(),
        clinics=clinics,
        total_clinics=len(clinics),
    )


# =============================================================================
# RUTAS — recepcionista
# =============================================================================

@app.route("/recepcionista/dashboard")
def recepcionista_dashboard():
    locked = _require_role("Recepcionista", "Administrador")
    if locked:
        return locked

    kpis        = {}
    citas_hoy   = []
    actividad   = []
    chart_data  = []

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("CALL sp_recepcionista_kpis(%s)", ("cur_rec_kpis",))
            cur.execute('FETCH ALL FROM "cur_rec_kpis"')
            row = cur.fetchone()
            kpis = dict(row) if row else {}

            cur.execute("CALL sp_recepcionista_citas_hoy(%s)", ("cur_rec_citas",))
            cur.execute('FETCH ALL FROM "cur_rec_citas"')
            citas_hoy = [
                {**dict(r), "scheduled_at": _temporal_text(r.get("scheduled_at")),
                 "hora_fin": _temporal_text(r.get("hora_fin"))}
                for r in cur.fetchall()
            ]

            cur.execute("CALL sp_recepcionista_actividad_reciente(%s, %s)", (15, "cur_rec_actividad"))
            cur.execute('FETCH ALL FROM "cur_rec_actividad"')
            actividad = [
                {**dict(r), "ts": _temporal_text(r.get("ts"))}
                for r in cur.fetchall()
            ]

            cur.execute("CALL sp_recepcionista_pacientes_semana(%s)", ("cur_rec_semana",))
            cur.execute('FETCH ALL FROM "cur_rec_semana"')
            chart_data = [
                {"dia": str(r.get("dia")), "dia_label": r.get("dia_label"), "total": r.get("total", 0)}
                for r in cur.fetchall()
            ]

        conn.commit()
    except Exception:
        import traceback
        logger.error(f"[SP ERROR] recepcionista_dashboard:\n{traceback.format_exc()}")
        _safe_rollback(conn)
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    citas_con_alerta = sum(1 for c in citas_hoy if c.get("alerta_tardia"))

    return render_template(
        "pages/recepcionista/dashboard_recepcionista.html",
        **_session_vars(),
        today=date.today().strftime("%d/%m/%Y"),
        # KPIs citas
        citas_hoy_total      =kpis.get("citas_hoy_total",       0),
        citas_hoy_completadas=kpis.get("citas_hoy_completadas", 0),
        citas_hoy_pendientes =kpis.get("citas_hoy_pendientes",  0),
        citas_hoy_canceladas =kpis.get("citas_hoy_canceladas",  0),
        citas_hoy_no_show    =kpis.get("citas_hoy_no_show",     0),
        # KPIs pacientes
        pacientes_hoy   =kpis.get("pacientes_hoy",    0),
        pacientes_semana=kpis.get("pacientes_semana",  0),
        # Widgets
        citas_hoy       =citas_hoy,
        citas_con_alerta=citas_con_alerta,
        actividad       =actividad,
        # Gráfica
        chart_data=chart_data,
    )


# =============================================================================
# RUTAS — medico
# =============================================================================

@app.route("/medico")
@app.route("/medico/dashboard")
def medico_dashboard():
    locked = _require_role("Medico", "Administrador")
    if locked:
        return locked

    worker_id = session.get("worker_id")
    clinic_id = session.get("clinic_id")
    today_iso = date.today().isoformat()

    citas_hoy        = []
    alertas          = []
    vacunas_hoy      = 0
    pacientes_semana = 0
    chart_data       = []

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            # Q1: Citas del día filtradas por médico
            cur.execute("CALL sp_get_citas_admin(%s, %s, %s, %s)",
                        (clinic_id, today_iso, today_iso, "cur_md_citas"))
            cur.execute('FETCH ALL FROM "cur_md_citas"')
            all_citas = [dict(r) for r in cur.fetchall()]
            citas_hoy = [r for r in all_citas if r.get("worker_id") == worker_id]

            # Q2: Alertas pendientes (Atraso + Critico)
            cur.execute("CALL sp_get_schema_alerts_full(%s)", ("cur_md_alertas",))
            cur.execute('FETCH ALL FROM "cur_md_alertas"')
            all_alertas = [dict(r) for r in cur.fetchall()]
            alertas = [a for a in all_alertas
                       if a.get("alert_status") == "Pendiente"
                       and a.get("alert_type") in ("Atraso", "Critico")]

            # Q3: Vacunas aplicadas hoy por este médico
            cur.execute(
                "SELECT COUNT(*) AS cnt FROM vaccination_records "
                "WHERE worker_id=%s AND applied_date=CURRENT_DATE",
                (worker_id,)
            )
            vacunas_hoy = (cur.fetchone() or {}).get("cnt", 0)

            # Q4: Pacientes atendidos esta semana
            cur.execute(
                "SELECT COUNT(DISTINCT patient_id) AS cnt FROM vaccination_records "
                "WHERE worker_id=%s AND applied_date >= DATE_TRUNC('week', CURRENT_DATE)",
                (worker_id,)
            )
            pacientes_semana = (cur.fetchone() or {}).get("cnt", 0)

            # Q5: Citas por día esta semana (gráfica)
            cur.execute(
                "SELECT DATE(scheduled_at) AS dia, "
                "TO_CHAR(DATE(scheduled_at), 'Dy') AS dia_label, "
                "COUNT(*) AS total "
                "FROM appointments "
                "WHERE worker_id=%s "
                "  AND scheduled_at >= DATE_TRUNC('week', CURRENT_DATE) "
                "  AND scheduled_at < DATE_TRUNC('week', CURRENT_DATE) + INTERVAL '7 days' "
                "GROUP BY dia ORDER BY dia",
                (worker_id,)
            )
            chart_data = [dict(r) for r in cur.fetchall()]
        conn.commit()
    except Exception as e:
        _safe_rollback(conn)
        logger.error("Error en medico_dashboard: %s", e)
        flash("Error al cargar el dashboard.", "danger")
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    citas_pendientes  = [c for c in citas_hoy
                         if c.get("appointment_status") in ("Programada", "Confirmada")]
    citas_completadas = [c for c in citas_hoy
                         if c.get("appointment_status") == "Completada"]

    return render_template(
        "pages/medico/dashboard_medico.html",
        **_session_vars(),
        today=date.today().strftime("%d/%m/%Y"),
        citas_hoy=citas_pendientes,
        citas_hoy_total=len(citas_hoy),
        citas_hoy_pendientes=len(citas_pendientes),
        citas_hoy_completadas=len(citas_completadas),
        vacunas_hoy=vacunas_hoy,
        pacientes_semana=pacientes_semana,
        alertas_pendientes=len(alertas),
        alertas=alertas,
        chart_data=chart_data,
    )


@app.route("/medico/citas")
def medico_citas_hoy():
    locked = _require_role("Medico", "Administrador")
    if locked:
        return locked

    worker_id = session.get("worker_id")
    clinic_id = session.get("clinic_id")
    today     = date.today()

    rows = []
    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("CALL sp_get_citas_admin(%s, %s, %s, %s)",
                        (clinic_id, today.isoformat(), today.isoformat(), "cur_mc_citas"))
            cur.execute('FETCH ALL FROM "cur_mc_citas"')
            rows = [dict(r) for r in cur.fetchall()]
        conn.commit()
    except Exception as e:
        _safe_rollback(conn)
        logger.error("Error en medico_citas_hoy: %s", e)
        flash("Error al cargar las citas.", "danger")
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    mis_citas = [r for r in rows if r.get("worker_id") == worker_id]
    ACTIVE    = {"Programada", "Confirmada"}
    HISTORY   = {"Completada", "Cancelada", "No Show"}
    upcoming  = [r for r in mis_citas if r.get("appointment_status") in ACTIVE]
    history   = [r for r in mis_citas if r.get("appointment_status") in HISTORY]

    return render_template(
        "pages/medico/citas_medico.html",
        **_session_vars(),
        upcoming=upcoming,
        history=history,
        today_label=today.strftime("%d/%m/%Y"),
    )


# =============================================================================
# APIs JSON
# =============================================================================

@app.route("/api/global-search")
def api_global_search():
    locked = _require_login()
    if locked:
        return jsonify({"results": []})

    q = (request.args.get("q") or "").strip().lower()
    if not q:
        return jsonify({"results": []})

    results = []

    is_numeric = q.isdigit()

    # Buscar pacientes — prioriza nfc_id si la query es solo números
    patient_results = []
    for p in _cur_fetchall("patients"):
        full    = f"{p['first_name']} {p['last_name']}".strip()
        nfc_id  = str(p.get("nfc_id") or "")
        matched = (
            q in full.lower()
            or q in str(p["patient_id"])
            or (nfc_id and q in nfc_id)
        )
        if matched:
            priority = 0 if (is_numeric and nfc_id == q) else 1
            patient_results.append((priority, {
                "type":     "paciente",
                "title":    full,
                "subtitle": f"ID: P{p['patient_id']}" + (f" · NFC: {nfc_id}" if nfc_id else ""),
                "url":      url_for("esquema_paciente", id=p["patient_id"]),
            }))

    patient_results.sort(key=lambda x: x[0])
    results.extend(r for _, r in patient_results)

    # Buscar vacunas
    for v in _cur_fetchall("vaccines"):
        if q in v["name"].lower() or q in str(v["vaccine_id"]):
            lot_stock = sum(
                l["quantity_available"]
                for l in _cur_fetchall_where("vaccine_lots", "vaccine_id", v["vaccine_id"])
            )
            results.append({
                "type":     "vacuna",
                "title":    v["name"],
                "subtitle": f"Stock: {lot_stock}",
                "url":      url_for("vacunas_page") + f"?q={v['name']}",
            })

    # Buscar personal vía SP
    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("CALL sp_get_workers_full(%s)", ("cur_workers_search",))
            cur.execute('FETCH ALL FROM "cur_workers_search"')
            workers = cur.fetchall()
        conn.commit()
    except Exception:
        _safe_rollback(conn)
        workers = []
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    for w in workers:
        name  = f"{w.get('first_name', '')} {w.get('last_name', '')}".strip()
        email = w.get("mail", "")
        if q in name.lower() or q in email.lower():
            results.append({
                "type":     "personal",
                "title":    name,
                "subtitle": w.get("role", ""),
                "url":      url_for("personal") + f"?q={name}",
            })

    return jsonify({"results": results[:10]})


@app.route("/api/assign-nfc-id", methods=["POST"])
def api_assign_nfc_id():
    if not _check_role("Administrador", "Recepcionista"):
        return jsonify({"error": "Sin permisos"}), 403

    data = request.get_json(silent=True) or {}
    patient_id = data.get("patient_id")
    nfc_id = str(data.get("nfc_id", "")).strip()

    if not patient_id:
        return jsonify({"error": "patient_id requerido"}), 400
    if not nfc_id or not nfc_id.isdigit():
        return jsonify({"error": "nfc_id debe ser solo números"}), 400

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("CALL sp_update_patient_nfc_id(%s, %s)", (patient_id, nfc_id))
        conn.commit()
    except Exception as e:
        _safe_rollback(conn)
        logger.error(f"Error en /api/assign-nfc-id: {e}")
        return jsonify({"error": str(e)}), 400
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    return jsonify({"message": "OK", "nfc_id": nfc_id}), 200


@app.route("/api/clear-nfc-id", methods=["POST"])
def api_clear_nfc_id():
    if not _check_role("Administrador", "Recepcionista"):
        return jsonify({"error": "Sin permisos"}), 403

    data = request.get_json(silent=True) or {}
    patient_id = data.get("patient_id")

    if not patient_id:
        return jsonify({"error": "patient_id requerido"}), 400

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("CALL sp_clear_patient_nfc_id(%s)", (patient_id,))
        conn.commit()
    except Exception as e:
        _safe_rollback(conn)
        logger.error(f"Error en /api/clear-nfc-id: {e}")
        return jsonify({"error": str(e)}), 400
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    return jsonify({"message": "OK"}), 200


@app.route("/api/reportes-publicos/resumen")
def api_reportes_publicos_resumen():
    if not _check_role("Administrador", "Medico"):
        return jsonify({"error": "Sin permisos"}), 403

    from_date = request.args.get("from")
    to_date   = request.args.get("to")

    # SP dedicado
    conn, should_close = _get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM sp_reportes_resumen(%s, %s)",
                (from_date, to_date),
            )
            sp_row = cur.fetchone()
        conn.commit()
    except Exception:
        _safe_rollback(conn)
        sp_row = None
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    if sp_row:
        import json as _json
        row = dict(sp_row)

        def _parse_col(val):
            if val is None:
                return []
            if isinstance(val, (list, dict)):
                return val
            try:
                return _json.loads(val)
            except Exception:
                return []

        return jsonify({
            "kpis": {
                "total_doses_applied":         row.get("total_doses_applied", 0),
                "target_population":           row.get("target_population", 0),
                "reached_population":          row.get("reached_population", 0),
                "coverage_percent":            float(row.get("coverage_percent") or 0),
                "avg_delay_days":              float(row.get("avg_delay_days") or 0),
                "active_zones":                row.get("active_zones", 0),
                "reaction_rate":               float(row.get("reaction_rate")) if row.get("reaction_rate") is not None else None,
                "completed_scheme":            row.get("completed_scheme"),
                "delayed_patients":            row.get("delayed_patients"),
                "appointment_completion_rate": float(row.get("appointment_completion_rate")) if row.get("appointment_completion_rate") is not None else None,
                "low_stock_count":             row.get("low_stock_count"),
                "new_patients":                row.get("new_patients"),
                "active_workers":              row.get("active_workers"),
                "avg_temp_c":                  float(row.get("avg_temp_c")) if row.get("avg_temp_c") is not None else None,
            },
            "vaccines": _parse_col(row.get("vaccines")),
            "monthly":  _parse_col(row.get("monthly")),
            "zones":    _parse_col(row.get("zones")),
        })

    # Fallback Python
    all_records  = _cur_fetchall("vaccination_records")
    all_patients = _cur_fetchall("patients")

    if from_date and to_date:
        all_records = [
            r for r in all_records
            if from_date <= str(r.get("applied_date") or "")[:10] <= to_date
        ]

    total_doses = len(all_records)
    reached_pop = len(set(r["patient_id"] for r in all_records))
    target_pop  = max(len(all_patients), 1)
    coverage    = round((reached_pop / target_pop) * 100, 1)

    monthly_map = {}
    for r in all_records:
        key = str(r.get("applied_date") or "")[:7]
        if key:
            entry = monthly_map.setdefault(key, {"period_label": key, "doses_applied": 0, "unique_patients": set()})
            entry["doses_applied"] += 1
            entry["unique_patients"].add(r["patient_id"])
    monthly = [
        {**v, "unique_patients": len(v["unique_patients"])}
        for v in sorted(monthly_map.values(), key=lambda x: x["period_label"])
    ]

    vaccine_map = {}
    for r in all_records:
        vid = r.get("vaccine_id")
        if vid:
            v     = _cur_fetchone("vaccines", "vaccine_id", vid)
            vname = v["name"] if v else "—"
            entry = vaccine_map.setdefault(vname, {"vaccine_name": vname, "doses_applied": 0, "unique_patients": set()})
            entry["doses_applied"] += 1
            entry["unique_patients"].add(r["patient_id"])

    vaccines_summary = sorted(
        [
            {
                "vaccine_name":    k,
                "doses_applied":   v["doses_applied"],
                "unique_patients": len(v["unique_patients"]),
                "share_percent":   round(v["doses_applied"] / total_doses * 100, 1) if total_doses else 0,
            }
            for k, v in vaccine_map.items()
        ],
        key=lambda x: x["doses_applied"],
        reverse=True,
    )[:50]

    zones_summary = [
        {
            "zone_name":       z.get("name"),
            "doses_applied":   z.get("cases"),
            "unique_patients": z.get("cases"),
            "risk_level":      z.get("risk"),
            "risk_label":      {"high": "Alto", "medium": "Medio", "low": "Bajo"}.get(z.get("risk"), "—"),
        }
        for z in _cur_fetchall("zones")
    ]

    return jsonify({
        "kpis": {
            "total_doses_applied": total_doses,
            "target_population":   target_pop,
            "reached_population":  reached_pop,
            "coverage_percent":    coverage,
            "avg_delay_days":      0.0,
            "active_zones":        len(zones_summary),
        },
        "monthly":  monthly,
        "vaccines": vaccines_summary,
        "zones":    zones_summary,
    })


@app.route("/api/alertas-esquema")
def api_alertas_esquema():
    if not _check_role("Administrador", "Medico", "Enfermero"):
        return jsonify({"error": "Sin permisos"}), 403

    conn, should_close = _get_conn()
    _safe_rollback(conn)
    try:
        with conn.cursor() as cur:
            cur.execute("CALL sp_get_schema_alerts_full(%s)", ("cur_schema_alerts",))
            cur.execute('FETCH ALL FROM "cur_schema_alerts"')
            rows = [dict(r) for r in cur.fetchall()]
        conn.commit()
    except Exception as e:
        _safe_rollback(conn)
        logger.error(f"Error en /api/alertas-esquema: {e}")
        rows = []
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    return jsonify(rows)


# =============================================================================
# CLI
# =============================================================================

@app.cli.command("init-db")
def cli_init_database():
    """Inicializa la base de datos. Usar antes de `flask run` si aplica."""
    from db_init import init_database
    init_database()


if __name__ == "__main__":
    try:
        from db_init import init_database
        with app.app_context():
            init_database()
    except Exception as e:
        logger.error(f"Error durante inicialización de DB: {e}")
        raise

    logger.info("✓ Flask iniciando en http://127.0.0.1:5000")
    app.run(debug=True)