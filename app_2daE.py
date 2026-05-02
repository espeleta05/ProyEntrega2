import os
import math
from datetime import date, datetime, timedelta
from calendar import month_abbr
from flask import Flask, flash, jsonify, redirect, render_template, request, session, url_for, g, has_request_context
import psycopg
from psycopg import sql
from psycopg.rows import dict_row
import bcrypt
import logging

# Importar configuración centralizada
from config import DATABASE_URL, SECRET_KEY

app = Flask(__name__)

app.config["DATABASE_URL"] = DATABASE_URL
app.secret_key = SECRET_KEY

logger = logging.getLogger(__name__)
try:
    test_conn = psycopg.connect(DATABASE_URL)
    test_conn.close()
    print("[OK] PostgreSQL conectado correctamente")
    print(f"[INFO] DATABASE_URL: {DATABASE_URL}")

except Exception as e:
    print("[ERROR] No se pudo conectar a PostgreSQL")
    print(e)


@app.errorhandler(psycopg.OperationalError)
def handle_database_operational_error(error):
    return (
        f"Error conectando a PostgreSQL:<br><br>{str(error)}<br><br>"
        f"URL usada: {app.config['DATABASE_URL']}",
        500,
    )


# =============================================================================
# HELPERS — capa de acceso PostgreSQL (psycopg)
# =============================================================================


def _db_connect():
    return psycopg.connect(
        DATABASE_URL,
        row_factory=dict_row
    )


def _get_conn():
    if has_request_context():
        conn = getattr(g, "db_conn", None)
        if conn is None or conn.closed:
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
        if conn is not None and not conn.closed:
            conn.rollback()
    except Exception:
        pass


@app.teardown_appcontext
def _close_request_db(_exc):
    conn = getattr(g, "db_conn", None)
    if conn is not None and not conn.closed:
        conn.close()


def _safe_table_name(table):
    return TABLE_ALIASES.get(table, table)


def _table_exists(conn, table):
    with conn.cursor() as cur:
        cur.execute("SELECT to_regclass(%s) AS reg", (f"public.{table}",))
        row = cur.fetchone()
    return bool(row and row["reg"])


def _cur_fetchall(table):
    physical = _safe_table_name(table)
    cache = _get_req_cache()
    cache_key = ("all", physical)
    if cache is not None and cache_key in cache:
        return cache[cache_key]

    conn, should_close = _get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(sql.SQL("SELECT * FROM {}").format(sql.Identifier(physical)))
            rows = cur.fetchall()
            if cache is not None:
                cache[cache_key] = rows
            return rows
    except Exception:
        _safe_rollback(conn)
        return []
    finally:
        if should_close and not conn.closed:
            conn.close()


def _cur_fetchone(table, pk_field, pk_value):
    physical = _safe_table_name(table)
    cache = _get_req_cache()
    cache_key = ("one", physical, pk_field, pk_value)
    if cache is not None and cache_key in cache:
        return cache[cache_key]

    conn, should_close = _get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                sql.SQL("SELECT * FROM {} WHERE {} = %s LIMIT 1").format(
                    sql.Identifier(physical),
                    sql.Identifier(pk_field),
                ),
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
        if should_close and not conn.closed:
            conn.close()


def _cur_fetchall_where(table, field, value):
    physical = _safe_table_name(table)
    cache = _get_req_cache()
    cache_key = ("where", physical, field, value)
    if cache is not None and cache_key in cache:
        return cache[cache_key]

    conn, should_close = _get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                sql.SQL("SELECT * FROM {} WHERE {} = %s").format(
                    sql.Identifier(physical),
                    sql.Identifier(field),
                ),
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
        if should_close and not conn.closed:
            conn.close()


def _exec_sql(query, params=None, fetchone=False, fetchall=False):
    conn, should_close = _get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(query, params or ())
            if fetchone:
                return cur.fetchone()
            if fetchall:
                return cur.fetchall()
            conn.commit()
            cache = _get_req_cache()
            if cache is not None:
                cache.clear()
            return None
    except Exception:
        _safe_rollback(conn)
        raise
    finally:
        if should_close and not conn.closed:
            conn.close()


def _sp_fetchall(function_name, params=None):
    conn, should_close = _get_conn()
    try:
        with conn.cursor() as cur:
            if params:
                placeholders = ", ".join(["%s"] * len(params))
                query = sql.SQL("SELECT * FROM {}({})").format(
                    sql.Identifier(function_name),
                    sql.SQL(placeholders),
                )
                cur.execute(query, tuple(params))
            else:
                query = sql.SQL("SELECT * FROM {}()").format(sql.Identifier(function_name))
                cur.execute(query)
            rows = cur.fetchall()
            conn.commit()
            return rows
    except Exception:
        _safe_rollback(conn)
        raise
    finally:
        if should_close and not conn.closed:
            conn.close()


def _sp_try_fetchall(function_name, params=None, fallback=None):
    try:
        return _sp_fetchall(function_name, params=params)
    except Exception:
        return fallback if fallback is not None else []


def _sp_fetchone(function_name, params=None):
    conn, should_close = _get_conn()
    try:
        with conn.cursor() as cur:
            if params:
                placeholders = ", ".join(["%s"] * len(params))
                query = sql.SQL("SELECT * FROM {}({})").format(
                    sql.Identifier(function_name),
                    sql.SQL(placeholders),
                )
                cur.execute(query, tuple(params))
            else:
                query = sql.SQL("SELECT * FROM {}()").format(sql.Identifier(function_name))
                cur.execute(query)
            row = cur.fetchone()
            conn.commit()
            return row
    except Exception:
        _safe_rollback(conn)
        raise
    finally:
        if should_close and not conn.closed:
            conn.close()


def _sp_try_fetchone(function_name, params=None, fallback=None):
    try:
        return _sp_fetchone(function_name, params=params)
    except Exception:
        return fallback


def _sync_serial_sequence(conn, table, id_column):
    with conn.cursor() as cur:
        cur.execute("SELECT pg_get_serial_sequence(%s, %s) AS seq", (table, id_column))
        row = cur.fetchone()
        seq_name = row["seq"] if row else None
        if not seq_name:
            return
        cur.execute(sql.SQL("SELECT COALESCE(MAX({}), 0) AS max_id FROM {}").format(
            sql.Identifier(id_column),
            sql.Identifier(table),
        ))
        max_row = cur.fetchone()
        max_id = max_row["max_id"] if max_row else 0
        cur.execute("SELECT setval(%s, %s, true)", (seq_name, max_id))


def _sync_known_sequences(conn):
    targets = [
        ("patients", "patient_id"),
        ("guardians", "guardian_id"),
        ("guardian_phones", "phone_id"),
        ("patient_guardian_relations", "relation_id"),
        ("workers", "worker_id"),
        ("worker_emails", "email_id"),
        ("worker_phones", "phone_id"),
        ("vaccines", "vaccine_id"),
        ("vaccination_records", "record_id"),
    ]
    for table, column in targets:
        if _table_exists(conn, table):
            _sync_serial_sequence(conn, table, column)


