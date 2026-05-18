-- ============================================================
-- ARCHIVO: vistas.sql
-- Total de objetos: 11
-- ============================================================

SET client_encoding = 'UTF8';

-- VER VISTAS
-- \dv --

-- ===================================================
-- VISTAS PARA EL SISTEMA CLÍNICO DE VACUNACIÓN
-- ===================================================

-- ============================================================
-- [1] vw_patients
-- Función   : Información completa de pacientes con guardián principal, teléfono de contacto y alergias concatenadas
-- Recibe    : patients, blood_types, patient_guardian_relations, guardians, guardian_phones, patient_allergies, allergies
-- Devuelve  : Una fila por paciente activo o inactivo con datos demográficos, guardián y alergias
-- ============================================================
CREATE OR REPLACE VIEW vw_patients AS
SELECT
    p.patient_id,
    p.first_name,
    p.last_name,
    TRIM(p.first_name || ' ' || p.last_name)                             AS full_name,
    p.curp,
    p.birth_date,
    p.gender,
    p.weight_kg,
    p.premature,
    p.is_active,
    p.created_at,
    p.blood_type_id,
    COALESCE(bt.blood_type, '—')                                         AS blood_type,
    DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT              AS age,
    g.guardian_id,
    COALESCE(TRIM(g.first_name || ' ' || g.last_name), 'Sin tutor')      AS guardian,
    COALESCE(
        (
            SELECT gp.phone
            FROM   guardian_phones gp
            WHERE  gp.guardian_id = g.guardian_id
            ORDER  BY gp.is_primary DESC, gp.guardian_phone_id ASC
            LIMIT  1
        ),
        '—'
    )                                                                     AS contact,
    COALESCE(
        NULLIF(
            (
                SELECT STRING_AGG(al.name, ', ' ORDER BY al.name)
                FROM   patient_allergies pa
                JOIN   allergies al ON al.allergy_id = pa.allergy_id
                WHERE  pa.patient_id = p.patient_id
            ),
            ''
        ),
        'Ninguna'
    )                                                                     AS allergies,
    'N/A'::TEXT                                                           AS risk

FROM patients p
LEFT JOIN blood_types bt ON bt.blood_type_id = p.blood_type_id
LEFT JOIN LATERAL (
    SELECT pgr.guardian_id
    FROM   patient_guardian_relations pgr
    WHERE  pgr.patient_id = p.patient_id
    ORDER  BY pgr.is_primary DESC, pgr.relation_id ASC
    LIMIT  1
) rel ON TRUE
LEFT JOIN guardians g ON g.guardian_id = rel.guardian_id;

-- ============================================================
-- [2] v_vaccination_records_full
-- Función   : Historial de vacunación completo por paciente con datos de vacuna, trabajador, dosis y clínica
-- Recibe    : vaccination_records, patients, vaccines, workers, scheme_doses, application_sites, clinics
-- Devuelve  : Una fila por registro de vacunación con todos los datos enriquecidos
-- ============================================================
CREATE OR REPLACE VIEW v_vaccination_records_full AS
SELECT
    vr.record_id,
    vr.patient_id,
    vr.vaccine_id,
    vr.applied_date,
    vr.patient_temp_c,
    vr.had_reaction,
    p.first_name || ' ' || p.last_name AS patient_name,
    v.name AS vaccine_name,
    w.first_name || ' ' || w.last_name AS worker_name,
    sd.dose_label,
    aps.application_site,
    c.name AS clinic_name
FROM vaccination_records vr
JOIN patients p ON p.patient_id = vr.patient_id
JOIN vaccines v ON v.vaccine_id = vr.vaccine_id
JOIN workers w ON w.worker_id = vr.worker_id
LEFT JOIN scheme_doses sd ON sd.dose_id = vr.scheme_dose_id
LEFT JOIN application_sites aps ON aps.application_site_id = vr.application_site_id
JOIN clinics c ON c.clinic_id = vr.clinic_id;

-- ============================================================
-- [3] v_vaccine_stock
-- Función   : Stock de vacunas disponibles agregado por vacuna con fabricante, vía y fecha de vencimiento más próxima
-- Recibe    : vaccines, manufacturers, vaccine_vias, vaccine_lots
-- Devuelve  : Una fila por vacuna con total_stock acumulado y nearest_expiration
-- ============================================================
CREATE OR REPLACE VIEW v_vaccine_stock AS
SELECT
    v.vaccine_id,
    v.name,
    v.commercial_name,
    m.name AS manufacturer,
    vv.via AS route,
    SUM(vl.quantity_available) AS total_stock,
    MIN(vl.expiration_date) AS nearest_expiration
