-- ============================================================
--  Base de datos: sistemavacunacion
-- ============================================================
CREATE DATABASE sistemavacunacion;
CREATE USER vaccine_user WITH PASSWORD '666-999';
\c sistemavacunacion

GRANT CONNECT ON DATABASE sistemavacunacion TO vaccine_user;
GRANT USAGE ON SCHEMA public TO vaccine_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO vaccine_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO vaccine_user;
ALTER DATABASE sistemavacunacion OWNER TO vaccine_user;

DO $$ DECLARE r RECORD;
BEGIN
    FOR r IN SELECT tablename FROM pg_tables WHERE schemaname = 'public'
    LOOP
        EXECUTE 'ALTER TABLE public.' || quote_ident(r.tablename) || ' OWNER TO vaccine_user';
    END LOOP;
END $$;

---- MÓDULO: ADDRESSES

CREATE TABLE countries (
    country_id   SERIAL PRIMARY KEY,
    name         VARCHAR(100) NOT NULL,
    iso_code     CHAR(2)      NOT NULL UNIQUE
);

CREATE TABLE states (
    state_id    SERIAL PRIMARY KEY,
    country_id  INT          NOT NULL REFERENCES countries(country_id),
    name        VARCHAR(100) NOT NULL,
    code        VARCHAR(10),
    UNIQUE(country_id, name),
    UNIQUE(country_id, code)
);

CREATE TABLE municipalities (
    municipality_id  SERIAL PRIMARY KEY,
    state_id         INT          NOT NULL REFERENCES states(state_id),
    name             VARCHAR(100) NOT NULL,
    UNIQUE(state_id, name)
);

CREATE TABLE neighborhoods (
    neighborhood_id  SERIAL PRIMARY KEY,
    municipality_id  INT          NOT NULL REFERENCES municipalities(municipality_id),
    name             VARCHAR(100) NOT NULL,
    zip_code         VARCHAR(10),
    UNIQUE(municipality_id, name, zip_code)
);

CREATE TABLE addresses (
    address_id        SERIAL PRIMARY KEY,
    neighborhood_id   INT           NOT NULL REFERENCES neighborhoods(neighborhood_id),
    street            VARCHAR(200)  NOT NULL,
    ext_number        VARCHAR(20),
    cross_street_1    VARCHAR(200),
    latitude          NUMERIC(9,4),
    longitude         NUMERIC(9,4),
    UNIQUE(neighborhood_id, street, ext_number)
);


---- MÓDULO: CLINICS
CREATE TABLE clinics (
    clinic_id         SERIAL PRIMARY KEY,
    name              VARCHAR(200) NOT NULL,
    address_id        INT          NOT NULL REFERENCES addresses(address_id),
    phone             VARCHAR(20),
    institution_type  VARCHAR(50),
    is_active         BOOLEAN      NOT NULL DEFAULT TRUE
);

