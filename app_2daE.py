import math
from datetime import date, datetime
from flask import Flask, flash, jsonify, redirect, render_template, request, session, url_for, g, has_request_context
import bcrypt
import logging

from config import DATABASE_URL, DB_ENGINE, SECRET_KEY
from db import OperationalError, get_db_connection, quote_identifier

app = Flask(__name__)

app.config["DATABASE_URL"] = DATABASE_URL
app.config["DB_ENGINE"] = DB_ENGINE
app.secret_key = SECRET_KEY

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
# HELPERS — capa de acceso DB
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
    """Devuelve todas las filas de una tabla."""
    physical = _safe_table_name(table)
    cache = _get_req_cache()
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
    """Devuelve una fila por clave primaria."""
    physical = _safe_table_name(table)
    cache = _get_req_cache()
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
    """Devuelve filas filtradas por un campo."""
    physical = _safe_table_name(table)
    cache = _get_req_cache()
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


def _sp_fetchall(function_name, params=None):
    """Llama a un SP/función y devuelve todas las filas."""
    conn, should_close = _get_conn()
    try:
        with conn.cursor() as cur:
            placeholders = ", ".join(["%s"] * len(params or []))
            if app.config["DB_ENGINE"] == "postgres":
                query = f"SELECT * FROM {quote_identifier(function_name)}({placeholders})"
            else:
                query = f"CALL {quote_identifier(function_name)}({placeholders})"
            cur.execute(query, tuple(params or []))
            rows = cur.fetchall()
            conn.commit()
            return rows
    except Exception:
        _safe_rollback(conn)
        raise
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()


def _sp_try_fetchall(function_name, params=None, fallback=None):
    """Llama a un SP y devuelve todas las filas; retorna fallback si falla."""
    try:
        return _sp_fetchall(function_name, params=params)
    except Exception:
        return fallback if fallback is not None else []


def _sp_fetchone(function_name, params=None):
    """Llama a un SP/función y devuelve la primera fila."""
    conn, should_close = _get_conn()
    try:
        with conn.cursor() as cur:
            placeholders = ", ".join(["%s"] * len(params or []))
            if app.config["DB_ENGINE"] == "postgres":
                query = f"SELECT * FROM {quote_identifier(function_name)}({placeholders})"
            else:
                query = f"CALL {quote_identifier(function_name)}({placeholders})"
            cur.execute(query, tuple(params or []))
            row = cur.fetchone()
            conn.commit()
            return row
    except Exception:
        _safe_rollback(conn)
        raise
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

def _sp_try_fetchone(function_name, params=None, fallback=None):
    """Llama a un SP y devuelve la primera fila; retorna fallback si falla."""
    try:
        return _sp_fetchone(function_name, params=params)
    except Exception:
        return fallback


# =============================================================================
# HELPERS — sesión, formateo, nombres
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


def _worker_full_name(worker_id):
    w = _cur_fetchone("workers", "worker_id", worker_id)
    if not w:
        return "Personal demo"
    return f"{w['first_name']} {w['last_name']}".strip()


def _worker_email(worker_id):
    emails = _cur_fetchall_where("worker_emails", "worker_id", worker_id)
    primary = next((e for e in emails if e.get("is_primary")), None)
    return (primary or emails[0])["email"] if emails else "—"


def _guardian_primary_phone(guardian_id):
    phones = _cur_fetchall_where("guardian_phones", "guardian_id", guardian_id)
    primary = next((p for p in phones if p.get("is_primary")), None)
    return (primary or phones[0])["phone"] if phones else "—"


def _patient_primary_guardian(patient_id):
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


def _distance_meters(lat1, lon1, lat2, lon2):
    r = 6371000.0
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi    = math.radians(lat2 - lat1)
    dlambda = math.radians(lon2 - lon1)
    a = math.sin(dphi / 2) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))


# =============================================================================
# HELPERS — enriquecimiento de entidades
# =============================================================================