FROM vaccines v
LEFT JOIN manufacturers m ON m.manufacturer_id = v.manufacturer_id
LEFT JOIN vaccine_vias vv ON vv.via_id = v.via_id
LEFT JOIN vaccine_lots vl ON vl.vaccine_id = v.vaccine_id
GROUP BY v.vaccine_id, v.name, v.commercial_name, m.name, vv.via;

-- ============================================================
-- [4] v_appointments_full
-- Función   : Citas enriquecidas con datos de paciente, trabajador, clínica, área y dosis del esquema vinculada
-- Recibe    : appointments, patients, patient_vaccine_schedule, scheme_doses, vaccines, workers, clinics, clinic_areas
-- Devuelve  : Una fila por cita con todos los detalles y datos de auditoría de origen
-- ============================================================
-- [REFACTORED] Ahora usa a.patient_id directamente (campo añadido a appointments).
--              Eliminado a.tutor_accepted (flujo deprecado).
--              patient_schedule_id sigue presente para citas vinculadas a dosis del esquema (opcional).
--              Añadidos campos de auditoría de origen: created_by_role, created_by_worker_id, created_by_guardian_id.
CREATE OR REPLACE VIEW v_appointments_full AS
SELECT
    a.appointment_id,
    a.patient_id,
    a.patient_schedule_id,
    a.worker_id,
    a.clinic_id,
    a.area_id,
    a.scheduled_at,
    a.duration_min,
    a.reason,
    a.appointment_status,
    a.appointment_notes,
    a.cancel_reason,
    a.confirmed_at,
    a.rescheduled_from_id,
    a.created_by_role,
    a.created_by_worker_id,
    a.created_by_guardian_id,
    COALESCE(TRIM(p.first_name || ' ' || p.last_name), '—') AS patient_name,
    COALESCE(TRIM(w.first_name || ' ' || w.last_name), '—') AS worker_name,
    c.name                                                   AS clinic_name,
    COALESCE(ca.name, '—')                                   AS area_name,
    -- Dosis del esquema (solo si la cita está vinculada a patient_vaccine_schedule)
    pvs.scheme_dose_id,
    COALESCE(v.name, '—')                                    AS vaccine_name,
    COALESCE(sd.dose_label, '—')                             AS dose_label,
    pvs.due_date                                             AS dose_due_date,
    pvs.status                                               AS dose_status
FROM appointments a
JOIN      patients p                   ON p.patient_id     = a.patient_id
LEFT JOIN patient_vaccine_schedule pvs ON pvs.schedule_id  = a.patient_schedule_id
LEFT JOIN scheme_doses sd              ON sd.dose_id       = pvs.scheme_dose_id
LEFT JOIN vaccines v                   ON v.vaccine_id     = sd.vaccine_id
LEFT JOIN workers w                    ON w.worker_id      = a.worker_id
JOIN      clinics c                    ON c.clinic_id      = a.clinic_id
LEFT JOIN clinic_areas ca              ON ca.area_id       = a.area_id;

-- ============================================================
-- [5] v_inventory_status
-- Función   : Estado de inventario de insumos por clínica con bandera de bajo stock
-- Recibe    : clinic_inventory, supply_catalog, clinics
-- Devuelve  : Una fila por ítem de inventario con datos del insumo, clínica y flag low_stock
-- ============================================================
CREATE OR REPLACE VIEW v_inventory_status AS
SELECT
    ci.inventory_id,
    ci.quantity,
    ci.min_stock,
    ci.last_updated,
    (ci.quantity < ci.min_stock) AS low_stock,
    sc.name AS supply_name,
    sc.unit AS supply_unit,
    sc.category AS supply_category,
    c.name AS clinic_name,
    c.clinic_id
FROM clinic_inventory ci
JOIN supply_catalog sc ON sc.supply_id = ci.supply_id
JOIN clinics c ON c.clinic_id = ci.clinic_id;