CREATE TABLE clinic_area_types (
    area_type_id  SERIAL PRIMARY KEY,
    code          VARCHAR(20) NOT NULL UNIQUE,
    name          VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE clinic_areas (
    area_id       SERIAL PRIMARY KEY,
    clinic_id     INT          NOT NULL REFERENCES clinics(clinic_id),
    name          VARCHAR(200) NOT NULL,
    area_type_id  INT          NOT NULL REFERENCES clinic_area_types(area_type_id),
    code          VARCHAR(20),    -- "VACC-01"
    floor         SMALLINT,
    capacity      SMALLINT,
    UNIQUE(clinic_id, name),
    UNIQUE(clinic_id, code)
);

CREATE TABLE equipment_catalog (
    equipment_id           SERIAL PRIMARY KEY,
    name                   VARCHAR(200) NOT NULL UNIQUE,
    category               VARCHAR(100),
    requires_calibration   BOOLEAN      NOT NULL DEFAULT FALSE
);

CREATE TABLE area_equipment (
    area_equipment_id  SERIAL PRIMARY KEY,
    area_id            INT           NOT NULL REFERENCES clinic_areas(area_id),
    equipment_id       INT           NOT NULL REFERENCES equipment_catalog(equipment_id),
    quantity           SMALLINT      NOT NULL DEFAULT 1,
    serial_number      VARCHAR(50),
    condition          VARCHAR(50),
    UNIQUE(area_id, equipment_id)
);


----  MÓDULO: PATIENTS
CREATE TABLE blood_types (
    blood_type_id  SERIAL PRIMARY KEY,
    blood_type     VARCHAR(5) NOT NULL UNIQUE
);

CREATE TABLE patients (
    patient_id     SERIAL PRIMARY KEY,
    first_name     VARCHAR(100) NOT NULL,
    last_name      VARCHAR(100) NOT NULL,
    birth_date     DATE         NOT NULL,
    blood_type_id  INT          REFERENCES blood_types(blood_type_id),
    gender         CHAR(1)      CHECK (gender IN ('M','F','O')),
    nfc_id         VARCHAR(50)  UNIQUE,
    curp           VARCHAR(18)     UNIQUE,
    weight_kg      NUMERIC(5,2),
    premature      BOOLEAN      NOT NULL DEFAULT FALSE,
    photo          VARCHAR(255),
    created_at     TIMESTAMP    DEFAULT CURRENT_TIMESTAMP,
    is_active      BOOLEAN      NOT NULL DEFAULT TRUE,
    deleted_at      TIMESTAMP,
    updated_at      TIMESTAMP
);

CREATE TABLE allergies (
    allergy_id    SERIAL PRIMARY KEY,
    name          VARCHAR(100) NOT NULL UNIQUE,
    allergy_type  VARCHAR(50)
);

CREATE TABLE patient_allergies (
    patient_allergy_id  SERIAL PRIMARY KEY,
    patient_id          INT          NOT NULL REFERENCES patients(patient_id),
    allergy_id          INT          NOT NULL REFERENCES allergies(allergy_id),
    severity            VARCHAR(50),
    reaction_desc       TEXT,
    UNIQUE(patient_id, allergy_id)
);


----  MÓDULO: GUARDIANS
CREATE TABLE marital_status (
    marital_status_id  SERIAL PRIMARY KEY,
    marital_status     VARCHAR(50) NOT NULL UNIQUE CHECK (marital_status IN ('Soltero','Casado','Divorciado','Viudo'))
);

CREATE TABLE occupations (
    occupation_id    SERIAL PRIMARY KEY,
    occupation_name  VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE guardians (
    guardian_id        SERIAL PRIMARY KEY,
    first_name         VARCHAR(100) NOT NULL,
    last_name          VARCHAR(100) NOT NULL,
    curp               CHAR(18)     UNIQUE,
    address_id         INT          REFERENCES addresses(address_id),
    marital_status_id  INT          REFERENCES marital_status(marital_status_id),
    occupation         INT          REFERENCES occupations(occupation_id)
);

CREATE TABLE guardian_phones (
    phone_id     SERIAL PRIMARY KEY,
    guardian_id  INT          NOT NULL REFERENCES guardians(guardian_id),
    phone        VARCHAR(20)  NOT NULL,
    phone_type   VARCHAR(30),
    is_primary   BOOLEAN      NOT NULL DEFAULT FALSE,
    UNIQUE(guardian_id, phone)
);

CREATE TABLE guardian_emails (
    email_id     SERIAL PRIMARY KEY,
    guardian_id  INT          NOT NULL REFERENCES guardians(guardian_id),
    email        VARCHAR(150) NOT NULL,
    is_primary   BOOLEAN      NOT NULL DEFAULT FALSE,
    UNIQUE(guardian_id, email)
);

CREATE TABLE patient_guardian_relations (
    relation_id    SERIAL PRIMARY KEY,
    patient_id     INT          NOT NULL REFERENCES patients(patient_id),
    guardian_id    INT          NOT NULL REFERENCES guardians(guardian_id),
    relation_type  VARCHAR(50),
    is_primary     BOOLEAN      NOT NULL DEFAULT FALSE,
    has_custody    BOOLEAN      NOT NULL DEFAULT FALSE,
    UNIQUE (patient_id, guardian_id)
);


----  MÓDULO: WORKERS
CREATE TABLE roles (
    role_id      SERIAL PRIMARY KEY,
    name         VARCHAR(100) NOT NULL UNIQUE CHECK (name IN ('Administrador','Enfermero','Medico','Recepcionista','Almacen', 'Tutor')),
    description  TEXT
);

CREATE TABLE specialties (
    specialty_id  SERIAL PRIMARY KEY,
    name          VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE institutions (
    institution_id    SERIAL PRIMARY KEY,
    institution_name  VARCHAR(200) NOT NULL UNIQUE,
    address_id        INT          REFERENCES addresses(address_id)
);

CREATE TABLE workers (
    worker_id      SERIAL PRIMARY KEY,
    role_id        INT           NOT NULL REFERENCES roles(role_id),
    first_name     VARCHAR(100)  NOT NULL,
    last_name      VARCHAR(100)  NOT NULL,
    curp           CHAR(18)      UNIQUE,
    address_id     INT           REFERENCES addresses(address_id),
    birth_date     DATE,
    hire_date      DATE,
);

CREATE TABLE worker_professional (
    worker_id           INT NOT NULL REFERENCES workers(worker_id),
    cedula_profesional  VARCHAR(20),
    specialty_id        INT REFERENCES specialties(specialty_id),
    institution_id      INT REFERENCES institutions(institution_id),
    PRIMARY KEY (worker_id, specialty_id)
);

CREATE TABLE worker_phones (
    phone_id    SERIAL PRIMARY KEY,
    worker_id   INT          NOT NULL REFERENCES workers(worker_id),
    phone       VARCHAR(20)  NOT NULL,
    phone_type  VARCHAR(30),
    is_primary  BOOLEAN      NOT NULL DEFAULT FALSE,
    UNIQUE(worker_id, phone)
);

CREATE TABLE worker_emails (
    email_id   SERIAL PRIMARY KEY,
    worker_id  INT          NOT NULL REFERENCES workers(worker_id),
    email      VARCHAR(150) NOT NULL,
    is_primary BOOLEAN      NOT NULL DEFAULT FALSE,
    UNIQUE(worker_id, email)
);

CREATE TABLE worker_clinic_assignment (
    assignment_id  SERIAL PRIMARY KEY,
    worker_id      INT  NOT NULL REFERENCES workers(worker_id),
    clinic_id      INT  NOT NULL REFERENCES clinics(clinic_id),
    area_id        INT  REFERENCES clinic_areas(area_id),
    start_date     DATE NOT NULL,
    end_date       DATE,
    is_active      BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE worker_schedules (
    schedule_id  SERIAL PRIMARY KEY,
    worker_id    INT         NOT NULL REFERENCES workers(worker_id),
    clinic_id    INT         NOT NULL REFERENCES clinics(clinic_id),
    day_of_week  SMALLINT    NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),
    entry_time   TIME        NOT NULL,
    exit_time    TIME        NOT NULL,
    shift_type   VARCHAR(30)
);


---- LOGIN
CREATE TABLE users (
    user_id        SERIAL PRIMARY KEY,
    worker_id      INT UNIQUE REFERENCES workers(worker_id),
    username       VARCHAR(50)  NOT NULL UNIQUE,
    password_hash  VARCHAR(255) NOT NULL,
    is_active      BOOLEAN      DEFAULT TRUE,
    created_at     TIMESTAMP    DEFAULT CURRENT_TIMESTAMP  
);

CREATE TABLE guardian_accounts (
    guardian_account_id SERIAL PRIMARY KEY,
    guardian_id INT NOT NULL UNIQUE REFERENCES guardians(guardian_id) ON DELETE CASCADE,
    email VARCHAR(120) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    email_verified BOOLEAN DEFAULT FALSE,
    last_login TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

----  MÓDULO: VACCINES / OFFICIAL SCHEME
CREATE TABLE manufacturers (
    manufacturer_id  SERIAL PRIMARY KEY,
    name             VARCHAR(200) NOT NULL UNIQUE,
    country_id       INT          REFERENCES countries(country_id),
    contact_email    VARCHAR(150)
);

CREATE TABLE vaccine_vias (
    via_id  SERIAL PRIMARY KEY,
    via     VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE vaccines (
    vaccine_id        SERIAL PRIMARY KEY,
    name              VARCHAR(100) NOT NULL UNIQUE,
    commercial_name   VARCHAR(100) UNIQUE,
    manufacturer_id   INT          REFERENCES manufacturers(manufacturer_id),
    via_id            INT          REFERENCES vaccine_vias(via_id),
    ideal_age_months  SMALLINT,
    disease_prevented TEXT
);

CREATE TABLE vaccine_lots (
    lot_id              SERIAL PRIMARY KEY,
    vaccine_id          INT          NOT NULL REFERENCES vaccines(vaccine_id),
    clinic_id           INT          NOT NULL REFERENCES clinics(clinic_id),
    lot_number          VARCHAR(50)  NOT NULL UNIQUE,
    quantity_received   INT          NOT NULL,
    quantity_available  INT          NOT NULL,
    expiration_date     DATE         NOT NULL,
    received_date       DATE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    lot_status VARCHAR(30) NOT NULL DEFAULT 'Disponible'
    CHECK (lot_status IN ('Disponible', 'Agotado', 'Caducado', 'Bloqueado', 'Retirado'))
);

CREATE TABLE inventory_transfers (
    transfer_id     SERIAL PRIMARY KEY,
    lot_id          INT         NOT NULL REFERENCES vaccine_lots(lot_id),
    vaccine_id      INT         NOT NULL REFERENCES vaccines(vaccine_id),
    from_clinic_id  INT         NOT NULL REFERENCES clinics(clinic_id),
    to_clinic_id    INT         NOT NULL REFERENCES clinics(clinic_id),
    quantity        INT         NOT NULL CHECK (quantity > 0),
    transfer_status VARCHAR(20) NOT NULL DEFAULT 'Pendiente'
                    CHECK (transfer_status IN (
                        'Pendiente',
                        'En_Transito',
                        'Recibido',
                        'Cancelado',
                        'Rechazado'
                    )),
    requested_by    INT         NOT NULL REFERENCES workers(worker_id),
    approved_by     INT                  REFERENCES workers(worker_id),
    reason          TEXT,
    notes           TEXT,
    requested_at    TIMESTAMP   NOT NULL DEFAULT NOW(),
    resolved_at     TIMESTAMP,
    CONSTRAINT chk_transfer_different_clinics CHECK (from_clinic_id <> to_clinic_id)
);


CREATE TABLE vaccination_scheme (
    scheme_id     SERIAL PRIMARY KEY,
    name          VARCHAR(200) NOT NULL,
    issuing_body  VARCHAR(100),
    year          SMALLINT,
    is_current    BOOLEAN      NOT NULL DEFAULT FALSE
);

CREATE TABLE scheme_doses (
    dose_id            SERIAL PRIMARY KEY,
    scheme_id          INT          NOT NULL REFERENCES vaccination_scheme(scheme_id),
    vaccine_id         INT          NOT NULL REFERENCES vaccines(vaccine_id),
    dose_number        SMALLINT     NOT NULL,
    dose_label         VARCHAR(100),
    ideal_age_months   SMALLINT,
    min_interval_days  SMALLINT,
    UNIQUE(scheme_id, vaccine_id, dose_number)
);



----  MÓDULO: CLINICAL RECORDS

CREATE TABLE appointments (
    appointment_id       SERIAL      PRIMARY KEY,
    patient_id           INT         NOT NULL REFERENCES patients(patient_id),
    clinic_id            INT         NOT NULL REFERENCES clinics(clinic_id),
    area_id              INT         REFERENCES clinic_areas(area_id),
    worker_id            INT         REFERENCES workers(worker_id),
    patient_schedule_id  INT,
    scheduled_at         TIMESTAMP   NOT NULL,
    duration_min         SMALLINT    DEFAULT 20,
    reason               TEXT,
    appointment_status   VARCHAR(30) NOT NULL DEFAULT 'Programada' CHECK (appointment_status IN (
                                         'Programada','Confirmada','Reagendada',
                                         'Completada','Cancelada','No Show'
                                     )),
    appointment_notes    TEXT,
    cancel_reason        TEXT,
    confirmed_at         TIMESTAMP,
    rescheduled_from_id  INT         REFERENCES appointments(appointment_id),
    created_by_role      VARCHAR(20) NOT NULL
                                     CHECK (created_by_role IN (
                                         'Tutor','Recepcionista','Medico','Enfermero','Administrador'
                                     )),
    created_by_worker_id INT         REFERENCES workers(worker_id),
    created_by_guardian_id INT       REFERENCES guardians(guardian_id),
    created_at           TIMESTAMP   DEFAULT NOW(),
    UNIQUE (worker_id, scheduled_at),
    UNIQUE (clinic_id, area_id, scheduled_at)
);


CREATE TABLE application_sites (
    application_site_id  SERIAL PRIMARY KEY,
    application_site     VARCHAR(50) NOT NULL UNIQUE
);


CREATE TABLE patient_vaccine_schedule (
    schedule_id    SERIAL      PRIMARY KEY,
    patient_id     INT         NOT NULL REFERENCES patients(patient_id),
    scheme_dose_id INT         NOT NULL REFERENCES scheme_doses(dose_id),
    due_date       DATE        NOT NULL,
    status         VARCHAR(20) NOT NULL DEFAULT 'Pendiente'
                               CHECK (status IN ('Pendiente','Aplicada','Atrasada')),
    updated_at     TIMESTAMP   DEFAULT NOW(),
    UNIQUE (patient_id, scheme_dose_id)
);

ALTER TABLE patient_vaccine_schedule ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP DEFAULT NOW();

CREATE TABLE vaccination_records (
    record_id            SERIAL   PRIMARY KEY,
    patient_id           INT      NOT NULL REFERENCES patients(patient_id),
    vaccine_id           INT      NOT NULL REFERENCES vaccines(vaccine_id),
    worker_id            INT      NOT NULL REFERENCES workers(worker_id),
    clinic_id            INT      NOT NULL REFERENCES clinics(clinic_id),
    lot_id               INT      REFERENCES vaccine_lots(lot_id),
    scheme_dose_id       INT      REFERENCES scheme_doses(dose_id),
    applied_date         DATE     NOT NULL,
    application_site_id  INT      REFERENCES application_sites(application_site_id),
    appointment_id       INT      REFERENCES appointments(appointment_id),
    -- Una cita puede tener múltiples registros de vacunación (varias vacunas por cita)
    patient_temp_c       NUMERIC(4,1),
    had_reaction         BOOLEAN  NOT NULL DEFAULT FALSE
);


ALTER TABLE vaccination_records ADD COLUMN created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP;

ALTER TABLE vaccination_records ADD COLUMN patient_schedule_id INT REFERENCES patient_vaccine_schedule(schedule_id);


CREATE TABLE post_vaccine_reactions (
    reaction_id         SERIAL   PRIMARY KEY,
    record_id           INT      NOT NULL REFERENCES vaccination_records(record_id),
    reported_by         INT      REFERENCES workers(worker_id),
    symptom             TEXT,
    severity            VARCHAR(30),
    onset_hours         SMALLINT,
    treatment           TEXT,
    notified_authority  BOOLEAN  NOT NULL DEFAULT FALSE
);


---- MÓDULO: NFC
CREATE TABLE nfc_cards (
    nfc_card_id      SERIAL PRIMARY KEY,
    patient_id       INT          NOT NULL REFERENCES patients(patient_id),
    uid              VARCHAR(30)  NOT NULL UNIQUE,
    card_type        VARCHAR(30),
    issued_date      DATE,
    issued_by        INT          REFERENCES workers(worker_id),
    status           VARCHAR(20)  NOT NULL DEFAULT 'Activa' CHECK (status IN ('Activa','Inactiva','Perdida','Robada')),
    last_scanned_at  TIMESTAMP,
    nfc_card_notes   TEXT
);

CREATE TABLE nfc_devices (
    device_id          VARCHAR(30) PRIMARY KEY,
    clinic_id          INT         NOT NULL REFERENCES clinics(clinic_id),
    area_id            INT         REFERENCES clinic_areas(area_id),
    device_name        VARCHAR(100),
    model              VARCHAR(50),
    serial_number      VARCHAR(50),
    nfc_device_status  VARCHAR(20) NOT NULL DEFAULT 'Activo' CHECK (nfc_device_status IN ('Activo','Inactivo','Mantenimiento')),
    registered_at      DATE
);

CREATE TABLE nfc_scan_events (
    scan_event_id     SERIAL PRIMARY KEY,
    nfc_card_id       INT          NOT NULL REFERENCES nfc_cards(nfc_card_id),
    scanned_by        INT          REFERENCES workers(worker_id),
    clinic_id         INT          NOT NULL REFERENCES clinics(clinic_id),
    area_id           INT          REFERENCES clinic_areas(area_id),
    scanned_at        TIMESTAMP    NOT NULL,
    action_triggered  VARCHAR(50),
    device_id         VARCHAR(30)  REFERENCES nfc_devices(device_id),
    nfc_scan_result   VARCHAR(100),
    visit_id       INT REFERENCES patient_clinic_visits(visit_id),
    scan_context   VARCHAR(30)
                                            CHECK (scan_context IN (
                                                'checkin','area_change','medical_open',
                                                'vaccination_start','checkout','info_only'
                                            )),
    resolved_action VARCHAR(50),
    error_reason   TEXT
);


--  MÓDULO: ALERTS AND AUDITS
CREATE TABLE scheme_completion_alerts (
    alert_id       SERIAL      PRIMARY KEY,
    patient_id     INT         NOT NULL REFERENCES patients(patient_id),
    schedule_id    INT         NOT NULL REFERENCES patient_vaccine_schedule(schedule_id),
    alert_type     VARCHAR(30) NOT NULL CHECK (alert_type IN ('Proximidad','Atraso','Critico')),
    due_date       DATE        NOT NULL,
    message        TEXT,
    status         VARCHAR(20) NOT NULL DEFAULT 'Pendiente'
                               CHECK (status IN ('Pendiente','Enviada','Leida', 'Ignorada')),
    notified_at    TIMESTAMP,
    read_at        TIMESTAMP,
    created_at     TIMESTAMP   DEFAULT NOW()
);

ALTER TABLE scheme_completion_alerts ADD COLUMN IF NOT EXISTS schedule_id INT REFERENCES patient_vaccine_schedule(schedule_id);

CREATE TABLE supply_catalog (
    supply_id  SERIAL PRIMARY KEY,
    name       VARCHAR(200) NOT NULL UNIQUE,
    unit       VARCHAR(30),
    category   VARCHAR(50)
);

CREATE TABLE clinic_inventory (
    inventory_id  SERIAL PRIMARY KEY,
    clinic_id     INT     NOT NULL REFERENCES clinics(clinic_id),
    supply_id     INT     NOT NULL REFERENCES supply_catalog(supply_id),
    quantity      INT     NOT NULL DEFAULT 0,
    min_stock     INT     NOT NULL DEFAULT 0,
    last_updated  DATE,
    UNIQUE(clinic_id, supply_id)
);

CREATE TABLE IF NOT EXISTS inventory_movements (
    movement_id     SERIAL PRIMARY KEY,
    lot_id          INT          NOT NULL REFERENCES vaccine_lots(lot_id),
    vaccine_id      INT          NOT NULL REFERENCES vaccines(vaccine_id),
    clinic_id       INT          NOT NULL REFERENCES clinics(clinic_id),
    worker_id       INT          REFERENCES workers(worker_id),
    movement_type   VARCHAR(30)  NOT NULL
                    CHECK (movement_type IN (
                        'Entrada',
                        'Salida_Aplicacion',
                        'Salida_Merma',
                        'Salida_Caducidad',
                        'Ajuste_Positivo',
                        'Ajuste_Negativo',
                        'Transferencia_Salida',
                        'Transferencia_Entrada'
                    )),
    quantity        INT          NOT NULL CHECK (quantity > 0),
    quantity_before INT          NOT NULL,
    quantity_after  INT          NOT NULL,
    reference_id    INT,
    reference_type  VARCHAR(30)  CHECK (reference_type IN ('vaccination_record', 'transfer', 'manual')),
    reason          TEXT,
    created_at      TIMESTAMP    NOT NULL DEFAULT NOW()
);


CREATE TABLE audit_log (
    audit_id     SERIAL PRIMARY KEY,
    table_name   VARCHAR(100) NOT NULL,
    record_id    INT          NOT NULL,
    action       VARCHAR(20)  NOT NULL CHECK (action IN ('INSERT','UPDATE','DELETE')),
    changed_data JSONB,
    worker_id    INT          REFERENCES workers(worker_id),
    changed_at   TIMESTAMP    NOT NULL DEFAULT NOW(),
    ip_address   VARCHAR(45)
);

-- ============================================================
--  ÍNDICES
-- ============================================================
CREATE INDEX idx_patients_curp             ON patients(curp);
CREATE INDEX idx_patients_nfc_id           ON patients(nfc_id);
CREATE INDEX idx_vaccination_records_pat   ON vaccination_records(patient_id);
CREATE INDEX idx_vaccination_records_date  ON vaccination_records(applied_date);
CREATE INDEX idx_appointments_pat_date     ON appointments(patient_id, scheduled_at);
CREATE INDEX idx_nfc_scan_events_card      ON nfc_scan_events(nfc_card_id, scanned_at);
CREATE INDEX idx_audit_log_table_record    ON audit_log(table_name, record_id);
CREATE INDEX idx_pvs_patient_status        ON patient_vaccine_schedule(patient_id, status);
CREATE INDEX idx_pvs_due_date_status       ON patient_vaccine_schedule(due_date, status) WHERE status IN ('Pendiente','Atrasada');
CREATE INDEX idx_appointments_patient      ON appointments(patient_id, scheduled_at);
CREATE INDEX idx_appointments_status_date  ON appointments(appointment_status, scheduled_at) WHERE appointment_status NOT IN ('Cancelada','No Show','Completada');
CREATE INDEX idx_appointments_worker_date  ON appointments(worker_id, scheduled_at);
CREATE INDEX idx_appointments_clinic_date  ON appointments(clinic_id, scheduled_at::DATE);
CREATE INDEX idx_alerts_patient_status     ON scheme_completion_alerts(patient_id, status);
CREATE INDEX idx_alerts_due_date           ON scheme_completion_alerts(due_date, status) WHERE status = 'Pendiente';
CREATE INDEX idx_vaccination_records_schedule ON vaccination_records(patient_schedule_id);
CREATE INDEX idx_patients_active           ON patients(patient_id) WHERE is_active = TRUE;
CREATE INDEX IF NOT EXISTS idx_transfers_lot        ON inventory_transfers(lot_id);
CREATE INDEX IF NOT EXISTS idx_transfers_from       ON inventory_transfers(from_clinic_id);
CREATE INDEX IF NOT EXISTS idx_transfers_to         ON inventory_transfers(to_clinic_id);
CREATE INDEX IF NOT EXISTS idx_transfers_status     ON inventory_transfers(transfer_status);
CREATE INDEX IF NOT EXISTS idx_transfers_requested  ON inventory_transfers(requested_at DESC);
CREATE INDEX IF NOT EXISTS idx_transfers_requester  ON inventory_transfers(requested_by);