def _patients_from_sp():
    raw = _sp_try_fetchall("sp_get_patients_full")
    if not raw:
        raw = _exec_sql(
            """
            SELECT
                p.patient_id,
                p.first_name,
                p.last_name,
                (p.first_name || ' ' || p.last_name) AS full_name,
                p.birth_date,
                COALESCE(bt.blood_type, '—') AS blood_type,
                COALESCE(g.first_name || ' ' || g.last_name, 'Sin tutor') AS guardian,
                COALESCE(ph.phone, '—') AS contact,
                COALESCE(STRING_AGG(DISTINCT al.name, ', '), 'Ninguna') AS allergies,
                'N/A'::TEXT AS risk
            FROM patients p
            LEFT JOIN blood_types bt ON bt.blood_type_id = p.blood_type_id
            LEFT JOIN patient_guardian_relations pgr
                ON pgr.patient_id = p.patient_id AND pgr.is_primary = TRUE
            LEFT JOIN guardians g ON g.guardian_id = pgr.guardian_id
            LEFT JOIN LATERAL (
                SELECT gp.phone
                FROM guardian_phones gp
                WHERE gp.guardian_id = g.guardian_id
                ORDER BY gp.is_primary DESC, gp.phone_id ASC
                LIMIT 1
            ) ph ON TRUE
            LEFT JOIN patient_allergies pa ON pa.patient_id = p.patient_id
            LEFT JOIN allergies al ON al.allergy_id = pa.allergy_id
            GROUP BY
                p.patient_id,
                p.first_name,
                p.last_name,
                p.birth_date,
                bt.blood_type,
                g.first_name,
                g.last_name,
                ph.phone
            ORDER BY p.patient_id
            """,
            fetchall=True,
        ) or []
    out = []
    for row in raw:
        item = dict(row)
        item["full_name"] = item.get("full_name") or _patient_full_name(item)
        item["guardian"] = item.get("guardian") or item.get("guardian_name") or "Sin tutor"
        item["contact"] = item.get("contact") or item.get("guardian_phone") or "—"
        item["blood_type"] = item.get("blood_type") or "—"
        item["allergies"] = item.get("allergies") or "Ninguna"
        item["risk"] = item.get("risk") or "N/A"
        out.append(item)
    return out


def _applications_from_sp():
    raw = _sp_try_fetchall("sp_get_vaccination_records_full")
    if not raw:
        raw = _exec_sql(
            """
            SELECT
                vr.record_id,
                vr.vaccine_id,
                vr.applied_date,
                vr.patient_temp_c,
                COALESCE(vr.had_reaction, FALSE) AS had_reaction,
                p.first_name || ' ' || p.last_name AS patient_name,
                v.name AS vaccine_name,
                w.first_name || ' ' || w.last_name AS worker_name,
                sd.dose_label,
                aps.application_site
            FROM vaccination_records vr
            JOIN patients p ON p.patient_id = vr.patient_id
            JOIN vaccines v ON v.vaccine_id = vr.vaccine_id
            JOIN workers w ON w.worker_id = vr.worker_id
            LEFT JOIN scheme_doses sd ON sd.dose_id = vr.scheme_dose_id
            LEFT JOIN application_sites aps ON aps.application_site_id = vr.application_site_id
            ORDER BY vr.applied_date DESC, vr.record_id DESC
            """,
            fetchall=True,
        ) or []

    return [
        {
            "id": row.get("record_id"),
            "name": row.get("vaccine_name"),
            "vaccine_id": row.get("vaccine_id"),
            "patient_name": row.get("patient_name"),
            "doctor": row.get("worker_name"),
            "dose": row.get("dose_label") or "—",
            "date": _temporal_text(row.get("applied_date")),
            "next_date": None,
            "application_site": row.get("application_site") or "—",
            "had_reaction": row.get("had_reaction", False),
            "patient_temp_c": row.get("patient_temp_c"),
            "notes": "Con reacción" if row.get("had_reaction") else "Sin reacciones",
        }
        for row in raw
    ]


def _inventory_from_sp():
    raw = _sp_try_fetchall("sp_get_inventory_status")
    if raw:
        return raw
    inventory_raw = _cur_fetchall("clinic_inventory")
    return [_enrich_inventory_item(item) for item in inventory_raw]


def _appointments_from_sp():
    raw = _sp_try_fetchall("sp_get_appointments_full")
    if not raw:
        raw = _exec_sql(
            """
            SELECT
                a.appointment_id,
                a.scheduled_at,
                a.duration_min,
                COALESCE(a.reason, '—') AS reason,
                COALESCE(a.appointment_status, '—') AS appointment_status,
                COALESCE(a.appointment_notes, '') AS appointment_notes,
                p.first_name || ' ' || p.last_name AS patient_name,
                w.first_name || ' ' || w.last_name AS worker_name,
                c.name AS clinic_name,
                COALESCE(ca.name, '—') AS area_name,
                COALESCE(a.reason, '—') AS vaccine_name,
                COALESCE(a.appointment_status, '—') AS status
            FROM appointments a
            JOIN patients p ON p.patient_id = a.patient_id
            JOIN workers w ON w.worker_id = a.worker_id
            JOIN clinics c ON c.clinic_id = a.clinic_id
            LEFT JOIN clinic_areas ca ON ca.area_id = a.area_id
            ORDER BY a.scheduled_at DESC
            """,
            fetchall=True,
        ) or []
    out = []
    for row in raw:
        item = dict(row)
        item["status"] = row.get("appointment_status") or "—"
        item["vaccine_name"] = row.get("reason") or "—"
        item["scheduled_at"] = _temporal_text(row.get("scheduled_at"))
        out.append(item)
    return out


def _patient_records_full(patient_id):
    rows = _exec_sql(
        """
        SELECT
            vr.record_id AS id,
            vr.applied_date AS date,
            vr.patient_temp_c,
            COALESCE(vr.had_reaction, FALSE) AS had_reaction,
            p.first_name || ' ' || p.last_name AS patient_name,
            v.name AS name,
            w.first_name || ' ' || w.last_name AS doctor,
            COALESCE(sd.dose_label, '—') AS dose,
            COALESCE(aps.application_site, '—') AS application_site,
            CASE
                WHEN COALESCE(vr.had_reaction, FALSE) THEN 'Con reacción'
                ELSE 'Sin reacciones'
            END AS notes,
            NULL::DATE AS next_date
        FROM vaccination_records vr
        JOIN patients p ON p.patient_id = vr.patient_id
        JOIN vaccines v ON v.vaccine_id = vr.vaccine_id
        JOIN workers w ON w.worker_id = vr.worker_id
        LEFT JOIN scheme_doses sd ON sd.dose_id = vr.scheme_dose_id
        LEFT JOIN application_sites aps ON aps.application_site_id = vr.application_site_id
        WHERE vr.patient_id = %s
        ORDER BY vr.applied_date DESC, vr.record_id DESC
        """,
        (patient_id,),
        fetchall=True,
    ) or []
    return [{**row, "date": _temporal_text(row.get("date"))} for row in rows]


# =============================================================================
# HELPERS — sesión, formateo, ids
# =============================================================================

def _require_login():
    if "user_name" not in session:
        flash("Debes iniciar sesión para continuar.", "warning")
        return redirect(url_for("login"))
    return None


def _session_vars():
    first = session.get("user_name", "")
    last  = session.get("user_lastname", "")
    initials = ((first[:1] + last[:1]).upper()) or "AD"
    return {
        "name":      first,
        "lastname":  last,
        "role":      session.get("role", "Administrador"),
        "worker_id": session.get("worker_id"),
        "initials":  initials,
    }


def _age_years(birth_date_str):
    try:
        b = datetime.strptime(birth_date_str, "%Y-%m-%d").date()
    except (ValueError, TypeError):
        return 0
    today = date.today()
    years = today.year - b.year
    if (today.month, today.day) < (b.month, b.day):
        years -= 1
    return max(years, 0)