def _enrich_patient(p):
    item = dict(p)
    item["full_name"]  = _patient_full_name(p)
    item["age"]        = _age_years(p["birth_date"])
    item["blood_type"] = _blood_type_str(p.get("blood_type_id"))

    g_id = _patient_primary_guardian(p["patient_id"])
    item["guardian"] = _guardian_full_name(g_id) if g_id else "Sin tutor"
    item["contact"]  = _guardian_primary_phone(g_id) if g_id else "—"

    pa_rows = _cur_fetchall_where("patient_allergies", "patient_id", p["patient_id"])
    allergy_names = []
    for pa in pa_rows:
        allergy = _cur_fetchone("allergies", "allergy_id", pa["allergy_id"])
        if allergy:
            allergy_names.append(allergy["name"])
    item["allergies"] = ", ".join(allergy_names) or "Ninguna"
    item["risk"] = "N/A"
    return item


def _enrich_record(r):
    item = dict(r)
    patient = _cur_fetchone("patients", "patient_id", r["patient_id"])
    item["patient_name"] = _patient_full_name(patient) if patient else "—"
    item["name"]         = _vaccine_name(r["vaccine_id"])
    item["doctor"]       = _worker_full_name(r["worker_id"])
    item["date"]         = r["applied_date"]
    item["id"]           = r["record_id"]

    dose = _cur_fetchone("scheme_doses", "dose_id", r.get("scheme_dose_id"))
    item["dose"]      = dose["dose_label"] if dose else "—"
    item["next_date"] = None

    site = _cur_fetchone("application_sites", "application_site_id", r.get("application_site_id"))
    item["application_site"] = site["application_site"] if site else "—"
    item["had_reaction"]     = r.get("had_reaction", False)
    item["patient_temp_c"]   = r.get("patient_temp_c")
    item["notes"]            = "Con reacción" if r.get("had_reaction") else "Sin reacciones"
    return item


def _enrich_appointment(ap):
    item    = dict(ap)
    patient = _cur_fetchone("patients",    "patient_id", ap["patient_id"])
    worker  = _cur_fetchone("workers",     "worker_id",  ap["worker_id"])
    clinic  = _cur_fetchone("clinics",     "clinic_id",  ap["clinic_id"])
    area    = _cur_fetchone("clinic_areas","area_id",    ap["area_id"]) if ap.get("area_id") else None

    item["patient_name"] = _patient_full_name(patient) if patient else "—"
    item["worker_name"]  = f"{worker['first_name']} {worker['last_name']}" if worker else "—"
    item["clinic_name"]  = clinic["name"] if clinic else "—"
    item["area_name"]    = area["name"]   if area   else "—"
    item["vaccine_name"] = ap.get("reason") or "—"
    item["status"]       = ap.get("appointment_status", "—")
    item["notes"]        = ap.get("appointment_notes", "")
    return item


def _enrich_inventory_item(inv):
    item   = dict(inv)
    supply = _cur_fetchone("supply_catalog", "supply_id", inv["supply_id"])
    clinic = _cur_fetchone("clinics",        "clinic_id", inv["clinic_id"])

    item["supply_name"]     = supply["name"]     if supply else "—"
    item["supply_unit"]     = supply["unit"]     if supply else "—"
    item["supply_category"] = supply["category"] if supply else "—"
    item["clinic_name"]     = clinic["name"]     if clinic else "—"
    item["low_stock"]       = inv["quantity"] < inv["min_stock"]
    return item


def _enrich_nfc_card(c):
    item    = dict(c)
    patient = _cur_fetchone("patients", "patient_id", c["patient_id"])
    item["patient_name"]    = _patient_full_name(patient) if patient else "—"
    item["notes"]           = c.get("nfc_card_notes")
    item["issued_date"]     = _temporal_text(c.get("issued_date"))
    item["last_scanned_at"] = _temporal_text(c.get("last_scanned_at"))
    return item


def _enrich_nfc_scan(s):
    item    = dict(s)
    card    = _cur_fetchone("nfc_cards", "nfc_card_id", s["nfc_card_id"])
    patient = _cur_fetchone("patients",  "patient_id",  card["patient_id"]) if card else None
    item["worker_name"]  = _worker_full_name(s["scanned_by"]) if s.get("scanned_by") else "—"
    item["patient_name"] = _patient_full_name(patient) if patient else "—"
    item["result"]       = s.get("nfc_scan_result")
    item["scanned_at"]   = _temporal_text(s.get("scanned_at"))
    return item


def _enrich_area(a):
    item  = dict(a)
    atype = _cur_fetchone("area_types", "area_type_id", a["area_type_id"])
    item["area_type"] = atype["area_type"] if atype else "—"
    return item


