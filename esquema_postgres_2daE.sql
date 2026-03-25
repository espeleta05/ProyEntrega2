-- ============================================================
-- Base de datos: sistemaVacunacion
-- ============================================================

-- ============================================================
-- MÓDULO: ADDRESSES
-- ============================================================
CREATE TABLE countries (
    country_id  SERIAL PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    iso_code    CHAR(2)      NOT NULL UNIQUE
);

CREATE TABLE states (
    state_id    SERIAL PRIMARY KEY,
    country_id  INT NOT NULL REFERENCES countries(country_id),
    name        VARCHAR(100) NOT NULL,
    code        VARCHAR(10)
);

CREATE TABLE municipalities (
    municipality_id SERIAL PRIMARY KEY,
    state_id        INT NOT NULL REFERENCES states(state_id),
    name            VARCHAR(100) NOT NULL
);

CREATE TABLE neighborhoods (
    neighborhood_id SERIAL PRIMARY KEY,
    municipality_id INT NOT NULL REFERENCES municipalities(municipality_id),
    name            VARCHAR(150) NOT NULL,
    zip_code        VARCHAR(10)
);

CREATE TABLE addresses (
    address_id      SERIAL PRIMARY KEY,
    neighborhood_id INT NOT NULL REFERENCES neighborhoods(neighborhood_id),
    street          VARCHAR(200) NOT NULL,
    ext_number      VARCHAR(20),
    int_number      VARCHAR(20),
    cross_street_1  VARCHAR(200),
    latitude        DECIMAL(10,7),
    longitude       DECIMAL(10,7),
    reference       TEXT
);


