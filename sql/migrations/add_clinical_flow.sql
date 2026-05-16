-- ============================================================
-- MIGRACIÓN: Flujo clínico NFC completo
-- Archivo: sql/migrations/add_clinical_flow.sql
-- Ejecutar UNA sola vez sobre la BD existente.
-- ============================================================

SET client_encoding = 'UTF8';
SET search_path = public;

-- ============================================================
-- PASO 1: ENUM de estados clínicos
-- ============================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'visit_status') THEN
        CREATE TYPE visit_status AS ENUM (
            'En recepcion',
            'En espera',
            'En consulta',
            'En vacunacion',
            'Finalizado',
            'Abandono',
            'Cancelado'
        );
    END IF;
END$$;


-- ============================================================
-- PASO 2: TABLA CENTRAL — patient_clinic_visits
-- Modela la presencia física del paciente dentro de la clínica.
-- Una visita puede corresponder a una cita programada (appointment_id)
-- o ser espontánea (appointment_id = NULL).
-- ============================================================
CREATE TABLE IF NOT EXISTS patient_clinic_visits (
    visit_id                SERIAL          PRIMARY KEY,
    patient_id              INT             NOT NULL REFERENCES patients(patient_id),
    clinic_id               INT             NOT NULL REFERENCES clinics(clinic_id),
    appointment_id          INT             UNIQUE REFERENCES appointments(appointment_id),

    -- ESTADO CLÍNICO ACTUAL
    visit_status            visit_status    NOT NULL DEFAULT 'En recepcion',
    current_area_id         INT             REFERENCES clinic_areas(area_id),
    assigned_worker_id      INT             REFERENCES workers(worker_id),

    -- TIMESTAMPS DE CADA FASE DEL FLUJO
    checked_in_at           TIMESTAMP       NOT NULL DEFAULT NOW(),
    waiting_since           TIMESTAMP,
    consultation_start      TIMESTAMP,
    vaccination_start       TIMESTAMP,
    checked_out_at          TIMESTAMP,

    -- TRAZABILIDAD OPERATIVA
    checkin_by_worker_id    INT             NOT NULL REFERENCES workers(worker_id),
    checkout_by_worker_id   INT             REFERENCES workers(worker_id),
    checkin_nfc_scan_id     INT             REFERENCES nfc_scan_events(scan_event_id),
    checkout_nfc_scan_id    INT             REFERENCES nfc_scan_events(scan_event_id),

    -- METADATOS
    visit_type              VARCHAR(20)     NOT NULL DEFAULT 'Programada'
                                            CHECK (visit_type IN ('Programada','Espontanea','Urgencia')),
    visit_notes             TEXT,
    created_at              TIMESTAMP       NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMP       NOT NULL DEFAULT NOW()
);

-- Restricción: un paciente no puede tener dos visitas activas simultáneas.
-- Se usa UNIQUE parcial en lugar de EXCLUDE para compatibilidad máxima.
CREATE UNIQUE INDEX IF NOT EXISTS uq_one_active_visit_per_patient
    ON patient_clinic_visits(patient_id)
    WHERE visit_status NOT IN ('Finalizado','Abandono','Cancelado');


-- ============================================================
-- PASO 3: TABLA DE MOVIMIENTOS — visit_area_movements
-- Registra cada cambio de área o estado durante la visita.
-- Permite reconstruir el recorrido completo del paciente.
-- ============================================================
CREATE TABLE IF NOT EXISTS visit_area_movements (
    movement_id     SERIAL          PRIMARY KEY,
    visit_id        INT             NOT NULL REFERENCES patient_clinic_visits(visit_id),
    from_area_id    INT             REFERENCES clinic_areas(area_id),
    to_area_id      INT             REFERENCES clinic_areas(area_id),
    from_status     visit_status,
    to_status       visit_status    NOT NULL,
    moved_at        TIMESTAMP       NOT NULL DEFAULT NOW(),
    moved_by        INT             NOT NULL REFERENCES workers(worker_id),
    nfc_scan_id     INT             REFERENCES nfc_scan_events(scan_event_id),
    movement_notes  TEXT
);


-- ============================================================
-- PASO 4: AMPLIAR nfc_scan_events
-- Agregar contexto clínico al log de escaneos existente.
-- ============================================================
ALTER TABLE nfc_scan_events
    ADD COLUMN IF NOT EXISTS visit_id       INT REFERENCES patient_clinic_visits(visit_id),
    ADD COLUMN IF NOT EXISTS scan_context   VARCHAR(30)
                                            CHECK (scan_context IN (
                                                'checkin','area_change','medical_open',
                                                'vaccination_start','checkout','info_only'
                                            )),
    ADD COLUMN IF NOT EXISTS resolved_action VARCHAR(50),
    ADD COLUMN IF NOT EXISTS error_reason   TEXT;


-- ============================================================
-- PASO 5: AMPLIAR vaccination_records
-- Vincular cada vacuna aplicada a la visita clínica correspondiente.
-- ============================================================
ALTER TABLE vaccination_records
    ADD COLUMN IF NOT EXISTS visit_id INT REFERENCES patient_clinic_visits(visit_id);


-- ============================================================
-- PASO 6: ÍNDICES DE PERFORMANCE
-- Orientados a las consultas más frecuentes del dashboard en tiempo real.
-- ============================================================

-- Dashboard en tiempo real: pacientes activos por clínica
CREATE INDEX IF NOT EXISTS idx_visits_active_clinic
    ON patient_clinic_visits(clinic_id, visit_status)
    WHERE visit_status NOT IN ('Finalizado','Abandono','Cancelado');

-- Búsqueda de visita activa al escanear NFC (crítico, debe ser rápido)
CREATE INDEX IF NOT EXISTS idx_visits_active_patient
    ON patient_clinic_visits(patient_id, visit_status)
    WHERE visit_status NOT IN ('Finalizado','Abandono','Cancelado');

-- Historial de visitas por paciente
CREATE INDEX IF NOT EXISTS idx_visits_patient_date
    ON patient_clinic_visits(patient_id, checked_in_at DESC);

-- Tiempo en espera (para alertas de > 30 min)
CREATE INDEX IF NOT EXISTS idx_visits_waiting_since
    ON patient_clinic_visits(waiting_since)
    WHERE visit_status = 'En espera';

-- Movimientos por visita
CREATE INDEX IF NOT EXISTS idx_movements_visit
    ON visit_area_movements(visit_id, moved_at);

-- NFC scans de hoy por clínica (para actividad reciente en dashboard)
CREATE INDEX IF NOT EXISTS idx_nfc_scans_clinic_today
    ON nfc_scan_events(clinic_id, scanned_at DESC)
    WHERE scanned_at >= CURRENT_DATE;

-- Vacunas vinculadas a visita
CREATE INDEX IF NOT EXISTS idx_vr_visit
    ON vaccination_records(visit_id);