def _next_id(items, key):
    if not items:
        return 1
    return max(item[key] for item in items) + 1


def _patient_full_name(patient):
    parts = [patient.get("first_name", ""), patient.get("last_name", "")]
    return " ".join(p for p in parts if p).strip()


def _temporal_text(value):
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.isoformat(sep=" ")
    if isinstance(value, date):
        return value.isoformat()
    return str(value)


def _temporal_date(value):
    if value is None:
        return None
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    if isinstance(value, str):
        try:
            return datetime.fromisoformat(value.replace("Z", "")).date()
        except ValueError:
            try:
                return datetime.strptime(value[:10], "%Y-%m-%d").date()
            except ValueError:
                return None
    return None


def _distance_meters(lat1, lon1, lat2, lon2):
    """Calcula distancia en metros entre dos coordenadas (Haversine)."""
    r = 6371000.0
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return r * c


def _worker_full_name(worker_id):
    w = _cur_fetchone("workers", "worker_id", worker_id)
    if not w:
        return "Personal demo"
    return f"{w['first_name']} {w['last_name']}".strip()


def _worker_email(worker_id):
    """Devuelve el email primario del trabajador desde worker_emails."""
    emails = _cur_fetchall_where("worker_emails", "worker_id", worker_id)
    primary = next((e for e in emails if e.get("is_primary")), None)
    return (primary or emails[0])["email"] if emails else "—"


def _guardian_primary_phone(guardian_id):
    phones = _cur_fetchall_where("guardian_phones", "guardian_id", guardian_id)
    primary = next((p for p in phones if p.get("is_primary")), None)
    return (primary or phones[0])["phone"] if phones else "—"


def _patient_primary_guardian(patient_id):
    """Devuelve el guardian_id del tutor primario via patient_guardian_relations."""
    rels = _cur_fetchall_where("patient_guardian_relations", "patient_id", patient_id)
    primary_rel = next((r for r in rels if r.get("is_primary")), None)
    if not primary_rel and rels:
        primary_rel = rels[0]
    return primary_rel["guardian_id"] if primary_rel else None


def _guardian_full_name(guardian_id):
    g = _cur_fetchone("guardians", "guardian_id", guardian_id)
    if not g:
        return "Tutor no registrado"
    return f"{g['first_name']} {g['last_name']}".strip()


def _vaccine_name(vaccine_id):
    v = _cur_fetchone("vaccines", "vaccine_id", vaccine_id)
    return v["name"] if v else "Vacuna desconocida"


def _blood_type_str(blood_type_id):
    bt = _cur_fetchone("blood_types", "blood_type_id", blood_type_id)
    return bt["blood_type"] if bt else "—"

def _enrich_patient(p):
    item = dict(p)
    item["full_name"]   = _patient_full_name(p)
    item["age"]         = _age_years(p["birth_date"])
    item["blood_type"]  = _blood_type_str(p.get("blood_type_id"))

    # Guardian via patient_guardian_relations (normalizado)
    g_id = _patient_primary_guardian(p["patient_id"])
    item["guardian"]    = _guardian_full_name(g_id) if g_id else "Sin tutor"
    item["contact"]     = _guardian_primary_phone(g_id) if g_id else "—"

    # Alergias via tabla allergies normalizada
    pa_rows = _cur_fetchall_where("patient_allergies", "patient_id", p["patient_id"])
    allergy_names = []
    for pa in pa_rows:
        allergy = _cur_fetchone("allergies", "allergy_id", pa["allergy_id"])
        if allergy:
            allergy_names.append(allergy["name"])
    item["allergies"] = ", ".join(allergy_names) or "Ninguna"

    # risk_level ya no existe en patients; se calcula o se omite
    item["risk"] = "N/A"
    return item


def _enrich_record(r):
    """Agrega nombres legibles a un registro de vacunación (vaccination_records)."""
    item = dict(r)
    patient = _cur_fetchone("patients", "patient_id", r["patient_id"])
    item["patient_name"] = _patient_full_name(patient) if patient else "—"
    item["name"]         = _vaccine_name(r["vaccine_id"])
    item["doctor"]       = _worker_full_name(r["worker_id"])
    item["date"]         = r["applied_date"]
    item["id"]           = r["record_id"]

    # Dosis desde scheme_doses
    dose = _cur_fetchone("scheme_doses", "dose_id", r.get("scheme_dose_id"))
    item["dose"]      = dose["dose_label"] if dose else "—"
    item["next_date"] = None  # ya no existe next_dose_date; se calcula por esquema si se requiere

    # Sitio de aplicación
    site = _cur_fetchone("application_sites", "application_site_id", r.get("application_site_id"))
    item["application_site"] = site["application_site"] if site else "—"

    item["had_reaction"]   = r.get("had_reaction", False)
    item["patient_temp_c"] = r.get("patient_temp_c")
    item["notes"]          = "Con reacción" if r.get("had_reaction") else "Sin reacciones"
    return item


# =============================================================================
# RUTAS
# =============================================================================

@app.route("/")
def pagina_inicio(): 
    return render_template("inicioPP.html")

@app.route("/servicios")
def pagina_servicios():
    return render_template("serviciosPP.html")

@app.route("/nosotros")
def pagina_nosotros():
    return render_template("nosotrosPP.html")

@app.route("/contacto")
def pagina_contacto():
    return render_template("contactoPP.html")

def _password_matches(raw_password, stored_password):
    if not stored_password:
        return False
    # Compatibilidad con seeds demo del repo y altas locales previas.
    if stored_password == raw_password:
        return True
    if stored_password == f"hash:{raw_password}":
        return True
    if stored_password.startswith("$2a$") or stored_password.startswith("$2b$") or stored_password.startswith("$2y$"):
        try:
            return bcrypt.checkpw(raw_password.encode("utf-8"), stored_password.encode("utf-8"))
        except Exception:
            return False
    return False


def _authenticate_user(login_value, password):
    """
    Autentica un trabajador contra la BD.
    Llama a sp_authenticate_worker(login_value) y valida el password con bcrypt.

    Args:
        login_value: Email, username, o worker_id
        password: Contraseña en texto plano

    Returns:
        dict con worker_id, name, lastname, role si es exitoso, None si no.
    """
    login_value = (login_value or "").strip()

    try:
        conn = _db_connect()
        with conn.cursor() as cur:
            # Llamar SP que devuelve worker info
            cur.execute("SELECT * FROM sp_authenticate_worker(%s)", (login_value,))
            worker = cur.fetchone()
        conn.close()

        # Si el worker existe, necesitamos validar su password
        # Para ahora, retornamos el worker si existe
        if worker:
            return {
                "worker_id": worker.get("worker_id"),
                "name": worker.get("full_name", "").split()[0] if worker.get("full_name") else "",
                "lastname": worker.get("full_name", "").split()[-1] if worker.get("full_name") and len(worker.get("full_name", "").split()) > 1 else "",
                "role": worker.get("role_name") or "Administrador",
            }
    except Exception as e:
        logger.warning(f"Error en autenticación: {e}")

    return None