-- ============================================================
-- [6] v_low_stock_items
-- Función   : Insumos con bajo stock (sin filtro de clínica) para alertas de almacén
-- Recibe    : clinic_inventory, clinics, supply_catalog
-- Devuelve  : Una fila por ítem cuya quantity < min_stock con datos de clínica e insumo
-- ============================================================
CREATE OR REPLACE VIEW v_low_stock_items AS
SELECT
    ci.inventory_id,
    c.clinic_id,
    c.name   AS clinic_name,
    sc.name  AS supply_name,
    ci.quantity,
    ci.min_stock
FROM clinic_inventory ci
JOIN clinics        c  ON ci.clinic_id = c.clinic_id
JOIN supply_catalog sc ON ci.supply_id = sc.supply_id
WHERE ci.quantity < ci.min_stock;

-- ============================================================
-- [7] vw_worker_full
-- Función   : Trabajadores con detalles completos: nombre, rol y correos electrónicos
-- Recibe    : workers, roles, worker_emails
-- Devuelve  : Una fila por trabajador-email con full_name, role_name y flag is_primary_email
-- ============================================================
CREATE OR REPLACE VIEW vw_worker_full AS
SELECT
    w.worker_id,
    w.first_name,
    w.last_name,
    w.first_name || ' ' || w.last_name AS full_name,
    r.name AS role_name,
    r.role_id,
    we.email,
    we.is_primary AS is_primary_email
FROM workers w
LEFT JOIN roles r ON w.role_id = r.role_id
LEFT JOIN worker_emails we ON we.worker_id = w.worker_id;

-- ============================================================
-- [8] v_patient_vaccination_scheme_base
-- Función   : Define el esquema vacunal completo del paciente con todos los joins reutilizables para reportes y SPs
-- Recibe    : patient_vaccine_schedule, patients, scheme_doses, vaccines, vaccination_records, workers, application_sites
-- Devuelve  : Una fila por dosis programada de paciente activo con estado (Aplicada/Atrasada/Pendiente), días de retraso y próxima dosis
-- ============================================================
CREATE OR REPLACE VIEW v_patient_vaccination_scheme_base AS

SELECT
    pvs.schedule_id,
    p.patient_id,
    sd.dose_id,
    v.vaccine_id,


    p.first_name,
    p.last_name,
    TRIM(p.first_name || ' ' || p.last_name)
        AS full_name,
    p.birth_date,
    DATE_PART(
        'year',
        AGE(CURRENT_DATE, p.birth_date)
    )::INT AS age_years,


    v.name AS vaccine_name,
    v.disease_prevented,
    sd.dose_label,
    sd.dose_number,
    sd.ideal_age_months,

    (
        p.birth_date
        +
        (sd.ideal_age_months || ' months')::INTERVAL
    )::DATE AS ideal_date,

    vr.record_id,
    vr.applied_date,
    vr.had_reaction,
    vr.patient_temp_c,
    vr.lot_id,

    COALESCE(
        TRIM(w.first_name || ' ' || w.last_name),
        '—'
    ) AS doctor,


    COALESCE(
        aps.application_site,
        '—'
    ) AS application_site,

    CASE

        WHEN vr.record_id IS NOT NULL THEN
            'Aplicada'

        WHEN pvs.due_date < CURRENT_DATE THEN
            'Atrasada'

        ELSE
            'Pendiente'

    END AS vaccination_status,


    CASE
        WHEN vr.record_id IS NOT NULL THEN
            0
        ELSE
            CURRENT_DATE - pvs.due_date
    END AS dias_retraso,

    (
        SELECT MIN(sd2.ideal_age_months)
        FROM scheme_doses sd2
        WHERE sd2.vaccine_id = sd.vaccine_id
          AND sd2.dose_number > sd.dose_number
          AND NOT EXISTS (
                SELECT 1
                FROM vaccination_records vr2
                WHERE vr2.patient_id = p.patient_id
                  AND vr2.scheme_dose_id = sd2.dose_id
          )
    ) AS next_dose_age_months

FROM patient_vaccine_schedule pvs
-- PACIENTE
JOIN patients p ON pvs.patient_id = p.patient_id
-- DOSIS DEL ESQUEMA
JOIN scheme_doses sd ON pvs.scheme_dose_id = sd.dose_id
-- VACUNA
JOIN vaccines v ON sd.vaccine_id = v.vaccine_id
-- REGISTRO DE VACUNACIÓN
LEFT JOIN vaccination_records vr
    ON vr.patient_id = p.patient_id
   AND vr.scheme_dose_id = sd.dose_id
