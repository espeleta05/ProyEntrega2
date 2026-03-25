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


-- 8. Calcular el porcentaje de avance de cada paciente respecto al esquema de vacunación vigente. Identifica qué pacientes tienen un esquema incompleto para enviar campañas de recordatorio.

WITH esquema_actual AS (
    SELECT sd.dose_id, sd.vaccine_id, v.name AS vacuna
    FROM scheme_doses sd
    JOIN vaccination_scheme vs ON sd.scheme_id = vs.scheme_id
    JOIN vaccines v ON sd.vaccine_id = v.vaccine_id
    WHERE vs.is_current = TRUE
),
dosis_aplicadas AS (
    SELECT patient_id, vaccine_id, COUNT(*) as total_aplicadas
    FROM vaccination_records
    GROUP BY patient_id, vaccine_id
)
SELECT 
    p.curp,
    p.first_name || ' ' || p.last_name AS paciente,
    COUNT(ea.dose_id) AS dosis_requeridas,
    COALESCE(SUM(da.total_aplicadas), 0) AS dosis_totales_recibidas,
    ROUND((COALESCE(SUM(da.total_aplicadas), 0) * 100.0 / COUNT(ea.dose_id)), 2) || '%' AS porcentaje_adherencia
FROM patients p
CROSS JOIN esquema_actual ea
LEFT JOIN dosis_aplicadas da ON p.patient_id = da.patient_id AND ea.vaccine_id = da.vaccine_id
GROUP BY p.patient_id, p.curp, p.first_name, p.last_name
HAVING COUNT(ea.dose_id) > 0
ORDER BY porcentaje_adherencia ASC;

-- Resultado esperado: Un listado de todos los pacientes con su porcentaje de cumplimiento (ej. 100% para esquemas completos, 20% para quienes solo tienen la primera dosis de varias).


-- 9. Métricas sobre el inventario para predecir cuándo se quedará la clínica sin vacunas, comparando lo recibido contra lo disponible actualmente.

SELECT 
    c.name AS clinica,
    v.name AS vacuna,
    vl.lot_number,
    vl.quantity_received,
    vl.quantity_available,
    ROUND(((vl.quantity_received - vl.quantity_available) * 100.0 / vl.quantity_received), 2) AS porcentaje_consumo,
    vl.expiration_date
FROM vaccine_lots vl
JOIN clinics c ON vl.clinic_id = c.clinic_id
JOIN vaccines v ON vl.vaccine_id = v.vaccine_id
WHERE vl.quantity_available < (vl.quantity_received * 0.2) -- Lotes con menos del 20% disponible
   OR vl.expiration_date < CURRENT_DATE + INTERVAL '30 days'
ORDER BY vl.expiration_date ASC, porcentaje_consumo DESC;

-- Resultado esperado: Una lista de alerta roja que muestra lotes próximos a caducar o que están a punto de agotarse (stock crítico).

-- 10. 