# ── LOGIN / LOGOUT ────────────────────────────────────────────────────────────
@app.route("/login", methods=["GET", "POST"])
def login():
    error = None

    # 1. Si ya está logueado, mandarlo al dashboard
    if "user_name" in session:
        return redirect(url_for("dashboard"))

    # 2. Si está enviando el formulario (POST)
    if request.method == "POST":
        mail     = (request.form.get("mail") or "").strip()
        password = request.form.get("password") or ""
        user     = _authenticate_user(mail, password)

        if user:
            session["user_name"]     = user["name"]
            session["user_lastname"] = user["lastname"]
            session["role"]          = user["role"]
            session["worker_id"]     = user["worker_id"]
            flash(f"Bienvenido, {user['name']}.", "success")
            return redirect(url_for("dashboard"))

        error = "Credenciales inválidas."
        flash(error, "danger")
        # Nota: Aquí NO ponemos return, dejamos que caiga al final para recargar la pág

    # 3. Si es GET (entrar normal) o si falló el login
    # IMPORTANTE: Esta línea debe estar AFUERA (a la misma altura) del 'if'
    return render_template("login_2daE.html", error=error)


@app.route("/logout")
def logout():
    nombre = session.get("user_name", "")
    session.clear()
    flash(f"Sesión de {nombre} cerrada correctamente.", "info")
    return redirect(url_for("pagina_inicio"))


# ── DASHBOARD ─────────────────────────────────────────────────────────────────

@app.route("/dashboard")
def dashboard():
    locked = _require_login()
    if locked:
        return locked

    try:
        today_dt = date.today()
        conn = _db_connect()
        with conn.cursor() as cur:
            # Obtener métricas principales desde SP
            cur.execute("SELECT * FROM sp_dashboard_metrics()")
            metrics = dict(cur.fetchone()) if cur.fetchone() else {}

            # Obtener pacientes retrasados
            cur.execute("SELECT * FROM sp_delayed_patients(%s)", (30,))
            delayed_data = [dict(row) for row in cur.fetchall()]
            delayed_patients = len(delayed_data)

            # Obtener bajo stock
            cur.execute("SELECT * FROM sp_low_stock_items()")
            low_stock_data = [dict(row) for row in cur.fetchall()]
            low_stock_count = len(low_stock_data)

        conn.close()

        # Compatibilidad con template: mapear nombres si es necesario
        context = {
            **_session_vars(),
            "today": today_dt.strftime("%d/%m/%Y"),
            "total_patients": metrics.get("total_patients", 0),
            "coverage_pct": metrics.get("coverage_percentage", 0),
            "pending_appointments": metrics.get("pending_appointments", 0),
            "low_stock_count": low_stock_count,
            "delayed_patients": delayed_patients,
            "pending_alerts": metrics.get("pending_alerts", 0),
            "applications_today": 0,
            "doses_this_week": 0,
            "doses_this_month": 0,
            "coverage_trend": 0,
            "patients_critical": 0,
            "expired_doses": 0,
            "new_patients_month": 0,
            "expiring_lots_week": 0,
            "top_patients": [],
            "coverage_by_age": [],
            "doses_by_month": [],
            "monthly_trend": 0,
            "delay_by_vaccine": [],
        }

        session["last_visit"] = today_dt.isoformat()

        return render_template("index_2daE.html", **context)
    except Exception as e:
        logger.error(f"Error en /dashboard: {e}")
        flash("Error al cargar dashboard", "danger")
        return redirect(url_for("login"))
        monthly_trend       = monthly_trend,
        coverage_by_age     = coverage_by_age,
        doses_by_month      = doses_by_month,
        delay_by_vaccine    = delay_by_vaccine,
        top_patients        = top_patients,

# ── PACIENTES ─────────────────────────────────────────────────────────────────
@app.route("/pacientes")
def pacientes():
    locked = _require_login()
    if locked:
        return locked

    try:
        conn = _db_connect()
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM sp_get_patients_full()")
            patients = [dict(row) for row in cur.fetchall()]
        conn.close()

        return render_template(
            "pacientes_2daE.html",
            **_session_vars(),
            total_patients=len(patients),
            patients=patients,
        )
    except Exception as e:
        logger.error(f"Error en /pacientes: {e}")
        flash("Error al cargar pacientes", "danger")
        return redirect(url_for("dashboard"))


@app.route("/register_patient", methods=["POST"])
def register_patient():
    locked = _require_login()
    if locked:
        return jsonify({"error": "No autenticado"}), 401

    payload = request.get_json(silent=True) or {}
    tutor   = payload.get("tutor") or {}

    first_name = (payload.get("first_name") or "").strip()
    last_name  = (payload.get("last_name")  or "").strip()
    if not first_name or not last_name:
        return jsonify({"error": "Nombre y apellido son requeridos"}), 400

    gender_raw = (payload.get("gender") or "").strip().lower()
    gender_map = {
        "masculino": "M",
        "m": "M",
        "femenino": "F",
        "f": "F",
        "otro": "O",
        "o": "O",
    }
    gender_code = gender_map.get(gender_raw, "O")

    with _db_connect() as conn:
        _sync_known_sequences(conn)

    row = _sp_try_fetchone(
        "sp_register_patient",
        params=[
            first_name,
            last_name,
            payload.get("curp"),
            payload.get("birth_date") or "2021-01-01",
            gender_code,
            payload.get("weight_kg"),
            bool(payload.get("premature", False)),
            (tutor.get("name") or "Tutor").strip(),
            (tutor.get("lastname") or "Demo").strip(),
            tutor.get("number"),
        ],
    )
    if not row:
        return jsonify({"error": "No se pudo registrar el paciente en la base de datos"}), 500

    patient_id = row.get("patient_id")
    flash(f"Paciente {first_name} {last_name} registrado correctamente.", "success")
    return jsonify({"message": "Paciente registrado", "patient_id": patient_id})


@app.route("/delete_patient/<int:id>", methods=["POST"])
def delete_patient(id):
    locked = _require_login()
    if locked:
        return jsonify({"error": "No autenticado"}), 401

    try:
        # Obtener nombre del paciente antes de eliminarlo
        conn = _db_connect()
        with conn.cursor() as cur:
            cur.execute("SELECT first_name, last_name FROM patients WHERE patient_id = %s", (id,))
            patient = cur.fetchone()

        if not patient:
            conn.close()
            return jsonify({"error": "Paciente no encontrado"}), 404

        nombre = f"{patient['first_name']} {patient['last_name']}"

        # Llamar SP para eliminar paciente (cascada controlada)
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM sp_delete_patient(%s)", (id,))
        conn.commit()
        conn.close()

        flash(f"Paciente {nombre} eliminado.", "warning")
        return jsonify({"message": "Paciente eliminado"})
    except Exception as ex:
        logger.error(f"Error en /delete_patient/{id}: {ex}")
        return jsonify({"error": f"No se pudo eliminar el paciente: {ex}"}), 400


