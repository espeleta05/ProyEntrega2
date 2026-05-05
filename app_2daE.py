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
        return {
            "worker_id": row["worker_id"],
            "name":      (row.get("first_name") or "").strip(),
            "lastname":  (row.get("last_name")  or "").strip(),
            "role":      row.get("name") or "Administrador",
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
        conn, should_close = _get_conn()
        old_autocommit = conn.autocommit
        kpis         = {}
        top_patients = []
        chart_rows   = []
        try:
            conn.autocommit = False
            with conn.cursor() as cur:

                # 1. KPIs y alertas
                cur.execute("CALL sp_dashboard_kpis(%s)", ("cur_kpis",))
                cur.execute('FETCH ALL FROM "cur_kpis"')
                kpis = dict(cur.fetchone() or {})

                # 2. Últimos 10 pacientes (reutiliza sp_get_patients con límite)
                cur.execute("CALL sp_get_patients(%s, %s)", (10, "cur_top_patients"))
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
            conn.autocommit = old_autocommit
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
    locked = _require_login()
    if locked:
        return locked

    try:
        conn, should_close = _get_conn()
        old_autocommit = conn.autocommit
        try:
            conn.autocommit = False
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

    conn, should_close = _get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM sp_register_patient(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
                (
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
                ),
            )
            row = cur.fetchone()
        conn.commit()
    except Exception as ex:
        _safe_rollback(conn)
        return jsonify({"error": f"No se pudo registrar el paciente: {ex}"}), 500
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    if not row:
        return jsonify({"error": "No se pudo registrar el paciente en la base de datos"}), 500

    flash(f"Paciente {first_name} {last_name} registrado correctamente.", "success")
    return jsonify({"message": "Paciente registrado", "patient_id": row.get("patient_id")})


@app.route("/delete_patient/<int:id>", methods=["POST"])
def delete_patient(id):
    locked = _require_login()
    if locked:
        return jsonify({"error": "No autenticado"}), 401

    patient = _cur_fetchone("patients", "patient_id", id)
    if not patient:
        return jsonify({"error": "Paciente no encontrado"}), 404

    nombre = f"{patient['first_name']} {patient['last_name']}"
    conn, should_close = _get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM sp_delete_patient(%s)", (id,))
        conn.commit()
    except Exception as ex:
        _safe_rollback(conn)
        logger.error(f"Error en /delete_patient/{id}: {ex}")
        return jsonify({"error": f"No se pudo eliminar el paciente: {ex}"}), 400
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    flash(f"Paciente {nombre} eliminado.", "warning")
    return jsonify({"message": "Paciente eliminado"})


# =============================================================================
# RUTAS — historial
# =============================================================================

@app.route("/historial")
def historial():
    locked = _require_login()
    if locked:
        return locked

    try:
        conn, should_close = _get_conn()
        old_autocommit = conn.autocommit
        try:
            conn.autocommit = False
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
            conn.autocommit = old_autocommit
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
            old_ac2 = conn2.autocommit
            try:
                conn2.autocommit = False
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
                conn2.autocommit = old_ac2
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
    locked = _require_login()
    if locked:
        return locked

    conn, should_close = _get_conn()
    old_autocommit = conn.autocommit
    try:
        conn.autocommit = False
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
        conn.autocommit = old_autocommit
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
    locked = _require_login()
    if locked:
        return locked

    conn, should_close = _get_conn()
    old_autocommit = conn.autocommit
    try:
        conn.autocommit = False
        with conn.cursor() as cur:
            cur.execute("CALL sp_get_esquema_paciente(%s, %s)", (id, "cur_esquema_paciente"))
            cur.execute('FETCH ALL FROM "cur_esquema_paciente"')
            esquema_rows = [dict(r) for r in cur.fetchall()]
        conn.commit()
    except Exception as e:
        _safe_rollback(conn)
        logger.error(f"Error en /esquema_paciente/{id}: {e}")
        flash("Error al cargar el esquema del paciente.", "danger")
        return redirect(url_for("historial"))
    finally:
        conn.autocommit = old_autocommit
        if should_close and not _conn_is_closed(conn):
            conn.close()

    if not esquema_rows:
        flash("Paciente no encontrado o sin esquema.", "danger")
        return redirect(url_for("historial"))

    # Datos del paciente desde la primera fila (todos tienen los mismos)
    first = esquema_rows[0]
    patient = {
        "patient_id": first.get("patient_id"),
        "full_name":  first.get("full_name"),
        "birth_date": first.get("birth_date"),
        "age":        first.get("age_years"),
    }

    # Dosis ya aplicadas → tabla principal del template (applications)
    applications = [
        {
            "name":             r.get("name"),
            "dose":             r.get("dose"),
            "date":             _temporal_text(r.get("date")),
            "doctor":           r.get("doctor"),
            "application_site": r.get("application_site"),
            "had_reaction":     r.get("had_reaction"),
            "next_date":        r.get("next_date"),
            "alerta_retraso":   r.get("alerta_retraso"),
            "estado":           r.get("estado"),
        }
        for r in esquema_rows
        if r.get("estado") == "Aplicada"
    ]

    # Dosis pendientes → sección "Próximas dosis" del template (next_vaccines)
    next_vaccines = [
        {
            "name":           r.get("name"),
            "dose":           r.get("dose"),
            "date":           r.get("edad_ideal_label"),
            "alerta_retraso": r.get("alerta_retraso"),
            "estado":         r.get("estado"),
        }
        for r in esquema_rows
        if r.get("estado") in ("Pendiente", "Pendiente con retraso")
    ]

    return render_template(
        "pages/esquemaPaciente_2daE.html",
        **_session_vars(),
        patient=patient,
        patient_name=patient.get("full_name", ""),
        applications=applications,
        next_vaccines=next_vaccines,
    )


@app.route("/esquema")
def esquema_vacunacion():
    locked = _require_login()
    if locked:
        return locked

    conn, should_close = _get_conn()
    old_autocommit = conn.autocommit
    try:
        conn.autocommit = False
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
        conn.autocommit = old_autocommit
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
    locked = _require_login()
    if locked:
        return locked

    conn, should_close = _get_conn()
    old_autocommit = conn.autocommit
    try:
        conn.autocommit = False
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
        conn.autocommit = old_autocommit
        if should_close and not _conn_is_closed(conn):
            conn.close()

    lots = _cur_fetchall("vaccine_lots")

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

    conn, should_close = _get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT * FROM sp_register_vaccine(%s,%s,%s,%s,%s,%s)",
                (
                    name,
                    payload.get("commercial_name"),
                    payload.get("manufacturer_id"),
                    payload.get("via_id"),
                    payload.get("ideal_age_months"),
                    payload.get("disease_prevented") or payload.get("descripcion") or "No especificado",
                ),
            )
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

    conn, should_close = _get_conn()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM sp_delete_vaccine(%s)", (id,))
            result = cur.fetchone()
        conn.commit()
    except Exception as ex:
        _safe_rollback(conn)
        return jsonify({"error": f"No se pudo eliminar la vacuna: {ex}"}), 400
    finally:
        if should_close and not _conn_is_closed(conn):
            conn.close()

    if result and result.get("error"):
        return jsonify({"error": result["error"]}), 400

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

    conn, should_close = _get_conn()
    old_autocommit = conn.autocommit
    try:
        conn.autocommit = False
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
        conn.autocommit = old_autocommit
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

                conn, should_close = _get_conn()
                try:
                    with conn.cursor() as cur:
                        cur.execute(
                            "SELECT * FROM sp_register_vaccination_record(%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)",
                            (
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
                            ),
                        )
                        row = cur.fetchone()
                    conn.commit()
                except Exception as ex:
                    _safe_rollback(conn)
                    error = f"No se pudo registrar la aplicación: {ex}"
                    row   = None
                finally:
                    if should_close and not _conn_is_closed(conn):
                        conn.close()

                if row:
                    p_name = f"{patient['first_name']} {patient['last_name']}".strip()
                    flash(f"Aplicación de {vaccine['name']} registrada para {p_name}.", "success")
                    return redirect(url_for("aplicaciones"))
                elif not error:
                    error = "No se pudo registrar la aplicación en base de datos"

    return render_template(
        "pages/agregarAplicacion_2daE.html",
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

    conn, should_close = _get_conn()
    old_autocommit = conn.autocommit
    try:
        conn.autocommit = False
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
        conn.autocommit = old_autocommit
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
            try:
                with conn.cursor() as cur:
                    cur.execute(
                        "SELECT * FROM sp_register_worker(%s,%s,%s,%s,%s,%s,%s)",
                        (
                            role_id,
                            first_name,
                            last_name,
                            date.today().isoformat(),
                            f"hash:{password}",
                            mail,
                            (request.form.get("phone") or "").strip() or None,
                        ),
                    )
                    row = cur.fetchone()
                conn.commit()
            except Exception as ex:
                _safe_rollback(conn)
                error = f"No se pudo registrar el usuario: {ex}"
                row   = None
            finally:
                if should_close and not _conn_is_closed(conn):
                    conn.close()

            if row:
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
    locked = _require_login()
    if locked:
        return locked
    return render_template("pages/reportesPublicos_2daE.html", **_session_vars())


@app.route("/inventario")
def inventario():
    locked = _require_login()
    if locked:
        return locked

    conn, should_close = _get_conn()
    old_autocommit = conn.autocommit
    try:
        conn.autocommit = False
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
        conn.autocommit = old_autocommit
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
    locked = _require_login()
    if locked:
        return locked

    conn, should_close = _get_conn()
    old_autocommit = conn.autocommit
    try:
        conn.autocommit = False
        with conn.cursor() as cur:
            cur.execute("CALL sp_get_appointments_full(%s)", ("cur_appointments_full",))
            cur.execute('FETCH ALL FROM "cur_appointments_full"')
            raw_appointments = cur.fetchall()
        conn.commit()
    except Exception as e:
        _safe_rollback(conn)
        logger.error(f"Error en /citas: {e}")
        raw_appointments = []
    finally:
        conn.autocommit = old_autocommit
        if should_close and not _conn_is_closed(conn):
            conn.close()

    appointments = [
        {**dict(r), "scheduled_at": _temporal_text(r.get("scheduled_at"))}
        for r in raw_appointments
    ]

    session["last_section"] = "citas"
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

    conn, should_close = _get_conn()
    old_autocommit = conn.autocommit
    try:
        conn.autocommit = False
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
        conn.autocommit = old_autocommit
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
    locked = _require_login()
    if locked:
        return locked

    conn, should_close = _get_conn()
    old_autocommit = conn.autocommit
    try:
        conn.autocommit = False
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
        conn.autocommit = old_autocommit
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

    # Buscar pacientes
    for p in _cur_fetchall("patients"):
        full = f"{p['first_name']} {p['last_name']}".strip()
        if q in full.lower() or q in str(p["patient_id"]):
            results.append({
                "type":     "paciente",
                "title":    full,
                "subtitle": f"ID: P{p['patient_id']}",
                "url":      url_for("historial_paciente", id=p["patient_id"]),
            })

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
    old_autocommit = conn.autocommit
    try:
        conn.autocommit = False
        with conn.cursor() as cur:
            cur.execute("CALL sp_get_workers_full(%s)", ("cur_workers_search",))
            cur.execute('FETCH ALL FROM "cur_workers_search"')
            workers = cur.fetchall()
        conn.commit()
    except Exception:
        _safe_rollback(conn)
        workers = []
    finally:
        conn.autocommit = old_autocommit
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


@app.route("/api/reportes-publicos/resumen")
def api_reportes_publicos_resumen():
    locked = _require_login()
    if locked:
        return jsonify({"error": "No autenticado"}), 401

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
        return jsonify(dict(sp_row))

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
    locked = _require_login()
    if locked:
        return jsonify({"error": "No autenticado"}), 401

    conn, should_close = _get_conn()
    old_autocommit = conn.autocommit
    try:
        conn.autocommit = False
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
        conn.autocommit = old_autocommit
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