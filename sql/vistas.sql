-- ===================================================
-- Vistas para el sistema clínico de vacunación
-- ===================================================

-- Vista 1: Información completa de vacunación por paciente
CREATE VIEW v_patients_full AS
SELECT
    p.patient_id,
    p.first_name,
    p.last_name,
    p.first_name || ' ' || p.last_name AS full_name,
    p.birth_date,
    p.gender,
    p.weight_kg,
    p.premature,
    bt.blood_type,
    g.first_name || ' ' || g.last_name AS guardian_name,
    ph.phone AS guardian_phone,
    STRING_AGG(al.name, ', ') AS allergies
FROM patients p
LEFT JOIN blood_types bt ON bt.blood_type_id = p.blood_type_id
LEFT JOIN patient_guardian_relations pgr ON pgr.patient_id = p.patient_id AND pgr.is_primary = TRUE
LEFT JOIN guardians g ON g.guardian_id = pgr.guardian_id
LEFT JOIN guardian_phones ph ON ph.guardian_id = g.guardian_id AND ph.is_primary = TRUE
LEFT JOIN patient_allergies pa ON pa.patient_id = p.patient_id
LEFT JOIN allergies al ON al.allergy_id = pa.allergy_id
GROUP BY p.patient_id, bt.blood_type, g.first_name, g.last_name, ph.phone;

-- Vista 2: Historial de vacunación por paciente
CREATE VIEW v_vaccination_records_full AS
SELECT
    vr.record_id,
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
JOIN scheme_doses sd ON sd.dose_id = vr.scheme_dose_id
JOIN application_sites aps ON aps.application_site_id = vr.application_site_id
JOIN clinics c ON c.clinic_id = vr.clinic_id;

-- Vista 3: Inventario de vacunas 
CREATE VIEW v_vaccine_stock AS
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

-- Vista 4: Citas 
CREATE VIEW v_appointments_full AS
SELECT
    a.appointment_id,
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

-- Vista 5: Status de inventario
CREATE VIEW v_inventory_status AS
SELECT
    ci.inventory_id,
    ci.quantity,
    ci.min_stock,
    ci.last_updated,
    (ci.quantity < ci.min_stock) AS low_stock,
    sc.name AS supply_name,
    sc.unit AS supply_unit,
    sc.category AS supply_category,
    c.name AS clinic_name
FROM clinic_inventory ci
JOIN supply_catalog sc ON sc.supply_id = ci.supply_id
JOIN clinics c ON c.clinic_id = ci.clinic_id;

-- Vista 6: Dosis pendientes por paciente según esquema oficial
CREATE VIEW v_pending_scheme_doses AS
SELECT
    p.patient_id,
    v.name AS vaccine_name,
    sd.dose_label,
    sd.ideal_age_months
FROM patients p
CROSS JOIN scheme_doses sd
JOIN vaccines v ON v.vaccine_id = sd.vaccine_id
WHERE NOT EXISTS (
    SELECT 1 FROM vaccination_records vr
    WHERE vr.patient_id = p.patient_id
    AND vr.scheme_dose_id = sd.dose_id
);

