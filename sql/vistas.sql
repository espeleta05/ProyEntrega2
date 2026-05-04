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
    p.first_name || ' ' || p.last_name AS full_name,
    p.birth_date,
    p.gender,
    p.weight_kg,
    p.premature,
    p.curp,
    bt.blood_type,
    g.first_name || ' ' || g.last_name AS guardian_name,
    ph.phone AS guardian_phone,
    STRING_AGG(DISTINCT al.name, ', ') AS allergies
FROM patients p
LEFT JOIN blood_types bt ON bt.blood_type_id = p.blood_type_id
LEFT JOIN patient_guardian_relations pgr ON pgr.patient_id = p.patient_id AND pgr.is_primary = TRUE
LEFT JOIN guardians g ON g.guardian_id = pgr.guardian_id
LEFT JOIN guardian_phones ph ON ph.guardian_id = g.guardian_id AND ph.is_primary = TRUE
LEFT JOIN patient_allergies pa ON pa.patient_id = p.patient_id
LEFT JOIN allergies al ON al.allergy_id = pa.allergy_id
GROUP BY p.patient_id, bt.blood_type, g.first_name, g.last_name, ph.phone;

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
CREATE OR REPLACE VIEW v_appointments_full AS
SELECT
    a.appointment_id,
    a.patient_id,
    a.worker_id,
    a.clinic_id,
    a.area_id,
    a.scheduled_at,
    a.duration_min,
    a.reason,
    a.appointment_status,
    a.appointment_notes,
    p.first_name || ' ' || p.last_name AS patient_name,
    w.first_name || ' ' || w.last_name AS worker_name,
    c.name AS clinic_name,
    ca.name AS area_name
FROM appointments a
JOIN patients p ON p.patient_id = a.patient_id
JOIN workers w ON w.worker_id = a.worker_id
JOIN clinics c ON c.clinic_id = a.clinic_id
LEFT JOIN clinic_areas ca ON ca.area_id = a.area_id;

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

-- Vista 6: Dosis pendientes por paciente según esquema oficial
CREATE OR REPLACE VIEW v_pending_scheme_doses AS
SELECT
    p.patient_id,
    v.name AS vaccine_name,
    v.vaccine_id,
    sd.dose_label,
    sd.ideal_age_months,
    sd.dose_id
FROM patients p
CROSS JOIN scheme_doses sd
JOIN vaccines v ON v.vaccine_id = sd.vaccine_id
WHERE NOT EXISTS (
    SELECT 1 FROM vaccination_records vr
    WHERE vr.patient_id = p.patient_id
    AND vr.scheme_dose_id = sd.dose_id
);

-- Vista 7: Métricas generales del dashboard (sin filtro de fecha)
CREATE OR REPLACE VIEW v_dashboard_metrics AS
SELECT
    COUNT(DISTINCT p.patient_id)::BIGINT                                                          AS total_patients,
    COUNT(DISTINCT vr.patient_id)::BIGINT                                                         AS vaccinated_patients,
    COUNT(DISTINCT a.appointment_id)   FILTER (WHERE a.appointment_status = 'Programada')::BIGINT AS pending_appointments,
    COUNT(DISTINCT ci.inventory_id)    FILTER (WHERE ci.quantity < ci.min_stock)::BIGINT           AS low_stock_items,
    COUNT(DISTINCT sca.alert_id)       FILTER (WHERE sca.status  = 'Pendiente')::BIGINT            AS pending_alerts,
    ROUND(
        COUNT(DISTINCT vr.patient_id)::NUMERIC /
        NULLIF(COUNT(DISTINCT p.patient_id)::NUMERIC, 0) * 100, 2
    )::NUMERIC                                                                                     AS coverage_percentage
FROM patients p
LEFT JOIN vaccination_records          vr  ON p.patient_id  = vr.patient_id
LEFT JOIN appointments                 a   ON p.patient_id  = a.patient_id
LEFT JOIN clinic_inventory             ci  ON ci.quantity   < ci.min_stock
LEFT JOIN scheme_completion_alerts     sca ON p.patient_id  = sca.patient_id;

-- Vista 8: Pacientes con dosis atrasadas (sin umbral de días)
CREATE OR REPLACE VIEW v_delayed_patients AS
SELECT
    p.patient_id,
    p.first_name || ' ' || p.last_name  AS patient_name,
    v.name                               AS vaccine_name,
    sca.due_date,
    (NOW()::DATE - sca.due_date)::INT    AS days_late
FROM patients p
JOIN scheme_completion_alerts sca ON p.patient_id      = sca.patient_id
JOIN scheme_doses             sd  ON sca.scheme_dose_id = sd.dose_id
JOIN vaccines                 v   ON sd.vaccine_id      = v.vaccine_id
WHERE sca.status = 'Pendiente'
  AND NOW()::DATE > sca.due_date;

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
CREATE OR REPLACE VIEW v_worker_full AS
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

-- ==============================================
-- FIN VISTAS
-- ==============================================
