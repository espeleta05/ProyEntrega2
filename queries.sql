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
    SELECT 
    p.first_name,
    p.last_name,
    gl.latitude,
    gl.longitude,
    gl.recorded_at,
    LAG(gl.recorded_at) OVER (
        PARTITION BY p.patient_id 
        ORDER BY gl.recorded_at
    ) AS previous_time
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

-- 9. Calcular el nivel de riesgo de cada paciente
WITH conteo_alergias AS (
    -- Cuenta alergias de severidad Alta o Crítica por paciente
    SELECT 
        patient_id, 
        COUNT(*) * 4 AS puntos_alergias
    FROM patient_allergies
    WHERE severity ILIKE '%alta%' OR severity ILIKE '%crítica%'
    GROUP BY patient_id
),
conteo_vacunas AS (
    -- Cuenta vacunas pendientes cuya fecha límite ya pasó
    SELECT 
        patient_id, 
        COUNT(*) * 2 AS puntos_vacunas
    FROM scheme_completion_alerts
    WHERE status = 'Pendiente' AND due_date < CURRENT_DATE
    GROUP BY patient_id
),
conteo_gps AS (
    -- Cuenta alertas de GPS que no han sido resueltas
    SELECT 
        patient_id, 
        COUNT(*) * 5 AS puntos_gps
    FROM gps_risk_alerts
    WHERE resolved_at IS NULL
    GROUP BY patient_id
)
SELECT 
    p.patient_id,
    p.curp,
    p.first_name || ' ' || p.last_name AS nombre_completo,
    p.birth_date,
    -- Cálculo del Score Total
    (
        CASE WHEN p.premature THEN 3 ELSE 0 END +
        COALESCE(ca.puntos_alergias, 0) +
        COALESCE(cv.puntos_vacunas, 0) +
        COALESCE(cg.puntos_gps, 0)
    ) AS risk_score,
    -- Clasificación dinámica
    CASE 
        WHEN (CASE WHEN p.premature THEN 3 ELSE 0 END + COALESCE(ca.puntos_alergias, 0) + COALESCE(cv.puntos_vacunas, 0) + COALESCE(cg.puntos_gps, 0)) >= 8 THEN 'Crítico'
        WHEN (CASE WHEN p.premature THEN 3 ELSE 0 END + COALESCE(ca.puntos_alergias, 0) + COALESCE(cv.puntos_vacunas, 0) + COALESCE(cg.puntos_gps, 0)) >= 5 THEN 'Alto'
        WHEN (CASE WHEN p.premature THEN 3 ELSE 0 END + COALESCE(ca.puntos_alergias, 0) + COALESCE(cv.puntos_vacunas, 0) + COALESCE(cg.puntos_gps, 0)) >= 2 THEN 'Medio'
        ELSE 'Bajo'
    END AS risk_level
FROM patients p
LEFT JOIN conteo_alergias ca ON p.patient_id = ca.patient_id
LEFT JOIN conteo_vacunas cv ON p.patient_id = cv.patient_id
LEFT JOIN conteo_gps cg ON p.patient_id = cg.patient_id
ORDER BY risk_score DESC;

--Resultado esperado: Una lista ordenada de los pacientes con mayor riesgo a menor riesgo

-- 10. Como saber que vacunas te dan mas problemas para despues reportarlo al fabricante
SELECT 
    v.name AS vacuna, 
    m.name AS fabricante,
    COUNT(pvr.reaction_id) AS total_reacciones,
    MAX(pvr.severity) AS severidad_maxima
FROM vaccines v
JOIN manufacturers m ON v.manufacturer_id = m.manufacturer_id
JOIN vaccination_records vr ON v.vaccine_id = vr.vaccine_id
JOIN post_vaccine_reactions pvr ON vr.record_id = pvr.record_id
GROUP BY v.name, m.name
ORDER BY total_reacciones DESC
LIMIT 3;

-- Resultado esperado: Una lista con las 3 vacunas que tienen más reportes de síntomas post-vacunación.

-- 11. Cuál es el enfermero o doctor que más vacunas ha aplicado este mes en cada clínica
SELECT 
    c.name AS clinica,
    w.first_name || ' ' || w.last_name AS trabajador,
    COUNT(vr.record_id) AS aplicaciones_realizadas
FROM workers w
JOIN vaccination_records vr ON w.worker_id = vr.worker_id
JOIN clinics c ON vr.clinic_id = c.clinic_id
WHERE vr.applied_date >= CURRENT_DATE - INTERVAL '1 month'
GROUP BY c.name, w.worker_id, w.first_name, w.last_name
ORDER BY c.name, aplicaciones_realizadas DESC;

-- Un ranking de la productividad del personal

-- 12. Mostrar una lista de pacientes que están registrados pero no tienen ninguna vacuna aplicada ni citas programadas
SELECT 
    p.patient_id, 
    p.first_name || ' ' || p.last_name AS paciente,
    p.curp
FROM patients p
LEFT JOIN vaccination_records vr ON p.patient_id = vr.patient_id
LEFT JOIN appointments a ON p.patient_id = a.patient_id
WHERE vr.record_id IS NULL 
  AND a.appointment_id IS NULL;

-- Resultado esperado: Pacientes que probablemente se registraron pero abandonaron el seguimiento