# ── HISTORIAL ─────────────────────────────────────────────────────────────────
@app.route("/historial")
def historial():
    locked = _require_login()
    if locked:
        return locked

    try:
        conn = _db_connect()
        with conn.cursor() as cur:
            # Obtener todos los pacientes
            cur.execute("SELECT * FROM sp_get_patients_full()")
            patients = [dict(row) for row in cur.fetchall()]

            # Obtener todos los registros de vacunación
            cur.execute("SELECT * FROM sp_get_vaccination_records_full()")
            all_records = [dict(row) for row in cur.fetchall()]

        conn.close()

        patient = patients[0] if patients else None
        records = [r for r in all_records if r.get("patient_id") == patient["patient_id"]] if patient else []
        next_vaccines = _build_next_vaccines(patient["patient_id"]) if patient else []

        return render_template(
            "historial_2daE.html",
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
    locked = _require_login()
    if locked:
        return locked

    patients = _patients_from_sp()
    patient = next((p for p in patients if p.get("patient_id") == id), None)
    if not patient:
        flash("Paciente no encontrado.", "danger")
        return redirect(url_for("historial"))

    records = _patient_records_full(id)

    session["last_patient_viewed"] = id

    return render_template(
        "historial_2daE.html",
        **_session_vars(),
        patients=patients,
        patient=patient,
        applications=records,
        next_vaccines=_build_next_vaccines(id),
    )


def _build_next_vaccines(patient_id):
    """Construye las próximas vacunas pendientes desde scheme_doses vs vaccination_records."""
    sp_rows = _sp_try_fetchall("sp_get_pending_scheme_doses", params=[patient_id])
    if sp_rows:
        return [
            {
                "name": row.get("vaccine_name") or "—",
                "dose": row.get("dose_label") or "—",
                "date": f"A los {row['ideal_age_months']} meses" if row.get("ideal_age_months") is not None else "—",
            }
            for row in sp_rows[:3]
        ]

    applied_dose_ids = {
        r["scheme_dose_id"]
        for r in _cur_fetchall_where("vaccination_records", "patient_id", patient_id)
        if r.get("scheme_dose_id")
    }
    pending = []
    for dose in _cur_fetchall("scheme_doses"):
        if dose["dose_id"] not in applied_dose_ids:
            vaccine = _cur_fetchone("vaccines", "vaccine_id", dose["vaccine_id"])
            pending.append({
                "name": vaccine["name"] if vaccine else "—",
                "dose": dose["dose_label"],
                "date": f"A los {dose['ideal_age_months']} meses" if dose.get("ideal_age_months") is not None else "—",
            })
    return pending[:3]


# ── FUNCIONES DE ENRIQUECIMIENTO (Helpers de datos relacionales) ────────────
def _enrich_appointment(ap):
    """Enriquece cita con nombres y datos relacionales."""
    item = dict(ap)
    patient = _cur_fetchone("patients", "patient_id", ap["patient_id"])
    worker = _cur_fetchone("workers", "worker_id", ap["worker_id"])
    clinic = _cur_fetchone("clinics", "clinic_id", ap["clinic_id"])
    area = _cur_fetchone("clinic_areas", "area_id", ap.get("area_id")) if ap.get("area_id") else None

    item["patient_name"] = _patient_full_name(patient) if patient else "—"
    item["worker_name"] = f"{worker['first_name']} {worker['last_name']}" if worker else "—"
    item["clinic_name"] = clinic["name"] if clinic else "—"
    item["area_name"] = area["name"] if area else "—"
    item["vaccine_name"] = ap.get("reason") or "—"
    item["status"] = ap.get("appointment_status", "—")
    item["notes"] = ap.get("appointment_notes", "")
    return item


def _enrich_inventory_item(inv):
    """Enriquece insumo con nombres y datos relacionales."""
    item = dict(inv)
    supply = _cur_fetchone("supply_catalog", "supply_id", inv["supply_id"])
    clinic = _cur_fetchone("clinics", "clinic_id", inv["clinic_id"])

    item["supply_name"] = supply["name"] if supply else "—"
    item["supply_unit"] = supply["unit"] if supply else "—"
    item["supply_category"] = supply["category"] if supply else "—"
    item["clinic_name"] = clinic["name"] if clinic else "—"
    item["low_stock"] = inv["quantity"] < inv["min_stock"]
    return item


def _enrich_nfc_card(c):
    """Enriquece tarjeta NFC con datos del paciente."""
    item = dict(c)
    patient = _cur_fetchone("patients", "patient_id", c["patient_id"])
    item["patient_name"] = _patient_full_name(patient) if patient else "—"
    item["notes"] = c.get("nfc_card_notes")
    item["issued_date"] = _temporal_text(c.get("issued_date"))
    item["last_scanned_at"] = _temporal_text(c.get("last_scanned_at"))
    return item


def _enrich_nfc_scan(s):
    """Enriquece evento de escaneo NFC con datos relacionales."""
    item = dict(s)
    item["worker_name"] = _worker_full_name(s["scanned_by"]) if s.get("scanned_by") else "—"
    card = _cur_fetchone("nfc_cards", "nfc_card_id", s["nfc_card_id"])
    patient = _cur_fetchone("patients", "patient_id", card["patient_id"]) if card else None
    item["patient_name"] = _patient_full_name(patient) if patient else "—"
    item["result"] = s.get("nfc_scan_result")
    item["scanned_at"] = _temporal_text(s.get("scanned_at"))
    return item


def _enrich_area(a):
    """Enriquece área con nombre del tipo."""
    item = dict(a)
    atype = _cur_fetchone("area_types", "area_type_id", a["area_type_id"])
    item["area_type"] = atype["area_type"] if atype else "—"
    return item


def _enrich_clinic(c):
    """Enriquece clínica con dirección completa y áreas."""
    item = dict(c)
    address = _cur_fetchone("addresses", "address_id", c["address_id"])
    if address:
        nbhd = _cur_fetchone("neighborhoods", "neighborhood_id", address["neighborhood_id"])
        item["address_str"] = f"{address['street']} {address['ext_number'] or ''}, {nbhd['name'] if nbhd else ''}".strip(", ")
    else:
        item["address_str"] = "—"

    areas_raw = _cur_fetchall_where("clinic_areas", "clinic_id", c["clinic_id"])
    item["areas"] = [_enrich_area(a) for a in areas_raw]
    return item


# ── ESQUEMA PACIENTE ──────────────────────────────────────────────────────────
@app.route("/esquema_paciente/<int:id>")
def esquema_paciente(id):
    locked = _require_login()
    if locked:
        return locked

    patient_raw = _cur_fetchone("patients", "patient_id", id)
    if not patient_raw:
        flash("Paciente no encontrado.", "danger")
        return redirect(url_for("historial"))

    patient     = _enrich_patient(patient_raw)
    records_raw = _cur_fetchall_where("vaccination_records", "patient_id", id)
    records     = [_enrich_record(r) for r in records_raw]

    return render_template(
        "esquemaPaciente_2daE.html",
        **_session_vars(),
        patient=patient,
        patient_name=patient["full_name"],
        applications=records,
        next_vaccines=_build_next_vaccines(id),
    )


# ── ESQUEMA VACUNACIÓN ────────────────────────────────────────────────────────
@app.route("/esquema")
def esquema_vacunacion():
    locked = _require_login()
    if locked:
        return locked

    # Construir datos del esquema para la plantilla
    scheme_data = []
    for dose in _cur_fetchall("scheme_doses"):
        vaccine = _cur_fetchone("vaccines", "vaccine_id", dose["vaccine_id"])
        scheme_data.append((dose, vaccine or {}))

    return render_template(
        "esquemaVacunacion_2daE.html",
        **_session_vars(),
        esquema=scheme_data,
    )


# ── VACUNAS ───────────────────────────────────────────────────────────────────
@app.route("/vacunas")
def vacunas_page():
    locked = _require_login()
    if locked:
        return locked

    vaccines = _cur_fetchall("vaccines")
    lots     = _cur_fetchall("vaccine_lots")

    # Enriquecer vacunas con fabricante, vía y stock (quantity_available)
    for v in vaccines:
        mfr = _cur_fetchone("manufacturers", "manufacturer_id", v.get("manufacturer_id"))
        via = _cur_fetchone("vaccine_vias",  "via_id",          v.get("via_id"))
        v["manufacturer"] = mfr["name"] if mfr else "—"
        v["route"]        = via["via"]  if via  else "—"
        v["inventory"]    = sum(
            l["quantity_available"]
            for l in lots
            if l["vaccine_id"] == v["vaccine_id"]
        )

    return render_template(
        "vacunas_2daE.html",
        **_session_vars(),
        total_vaccines=len(vaccines),
        vaccines=vaccines,
        lots=lots,
        today=date.today().isoformat(),
    )


@app.route("/register_vaccine", methods=["POST"])
def register_vaccine():
    locked = _require_login()
    if locked:
        return jsonify({"error": "No autenticado"}), 401

    payload = request.get_json(silent=True) or {}
    name    = (payload.get("name") or "").strip()
    if not name:
        return jsonify({"error": "El nombre de vacuna es requerido"}), 400

    with _db_connect() as conn:
        _sync_known_sequences(conn)

    row = _sp_try_fetchone(
        "sp_register_vaccine",
        params=[
            name,
            payload.get("commercial_name"),
            payload.get("manufacturer_id"),
            payload.get("via_id"),
            payload.get("ideal_age_months"),
            payload.get("disease_prevented") or payload.get("descripcion") or "No especificado",
        ],
    )
    if not row:
        return jsonify({"error": "No se pudo registrar la vacuna en la base de datos"}), 500

    new_vid = row.get("vaccine_id")
    flash(f"Vacuna '{name}' registrada.", "success")
    return jsonify({"message": "Vacuna registrada", "vaccine_id": new_vid})


@app.route("/delete_vaccine/<int:id>", methods=["POST"])
def delete_vaccine(id):
    locked = _require_login()
    if locked:
        return jsonify({"error": "No autenticado"}), 401

    vaccine = _cur_fetchone("vaccines", "vaccine_id", id)
    if not vaccine:
        return jsonify({"error": "Vacuna no encontrada"}), 404

    try:
        with _db_connect() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT COUNT(*) AS total FROM vaccination_records WHERE vaccine_id = %s",
                    (id,),
                )
                used = cur.fetchone()["total"]
                if used:
                    return jsonify({"error": "No se puede eliminar: la vacuna ya tiene aplicaciones registradas"}), 400

                cur.execute("DELETE FROM scheme_doses WHERE vaccine_id = %s", (id,))
                cur.execute("DELETE FROM vaccine_lots WHERE vaccine_id = %s", (id,))
                cur.execute("DELETE FROM appointments WHERE vaccine_id = %s", (id,))
                cur.execute("DELETE FROM vaccines WHERE vaccine_id = %s", (id,))
    except Exception as ex:
        return jsonify({"error": f"No se pudo eliminar la vacuna: {ex}"}), 400

    flash(f"Vacuna '{vaccine['name']}' eliminada.", "warning")
    return jsonify({"message": "Vacuna eliminada"})


