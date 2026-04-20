from datetime import date, datetime
import json
import os
import re
from threading import Lock
from flask import Flask, flash, g, jsonify, redirect, render_template, request, session, url_for

try:
    import bcrypt
except ImportError:  # pragma: no cover
    bcrypt = None

try:
    import psycopg2
    from psycopg2.extras import RealDictCursor
except ImportError:  # pragma: no cover
    psycopg2 = None
    RealDictCursor = None

app = Flask(__name__)
app.secret_key = "segunda-entrega-demo"

# Estado en memoria para puente NFC (ultima lectura + historial corto)
NFC_BRIDGE_LOCK = Lock()
NFC_BRIDGE_STATE = {
    "latest": None,
    "events": [],
    "event_seq": 0,
}

# Vinculacion UID -> entidad (medico/paciente) para acciones automaticas.
# Ya no se cargan semillas demo: todo debe vivir en PostgreSQL.
NFC_BINDINGS = []


def _nfc_bridge_token():
    """Token compartido para proteger el endpoint publico de ingesta NFC."""
    return os.getenv("NFC_BRIDGE_TOKEN", "demo-nfc-token")


def _is_local_request():
    remote = (request.remote_addr or "").strip()
    return remote in {"127.0.0.1", "::1", "localhost"}


def _extract_nfc_uid(payload):
    """Intenta extraer UID desde nombres de campos comunes enviados por apps NFC."""
    if not isinstance(payload, dict):
        return None
    candidates = [
        "uid", "id", "tag_id", "nfc_id", "NFC_ID", "serial", "identifier", "value",
        "TAG_UID", "tagUid", "nfcUid", "scanned_tag_id", "tagId", "serial_number",
    ]
    for key in candidates:
        value = payload.get(key)
        if value is not None and str(value).strip():
            return str(value).strip().upper()
    return None


def _record_nfc_event(uid, source):
    now = datetime.now().isoformat(timespec="seconds")
    normalized_uid = str(uid).strip().upper()
    event = {
        "uid": normalized_uid,
        "source": source,
        "timestamp": now,
    }
    with NFC_BRIDGE_LOCK:
        NFC_BRIDGE_STATE["event_seq"] += 1
        event["event_id"] = NFC_BRIDGE_STATE["event_seq"]
        NFC_BRIDGE_STATE["latest"] = event
        NFC_BRIDGE_STATE["events"].insert(0, event)
        NFC_BRIDGE_STATE["events"] = NFC_BRIDGE_STATE["events"][:30]
    return event


def _normalize_uid(uid):
    raw = str(uid or "").strip().upper()
    # Igualar tags aunque lleguen con separadores ({}, :, -, espacios).
    return re.sub(r"[^A-Z0-9]", "", raw)


def _looks_like_placeholder_uid(uid):
    raw = str(uid or "").strip().upper()
    normalized = _normalize_uid(raw)
    placeholders = {
        "UID", "UIDTAG", "TAGUID", "TAGID", "NFCTAG", "UIDAQUI", "UIDDELTAG",
    }
    return (
        raw in {"{UID_TAG}", "{UID}", "UID_TAG", "UID"}
        or normalized in placeholders
        or "UID_TAG" in raw
    )


def _db_configured():
    return bool(psycopg2 is not None and (
        os.getenv("DATABASE_URL")
        or (
            os.getenv("PGHOST")
            and os.getenv("PGDATABASE")
            and os.getenv("PGUSER")
            and os.getenv("PGPASSWORD")
        )
    ))


def _db_connect():
    if not _db_configured():
        return None

    dsn = os.getenv("DATABASE_URL")
    if dsn:
        return psycopg2.connect(dsn, cursor_factory=RealDictCursor)

    return psycopg2.connect(
        host=os.getenv("PGHOST"),
        port=int(os.getenv("PGPORT", "5432")),
        dbname=os.getenv("PGDATABASE"),
        user=os.getenv("PGUSER"),
        password=os.getenv("PGPASSWORD"),
        cursor_factory=RealDictCursor,
    )


def _db_query_one(sql, params=None):
    conn = _db_connect()
    if not conn:
        return None
    try:
        with conn:
            with conn.cursor() as cursor:
                cursor.execute(sql, params or ())
                row = cursor.fetchone()
                return dict(row) if row else None
    finally:
        conn.close()


def _db_query_all(sql, params=None):
    conn = _db_connect()
    if not conn:
        return []
    try:
        with conn:
            with conn.cursor() as cursor:
                cursor.execute(sql, params or ())
                rows = cursor.fetchall()
                return [dict(row) for row in rows]
    finally:
        conn.close()


def _db_execute(sql, params=None):
    conn = _db_connect()
    if not conn:
        return
    try:
        with conn:
            with conn.cursor() as cursor:
                cursor.execute(sql, params or ())
    finally:
        conn.close()


ACTION_LOG_TABLE_READY = False
ACTION_LOG_LOCK = Lock()
REQUIRE_DATABASE_MODE = os.getenv("REQUIRE_DATABASE_MODE", "1").strip() != "0"
SENSITIVE_KEYS = {
    "password", "password_confirm", "pass", "token", "nfc_bridge_token",
    "authorization", "x-nfc-token",
}


def _db_ensure_action_log_table():
    global ACTION_LOG_TABLE_READY
    if ACTION_LOG_TABLE_READY or not _db_configured():
        return

    with ACTION_LOG_LOCK:
        if ACTION_LOG_TABLE_READY:
            return
        _db_execute(
            """
            CREATE TABLE IF NOT EXISTS action_log (
                action_id       SERIAL PRIMARY KEY,
                module          VARCHAR(20)  NOT NULL,
                action_type     VARCHAR(20)  NOT NULL,
                http_method     VARCHAR(10)  NOT NULL,
                route_path      VARCHAR(255) NOT NULL,
                entity_id       INT,
                worker_id       INT          REFERENCES workers(worker_id),
                status_code     INT          NOT NULL,
                request_payload TEXT,
                ip_address      VARCHAR(45),
                created_at      TIMESTAMP    NOT NULL DEFAULT NOW()
            )
            """
        )
        _db_execute(
            """
            CREATE INDEX IF NOT EXISTS idx_action_log_module_created
            ON action_log(module, created_at DESC)
            """
        )
        ACTION_LOG_TABLE_READY = True


def _db_is_reachable():
    try:
        conn = _db_connect()
    except Exception:
        return False
    if not conn:
        return False
    try:
        return True
    finally:
        conn.close()


def _audit_module_from_path(path):
    route = (path or "").lower()
    if route.startswith("/api/nfc") or route.startswith("/nfc"):
        return "nfc"

    patient_prefixes = (
        "/pacientes", "/register_patient", "/delete_patient", "/historial", "/esquema_paciente", "/api/patients-list",
    )
    if route.startswith(patient_prefixes):
        return "patients"

    worker_prefixes = (
        "/personal", "/api/workers-list",
    )
    if route.startswith(worker_prefixes):
        return "workers"

    return None


def _requires_persistent_storage(path):
    route = (path or "").lower()
    prefixes = (
        "/pacientes", "/register_patient", "/delete_patient", "/historial", "/esquema_paciente", "/api/patients-list",
        "/personal", "/api/workers-list",
        "/nfc", "/api/nfc", "/nfc-bridge", "/nfc-station",
    )
    return route.startswith(prefixes)


def _sanitize_payload(value):
    if isinstance(value, dict):
        cleaned = {}
        for key, item in value.items():
            key_l = str(key).lower()
            if key_l in SENSITIVE_KEYS:
                cleaned[key] = "***"
            else:
                cleaned[key] = _sanitize_payload(item)
        return cleaned
    if isinstance(value, list):
        return [_sanitize_payload(item) for item in value]
    return value


def _collect_request_payload():
    payload = {}
    if request.args:
        payload["query"] = _sanitize_payload(request.args.to_dict(flat=True))

    if request.method in {"POST", "PUT", "PATCH", "DELETE"}:
        json_body = request.get_json(silent=True)
        if isinstance(json_body, dict):
            payload["json"] = _sanitize_payload(json_body)
        elif request.form:
            payload["form"] = _sanitize_payload(request.form.to_dict(flat=True))

    if not payload:
        return None
    return payload


def _extract_entity_id(module_name):
    candidates = []
    if request.view_args:
        candidates.extend(request.view_args.values())

    for key in ("patient_id", "worker_id", "entity_id", "id"):
        value = request.args.get(key)
        if value is not None:
            candidates.append(value)
        value = request.form.get(key)
        if value is not None:
            candidates.append(value)

    json_body = request.get_json(silent=True)
    if isinstance(json_body, dict):
        for key in ("patient_id", "worker_id", "entity_id", "id"):
            if json_body.get(key) is not None:
                candidates.append(json_body.get(key))
        if module_name == "nfc":
            entity_type = str(json_body.get("entity_type") or "").lower()
            if entity_type == "worker" and json_body.get("entity_id") is not None:
                candidates.append(json_body.get("entity_id"))

    for value in candidates:
        text = str(value).strip()
        if text.isdigit():
            return int(text)
    return None


def _action_type_from_method(method):
    method_u = (method or "").upper()
    if method_u == "POST":
        return "CREATE"
    if method_u in {"PUT", "PATCH"}:
        return "UPDATE"
    if method_u == "DELETE":
        return "DELETE"
    if method_u == "GET":
        return "READ"
    return "OTHER"


