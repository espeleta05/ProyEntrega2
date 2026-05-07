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


--============================================================================
-- Vista 7: Métricas generales del dashboard (sin filtro de fecha)
CREATE OR REPLACE VIEW vw_dashboard_kpis AS
WITH
-- Fechas de referencia
fechas AS (
    SELECT
        CURRENT_DATE                                                       AS hoy,
        DATE_TRUNC('week',  CURRENT_DATE)::DATE                            AS inicio_semana,
        DATE_TRUNC('month', CURRENT_DATE)::DATE                            AS inicio_mes,
        (DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 month')::DATE     AS inicio_mes_anterior,
        (DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 day')::DATE       AS fin_mes_anterior
),
-- Total pacientes activos
total_pacientes AS (
    SELECT COUNT(*)::INT AS total_patients
    FROM   patients
    WHERE  is_active = TRUE
),
 
-- Cobertura: % pacientes con todo el esquema completado
cobertura AS (
    SELECT
        ROUND(
            COUNT(DISTINCT CASE
                WHEN NOT EXISTS (
                    SELECT 1 FROM scheme_doses sd
                    WHERE NOT EXISTS (
                        SELECT 1 FROM vaccination_records vr
                        WHERE vr.patient_id     = p.patient_id
                          AND vr.scheme_dose_id  = sd.dose_id
                    )
                ) THEN p.patient_id
            END)::NUMERIC
            / NULLIF(COUNT(DISTINCT p.patient_id)::NUMERIC, 0) * 100
        , 1)                                                                AS coverage_pct
    FROM patients p, fechas
    WHERE p.is_active = TRUE
),
 
-- Tendencia de cobertura: dosis este mes vs mes anterior
tendencia_cobertura AS (
    SELECT
        (
            SELECT COUNT(*) FROM vaccination_records vr, fechas
            WHERE  vr.applied_date >= fechas.inicio_mes
              AND  vr.applied_date <= fechas.hoy
        ) -
        (
            SELECT COUNT(*) FROM vaccination_records vr, fechas
            WHERE  vr.applied_date >= fechas.inicio_mes_anterior
              AND  vr.applied_date <= fechas.fin_mes_anterior
        )                                                                   AS coverage_trend
),
 
-- Pacientes con al menos 1 dosis atrasada
atrasados AS (
    SELECT COUNT(DISTINCT p.patient_id)::INT                               AS delayed_patients
    FROM   patients p, scheme_doses sd, fechas
    WHERE  p.is_active = TRUE
      AND  (p.birth_date + (sd.ideal_age_months || ' months')::INTERVAL)::DATE < fechas.hoy
      AND  NOT EXISTS (
               SELECT 1 FROM vaccination_records vr
               WHERE vr.patient_id     = p.patient_id
                 AND vr.scheme_dose_id  = sd.dose_id
           )
),
 
-- Pacientes críticos: 2+ dosis atrasadas
criticos AS (
    SELECT COUNT(*)::INT                                                    AS patients_critical
    FROM (
        SELECT p.patient_id
        FROM   patients p, scheme_doses sd, fechas
        WHERE  p.is_active = TRUE
          AND  (p.birth_date + (sd.ideal_age_months || ' months')::INTERVAL)::DATE < fechas.hoy
          AND  NOT EXISTS (
                   SELECT 1 FROM vaccination_records vr
                   WHERE vr.patient_id     = p.patient_id
                     AND vr.scheme_dose_id  = sd.dose_id
               )
        GROUP  BY p.patient_id
        HAVING COUNT(*) >= 2
    ) sub
),
 
-- Dosis aplicadas: hoy / esta semana / este mes
dosis AS (
    SELECT
        COUNT(*) FILTER (WHERE vr.applied_date  = f.hoy)                ::INT AS applications_today,
        COUNT(*) FILTER (WHERE vr.applied_date >= f.inicio_semana)      ::INT AS doses_this_week,
        COUNT(*) FILTER (WHERE vr.applied_date >= f.inicio_mes)         ::INT AS doses_this_month
    FROM vaccination_records vr, fechas f
),
 
-- Tendencia mensual %
tendencia_mensual AS (
    SELECT
        CASE
            WHEN prev_cnt = 0 THEN 0
            ELSE ROUND((curr_cnt - prev_cnt)::NUMERIC / prev_cnt * 100, 1)::INT
        END                                                                AS monthly_trend
    FROM (
        SELECT
            (SELECT COUNT(*) FROM vaccination_records vr, fechas f
             WHERE  vr.applied_date >= f.inicio_mes
               AND  vr.applied_date <= f.hoy)::NUMERIC                     AS curr_cnt,
            (SELECT COUNT(*) FROM vaccination_records vr, fechas f
             WHERE  vr.applied_date >= f.inicio_mes_anterior
               AND  vr.applied_date <= f.fin_mes_anterior)::NUMERIC        AS prev_cnt
    ) sub
),
 
-- Pacientes con dosis vencidas (fecha ideal ya pasó y no se aplicó)
vencidas AS (
    SELECT COUNT(DISTINCT p.patient_id)::INT                               AS expired_doses
    FROM   patients p, scheme_doses sd, fechas f
    WHERE  p.is_active = TRUE
      AND  (p.birth_date + (sd.ideal_age_months || ' months')::INTERVAL)::DATE < f.hoy
      AND  NOT EXISTS (
               SELECT 1 FROM vaccination_records vr
               WHERE vr.patient_id     = p.patient_id
                 AND vr.scheme_dose_id  = sd.dose_id
           )
),
 
-- Nuevos pacientes registrados este mes
nuevos AS (
    SELECT COUNT(*)::INT                                                    AS new_patients_month
    FROM   patients p, fechas f
    WHERE  p.is_active      = TRUE
      AND  p.created_at::DATE >= f.inicio_mes
),
 
-- Lotes que vencen en los próximos 7 días
lotes_por_vencer AS (
    SELECT COUNT(*)::INT                                                    AS expiring_lots_week
    FROM   vaccine_lots vl, fechas f
    WHERE  vl.expiration_date >= f.hoy
      AND  vl.expiration_date <= f.hoy + INTERVAL '7 days'
      AND  vl.quantity_available > 0
),
 
-- Insumos con stock bajo
stock_bajo AS (
    SELECT COUNT(*)::INT                                                    AS low_stock_count
    FROM   clinic_inventory
    WHERE  quantity < min_stock
),
 
-- Alertas de esquema pendientes
alertas AS (
    SELECT COUNT(*)::INT                                                    AS pending_alerts
    FROM   scheme_completion_alerts
    WHERE  status = 'Pendiente'
)
 
SELECT
    tp.total_patients,
    cb.coverage_pct,
    COALESCE(tc.coverage_trend, 0)::INT     AS coverage_trend,
    at.delayed_patients,
    cr.patients_critical,
    ds.applications_today,
    ds.doses_this_week,
    ds.doses_this_month,
    tm.monthly_trend,
    vc.expired_doses,
    nv.new_patients_month,
    lv.expiring_lots_week,
    sb.low_stock_count,
    al.pending_alerts
 
FROM total_pacientes    tp
CROSS JOIN cobertura         cb
CROSS JOIN tendencia_cobertura tc
CROSS JOIN atrasados         at
CROSS JOIN criticos          cr
CROSS JOIN dosis             ds
CROSS JOIN tendencia_mensual tm
CROSS JOIN vencidas          vc
CROSS JOIN nuevos            nv
CROSS JOIN lotes_por_vencer  lv
CROSS JOIN stock_bajo        sb
CROSS JOIN alertas           al;
;

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
    -- Identificadores
    p.patient_id,
    sd.dose_id,
 
    -- Datos del paciente
    p.first_name,
    p.last_name,
    TRIM(p.first_name || ' ' || p.last_name)            AS full_name,
    p.birth_date,
    DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT AS age_years,
 
    -- Datos de la vacuna / dosis
    v.vaccine_id,
    v.name                                               AS vaccine_name,
    v.disease_prevented,
    sd.dose_label,
    sd.dose_number,
    sd.ideal_age_months,
 
    -- Fecha ideal de aplicación calculada desde fecha de nacimiento
    (p.birth_date + (sd.ideal_age_months || ' months')::INTERVAL)::DATE
                                                         AS ideal_date,
 
    -- Datos del registro de vacunación (NULL si aún no aplicada)
    vr.record_id,
    vr.applied_date,
    vr.had_reaction,
    vr.patient_temp_c,
    vr.lot_id,
 
    -- Doctor que aplicó
    COALESCE(TRIM(w.first_name || ' ' || w.last_name), '—') AS doctor,
 
    -- Sitio de aplicación
    COALESCE(aps.application_site, '—')                  AS application_site,
 
    -- Estado de la dosis
    CASE
        WHEN vr.record_id IS NOT NULL THEN 'Aplicada'
        WHEN (p.birth_date + (sd.ideal_age_months || ' months')::INTERVAL)::DATE < CURRENT_DATE
             THEN 'Pendiente con retraso'
        ELSE 'Pendiente'
    END                                                  AS estado,
 
    -- Días de retraso (positivo = tarde, negativo = aún no vence)
    CASE
        WHEN vr.record_id IS NOT NULL THEN 0
        ELSE (CURRENT_DATE - (p.birth_date + (sd.ideal_age_months || ' months')::INTERVAL)::DATE)
    END                                                  AS dias_retraso,
 
    -- Próxima dosis esperada para la misma vacuna (si existe una posterior aún no aplicada)
    (
        SELECT MIN(sd2.ideal_age_months)
        FROM scheme_doses sd2
        WHERE sd2.vaccine_id = sd.vaccine_id
          AND sd2.dose_number > sd.dose_number
          AND NOT EXISTS (
              SELECT 1 FROM vaccination_records vr2
              WHERE vr2.patient_id    = p.patient_id
                AND vr2.scheme_dose_id = sd2.dose_id
          )
    )                                                    AS next_dose_age_months
 
FROM patients p
 
-- Cruce completo: cada paciente × cada dosis del esquema
CROSS JOIN scheme_doses sd
JOIN vaccines v ON v.vaccine_id = sd.vaccine_id
 
-- Registro aplicado (si existe)
LEFT JOIN vaccination_records vr
       ON vr.patient_id     = p.patient_id
      AND vr.scheme_dose_id  = sd.dose_id
 
-- Doctor
LEFT JOIN workers w ON w.worker_id = vr.worker_id
 
-- Sitio de aplicación
LEFT JOIN application_sites aps ON aps.application_site_id = vr.application_site_id
 
WHERE p.is_active = TRUE
ORDER BY p.patient_id, sd.ideal_age_months, sd.dose_number;