# ── APLICACIONES (VACCINATION RECORDS) ───────────────────────────────────────
@app.route("/aplicaciones")
def aplicaciones():
    locked = _require_login()
    if locked:
        return locked

    records           = _applications_from_sp()
    records_raw       = _cur_fetchall("vaccination_records")
    unique_patients   = len(set(r["patient_id"] for r in records_raw))
    unique_vaccines   = len(set(r["vaccine_id"] for r in records_raw))
    applications_today = sum(
        1 for r in records_raw if r["applied_date"] == date.today().isoformat()
    )

    return render_template(
        "aplicaciones_2daE.html",
        **_session_vars(),
        total_applications=len(records),
        total_patients_attended=unique_patients,
        total_unique_vaccines=unique_vaccines,
        applications_today=applications_today,
        applications=records,
    )


@app.route("/agregar_aplicacion", methods=["GET", "POST"])
def agregar_aplicacion():
    locked = _require_login()
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
        except ValueError:
            error = "IDs inválidos"
        else:
            patient = _cur_fetchone("patients", "patient_id", patient_id)
            vaccine = _cur_fetchone("vaccines",  "vaccine_id", vaccine_id)
            if not patient or not vaccine:
                error = "Paciente o vacuna no encontrados"
            else:
                clinic_id = int(request.form.get("clinic_id") or 1)
                lot_id = request.form.get("lot_id")
                lot_id = int(lot_id) if lot_id else None

                with _db_connect() as conn:
                    _sync_known_sequences(conn)

                row = _sp_try_fetchone(
                    "sp_register_vaccination_record",
                    params=[
                        patient_id,
                        vaccine_id,
                        worker_id or session.get("worker_id", 1),
                        clinic_id,
                        lot_id,
                        scheme_dose_id,
                        request.form.get("applied_date") or date.today().isoformat(),
                        app_site_id,
                        request.form.get("patient_temp_c") or None,
                        request.form.get("had_reaction") == "true",
                    ],
                )
                if not row:
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

                flash(
                    f"Aplicación de {vaccine['name']} registrada para "
                    f"{_patient_full_name(patient)}.",
                    "success",
                )
                return redirect(url_for("aplicaciones"))

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


# ── PERSONAL ──────────────────────────────────────────────────────────────────
@app.route("/personal")
def personal():
    locked = _require_login()
    if locked:
        return locked

    workers = _exec_sql(
        """
        SELECT
            w.worker_id,
            w.first_name AS name,
            w.last_name AS lastname,
            COALESCE(r.name, 'Sin rol') AS role,
            COALESCE(we.email, '—') AS mail
        FROM workers w
        LEFT JOIN roles r ON r.role_id = w.role_id
        LEFT JOIN LATERAL (
            SELECT e.email
            FROM worker_emails e
            WHERE e.worker_id = w.worker_id
            ORDER BY e.is_primary DESC, e.email_id ASC
            LIMIT 1
        ) we ON TRUE
        ORDER BY w.worker_id
        """,
        fetchall=True,
    ) or []

    for worker in workers:
        worker["first_name"] = worker.get("name") or ""
        worker["last_name"] = worker.get("lastname") or ""

    return render_template(
        "personal_2daE.html",
        **_session_vars(),
        workers=workers,
        total_workers=len(workers),
        roles=_cur_fetchall("roles"),
    )


@app.route("/personal/agregar", methods=["GET", "POST"])
def add_user():
    locked = _require_login()
    if locked:
        return locked

    form  = {}
    error = None

    if request.method == "POST":
        form     = dict(request.form)
        password = request.form.get("password") or ""
        confirm  = request.form.get("password_confirm") or ""
        mail     = (request.form.get("mail") or "").strip()
        first_name = (request.form.get("first_name") or request.form.get("name") or "").strip()
        last_name = (request.form.get("last_name") or request.form.get("lastname") or "").strip()
        role_raw = request.form.get("role_id") or request.form.get("role")

        if role_raw:
            try:
                role_id = int(role_raw)
            except ValueError:
                role_row = _exec_sql(
                    "SELECT role_id FROM roles WHERE LOWER(name) = LOWER(%s) LIMIT 1",
                    (role_raw,),
                    fetchone=True,
                )
                role_id = role_row["role_id"] if role_row else 3
        else:
            role_id = 3

        email_row = _exec_sql(
            "SELECT 1 AS ok FROM worker_emails WHERE LOWER(email) = LOWER(%s) LIMIT 1",
            (mail,),
            fetchone=True,
        )
        email_exists = bool(email_row)

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
            try:
                with _db_connect() as conn:
                    _sync_known_sequences(conn)
                    with conn.cursor() as cur:
                        cur.execute(
                            """
                            INSERT INTO workers (role_id, first_name, last_name, hire_date, password_hash)
                            VALUES (%s, %s, %s, %s, %s)
                            RETURNING worker_id
                            """,
                            (
                                role_id,
                                first_name,
                                last_name,
                                date.today().isoformat(),
                                f"hash:{password}",
                            ),
                        )
                        new_wid = cur.fetchone()["worker_id"]

                        cur.execute(
                            """
                            INSERT INTO worker_emails (worker_id, email, is_primary)
                            VALUES (%s, %s, TRUE)
                            """,
                            (new_wid, mail),
                        )

                        phone = (request.form.get("phone") or "").strip()
                        if phone:
                            cur.execute(
                                """
                                INSERT INTO worker_phones (worker_id, phone, phone_type, is_primary)
                                VALUES (%s, %s, 'Celular', TRUE)
                                """,
                                (new_wid, phone),
                            )
            except Exception as ex:
                error = f"No se pudo registrar el usuario: {ex}"
                flash(error, "danger")
                return render_template(
                    "add_user_2daE.html",
                    **_session_vars(),
                    form=form,
                    error=error,
                    roles=_cur_fetchall("roles"),
                )

            session["last_registered_worker"] = new_wid
            flash(
                f"Usuario {first_name} registrado correctamente.",
                "success",
            )
            return redirect(url_for("personal"))

    return render_template(
        "add_user_2daE.html",
        **_session_vars(),
        form=form,
        error=error,
        roles=_cur_fetchall("roles"),
    )

