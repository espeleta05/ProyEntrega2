SET client_encoding = 'UTF8';

-- VER VISTAS
-- \dv --

-- ===================================================
-- VISTAS PARA EL SISTEMA CLÍNICO DE VACUNACIÓN
-- ===================================================

-- Vista 1: Información completa de pacientes (con guardián y alergias)
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

-- Vista 2: Historial de vacunación completo por paciente
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

-- Vista 3: Stock de vacunas disponibles
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

-- Vista 4: Citas enriquecidas (con todos los detalles)
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

-- Vista 5: Estado de inventario de insumos
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

-- Vista 9: Insumos con bajo stock (sin filtro de clínica)
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

-- Vista 10: Trabajadores con detalles (nombres, roles, emails)
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


-- Vista 11: define el esquema completo con joins (reutilizable)
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
-- [NUEVO] Vista 12: Alertas de esquema enriquecidas
-- Reemplaza la lectura directa de scheme_completion_alerts en el backend.
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
-- [REFACTORED] Vista 13: KPIs del dashboard clínico
-- ANTES: usaba CROSS JOIN patients × scheme_doses (explota en prod).
-- AHORA: usa patient_vaccine_schedule como fuente de verdad directa.
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

-- Vista: pacientes con nfc_id — usada por sp_global_search
CREATE OR REPLACE VIEW v_patients_full AS
SELECT
    p.patient_id,
    TRIM(p.first_name || ' ' || p.last_name) AS full_name,
    p.birth_date,
    p.curp,
    p.nfc_id
FROM patients p;