def _enrich_clinic(c):
    item    = dict(c)
    address = _cur_fetchone("addresses", "address_id", c["address_id"])
    if address:
        nbhd = _cur_fetchone("neighborhoods", "neighborhood_id", address["neighborhood_id"])
        item["address_str"] = f"{address['street']} {address['ext_number'] or ''}, {nbhd['name'] if nbhd else ''}".strip(", ")
    else:
        item["address_str"] = "—"

    areas_raw = _cur_fetchall_where("clinic_areas", "clinic_id", c["clinic_id"])
    item["areas"] = [_enrich_area(a) for a in areas_raw]
    return item


# =============================================================================
# HELPERS — datos compuestos desde SPs
# =============================================================================

def _patients_from_sp():
    raw = _sp_try_fetchall("sp_get_patients_full")
    out = []
    for row in raw:
        item = dict(row)
        item["full_name"]  = item.get("full_name")  or _patient_full_name(item)
        item["guardian"]   = item.get("guardian")   or item.get("guardian_name") or "Sin tutor"
        item["contact"]    = item.get("contact")    or item.get("guardian_phone") or "—"
        item["blood_type"] = item.get("blood_type") or "—"
        item["allergies"]  = item.get("allergies")  or "Ninguna"
        item["risk"]       = item.get("risk")        or "N/A"
        out.append(item)
    return out


def _applications_from_sp():
    raw = _sp_try_fetchall("sp_get_vaccination_records_full")
    return [
        {
            "id":               row.get("record_id"),
            "name":             row.get("vaccine_name"),
            "vaccine_id":       row.get("vaccine_id"),
            "patient_name":     row.get("patient_name"),
            "doctor":           row.get("worker_name"),
            "dose":             row.get("dose_label") or "—",
            "date":             _temporal_text(row.get("applied_date")),
            "next_date":        None,
            "application_site": row.get("application_site") or "—",
            "had_reaction":     row.get("had_reaction", False),
            "patient_temp_c":   row.get("patient_temp_c"),
            "notes":            "Con reacción" if row.get("had_reaction") else "Sin reacciones",
        }
        for row in raw
    ]


def _inventory_from_sp():
    raw = _sp_try_fetchall("sp_get_inventory_status")
    if raw:
        return raw
    return [_enrich_inventory_item(i) for i in _cur_fetchall("clinic_inventory")]


def _appointments_from_sp():
    raw = _sp_try_fetchall("sp_get_appointments_full")
    out = []
    for row in raw:
        item = dict(row)
        item["status"]       = row.get("appointment_status") or "—"
        item["vaccine_name"] = row.get("reason") or "—"
        item["scheduled_at"] = _temporal_text(row.get("scheduled_at"))
        out.append(item)
    return out


def _patient_records_full(patient_id):
    rows = _sp_try_fetchall("sp_get_vaccination_records_full")
    return [
        {**dict(r), "date": _temporal_text(r.get("applied_date"))}
        for r in rows
        if r.get("patient_id") == patient_id
    ]


def _build_next_vaccines(patient_id):
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


def _authenticate_user(login_value, password):
    """
    Autenticación 100% en backend (sin SP, sin lógica en DB)
    - login_value: username o email
    - password: texto plano
    """
    login_value = (login_value or "").strip()
    password = password or ""

    if not login_value or not password:
        return None

    try:
        conn = get_db_connection()
        cur = conn.cursor()

        cur.execute("""
            SELECT 
                u.user_id,
                u.password_hash,
                u.is_active,
                w.worker_id,
                w.first_name,
                w.last_name,
                r.name
            FROM users u
            JOIN workers w ON u.worker_id = w.worker_id
            LEFT JOIN roles r ON w.role_id = r.role_id
            LEFT JOIN worker_emails we ON w.worker_id = we.worker_id
            WHERE u.username = %s OR we.email = %s
            LIMIT 1;
        """, (login_value, login_value))

        row = cur.fetchone()

        if not row:
            return None

        if not row["is_active"]:
            return None

        stored_hash = row["password_hash"]

        if not stored_hash or not bcrypt.checkpw(
            password.encode("utf-8"),
            stored_hash.encode("utf-8")
        ):
            return None

        return {
            "worker_id": row["worker_id"],
            "name":      (row.get("first_name") or "").strip(),
            "lastname":  (row.get("last_name") or "").strip(),
            "role":      row.get("name") or "Administrador",
        }

    except Exception as e:
        logger.warning("Error en autenticación: %s", e)
        return None
    finally:
        try:
            cur.close()
            conn.close()
        except:
            pass

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
        return redirect(url_for("dashboard"))

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

    return render_template("pages/login_2daE.html", error=error)