-- ============================================================
-- MÓDULO: CLÍNICAS
-- ============================================================
CREATE TABLE clinics (
    clinic_id        SERIAL PRIMARY KEY,
    name             VARCHAR(150) NOT NULL,
    clues            VARCHAR(20)  UNIQUE,
    address_id       INT NOT NULL REFERENCES addresses(address_id),
    phone            VARCHAR(20),
    institution_type VARCHAR(50),
    is_active        BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE area_types (
    area_type_id SERIAL PRIMARY KEY,
    area_type    VARCHAR(50) NOT NULL UNIQUE
    -- Sala_Espera / Consultorio / Enfermeria / Almacen / Recepcion
);

CREATE TABLE clinic_areas (
    area_id      SERIAL PRIMARY KEY,
    clinic_id    INT NOT NULL REFERENCES clinics(clinic_id),
    name         VARCHAR(100) NOT NULL,
    area_type_id INT NOT NULL REFERENCES area_types(area_type_id),
    floor        SMALLINT,
    capacity     SMALLINT
);

CREATE TABLE equipment_catalog (
    equipment_id         SERIAL PRIMARY KEY,
    name                 VARCHAR(150) NOT NULL,
    category             VARCHAR(80)  NOT NULL,
    requires_calibration BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE area_equipment (
    area_equipment_id SERIAL PRIMARY KEY,
    area_id           INT NOT NULL REFERENCES clinic_areas(area_id),
    equipment_id      INT NOT NULL REFERENCES equipment_catalog(equipment_id),
    quantity          SMALLINT NOT NULL DEFAULT 1,
    serial_number     VARCHAR(100),
    condition         VARCHAR(30)  -- Bueno / Regular / Deteriorado
);


-- ============================================================
-- MÓDULO: WORKERS
-- ============================================================
CREATE TABLE roles (
    role_id     SERIAL PRIMARY KEY,
    name        VARCHAR(50) NOT NULL UNIQUE,
    description TEXT
);

CREATE TABLE workers (
    worker_id     SERIAL PRIMARY KEY,
    role_id       INT NOT NULL REFERENCES roles(role_id),
    first_name    VARCHAR(80) NOT NULL,
    last_name     VARCHAR(80) NOT NULL,
    curp          CHAR(18)    UNIQUE,
    email         VARCHAR(100) NOT NULL UNIQUE,
    address_id    INT REFERENCES addresses(address_id),
    hire_date     DATE,
    is_active     BOOLEAN NOT NULL DEFAULT TRUE,
    password_hash VARCHAR(255)
);

CREATE TABLE worker_phones (
    phone_id    SERIAL PRIMARY KEY,
    worker_id   INT NOT NULL REFERENCES workers(worker_id),
    phone       VARCHAR(20) NOT NULL,
    phone_type  VARCHAR(20),
    is_primary  BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE worker_emails (
    email_id    SERIAL PRIMARY KEY,
    worker_id   INT NOT NULL REFERENCES workers(worker_id),
    email       VARCHAR(100) NOT NULL,
    is_primary  BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE specialties (
    specialty_id SERIAL PRIMARY KEY,
    name         VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE institutions (
    institution_id   SERIAL PRIMARY KEY,
    institution_name VARCHAR(150) NOT NULL,
    address_id       INT REFERENCES addresses(address_id)
);

CREATE TABLE worker_professional (
    worker_id          INT PRIMARY KEY REFERENCES workers(worker_id),
    cedula_profesional VARCHAR(20) NOT NULL,
    specialty_id       INT REFERENCES specialties(specialty_id),
    institution_id     INT REFERENCES institutions(institution_id),
    institution_title  VARCHAR(150)
);

CREATE TABLE worker_clinic_assignment (
    assignment_id SERIAL PRIMARY KEY,
    worker_id     INT NOT NULL REFERENCES workers(worker_id),
    clinic_id     INT NOT NULL REFERENCES clinics(clinic_id),
    area_id       INT REFERENCES clinic_areas(area_id),
    start_date    DATE NOT NULL,
    end_date      DATE,
    is_active     BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE worker_schedules (
    schedule_id SERIAL PRIMARY KEY,
    worker_id   INT NOT NULL REFERENCES workers(worker_id),
    clinic_id   INT NOT NULL REFERENCES clinics(clinic_id),
    day_of_week SMALLINT NOT NULL,  -- 1=Lunes ... 7=Domingo
    entry_time  TIME NOT NULL,
    exit_time   TIME NOT NULL,
    shift_type  VARCHAR(20)  -- Matutino / Vespertino / Nocturno / Mixto
);


-- ============================================================
-- MÓDULO: GUARDIANS
-- ============================================================
CREATE TABLE guardians (
    guardian_id    SERIAL PRIMARY KEY,
    first_name     VARCHAR(80) NOT NULL,
    last_name      VARCHAR(80) NOT NULL,
    curp           CHAR(18)    UNIQUE,
    address_id     INT REFERENCES addresses(address_id),
    marital_status VARCHAR(30),
    occupation     VARCHAR(100)
);

CREATE TABLE guardian_phones (
    phone_id    SERIAL PRIMARY KEY,
    guardian_id INT NOT NULL REFERENCES guardians(guardian_id),
    phone       VARCHAR(20) NOT NULL,
    phone_type  VARCHAR(20),
    is_primary  BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE guardian_emails (
    email_id    SERIAL PRIMARY KEY,
    guardian_id INT NOT NULL REFERENCES guardians(guardian_id),
    email       VARCHAR(100) NOT NULL,
    is_primary  BOOLEAN NOT NULL DEFAULT FALSE
);


-- ============================================================
-- MÓDULO: PATIENTS
-- ============================================================
CREATE TABLE blood_types (
    blood_type_id SERIAL PRIMARY KEY,
    blood_type    VARCHAR(5) NOT NULL UNIQUE
    -- O+/O-/A+/A-/B+/B-/AB+/AB-
);

CREATE TABLE patients (
    patient_id        SERIAL PRIMARY KEY,
    first_name        VARCHAR(80) NOT NULL,
    last_name         VARCHAR(80) NOT NULL,
    birth_date        DATE NOT NULL,
    blood_type_id     INT REFERENCES blood_types(blood_type_id),
    gender            CHAR(1),       -- M / F
    nfc_token         VARCHAR(50)  UNIQUE,
    curp              CHAR(18)     UNIQUE,
    weight_kg         DECIMAL(5,2),
    premature         BOOLEAN NOT NULL DEFAULT FALSE,
    gestational_weeks SMALLINT
);

CREATE TABLE allergy_catalog (
    allergy_id   SERIAL PRIMARY KEY,
    name         VARCHAR(150) NOT NULL UNIQUE,
    allergy_type VARCHAR(50)  -- Medicamento / Alimento / Ambiental / Latex
);

CREATE TABLE patient_allergies (
    patient_allergy_id SERIAL PRIMARY KEY,
    patient_id         INT NOT NULL REFERENCES patients(patient_id),
    allergy_id         INT NOT NULL REFERENCES allergy_catalog(allergy_id),
    severity           VARCHAR(20),
    reaction_desc      TEXT
);

CREATE TABLE patient_guardian_relations (
    relation_id   SERIAL PRIMARY KEY,
    patient_id    INT NOT NULL REFERENCES patients(patient_id),
    guardian_id   INT NOT NULL REFERENCES guardians(guardian_id),
    relation_type VARCHAR(50) NOT NULL,  -- Padre / Madre / Abuelo / Tutor_Legal
    is_primary    BOOLEAN NOT NULL DEFAULT FALSE,
    has_custody   BOOLEAN NOT NULL DEFAULT FALSE
);


-- ============================================================
-- MÓDULO: CITAS
-- ============================================================
CREATE TABLE appointments (
    appointment_id SERIAL PRIMARY KEY,
    patient_id     INT NOT NULL REFERENCES patients(patient_id),
    clinic_id      INT NOT NULL REFERENCES clinics(clinic_id),
    area_id        INT REFERENCES clinic_areas(area_id),
    worker_id      INT REFERENCES workers(worker_id),
    scheduled_at   TIMESTAMPTZ NOT NULL,
    duration_min   SMALLINT,
    reason         VARCHAR(150),
    status         VARCHAR(20) NOT NULL DEFAULT 'Pendiente',
    -- Pendiente / Confirmada / Completada / Cancelada / No_Asistio
    notes          TEXT
);


-- ============================================================
-- MÓDULO: VACUNAS
-- ============================================================
CREATE TABLE manufacturers (
    manufacturer_id SERIAL PRIMARY KEY,
    name            VARCHAR(150) NOT NULL UNIQUE,
    country_id      INT REFERENCES countries(country_id),
    contact_email   VARCHAR(100),
    website         VARCHAR(100)
);

CREATE TABLE vaccine_vias (
    via_id SERIAL PRIMARY KEY,
    via    VARCHAR(30) NOT NULL UNIQUE
    -- Intradermica / Intramuscular / Subcutanea / Oral
);

CREATE TABLE vaccines (
    vaccine_id      SERIAL PRIMARY KEY,
    name            VARCHAR(150) NOT NULL,
    commercial_name VARCHAR(150),
    manufacturer_id INT REFERENCES manufacturers(manufacturer_id),
    via_id          INT REFERENCES vaccine_vias(via_id),
    min_age_months  SMALLINT,
    max_age_months  SMALLINT,
    requires_cold_chain BOOLEAN NOT NULL DEFAULT TRUE,
    description     TEXT
);

CREATE TABLE vaccine_lots (
    lot_id             SERIAL PRIMARY KEY,
    vaccine_id         INT NOT NULL REFERENCES vaccines(vaccine_id),
    clinic_id          INT NOT NULL REFERENCES clinics(clinic_id),
    lot_number         VARCHAR(80) NOT NULL,
    quantity_received  INT NOT NULL,
    quantity_available INT NOT NULL,
    expiration_date    DATE NOT NULL,
    received_date      DATE NOT NULL
);


-- ============================================================
-- MÓDULO: ESQUEMA OFICIAL DE VACUNACIÓN
-- ============================================================
CREATE TABLE vaccination_schemes (
    scheme_id    SERIAL PRIMARY KEY,
    name         VARCHAR(150) NOT NULL,
    issuing_body VARCHAR(100),
    year         SMALLINT NOT NULL,
    is_current   BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE scheme_doses (
    dose_id           SERIAL PRIMARY KEY,
    scheme_id         INT NOT NULL REFERENCES vaccination_schemes(scheme_id),
    vaccine_id        INT NOT NULL REFERENCES vaccines(vaccine_id),
    dose_number       SMALLINT NOT NULL,
    dose_label        VARCHAR(50),
    ideal_age_months  SMALLINT NOT NULL,
    min_interval_days SMALLINT NOT NULL DEFAULT 0
);


-- ============================================================
-- MÓDULO: REGISTROS DE VACUNACIÓN
-- ============================================================
CREATE TABLE application_sites (
    application_site_id SERIAL PRIMARY KEY,
    application_site    VARCHAR(30) NOT NULL UNIQUE
    -- Muslo_Izq / Muslo_Der / Brazo_Der / Brazo_Izq / Oral / Nasal
);

CREATE TABLE vaccination_records (
    record_id           SERIAL PRIMARY KEY,
    patient_id          INT NOT NULL REFERENCES patients(patient_id),
    vaccine_id          INT NOT NULL REFERENCES vaccines(vaccine_id),
    worker_id           INT NOT NULL REFERENCES workers(worker_id),
    clinic_id           INT NOT NULL REFERENCES clinics(clinic_id),
    lot_id              INT NOT NULL REFERENCES vaccine_lots(lot_id),
    scheme_dose_id      INT REFERENCES scheme_doses(dose_id),
    applied_date        DATE NOT NULL,
    application_site_id INT REFERENCES application_sites(application_site_id),
    patient_temp_c      DECIMAL(4,1),
    had_reaction        BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE post_vaccine_reactions (
    reaction_id        SERIAL PRIMARY KEY,
    record_id          INT NOT NULL REFERENCES vaccination_records(record_id),
    reported_by        INT REFERENCES workers(worker_id),
    symptom            VARCHAR(150) NOT NULL,
    severity           VARCHAR(20),
    onset_hours        SMALLINT,
    treatment          TEXT,
    notified_authority BOOLEAN NOT NULL DEFAULT FALSE
);


-- ============================================================
-- MÓDULO: NFC
-- ============================================================
CREATE TABLE nfc_cards (
    nfc_card_id     SERIAL PRIMARY KEY,
    patient_id      INT NOT NULL REFERENCES patients(patient_id),
    uid             VARCHAR(30) NOT NULL UNIQUE,
    card_type       VARCHAR(20) NOT NULL,  -- Tarjeta / Pulsera / Llavero
    issued_date     DATE NOT NULL,
    issued_by       INT NOT NULL REFERENCES workers(worker_id),
    status          VARCHAR(20) NOT NULL DEFAULT 'Activa',
    -- Activa / Desactivada / Extraviada / Vencida
    last_scanned_at TIMESTAMPTZ,
    notes           TEXT
);

CREATE TABLE nfc_devices (
    device_id   VARCHAR(30) PRIMARY KEY,
    clinic_id   INT NOT NULL REFERENCES clinics(clinic_id),
    area_id     INT REFERENCES clinic_areas(area_id),
    device_name VARCHAR(100) NOT NULL,
    model       VARCHAR(50),
    serial_number VARCHAR(30),
    status      VARCHAR(20) NOT NULL DEFAULT 'Activo',
    -- Activo / Inactivo / En_Reparacion
    registered_at DATE
);

CREATE TABLE nfc_scan_events (
    scan_event_id    SERIAL PRIMARY KEY,
    nfc_card_id      INT NOT NULL REFERENCES nfc_cards(nfc_card_id),
    scanned_by       INT REFERENCES workers(worker_id),
    clinic_id        INT NOT NULL REFERENCES clinics(clinic_id),
    area_id          INT REFERENCES clinic_areas(area_id),
    scanned_at       TIMESTAMPTZ NOT NULL,
    action_triggered VARCHAR(80),
    device_id        VARCHAR(30) REFERENCES nfc_devices(device_id),
    result           VARCHAR(100)
);


-- ============================================================
-- MÓDULO: GPS
-- ============================================================
CREATE TABLE gps_devices (
    gps_device_id SERIAL PRIMARY KEY,
    patient_id    INT NOT NULL REFERENCES patients(patient_id),
    device_type   VARCHAR(30) NOT NULL,  -- Pulsera GPS / App Tutor
    model         VARCHAR(50),
    imei          VARCHAR(20) UNIQUE,
    assigned_date DATE NOT NULL,
    assigned_by   INT NOT NULL REFERENCES workers(worker_id),
    battery_pct   SMALLINT,
    status        VARCHAR(20) NOT NULL DEFAULT 'Activo'
    -- Activo / Inactivo / Perdido / Sin_Señal
);

CREATE TABLE gps_locations (
    location_id   BIGSERIAL PRIMARY KEY,
    gps_device_id INT NOT NULL REFERENCES gps_devices(gps_device_id),
    patient_id    INT NOT NULL REFERENCES patients(patient_id),
    latitude      DECIMAL(10,7) NOT NULL,
    longitude     DECIMAL(10,7) NOT NULL,
    accuracy_m    SMALLINT,
    recorded_at   TIMESTAMPTZ NOT NULL,
    speed_kmh     DECIMAL(5,2),
    altitude_m    SMALLINT
);

CREATE TABLE gps_safe_zones (
    zone_id     SERIAL PRIMARY KEY,
    patient_id  INT NOT NULL REFERENCES patients(patient_id),
    guardian_id INT NOT NULL REFERENCES guardians(guardian_id),
    zone_name   VARCHAR(100) NOT NULL,
    center_lat  DECIMAL(10,7) NOT NULL,
    center_lng  DECIMAL(10,7) NOT NULL,
    radius_m    SMALLINT NOT NULL,
    is_active   BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE gps_risk_alerts (
    alert_id      SERIAL PRIMARY KEY,
    patient_id    INT NOT NULL REFERENCES patients(patient_id),
    gps_device_id INT NOT NULL REFERENCES gps_devices(gps_device_id),
    alert_type    VARCHAR(40) NOT NULL,
    -- Salida_Zona_Segura / Sin_Señal / Inasistencia_Cita / Bateria_Baja
    triggered_at  TIMESTAMPTZ NOT NULL,
    location_lat  DECIMAL(10,7),
    location_lng  DECIMAL(10,7),
    resolved_at   TIMESTAMPTZ,
    resolved_by   INT REFERENCES workers(worker_id),
    notes         TEXT
);


-- ============================================================
-- MÓDULO: BEACONS (IoT BLE)
-- ============================================================
CREATE TABLE beacons (
    beacon_id     SERIAL PRIMARY KEY,
    uuid          UUID NOT NULL UNIQUE,
    major         SMALLINT NOT NULL,
    minor         SMALLINT NOT NULL,
    area_id       INT REFERENCES clinic_areas(area_id),
    clinic_id     INT NOT NULL REFERENCES clinics(clinic_id),
    status        VARCHAR(10) NOT NULL DEFAULT 'Online',  -- Online / Offline
    last_ping     TIMESTAMPTZ
);

CREATE TABLE scan_logs (
    log_id      BIGSERIAL PRIMARY KEY,
    patient_id  INT REFERENCES patients(patient_id),
    beacon_id   INT REFERENCES beacons(beacon_id),
    rssi        SMALLINT,
    scanned_at  TIMESTAMPTZ NOT NULL,
    scan_type   VARCHAR(10)  -- NFC / BLE
);


-- ============================================================
-- MÓDULO: INVENTARIO DE INSUMOS
-- ============================================================
CREATE TABLE supply_catalog (
    supply_id SERIAL PRIMARY KEY,
    name      VARCHAR(150) NOT NULL,
    unit      VARCHAR(30)  NOT NULL,
    category  VARCHAR(60)
    -- Jeringa / Desechable / Medicamento / Limpieza
);

CREATE TABLE clinic_inventory (
    inventory_id SERIAL PRIMARY KEY,
    clinic_id    INT NOT NULL REFERENCES clinics(clinic_id),
    supply_id    INT NOT NULL REFERENCES supply_catalog(supply_id),
    quantity     INT NOT NULL DEFAULT 0,
    min_stock    INT,
    last_updated TIMESTAMPTZ
);


-- ============================================================
-- MÓDULO: ALERTAS Y AUDITORÍA
-- ============================================================
CREATE TABLE scheme_completion_alerts (
    alert_id       SERIAL PRIMARY KEY,
    patient_id     INT NOT NULL REFERENCES patients(patient_id),
    scheme_dose_id INT NOT NULL REFERENCES scheme_doses(dose_id),
    due_date       DATE NOT NULL,
    status         VARCHAR(20) NOT NULL DEFAULT 'Pendiente',
    -- Pendiente / Aplicada / Vencida / Omitida
    notified_at    TIMESTAMPTZ
);

CREATE TABLE audit_log (
    audit_id   BIGSERIAL PRIMARY KEY,
    table_name VARCHAR(80) NOT NULL,
    record_id  INT NOT NULL,
    action     VARCHAR(10) NOT NULL,  -- INSERT / UPDATE / DELETE
    worker_id  INT REFERENCES workers(worker_id),
    changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    old_data   JSONB,
    new_data   JSONB,
    ip_address INET
);


-- ============================================================
-- ÍNDICES
-- ============================================================
CREATE INDEX idx_patients_nfc_token ON patients(nfc_token);
CREATE INDEX idx_patients_curp      ON patients(curp);
CREATE INDEX idx_vaccination_records_patient ON vaccination_records(patient_id);
CREATE INDEX idx_vaccination_records_date    ON vaccination_records(applied_date);
CREATE INDEX idx_gps_locations_device ON gps_locations(gps_device_id, recorded_at DESC);
CREATE INDEX idx_scan_logs_patient   ON scan_logs(patient_id, scanned_at DESC);
CREATE INDEX idx_audit_log_table     ON audit_log(table_name, changed_at DESC);
CREATE INDEX idx_nfc_scan_events_card ON nfc_scan_events(nfc_card_id, scanned_at DESC);

-- ============================================================
-- TOTAL: 48 tablas
-- ============================================================