
--- 1. ANÁLISIS CLÍNICO

--- A. Evaluación de Riesgo Pre-Vacunación (Historial y Alergias)
--- Objetivo: Antes de aplicar una vacuna, obtener un resumen completo del paciente: edad exacta, alergias activas, peso y última vacuna aplicada para evitar eventos adversos.

WITH patient_age AS (
    SELECT 
        patient_id,
        EXTRACT(YEAR FROM AGE(CURRENT_DATE, birth_date)) AS years,
        EXTRACT(MONTH FROM AGE(CURRENT_DATE, birth_date)) AS months
    FROM patients
    WHERE is_active = TRUE
)
SELECT 
    p.patient_id,
    CONCAT(p.first_name, ' ', p.last_name) AS nombre_paciente,
    pa.years || ' años ' || pa.months || ' meses' AS edad_actual,
    p.blood_type,
    p.weight_kg,
    COALESCE(
        STRING_AGG(DISTINCT ac.name || ' (' || pax.severity || ')', ', '),
        'Sin alergias registradas'
    ) AS alergias_criticas,
    MAX(vr.applied_date) AS ultima_vacuna
FROM patients p
JOIN patient_age pa ON p.patient_id = pa.patient_id
LEFT JOIN patient_allergies pax ON p.patient_id = pax.patient_id
LEFT JOIN allergy_catalog ac ON pax.allergy_id = ac.allergy_id
LEFT JOIN vaccination_records vr ON p.patient_id = vr.patient_id
WHERE p.patient_id = :patient_id_param
GROUP BY p.patient_id, pa.years, pa.months, p.blood_type, p.weight_kg;

--- B. Cumplimiento de Esquema Oficial (Dosis Faltantes)
--- Objetivo: Comparar la edad del paciente contra el esquema oficial vigente para detectar dosis pendientes o retrasadas, ignorando las ya aplicadas.

SELECT 
    p.patient_id,
    CONCAT(p.first_name, ' ', p.last_name) AS paciente,
    v.name AS vacuna_pendiente,
    sd.dose_label,
    sd.ideal_age_months AS mes_ideal,
    (EXTRACT(YEAR FROM AGE(CURRENT_DATE, p.birth_date)) * 12 +
     EXTRACT(MONTH FROM AGE(CURRENT_DATE, p.birth_date))) AS edad_actual_meses,
    ((EXTRACT(YEAR FROM AGE(CURRENT_DATE, p.birth_date)) * 12 +
      EXTRACT(MONTH FROM AGE(CURRENT_DATE, p.birth_date))) - sd.ideal_age_months) AS meses_retraso
FROM patients p
CROSS JOIN vaccination_schemes vs
JOIN scheme_doses sd ON vs.scheme_id = sd.scheme_id
JOIN vaccines v ON sd.vaccine_id = v.vaccine_id
WHERE vs.is_current = TRUE
AND p.is_active = TRUE
AND (EXTRACT(YEAR FROM AGE(CURRENT_DATE, p.birth_date)) * 12 +
     EXTRACT(MONTH FROM AGE(CURRENT_DATE, p.birth_date))) >= sd.ideal_age_months
AND NOT EXISTS (
    SELECT 1 
    FROM vaccination_records vr
    WHERE vr.patient_id = p.patient_id 
      AND vr.scheme_dose_id = sd.dose_id
      AND vr.is_cancelled = FALSE
)
ORDER BY p.patient_id, sd.ideal_age_months;

--- 2. MÉTRICAS OPERATIVAS

--- A. Inventario en Riesgo (Stock Bajo y Próximos a Vencer)
--- Objetivo: Alertar al área de Almacén sobre lotes que necesitan reposición urgente o descarte por caducidad (regla 30 días).

SELECT 
    c.name AS clinica,
    v.name AS vacuna,
    vl.lot_number,
    vl.quantity_available AS stock_actual,
    vl.expiration_date,
    (vl.expiration_date - CURRENT_DATE) AS dias_para_vencer,
    CASE 
        WHEN vl.quantity_available = 0 THEN 'SIN STOCK'
        WHEN vl.quantity_available < 10 THEN 'STOCK CRITICO'
        WHEN (vl.expiration_date - CURRENT_DATE) <= 30 THEN 'PROXIMO A VENCER'
        ELSE 'OK'
    END AS estado_alerta
FROM vaccine_lots vl
JOIN vaccines v ON vl.vaccine_id = v.vaccine_id
JOIN clinics c ON vl.clinic_id = c.clinic_id
WHERE vl.is_active = TRUE
  AND (
      vl.quantity_available < 10 
      OR (vl.expiration_date - CURRENT_DATE) <= 30
  )
ORDER BY estado_alerta DESC, vl.expiration_date ASC;


--- B. Rendimiento del Personal (Tasa de Vacunación y Reacciones)
--- Objetivo: Evaluar a los enfermeros por cantidad de aplicaciones y frecuencia de reacciones adversas reportadas.