@app.route("/logout")
def logout():
    nombre = session.get("user_name", "")
    session.clear()
    flash(f"Sesión de {nombre} cerrada correctamente.", "info")
    return redirect(url_for("pagina_inicio"))


# =============================================================================
# RUTAS — dashboard
# =============================================================================

@app.route("/dashboard")
def dashboard():
    locked = _require_login()
    if locked:
        return locked

    try:
        today_dt       = date.today()
        metrics        = dict(_sp_try_fetchone("sp_dashboard_metrics") or {})
        delayed_data   = _sp_try_fetchall("sp_delayed_patients", params=[30])
        low_stock_data = _sp_try_fetchall("sp_low_stock_items")

        context = {
            **_session_vars(),
            "today":                today_dt.strftime("%d/%m/%Y"),
            "total_patients":       metrics.get("total_patients", 0),
            "coverage_pct":         metrics.get("coverage_percentage", 0),
            "pending_appointments": metrics.get("pending_appointments", 0),
            "low_stock_count":      len(low_stock_data),
            "delayed_patients":     len(delayed_data),
            "pending_alerts":       metrics.get("pending_alerts", 0),
            "applications_today":   0,
            "doses_this_week":      0,
            "doses_this_month":     0,
            "coverage_trend":       0,
            "patients_critical":    0,
            "expired_doses":        0,
            "new_patients_month":   0,
            "expiring_lots_week":   0,
            "top_patients":         [],
            "coverage_by_age":      [],
            "doses_by_month":       [],
            "monthly_trend":        0,
            "delay_by_vaccine":     [],
        }

        session["last_visit"] = today_dt.isoformat()
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
    locked = _require_login()
    if locked:
        return locked
 
    try:
        conn, should_close = _get_conn()
        old_autocommit = conn.autocommit
        try:
            conn.autocommit = False
            with conn.cursor() as cur:
                cur.execute("CALL sp_get_patients(%s)", ("p_results",))
                cur.execute('FETCH ALL FROM "p_results"')
                patients = [dict(r) for r in cur.fetchall()]
            conn.commit()
        except Exception as sp_err:
            import traceback
            logger.error(f"[SP ERROR] sp_get_patients falló:\n{traceback.format_exc()}")
            _safe_rollback(conn)
            patients = []
        finally:
            conn.autocommit = old_autocommit
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

    gender_raw  = (payload.get("gender") or "").strip().lower()
    gender_map  = {"masculino": "M", "m": "M", "femenino": "F", "f": "F", "otro": "O", "o": "O"}
    gender_code = gender_map.get(gender_raw, "O")

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

    flash(f"Paciente {first_name} {last_name} registrado correctamente.", "success")
    return jsonify({"message": "Paciente registrado", "patient_id": row.get("patient_id")})


@app.route("/delete_patient/<int:id>", methods=["POST"])
def delete_patient(id):
    locked = _require_login()
    if locked:
        return jsonify({"error": "No autenticado"}), 401

    try:
        patient = _cur_fetchone("patients", "patient_id", id)
        if not patient:
            return jsonify({"error": "Paciente no encontrado"}), 404

        nombre = f"{patient['first_name']} {patient['last_name']}"
        _sp_fetchone("sp_delete_patient", params=[id])

        flash(f"Paciente {nombre} eliminado.", "warning")
        return jsonify({"message": "Paciente eliminado"})
    except Exception as ex:
        logger.error(f"Error en /delete_patient/{id}: {ex}")
        return jsonify({"error": f"No se pudo eliminar el paciente: {ex}"}), 400


# =============================================================================
# RUTAS — historial
# =============================================================================