-- TRABAJADOR
LEFT JOIN workers w ON w.worker_id = vr.worker_id
-- SITIO DE APLICACIÓN
LEFT JOIN application_sites aps ON aps.application_site_id = vr.application_site_id
WHERE p.is_active = TRUE;

-- ============================================================
-- [9] v_scheme_alerts_full
-- Función   : Alertas de esquema vacunal enriquecidas con datos de paciente, dosis y vacuna
-- Recibe    : scheme_completion_alerts, patient_vaccine_schedule, patients, scheme_doses, vaccines
-- Devuelve  : Una fila por alerta con patient_name, dose_label, vaccine_name, due_date y estados
-- ============================================================
CREATE OR REPLACE VIEW v_scheme_alerts_full AS
SELECT
    sca.alert_id,
    sca.schedule_id,
    sca.alert_type,
    sca.message,
    sca.status                                              AS alert_status,
    sca.read_at,
    sca.created_at,
    pvs.patient_id,
    pvs.due_date,
    pvs.status                                             AS dose_status,
    TRIM(p.first_name || ' ' || p.last_name)              AS patient_name,
    sd.dose_label,
    v.name                                                 AS vaccine_name
FROM scheme_completion_alerts sca
JOIN patient_vaccine_schedule pvs ON pvs.schedule_id = sca.schedule_id
JOIN patients p                   ON p.patient_id    = pvs.patient_id
JOIN scheme_doses sd               ON sd.dose_id     = pvs.scheme_dose_id
JOIN vaccines v                    ON v.vaccine_id   = sd.vaccine_id;

-- ============================================================
-- [10] vw_dashboard_kpis
-- Función   : KPIs del dashboard clínico: pacientes activos, vacunaciones hoy, dosis atrasadas, citas hoy, lotes con bajo stock y lotes próximos a vencer
-- Recibe    : patients, vaccination_records, patient_vaccine_schedule, appointments, vaccine_lots
-- Devuelve  : Una sola fila con todos los conteos del día actual
-- ============================================================
CREATE OR REPLACE VIEW vw_dashboard_kpis AS
SELECT
    -- Pacientes activos
    (SELECT COUNT(*) FROM patients WHERE is_active = TRUE)::INT          AS total_patients,

    -- Vacunaciones hoy
    (SELECT COUNT(*)
     FROM vaccination_records
     WHERE applied_date = CURRENT_DATE)::INT                              AS vaccinations_today,

    -- Dosis atrasadas (pacientes activos)
    (SELECT COUNT(*)
     FROM patient_vaccine_schedule pvs
     JOIN patients p ON p.patient_id = pvs.patient_id
     WHERE pvs.status = 'Atrasada'
       AND p.is_active = TRUE)::INT                                       AS overdue_doses,

    -- Citas pendientes hoy
    (SELECT COUNT(*)
     FROM appointments
     WHERE appointment_status IN ('Programada', 'Confirmada')
       AND DATE(scheduled_at) = CURRENT_DATE)::INT                        AS appointments_today,

    -- Lotes con stock bajo (≤10)
    (SELECT COUNT(*)
     FROM vaccine_lots
     WHERE quantity_available <= 10
       AND expiration_date >= CURRENT_DATE)::INT                          AS low_stock_lots,

    -- Lotes próximos a vencer (≤30 días)
    (SELECT COUNT(*)
     FROM vaccine_lots
     WHERE expiration_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 30
       AND quantity_available > 0)::INT                                   AS expiring_lots;

-- ============================================================
-- [11] nfc_relations
-- Función   : Vista de relaciones NFC-paciente: mapea cada tarjeta NFC a su paciente con fecha de emisión y último escaneo
-- Recibe    : nfc_cards (uid, patient_id, issued_date, last_scanned_at, status)
-- Devuelve  : Una fila por tarjeta NFC con nfc_id, patient_id, issued_date, last_scanned_at y status
-- ============================================================
CREATE OR REPLACE VIEW nfc_relations AS
SELECT
    uid        AS nfc_id,
    patient_id,
    issued_date,
    last_scanned_at,
    status
FROM nfc_cards;