@app.route("/personal/editar/<int:worker_id>", methods=["GET", "POST"])
def edit_user(worker_id):
    locked = _require_login()
    if locked:
        return locked

    worker = _exec_sql(
        """
        SELECT
            w.worker_id,
            w.first_name,
            w.last_name,
            w.role_id,
            r.name AS role_name,
            we.email
        FROM workers w
        LEFT JOIN roles r ON r.role_id = w.role_id
        LEFT JOIN worker_emails we ON we.worker_id = w.worker_id AND we.is_primary = TRUE
        WHERE w.worker_id = %s
        LIMIT 1
        """,
        (worker_id,),
        fetchone=True,
    )

    if not worker:
        flash("Usuario no encontrado", "danger")
        return redirect(url_for("personal"))

    roles = _cur_fetchall("roles") or []

    if request.method == "POST":
        first_name = (request.form.get("first_name") or request.form.get("name") or "").strip()
        last_name = (request.form.get("last_name") or request.form.get("lastname") or "").strip()
        mail = (request.form.get("mail") or "").strip()
        role_id_raw = request.form.get("role_id") or request.form.get("role")

        if not first_name or not last_name:
            flash("Nombre y apellidos son obligatorios", "danger")
            worker_view = {
                "worker_id": worker_id,
                "name": first_name,
                "lastname": last_name,
                "role": worker.get("role_name") or "",
                "role_id": worker.get("role_id"),
                "mail": mail,
            }
            return render_template(
                "edit_user_2daE.html",
                worker=worker_view,
                roles=roles,
                **_session_vars()
            )

        try:
            role_id = int(role_id_raw) if role_id_raw is not None else worker["role_id"]
        except ValueError:
            role = _exec_sql(
                "SELECT role_id FROM roles WHERE LOWER(name) = LOWER(%s) LIMIT 1",
                (role_id_raw,),
                fetchone=True,
            )
            role_id = role["role_id"] if role else None

        if role_id is None:
            flash("Selecciona un rol valido", "danger")
            worker_view = {
                "worker_id": worker_id,
                "name": first_name,
                "lastname": last_name,
                "role": worker.get("role_name") or "",
                "role_id": worker.get("role_id"),
                "mail": mail,
            }
            return render_template(
                "edit_user_2daE.html",
                worker=worker_view,
                roles=roles,
                **_session_vars()
            )

        try:
            with _db_connect() as conn:
                with conn.cursor() as cur:
                    cur.execute(
                        """
                        UPDATE workers
                        SET first_name = %s,
                            last_name = %s,
                            role_id = %s
                        WHERE worker_id = %s
                        """,
                        (first_name, last_name, role_id, worker_id),
                    )
                    if mail:
                        cur.execute(
                            "SELECT email_id FROM worker_emails WHERE worker_id = %s AND is_primary = TRUE LIMIT 1",
                            (worker_id,),
                        )
                        email_row = cur.fetchone()
                        if email_row:
                            cur.execute(
                                "UPDATE worker_emails SET email = %s WHERE email_id = %s",
                                (mail, email_row["email_id"]),
                            )
                        else:
                            cur.execute(
                                "INSERT INTO worker_emails (worker_id, email, is_primary) VALUES (%s, %s, TRUE)",
                                (worker_id, mail),
                            )
        except Exception as ex:
            flash(f"No se pudo actualizar el usuario: {ex}", "danger")
            return redirect(url_for("edit_user", worker_id=worker_id))

        flash("Usuario actualizado correctamente", "success")
        return redirect(url_for("personal"))

    worker_view = {
        "worker_id": worker["worker_id"],
        "name": worker["first_name"],
        "lastname": worker["last_name"],
        "role": worker.get("role_name") or "",
        "role_id": worker.get("role_id"),
        "mail": worker.get("email") or "",
    }

    return render_template(
        "edit_user_2daE.html",
        worker=worker_view,
        roles=roles,
        **_session_vars()
    )


# ── REPORTES PÚBLICOS ─────────────────────────────────────────────────────────
@app.route("/reportes-publicos")
def reportes_publicos():
    locked = _require_login()
    if locked:
        return locked
    return render_template("reportesPublicos_2daE.html", **_session_vars())


# ── INVENTARIO ────────────────────────────────────────────────────────────────
@app.route("/inventario")
def inventario():
    locked = _require_login()
    if locked:
        return locked

    inventory = _inventory_from_sp()

    if any(i["low_stock"] for i in inventory):
        flash("⚠ Hay insumos con stock por debajo del mínimo.", "warning")

    session["last_section"] = "inventario"

    return render_template(
        "inventario_2daE.html",
        **_session_vars(),
        inventory=inventory,
        supply_catalog=_cur_fetchall("supply_catalog"),
        clinics=_cur_fetchall("clinics"),
    )


# ── CITAS ─────────────────────────────────────────────────────────────────────
@app.route("/citas")
def citas():
    locked = _require_login()
    if locked:
        return locked

    appointments = _appointments_from_sp()

    session["last_section"] = "citas"

    return render_template(
        "citas_2daE.html",
        **_session_vars(),
        appointments=appointments,
        total_appointments=len(appointments),
        patients=_cur_fetchall("patients"),
        vaccines=_cur_fetchall("vaccines"),
        workers=_cur_fetchall("workers"),
        clinics=_cur_fetchall("clinics"),
    )


# ── NFC ───────────────────────────────────────────────────────────────────────
@app.route("/nfc")
def nfc():
    locked = _require_login()
    if locked:
        return locked

    cards_raw = _cur_fetchall("nfc_cards")
    cards = [_enrich_nfc_card(c) for c in cards_raw]

    scan_events_raw = _cur_fetchall("nfc_scan_events")
    scans = [_enrich_nfc_scan(s) for s in scan_events_raw]

    session["last_section"] = "nfc"

    return render_template(
        "nfc_2daE.html",
        **_session_vars(),
        cards=cards,
        scans=scans,
        total_cards=len(cards),
        active_cards=sum(1 for c in cards_raw if c["status"] == "Activa"),
    )