@app.route("/historial")
def historial():
    locked = _require_login()
    if locked:
        return locked

    try:
        patients    = _patients_from_sp()
        all_records = _applications_from_sp()

        patient       = patients[0] if patients else None
        records       = [r for r in all_records if r.get("patient_id") == patient["patient_id"]] if patient else []
        next_vaccines = _build_next_vaccines(patient["patient_id"]) if patient else []

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
    locked = _require_login()
    if locked:
        return locked

    patients = _patients_from_sp()
    patient  = next((p for p in patients if p.get("patient_id") == id), None)
    if not patient:
        flash("Paciente no encontrado.", "danger")
        return redirect(url_for("historial"))

    session["last_patient_viewed"] = id

    return render_template(
        "pages/historial_2daE.html",
        **_session_vars(),
        patients=patients,
        patient=patient,
        applications=_patient_records_full(id),
        next_vaccines=_build_next_vaccines(id),
    )


# =============================================================================
# RUTAS — esquema paciente / esquema vacunación
# =============================================================================

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
        "pages/esquemaPaciente_2daE.html",
        **_session_vars(),
        patient=patient,
        patient_name=patient["full_name"],
        applications=records,
        next_vaccines=_build_next_vaccines(id),
    )


@app.route("/esquema")
def esquema_vacunacion():
    locked = _require_login()
    if locked:
        return locked

    scheme_data = []
    for dose in _cur_fetchall("scheme_doses"):
        vaccine = _cur_fetchone("vaccines", "vaccine_id", dose["vaccine_id"])
        scheme_data.append((dose, vaccine or {}))

    return render_template(
        "pages/esquemaVacunacion_2daE.html",
        **_session_vars(),
        esquema=scheme_data,
    )


# =============================================================================
# RUTAS — vacunas
# =============================================================================

@app.route("/vacunas")
def vacunas_page():
    locked = _require_login()
    if locked:
        return locked

    vaccines = _cur_fetchall("vaccines")
    lots     = _cur_fetchall("vaccine_lots")

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
        "pages/vacunas_2daE.html",
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

    flash(f"Vacuna '{name}' registrada.", "success")
    return jsonify({"message": "Vacuna registrada", "vaccine_id": row.get("vaccine_id")})


@app.route("/delete_vaccine/<int:id>", methods=["POST"])
def delete_vaccine(id):
    locked = _require_login()
    if locked:
        return jsonify({"error": "No autenticado"}), 401

    vaccine = _cur_fetchone("vaccines", "vaccine_id", id)
    if not vaccine:
        return jsonify({"error": "Vacuna no encontrada"}), 404

    try:
        result = _sp_try_fetchone("sp_delete_vaccine", params=[id])
        if result and result.get("error"):
            return jsonify({"error": result["error"]}), 400
    except Exception as ex:
        return jsonify({"error": f"No se pudo eliminar la vacuna: {ex}"}), 400

    flash(f"Vacuna '{vaccine['name']}' eliminada.", "warning")
    return jsonify({"message": "Vacuna eliminada"})


# =============================================================================
# RUTAS — aplicaciones (vaccination records)
# =============================================================================

