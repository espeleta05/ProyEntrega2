-- 1. Tiempo promedio de atención por clínica

SELECT 
    c.name AS clinic_name,
    AVG(a.duration_min) AS avg_duration
FROM appointments a
JOIN clinics c ON a.clinic_id = c.clinic_id
WHERE a.duration_min IS NOT NULL
GROUP BY c.name
HAVING AVG(a.duration_min) > 0;

-- Resultado esperado: lista de clínicas con el tiempo promedio de atención en minutos.

-- 2. Pacientes fuera de zona segura
SELECT 
    p.patient_id,
    p.first_name,
    p.last_name,
    gl.latitude,
    gl.longitude,
    gz.zone_name
FROM patients p
JOIN gps_safe_zones gz ON gz.patient_id = p.patient_id
JOIN gps_locations gl ON gl.patient_id = p.patient_id
WHERE gl.recorded_at = (
    SELECT MAX(gl2.recorded_at)
    FROM gps_locations gl2
    WHERE gl2.patient_id = p.patient_id
)
AND (
    (ABS(gl.latitude - gz.center_lat) * 111000) > gz.radius_m
    OR 
    (ABS(gl.longitude - gz.center_lng) * 111000) > gz.radius_m
);

-- Resultado esperado: pacientes que están fuera de su zona segura con su ubicación actual.

-- 3. Adherencia terapéutica por periodo

SELECT 
    DATE_TRUNC('month', vr.applied_date) AS month,
    COUNT(vr.record_id) AS applied_doses,
    COUNT(sd.dose_id) AS expected_doses
FROM scheme_doses sd
LEFT JOIN vaccination_records vr 
    ON vr.scheme_dose_id = sd.dose_id
GROUP BY month
ORDER BY month;

-- Resultado esperado: cantidad de vacunas aplicadas por mes (tendencia histórica).

-- 4. Carga de trabajo por especialidad

SELECT 
    s.name AS specialty,
    COUNT(a.appointment_id) AS total_appointments
FROM appointments a
JOIN workers w ON a.worker_id = w.worker_id
JOIN worker_professional wp ON w.worker_id = wp.worker_id
JOIN specialties s ON wp.specialty_id = s.specialty_id
GROUP BY s.name
ORDER BY total_appointments DESC;

-- Resultado esperado: lista de especialidades con número de citas atendidas.

-- 5. Reacciones adversas por vacuna

SELECT 
    v.name AS vaccine,
    COUNT(pvr.reaction_id) AS total_reactions
FROM post_vaccine_reactions pvr
JOIN vaccination_records vr ON pvr.record_id = vr.record_id
JOIN vaccines v ON vr.vaccine_id = v.vaccine_id
GROUP BY v.name
HAVING COUNT(pvr.reaction_id) > 0
ORDER BY total_reactions DESC;

-- Resultado esperado: vacunas con mayor número de reacciones registradas.

-- 6. Inventario bajo en clínicas

SELECT 
    c.name AS clinic,
    sc.name AS supply,
    ci.quantity,
    ci.min_stock,
    (ci.min_stock - ci.quantity) AS deficit
FROM clinic_inventory ci
JOIN clinics c ON ci.clinic_id = c.clinic_id
JOIN supply_catalog sc ON ci.supply_id = sc.supply_id
WHERE ci.quantity < ci.min_stock
ORDER BY deficit DESC;

-- Resultado esperado: lista de insumos que están por debajo del mínimo.

-- 7. Historial de ubicaciones de un paciente

SELECT 
    p.first_name,
    p.last_name,
    gl.latitude,
    gl.longitude,
    gl.recorded_at,
    LAG(gl.recorded_at) OVER (ORDER BY gl.recorded_at) AS previous_time
FROM gps_locations gl
JOIN patients p ON gl.patient_id = p.patient_id
WHERE p.patient_id = 1
ORDER BY gl.recorded_at DESC;

-- Resultado esperado: historial de ubicaciones ordenado por fecha.