def _db_insert_action_log(module_name, action_type, entity_id, status_code, payload):
    if _db_configured():
        _db_ensure_action_log_table()
        _db_execute(
            """
            INSERT INTO action_log (
                module, action_type, http_method, route_path, entity_id,
                worker_id, status_code, request_payload, ip_address
            )
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (
                module_name,
                action_type,
                request.method,
                request.path,
                entity_id,
                session.get("worker_id"),
                int(status_code or 0),
                json.dumps(payload, ensure_ascii=True) if payload is not None else None,
                request.headers.get("X-Forwarded-For") or request.remote_addr,
            ),
        )
        return

    AUDIT_LOG.append({
        "audit_id": _next_id(AUDIT_LOG, "audit_id"),
        "table_name": module_name,
        "record_id": entity_id or 0,
        "action": action_type,
        "worker_id": session.get("worker_id"),
        "changed_at": datetime.now().isoformat(timespec="seconds"),
        "ip_address": request.headers.get("X-Forwarded-For") or request.remote_addr,
    })


def _db_sync_serial_sequence(table_name, id_column):
    """Alinea la secuencia SERIAL con el MAX(id) actual para evitar PK duplicada."""
    conn = _db_connect()
    if not conn:
        return
    try:
        with conn:
            with conn.cursor() as cursor:
                cursor.execute("SELECT pg_get_serial_sequence(%s, %s) AS seq", (table_name, id_column))
                row = cursor.fetchone()
                seq = row.get("seq") if row else None
                if not seq:
                    return
                cursor.execute(
                    f"SELECT setval(%s, COALESCE((SELECT MAX({id_column}) FROM {table_name}), 1), true)",
                    (seq,),
                )
    finally:
        conn.close()


def _db_password_matches(stored_hash, password):
    if not stored_hash:
        return False
    if stored_hash.startswith("$2"):
        if bcrypt is None:
            return False
        return bcrypt.checkpw(password.encode("utf-8"), stored_hash.encode("utf-8"))
    if stored_hash.startswith("hash:"):
        return stored_hash == f"hash:{password}"
    return stored_hash == password


def _password_hash_for_storage(password):
    if bcrypt is not None:
        return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")
    return f"hash:{password}"


def _db_authenticate_worker(login_value, password):
    row = _db_query_one(
        """
        SELECT w.worker_id, w.first_name, w.last_name, w.password_hash, r.name AS role_name
        FROM workers w
        LEFT JOIN worker_emails we
            ON we.worker_id = w.worker_id AND we.is_primary = TRUE
        LEFT JOIN roles r
            ON r.role_id = w.role_id
        WHERE LOWER(we.email) = LOWER(%s)
           OR LOWER(w.curp) = LOWER(%s)
           OR LOWER(w.first_name) = LOWER(%s)
        ORDER BY we.is_primary DESC
        LIMIT 1
        """,
        (login_value, login_value, login_value),
    )
    if row and _db_password_matches(row.get("password_hash"), password):
        return {
            "worker_id": row["worker_id"],
            "name": row["first_name"],
            "lastname": row["last_name"],
            "role": row.get("role_name") or "Personal",
        }
    return None


def _db_list_workers_for_binding():
    return _db_query_all(
        """
        SELECT w.worker_id, w.first_name, w.last_name, r.name AS role_name,
               COALESCE(we.email, '') AS email
        FROM workers w
        LEFT JOIN worker_emails we
            ON we.worker_id = w.worker_id AND we.is_primary = TRUE
        LEFT JOIN roles r
            ON r.role_id = w.role_id
        ORDER BY w.worker_id
        """
    )


def _db_list_patients_for_binding():
    return _db_query_all(
        """
        SELECT patient_id, first_name, last_name
        FROM patients
        ORDER BY patient_id
        """
    )


def _db_worker_by_id(worker_id):
    return _db_query_one(
        """
        SELECT w.worker_id, w.first_name, w.last_name, r.name AS role_name
        FROM workers w
        LEFT JOIN roles r ON r.role_id = w.role_id
        WHERE w.worker_id = %s
        LIMIT 1
        """,
        (worker_id,),
    )


def _db_patient_by_id(patient_id):
    return _db_query_one(
        """
        SELECT patient_id, first_name, last_name
        FROM patients
        WHERE patient_id = %s
        LIMIT 1
        """,
        (patient_id,),
    )


def _db_role_id_by_name(role_name):
    row = _db_query_one("SELECT role_id FROM roles WHERE LOWER(name) = LOWER(%s) LIMIT 1", (role_name,))
    return row["role_id"] if row else None


def _db_blood_type_id(blood_type):
    row = _db_query_one("SELECT blood_type_id FROM blood_types WHERE blood_type = %s LIMIT 1", (blood_type,))
    return row["blood_type_id"] if row else None


def _db_list_patients_for_page():
    rows = _db_query_all(
        """
        SELECT
            p.patient_id,
            p.first_name,
            p.last_name,
            p.birth_date::text AS birth_date,
            COALESCE(bt.blood_type, '—') AS blood_type,
            COALESCE(g.first_name || ' ' || g.last_name, 'Sin tutor') AS guardian,
            COALESCE(gp.phone, '—') AS contact,
            COALESCE(string_agg(DISTINCT a.name, ', '), 'Ninguna') AS allergies
        FROM patients p
        LEFT JOIN blood_types bt
            ON bt.blood_type_id = p.blood_type_id
        LEFT JOIN LATERAL (
            SELECT r.guardian_id
            FROM patient_guardian_relations r
            WHERE r.patient_id = p.patient_id
            ORDER BY r.is_primary DESC, r.relation_id
            LIMIT 1
        ) rel ON TRUE
        LEFT JOIN guardians g
            ON g.guardian_id = rel.guardian_id
        LEFT JOIN LATERAL (
            SELECT phone
            FROM guardian_phones
            WHERE guardian_id = g.guardian_id
            ORDER BY is_primary DESC, phone_id
            LIMIT 1
        ) gp ON TRUE
        LEFT JOIN patient_allergies pa
            ON pa.patient_id = p.patient_id
        LEFT JOIN allergies a
            ON a.allergy_id = pa.allergy_id
        GROUP BY p.patient_id, p.first_name, p.last_name, p.birth_date, bt.blood_type, g.first_name, g.last_name, gp.phone
        ORDER BY p.patient_id
        """
    )
    out = []
    for row in rows:
        item = dict(row)
        item["full_name"] = f"{item.get('first_name', '')} {item.get('last_name', '')}".strip()
        item["risk"] = "N/A"
        out.append(item)
    return out


def _db_list_workers_for_page():
    return _db_query_all(
        """
        SELECT
            w.worker_id,
            w.first_name AS name,
            w.last_name AS lastname,
            COALESCE(r.name, 'Sin rol') AS role,
            COALESCE(we.email, '') AS mail
        FROM workers w
        LEFT JOIN roles r
            ON r.role_id = w.role_id
        LEFT JOIN LATERAL (
            SELECT email
            FROM worker_emails
            WHERE worker_id = w.worker_id
            ORDER BY is_primary DESC, email_id
            LIMIT 1
        ) we ON TRUE
        ORDER BY w.worker_id
        """
    )


def _db_ensure_nfc_bindings_table():
    """Crea la tabla de vinculaciones NFC si no existe."""
    _db_execute(
        """
        CREATE TABLE IF NOT EXISTS nfc_bindings (
            binding_id    SERIAL PRIMARY KEY,
            uid           VARCHAR(50)  NOT NULL,
            uid_norm      VARCHAR(50)  NOT NULL UNIQUE,
            entity_type   VARCHAR(20)  NOT NULL CHECK (entity_type IN ('worker', 'patient')),
            entity_id     INT          NOT NULL,
            worker_id     INT          REFERENCES workers(worker_id),
            label         VARCHAR(150),
            created_at    TIMESTAMP    NOT NULL DEFAULT NOW(),
            updated_at    TIMESTAMP    NOT NULL DEFAULT NOW()
        )
        """
    )
    _db_execute("ALTER TABLE nfc_bindings ADD COLUMN IF NOT EXISTS worker_id INT REFERENCES workers(worker_id)")
    _db_execute("UPDATE nfc_bindings SET worker_id = entity_id WHERE entity_type = 'worker' AND worker_id IS NULL")
    _db_execute(
        """
        CREATE INDEX IF NOT EXISTS idx_nfc_bindings_entity
        ON nfc_bindings(entity_type, entity_id)
        """
    )


def _db_list_nfc_bindings():
    if not _db_configured():
        return []

    _db_ensure_nfc_bindings_table()
    rows = _db_query_all(
        """
        SELECT uid, entity_type, entity_id, worker_id, COALESCE(label, '') AS label
        FROM nfc_bindings
        ORDER BY binding_id
        """
    )

    return rows


def _db_upsert_nfc_binding(uid, uid_norm, entity_type, entity_id, label):
    if not _db_configured():
        return None
    _db_ensure_nfc_bindings_table()
    worker_id = entity_id if entity_type == "worker" else None
    _db_execute(
        """
        INSERT INTO nfc_bindings (uid, uid_norm, entity_type, entity_id, worker_id, label, updated_at)
        VALUES (%s, %s, %s, %s, %s, %s, NOW())
        ON CONFLICT (uid_norm)
        DO UPDATE SET
            uid = EXCLUDED.uid,
            entity_type = EXCLUDED.entity_type,
            entity_id = EXCLUDED.entity_id,
            worker_id = EXCLUDED.worker_id,
            label = EXCLUDED.label,
            updated_at = NOW()
        """,
        (uid, uid_norm, entity_type, entity_id, worker_id, label),
    )
    return _db_query_one(
        """
        SELECT uid, entity_type, entity_id, worker_id, COALESCE(label, '') AS label
        FROM nfc_bindings
        WHERE uid_norm = %s
        LIMIT 1
        """,
        (uid_norm,),
    )


def _db_delete_nfc_binding(uid_norm):
    if not _db_configured():
        return 0
    _db_ensure_nfc_bindings_table()
    row = _db_query_one("DELETE FROM nfc_bindings WHERE uid_norm = %s RETURNING binding_id", (uid_norm,))
    return 1 if row else 0


def _db_delete_nfc_bindings_for_entity(entity_type, entity_id):
    if not _db_configured():
        return
    _db_ensure_nfc_bindings_table()
    _db_execute("DELETE FROM nfc_bindings WHERE entity_type = %s AND entity_id = %s", (entity_type, entity_id))


def _dedupe_nfc_bindings():
    """Normaliza y deduplica bindings por UID, conservando el mas reciente."""
    dedup = {}
    for b in NFC_BINDINGS:
        key = _normalize_uid(b.get("uid"))
        if not key:
            continue
        dedup[key] = {
            "uid": str(b.get("uid") or "").strip().upper(),
            "entity_type": b.get("entity_type"),
            "entity_id": b.get("entity_id"),
            "label": b.get("label", ""),
        }
    NFC_BINDINGS[:] = list(dedup.values())


_dedupe_nfc_bindings()


# DATOS HARDCODEADOS  (simulan lo que devolvería PostgreSQL)

# --- ADDRESSES -----------------------------------------------------------
COUNTRIES = [
    {"country_id": 1, "name": "México", "iso_code": "MX"},
]

STATES = [
    {"state_id": 1, "country_id": 1, "name": "Nuevo León", "code": "NL"},
]

MUNICIPALITIES = [
    {"municipality_id": 1, "state_id": 1, "name": "Monterrey"},
    {"municipality_id": 2, "state_id": 1, "name": "Guadalupe"},
]

NEIGHBORHOODS = [
    {"neighborhood_id": 1, "municipality_id": 1, "name": "Centro",     "zip_code": "64000"},
    {"neighborhood_id": 2, "municipality_id": 1, "name": "Obispado",   "zip_code": "64010"},
    {"neighborhood_id": 3, "municipality_id": 2, "name": "Topo Chico", "zip_code": "64260"},
]

# cross_street_2 fue eliminada del schema
ADDRESSES = [
    {"address_id": 1, "neighborhood_id": 1, "street": "Av. Constitución", "ext_number": "100", "cross_street_1": "Juárez",  "latitude": 25.6700, "longitude": -100.3099},
    {"address_id": 2, "neighborhood_id": 2, "street": "Calle Obispado",   "ext_number": "45",  "cross_street_1": "Hidalgo", "latitude": 25.6780, "longitude": -100.3200},
    {"address_id": 3, "neighborhood_id": 3, "street": "Blvd. Díaz Ordaz", "ext_number": "500", "cross_street_1": "Morones", "latitude": 25.7050, "longitude": -100.3500},
]

# --- CLINICS -------------------------------------------------------------
# clues fue eliminada del schema
CLINICS = [
    {"clinic_id": 1, "name": "Centro de Salud Centro",  "address_id": 1, "phone": "8112223344", "institution_type": "SSA",  "is_active": True},
    {"clinic_id": 2, "name": "Unidad Médica Obispado",  "address_id": 2, "phone": "8118887766", "institution_type": "IMSS", "is_active": True},
    {"clinic_id": 3, "name": "Clínica DIF Guadalupe",   "address_id": 3, "phone": "8191234567", "institution_type": "DIF",  "is_active": True},
]

# area_type ahora es FK a area_types
AREA_TYPES = [
    {"area_type_id": 1, "area_type": "Recepcion"},
    {"area_type_id": 2, "area_type": "Sala_Espera"},
    {"area_type_id": 3, "area_type": "Consultorio"},
    {"area_type_id": 4, "area_type": "Enfermeria"},
    {"area_type_id": 5, "area_type": "Almacen"},
]

CLINIC_AREAS = [
    {"area_id": 1, "clinic_id": 1, "name": "Recepción",      "area_type_id": 1, "floor": 1, "capacity": 20},
    {"area_id": 2, "clinic_id": 1, "name": "Sala de Espera", "area_type_id": 2, "floor": 1, "capacity": 40},
    {"area_id": 3, "clinic_id": 1, "name": "Consultorio 1",  "area_type_id": 3, "floor": 1, "capacity": 5},
    {"area_id": 4, "clinic_id": 2, "name": "Enfermería A",   "area_type_id": 4, "floor": 1, "capacity": 10},
    {"area_id": 5, "clinic_id": 3, "name": "Almacén Central","area_type_id": 5, "floor": 1, "capacity": None},
]

EQUIPMENT_CATALOG = [
    {"equipment_id": 1, "name": "Refrigerador de vacunas", "category": "Refrigeración", "requires_calibration": True},
    {"equipment_id": 2, "name": "Termómetro digital",      "category": "Medición",      "requires_calibration": True},
]

AREA_EQUIPMENT = [
    {"area_equipment_id": 1, "area_id": 3, "equipment_id": 1, "quantity": 1, "serial_number": "SER-001", "condition": "Bueno"},
    {"area_equipment_id": 2, "area_id": 4, "equipment_id": 2, "quantity": 2, "serial_number": None,      "condition": "Regular"},
]

# --- PATIENTS ------------------------------------------------------------
# Normalizado: second_last, address_id, risk_level, is_active, registered_at eliminados
# blood_type_id ahora es FK; agregados weight_kg y premature
BLOOD_TYPES = [
    {"blood_type_id": 1, "blood_type": "O+"},
    {"blood_type_id": 2, "blood_type": "A+"},
    {"blood_type_id": 3, "blood_type": "B+"},
    {"blood_type_id": 4, "blood_type": "AB+"},
    {"blood_type_id": 5, "blood_type": "O-"},
    {"blood_type_id": 6, "blood_type": "A-"},
    {"blood_type_id": 7, "blood_type": "B-"},
    {"blood_type_id": 8, "blood_type": "AB-"},
]

PATIENTS = [
    {"patient_id": 1, "first_name": "Ana",     "last_name": "Martínez", "curp": "MASA200515MNLRTN09", "birth_date": "2020-05-15", "gender": "F", "blood_type_id": 1, "nfc_token": "NFC001", "weight_kg": 12.5, "premature": False},
    {"patient_id": 2, "first_name": "Carlos",  "last_name": "Sánchez",  "curp": "SARC190308HNLNRL05", "birth_date": "2019-03-08", "gender": "M", "blood_type_id": 2, "nfc_token": "NFC002", "weight_kg": 15.0, "premature": False},
    {"patient_id": 3, "first_name": "Daniela", "last_name": "López",    "curp": "LOJD221003MNLPJN07", "birth_date": "2022-10-03", "gender": "F", "blood_type_id": 3, "nfc_token": "NFC003", "weight_kg": 10.2, "premature": True},
    {"patient_id": 4, "first_name": "Miguel",  "last_name": "Flores",   "curp": "FOCM210720HNLLRG04", "birth_date": "2021-07-20", "gender": "M", "blood_type_id": 4, "nfc_token": "NFC004", "weight_kg": 13.8, "premature": False},
]

# allergies ahora es catálogo normalizado
ALLERGIES = [
    {"allergy_id": 1, "name": "Polen",      "allergy_type": "Ambiental"},
    {"allergy_id": 2, "name": "Penicilina", "allergy_type": "Medicamento"},
    {"allergy_id": 3, "name": "Látex",      "allergy_type": "Contacto"},
]

# patient_allergies ahora referencia allergy_id en vez de guardar allergen/reaction directo
PATIENT_ALLERGIES = [
    {"patient_allergy_id": 1, "patient_id": 2, "allergy_id": 1, "severity": "Leve",     "reaction_desc": "Rinitis"},
    {"patient_allergy_id": 2, "patient_id": 3, "allergy_id": 2, "severity": "Moderada", "reaction_desc": "Urticaria – evitar derivados"},
    {"patient_allergy_id": 3, "patient_id": 3, "allergy_id": 3, "severity": "Leve",     "reaction_desc": "Erupción"},
]

# --- GUARDIANS ----------------------------------------------------------
# marital_status y occupation ahora son tablas normalizadas
MARITAL_STATUS = [
    {"marital_status_id": 1, "marital_status": "Casado"},
    {"marital_status_id": 2, "marital_status": "Soltero"},
    {"marital_status_id": 3, "marital_status": "Union_Libre"},
    {"marital_status_id": 4, "marital_status": "Divorciado"},
    {"marital_status_id": 5, "marital_status": "Viudo"},
]

OCCUPATIONS = [
    {"occupation_id": 1, "occupation_name": "Profesora"},
    {"occupation_id": 2, "occupation_name": "Contador"},
    {"occupation_id": 3, "occupation_name": "Enfermera"},
]

# second_last eliminado; marital_status_id y occupation son FK int
GUARDIANS = [
    {"guardian_id": 1, "first_name": "María", "last_name": "Martínez", "curp": "MASM800501MNLRTRO8", "address_id": 1, "marital_status_id": 1, "occupation": 1},
    {"guardian_id": 2, "first_name": "Jorge", "last_name": "Sánchez",  "curp": "SARJ790320HNLNYR02", "address_id": 2, "marital_status_id": 2, "occupation": 2},
    {"guardian_id": 3, "first_name": "Laura", "last_name": "López",    "curp": "LOJL850715MNLPJR05", "address_id": 3, "marital_status_id": 3, "occupation": 3},
]

GUARDIAN_PHONES = [
    {"phone_id": 1, "guardian_id": 1, "phone": "8112345678", "phone_type": "Celular",    "is_primary": True},
    {"phone_id": 2, "guardian_id": 1, "phone": "8118889900", "phone_type": "Casa",       "is_primary": False},
    {"phone_id": 3, "guardian_id": 2, "phone": "8187654321", "phone_type": "Celular",    "is_primary": True},
    {"phone_id": 4, "guardian_id": 3, "phone": "8199911122", "phone_type": "Celular",    "is_primary": True},
    {"phone_id": 5, "guardian_id": 3, "phone": "8005551234", "phone_type": "Emergencia", "is_primary": False},
]

GUARDIAN_EMAILS = [
    {"email_id": 1, "guardian_id": 1, "email": "maria.martinez@mail.com", "is_primary": True},
    {"email_id": 2, "guardian_id": 2, "email": "jorge.sanchez@mail.com",  "is_primary": True},
    {"email_id": 3, "guardian_id": 3, "email": "laura.lopez@mail.com",    "is_primary": True},
]

# Tabla nueva: relación paciente-tutor normalizada (antes era guardian_id directo en patients)
PATIENT_GUARDIAN_RELATIONS = [
    {"relation_id": 1, "patient_id": 1, "guardian_id": 1, "relation_type": "Madre",  "is_primary": True,  "has_custody": True},
    {"relation_id": 2, "patient_id": 2, "guardian_id": 2, "relation_type": "Padre",  "is_primary": True,  "has_custody": True},
    {"relation_id": 3, "patient_id": 3, "guardian_id": 3, "relation_type": "Madre",  "is_primary": True,  "has_custody": True},
    {"relation_id": 4, "patient_id": 4, "guardian_id": 1, "relation_type": "Madre",  "is_primary": True,  "has_custody": True},
]

# --- WORKERS ------------------------------------------------------------
# second_last, email, phone, is_active eliminados del workers principal
# email y teléfono ahora en worker_emails / worker_phones
# specialty normalizada en specialties / institutions
ROLES = [
    {"role_id": 1, "name": "Administrador", "description": "Acceso total al sistema"},
    {"role_id": 2, "name": "Médico",        "description": "Consulta y vacunación"},
    {"role_id": 3, "name": "Enfermero",     "description": "Aplicación de vacunas"},
    {"role_id": 4, "name": "Almacen",       "description": "Control de inventario"},
    {"role_id": 5, "name": "Recepcionista", "description": "Registro de llegadas"},
]

SPECIALTIES = [
    {"specialty_id": 1, "name": "Pediatría"},
    {"specialty_id": 2, "name": "Enfermería General"},
]

INSTITUTIONS = [
    {"institution_id": 1, "institution_name": "UANL",        "address_id": None},
    {"institution_id": 2, "institution_name": "TecSalud NL", "address_id": None},
]

WORKERS = [
    {"worker_id": 1, "role_id": 1, "first_name": "Admin",  "last_name": "Demo",   "curp": "ADMD800101HNLMMS09", "address_id": None, "birth_date": "1980-01-01", "hire_date": "2020-01-01", "password_hash": "hash:123"},
    {"worker_id": 2, "role_id": 3, "first_name": "Elena",  "last_name": "Garza",  "curp": "GALE900215MNLRZL05", "address_id": 1,    "birth_date": "1990-02-15", "hire_date": "2021-03-10", "password_hash": "hash:elena"},
    {"worker_id": 3, "role_id": 4, "first_name": "Mario",  "last_name": "Ruiz",   "curp": "RUPM850730HNLZXR08", "address_id": 2,    "birth_date": "1985-07-30", "hire_date": "2022-06-01", "password_hash": "hash:mario"},
    {"worker_id": 4, "role_id": 2, "first_name": "Sofía",  "last_name": "Torres", "curp": "TOVS920410MNLRRG06", "address_id": 3,    "birth_date": "1992-04-10", "hire_date": "2023-01-15", "password_hash": "hash:sofia"},
    {"worker_id": 5, "role_id": 5, "first_name": "Pedro",  "last_name": "Luna",   "curp": "LUMP781120HNLNND03", "address_id": 1,    "birth_date": "1978-11-20", "hire_date": "2020-09-05", "password_hash": "hash:pedro"},
]

WORKER_PHONES = [
    {"phone_id": 1, "worker_id": 2, "phone": "8111122334", "phone_type": "Celular", "is_primary": True},
    {"phone_id": 2, "worker_id": 3, "phone": "8199988776", "phone_type": "Celular", "is_primary": True},
    {"phone_id": 3, "worker_id": 4, "phone": "8115566778", "phone_type": "Celular", "is_primary": True},
    {"phone_id": 4, "worker_id": 5, "phone": "8182233445", "phone_type": "Celular", "is_primary": True},
]

WORKER_EMAILS = [
    {"email_id": 1, "worker_id": 1, "email": "admin",             "is_primary": True},
    {"email_id": 2, "worker_id": 2, "email": "elena@demo.local",  "is_primary": True},
    {"email_id": 3, "worker_id": 3, "email": "mario@demo.local",  "is_primary": True},
    {"email_id": 4, "worker_id": 4, "email": "sofia@demo.local",  "is_primary": True},
    {"email_id": 5, "worker_id": 5, "email": "pedro@demo.local",  "is_primary": True},
]

# specialty ahora referencia specialty_id e institution_id (FKs)
WORKER_PROFESSIONAL = [
    {"worker_id": 4, "cedula_profesional": "CED-1234567", "specialty_id": 1, "institution_id": 1},
    {"worker_id": 2, "cedula_profesional": "CED-9876543", "specialty_id": 2, "institution_id": 2},
]

# Renombrada: worker_clinic_assignments → worker_clinic_assignment (sin 's' final)
WORKER_CLINIC_ASSIGNMENT = [
    {"assignment_id": 1, "worker_id": 1, "clinic_id": 1, "area_id": None, "start_date": "2020-01-01", "end_date": None,         "is_active": True},
    {"assignment_id": 2, "worker_id": 2, "clinic_id": 1, "area_id": 3,    "start_date": "2021-03-10", "end_date": None,         "is_active": True},
    {"assignment_id": 3, "worker_id": 3, "clinic_id": 1, "area_id": 5,    "start_date": "2022-06-01", "end_date": None,         "is_active": True},
    {"assignment_id": 4, "worker_id": 4, "clinic_id": 2, "area_id": 4,    "start_date": "2023-01-15", "end_date": None,         "is_active": True},
    {"assignment_id": 5, "worker_id": 5, "clinic_id": 3, "area_id": 1,    "start_date": "2020-09-05", "end_date": "2024-12-31", "is_active": False},
]

WORKER_SCHEDULES = [
    {"schedule_id": 1, "worker_id": 2, "clinic_id": 1, "day_of_week": 1, "entry_time": "08:00", "exit_time": "14:00", "shift_type": "Matutino"},
    {"schedule_id": 2, "worker_id": 2, "clinic_id": 1, "day_of_week": 3, "entry_time": "08:00", "exit_time": "14:00", "shift_type": "Matutino"},
    {"schedule_id": 3, "worker_id": 4, "clinic_id": 2, "day_of_week": 2, "entry_time": "14:00", "exit_time": "20:00", "shift_type": "Vespertino"},
]

# --- VACCINES -----------------------------------------------------------
# manufacturer, disease_target, route etc. normalizados a tablas propias
MANUFACTURERS = [
    {"manufacturer_id": 1, "name": "Biofabrica MX", "country_id": 1, "contact_email": None},
    {"manufacturer_id": 2, "name": "SaludVac",      "country_id": 1, "contact_email": None},
    {"manufacturer_id": 3, "name": "GSK",           "country_id": None, "contact_email": None},
    {"manufacturer_id": 4, "name": "MSD",           "country_id": None, "contact_email": None},
    {"manufacturer_id": 5, "name": "Sanofi",        "country_id": None, "contact_email": None},
]

VACCINE_VIAS = [
    {"via_id": 1, "via": "Intradérmica"},
    {"via_id": 2, "via": "Intramuscular"},
    {"via_id": 3, "via": "Oral"},
    {"via_id": 4, "via": "Subcutánea"},
]

# Campos eliminados: disease_target, recommended_age_months, doses_required, interval_days, route, is_active
VACCINES = [
    {"vaccine_id": 1, "name": "BCG",          "commercial_name": None,             "manufacturer_id": 1, "via_id": 1, "ideal_age_months": 0,  "descripcion": "Tuberculosis"},
    {"vaccine_id": 2, "name": "Hepatitis B",  "commercial_name": "Engerix-B",      "manufacturer_id": 2, "via_id": 2, "ideal_age_months": 0,  "descripcion": "Hepatitis B"},
    {"vaccine_id": 3, "name": "Pentavalente", "commercial_name": None,             "manufacturer_id": 3, "via_id": 2, "ideal_age_months": 2,  "descripcion": "Difteria/Tos/Tétanos"},
    {"vaccine_id": 4, "name": "Rotavirus",    "commercial_name": "RotaTeq",        "manufacturer_id": 4, "via_id": 3, "ideal_age_months": 2,  "descripcion": "Gastroenteritis"},
    {"vaccine_id": 5, "name": "Influenza",    "commercial_name": "Vaxigrip Tetra", "manufacturer_id": 5, "via_id": 2, "ideal_age_months": 6,  "descripcion": "Influenza estacional"},
]

# quantity_remaining → quantity_available; reception_date → received_date; is_active y received_by eliminados
VACCINE_LOTS = [
    {"lot_id": 1, "vaccine_id": 1, "clinic_id": 1, "lot_number": "LOT-BCG-2025-01", "quantity_received": 200, "quantity_available": 120, "expiration_date": "2026-06-30", "received_date": "2025-01-05"},
    {"lot_id": 2, "vaccine_id": 2, "clinic_id": 1, "lot_number": "LOT-HEB-2025-02", "quantity_received": 150, "quantity_available": 95,  "expiration_date": "2025-12-31", "received_date": "2025-01-10"},
    {"lot_id": 3, "vaccine_id": 3, "clinic_id": 1, "lot_number": "LOT-PEN-2025-03", "quantity_received": 100, "quantity_available": 80,  "expiration_date": "2026-03-15", "received_date": "2025-02-01"},
    {"lot_id": 4, "vaccine_id": 4, "clinic_id": 2, "lot_number": "LOT-ROT-2025-04", "quantity_received": 60,  "quantity_available": 30,  "expiration_date": "2025-08-01", "received_date": "2025-02-15"},
    {"lot_id": 5, "vaccine_id": 5, "clinic_id": 3, "lot_number": "LOT-INF-2024-09", "quantity_received": 300, "quantity_available": 0,   "expiration_date": "2025-06-30", "received_date": "2024-09-01"},
]

# --- OFFICIAL SCHEME ----------------------------------------------------
VACCINATION_SCHEME = [
    {"scheme_id": 1, "name": "Esquema Nacional de Vacunación", "issuing_body": "SS México", "year": 2024, "is_current": True},
]

SCHEME_DOSES = [
    {"dose_id": 1, "scheme_id": 1, "vaccine_id": 1, "dose_number": 1, "dose_label": "Dosis 1", "ideal_age_months": 0,  "min_interval_days": None},
    {"dose_id": 2, "scheme_id": 1, "vaccine_id": 2, "dose_number": 1, "dose_label": "Dosis 1", "ideal_age_months": 0,  "min_interval_days": None},
    {"dose_id": 3, "scheme_id": 1, "vaccine_id": 3, "dose_number": 1, "dose_label": "Dosis 1", "ideal_age_months": 2,  "min_interval_days": None},
    {"dose_id": 4, "scheme_id": 1, "vaccine_id": 4, "dose_number": 1, "dose_label": "Dosis 1", "ideal_age_months": 2,  "min_interval_days": None},
    {"dose_id": 5, "scheme_id": 1, "vaccine_id": 3, "dose_number": 2, "dose_label": "Dosis 2", "ideal_age_months": 4,  "min_interval_days": 60},
    {"dose_id": 6, "scheme_id": 1, "vaccine_id": 5, "dose_number": 1, "dose_label": "Dosis 1", "ideal_age_months": 6,  "min_interval_days": None},
    {"dose_id": 7, "scheme_id": 1, "vaccine_id": 2, "dose_number": 3, "dose_label": "Dosis 3", "ideal_age_months": 6,  "min_interval_days": 30},
]

# --- APPOINTMENTS -------------------------------------------------------
# vaccine_id eliminado; agregados area_id, duration_min, reason
# status → appointment_status; notes → appointment_notes
APPOINTMENTS = [
    {"appointment_id": 1, "patient_id": 1, "clinic_id": 1, "area_id": 3, "worker_id": 2, "scheduled_at": "2025-06-10 09:00", "duration_min": 15, "reason": "Segunda dosis Hep B",      "appointment_status": "Programada", "appointment_notes": None},
    {"appointment_id": 2, "patient_id": 2, "clinic_id": 1, "area_id": 3, "worker_id": 2, "scheduled_at": "2025-04-15 10:30", "duration_min": 15, "reason": "Pentavalente refuerzo",    "appointment_status": "Programada", "appointment_notes": None},
    {"appointment_id": 3, "patient_id": 3, "clinic_id": 2, "area_id": 4, "worker_id": 4, "scheduled_at": "2025-05-20 08:00", "duration_min": 20, "reason": "Influenza",                "appointment_status": "Cancelada",  "appointment_notes": "Paciente no asistió"},
    {"appointment_id": 4, "patient_id": 4, "clinic_id": 1, "area_id": 3, "worker_id": 2, "scheduled_at": "2025-03-22 11:00", "duration_min": 15, "reason": "BCG",                      "appointment_status": "Completada", "appointment_notes": "Aplicada sin incidentes"},
]

# --- VACCINATION RECORDS ------------------------------------------------
# Antes llamada APPLICATIONS; campos eliminados: dose_applied, next_dose_date, clinic_location, notes
# Nuevos campos: scheme_dose_id, application_site_id, patient_temp_c, had_reaction
APPLICATION_SITES = [
    {"application_site_id": 1, "application_site": "Deltoides_Izquierdo"},
    {"application_site_id": 2, "application_site": "Deltoides_Derecho"},
    {"application_site_id": 3, "application_site": "Muslo_Izquierdo"},
    {"application_site_id": 4, "application_site": "Muslo_Derecho"},
    {"application_site_id": 5, "application_site": "Oral"},
]

VACCINATION_RECORDS = [
    {"record_id": 1, "patient_id": 1, "vaccine_id": 1, "worker_id": 2, "clinic_id": 1, "lot_id": 1, "scheme_dose_id": 1, "applied_date": "2025-01-10", "application_site_id": 3, "patient_temp_c": 36.5, "had_reaction": False},
    {"record_id": 2, "patient_id": 2, "vaccine_id": 2, "worker_id": 2, "clinic_id": 1, "lot_id": 2, "scheme_dose_id": 2, "applied_date": "2025-02-15", "application_site_id": 1, "patient_temp_c": 36.8, "had_reaction": False},
    {"record_id": 3, "patient_id": 1, "vaccine_id": 3, "worker_id": 1, "clinic_id": 1, "lot_id": 3, "scheme_dose_id": 3, "applied_date": "2025-03-20", "application_site_id": 4, "patient_temp_c": 37.0, "had_reaction": False},
    {"record_id": 4, "patient_id": 3, "vaccine_id": 2, "worker_id": 4, "clinic_id": 2, "lot_id": 2, "scheme_dose_id": 2, "applied_date": "2025-03-01", "application_site_id": 2, "patient_temp_c": 36.6, "had_reaction": False},
    {"record_id": 5, "patient_id": 4, "vaccine_id": 4, "worker_id": 2, "clinic_id": 2, "lot_id": 4, "scheme_dose_id": 4, "applied_date": "2025-03-22", "application_site_id": 5, "patient_temp_c": 36.9, "had_reaction": False},
]

POST_VACCINE_REACTIONS = []  # vacío en demo

# --- SCHEME COMPLETION ALERTS -------------------------------------------
# vaccine_id → scheme_dose_id; resolved_at, resolved_by, notes, generated_at eliminados
# expected_date → due_date; agregado notified_at
SCHEME_COMPLETION_ALERTS = [
    {"alert_id": 1, "patient_id": 3, "scheme_dose_id": 3, "due_date": "2023-12-03", "status": "Pendiente", "notified_at": None},
    {"alert_id": 2, "patient_id": 2, "scheme_dose_id": 6, "due_date": "2025-03-08", "status": "Enviada",   "notified_at": "2025-03-09 08:00"},
    {"alert_id": 3, "patient_id": 1, "scheme_dose_id": 2, "due_date": "2025-04-15", "status": "Resuelta",  "notified_at": "2025-03-10 09:00"},
]

# --- NFC ----------------------------------------------------------------
# notes → nfc_card_notes
NFC_CARDS = [
    {"nfc_card_id": 1, "patient_id": 1, "uid": "NFC001AA", "card_type": "Tarjeta", "issued_date": "2024-01-10", "issued_by": 1, "status": "Activa",      "last_scanned_at": "2025-03-20 09:15", "nfc_card_notes": None},
    {"nfc_card_id": 2, "patient_id": 2, "uid": "NFC002BB", "card_type": "Pulsera", "issued_date": "2024-02-14", "issued_by": 1, "status": "Activa",      "last_scanned_at": "2025-02-15 10:05", "nfc_card_notes": None},
    {"nfc_card_id": 3, "patient_id": 3, "uid": "NFC003CC", "card_type": "Llavero", "issued_date": "2024-03-20", "issued_by": 1, "status": "Desactivada", "last_scanned_at": None,               "nfc_card_notes": "Reportado extraviado"},
    {"nfc_card_id": 4, "patient_id": 4, "uid": "NFC004DD", "card_type": "Tarjeta", "issued_date": "2024-04-05", "issued_by": 1, "status": "Activa",      "last_scanned_at": "2025-03-22 11:00", "nfc_card_notes": None},
]

NFC_DEVICES = [
    {"device_id": "DEV-001", "clinic_id": 1, "area_id": 3, "device_name": "Lector Consultorio 1", "model": "ACR122U", "serial_number": "SN-ACR-001", "nfc_device_status": "Activo", "registered_at": "2024-01-01"},
]

# result → nfc_scan_result; agregado device_id
NFC_SCAN_EVENTS = [
    {"scan_event_id": 1, "nfc_card_id": 1, "scanned_by": 2, "clinic_id": 1, "area_id": 3, "scanned_at": "2025-03-20 09:15", "action_triggered": "Abrir_Expediente",    "device_id": "DEV-001", "nfc_scan_result": "Expediente abierto correctamente"},
    {"scan_event_id": 2, "nfc_card_id": 2, "scanned_by": 2, "clinic_id": 1, "area_id": 3, "scanned_at": "2025-02-15 10:05", "action_triggered": "Confirmar_Vacunacion", "device_id": "DEV-001", "nfc_scan_result": "Vacunación registrada"},
    {"scan_event_id": 3, "nfc_card_id": 4, "scanned_by": 2, "clinic_id": 1, "area_id": 1, "scanned_at": "2025-03-22 11:00", "action_triggered": "Registrar_Llegada",    "device_id": None,      "nfc_scan_result": "Llegada registrada"},
]

# --- GPS ----------------------------------------------------------------
# status → gps_device_status
GPS_DEVICES = [
    {"gps_device_id": 1, "patient_id": 3, "device_type": "Pulsera_GPS", "model": "GarminKid3",  "imei": "352099001761481", "assigned_date": "2024-03-20", "assigned_by": 1, "battery_pct": 72, "gps_device_status": "Activo"},
    {"gps_device_id": 2, "patient_id": 2, "device_type": "App_Tutor",   "model": "AppSalud v2", "imei": None,             "assigned_date": "2024-02-14", "assigned_by": 1, "battery_pct": 95, "gps_device_status": "Activo"},
]

GPS_LOCATIONS = []  # vacío en demo; se llenaría con pings en tiempo real

GPS_SAFE_ZONES = [
    {"zone_id": 1, "patient_id": 3, "guardian_id": 3, "zone_name": "Casa",    "center_lat": 25.7050, "center_lng": -100.3500, "radius_m": 150, "is_active": True},
    {"zone_id": 2, "patient_id": 3, "guardian_id": 3, "zone_name": "Clínica", "center_lat": 25.6700, "center_lng": -100.3099, "radius_m": 200, "is_active": True},
    {"zone_id": 3, "patient_id": 2, "guardian_id": 2, "zone_name": "Escuela", "center_lat": 25.6780, "center_lng": -100.3200, "radius_m": 100, "is_active": True},
]

# notes → risk_notes
GPS_RISK_ALERTS = [
    {"alert_id": 1, "patient_id": 3, "gps_device_id": 1, "alert_type": "Salida_Zona_Segura", "triggered_at": "2025-03-10 14:35", "location_lat": 25.6850, "location_lng": -100.3150, "resolved_at": "2025-03-10 14:50", "resolved_by": 2,    "risk_notes": "Tutor confirmó ubicación"},
    {"alert_id": 2, "patient_id": 2, "gps_device_id": 2, "alert_type": "Bateria_Baja",       "triggered_at": "2025-03-20 07:00", "location_lat": None,    "location_lng": None,       "resolved_at": None,               "resolved_by": None, "risk_notes": "Pendiente de respuesta"},
]

# --- SUPPLY / INVENTORY -------------------------------------------------
# supply_catalog: eliminado description; clinic_inventory: eliminado updated_by; last_updated solo DATE
SUPPLY_CATALOG = [
    {"supply_id": 1, "name": "Jeringa 1mL",       "unit": "pieza",   "category": "Jeringa"},
    {"supply_id": 2, "name": "Jeringa 5mL",       "unit": "pieza",   "category": "Jeringa"},
    {"supply_id": 3, "name": "Algodón estéril",   "unit": "paquete", "category": "Desechable"},
    {"supply_id": 4, "name": "Guantes nitrilo M", "unit": "caja",    "category": "Desechable"},
    {"supply_id": 5, "name": "Paracetamol 500mg", "unit": "tableta", "category": "Medicamento"},
]

CLINIC_INVENTORY = [
    {"inventory_id": 1, "clinic_id": 1, "supply_id": 1, "quantity": 500,  "min_stock": 50,  "last_updated": "2025-03-01"},
    {"inventory_id": 2, "clinic_id": 1, "supply_id": 3, "quantity": 30,   "min_stock": 20,  "last_updated": "2025-03-01"},
    {"inventory_id": 3, "clinic_id": 1, "supply_id": 4, "quantity": 8,    "min_stock": 10,  "last_updated": "2025-03-10"},  # bajo stock
    {"inventory_id": 4, "clinic_id": 2, "supply_id": 2, "quantity": 200,  "min_stock": 30,  "last_updated": "2025-02-20"},
    {"inventory_id": 5, "clinic_id": 3, "supply_id": 5, "quantity": 1000, "min_stock": 100, "last_updated": "2025-01-15"},
]

# Tablas nuevas del schema
BEACONS = []
SCAN_LOGS = []
AUDIT_LOG = []

# --- RISK ZONES (mapa) --------------------------------------------------
ZONES = [
    {"name": "Zona Centro",   "cases": 4, "risk": "high"},
    {"name": "Zona Norte",    "cases": 2, "risk": "medium"},
    {"name": "Zona Sur",      "cases": 1, "risk": "low"},
    {"name": "Zona Oriente",  "cases": 3, "risk": "high"},
    {"name": "Zona Poniente", "cases": 1, "risk": "low"},
]

# --- USERS (login) -------------------------------------------------------
USERS = {
    "admin": {"password": "123", "worker_id": 1, "name": "Admin", "lastname": "Demo", "role": "Administrador"},
}


# =============================================================================
# HELPERS — simulan el cursor de psycopg2
# =============================================================================

def _cur_fetchall(table):
    tables = {
        "countries":                  COUNTRIES,
        "states":                     STATES,
        "municipalities":             MUNICIPALITIES,
        "neighborhoods":              NEIGHBORHOODS,
        "addresses":                  ADDRESSES,
        "clinics":                    CLINICS,
        "area_types":                 AREA_TYPES,
        "clinic_areas":               CLINIC_AREAS,
        "equipment_catalog":          EQUIPMENT_CATALOG,
        "area_equipment":             AREA_EQUIPMENT,
        "blood_types":                BLOOD_TYPES,
        "patients":                   PATIENTS,
        "allergies":                  ALLERGIES,
        "patient_allergies":          PATIENT_ALLERGIES,
        "marital_status":             MARITAL_STATUS,
        "occupations":                OCCUPATIONS,
        "guardians":                  GUARDIANS,
        "guardian_phones":            GUARDIAN_PHONES,
        "guardian_emails":            GUARDIAN_EMAILS,
        "patient_guardian_relations": PATIENT_GUARDIAN_RELATIONS,
        "roles":                      ROLES,
        "specialties":                SPECIALTIES,
        "institutions":               INSTITUTIONS,
        "workers":                    WORKERS,
        "worker_phones":              WORKER_PHONES,
        "worker_emails":              WORKER_EMAILS,
        "worker_professional":        WORKER_PROFESSIONAL,
        "worker_clinic_assignment":   WORKER_CLINIC_ASSIGNMENT,
        "worker_schedules":           WORKER_SCHEDULES,
        "manufacturers":              MANUFACTURERS,
        "vaccine_vias":               VACCINE_VIAS,
        "vaccines":                   VACCINES,
        "vaccine_lots":               VACCINE_LOTS,
        "vaccination_scheme":         VACCINATION_SCHEME,
        "scheme_doses":               SCHEME_DOSES,
        "appointments":               APPOINTMENTS,
        "application_sites":          APPLICATION_SITES,
        "vaccination_records":        VACCINATION_RECORDS,
        "post_vaccine_reactions":     POST_VACCINE_REACTIONS,
        "scheme_completion_alerts":   SCHEME_COMPLETION_ALERTS,
        "nfc_cards":                  [],
        "nfc_devices":                NFC_DEVICES,
        "nfc_scan_events":            [],
        "gps_devices":                GPS_DEVICES,
        "gps_locations":              GPS_LOCATIONS,
        "gps_safe_zones":             GPS_SAFE_ZONES,
        "gps_risk_alerts":            GPS_RISK_ALERTS,
        "supply_catalog":             SUPPLY_CATALOG,
        "clinic_inventory":           CLINIC_INVENTORY,
        "beacons":                    BEACONS,
        "scan_logs":                  SCAN_LOGS,
        "audit_log":                  AUDIT_LOG,
        "zones":                      ZONES,
    }
    return list(tables.get(table, []))


def _cur_fetchone(table, pk_field, pk_value):
    return next((row for row in _cur_fetchall(table) if row.get(pk_field) == pk_value), None)


def _cur_fetchall_where(table, field, value):
    return [row for row in _cur_fetchall(table) if row.get(field) == value]


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


def _worker_full_name(worker_id):
    if _db_configured():
        worker = _db_worker_by_id(worker_id)
        if worker:
            return f"{worker['first_name']} {worker['last_name']}".strip()
    w = _cur_fetchone("workers", "worker_id", worker_id)
    if not w:
        return "Personal demo"
    return f"{w['first_name']} {w['last_name']}".strip()


def _worker_email(worker_id):
    """Devuelve el email primario del trabajador desde worker_emails."""
    if _db_configured():
        row = _db_query_one(
            """
            SELECT email
            FROM worker_emails
            WHERE worker_id = %s AND is_primary = TRUE
            ORDER BY email_id
            LIMIT 1
            """,
            (worker_id,),
        )
        if row:
            return row["email"]
    emails = _cur_fetchall_where("worker_emails", "worker_id", worker_id)
    primary = next((e for e in emails if e.get("is_primary")), None)
    return (primary or emails[0])["email"] if emails else "—"


def _role_name(role_id):
    if _db_configured():
        row = _db_query_one("SELECT name FROM roles WHERE role_id = %s LIMIT 1", (role_id,))
        if row:
            return row["name"]
    role = _cur_fetchone("roles", "role_id", role_id)
    return role["name"] if role else "Personal"


def _find_nfc_binding(uid):
    needle = _normalize_uid(uid)

    # Comando especial para iniciar sesion por worker_id sin UID NFC fisico.
    if needle.startswith("WORKERID"):
        worker_digits = needle.replace("WORKERID", "", 1)
        if worker_digits.isdigit():
            wid = int(worker_digits)
            worker = _db_worker_by_id(wid) if _db_configured() else _cur_fetchone("workers", "worker_id", wid)
            if worker:
                return {
                    "uid": f"WORKER_ID:{wid}",
                    "entity_type": "worker",
                    "entity_id": wid,
                    "worker_id": wid,
                    "label": "Comando worker_id",
                }

    if _db_configured():
        _db_ensure_nfc_bindings_table()
        return _db_query_one(
            """
            SELECT uid, entity_type, entity_id, worker_id, COALESCE(label, '') AS label
            FROM nfc_bindings
            WHERE uid_norm = %s
            LIMIT 1
            """,
            (needle,),
        )
    return None


def _binding_command(binding):
    if not binding:
        return None

    entity_type = binding.get("entity_type")
    entity_id = binding.get("worker_id") or binding.get("entity_id")

    if entity_type == "worker":
        return {
            "type": "worker_login",
            "worker_id": int(entity_id),
            "entity_type": "worker",
            "entity_id": int(entity_id),
        }

    if entity_type == "patient":
        return {
            "type": "open_patient",
            "patient_id": int(entity_id),
            "entity_type": "patient",
            "entity_id": int(entity_id),
        }

    return None


def _nfc_match_from_input(raw_value):
    value = str(raw_value or "").strip()
    if not value:
        return None

    if value.isdigit():
        worker_id = int(value)
        worker = _db_worker_by_id(worker_id) if _db_configured() else _cur_fetchone("workers", "worker_id", worker_id)
        if worker:
            return {
                "uid": f"WORKER_ID:{worker_id}",
                "entity_type": "worker",
                "entity_id": worker_id,
                "worker_id": worker_id,
                "label": "Comando worker_id",
            }

    if value.upper().startswith("WORKER_ID:"):
        worker_digits = value.split(":", 1)[1].strip()
        if worker_digits.isdigit():
            worker_id = int(worker_digits)
            worker = _db_worker_by_id(worker_id) if _db_configured() else _cur_fetchone("workers", "worker_id", worker_id)
            if worker:
                return {
                    "uid": f"WORKER_ID:{worker_id}",
                    "entity_type": "worker",
                    "entity_id": worker_id,
                    "worker_id": worker_id,
                    "label": "Comando worker_id",
                }

    return _find_nfc_binding(value)


def _set_session_from_worker(worker_id):
    if _db_configured():
        worker = _db_worker_by_id(worker_id)
        if not worker:
            return False
        session["user_name"] = worker.get("first_name") or "Personal"
        session["user_lastname"] = worker.get("last_name") or ""
        session["role"] = worker.get("role_name") or "Personal"
        session["worker_id"] = worker["worker_id"]
        return True

    worker = _cur_fetchone("workers", "worker_id", worker_id)
    if not worker:
        return False
    session["user_name"] = worker.get("first_name") or "Personal"
    session["user_lastname"] = worker.get("last_name") or ""
    session["role"] = _role_name(worker.get("role_id"))
    session["worker_id"] = worker["worker_id"]
    return True


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
    """Agrega campos calculados y relacionados a un paciente."""
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


@app.before_request
def _enforce_persistent_storage_mode():
    if not REQUIRE_DATABASE_MODE:
        return None
    if not _requires_persistent_storage(request.path):
        return None
    if not _db_configured() or not _db_is_reachable():
        return jsonify({
            "ok": False,
            "error": "Base de datos no disponible. Se bloqueo el modo demo para evitar reinicios de datos.",
            "path": request.path,
        }), 503
    return None


@app.before_request
def _capture_action_context():
    module_name = _audit_module_from_path(request.path)
    if not module_name:
        return
    g.audit_module_name = module_name
    g.audit_payload = _collect_request_payload()
    g.audit_entity_id = _extract_entity_id(module_name)


@app.after_request
def _persist_action_log(response):
    module_name = getattr(g, "audit_module_name", None)
    if not module_name:
        return response

    try:
        _db_insert_action_log(
            module_name=module_name,
            action_type=_action_type_from_method(request.method),
            entity_id=getattr(g, "audit_entity_id", None),
            status_code=response.status_code,
            payload=getattr(g, "audit_payload", None),
        )
    except Exception:
        # La auditoria no debe romper el flujo principal.
        pass
    return response


# =============================================================================
# RUTAS
# =============================================================================

@app.route("/")
def home():
    return redirect(url_for("login"))


# ── LOGIN / LOGOUT ────────────────────────────────────────────────────────────
@app.route("/login", methods=["GET", "POST"])
def login():
    if "user_name" in session:
        return redirect(url_for("dashboard"))

    if request.method == "POST":
        mail     = (request.form.get("mail") or "").strip()
        password = request.form.get("password") or ""
        user = None

        if _db_configured():
            user = _db_authenticate_worker(mail, password)

        if not user:
            user = USERS.get(mail)

        if user and (("password" in user and user["password"] == password) or "password" not in user):
            session["user_name"]     = user["name"]
            session["user_lastname"] = user["lastname"]
            session["role"]          = user["role"]
            session["worker_id"]     = user["worker_id"]
            flash(f"Bienvenido, {user['name']}.", "success")
            return redirect(url_for("dashboard"))

        flash("Credenciales inválidas. Usa tu email de worker y la contraseña real del seed SQL, o admin / 123.", "danger")

    return render_template("login_2daE.html")


@app.route("/logout")
def logout():
    nombre = session.get("user_name", "")
    session.clear()
    flash(f"Sesión de {nombre} cerrada correctamente.", "info")
    return redirect(url_for("login"))


# ── DASHBOARD ─────────────────────────────────────────────────────────────────
@app.route("/dashboard")
def dashboard():
    locked = _require_login()
    if locked:
        return locked

    patients_raw  = _cur_fetchall("patients")
    vaccines_raw  = _cur_fetchall("vaccines")
    records_raw   = _cur_fetchall("vaccination_records")
    alerts_raw    = _cur_fetchall("gps_risk_alerts")
    inventory_raw = _cur_fetchall("clinic_inventory")

    low_stock    = [i for i in inventory_raw if i["quantity"] < i["min_stock"]]
    top_patients = [_enrich_patient(p) for p in patients_raw[:3]]

    session["last_visit"] = date.today().isoformat()

    ctx = {
        **_session_vars(),
        "today":              date.today().strftime("%d/%m/%Y"),
        "total_patients":     len(patients_raw),
        "total_vaccines":     len(vaccines_raw),
        "applications_today": sum(
            1 for r in records_raw if r["applied_date"] == date.today().isoformat()
        ),
        "pending_alerts":     len([al for al in alerts_raw if al["resolved_at"] is None]),
        "low_stock_count":    len(low_stock),
        "top_patients":       top_patients,
        "dashboard_vaccines": vaccines_raw[:3],
    }
    return render_template("index_2daE.html", **ctx)


# ── PACIENTES ─────────────────────────────────────────────────────────────────
@app.route("/pacientes")
def pacientes():
    locked = _require_login()
    if locked:
        return locked

    if _db_configured():
        patients = _db_list_patients_for_page()
    else:
        patients_raw = _cur_fetchall("patients")
        patients = [_enrich_patient(p) for p in patients_raw]

    return render_template(
        "pacientes_2daE.html",
        **_session_vars(),
        total_patients=len(patients),
        patients=patients,
    )


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

    if _db_configured():
        try:
            _db_sync_serial_sequence("guardians", "guardian_id")
            _db_sync_serial_sequence("guardian_phones", "phone_id")
            _db_sync_serial_sequence("guardian_emails", "email_id")
            _db_sync_serial_sequence("patients", "patient_id")
            _db_sync_serial_sequence("patient_guardian_relations", "relation_id")
            _db_sync_serial_sequence("allergies", "allergy_id")
            _db_sync_serial_sequence("patient_allergies", "patient_allergy_id")

            blood_type_id = _db_blood_type_id(payload.get("blood_type") or "O+") or 1
            raw_gender = (payload.get("gender") or "M").strip().upper()
            gender_map = {"MASCULINO": "M", "FEMENINO": "F"}
            gender = gender_map.get(raw_gender, raw_gender[:1] if raw_gender else "M")
            if gender not in {"M", "F", "O"}:
                gender = "O"

            tutor_name = (tutor.get("name") or "Tutor").strip()
            tutor_lastname = (tutor.get("lastname") or "Demo").strip()
            guardian = _db_query_one(
                """
                INSERT INTO guardians (first_name, last_name, curp)
                VALUES (%s, %s, %s)
                RETURNING guardian_id
                """,
                (tutor_name, tutor_lastname, (tutor.get("curp") or None)),
            )
            guardian_id = guardian["guardian_id"]

            if tutor.get("number"):
                _db_execute(
                    """
                    INSERT INTO guardian_phones (guardian_id, phone, phone_type, is_primary)
                    VALUES (%s, %s, 'Celular', TRUE)
                    """,
                    (guardian_id, tutor.get("number")),
                )

            if tutor.get("mail"):
                _db_execute(
                    """
                    INSERT INTO guardian_emails (guardian_id, email, is_primary)
                    VALUES (%s, %s, TRUE)
                    """,
                    (guardian_id, tutor.get("mail")),
                )

            patient = _db_query_one(
                """
                INSERT INTO patients (first_name, last_name, birth_date, blood_type_id, gender, curp, weight_kg, premature)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                RETURNING patient_id
                """,
                (
                    first_name,
                    last_name,
                    payload.get("birth_date") or date.today().isoformat(),
                    blood_type_id,
                    gender,
                    payload.get("curp") or None,
                    payload.get("weight_kg") or None,
                    bool(payload.get("premature", False)),
                ),
            )
            new_pid = patient["patient_id"]

            _db_execute(
                "UPDATE patients SET nfc_token = %s WHERE patient_id = %s",
                (f"NFC{new_pid:03d}", new_pid),
            )

            _db_execute(
                """
                INSERT INTO patient_guardian_relations (patient_id, guardian_id, relation_type, is_primary, has_custody)
                VALUES (%s, %s, 'Tutor', TRUE, TRUE)
                """,
                (new_pid, guardian_id),
            )

            allergies_raw = (payload.get("allergies") or "").strip()
            if allergies_raw:
                for allergy_name in [a.strip() for a in allergies_raw.split(",") if a.strip()]:
                    allergy = _db_query_one(
                        "SELECT allergy_id FROM allergies WHERE LOWER(name) = LOWER(%s) LIMIT 1",
                        (allergy_name,),
                    )
                    if not allergy:
                        allergy = _db_query_one(
                            "INSERT INTO allergies (name, allergy_type) VALUES (%s, 'General') RETURNING allergy_id",
                            (allergy_name,),
                        )
                    _db_execute(
                        """
                        INSERT INTO patient_allergies (patient_id, allergy_id, severity, reaction_desc)
                        VALUES (%s, %s, %s, %s)
                        """,
                        (new_pid, allergy["allergy_id"], "Leve", None),
                    )
        except Exception as exc:  # pragma: no cover - depende del estado de BD
            return jsonify({"error": f"No se pudo registrar en PostgreSQL: {exc}"}), 500

        flash(f"Paciente {first_name} {last_name} registrado correctamente.", "success")
        return jsonify({"message": "Paciente registrado en PostgreSQL", "patient_id": new_pid})

    # Simular INSERT en guardians (sin second_last, marital_status/occupation como FK int)
    new_guardian_id = _next_id(GUARDIANS, "guardian_id")
    GUARDIANS.append({
        "guardian_id":       new_guardian_id,
        "first_name":        (tutor.get("name")    or "Tutor").strip(),
        "last_name":         (tutor.get("lastname") or "Demo").strip(),
        "curp":              None,
        "address_id":        None,
        "marital_status_id": None,
        "occupation":        None,
    })
    if tutor.get("number"):
        GUARDIAN_PHONES.append({
            "phone_id":   _next_id(GUARDIAN_PHONES, "phone_id"),
            "guardian_id": new_guardian_id,
            "phone":       tutor["number"],
            "phone_type":  "Celular",
            "is_primary":  True,
        })

    # Simular INSERT en patients (sin second_last, address_id, risk_level, is_active, registered_at)
    new_pid = _next_id(PATIENTS, "patient_id")
    PATIENTS.append({
        "patient_id":   new_pid,
        "first_name":   first_name,
        "last_name":    last_name,
        "curp":         payload.get("curp"),
        "birth_date":   payload.get("birth_date") or "2021-01-01",
        "gender":       payload.get("gender") or "M",
        "blood_type_id": 1,  # O+ por default
        "nfc_token":    f"NFC{new_pid:03d}",
        "weight_kg":    payload.get("weight_kg"),
        "premature":    bool(payload.get("premature", False)),
    })

    # Simular INSERT en patient_guardian_relations
    PATIENT_GUARDIAN_RELATIONS.append({
        "relation_id":   _next_id(PATIENT_GUARDIAN_RELATIONS, "relation_id"),
        "patient_id":    new_pid,
        "guardian_id":   new_guardian_id,
        "relation_type": "Tutor",
        "is_primary":    True,
        "has_custody":   True,
    })

    flash(f"Paciente {first_name} {last_name} registrado correctamente.", "success")
    return jsonify({"message": "Paciente registrado (demo)", "patient_id": new_pid})


@app.route("/delete_patient/<int:id>", methods=["POST"])
def delete_patient(id):
    locked = _require_login()
    if locked:
        return jsonify({"error": "No autenticado"}), 401

    if _db_configured():
        patient = _db_query_one(
            "SELECT patient_id, first_name, last_name FROM patients WHERE patient_id = %s LIMIT 1",
            (id,),
        )
        if not patient:
            return jsonify({"error": "Paciente no encontrado"}), 404

        try:
            _db_execute(
                "DELETE FROM scan_logs WHERE patient_id = %s",
                (id,),
            )
            _db_execute(
                "DELETE FROM nfc_scan_events WHERE nfc_card_id IN (SELECT nfc_card_id FROM nfc_cards WHERE patient_id = %s)",
                (id,),
            )
            _db_execute(
                "DELETE FROM nfc_cards WHERE patient_id = %s",
                (id,),
            )
            _db_execute(
                "DELETE FROM gps_locations WHERE patient_id = %s OR gps_device_id IN (SELECT gps_device_id FROM gps_devices WHERE patient_id = %s)",
                (id, id),
            )
            _db_execute(
                "DELETE FROM gps_risk_alerts WHERE patient_id = %s OR gps_device_id IN (SELECT gps_device_id FROM gps_devices WHERE patient_id = %s)",
                (id, id),
            )
            _db_execute("DELETE FROM gps_safe_zones WHERE patient_id = %s", (id,))
            _db_execute("DELETE FROM gps_devices WHERE patient_id = %s", (id,))
            _db_execute("DELETE FROM scheme_completion_alerts WHERE patient_id = %s", (id,))
            _db_execute("DELETE FROM patient_allergies WHERE patient_id = %s", (id,))
            _db_execute("DELETE FROM appointments WHERE patient_id = %s", (id,))
            _db_execute("DELETE FROM vaccination_records WHERE patient_id = %s", (id,))
            _db_execute("DELETE FROM patient_guardian_relations WHERE patient_id = %s", (id,))
            _db_execute("DELETE FROM patients WHERE patient_id = %s", (id,))
            _db_delete_nfc_bindings_for_entity("patient", id)
        except Exception as exc:  # pragma: no cover - depende del estado de BD
            return jsonify({"error": f"No se pudo eliminar en PostgreSQL: {exc}"}), 500

        nombre = f"{patient['first_name']} {patient['last_name']}".strip()
        flash(f"Paciente {nombre} eliminado.", "warning")
        return jsonify({"message": "Paciente eliminado en PostgreSQL"})

    patient = _cur_fetchone("patients", "patient_id", id)
    if not patient:
        return jsonify({"error": "Paciente no encontrado"}), 404

    PATIENTS.remove(patient)
    nombre = _patient_full_name(patient)

    for r in _cur_fetchall_where("vaccination_records", "patient_id", id):
        VACCINATION_RECORDS.remove(r)

    for rel in _cur_fetchall_where("patient_guardian_relations", "patient_id", id):
        PATIENT_GUARDIAN_RELATIONS.remove(rel)

    flash(f"Paciente {nombre} eliminado.", "warning")
    return jsonify({"message": "Paciente eliminado (demo)"})


# ── HISTORIAL ─────────────────────────────────────────────────────────────────
@app.route("/historial")
def historial():
    locked = _require_login()
    if locked:
        return locked

    patients_raw = _cur_fetchall("patients")
    patient      = _enrich_patient(patients_raw[0]) if patients_raw else None
    records_raw  = _cur_fetchall_where("vaccination_records", "patient_id", patient["patient_id"]) if patient else []
    records      = [_enrich_record(r) for r in records_raw]

    next_vaccines = _build_next_vaccines(patient["patient_id"]) if patient else []

    return render_template(
        "historial_2daE.html",
        **_session_vars(),
        patients=[_enrich_patient(p) for p in patients_raw],
        patient=patient,
        applications=records,
        next_vaccines=next_vaccines,
    )


@app.route("/historial/<int:id>")
def historial_paciente(id):
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

    session["last_patient_viewed"] = id

    return render_template(
        "historial_2daE.html",
        **_session_vars(),
        patients=[_enrich_patient(p) for p in _cur_fetchall("patients")],
        patient=patient,
        applications=records,
        next_vaccines=_build_next_vaccines(id),
    )


def _build_next_vaccines(patient_id):
    """Construye las próximas vacunas pendientes desde scheme_doses vs vaccination_records."""
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

    new_vid = _next_id(VACCINES, "vaccine_id")
    VACCINES.append({
        "vaccine_id":       new_vid,
        "name":             name,
        "commercial_name":  payload.get("commercial_name"),
        "manufacturer_id":  payload.get("manufacturer_id"),
        "via_id":           payload.get("via_id"),
        "ideal_age_months": payload.get("ideal_age_months"),
        "descripcion":      payload.get("descripcion") or "No especificado",
    })
    flash(f"Vacuna '{name}' registrada.", "success")
    return jsonify({"message": "Vacuna registrada (demo)", "vaccine_id": new_vid})


@app.route("/delete_vaccine/<int:id>", methods=["POST"])
def delete_vaccine(id):
    locked = _require_login()
    if locked:
        return jsonify({"error": "No autenticado"}), 401

    vaccine = _cur_fetchone("vaccines", "vaccine_id", id)
    if not vaccine:
        return jsonify({"error": "Vacuna no encontrada"}), 404

    VACCINES.remove(vaccine)
    flash(f"Vacuna '{vaccine['name']}' eliminada.", "warning")
    return jsonify({"message": "Vacuna eliminada (demo)"})


# ── APLICACIONES (VACCINATION RECORDS) ───────────────────────────────────────
@app.route("/aplicaciones")
def aplicaciones():
    locked = _require_login()
    if locked:
        return locked

    records_raw       = _cur_fetchall("vaccination_records")
    records           = [_enrich_record(r) for r in records_raw]
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
                new_record = {
                    "record_id":           _next_id(VACCINATION_RECORDS, "record_id"),
                    "patient_id":          patient_id,
                    "vaccine_id":          vaccine_id,
                    "worker_id":           worker_id or session.get("worker_id", 1),
                    "clinic_id":           1,
                    "lot_id":              None,
                    "scheme_dose_id":      scheme_dose_id,
                    "applied_date":        request.form.get("applied_date") or date.today().isoformat(),
                    "application_site_id": app_site_id,
                    "patient_temp_c":      request.form.get("patient_temp_c") or None,
                    "had_reaction":        request.form.get("had_reaction") == "true",
                }
                VACCINATION_RECORDS.insert(0, new_record)
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

    if _db_configured():
        workers = _db_list_workers_for_page()
    else:
        workers_raw = _cur_fetchall("workers")
        workers = []
        for w in workers_raw:
            row = dict(w)
            role = _cur_fetchone("roles", "role_id", w["role_id"])
            row["role"] = role["name"] if role else "Sin rol"
            row["name"] = w["first_name"]
            row["lastname"] = w["last_name"]
            row["mail"] = _worker_email(w["worker_id"])
            workers.append(row)

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

        if _db_configured():
            existing = _db_query_one(
                "SELECT 1 FROM worker_emails WHERE LOWER(email) = LOWER(%s) LIMIT 1",
                (mail,),
            )
            email_exists = bool(existing)
        else:
            email_exists = any(
                (e.get("email") or "").lower() == mail.lower()
                for e in _cur_fetchall("worker_emails")
            )

        if password != confirm:
            error = "Las contraseñas no coinciden"
            flash(error, "danger")
        elif email_exists:
            error = "El email ya existe en el sistema"
            flash(error, "danger")
        else:
            selected_role = (request.form.get("role") or "").strip()

            if _db_configured():
                role_id = _db_role_id_by_name(selected_role) or 3
                try:
                    _db_sync_serial_sequence("workers", "worker_id")
                    _db_sync_serial_sequence("worker_emails", "email_id")

                    new_worker = _db_query_one(
                        """
                        INSERT INTO workers (role_id, first_name, last_name, curp, birth_date, hire_date, password_hash)
                        VALUES (%s, %s, %s, %s, %s, %s, %s)
                        RETURNING worker_id
                        """,
                        (
                            role_id,
                            request.form.get("name", ""),
                            request.form.get("lastname", ""),
                            request.form.get("curp") or None,
                            request.form.get("birth_date") or None,
                            date.today().isoformat(),
                            _password_hash_for_storage(password),
                        ),
                    )
                    new_wid = new_worker["worker_id"]
                    _db_execute(
                        "INSERT INTO worker_emails (worker_id, email, is_primary) VALUES (%s, %s, TRUE)",
                        (new_wid, mail),
                    )
                except Exception as exc:  # pragma: no cover - depende del estado de BD
                    error = f"No se pudo registrar en PostgreSQL: {exc}"
                    flash(error, "danger")
                    return render_template(
                        "add_user_2daE.html",
                        **_session_vars(),
                        form=form,
                        error=error,
                        roles=_cur_fetchall("roles"),
                    )
            else:
                role_id = int(request.form.get("role_id") or 3)
                new_wid = _next_id(WORKERS, "worker_id")
                WORKERS.append({
                    "worker_id": new_wid,
                    "role_id": role_id,
                    "first_name": request.form.get("name", ""),
                    "last_name": request.form.get("lastname", ""),
                    "curp": None,
                    "address_id": None,
                    "birth_date": None,
                    "hire_date": date.today().isoformat(),
                    "password_hash": f"hash:{password}",
                })
                WORKER_EMAILS.append({
                    "email_id": _next_id(WORKER_EMAILS, "email_id"),
                    "worker_id": new_wid,
                    "email": mail,
                    "is_primary": True,
                })

            session["last_registered_worker"] = new_wid
            flash(
                f"Usuario {request.form.get('name', '')} registrado correctamente.",
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


@app.route("/personal/delete/<int:id>", methods=["POST"])
def delete_user(id):
    locked = _require_login()
    if locked:
        return jsonify({"error": "No autenticado"}), 401

    if session.get("worker_id") == id:
        return jsonify({"error": "No puedes eliminar tu propio usuario activo"}), 400

    if _db_configured():
        worker = _db_query_one(
            "SELECT worker_id, first_name, last_name FROM workers WHERE worker_id = %s LIMIT 1",
            (id,),
        )
        if not worker:
            return jsonify({"error": "Trabajador no encontrado"}), 404

        refs = _db_query_one("SELECT COUNT(*) AS total FROM vaccination_records WHERE worker_id = %s", (id,))
        if refs and refs.get("total", 0) > 0:
            return jsonify({"error": "No se puede eliminar: tiene aplicaciones de vacunas registradas"}), 409

        try:
            _db_execute("UPDATE appointments SET worker_id = NULL WHERE worker_id = %s", (id,))
            _db_execute("UPDATE post_vaccine_reactions SET reported_by = NULL WHERE reported_by = %s", (id,))
            _db_execute("UPDATE nfc_scan_events SET scanned_by = NULL WHERE scanned_by = %s", (id,))
            _db_execute("UPDATE nfc_cards SET issued_by = NULL WHERE issued_by = %s", (id,))
            _db_execute("UPDATE gps_devices SET assigned_by = NULL WHERE assigned_by = %s", (id,))
            _db_execute("UPDATE gps_risk_alerts SET resolved_by = NULL WHERE resolved_by = %s", (id,))
            _db_execute("UPDATE audit_log SET worker_id = NULL WHERE worker_id = %s", (id,))

            _db_execute("DELETE FROM worker_schedules WHERE worker_id = %s", (id,))
            _db_execute("DELETE FROM worker_clinic_assignment WHERE worker_id = %s", (id,))
            _db_execute("DELETE FROM worker_professional WHERE worker_id = %s", (id,))
            _db_execute("DELETE FROM worker_phones WHERE worker_id = %s", (id,))
            _db_execute("DELETE FROM worker_emails WHERE worker_id = %s", (id,))
            _db_execute("DELETE FROM workers WHERE worker_id = %s", (id,))
            _db_delete_nfc_bindings_for_entity("worker", id)
        except Exception as exc:  # pragma: no cover - depende del estado de BD
            return jsonify({"error": f"No se pudo eliminar en PostgreSQL: {exc}"}), 500
        nombre = f"{worker['first_name']} {worker['last_name']}".strip()
        flash(f"Trabajador {nombre} eliminado.", "warning")
        return jsonify({"message": "Trabajador eliminado en PostgreSQL"})

    worker = _cur_fetchone("workers", "worker_id", id)
    if not worker:
        return jsonify({"error": "Trabajador no encontrado"}), 404

    WORKERS.remove(worker)
    for e in list(_cur_fetchall_where("worker_emails", "worker_id", id)):
        WORKER_EMAILS.remove(e)
    for p in list(_cur_fetchall_where("worker_phones", "worker_id", id)):
        WORKER_PHONES.remove(p)

    nombre = f"{worker['first_name']} {worker['last_name']}".strip()
    flash(f"Trabajador {nombre} eliminado.", "warning")
    return jsonify({"message": "Trabajador eliminado (demo)"})


# ── REPORTES PÚBLICOS ─────────────────────────────────────────────────────────
@app.route("/reportes-publicos")
def reportes_publicos():
    locked = _require_login()
    if locked:
        return locked
    return render_template("reportesPublicos_2daE.html", **_session_vars())


# ── NFC BRIDGE (ANDROID -> WEB) ─────────────────────────────────────────────
@app.route("/nfc-bridge")
def nfc_bridge_page():
    """Página para administrar vinculaciones NFC - registrar nuevos tags."""
    locked = _require_login()
    if locked:
        return locked
    return render_template("nfc_bridge_2daE.html", **_session_vars())


@app.route("/nfc-register")
def nfc_register():
    """Página para capturar manualmente el UID de una tarjeta NFC y registrarlo."""
    locked = _require_login()
    if locked:
        return locked
    return render_template("registrarNFC_2daE.html", **_session_vars())


@app.route("/nfc-station")
def nfc_station():
    """Pantalla que espera escaneo NFC y ejecuta acciones automaticas en esta sesion."""
    return render_template(
        "nfcStation_2daE.html",
        logged_in="user_name" in session,
        user_name=session.get("user_name", ""),
        role=session.get("role", ""),
    )


# ── INVENTARIO ────────────────────────────────────────────────────────────────
@app.route("/inventario")
def inventario():
    locked = _require_login()
    if locked:
        return locked

    inventory_raw = _cur_fetchall("clinic_inventory")
    inventory = []
    for row in inventory_raw:
        item   = dict(row)
        supply = _cur_fetchone("supply_catalog", "supply_id", row["supply_id"])
        clinic = _cur_fetchone("clinics",        "clinic_id", row["clinic_id"])
        item["supply_name"]     = supply["name"]     if supply else "—"
        item["supply_unit"]     = supply["unit"]     if supply else "—"
        item["supply_category"] = supply["category"] if supply else "—"
        item["clinic_name"]     = clinic["name"]     if clinic else "—"
        item["low_stock"]       = row["quantity"] < row["min_stock"]
        inventory.append(item)

    if any(i["low_stock"] for i in inventory):
        flash("⚠ Hay insumos con stock por debajo del mínimo.", "warning")

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

    appointments_raw = _cur_fetchall("appointments")
    appointments = []
    for ap in appointments_raw:
        item    = dict(ap)
        patient = _cur_fetchone("patients", "patient_id", ap["patient_id"])
        worker  = _cur_fetchone("workers",  "worker_id",  ap["worker_id"])
        clinic  = _cur_fetchone("clinics",  "clinic_id",  ap["clinic_id"])
        area    = _cur_fetchone("clinic_areas", "area_id", ap.get("area_id")) if ap.get("area_id") else None
        item["patient_name"] = _patient_full_name(patient) if patient else "—"
        item["worker_name"]  = f"{worker['first_name']} {worker['last_name']}" if worker else "—"
        item["clinic_name"]  = clinic["name"] if clinic else "—"
        item["area_name"]    = area["name"]   if area   else "—"
        # vaccine_id ya no existe en appointments; se muestra el motivo
        item["vaccine_name"] = ap.get("reason") or "—"
        # normalizar nombres de campos para la plantilla
        item["status"]       = ap.get("appointment_status", "—")
        item["notes"]        = ap.get("appointment_notes", "")
        appointments.append(item)

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
    cards = []
    for c in cards_raw:
        item    = dict(c)
        patient = _cur_fetchone("patients", "patient_id", c["patient_id"])
        item["patient_name"] = _patient_full_name(patient) if patient else "—"
        # nfc_card_notes → notas en plantilla
        item["notes"] = c.get("nfc_card_notes")
        cards.append(item)

    scan_events_raw = _cur_fetchall("nfc_scan_events")
    scans = []
    for s in scan_events_raw:
        item = dict(s)
        item["worker_name"] = _worker_full_name(s["scanned_by"]) if s.get("scanned_by") else "—"
        card    = _cur_fetchone("nfc_cards", "nfc_card_id", s["nfc_card_id"])
        patient = _cur_fetchone("patients", "patient_id", card["patient_id"]) if card else None
        item["patient_name"] = _patient_full_name(patient) if patient else "—"
        # nfc_scan_result → result en plantilla
        item["result"] = s.get("nfc_scan_result")
        scans.append(item)

    return render_template(
        "nfc_2daE.html",
        **_session_vars(),
        cards=cards,
        scans=scans,
        total_cards=len(cards),
        active_cards=sum(1 for c in cards_raw if c["status"] == "Activa"),
    )


# ── GPS / ALERTAS ─────────────────────────────────────────────────────────────
@app.route("/gps")
def gps():
    locked = _require_login()
    if locked:
        return locked

    devices_raw = _cur_fetchall("gps_devices")
    devices = []
    for d in devices_raw:
        item    = dict(d)
        patient = _cur_fetchone("patients", "patient_id", d["patient_id"])
        item["patient_name"] = _patient_full_name(patient) if patient else "—"
        # gps_device_status → status en plantilla
        item["status"] = d.get("gps_device_status")
        devices.append(item)

    alerts_raw = _cur_fetchall("gps_risk_alerts")
    alerts = []
    for a in alerts_raw:
        item    = dict(a)
        patient = _cur_fetchone("patients", "patient_id", a["patient_id"])
        item["patient_name"]  = _patient_full_name(patient) if patient else "—"
        item["resolved_name"] = _worker_full_name(a["resolved_by"]) if a.get("resolved_by") else "Pendiente"
        # risk_notes → notes en plantilla
        item["notes"] = a.get("risk_notes")
        alerts.append(item)

    active_alerts = [a for a in alerts if a["resolved_at"] is None]
    if active_alerts:
        flash(f"Tienes {len(active_alerts)} alerta(s) GPS sin resolver.", "danger")

    return render_template(
        "gps_2daE.html",
        **_session_vars(),
        devices=devices,
        alerts=alerts,
        active_alerts_count=len(active_alerts),
        safe_zones=_cur_fetchall("gps_safe_zones"),
    )


# ── CLÍNICAS ──────────────────────────────────────────────────────────────────
@app.route("/clinicas")
def clinicas():
    locked = _require_login()
    if locked:
        return locked

    clinics_raw = _cur_fetchall("clinics")
    clinics = []
    for c in clinics_raw:
        item    = dict(c)
        address = _cur_fetchone("addresses", "address_id", c["address_id"])
        if address:
            nbhd = _cur_fetchone("neighborhoods", "neighborhood_id", address["neighborhood_id"])
            item["address_str"] = f"{address['street']} {address['ext_number'] or ''}, {nbhd['name'] if nbhd else ''}".strip(", ")
        else:
            item["address_str"] = "—"
        # Enriquecer áreas con nombre del tipo
        areas_raw = _cur_fetchall_where("clinic_areas", "clinic_id", c["clinic_id"])
        areas = []
        for a in areas_raw:
            area_item = dict(a)
            atype = _cur_fetchone("area_types", "area_type_id", a["area_type_id"])
            area_item["area_type"] = atype["area_type"] if atype else "—"
            areas.append(area_item)
        item["areas"] = areas
        clinics.append(item)

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

    records_raw  = _cur_fetchall("vaccination_records")
    patients_raw = _cur_fetchall("patients")
    total_doses  = len(records_raw)
    reached_pop  = len(set(r["patient_id"] for r in records_raw))
    target_pop   = max(len(patients_raw), 1)
    coverage     = (reached_pop / target_pop) * 100

    monthly = [
        {"period_label": "2026-01", "doses_applied": 1, "unique_patients": 1},
        {"period_label": "2026-02", "doses_applied": 1, "unique_patients": 1},
        {"period_label": "2026-03", "doses_applied": 3, "unique_patients": 3},
    ]

    vax_count  = {}
    vax_people = {}
    for r in records_raw:
        vname = _vaccine_name(r["vaccine_id"])
        vax_count[vname]  = vax_count.get(vname, 0) + 1
        vax_people.setdefault(vname, set()).add(r["patient_id"])

    vaccines_summary = [
        {
            "vaccine_name":    name,
            "doses_applied":   doses,
            "unique_patients": len(vax_people[name]),
            "share_percent":   round(doses / total_doses * 100, 1) if total_doses else 0,
        }
        for name, doses in vax_count.items()
    ]

    zones_raw = _cur_fetchall("zones")
    zones_summary = [
        {
            "zone_name":       z["name"],
            "doses_applied":   z["cases"],
            "unique_patients": z["cases"],
            "risk_level":      z["risk"],
            "risk_label":      {"high": "Alto", "medium": "Medio", "low": "Bajo"}.get(z["risk"], "—"),
        }
        for z in zones_raw
    ]

    payload = {
        "kpis": {
            "total_doses_applied": total_doses,
            "target_population":   target_pop,
            "reached_population":  reached_pop,
            "coverage_percent":    round(coverage, 1),
            "avg_delay_days":      5.0,
            "active_zones":        len(zones_raw),
        },
        "monthly":  monthly,
        "vaccines": vaccines_summary,
        "zones":    zones_summary,
    }
    return jsonify(payload)


@app.route("/api/nfc/ingest", methods=["GET", "POST"])
def api_nfc_ingest():
    """Recibe lecturas NFC desde Android (NFC Tools / atajos HTTP)."""
    token = (request.headers.get("X-NFC-Token") or request.args.get("token") or "").strip()
    # Si viene por adb reverse (localhost), permitir sin token para simplificar flujo USB local.
    if token != _nfc_bridge_token() and not _is_local_request():
        return jsonify({"ok": False, "error": "Token invalido"}), 401

    payload = request.get_json(silent=True) or {}

    # Compatibilidad con integraciones que solo envian query string.
    if not payload:
        payload = {
            "uid": request.args.get("uid") or request.args.get("nfc_id") or request.args.get("NFC_ID") or request.args.get("id") or request.args.get("tag"),
            "source": request.args.get("source"),
        }

    uid = _extract_nfc_uid(payload)
    if not uid:
        worker_id_input = payload.get("worker_id") or request.args.get("worker_id")
        if worker_id_input is not None and str(worker_id_input).strip().isdigit():
            uid = f"WORKER_ID:{int(worker_id_input)}"

    if not uid:
        raw_uid = request.data.decode("utf-8", errors="ignore").strip()
        if raw_uid:
            uid = raw_uid.upper()

    if not uid:
        return jsonify({"ok": False, "error": "No se encontro UID en la solicitud"}), 400

    if _looks_like_placeholder_uid(uid):
        return jsonify({
            "ok": False,
            "error": "El telefono envio un placeholder ({UID_TAG}) en vez del UID real. Revisa la variable del flujo Android.",
            "received_uid": uid,
        }), 400

    source = (payload.get("source") or request.user_agent.string or "android").strip()
    event = _record_nfc_event(uid=uid, source=source)
    binding = _find_nfc_binding(uid)
    command = _binding_command(binding)
    return jsonify({"ok": True, "event": event, "binding": binding, "command": command})


@app.route("/api/nfc/latest")
def api_nfc_latest():
    """Devuelve la ultima lectura NFC capturada por /api/nfc/ingest."""
    with NFC_BRIDGE_LOCK:
        latest = NFC_BRIDGE_STATE.get("latest")
        recent_events = NFC_BRIDGE_STATE.get("events", [])[:10]
    return jsonify({"ok": True, "latest": latest, "events": recent_events})


@app.route("/api/nfc/read", methods=["GET", "POST"])
def api_nfc_read():
    """Endpoint simplificado para NFC Tools u otras apps de lectura NFC.
    Acepta UID en formato: /api/nfc/read?id=3F:E9:2F:36 o /api/nfc/read/3FE92F36
    """
    uid = None
    
    # Intenta obtener UID desde query string (múltiples nombres posibles)
    for param in ["id", "uid", "nfc_id", "NFC_ID", "serial", "hex"]:
        uid = request.args.get(param, "").strip().upper()
        if uid:
            break
    
    # Si viene en path como /api/nfc/read/3FE92F36
    if not uid and request.path_info.startswith("/api/nfc/read/"):
        path_parts = request.path_info.split("/")
        if len(path_parts) > 3:
            uid = path_parts[3].strip().upper()
    
    # Si viene en JSON
    if not uid:
        data = request.get_json(silent=True) or {}
        uid = data.get("id") or data.get("uid") or data.get("serial")
        if uid:
            uid = str(uid).strip().upper()
    
    # Si viene en raw body
    if not uid:
        raw = request.data.decode("utf-8", errors="ignore").strip().upper()
        if raw and len(raw) > 3:
            uid = raw
    
    if not uid:
        return jsonify({"ok": False, "error": "No se envio UID. Usa: /api/nfc/read?id=3F:E9:2F:36"}), 400
    
    # Permite con o sin dos puntos (3F:E9:2F:36 o 3FE92F36)
    uid = uid.replace(":", "").replace(" ", "")
    
    source = (request.user_agent.string or "nfc_tools").strip()
    event = _record_nfc_event(uid=uid, source=source)
    binding = _find_nfc_binding(uid)
    command = _binding_command(binding)
    return jsonify({"ok": True, "event": event, "binding": binding, "command": command})


@app.route("/api/nfc/bindings")
def api_nfc_bindings():
    locked = _require_login()
    if locked:
        return jsonify({"ok": False, "error": "No autenticado"}), 401

    binding_source = _db_list_nfc_bindings() if _db_configured() else []
    bindings = []
    for b in binding_source:
        row = dict(b)
        if b["entity_type"] == "worker":
            if _db_configured():
                worker = _db_worker_by_id(b["entity_id"])
                row["entity_name"] = f"{worker['first_name']} {worker['last_name']}".strip() if worker else "Personal no encontrado"
            else:
                row["entity_name"] = _worker_full_name(b["entity_id"])
        else:
            if _db_configured():
                patient = _db_patient_by_id(b["entity_id"])
                row["entity_name"] = f"{patient['first_name']} {patient['last_name']}".strip() if patient else "Paciente no encontrado"
            else:
                patient = _cur_fetchone("patients", "patient_id", b["entity_id"])
                row["entity_name"] = _patient_full_name(patient) if patient else "Paciente no encontrado"
        bindings.append(row)
    return jsonify({"ok": True, "bindings": bindings})


@app.route("/api/nfc/bind", methods=["POST"])
def api_nfc_bind():
    locked = _require_login()
    if locked:
        return jsonify({"ok": False, "error": "No autenticado"}), 401

    payload = request.get_json(silent=True) or {}
    worker_id_payload = payload.get("worker_id")
    raw_uid = str(payload.get("uid") or payload.get("nfc_id") or payload.get("NFC_ID") or "").strip().upper()
    if not raw_uid and worker_id_payload is not None and str(worker_id_payload).strip().isdigit():
        raw_uid = f"WORKER_ID:{int(worker_id_payload)}"
    uid_norm = _normalize_uid(raw_uid)
    entity_type = (payload.get("entity_type") or "").strip().lower()
    if not entity_type and worker_id_payload is not None:
        entity_type = "worker"
    label = (payload.get("label") or "").strip()

    if not uid_norm:
        return jsonify({"ok": False, "error": "UID requerido"}), 400
    if entity_type not in {"worker", "patient"}:
        return jsonify({"ok": False, "error": "entity_type debe ser worker o patient"}), 400

    try:
        if worker_id_payload is not None and str(worker_id_payload).strip().isdigit():
            entity_id = int(worker_id_payload)
        else:
            entity_id = int(payload.get("entity_id"))
    except (TypeError, ValueError):
        return jsonify({"ok": False, "error": "entity_id invalido"}), 400

    if entity_type == "worker":
        entity = _db_worker_by_id(entity_id) if _db_configured() else _cur_fetchone("workers", "worker_id", entity_id)
    else:
        entity = _db_patient_by_id(entity_id) if _db_configured() else _cur_fetchone("patients", "patient_id", entity_id)

    if not entity:
        return jsonify({"ok": False, "error": "Entidad no encontrada"}), 404

    if _db_configured():
        binding = _db_upsert_nfc_binding(raw_uid, uid_norm, entity_type, entity_id, label)
    else:
        return jsonify({"ok": False, "error": "Base de datos no disponible para guardar vinculaciones NFC"}), 503

    return jsonify({"ok": True, "binding": binding})


@app.route("/api/nfc/bind", methods=["DELETE"])
def api_nfc_unbind():
    locked = _require_login()
    if locked:
        return jsonify({"ok": False, "error": "No autenticado"}), 401

    payload = request.get_json(silent=True) or {}
    raw_uid = str(payload.get("uid") or payload.get("nfc_id") or payload.get("NFC_ID") or "").strip().upper()
    uid_norm = _normalize_uid(raw_uid)
    if not uid_norm:
        return jsonify({"ok": False, "error": "UID requerido para borrar"}), 400

    if _db_configured():
        removed = _db_delete_nfc_binding(uid_norm)
    else:
        return jsonify({"ok": False, "error": "Base de datos no disponible para borrar vinculaciones NFC"}), 503
    if removed <= 0:
        return jsonify({"ok": False, "error": "No se encontro vinculacion para ese UID"}), 404

    return jsonify({"ok": True, "removed": removed, "uid": raw_uid})


@app.route("/api/nfc/command/login-worker", methods=["GET", "POST"])
def api_nfc_command_login_worker():
    return api_nfc_command_resolve()


@app.route("/api/nfc/command/resolve", methods=["GET", "POST"])
def api_nfc_command_resolve():
    """Resuelve un identificador NFC o worker_id y devuelve un command para trabajador o paciente."""
    token = (request.headers.get("X-NFC-Token") or request.args.get("token") or "").strip()
    if token != _nfc_bridge_token():
        return jsonify({"ok": False, "error": "Token invalido"}), 401

    payload = request.get_json(silent=True) or {}
    raw_input = (
        payload.get("worker_id")
        or payload.get("uid")
        or payload.get("nfc_id")
        or payload.get("NFC_ID")
        or request.args.get("worker_id")
        or request.args.get("uid")
        or request.args.get("nfc_id")
        or request.args.get("NFC_ID")
    )
    match = _nfc_match_from_input(raw_input)
    if not match:
        return jsonify({"ok": False, "error": "Identificador no encontrado"}), 404

    event = _record_nfc_event(uid=match["uid"], source="command-resolve")
    command = _binding_command(match)
    if not command:
        return jsonify({"ok": False, "error": "No se pudo construir el command"}), 500

    return jsonify({"ok": True, "event": event, "binding": match, "command": command})


@app.route("/api/nfc/station/poll")
def api_nfc_station_poll():
    """Consume el ultimo evento NFC nuevo y devuelve accion para esta sesion de navegador."""
    since = request.args.get("since", "0")
    try:
        since_id = int(since)
    except ValueError:
        since_id = 0

    with NFC_BRIDGE_LOCK:
        next_event = next(
            (ev for ev in NFC_BRIDGE_STATE.get("events", []) if ev.get("event_id", 0) > since_id),
            None,
        )

    if not next_event:
        return jsonify({"ok": True, "action": "none", "last_event_id": since_id})

    uid = next_event.get("uid")
    binding = _find_nfc_binding(uid)
    if not binding:
        return jsonify({
            "ok": True,
            "action": "unlinked",
            "last_event_id": next_event.get("event_id", since_id),
            "uid": uid,
            "message": "UID sin vincular. Vinculalo en NFC Bridge.",
            "command": None,
        })

    if binding["entity_type"] == "worker":
        ok = _set_session_from_worker(binding["entity_id"])
        if not ok:
            return jsonify({
                "ok": True,
                "action": "error",
                "last_event_id": next_event.get("event_id", since_id),
                "message": "No se pudo cargar el medico vinculado.",
            })

        command = _binding_command(binding)
        return jsonify({
            "ok": True,
            "action": "worker_login",
            "last_event_id": next_event.get("event_id", since_id),
            "message": f"Sesion iniciada: {_worker_full_name(binding['entity_id'])}",
            "redirect_url": url_for("dashboard"),
            "command": command,
        })

    # Patient tag
    if "user_name" not in session:
        return jsonify({
            "ok": True,
            "action": "need_worker_login",
            "last_event_id": next_event.get("event_id", since_id),
            "message": "Escanea primero un gafete de medico para iniciar sesion.",
            "command": _binding_command(binding),
        })

    patient = _cur_fetchone("patients", "patient_id", binding["entity_id"])
    patient_name = _patient_full_name(patient) if patient else "Paciente"
    return jsonify({
        "ok": True,
        "action": "open_patient",
        "last_event_id": next_event.get("event_id", since_id),
        "message": f"Abriendo expediente: {patient_name}",
        "redirect_url": url_for("historial_paciente", id=binding["entity_id"]),
        "command": _binding_command(binding),
    })


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


@app.route("/api/workers-list")
def api_workers_list():
    """Devuelve lista de trabajadores para el puente NFC."""
    locked = _require_login()
    if locked:
        return jsonify({"ok": False, "error": "No autenticado"}), 401

    if _db_configured():
        workers_raw = _db_list_workers_for_page() or []
    else:
        workers_raw = _cur_fetchall("workers") or []
    
    workers = []
    for w in workers_raw:
        # Handle both DB and non-DB field names
        first_name = w.get("first_name") or w.get("name", "")
        last_name = w.get("last_name") or w.get("lastname", "")
        workers.append({
            "worker_id": w["worker_id"],
            "name": first_name,
            "lastname": last_name,
            "first_name": first_name,
            "last_name": last_name,
            "full_name": f"{first_name} {last_name}".strip(),
        })
    return jsonify({"ok": True, "workers": workers})


@app.route("/api/patients-list")
def api_patients_list():
    """Devuelve lista de pacientes para el puente NFC."""
    locked = _require_login()
    if locked:
        return jsonify({"ok": False, "error": "No autenticado"}), 401

    if _db_configured():
        patients_raw = _db_list_patients_for_page() or []
    else:
        patients_raw = _cur_fetchall("patients") or []
    
    patients = []
    for p in patients_raw:
        first_name = p.get("first_name", "")
        last_name = p.get("last_name", "")
        patients.append({
            "patient_id": p["patient_id"],
            "first_name": first_name,
            "last_name": last_name,
            "full_name": f"{first_name} {last_name}".strip(),
        })
    return jsonify({"ok": True, "patients": patients})


if __name__ == "__main__":
    app.run(debug=True)