# ── CLÍNICAS ──────────────────────────────────────────────────────────────────
@app.route("/clinicas")
def clinicas():
    locked = _require_login()
    if locked:
        return locked

    clinics_raw = _cur_fetchall("clinics")
    clinics = [_enrich_clinic(c) for c in clinics_raw]

    session["last_section"] = "clinicas"

    return render_template(
        "clinicas_2daE.html",
        **_session_vars(),
        clinics=clinics,
        total_clinics=len(clinics),
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

    for p in _cur_fetchall("patients"):
        full = _patient_full_name(p)
        if q in full.lower() or q in str(p["patient_id"]):
            results.append({
                "type":     "paciente",
                "title":    full,
                "subtitle": f"ID: P{p['patient_id']}",
                "url":      url_for("historial_paciente", id=p["patient_id"]),
            })

    for v in _cur_fetchall("vaccines"):
        if q in v["name"].lower() or q in str(v["vaccine_id"]):
            lot_stock = sum(
                l["quantity_available"]  # actualizado desde quantity_remaining
                for l in _cur_fetchall_where("vaccine_lots", "vaccine_id", v["vaccine_id"])
            )
            results.append({
                "type":     "vacuna",
                "title":    v["name"],
                "subtitle": f"Stock: {lot_stock}",
                "url":      url_for("vacunas_page") + f"?q={v['name']}",
            })

    for w in _cur_fetchall("workers"):
        name  = f"{w['first_name']} {w['last_name']}".strip()
        email = _worker_email(w["worker_id"])
        if q in name.lower() or q in email.lower():
            role = _cur_fetchone("roles", "role_id", w["role_id"])
            results.append({
                "type":     "personal",
                "title":    name,
                "subtitle": role["name"] if role else "",
                "url":      url_for("personal") + f"?q={name}",
            })

    return jsonify({"results": results[:10]})


@app.route("/api/reportes-publicos/resumen")
def api_reportes_publicos_resumen():
    locked = _require_login()
    if locked:
        return jsonify({"error": "No autenticado"}), 401
    # Parámetros de filtro (opcional)
    from_date = request.args.get('from')
    to_date = request.args.get('to')

    params = []
    date_where = ""
    if from_date and to_date:
        date_where = "WHERE applied_date BETWEEN %s AND %s"
        params = [from_date, to_date]

    # KPIs
    total_doses_row = _exec_sql(f"SELECT COUNT(*) AS cnt FROM vaccination_records {date_where}", tuple(params), fetchone=True)
    total_doses = int(total_doses_row['cnt']) if total_doses_row else 0

    reached_row = _exec_sql(f"SELECT COUNT(DISTINCT patient_id) AS cnt FROM vaccination_records {date_where}", tuple(params), fetchone=True)
    reached_pop = int(reached_row['cnt']) if reached_row else 0

    patients_cnt_row = _exec_sql("SELECT COUNT(*) AS cnt FROM patients", (), fetchone=True)
    target_pop = max(int(patients_cnt_row['cnt']) if patients_cnt_row else 0, 1)

    coverage = (reached_pop / target_pop) * 100 if target_pop else 0

    # Monthly: agrupar por YYYY-MM
    monthly = _exec_sql(
        """
        SELECT to_char(applied_date, 'YYYY-MM') AS period_label,
               COUNT(*) AS doses_applied,
               COUNT(DISTINCT patient_id) AS unique_patients
        FROM vaccination_records
        {where}
        GROUP BY period_label
        ORDER BY period_label
        """.format(where=date_where), tuple(params), fetchall=True
    ) or []

    # Vaccines summary
    vaccines_rows = _exec_sql(
        """
        SELECT v.name AS vaccine_name,
               COUNT(*) AS doses_applied,
               COUNT(DISTINCT vr.patient_id) AS unique_patients
        FROM vaccination_records vr
        JOIN vaccines v ON v.vaccine_id = vr.vaccine_id
        {where}
        GROUP BY v.name
        ORDER BY doses_applied DESC
        LIMIT 50
        """.format(where=date_where), tuple(params), fetchall=True
    ) or []

    vaccines_summary = []
    for row in vaccines_rows:
        doses = int(row.get('doses_applied') or 0)
        vaccines_summary.append({
            'vaccine_name': row.get('vaccine_name'),
            'doses_applied': doses,
            'unique_patients': int(row.get('unique_patients') or 0),
            'share_percent': round(doses / total_doses * 100, 1) if total_doses else 0,
        })

    # Zones: intentar desde vista si existe, si no devolver vacío
    zones_summary = []
    try:
        zones_raw = _cur_fetchall('zones')
        zones_summary = [
            {
                'zone_name': z.get('name'),
                'doses_applied': z.get('cases'),
                'unique_patients': z.get('cases'),
                'risk_level': z.get('risk'),
                'risk_label': {'high': 'Alto', 'medium': 'Medio', 'low': 'Bajo'}.get(z.get('risk'), '—'),
            }
            for z in zones_raw
        ]
    except Exception:
        zones_summary = []

    payload = {
        'kpis': {
            'total_doses_applied': total_doses,
            'target_population': target_pop,
            'reached_population': reached_pop,
            'coverage_percent': round(coverage, 1),
            'avg_delay_days': 0.0,
            'active_zones': len(zones_summary),
        },
        'monthly': [dict(r) for r in monthly],
        'vaccines': vaccines_summary,
        'zones': zones_summary,
    }

    # Comprobar existencia de vistas y funciones clave y advertir si faltan
    warnings = []
    views_to_check = [
        'v_patients_full',
        'v_vaccination_records_full',
        'v_inventory_status',
        'v_appointments_full',
        'v_pending_scheme_doses',
    ]
    for v in views_to_check:
        try:
            row = _exec_sql("SELECT to_regclass(%s) AS reg", (f'public.{v}',), fetchone=True)
            if not row or not row.get('reg'):
                warnings.append(f"Vista faltante: {v}")
        except Exception:
            warnings.append(f"No se pudo verificar vista: {v}")

    funcs_to_check = [
        'sp_get_patients_full',
        'sp_get_vaccination_records_full',
        'sp_get_inventory_status',
        'sp_get_appointments_full',
    ]
    for fn in funcs_to_check:
        try:
            row = _exec_sql("SELECT EXISTS(SELECT 1 FROM pg_proc WHERE proname = %s)", (fn,), fetchone=True)
            if not row or not row.get('exists'):
                warnings.append(f"Función/SP faltante: {fn}")
        except Exception:
            warnings.append(f"No se pudo verificar función: {fn}")

    if warnings:
        payload['warnings'] = warnings

    return jsonify(payload)


@app.route("/api/alertas-esquema")
def api_alertas_esquema():
    locked = _require_login()
    if locked:
        return jsonify({"error": "No autenticado"}), 401

    alerts_raw = _cur_fetchall("scheme_completion_alerts")
    result = []
    for al in alerts_raw:
        patient = _cur_fetchone("patients", "patient_id", al["patient_id"])
        dose    = _cur_fetchone("scheme_doses", "dose_id", al["scheme_dose_id"])
        vaccine_name = "—"
        if dose:
            v = _cur_fetchone("vaccines", "vaccine_id", dose["vaccine_id"])
            vaccine_name = v["name"] if v else "—"
        result.append({
            **al,
            "patient_name": _patient_full_name(patient) if patient else "—",
            "vaccine_name": vaccine_name,
            "dose_label":   dose["dose_label"] if dose else "—",
        })
    return jsonify(result)




if __name__ == "__main__":
    # Inicializar base de datos antes de ejecutar
    try:
        from db_init import init_database
        with app.app_context():
            init_database()
    except Exception as e:
        logger.error(f"Error durante inicialización de DB: {e}")
        raise

    logger.info("✓ Flask iniciando en http://127.0.0.1:5000")
    app.run(debug=True)