SELECT 
    w.worker_id,
    CONCAT(w.first_name, ' ', w.last_name) AS enfermero,
    c.name AS clinica_asignada,
    COUNT(vr.record_id) AS total_aplicaciones,
    COUNT(pvr.reaction_id) AS total_reacciones,
    ROUND(
        (COUNT(pvr.reaction_id)::NUMERIC / NULLIF(COUNT(vr.record_id), 0)) * 100, 
    2) AS tasa_reacciones_pct
FROM workers w
JOIN roles r ON w.role_id = r.role_id
JOIN worker_clinic_assignment wca 
    ON w.worker_id = wca.worker_id AND wca.is_active = TRUE
JOIN clinics c ON wca.clinic_id = c.clinic_id
JOIN vaccination_records vr ON w.worker_id = vr.worker_id
LEFT JOIN post_vaccine_reactions pvr ON vr.record_id = pvr.record_id
WHERE r.name = 'Enfermero'
AND vr.applied_date >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY w.worker_id, c.name
ORDER BY total_aplicaciones DESC;

--- 3. MONITOREO DE EVENTOS (NFC, GPS Y BEACONS)

--- A. Trazabilidad de Movimiento (Últimas 24 horas)
--- Objetivo: Reconstruir la ruta del paciente dentro de la clínica usando los logs de escaneo (NFC/BEACONS).

SELECT 
    p.patient_id,
    CONCAT(p.first_name, ' ', p.last_name) AS paciente,
    ca.name AS ubicacion_detectada,
    sl.scanned_at,
    sl.scan_type,
    CASE 
        WHEN sl.beacon_id IS NOT NULL THEN 'BLE' 
        WHEN sl.source_device IS NOT NULL THEN 'NFC' 
        ELSE 'Otro' 
    END AS tecnologia
FROM scan_logs sl
JOIN patients p ON sl.patient_id = p.patient_id
LEFT JOIN beacons b ON sl.beacon_id = b.beacon_id
LEFT JOIN clinic_areas ca ON b.area_id = ca.area_id
WHERE sl.scanned_at >= NOW() - INTERVAL '24 hours'
ORDER BY sl.scanned_at DESC;

--- B. Detección de Anomalías de Ubicación (GPS)
-- Objetivo: Identificar pacientes que salieron de su zona segura y no han regresado, o cuyo dispositivo perdió señal.

SELECT 
    p.patient_id,
    CONCAT(p.first_name, ' ', p.last_name) AS nombre,
    gra.alert_type,
    gra.triggered_at,
    gra.location_lat,
    gra.location_lng,
    CASE 
        WHEN gra.resolved_at IS NULL THEN 'ACTIVA'
        ELSE 'RESUELTA'
    END AS estado_alerta,
    g.guardian_id 
FROM gps_risk_alerts gra
JOIN patients p ON gra.patient_id = p.patient_id
JOIN patient_guardian_relations pgr 
    ON p.patient_id = pgr.patient_id AND pgr.is_primary = TRUE
JOIN guardians g ON pgr.guardian_id = g.guardian_id
WHERE gra.resolved_at IS NULL
AND gra.triggered_at >= NOW() - INTERVAL '4 hours'
ORDER BY gra.triggered_at DESC;

--- 4. REPORTES ADMINISTRATIVOS

--- A. Reporte de Cobertura por Institución (SSA, IMSS, etc.)
--- Objetivo: Estadísticas mensuales comparativas entre diferentes clínicas.

SELECT 
    c.institution_type,
    c.name AS clinica,
    DATE_TRUNC('month', vr.applied_date) AS mes,
    COUNT(DISTINCT vr.patient_id) AS pacientes_atendidos,
    COUNT(vr.record_id) AS dosis_totales,
    COUNT(DISTINCT vr.vaccine_id) AS tipos_vacunas_usadas
FROM vaccination_records vr
JOIN clinics c ON vr.clinic_id = c.clinic_id
WHERE vr.applied_date >= DATE_TRUNC('year', CURRENT_DATE) -- Año actual
  AND vr.is_cancelled = FALSE
GROUP BY ROLLUP (c.institution_type, c.name, DATE_TRUNC('month', vr.applied_date))
ORDER BY c.institution_type, mes DESC;

--- B. Auditoría de Seguridad (Accesos y Modificaciones)
--- Objetivo: Detectar actividades sospechosas o errores de sistema en el último día.

SELECT 
    al.audit_id,
    al.table_name,
    al.action,
    CONCAT(w.first_name, ' ', w.last_name) AS usuario_responsable,
    al.changed_at,
    al.ip_address,
    al.old_data ->> 'status' AS estado_anterior, 
    al.new_data ->> 'status' AS estado_nuevo
FROM audit_log al
JOIN workers w ON al.worker_id = w.worker_id
WHERE al.changed_at >= NOW() - INTERVAL '24 hours'
  AND (al.action = 'DELETE' OR al.table_name IN ('vaccination_records', 'patient_allergies', 'workers'))
ORDER BY al.changed_at DESC;
