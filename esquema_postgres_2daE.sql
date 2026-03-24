-- BASE DE DATOS: sistema_vacunacion

--- ADDRESSES ---
--- Reemplaza: guardians.address, workers.address (VARCHAR libre)

CREATE TABLE IF NOT EXISTS countries (
    country_id  SERIAL          PRIMARY KEY,
    name        VARCHAR(100)    NOT NULL,
    iso_code    CHAR(2)         NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS states (
    state_id    SERIAL          PRIMARY KEY,
    country_id  INT             NOT NULL REFERENCES countries(country_id),
    name        VARCHAR(100)    NOT NULL,
    code        VARCHAR(10)
);

CREATE TABLE IF NOT EXISTS municipalities (
    municipality_id SERIAL      PRIMARY KEY,
    state_id        INT         NOT NULL REFERENCES states(state_id),
    name            VARCHAR(100) NOT NULL
);

CREATE TABLE IF NOT EXISTS neighborhoods (
    neighborhood_id SERIAL      PRIMARY KEY,
    municipality_id INT         NOT NULL REFERENCES municipalities(municipality_id),
    name            VARCHAR(150) NOT NULL,
    zip_code        VARCHAR(10)
);

CREATE TABLE IF NOT EXISTS addresses (
    address_id      SERIAL          PRIMARY KEY,
    neighborhood_id INT             NOT NULL REFERENCES neighborhoods(neighborhood_id),
    street          VARCHAR(200)    NOT NULL,
    ext_number      VARCHAR(20),
    cross_street_1  VARCHAR(200),
    cross_street_2  VARCHAR(200),
    latitude        DECIMAL(10,7),
    longitude       DECIMAL(10,7),
);

--- CLINICS ---
--- Reemplaza: vaccination_records.clinic_location (VARCHAR libre)

CREATE TABLE IF NOT EXISTS clinics (
    clinic_id        SERIAL          PRIMARY KEY,
    name             VARCHAR(150)    NOT NULL,
    clues            VARCHAR(20)     UNIQUE,
    address_id       INT             NOT NULL REFERENCES addresses(address_id),
    phone            VARCHAR(20),
    institution_type VARCHAR(50)     CHECK (institution_type IN
                       ('IMSS','ISSSTE','SSA','PRIVADA','DIF','OTRA')),
    is_active        BOOLEAN         DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS clinic_areas (
    area_id     SERIAL          PRIMARY KEY,
    clinic_id   INT             NOT NULL REFERENCES clinics(clinic_id) ON DELETE CASCADE,
    name        VARCHAR(100)    NOT NULL,
    area_type   VARCHAR(50)     NOT NULL CHECK (area_type IN (
                    'Recepcion','Sala_Espera','Consultorio','Almacen',
                    'Enfermeria','Laboratorio','Oficina','Farmacia','Otro')),
    floor       SMALLINT        DEFAULT 1,
    capacity    SMALLINT
);

CREATE TABLE IF NOT EXISTS equipment_catalog (
    equipment_id          SERIAL          PRIMARY KEY,
    name                  VARCHAR(150)    NOT NULL,
    category              VARCHAR(80)     NOT NULL,
    description           TEXT,
    requires_calibration  BOOLEAN         DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS area_equipment (
    area_equipment_id   SERIAL          PRIMARY KEY,
    area_id             INT             NOT NULL REFERENCES clinic_areas(area_id) ON DELETE CASCADE,
    equipment_id        INT             NOT NULL REFERENCES equipment_catalog(equipment_id),
    quantity            SMALLINT        NOT NULL DEFAULT 1 CHECK (quantity > 0),
    serial_number       VARCHAR(100),
    condition           VARCHAR(30)     CHECK (condition IN ('Bueno','Regular','Deteriorado','En_Reparacion','Baja')),
);

--- WORKERS ---
--- Reemplaza: workers.role (CHECK hardcodeado), workers.address (VARCHAR)

CREATE TABLE IF NOT EXISTS roles (
    role_id     SERIAL          PRIMARY KEY,
    name        VARCHAR(50)     NOT NULL UNIQUE,
    description TEXT
);

CREATE TABLE IF NOT EXISTS workers (
    worker_id       SERIAL          PRIMARY KEY,
    role_id         INT             NOT NULL REFERENCES roles(role_id),
    first_name      VARCHAR(80)     NOT NULL,
    last_name       VARCHAR(80)     NOT NULL,
    second_last     VARCHAR(80),
    curp            CHAR(18)        UNIQUE,
    email           VARCHAR(100)    NOT NULL UNIQUE,
    phone           VARCHAR(20),
    address_id      INT             REFERENCES addresses(address_id),
    birth_date      DATE,
    hire_date       DATE,
    is_active       BOOLEAN         DEFAULT TRUE,
    password_hash   VARCHAR(255),
    created_at      TIMESTAMPTZ     DEFAULT NOW(),
    updated_at      TIMESTAMPTZ     DEFAULT NOW()
);

-- Datos profesionales solo para médicos y enfermeros
CREATE TABLE IF NOT EXISTS worker_professional (
    worker_id            INT             PRIMARY KEY REFERENCES workers(worker_id),
    cedula_profesional   VARCHAR(20)     NOT NULL,
    specialty            VARCHAR(100),
    institution_title    VARCHAR(150),
    specialty  VARCHAR(20)
);

-- Asignación de trabajador a clínica y área (consultorio)
CREATE TABLE IF NOT EXISTS worker_clinic_assignment (
    assignment_id   SERIAL      PRIMARY KEY,
    worker_id       INT         NOT NULL REFERENCES workers(worker_id),
    clinic_id       INT         NOT NULL REFERENCES clinics(clinic_id),
    area_id         INT         REFERENCES clinic_areas(area_id),
    start_date      DATE        NOT NULL,
    end_date        DATE,
    is_active       BOOLEAN     DEFAULT TRUE,
    UNIQUE (worker_id, clinic_id, start_date)
);

-- Horarios por trabajador, clínica y día
CREATE TABLE IF NOT EXISTS worker_schedules (
    schedule_id SERIAL          PRIMARY KEY,
    worker_id   INT             NOT NULL REFERENCES workers(worker_id),
    clinic_id   INT             NOT NULL REFERENCES clinics(clinic_id),
    day_of_week SMALLINT        NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),
    entry_time  TIME            NOT NULL,
    exit_time   TIME            NOT NULL,
    shift_type  VARCHAR(20)     CHECK (shift_type IN ('Matutino','Vespertino','Nocturno','Mixto')),
    CONSTRAINT chk_schedule_times CHECK (exit_time > entry_time)
);

--- GUARDIANS ---
--- Reemplaza: guardians.address, guardians.number, guardians.mail

CREATE TABLE IF NOT EXISTS guardians (
    guardian_id     SERIAL          PRIMARY KEY,
    first_name      VARCHAR(80)     NOT NULL,
    last_name       VARCHAR(80)     NOT NULL,
    second_last     VARCHAR(80),
    curp            CHAR(18)        UNIQUE,
    address_id      INT             REFERENCES addresses(address_id),
    marital_status  VARCHAR(30)     CHECK (marital_status IN (
                        'Soltero','Casado','Divorciado','Viudo','Union_Libre','Otro')),
    occupation      VARCHAR(100),
    created_at      TIMESTAMPTZ     DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS guardian_phones (
    phone_id    SERIAL          PRIMARY KEY,
    guardian_id INT             NOT NULL REFERENCES guardians(guardian_id) ON DELETE CASCADE,
    phone       VARCHAR(20)     NOT NULL,
    phone_type  VARCHAR(20)     CHECK (phone_type IN ('Celular','Casa','Trabajo','Emergencia')),
    is_primary  BOOLEAN         DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS guardian_emails (
    email_id    SERIAL          PRIMARY KEY,
    guardian_id INT             NOT NULL REFERENCES guardians(guardian_id) ON DELETE CASCADE,
    email       VARCHAR(100)    NOT NULL,
    is_primary  BOOLEAN         DEFAULT FALSE
);

--- PATIENTS ---
--- Reemplaza: patients.allergies (TEXT libre), nfc_token sin soporte

CREATE TABLE IF NOT EXISTS patients (
    patient_id          SERIAL          PRIMARY KEY,
    first_name          VARCHAR(80)     NOT NULL,
    last_name           VARCHAR(80)     NOT NULL,
    second_last         VARCHAR(80),
    birth_date          DATE            NOT NULL,
    birth_place         VARCHAR(150),
    blood_type          VARCHAR(3)      CHECK (blood_type IN ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
    gender              CHAR(1)         CHECK (gender IN ('M','F')),
    nfc_token           VARCHAR(50)     UNIQUE,
    curp                CHAR(18)        UNIQUE,
    weight_kg           DECIMAL(5,2),
    premature           BOOLEAN         DEFAULT FALSE,
    is_active           BOOLEAN         DEFAULT TRUE,
    created_at          TIMESTAMPTZ     DEFAULT NOW(),
    updated_at          TIMESTAMPTZ     DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS allergy_catalog (
    allergy_id      SERIAL          PRIMARY KEY,
    name            VARCHAR(150)    NOT NULL UNIQUE,
    allergy_type    VARCHAR(50)     CHECK (allergy_type IN ('Medicamento','Alimento','Ambiental','Latex','Otro'))
);

CREATE TABLE IF NOT EXISTS patient_allergies (
    patient_allergy_id  SERIAL          PRIMARY KEY,
    patient_id          INT             NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,
    allergy_id          INT             NOT NULL REFERENCES allergy_catalog(allergy_id),
    severity            VARCHAR(20)     CHECK (severity IN ('Leve','Moderada','Severa','Anafilaxia')),
    reaction_desc       TEXT,
    diagnosed_date      DATE,
    UNIQUE (patient_id, allergy_id)
);

-- Relación paciente - tutor con tipo de parentesco y custodia
CREATE TABLE IF NOT EXISTS patient_guardian_relations (
    relation_id     SERIAL          PRIMARY KEY,
    patient_id      INT             NOT NULL REFERENCES patients(patient_id) ON DELETE CASCADE,
    guardian_id     INT             NOT NULL REFERENCES guardians(guardian_id) ON DELETE CASCADE,
    relation_type   VARCHAR(50)     NOT NULL CHECK (relation_type IN ('Padre','Madre','Abuelo','Abuela','Tio','Tia','Hermano','Hermana','Tutor_Legal','Otro')),
    is_primary      BOOLEAN         DEFAULT FALSE,
    has_custody     BOOLEAN         DEFAULT TRUE,
    UNIQUE (patient_id, guardian_id)
);

--- APPOINTMENTS ---
--- Nuevo módulo — no existía en el diseño original

CREATE TABLE IF NOT EXISTS appointments (
    appointment_id  SERIAL          PRIMARY KEY,
    patient_id      INT             NOT NULL REFERENCES patients(patient_id),
    clinic_id       INT             NOT NULL REFERENCES clinics(clinic_id),
    area_id         INT             REFERENCES clinic_areas(area_id),
    worker_id       INT             REFERENCES workers(worker_id),
    scheduled_at    TIMESTAMPTZ     NOT NULL,
    duration_min    SMALLINT        DEFAULT 20,
    reason          TEXT,
    status          VARCHAR(20)     NOT NULL DEFAULT 'Pendiente' CHECK (status IN ('Pendiente','Confirmada','En_Curso','Completada','Cancelada','No_Asistio')),
    notes           TEXT,
    created_at      TIMESTAMPTZ     DEFAULT NOW()
);

--- VACCINES ---
--- Reemplaza: vaccines.inventory (2FN), vaccines.manufacturer (3FN)

CREATE TABLE IF NOT EXISTS manufacturers (
    manufacturer_id SERIAL          PRIMARY KEY,
    name            VARCHAR(150)    NOT NULL UNIQUE,
    country_id      INT             REFERENCES countries(country_id),
    contact_email   VARCHAR(100),
    website         VARCHAR(200)
);

CREATE TABLE IF NOT EXISTS vaccines (
    vaccine_id              SERIAL          PRIMARY KEY,
    name                    VARCHAR(150)    NOT NULL,
    commercial_name         VARCHAR(150),
    manufacturer_id         INT             REFERENCES manufacturers(manufacturer_id),
    via                     VARCHAR(30)     CHECK (via IN ('Intramuscular','Subcutanea','Oral','Intradermica','Nasal')),
    ideal_age_months          SMALLINT,
    description             TEXT,
    diseases_prevented      TEXT,
    storage_temp_min        DECIMAL(4,1),
    storage_temp_max        DECIMAL(4,1),
    is_active               BOOLEAN         DEFAULT TRUE,
    CONSTRAINT chk_age_range CHECK (
        max_age_months IS NULL OR max_age_months >= min_age_months
    )
);

CREATE TABLE IF NOT EXISTS vaccine_lots (
    lot_id              SERIAL          PRIMARY KEY,
    vaccine_id          INT             NOT NULL REFERENCES vaccines(vaccine_id),
    clinic_id           INT             NOT NULL REFERENCES clinics(clinic_id),
    lot_number          VARCHAR(80)     NOT NULL,
    quantity_received   INT             NOT NULL CHECK (quantity_received > 0),
    quantity_available  INT             NOT NULL DEFAULT 0 CHECK (quantity_available >= 0),
    expiration_date     DATE            NOT NULL,
    received_date       DATE            NOT NULL DEFAULT CURRENT_DATE,
    received_by         INT             REFERENCES workers(worker_id),
    is_active           BOOLEAN         DEFAULT TRUE,
    CONSTRAINT chk_lot_dates CHECK (expiration_date > COALESCE(manufacture_date, expiration_date - 1)),
    UNIQUE (lot_number, vaccine_id)
);

--- OFFICIAL VACCINATION SCHEME ---
--- Reemplaza: vaccination_scheme (sin versión)

CREATE TABLE IF NOT EXISTS vaccination_schemes (
    scheme_id       SERIAL          PRIMARY KEY,
    name            VARCHAR(150)    NOT NULL,
    issuing_body    VARCHAR(100),
    year            SMALLINT        NOT NULL,
    is_current      BOOLEAN         DEFAULT FALSE,
);

CREATE TABLE IF NOT EXISTS scheme_doses (
    dose_id             SERIAL          PRIMARY KEY,
    scheme_id           INT             NOT NULL REFERENCES vaccination_schemes(scheme_id),
    vaccine_id          INT             NOT NULL REFERENCES vaccines(vaccine_id),
    dose_number         SMALLINT        NOT NULL,
    dose_label          VARCHAR(50),
    ideal_age_months    SMALLINT        NOT NULL,
    min_interval_days   SMALLINT        DEFAULT 0,
    is_mandatory        BOOLEAN         DEFAULT TRUE,
    UNIQUE (scheme_id, vaccine_id, dose_number)
);

--- VACCINATION RECORD ---
--- Reemplaza: vaccination_records.clinic_location (VARCHAR)
--- vaccination_records.lot_number (texto libre)
--- vaccination_records.dose_applied (texto libre)

CREATE TABLE IF NOT EXISTS vaccination_records (
    record_id           SERIAL          PRIMARY KEY,
    patient_id          INT             NOT NULL REFERENCES patients(patient_id),
    vaccine_id          INT             NOT NULL REFERENCES vaccines(vaccine_id),
    worker_id           INT             NOT NULL REFERENCES workers(worker_id),
    clinic_id           INT             NOT NULL REFERENCES clinics(clinic_id),
    area_id             INT             REFERENCES clinic_areas(area_id),
    appointment_id      INT             REFERENCES appointments(appointment_id),
    lot_id              INT             NOT NULL REFERENCES vaccine_lots(lot_id),
    scheme_dose_id      INT             REFERENCES scheme_doses(dose_id),
    applied_date        DATE            NOT NULL,
    applied_time        TIME,
    dose_ml             DECIMAL(4,2),
    application_site    VARCHAR(50)     CHECK (application_site IN (
                            'Muslo_Der','Muslo_Izq','Brazo_Der','Brazo_Izq',
                            'Gluteo_Der','Gluteo_Izq','Oral','Nasal','Intradermica')),
    patient_temp_c      DECIMAL(4,1),
    reaction_severity   VARCHAR(20)     CHECK (reaction_severity IN (
                            'Ninguna','Leve','Moderada','Severa')),
    notes               TEXT,
    is_cancelled        BOOLEAN         DEFAULT FALSE,
    cancel_reason       TEXT,
    created_at          TIMESTAMPTZ     DEFAULT NOW()
);

-- ALERTS AND AUDITS
-- Nuevo — requerido

CREATE TABLE IF NOT EXISTS post_vaccine_reactions (
    reaction_id         SERIAL          PRIMARY KEY,
    record_id           INT             NOT NULL REFERENCES vaccination_records(record_id),
    reported_by         INT             REFERENCES workers(worker_id),
    reported_at         TIMESTAMPTZ     DEFAULT NOW(),
    symptom             VARCHAR(150)    NOT NULL,
    severity            VARCHAR(20)     CHECK (severity IN ('Leve','Moderada','Severa','Critica')),
    onset_hours         SMALLINT,
    resolved_at         TIMESTAMPTZ,
    treatment           TEXT,
    notified_authority  BOOLEAN         DEFAULT FALSE
);


CREATE TABLE IF NOT EXISTS scheme_completion_alerts (
    alert_id        SERIAL          PRIMARY KEY,
    patient_id      INT             NOT NULL REFERENCES patients(patient_id),
    scheme_dose_id  INT             NOT NULL REFERENCES scheme_doses(dose_id),
    due_date        DATE            NOT NULL,
    status          VARCHAR(20)     NOT NULL DEFAULT 'Pendiente' CHECK (status IN (
                        'Pendiente','Aplicada','Vencida','Omitida')),
    notified_at     TIMESTAMPTZ,
    notified_by     INT             REFERENCES workers(worker_id),
    resolved_at     TIMESTAMPTZ,
    notes           TEXT,
    UNIQUE (patient_id, scheme_dose_id)
);


CREATE TABLE IF NOT EXISTS audit_log (
    audit_id    BIGSERIAL       PRIMARY KEY,
    table_name  VARCHAR(80)     NOT NULL,
    record_id   INT             NOT NULL,
    action      VARCHAR(10)     NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
    worker_id   INT             REFERENCES workers(worker_id),
    changed_at  TIMESTAMPTZ     DEFAULT NOW(),
    old_data    JSONB,
    new_data    JSONB,
    ip_address  INET
);

--- NFC — IDENTIFICACIÓN DE NIÑOS ---
-- Reemplaza: patients.nfc_token (VARCHAR sin soporte)

CREATE TABLE IF NOT EXISTS nfc_devices (
    device_id       VARCHAR(30)     PRIMARY KEY,
    clinic_id       INT             NOT NULL REFERENCES clinics(clinic_id),
    area_id         INT             REFERENCES clinic_areas(area_id),
    device_name     VARCHAR(100)    NOT NULL,
    model           VARCHAR(50),
    serial_number   VARCHAR(50),
    status          VARCHAR(20)     NOT NULL DEFAULT 'Activo' CHECK (status IN (
                        'Activo','Inactivo','En_Reparacion')),
    registered_at   DATE            DEFAULT CURRENT_DATE
);

CREATE TABLE IF NOT EXISTS nfc_cards (
    nfc_card_id     SERIAL          PRIMARY KEY,
    patient_id      INT             NOT NULL REFERENCES patients(patient_id),
    uid             VARCHAR(30)     NOT NULL UNIQUE,
    card_type       VARCHAR(20)     NOT NULL CHECK (card_type IN (
                        'Tarjeta','Pulsera','Llavero','Sticker')),
    issued_date     DATE            NOT NULL DEFAULT CURRENT_DATE,
    issued_by       INT             NOT NULL REFERENCES workers(worker_id),
    status          VARCHAR(20)     NOT NULL DEFAULT 'Activa' CHECK (status IN (
                        'Activa','Desactivada','Extraviada','Vencida')),
    last_scanned_at TIMESTAMPTZ,
    notes           TEXT
);

CREATE TABLE IF NOT EXISTS nfc_scan_events (
    scan_event_id       SERIAL          PRIMARY KEY,
    nfc_card_id         INT             NOT NULL REFERENCES nfc_cards(nfc_card_id),
    scanned_by          INT             REFERENCES workers(worker_id),
    clinic_id           INT             NOT NULL REFERENCES clinics(clinic_id),
    area_id             INT             REFERENCES clinic_areas(area_id),
    device_id           VARCHAR(30)     REFERENCES nfc_devices(device_id),
    scanned_at          TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    action_triggered    VARCHAR(80)     CHECK (action_triggered IN (
                            'Abrir_Expediente','Registrar_Llegada',
                            'Confirmar_Vacunacion','Verificar_Alergias','Otro')),
    result              VARCHAR(100),
    CONSTRAINT chk_scan_result CHECK (result IS NOT NULL)
);

-- GPS ---
-- Nuevo módulo — identificación de niños fuera de zonas seguras,
-- sin señal o con inasistencia a citas programadas

CREATE TABLE IF NOT EXISTS gps_devices (
    gps_device_id   SERIAL          PRIMARY KEY,
    patient_id      INT             NOT NULL REFERENCES patients(patient_id),
    device_type     VARCHAR(30)     NOT NULL CHECK (device_type IN (
                        'Pulsera_GPS','App_Tutor','Mochila_GPS','Otro')),
    model           VARCHAR(50),
    imei            VARCHAR(20)     UNIQUE,
    assigned_date   DATE            NOT NULL DEFAULT CURRENT_DATE,
    assigned_by     INT             NOT NULL REFERENCES workers(worker_id),
    battery_pct     SMALLINT        CHECK (battery_pct BETWEEN 0 AND 100),
    status          VARCHAR(20)     NOT NULL DEFAULT 'Activo' CHECK (status IN (
                        'Activo','Inactivo','Perdido','Sin_Señal'))
);

CREATE TABLE IF NOT EXISTS gps_locations (
    location_id     BIGSERIAL       PRIMARY KEY,
    gps_device_id   INT             NOT NULL REFERENCES gps_devices(gps_device_id),
    patient_id      INT             NOT NULL REFERENCES patients(patient_id),
    latitude        DECIMAL(10,7)   NOT NULL,
    longitude       DECIMAL(10,7)   NOT NULL,
    accuracy_m      SMALLINT,
    recorded_at     TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    speed_kmh       DECIMAL(5,2),
    altitude_m      DECIMAL(7,2)
);

CREATE TABLE IF NOT EXISTS gps_safe_zones (
    zone_id         SERIAL          PRIMARY KEY,
    patient_id      INT             NOT NULL REFERENCES patients(patient_id),
    guardian_id     INT             NOT NULL REFERENCES guardians(guardian_id),
    zone_name       VARCHAR(100)    NOT NULL,
    center_lat      DECIMAL(10,7)   NOT NULL,
    center_lng      DECIMAL(10,7)   NOT NULL,
    radius_m        SMALLINT        NOT NULL DEFAULT 150 CHECK (radius_m > 0),
    is_active       BOOLEAN         DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS gps_risk_alerts (
    alert_id        SERIAL          PRIMARY KEY,
    patient_id      INT             NOT NULL REFERENCES patients(patient_id),
    gps_device_id   INT             NOT NULL REFERENCES gps_devices(gps_device_id),
    alert_type      VARCHAR(40)     NOT NULL CHECK (alert_type IN (
                        'Salida_Zona_Segura','Sin_Señal','Inasistencia_Cita',
                        'Bateria_Baja','Dispositivo_Inactivo')),
    triggered_at    TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    location_lat    DECIMAL(10,7),
    location_lng    DECIMAL(10,7),
    resolved_at     TIMESTAMPTZ,
    resolved_by     INT             REFERENCES workers(worker_id),
    notes           TEXT
);

--- BEACONS BLE / SCAN LOGS ---
-- Reemplaza: beacons.lugar (ENUM inválido en PostgreSQL)
--            scan_logs.uuid/major/minor (redundantes, sin FK)

CREATE TABLE IF NOT EXISTS beacons (
    beacon_id       SERIAL          PRIMARY KEY,
    uuid            UUID            NOT NULL UNIQUE,
    major           SMALLINT        NOT NULL,
    minor           SMALLINT        NOT NULL,
    area_id         INT             REFERENCES clinic_areas(area_id),
    clinic_id       INT             NOT NULL REFERENCES clinics(clinic_id),
    mac_address     MACADDR,
    status          VARCHAR(10)     NOT NULL DEFAULT 'Offline' CHECK (status IN ('Online','Offline')),
    last_ping       TIMESTAMPTZ,
    firmware_v      VARCHAR(20),
    installed_date  DATE,
    notes           TEXT,
    UNIQUE (major, minor, uuid)
);

CREATE TABLE IF NOT EXISTS scan_logs (
    log_id          BIGSERIAL       PRIMARY KEY,
    patient_id      INT             REFERENCES patients(patient_id),
    beacon_id       INT             REFERENCES beacons(beacon_id),
    rssi            SMALLINT,
    scanned_at      TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
    scan_type       VARCHAR(10)     CHECK (scan_type IN ('NFC','BLE')),
    source_device   VARCHAR(80),
    action_triggered VARCHAR(80)
);

--- INVENTARIO GENERAL DE INSUMOS ---
-- Nuevo — almacén maneja jeringas, algodón, guantes, etc.

CREATE TABLE IF NOT EXISTS supply_catalog (
    supply_id   SERIAL          PRIMARY KEY,
    name        VARCHAR(150)    NOT NULL,
    unit        VARCHAR(30)     NOT NULL,
    category    VARCHAR(60)     CHECK (category IN (
                    'Jeringa','Desechable','Medicamento','Limpieza','Papeleria','Otro')),
    description TEXT
);

CREATE TABLE IF NOT EXISTS clinic_inventory (
    inventory_id    SERIAL          PRIMARY KEY,
    clinic_id       INT             NOT NULL REFERENCES clinics(clinic_id),
    supply_id       INT             NOT NULL REFERENCES supply_catalog(supply_id),
    quantity        INT             NOT NULL DEFAULT 0 CHECK (quantity >= 0),
    min_stock       INT             DEFAULT 10,
    last_updated    TIMESTAMPTZ     DEFAULT NOW(),
    updated_by      INT             REFERENCES workers(worker_id),
    UNIQUE (clinic_id, supply_id)
);

--- ÍNDICES ---

-- Identificación rápida de pacientes por NFC y CURP
CREATE INDEX IF NOT EXISTS idx_patients_nfc        ON patients(nfc_token);
CREATE INDEX IF NOT EXISTS idx_patients_curp       ON patients(curp);

-- Historial de vacunación por paciente y fecha
CREATE INDEX IF NOT EXISTS idx_vax_records_pat     ON vaccination_records(patient_id);
CREATE INDEX IF NOT EXISTS idx_vax_records_date    ON vaccination_records(applied_date);
CREATE INDEX IF NOT EXISTS idx_vax_records_clinic  ON vaccination_records(clinic_id);

-- Alertas de esquema incompleto por paciente y estado
CREATE INDEX IF NOT EXISTS idx_alerts_patient      ON scheme_completion_alerts(patient_id, status);

-- Lotes próximos a vencer
CREATE INDEX IF NOT EXISTS idx_lots_expiry         ON vaccine_lots(expiration_date)
    WHERE is_active = TRUE;

-- Citas por paciente y fecha
CREATE INDEX IF NOT EXISTS idx_appointments_sched  ON appointments(patient_id, scheduled_at);

-- Escaneos NFC por tarjeta y tiempo
CREATE INDEX IF NOT EXISTS idx_nfc_scans_card      ON nfc_scan_events(nfc_card_id, scanned_at);
CREATE INDEX IF NOT EXISTS idx_nfc_card_patient    ON nfc_cards(patient_id);

-- Ubicaciones GPS por dispositivo y tiempo (alto volumen)
CREATE INDEX IF NOT EXISTS idx_gps_loc_device      ON gps_locations(gps_device_id, recorded_at);
CREATE INDEX IF NOT EXISTS idx_gps_loc_patient     ON gps_locations(patient_id, recorded_at);

-- Alertas GPS activas (sin resolución)
CREATE INDEX IF NOT EXISTS idx_gps_alerts_active   ON gps_risk_alerts(patient_id)
    WHERE resolved_at IS NULL;

-- Logs de escaneo BLE por tiempo
CREATE INDEX IF NOT EXISTS idx_scan_logs_time      ON scan_logs(scanned_at);

-- Auditoría por tabla y fecha
CREATE INDEX IF NOT EXISTS idx_audit_table         ON audit_log(table_name, changed_at);