@app.route("/aplicaciones")
def aplicaciones():
    locked = _require_login()
    if locked:
        return locked

    records     = _applications_from_sp()
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
                lot_id    = request.form.get("lot_id")
                lot_id    = int(lot_id) if lot_id else None

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
                else:
                    flash(
                        f"Aplicación de {vaccine['name']} registrada para {_patient_full_name(patient)}.",
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


# =============================================================================
# RUTAS — personal
# =============================================================================

@app.route("/personal")
def personal():
    locked = _require_login()
    if locked:
        return locked

    workers_raw = _cur_fetchall("workers")
    workers = []
    for w in workers_raw:
        role  = _cur_fetchone("roles", "role_id", w.get("role_id"))
        email = _worker_email(w["worker_id"])
        workers.append({
            **w,
            "first_name": w.get("first_name") or "",
            "last_name":  w.get("last_name")  or "",
            "name":       w.get("first_name") or "",
            "lastname":   w.get("last_name")  or "",
            "role":       role["name"] if role else "Sin rol",
            "mail":       email,
        })

    return render_template(
        "pages/personal_2daE.html",
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
        form       = dict(request.form)
        password   = request.form.get("password") or ""
        confirm    = request.form.get("password_confirm") or ""
        mail       = (request.form.get("mail") or "").strip()
        first_name = (request.form.get("first_name") or request.form.get("name") or "").strip()
        last_name  = (request.form.get("last_name")  or request.form.get("lastname") or "").strip()
        role_raw   = request.form.get("role_id") or request.form.get("role")

        # Resolver role_id sin query embebida
        role_id = 3
        if role_raw:
            try:
                role_id = int(role_raw)
            except ValueError:
                match   = next((r for r in _cur_fetchall("roles") if r["name"].lower() == role_raw.lower()), None)
                role_id = match["role_id"] if match else 3

        # Verificar email duplicado sin query embebida
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
            row = _sp_try_fetchone(
                "sp_register_worker",
                params=[
                    role_id,
                    first_name,
                    last_name,
                    date.today().isoformat(),
                    f"hash:{password}",
                    mail,
                    (request.form.get("phone") or "").strip() or None,
                ],
            )
            if not row:
                error = "No se pudo registrar el usuario"
                flash(error, "danger")
            else:
                session["last_registered_worker"] = row.get("worker_id")
                flash(f"Usuario {first_name} registrado correctamente.", "success")
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
                result = _sp_try_fetchone(
                    "sp_update_worker",
                    params=[worker_id, first_name, last_name, role_id, mail or None],
                )
                if result is None:
                    flash("No se pudo actualizar el usuario", "danger")
                else:
                    flash("Usuario actualizado correctamente", "success")
                    return redirect(url_for("personal"))

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
    locked = _require_login()
    if locked:
        return locked
    return render_template("pages/reportesPublicos_2daE.html", **_session_vars())


@app.route("/inventario")
def inventario():
    locked = _require_login()
    if locked:
        return locked

    inventory = _inventory_from_sp()
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
    locked = _require_login()
    if locked:
        return locked

    session["last_section"] = "citas"
    appointments = _appointments_from_sp()
    return render_template(
        "pages/citas_2daE.html",
        **_session_vars(),
        appointments=appointments,
        total_appointments=len(appointments),
        patients=_cur_fetchall("patients"),
        vaccines=_cur_fetchall("vaccines"),
        workers=_cur_fetchall("workers"),
        clinics=_cur_fetchall("clinics"),
    )


@app.route("/nfc")
def nfc():
    locked = _require_login()
    if locked:
        return locked

    cards_raw       = _cur_fetchall("nfc_cards")
    scan_events_raw = _cur_fetchall("nfc_scan_events")

    session["last_section"] = "nfc"
    return render_template(
        "pages/nfc_2daE.html",
        **_session_vars(),
        cards=[_enrich_nfc_card(c) for c in cards_raw],
        scans=[_enrich_nfc_scan(s) for s in scan_events_raw],
        total_cards=len(cards_raw),
        active_cards=sum(1 for c in cards_raw if c.get("status") == "Activa"),
    )


@app.route("/clinicas")
def clinicas():
    locked = _require_login()
    if locked:
        return locked

    clinics_raw = _cur_fetchall("clinics")
    session["last_section"] = "clinicas"
    return render_template(
        "pages/clinicas_2daE.html",
        **_session_vars(),
        clinics=[_enrich_clinic(c) for c in clinics_raw],
        total_clinics=len(clinics_raw),
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
                l["quantity_available"]
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
            role = _cur_fetchone("roles", "role_id", w.get("role_id"))
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

    from_date = request.args.get("from")
    to_date   = request.args.get("to")

    # Intentar SP dedicado primero
    sp_row = _sp_try_fetchone("sp_reportes_resumen", params=[from_date, to_date])
    if sp_row:
        return jsonify(dict(sp_row))

    # Fallback: calcular en Python usando helpers genéricos
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

    # Agrupar por mes
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

    # Agrupar por vacuna
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
    locked = _require_login()
    if locked:
        return jsonify({"error": "No autenticado"}), 401

    result = []
    for al in _cur_fetchall("scheme_completion_alerts"):
        patient      = _cur_fetchone("patients",    "patient_id", al["patient_id"])
        dose         = _cur_fetchone("scheme_doses", "dose_id",   al["scheme_dose_id"])
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


@app.cli.command("init-db")
def cli_init_database():
    """Inicializa la base de datos (esquema/SQL vía db_init). Usar antes de `flask run` si aplica."""
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