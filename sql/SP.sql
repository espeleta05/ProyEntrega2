-- ============================================================
-- ARCHIVO: sp.sql
-- Total de objetos: 90
-- ============================================================

SET client_encoding = 'UTF8';

-- VER SPs EN POSTGRES
/*
SELECT routine_name 
FROM information_schema.routines 
WHERE routine_type = 'PROCEDURE' 
AND routine_schema = 'public';
*/

-- ============================================================
-- MÓDULO: WRAPPERS DE VISTAS
-- ============================================================

-- ============================================================
-- [1] sp_get_patients_full
-- Función   : Lista pacientes completos con guardián, contacto y alergias
-- Recibe    : p_limit INT (NULL=todos), p_results REFCURSOR
-- Devuelve  : Filas de patients con datos enriquecidos
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_patients_full(
    IN    p_limit   INT,
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_query TEXT;
BEGIN
    IF p_limit IS NOT NULL AND p_limit > 0 THEN
        OPEN p_results FOR
            SELECT
                p.patient_id,
                p.first_name,
                p.last_name,
                TRIM(p.first_name || ' ' || p.last_name)                AS full_name,
                p.curp,
                p.birth_date,
                p.gender,
                p.weight_kg,
                p.premature,
                p.created_at,
                p.photo,
                p.blood_type_id,
                COALESCE(bt.blood_type, '—')                            AS blood_type,
                DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT AS age,
                COALESCE(TRIM(g.first_name || ' ' || g.last_name), 'Sin tutor') AS guardian,
                COALESCE(
                    (SELECT gp.phone FROM guardian_phones gp
                     WHERE gp.guardian_id = g.guardian_id
                     ORDER BY gp.is_primary DESC LIMIT 1),
                    '—'
                )                                                        AS contact,
                'N/A'::TEXT                                              AS risk,
                COALESCE(
                    NULLIF((
                        SELECT STRING_AGG(al.name, ', ' ORDER BY al.name)
                        FROM patient_allergies pa
                        JOIN allergies al ON al.allergy_id = pa.allergy_id
                        WHERE pa.patient_id = p.patient_id
                    ), ''),
                    'Ninguna'
                )                                                        AS allergies
            FROM patients p
            LEFT JOIN blood_types bt ON bt.blood_type_id = p.blood_type_id
            LEFT JOIN LATERAL (
                SELECT pgr.guardian_id
                FROM   patient_guardian_relations pgr
                WHERE  pgr.patient_id = p.patient_id
                ORDER  BY pgr.is_primary DESC LIMIT 1
            ) rel ON TRUE
            LEFT JOIN guardians g ON g.guardian_id = rel.guardian_id
            WHERE p.is_active != FALSE
            ORDER BY p.created_at DESC
            LIMIT p_limit;
    ELSE
        OPEN p_results FOR
            SELECT
                p.patient_id,
                p.first_name,
                p.last_name,
                TRIM(p.first_name || ' ' || p.last_name)                AS full_name,
                p.curp,
                p.birth_date,
                p.gender,
                p.weight_kg,
                p.premature,
                p.created_at,
                p.photo,
                p.blood_type_id,
                COALESCE(bt.blood_type, '—')                            AS blood_type,
                DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT AS age,
                COALESCE(TRIM(g.first_name || ' ' || g.last_name), 'Sin tutor') AS guardian,
                COALESCE(
                    (SELECT gp.phone FROM guardian_phones gp
                     WHERE gp.guardian_id = g.guardian_id
                     ORDER BY gp.is_primary DESC LIMIT 1),
                    '—'
                )                                                        AS contact,
                'N/A'::TEXT                                              AS risk,
                COALESCE(
                    NULLIF((
                        SELECT STRING_AGG(al.name, ', ' ORDER BY al.name)
                        FROM patient_allergies pa
                        JOIN allergies al ON al.allergy_id = pa.allergy_id
                        WHERE pa.patient_id = p.patient_id
                    ), ''),
                    'Ninguna'
                )                                                        AS allergies
            FROM patients p
            LEFT JOIN blood_types bt ON bt.blood_type_id = p.blood_type_id
            LEFT JOIN LATERAL (
                SELECT pgr.guardian_id
                FROM   patient_guardian_relations pgr
                WHERE  pgr.patient_id = p.patient_id
                ORDER  BY pgr.is_primary DESC LIMIT 1
            ) rel ON TRUE
            LEFT JOIN guardians g ON g.guardian_id = rel.guardian_id
            WHERE p.is_active != FALSE
            ORDER BY p.last_name, p.first_name;
    END IF;
END;
$$;

-- ============================================================
-- [2] sp_get_appointments_full
-- Función   : Devuelve todas las citas de v_appointments_full ordenadas por fecha
-- Recibe    : p_results REFCURSOR
-- Devuelve  : Filas de v_appointments_full DESC
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_appointments_full(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT *
        FROM v_appointments_full
        ORDER BY scheduled_at DESC;
END;
$$;

-- ============================================================
-- [3] sp_dashboard_kpis
-- Función   : KPIs del dashboard clínico con tendencias mensuales y alertas
-- Recibe    : p_results REFCURSOR
-- Devuelve  : Una fila con métricas de cobertura, adherencia, stock y alertas
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_dashboard_kpis(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_today            DATE := CURRENT_DATE;
    v_first_of_month   DATE := DATE_TRUNC('month', CURRENT_DATE)::DATE;
    v_first_of_week    DATE := DATE_TRUNC('week',  CURRENT_DATE)::DATE;
    v_prev_month_start DATE := (DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 month')::DATE;
    v_prev_month_end   DATE := (DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 day')::DATE;
BEGIN
    OPEN p_results FOR
    WITH
 
    -- Total pacientes activos
    total AS (
        SELECT COUNT(*)::INT AS total_patients
        FROM   patients
        WHERE  is_active = TRUE
    ),
 
    -- Cobertura: % de pacientes con todas las dosis del esquema aplicadas
    coverage AS (
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
            , 1)::NUMERIC AS coverage_pct,
 
            -- Tendencia: dosis este mes menos dosis mes anterior
            (
                SELECT COUNT(*) FROM vaccination_records
                WHERE applied_date >= v_first_of_month
                  AND applied_date <= v_today
            ) -
            (
                SELECT COUNT(*) FROM vaccination_records
                WHERE applied_date >= v_prev_month_start
                  AND applied_date <= v_prev_month_end
            )                 AS coverage_trend_raw
        FROM patients p
        WHERE p.is_active = TRUE
    ),
 
    -- Pacientes con al menos 1 dosis atrasada
    delayed AS (
        SELECT COUNT(DISTINCT p.patient_id)::INT AS delayed_patients
        FROM   patients p
        JOIN   scheme_doses sd ON TRUE
        WHERE  p.is_active = TRUE
          AND  (p.birth_date + (sd.ideal_age_months || ' months')::INTERVAL)::DATE < v_today
          AND  NOT EXISTS (
                   SELECT 1 FROM vaccination_records vr
                   WHERE vr.patient_id     = p.patient_id
                     AND vr.scheme_dose_id  = sd.dose_id
               )
    ),
 
    -- Pacientes con 2+ dosis atrasadas (críticos)
    critical AS (
        SELECT COUNT(*)::INT AS patients_critical
        FROM (
            SELECT p.patient_id
            FROM   patients p
            JOIN   scheme_doses sd ON TRUE
            WHERE  p.is_active = TRUE
              AND  (p.birth_date + (sd.ideal_age_months || ' months')::INTERVAL)::DATE < v_today
              AND  NOT EXISTS (
                       SELECT 1 FROM vaccination_records vr
                       WHERE vr.patient_id     = p.patient_id
                         AND vr.scheme_dose_id  = sd.dose_id
                   )
            GROUP  BY p.patient_id
            HAVING COUNT(*) >= 2
        ) sub
    ),
 
    -- Dosis aplicadas: hoy / semana / mes
    doses AS (
        SELECT
            COUNT(*) FILTER (WHERE applied_date = v_today)           ::INT AS applications_today,
            COUNT(*) FILTER (WHERE applied_date >= v_first_of_week)  ::INT AS doses_this_week,
            COUNT(*) FILTER (WHERE applied_date >= v_first_of_month) ::INT AS doses_this_month
        FROM vaccination_records
    ),
 
    -- Tendencia mensual %
    monthly_trend AS (
        SELECT
            CASE
                WHEN prev.cnt = 0 THEN 0
                ELSE ROUND((curr.cnt - prev.cnt)::NUMERIC / prev.cnt * 100, 1)::INT
            END AS monthly_trend
        FROM (
            SELECT COUNT(*)::NUMERIC AS cnt
            FROM   vaccination_records
            WHERE  applied_date >= v_first_of_month
              AND  applied_date <= v_today
        ) curr,
        (
            SELECT COUNT(*)::NUMERIC AS cnt
            FROM   vaccination_records
            WHERE  applied_date >= v_prev_month_start
              AND  applied_date <= v_prev_month_end
        ) prev
    ),
 
    -- Pacientes con alguna dosis ya vencida (fecha ideal pasada, sin aplicar)
    expired AS (
        SELECT COUNT(DISTINCT p.patient_id)::INT AS expired_doses
        FROM   patients p
        JOIN   scheme_doses sd ON TRUE
        WHERE  p.is_active = TRUE
          AND  (p.birth_date + (sd.ideal_age_months || ' months')::INTERVAL)::DATE < v_today
          AND  NOT EXISTS (
                   SELECT 1 FROM vaccination_records vr
                   WHERE vr.patient_id     = p.patient_id
                     AND vr.scheme_dose_id  = sd.dose_id
               )
    ),
 
    -- Nuevos pacientes registrados este mes
    new_patients AS (
        SELECT COUNT(*)::INT AS new_patients_month
        FROM   patients
        WHERE  is_active   = TRUE
          AND  created_at::DATE >= v_first_of_month
    ),
 
    -- Lotes que vencen en los próximos 7 días
    expiring_lots AS (
        SELECT COUNT(*)::INT AS expiring_lots_week
        FROM   vaccine_lots
        WHERE  expiration_date >= v_today
          AND  expiration_date <= v_today + INTERVAL '7 days'
          AND  quantity_available > 0
    ),
 
    -- Insumos con stock bajo
    low_stock AS (
        SELECT COUNT(*)::INT AS low_stock_count
        FROM   clinic_inventory
        WHERE  quantity < min_stock
    ),
 
    -- Alertas de esquema pendientes
    alerts AS (
        SELECT COUNT(*)::INT AS pending_alerts
        FROM   scheme_completion_alerts
        WHERE  status = 'Pendiente'
    )
 
    SELECT
        t.total_patients,
        c.coverage_pct,
        COALESCE(c.coverage_trend_raw, 0)::INT  AS coverage_trend,
        d.delayed_patients,
        ds.applications_today,
        ds.doses_this_week,
        ds.doses_this_month,
        mt.monthly_trend,
        ex.expired_doses,
        np.new_patients_month,
        el.expiring_lots_week,
        ls.low_stock_count,
        al.pending_alerts,
        cr.patients_critical
    FROM total         t
    CROSS JOIN coverage      c
    CROSS JOIN delayed       d
    CROSS JOIN critical      cr
    CROSS JOIN doses         ds
    CROSS JOIN monthly_trend mt
    CROSS JOIN expired       ex
    CROSS JOIN new_patients  np
    CROSS JOIN expiring_lots el
    CROSS JOIN low_stock     ls
    CROSS JOIN alerts        al;
END;
$$;



-- ============================================================
-- MÓDULO: PACIENTES
-- ============================================================

-- ============================================================
-- [4] sp_register_patient
-- Función   : Registra nuevo paciente pediátrico con tutor (crea o reutiliza guardián)
-- Recibe    : datos del paciente y tutor
-- Devuelve  : success, message, patient_id, guardian_id
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_register_patient(
    IN    p_first_name       VARCHAR,
    IN    p_last_name        VARCHAR,
    IN    p_curp             VARCHAR,
    IN    p_birth_date       DATE,
    IN    p_gender           CHAR(1),
    IN    p_blood_type_id    INT,
    IN    p_weight_kg        NUMERIC,
    IN    p_premature        BOOLEAN,
    IN    p_guardian_name    VARCHAR,
    IN    p_guardian_last    VARCHAR,
    IN    p_guardian_curp    VARCHAR,
    IN    p_guardian_phone   VARCHAR,
    IN    p_guardian_email   VARCHAR,
    INOUT p_results          REFCURSOR
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_guardian_id INT;
    v_patient_id  INT;
    v_age_years   INT;
BEGIN

    -- Reglas de negocio y clinicas (Flask ya valido formato basico)

    -- Fecha no puede ser futura (regla de negocio)
    IF p_birth_date IS NULL OR p_birth_date > CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha de nacimiento no puede ser futura';
    END IF;

    -- Edad maxima pediatrica (regla clinica)
    v_age_years := DATE_PART('year', AGE(CURRENT_DATE, p_birth_date));
    IF v_age_years > 15 THEN
        RAISE EXCEPTION 'El paciente excede la edad pediatrica permitida';
    END IF;

    -- CURP duplicado (integridad)
    IF p_curp IS NOT NULL AND EXISTS (
        SELECT 1 FROM patients WHERE curp = p_curp
    ) THEN
        RAISE EXCEPTION 'El CURP ya existe';
    END IF;

    -- Peso fuera de rango (regla clinica)
    IF p_weight_kg IS NOT NULL AND (p_weight_kg <= 0 OR p_weight_kg > 80) THEN
        RAISE EXCEPTION 'Peso fuera de rango pediatrico';
    END IF;

    -- Tipo de sangre inexistente (integridad referencial)
    IF p_blood_type_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM blood_types WHERE blood_type_id = p_blood_type_id
    ) THEN
        RAISE EXCEPTION 'Tipo sanguineo inexistente';
    END IF;

    -- ── Tutor: buscar o crear 

    -- 1. Buscar por CURP (identificador unico, mas confiable)
    IF p_guardian_curp IS NOT NULL AND TRIM(p_guardian_curp) <> '' THEN
        SELECT guardian_id INTO v_guardian_id
        FROM   guardians
        WHERE  curp = UPPER(TRIM(p_guardian_curp))
        LIMIT  1;
    END IF;

    -- 2. Fallback: buscar por nombre completo si no hubo match por CURP
    IF v_guardian_id IS NULL
       AND p_guardian_name IS NOT NULL AND TRIM(p_guardian_name) <> ''
       AND p_guardian_last IS NOT NULL AND TRIM(p_guardian_last) <> ''
    THEN
        SELECT guardian_id INTO v_guardian_id
        FROM   guardians
        WHERE  first_name = TRIM(p_guardian_name)
          AND  last_name  = TRIM(p_guardian_last)
        LIMIT  1;
    END IF;

    -- 3. Si no existe, crear tutor nuevo (con manejo de race condition en CURP)
    IF v_guardian_id IS NULL AND p_guardian_name IS NOT NULL AND TRIM(p_guardian_name) <> '' THEN
        BEGIN
            INSERT INTO guardians (first_name, last_name, curp)
            VALUES (
                TRIM(p_guardian_name),
                TRIM(COALESCE(p_guardian_last, '')),
                NULLIF(UPPER(TRIM(COALESCE(p_guardian_curp, ''))), '')
            )
            RETURNING guardian_id INTO v_guardian_id;
        EXCEPTION
            WHEN unique_violation THEN
                -- CURP ya registrado; recuperar el guardian existente sin modificarlo
                SELECT guardian_id INTO v_guardian_id
                FROM   guardians
                WHERE  curp = NULLIF(UPPER(TRIM(COALESCE(p_guardian_curp, ''))), '');
        END;
    END IF;

    -- 4. Agregar contacto solo si no existe ya (ON CONFLICT DO NOTHING evita duplicados)
    --    Esto aplica tanto a tutores nuevos como a tutores ya existentes.
    IF v_guardian_id IS NOT NULL THEN

        IF p_guardian_phone IS NOT NULL AND TRIM(p_guardian_phone) <> '' THEN
            -- Contar solo digitos para validar longitud minima (regla clinica)
            IF LENGTH(REGEXP_REPLACE(p_guardian_phone, '[^0-9]', '', 'g')) < 10 THEN
                RAISE EXCEPTION 'Telefono invalido';
            END IF;
            INSERT INTO guardian_phones (guardian_id, phone, phone_type, is_primary)
            VALUES (v_guardian_id, TRIM(p_guardian_phone), 'Celular', TRUE)
            ON CONFLICT (guardian_id, phone) DO NOTHING;
        END IF;

        IF p_guardian_email IS NOT NULL AND TRIM(p_guardian_email) <> '' THEN
            INSERT INTO guardian_emails (guardian_id, email, is_primary)
            VALUES (v_guardian_id, TRIM(p_guardian_email), TRUE)
            ON CONFLICT (guardian_id, email) DO NOTHING;
        END IF;

    END IF;

    -- ── Insertar paciente ─────────────────────────────────────────────────

    INSERT INTO patients (
        first_name, last_name, curp, birth_date, gender,
        blood_type_id, weight_kg, premature, created_at, is_active
    )
    VALUES (
        TRIM(p_first_name),
        TRIM(p_last_name),
        NULLIF(TRIM(COALESCE(p_curp, '')), ''),
        p_birth_date,
        p_gender,
        p_blood_type_id,
        p_weight_kg,
        COALESCE(p_premature, FALSE),
        NOW(),
        TRUE
    )
    RETURNING patient_id INTO v_patient_id;

    -- ── Vincular paciente con tutor ───────────────────────────────────────

    IF v_guardian_id IS NOT NULL THEN
        INSERT INTO patient_guardian_relations (
            patient_id, guardian_id, relation_type, is_primary, has_custody
        )
        VALUES (v_patient_id, v_guardian_id, 'Tutor', TRUE, TRUE)
        ON CONFLICT DO NOTHING;
    END IF;

    -- Resultado exitoso
    OPEN p_results FOR
        SELECT TRUE                                AS success,
               'Paciente registrado correctamente' AS message,
               v_patient_id                        AS patient_id,
               v_guardian_id                       AS guardian_id;

EXCEPTION
WHEN OTHERS THEN
    -- Cualquier error de negocio/integridad regresa como fila, no como excepcion
    OPEN p_results FOR
        SELECT FALSE    AS success,
               SQLERRM  AS message,
               NULL::INT AS patient_id,
               NULL::INT AS guardian_id;
END;
$$;



-- Actualizar paciente (firma expandida: curp + birth_date)
DROP PROCEDURE IF EXISTS sp_update_patient(INT, VARCHAR, VARCHAR, INT, NUMERIC, REFCURSOR);

-- ============================================================
-- [5] sp_update_patient
-- Función   : Actualiza datos demográficos de un paciente activo
-- Recibe    : p_patient_id y campos opcionales (nombre, CURP, peso, tipo de sangre)
-- Devuelve  : success, message, patient_id
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_update_patient(
    IN    p_patient_id      INT,
    IN    p_first_name      VARCHAR,
    IN    p_last_name       VARCHAR,
    IN    p_curp            VARCHAR,
    IN    p_birth_date      DATE,
    IN    p_blood_type_id   INT,
    IN    p_weight_kg       NUMERIC,
    INOUT p_results         REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_exists BOOLEAN;
BEGIN

    SELECT EXISTS(
        SELECT 1 FROM patients
        WHERE patient_id = p_patient_id AND is_active = TRUE
    ) INTO v_exists;

    IF NOT v_exists THEN
        RAISE EXCEPTION 'El paciente no existe o esta inactivo';
    END IF;

    IF p_first_name IS NOT NULL AND LENGTH(TRIM(p_first_name)) < 2 THEN
        RAISE EXCEPTION 'Nombre invalido';
    END IF;

    IF p_last_name IS NOT NULL AND LENGTH(TRIM(p_last_name)) < 2 THEN
        RAISE EXCEPTION 'Apellido invalido';
    END IF;

    IF p_curp IS NOT NULL AND TRIM(p_curp) <> '' THEN
        IF LENGTH(TRIM(p_curp)) <> 18 THEN
            RAISE EXCEPTION 'CURP invalida';
        END IF;
        IF EXISTS (
            SELECT 1 FROM patients
            WHERE curp = TRIM(p_curp) AND patient_id <> p_patient_id
        ) THEN
            RAISE EXCEPTION 'El CURP ingresado ya esta registrado';
        END IF;
    END IF;

    IF p_birth_date IS NOT NULL AND p_birth_date > CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha de nacimiento no puede ser futura';
    END IF;

    IF p_weight_kg IS NOT NULL AND (p_weight_kg <= 0 OR p_weight_kg > 80) THEN
        RAISE EXCEPTION 'Peso fuera de rango pediatrico';
    END IF;

    IF p_blood_type_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM blood_types WHERE blood_type_id = p_blood_type_id) THEN
            RAISE EXCEPTION 'Tipo sanguineo inexistente';
        END IF;
    END IF;

    UPDATE patients
    SET
        first_name    = COALESCE(NULLIF(TRIM(p_first_name), ''), first_name),
        last_name     = COALESCE(NULLIF(TRIM(p_last_name),  ''), last_name),
        curp          = COALESCE(NULLIF(TRIM(p_curp),       ''), curp),
        birth_date    = COALESCE(p_birth_date,    birth_date),
        blood_type_id = COALESCE(p_blood_type_id, blood_type_id),
        weight_kg     = COALESCE(p_weight_kg,     weight_kg),
        updated_at    = NOW()
    WHERE patient_id = p_patient_id;

    OPEN p_results FOR
    SELECT TRUE AS success, 'Paciente actualizado correctamente' AS message, p_patient_id AS patient_id;

EXCEPTION WHEN OTHERS THEN
    OPEN p_results FOR
    SELECT FALSE AS success, SQLERRM AS message, NULL::INT AS patient_id;
END;
$$;

-- ============================================================
-- [6] sp_delete_patient
-- Función   : Desactiva (soft-delete) un paciente sin citas futuras
-- Recibe    : p_patient_id INT
-- Devuelve  : success, message, patient_id
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_delete_patient(
    IN    p_patient_id  INT,
    INOUT p_results     REFCURSOR
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_exists                BOOLEAN;
    v_has_future_appointments BOOLEAN;
BEGIN

    SELECT EXISTS(
        SELECT 1
        FROM patients
        WHERE patient_id = p_patient_id
        AND is_active = TRUE
    )
    INTO v_exists;

    IF NOT v_exists THEN
        RAISE EXCEPTION 'El paciente no existe o ya fue eliminado';
    END IF;

    SELECT EXISTS(
        SELECT 1
        FROM appointments a
        JOIN patient_vaccine_schedule pvs ON pvs.schedule_id = a.patient_schedule_id
        WHERE pvs.patient_id = p_patient_id
          AND a.scheduled_at >= CURRENT_DATE
          AND a.appointment_status NOT IN ('Cancelada', 'Completada', 'Reagendada', 'No Show')
    )
    INTO v_has_future_appointments;

    IF v_has_future_appointments THEN
        RAISE EXCEPTION 'El paciente tiene citas futuras pendientes';
    END IF;


    UPDATE patients
    SET
        is_active = FALSE,
        deleted_at = NOW(),
        updated_at = NOW()
    WHERE patient_id = p_patient_id;

    OPEN p_results FOR
    SELECT
        TRUE AS success,
        'Paciente desactivado correctamente' AS message,
        p_patient_id AS patient_id;

EXCEPTION
WHEN OTHERS THEN

    OPEN p_results FOR
    SELECT
        FALSE AS success,
        SQLERRM AS message,
        NULL::INT AS patient_id;
END;
$$;

-- ============================================================
-- [7] sp_calculate_patient_adherence
-- Función   : Calcula el porcentaje de adherencia al esquema vacunal del paciente
-- Recibe    : p_patient_id INT
-- Devuelve  : curp, nombre, dosis requeridas, aplicadas y porcentaje
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_calculate_patient_adherence(
    IN    p_patient_id INT,
    INOUT p_results    REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
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
    WHERE p.patient_id = p_patient_id
    GROUP BY p.patient_id;
END;
$$;

-- ============================================================
-- [8] sp_get_last_applications
-- Función   : Últimas 10 aplicaciones de vacunas del sistema
-- Recibe    : p_results REFCURSOR
-- Devuelve  : 10 filas de vaccination_records con datos de paciente, vacuna y trabajador
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_last_applications(   
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
    SELECT
        vr.record_id,
        vr.applied_date,
        TRIM(p.first_name || ' ' || p.last_name)  AS patient_name,
        p.patient_id,
        v.name                                     AS vaccine_name,
        COALESCE(sd.dose_label, 'Dosis única')    AS dose_label,
        TRIM(w.first_name || ' ' || w.last_name)  AS worker_name,
        c.name                                     AS clinic_name
        FROM   vaccination_records vr
        JOIN   patients   p  ON p.patient_id  = vr.patient_id
        JOIN   vaccines   v  ON v.vaccine_id  = vr.vaccine_id
        LEFT   JOIN scheme_doses sd ON sd.dose_id   = vr.scheme_dose_id
        LEFT   JOIN workers   w  ON w.worker_id  = vr.worker_id
        LEFT   JOIN clinics   c  ON c.clinic_id  = vr.clinic_id
        ORDER  BY vr.applied_date DESC, vr.record_id DESC
        LIMIT  10;
END;
$$;

-- ============================================================
-- [9] sp_get_patient_scheme
-- Función   : Esquema vacunal completo del paciente con estado de cada dosis y cita vinculada
-- Recibe    : p_patient_id INT
-- Devuelve  : Filas por dosis con estado, cita, alerta de retraso y próxima dosis
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_patient_scheme(
    IN    p_patient_id INT,
    INOUT p_results    REFCURSOR
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_patient_active BOOLEAN;
BEGIN

    -- ============================================================
    -- VALIDAR PACIENTE
    -- ============================================================

    SELECT is_active
    INTO v_patient_active
    FROM patients
    WHERE patient_id = p_patient_id;

    -- No existe
    IF v_patient_active IS NULL THEN
        RAISE EXCEPTION
            'El paciente con ID % no existe.',
            p_patient_id;
    END IF;

    -- Existe pero está inactivo
    IF v_patient_active = FALSE THEN
        RAISE EXCEPTION
            'El paciente con ID % está inactivo.',
            p_patient_id;
    END IF;


    -- ============================================================
    -- RETORNAR ESQUEMA COMPLETO
    -- ============================================================

    OPEN p_results FOR

    -- [CORREGIDO] Filtrar citas en estado final para no mostrar citas canceladas
    --             como "cita activa" de una dosis pendiente
    WITH latest_appointments AS (
        SELECT
            a.*,

            ROW_NUMBER() OVER (
                PARTITION BY a.patient_schedule_id
                ORDER BY a.created_at DESC
            ) AS rn

        FROM appointments a
        WHERE a.appointment_status NOT IN ('Cancelada', 'No Show', 'Completada', 'Reagendada', 'Pendiente confirmacion')
    )

    SELECT

        -- ========================================================
        -- IDENTIFICADORES
        -- ========================================================

        v.schedule_id,
        v.patient_id,
        v.dose_id,
        v.vaccine_id,
        v.record_id,

        la.appointment_id,


        -- ========================================================
        -- PACIENTE
        -- ========================================================

        v.full_name,
        v.birth_date,
        v.age_years,


        -- ========================================================
        -- VACUNA / DOSIS
        -- [CORREGIDO] aliases que lee Flask: name, dose (antes: vaccine_name, dose_label)
        -- ========================================================

        v.vaccine_name                                   AS name,
        v.disease_prevented,
        v.dose_label                                     AS dose,
        v.dose_number,
        v.ideal_age_months,
        v.ideal_date,


        -- ========================================================
        -- APLICACION
        -- [CORREGIDO] alias que lee Flask: date (antes: applied_date)
        -- ========================================================

        v.applied_date                                   AS date,
        v.doctor,
        v.application_site,
        v.had_reaction,
        v.patient_temp_c,


        -- ========================================================
        -- ESTADO CLINICO
        -- [CORREGIDO] columna "estado" con valores que espera Flask/template:
        --   Atrasada  -> 'Pendiente con retraso'
        --   Aplicada  -> 'Aplicada'
        --   Pendiente -> 'Pendiente'
        -- ========================================================

        CASE
            WHEN v.vaccination_status = 'Aplicada' THEN 'Aplicada'
            WHEN v.vaccination_status = 'Atrasada' THEN 'Pendiente con retraso'
            ELSE 'Pendiente'
        END                                              AS estado,
        v.dias_retraso,


        -- ========================================================
        -- CITA
        -- [CORREGIDO] aliases que lee Flask: fecha_cita, cita_estado
        --   (antes: appointment_date, appointment_status)
        -- ========================================================

        la.scheduled_at::DATE                            AS fecha_cita,
        la.appointment_status                            AS cita_estado,
        c.name AS clinic_name,


        -- ========================================================
        -- PRÓXIMA DOSIS
        -- ========================================================

        CASE
            WHEN v.next_dose_age_months IS NOT NULL THEN
                'A los '
                || v.next_dose_age_months
                || ' meses'
            ELSE NULL
        END AS next_dose_label,


        -- ========================================================
        -- EDAD IDEAL LEGIBLE
        -- ========================================================

        CASE
            WHEN v.ideal_age_months = 0 THEN
                'Al nacer'

            WHEN v.ideal_age_months >= 12 THEN
                (v.ideal_age_months / 12)
                || ' año(s)'

            ELSE
                v.ideal_age_months
                || ' meses'
        END AS edad_ideal_label,


        -- ========================================================
        -- ALERTA DE RETRASO
        -- ========================================================

        CASE

            WHEN v.record_id IS NULL
                 AND v.dias_retraso > 0 THEN

                'Retraso de '
                || v.dias_retraso
                || ' días'

            WHEN v.record_id IS NULL
                 AND v.dias_retraso <= 0 THEN

                'Programada en '
                || ABS(v.dias_retraso)
                || ' días'

            ELSE NULL

        END AS alerta_retraso

    FROM v_patient_vaccination_scheme_base v

    LEFT JOIN latest_appointments la
        ON v.schedule_id = la.patient_schedule_id
       AND la.rn = 1

    LEFT JOIN clinics c
        ON la.clinic_id = c.clinic_id

    WHERE v.patient_id = p_patient_id

    ORDER BY
        v.ideal_age_months,
        v.dose_number;

END;
$$;

-- ============================================================
-- [10] sp_get_vaccination_record
-- Función   : Datos completos de un registro de vacunación para generar comprobante PDF
-- Recibe    : p_record_id INT
-- Devuelve  : Una fila con datos del paciente, vacuna, trabajador, lote y clínica
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_vaccination_record(
    IN    p_record_id INT,
    INOUT p_results   REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
    SELECT
        vr.record_id,
        vr.patient_id,
        vr.applied_date,
        vr.patient_temp_c,
        vr.had_reaction,
        TRIM(p.first_name || ' ' || p.last_name)                    AS patient_name,
        p.curp,
        p.birth_date,
        DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT      AS age_years,
        v.name                                                        AS vaccine_name,
        v.commercial_name,
        COALESCE(TRIM(w.first_name || ' ' || w.last_name), '—')      AS worker_name,
        COALESCE(sd.dose_label, '—')                                  AS dose_label,
        COALESCE(aps.application_site, '—')                           AS application_site,
        c.name                                                        AS clinic_name,
        COALESCE(vl.lot_number, '—')                                  AS lot_number
    FROM   vaccination_records vr
    JOIN   patients            p   ON p.patient_id           = vr.patient_id
    JOIN   vaccines            v   ON v.vaccine_id           = vr.vaccine_id
    JOIN   workers             w   ON w.worker_id            = vr.worker_id
    JOIN   clinics             c   ON c.clinic_id            = vr.clinic_id
    LEFT JOIN scheme_doses     sd  ON sd.dose_id             = vr.scheme_dose_id
    LEFT JOIN application_sites aps ON aps.application_site_id = vr.application_site_id
    LEFT JOIN vaccine_lots     vl  ON vl.lot_id              = vr.lot_id
    WHERE  vr.record_id = p_record_id
    LIMIT  1;
END;
$$;

-- ============================================================
-- [13] sp_get_tutor_children
-- Función   : Lista de hijos vinculados a un tutor con KPIs de vacunación
-- Recibe    : p_guardian_id INT
-- Devuelve  : Una fila por paciente activo con métricas de adherencia
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_tutor_children(
    IN    p_guardian_id INT,
    INOUT p_results     REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM guardians WHERE guardian_id = p_guardian_id) THEN
        RAISE EXCEPTION 'Tutor no encontrado';
    END IF;

    OPEN p_results FOR
    SELECT
        p.patient_id,
        TRIM(p.first_name || ' ' || p.last_name)                    AS full_name,
        p.first_name,
        p.last_name,
        p.birth_date,
        DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT      AS age_years,
        COALESCE(p.curp, '')                                         AS curp,
        p.photo,
        p.gender,
        p.weight_kg,
        p.premature,
        COALESCE(bt.blood_type, '')                                  AS blood_type,
        -- KPIs de vacunación
        COALESCE(kpi.total_doses,   0)                               AS total_doses,
        COALESCE(kpi.total_applied, 0)                               AS total_applied,
        COALESCE(kpi.total_pending, 0)                               AS total_pending,
        COALESCE(kpi.delayed_count, 0)                               AS delayed_count,
        COALESCE(kpi.pct,           0)                               AS pct
    FROM patient_guardian_relations pgr
    JOIN   patients    p   ON p.patient_id    = pgr.patient_id
    LEFT JOIN blood_types bt ON bt.blood_type_id = p.blood_type_id
    LEFT JOIN LATERAL (
        SELECT
            COUNT(*)                                                               AS total_doses,
            SUM(CASE WHEN pvs.status = 'Aplicada' THEN 1 ELSE 0 END)              AS total_applied,
            SUM(CASE WHEN pvs.status <> 'Aplicada' THEN 1 ELSE 0 END)             AS total_pending,
            SUM(CASE WHEN pvs.status = 'Atrasada'  THEN 1 ELSE 0 END)             AS delayed_count,
            CASE
                WHEN COUNT(*) = 0 THEN 0
                ELSE SUM(CASE WHEN pvs.status = 'Aplicada' THEN 1 ELSE 0 END) * 100 / COUNT(*)
            END                                                                    AS pct
        FROM patient_vaccine_schedule pvs
        WHERE pvs.patient_id = p.patient_id
    ) kpi ON TRUE
    WHERE pgr.guardian_id = p_guardian_id
      AND p.is_active = TRUE
    ORDER BY p.patient_id ASC;
END;
$$;

-- ============================================================
-- [14] sp_tutor_register_child
-- Función   : Registra un nuevo hijo y lo vincula al tutor autenticado
-- Recibe    : p_guardian_id y datos del paciente
-- Devuelve  : success, message, patient_id
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_tutor_register_child(
    IN    p_guardian_id   INT,
    IN    p_first_name    VARCHAR,
    IN    p_last_name     VARCHAR,
    IN    p_birth_date    DATE,
    IN    p_gender        CHAR(1),
    IN    p_curp          VARCHAR,
    IN    p_blood_type_id INT,
    IN    p_weight_kg     NUMERIC,
    IN    p_premature     BOOLEAN,
    INOUT p_results       REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_patient_id INT;
    v_age_years  INT;
BEGIN
    -- Validaciones de negocio (paralelas a sp_register_patient)
    IF p_first_name IS NULL OR TRIM(p_first_name) = '' THEN
        RAISE EXCEPTION 'El nombre es obligatorio';
    END IF;
    IF p_last_name IS NULL OR TRIM(p_last_name) = '' THEN
        RAISE EXCEPTION 'El apellido es obligatorio';
    END IF;
    IF p_birth_date IS NULL OR p_birth_date > CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha de nacimiento no puede ser futura';
    END IF;
    v_age_years := DATE_PART('year', AGE(CURRENT_DATE, p_birth_date));
    IF v_age_years > 15 THEN
        RAISE EXCEPTION 'El paciente excede la edad pediátrica permitida';
    END IF;
    IF p_gender NOT IN ('M', 'F') THEN
        RAISE EXCEPTION 'El género debe ser M o F';
    END IF;
    IF p_curp IS NOT NULL AND TRIM(p_curp) <> '' AND EXISTS (
        SELECT 1 FROM patients WHERE curp = UPPER(TRIM(p_curp))
    ) THEN
        RAISE EXCEPTION 'Ya existe un paciente registrado con esa CURP';
    END IF;
    IF p_weight_kg IS NOT NULL AND (p_weight_kg <= 0 OR p_weight_kg > 80) THEN
        RAISE EXCEPTION 'Peso fuera de rango pediátrico';
    END IF;
    IF p_blood_type_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM blood_types WHERE blood_type_id = p_blood_type_id
    ) THEN
        RAISE EXCEPTION 'Tipo sanguíneo inexistente';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM guardians WHERE guardian_id = p_guardian_id) THEN
        RAISE EXCEPTION 'Tutor no encontrado';
    END IF;

    -- Insertar paciente (trigger genera esquema de vacunación automáticamente)
    INSERT INTO patients (
        first_name, last_name, curp, birth_date, gender,
        blood_type_id, weight_kg, premature, is_active, created_at
    )
    VALUES (
        TRIM(p_first_name),
        TRIM(p_last_name),
        NULLIF(UPPER(TRIM(COALESCE(p_curp, ''))), ''),
        p_birth_date,
        p_gender,
        p_blood_type_id,
        p_weight_kg,
        COALESCE(p_premature, FALSE),
        TRUE,
        NOW()
    )
    RETURNING patient_id INTO v_patient_id;

    -- Vincular paciente con el tutor
    INSERT INTO patient_guardian_relations (patient_id, guardian_id, relation_type, is_primary, has_custody)
    VALUES (v_patient_id, p_guardian_id, 'Tutor', TRUE, TRUE)
    ON CONFLICT DO NOTHING;

    OPEN p_results FOR
    SELECT TRUE  AS success,
           'Paciente registrado correctamente' AS message,
           v_patient_id AS patient_id;

EXCEPTION
WHEN OTHERS THEN
    OPEN p_results FOR
    SELECT FALSE AS success, SQLERRM AS message, NULL::INT AS patient_id;
END;
$$;

-- ============================================================
-- MÓDULO: VACUNAS
-- ============================================================

-- ============================================================
-- [17] sp_register_vaccine
-- Función   : Registra una nueva vacuna en el catálogo
-- Recibe    : nombre, fabricante, vía, edad ideal, enfermedad
-- Devuelve  : vaccine_id
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_register_vaccine(
    IN    p_name              VARCHAR,
    IN    p_commercial_name   VARCHAR,
    IN    p_manufacturer_id   INT,
    IN    p_via_id            INT,
    IN    p_ideal_age_months  SMALLINT,
    IN    p_disease_prevented TEXT,
    INOUT p_results           REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_vaccine_id INT;
BEGIN
    INSERT INTO vaccines (
        name,
        commercial_name,
        manufacturer_id,
        via_id,
        ideal_age_months,
        disease_prevented
    )
    VALUES (
        p_name,
        p_commercial_name,
        p_manufacturer_id,
        p_via_id,
        p_ideal_age_months,
        p_disease_prevented
    )
    RETURNING vaccines.vaccine_id INTO v_vaccine_id;

    OPEN p_results FOR
        SELECT v_vaccine_id AS vaccine_id;
END;
$$;

-- =====================================
-- [DEPRECADO] CITAS — PORTAL TUTOR (flujo tutor_accepted)
-- Movidos al fondo del archivo. Ver sección DEPRECATED.
-- Reemplazados por: sp_dashboard_tutor, sp_create_appointment (nuevo)
-- =====================================
-- sp_get_tutor_pending_citas  → DEPRECATED (usaba tutor_accepted IS NULL)
-- sp_get_tutor_citas_history  → DEPRECATED (usaba tutor_accepted)

-- ============================================================
-- [19] sp_create_vaccine_lot
-- Función   : Crea un nuevo lote de vacunas para una clínica
-- Recibe    : vaccine_id, clinic_id, lot_number, cantidad, fecha de vencimiento
-- Devuelve  : lot_id
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_create_vaccine_lot(
    IN    p_vaccine_id           INT,
    IN    p_clinic_id            INT,
    IN    p_lot_number           VARCHAR,
    IN    p_quantity_received    INT,
    IN    p_expiration_date      DATE,
    INOUT p_results              REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_lot_id INT;
BEGIN
    INSERT INTO vaccine_lots (
        vaccine_id, clinic_id, lot_number,
        quantity_received, quantity_available, expiration_date, received_date, is_active
    )
    VALUES (
        p_vaccine_id, p_clinic_id, p_lot_number,
        p_quantity_received, p_quantity_received, p_expiration_date, NOW()::DATE,
        (p_expiration_date >= NOW()::DATE)
    )
    RETURNING vaccine_lots.lot_id INTO v_lot_id;

    OPEN p_results FOR
        SELECT v_lot_id AS lot_id;
END;
$$;

-- ============================================================
-- [20] sp_edit_vaccine_lot
-- Función   : Edita datos de un lote existente (número, cantidad, vencimiento, clínica)
-- Recibe    : p_lot_id y campos del lote
-- Devuelve  : success boolean
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_edit_vaccine_lot(
    IN    p_lot_id            INT,
    IN    p_clinic_id         INT,
    IN    p_lot_number        VARCHAR,
    IN    p_quantity_received INT,
    IN    p_expiration_date   DATE,
    INOUT p_results           REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_rows INT;
BEGIN
    UPDATE vaccine_lots SET
        clinic_id         = p_clinic_id,
        lot_number        = p_lot_number,
        quantity_received = p_quantity_received,
        expiration_date   = p_expiration_date,
        is_active         = (p_expiration_date >= NOW()::DATE)
    WHERE lot_id = p_lot_id;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    OPEN p_results FOR
        SELECT (v_rows > 0) AS success;
END;
$$;

-- ============================================================
-- [21] sp_deactivate_vaccine_lot
-- Función   : Desactiva un lote vencido (soft-delete)
-- Recibe    : p_lot_id INT
-- Devuelve  : success boolean
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_deactivate_vaccine_lot(
    IN    p_lot_id   INT,
    INOUT p_results  REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_rows INT;
BEGIN
    UPDATE vaccine_lots
    SET    is_active = FALSE
    WHERE  lot_id          = p_lot_id
      AND  expiration_date <= NOW()::DATE;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    OPEN p_results FOR
        SELECT (v_rows > 0) AS success;
END;
$$;

-- ============================================================
-- [22] sp_update_vaccine_lot_stock
-- Función   : Actualiza manualmente la cantidad disponible de un lote
-- Recibe    : p_lot_id INT, p_quantity_available INT
-- Devuelve  : success (FOUND)
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_update_vaccine_lot_stock(
    IN    p_lot_id              INT,
    IN    p_quantity_available  INT,
    INOUT p_results             REFCURSOR
)

LANGUAGE plpgsql AS $$
BEGIN
    UPDATE vaccine_lots SET
        quantity_available = p_quantity_available
    WHERE lot_id = p_lot_id;

    OPEN p_results FOR
        SELECT FOUND AS success;
END;
$$;

-- ============================================================
-- MÓDULO: VACUNACIÓN
-- ============================================================

-- ============================================================
-- [24] sp_register_vaccination_record
-- Función   : Registra la aplicación de una vacuna con todas las validaciones clínicas
-- Recibe    : patient_id, vaccine_id, worker_id, clinic_id, lot_id, scheme_dose_id, applied_date, site, temp, reaction
-- Devuelve  : success, message, record_id
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_register_vaccination_record(

    IN    p_patient_id           INT,
    IN    p_vaccine_id           INT,
    IN    p_worker_id            INT,
    IN    p_clinic_id            INT,
    IN    p_lot_id               INT,
    IN    p_scheme_dose_id       INT,
    IN    p_applied_date         DATE,
    IN    p_application_site_id  INT,
    IN    p_patient_temp_c       NUMERIC,
    IN    p_had_reaction         BOOLEAN,
    INOUT p_results              REFCURSOR

)
LANGUAGE plpgsql
AS $$
DECLARE

    v_record_id                  INT;

    v_birth_date                 DATE;
    v_patient_age_months         INT;

    v_ideal_age_months           INT;
    v_min_interval_days          INT;

    v_last_application_date      DATE;
    v_days_since_last_dose       INT;

    v_schedule_status            TEXT;

BEGIN

    -- =====================================================
    -- VALIDAR PACIENTE
    -- =====================================================

    SELECT birth_date
    INTO v_birth_date
    FROM patients
    WHERE patient_id = p_patient_id
    AND is_active = TRUE;

    IF v_birth_date IS NULL THEN
        RAISE EXCEPTION
        'El paciente no existe o está inactivo';
    END IF;

    -- =====================================================
    -- VALIDAR PERSONAL AUTORIZADO
    -- =====================================================

    IF NOT EXISTS (

        SELECT 1
        FROM workers w
        JOIN roles r
            ON r.role_id = w.role_id
        WHERE w.worker_id = p_worker_id
        AND w.is_active = TRUE
        AND r.name IN ('Medico', 'Enfermero')

    ) THEN

        RAISE EXCEPTION
        'Solo medicos o enfermeros pueden aplicar vacunas';

    END IF;

    -- =====================================================
    -- VALIDAR CLÍNICA
    -- =====================================================

    IF NOT EXISTS (

        SELECT 1
        FROM clinics
        WHERE clinic_id = p_clinic_id

    ) THEN

        RAISE EXCEPTION
        'La clínica no existe';

    END IF;

    -- =====================================================
    -- VALIDAR VACUNA
    -- =====================================================

    IF NOT EXISTS (

        SELECT 1
        FROM vaccines
        WHERE vaccine_id = p_vaccine_id

    ) THEN

        RAISE EXCEPTION
        'La vacuna no existe';

    END IF;

    -- =====================================================
    -- VALIDAR LOTE
    -- =====================================================

    IF NOT EXISTS (

        SELECT 1
        FROM vaccine_lots
        WHERE lot_id = p_lot_id
        AND expiration_date >= CURRENT_DATE
        AND quantity_available > 0

    ) THEN

        RAISE EXCEPTION
        'El lote no existe, está vencido o no tiene stock';

    END IF;

    -- =====================================================
    -- VALIDAR QUE EL LOTE PERTENEZCA A LA CLÍNICA
    -- =====================================================

    IF NOT EXISTS (

        SELECT 1
        FROM vaccine_lots
        WHERE lot_id = p_lot_id
        AND clinic_id = p_clinic_id

    ) THEN

        RAISE EXCEPTION
        'El lote no pertenece a la clínica seleccionada';

    END IF;

    -- =====================================================
    -- VALIDAR FECHA
    -- =====================================================

    IF p_applied_date > CURRENT_DATE THEN

        RAISE EXCEPTION
        'La fecha de aplicación no puede ser futura';

    END IF;

    -- =====================================================
    -- VALIDAR TEMPERATURA
    -- =====================================================

    IF p_patient_temp_c IS NOT NULL THEN

        IF p_patient_temp_c < 30
        OR p_patient_temp_c > 45 THEN

            RAISE EXCEPTION
            'Temperatura corporal inválida';

        END IF;

    END IF;

    -- =====================================================
    -- VALIDAR SITIO DE APLICACIÓN
    -- =====================================================

    IF NOT EXISTS (

        SELECT 1
        FROM application_sites
        WHERE application_site_id = p_application_site_id

    ) THEN

        RAISE EXCEPTION
        'El sitio de aplicación no existe';

    END IF;

    -- =====================================================
    -- VALIDAR ESQUEMA DEL PACIENTE
    -- =====================================================

    SELECT status
    INTO v_schedule_status
    FROM patient_vaccine_schedule
    WHERE patient_id = p_patient_id
    AND scheme_dose_id = p_scheme_dose_id;

    IF v_schedule_status IS NULL THEN

        RAISE EXCEPTION
        'La dosis no pertenece al esquema del paciente';

    END IF;

    -- =====================================================
    -- VALIDAR DOSIS DUPLICADA
    -- =====================================================

    IF EXISTS (

        SELECT 1
        FROM vaccination_records
        WHERE patient_id = p_patient_id
        AND scheme_dose_id = p_scheme_dose_id

    ) THEN

        RAISE EXCEPTION
        'La dosis ya fue aplicada al paciente';

    END IF;

    -- =====================================================
    -- VALIDAR EDAD MÍNIMA
    -- =====================================================

    SELECT ideal_age_months
    INTO v_ideal_age_months
    FROM scheme_doses
    WHERE dose_id = p_scheme_dose_id;

    v_patient_age_months :=

        (
            EXTRACT(YEAR FROM AGE(p_applied_date, v_birth_date)) * 12
        )
        +
        EXTRACT(MONTH FROM AGE(p_applied_date, v_birth_date));

    IF v_ideal_age_months IS NOT NULL
    AND v_patient_age_months < v_ideal_age_months THEN

        RAISE EXCEPTION
        'El paciente no cumple la edad mínima requerida';

    END IF;

    -- =====================================================
    -- VALIDAR INTERVALO ENTRE DOSIS
    -- =====================================================

    SELECT min_interval_days
    INTO v_min_interval_days
    FROM scheme_doses
    WHERE dose_id = p_scheme_dose_id;

    SELECT MAX(applied_date)
    INTO v_last_application_date
    FROM vaccination_records
    WHERE patient_id = p_patient_id
    AND vaccine_id = p_vaccine_id;

    IF v_last_application_date IS NOT NULL
    AND v_min_interval_days IS NOT NULL THEN

        v_days_since_last_dose :=
            p_applied_date - v_last_application_date;

        IF v_days_since_last_dose < v_min_interval_days THEN

            RAISE EXCEPTION
            'No se cumple el intervalo mínimo entre dosis';

        END IF;

    END IF;

    -- =====================================================
    -- INSERTAR APLICACIÓN
    -- =====================================================

    INSERT INTO vaccination_records (

        patient_id,
        vaccine_id,
        worker_id,
        clinic_id,
        lot_id,
        scheme_dose_id,
        applied_date,
        application_site_id,
        patient_temp_c,
        had_reaction,
        created_at

    )
    VALUES (

        p_patient_id,
        p_vaccine_id,
        p_worker_id,
        p_clinic_id,
        p_lot_id,
        p_scheme_dose_id,
        p_applied_date,
        p_application_site_id,
        p_patient_temp_c,
        COALESCE(p_had_reaction, FALSE),
        NOW()

    )
    RETURNING record_id
    INTO v_record_id;

    -- =====================================================
    -- RESPUESTA
    -- =====================================================

    OPEN p_results FOR

    SELECT
        TRUE  AS success,
        'Vacuna aplicada correctamente' AS message,
        v_record_id AS record_id;

END;
$$;



-- ============================================================
-- [DEPRECADO] sp_record_vaccine_reaction
-- Columnas incorrectas: vaccination_record_id, reaction_description, reported_at
-- no existen en post_vaccine_reactions. La tabla usa: record_id, symptom.
-- Movido al fondo. Ver sección DEPRECATED.
-- ============================================================


-- ============================================================
-- MÓDULO: CITAS
-- ============================================================

-- ============================================================
-- [26] sp_create_appointment
-- Función   : Crea una nueva cita con validaciones de horario, solapamiento y disponibilidad del área
-- Recibe    : patient_id, clinic_id, area_id, worker_id, scheduled_at, reason, patient_schedule_id, campos created_by
-- Devuelve  : success, appointment_id, message
-- ============================================================
    CREATE OR REPLACE PROCEDURE sp_create_appointment(
        IN    p_patient_id            INT,
        IN    p_clinic_id             INT,
        IN    p_area_id               INT,
        IN    p_worker_id             INT,
        IN    p_scheduled_at          TIMESTAMP,
        IN    p_reason                TEXT,
        IN    p_patient_schedule_id   INT,
        IN    p_created_by_role       VARCHAR,
        IN    p_created_by_worker_id  INT,
        IN    p_created_by_guardian_id INT,
        INOUT p_results               REFCURSOR
    )
    LANGUAGE plpgsql AS $$
    DECLARE
        v_appointment_id INT;
    BEGIN
        -- Validar paciente activo
        IF NOT EXISTS (
            SELECT 1 FROM patients WHERE patient_id = p_patient_id AND is_active = TRUE
        ) THEN
            RAISE EXCEPTION 'El paciente no existe o está inactivo';
        END IF;

        -- Validar clínica activa
        IF NOT EXISTS (
            SELECT 1 FROM clinics WHERE clinic_id = p_clinic_id AND is_active = TRUE
        ) THEN
            RAISE EXCEPTION 'La clínica no existe o está inactiva';
        END IF;

        -- Validar fecha futura
        IF p_scheduled_at <= NOW() THEN
            RAISE EXCEPTION 'La cita debe ser en el futuro';
        END IF;

        -- Validar que el schedule_id corresponde al paciente y no está aplicado
        IF p_patient_schedule_id IS NOT NULL THEN
            IF NOT EXISTS (
                SELECT 1 FROM patient_vaccine_schedule
                WHERE  schedule_id = p_patient_schedule_id
                AND  patient_id  = p_patient_id
                AND  status     <> 'Aplicada'
            ) THEN
                RAISE EXCEPTION 'La dosis no pertenece a este paciente o ya fue aplicada';
            END IF;

            -- Verificar que no exista ya una cita activa para esta dosis
            IF EXISTS (
                SELECT 1 FROM appointments
                WHERE  patient_schedule_id = p_patient_schedule_id
                AND  appointment_status NOT IN ('Cancelada', 'No Show', 'Completada', 'Reagendada')
            ) THEN
                RAISE EXCEPTION 'Ya existe una cita activa para esta dosis';
            END IF;
        END IF;

        -- Validar que el paciente no tenga otra cita activa que se solape
        IF EXISTS (
            SELECT 1 FROM appointments
            WHERE  patient_id = p_patient_id
            AND    appointment_status NOT IN ('Cancelada', 'No Show', 'Completada', 'Reagendada')
            AND    scheduled_at < p_scheduled_at + (duration_min * INTERVAL '1 minute')
            AND    scheduled_at + (duration_min * INTERVAL '1 minute') > p_scheduled_at
        ) THEN
            RAISE EXCEPTION 'El paciente ya tiene una cita programada que se solapa con ese horario';
        END IF;

        -- Verificar horario laboral solo si el trabajador tiene horarios configurados en esa clínica
        IF p_worker_id IS NOT NULL THEN
            IF EXISTS (
                SELECT 1 FROM worker_schedules
                WHERE worker_id = p_worker_id AND clinic_id = p_clinic_id
            ) THEN
                IF NOT EXISTS (
                    SELECT 1
                    FROM   worker_schedules ws
                    WHERE  ws.worker_id   = p_worker_id
                    AND    ws.clinic_id   = p_clinic_id
                    AND    ws.day_of_week = EXTRACT(ISODOW FROM p_scheduled_at)::SMALLINT
                    AND    ws.entry_time  <= p_scheduled_at::TIME
                    AND    ws.exit_time   >  p_scheduled_at::TIME
                ) THEN
                    RAISE EXCEPTION 'El trabajador no tiene horario laboral en esa clinica para la fecha y hora indicadas';
                END IF;
            END IF;
        END IF;

        -- Verificar solapamiento por duracion del trabajador (ventana de 20 min)
        IF p_worker_id IS NOT NULL THEN
            IF EXISTS (
                SELECT 1
                FROM   appointments a
                WHERE  a.worker_id          = p_worker_id
                AND  a.appointment_status NOT IN ('Cancelada', 'No Show', 'Reagendada')
                AND  a.scheduled_at < p_scheduled_at + (20 * INTERVAL '1 minute')
                AND  a.scheduled_at + (a.duration_min * INTERVAL '1 minute') > p_scheduled_at
                AND  a.scheduled_at <> p_scheduled_at
            ) THEN
                RAISE EXCEPTION 'El trabajador ya tiene una cita que se solapa en ese rango horario';
            END IF;
        END IF;

        -- Verificar disponibilidad exacta del trabajador (constraint UNIQUE)
        IF p_worker_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM appointments
            WHERE  worker_id         = p_worker_id
            AND  scheduled_at      = p_scheduled_at
            AND  appointment_status NOT IN ('Cancelada', 'No Show', 'Reagendada')
        ) THEN
            RAISE EXCEPTION 'El trabajador ya tiene una cita agendada exactamente a esa hora';
        END IF;

        -- Verificar capacidad concurrente del area
        IF p_area_id IS NOT NULL THEN
            IF EXISTS (
                SELECT 1 FROM clinic_areas ca
                WHERE  ca.area_id  = p_area_id
                AND  ca.capacity IS NOT NULL
            ) THEN
                IF (
                    SELECT COUNT(*)
                    FROM   appointments a
                    WHERE  a.clinic_id          = p_clinic_id
                    AND  a.area_id            = p_area_id
                    AND  a.appointment_status NOT IN ('Cancelada', 'No Show', 'Reagendada')
                    AND  a.scheduled_at < p_scheduled_at + (20 * INTERVAL '1 minute')
                    AND  a.scheduled_at + (a.duration_min * INTERVAL '1 minute') > p_scheduled_at
                ) >= (
                    SELECT ca.capacity FROM clinic_areas ca WHERE ca.area_id = p_area_id
                )
                THEN
                    RAISE EXCEPTION 'El area ha alcanzado su capacidad maxima de citas en ese horario';
                END IF;
            END IF;
        END IF;

        -- Verificar disponibilidad exacta del area (constraint UNIQUE)
        IF p_area_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM appointments
            WHERE  clinic_id         = p_clinic_id
            AND  area_id           = p_area_id
            AND  scheduled_at      = p_scheduled_at
            AND  appointment_status NOT IN ('Cancelada', 'No Show', 'Reagendada')
        ) THEN
            RAISE EXCEPTION 'El area no esta disponible en ese horario exacto';
        END IF;

        INSERT INTO appointments (
            patient_id, clinic_id, area_id, worker_id,
            patient_schedule_id, scheduled_at, reason,
            appointment_status, duration_min,
            created_by_role, created_by_worker_id, created_by_guardian_id,
            created_at
        )
        VALUES (
            p_patient_id, p_clinic_id, p_area_id, p_worker_id,
            p_patient_schedule_id, p_scheduled_at, p_reason,
            'Programada', 20,
            p_created_by_role, p_created_by_worker_id, p_created_by_guardian_id,
            NOW()
        )
        RETURNING appointment_id INTO v_appointment_id;

        OPEN p_results FOR
            SELECT TRUE              AS success,
                v_appointment_id  AS appointment_id,
                'Cita creada correctamente' AS message;

    EXCEPTION WHEN OTHERS THEN
        OPEN p_results FOR
            SELECT FALSE AS success, SQLERRM AS message, NULL::INT AS appointment_id;
    END;
    $$;


-- ============================================================
-- [DEPRECADO] sp_confirm_appointment
-- Era para que el tutor confirmara citas automáticas (tutor_accepted flow).
-- Ya no existe 'Pendiente confirmación' en el nuevo flujo.
-- Movido al fondo. Ver sección DEPRECATED.
-- ============================================================

-- ============================================================
-- [27] sp_cancel_appointment
-- Función   : Cancela una cita activa registrando el motivo
-- Recibe    : p_appointment_id INT, p_reason TEXT
-- Devuelve  : success, message, appointment_id
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_cancel_appointment(
    IN    p_appointment_id INT,
    IN    p_reason         TEXT,
    INOUT p_results        REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM appointments WHERE appointment_id = p_appointment_id
    ) THEN
        RAISE EXCEPTION 'Cita no encontrada';
    END IF;

    IF EXISTS (
        SELECT 1 FROM appointments
        WHERE  appointment_id    = p_appointment_id
          AND  appointment_status IN ('Cancelada', 'Completada', 'No Show')
    ) THEN
        RAISE EXCEPTION 'La cita ya tiene un estado final y no puede cancelarse';
    END IF;

    UPDATE appointments
    SET    appointment_status = 'Cancelada',
           cancel_reason      = COALESCE(p_reason, 'Sin motivo'),
           appointment_notes  =
               COALESCE(appointment_notes || E'\n', '')
               || '[' || CURRENT_DATE || '] Cancelada. Motivo: '
               || COALESCE(p_reason, 'Sin motivo')
    WHERE  appointment_id = p_appointment_id;

    OPEN p_results FOR
        SELECT TRUE  AS success,
               'Cita cancelada correctamente' AS message,
               p_appointment_id AS appointment_id;

EXCEPTION WHEN OTHERS THEN
    OPEN p_results FOR
        SELECT FALSE AS success, SQLERRM AS message, NULL::INT AS appointment_id;
END;
$$;

-- ============================================================
-- [28] sp_reschedule_appointment
-- Función   : Reagenda una cita marcando la original como Reagendada y creando una nueva
-- Recibe    : p_appointment_id INT, p_new_scheduled_at TIMESTAMP, p_reschedule_reason TEXT
-- Devuelve  : success, new_appointment_id, old_appointment_id, message
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_reschedule_appointment(
    IN    p_appointment_id    INT,
    IN    p_new_scheduled_at  TIMESTAMP,
    IN    p_reschedule_reason TEXT,
    INOUT p_results           REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_old             appointments%ROWTYPE;
    v_new_id          INT;
BEGIN
    SELECT * INTO v_old
    FROM   appointments
    WHERE  appointment_id = p_appointment_id;

    IF v_old IS NULL THEN
        RAISE EXCEPTION 'Cita no encontrada';
    END IF;

    IF v_old.appointment_status IN ('Cancelada', 'Completada', 'No Show', 'Reagendada') THEN
        RAISE EXCEPTION 'No se puede reagendar una cita en estado %', v_old.appointment_status;
    END IF;

    IF p_new_scheduled_at <= NOW() THEN
        RAISE EXCEPTION 'La nueva fecha debe ser en el futuro';
    END IF;

    -- Marcar cita original como Reagendada
    UPDATE appointments
    SET    appointment_status = 'Reagendada',
           appointment_notes  =
               COALESCE(appointment_notes || E'\n', '')
               || '[' || CURRENT_DATE || '] Reagendada. Motivo: '
               || COALESCE(p_reschedule_reason, 'No especificado')
    WHERE  appointment_id = p_appointment_id;

    -- Crear nueva cita heredando datos
    INSERT INTO appointments (
        patient_id, clinic_id, area_id, worker_id,
        patient_schedule_id, scheduled_at, reason,
        appointment_status, duration_min,
        created_by_role, created_by_worker_id, created_by_guardian_id,
        rescheduled_from_id, created_at
    )
    VALUES (
        v_old.patient_id, v_old.clinic_id, v_old.area_id, v_old.worker_id,
        v_old.patient_schedule_id, p_new_scheduled_at, v_old.reason,
        'Programada', v_old.duration_min,
        v_old.created_by_role, v_old.created_by_worker_id, v_old.created_by_guardian_id,
        p_appointment_id, NOW()
    )
    RETURNING appointment_id INTO v_new_id;

    OPEN p_results FOR
        SELECT TRUE              AS success,
               v_new_id          AS new_appointment_id,
               p_appointment_id  AS old_appointment_id,
               'Cita reagendada correctamente' AS message;

EXCEPTION WHEN OTHERS THEN
    OPEN p_results FOR
        SELECT FALSE AS success, SQLERRM AS message,
               NULL::INT AS new_appointment_id, p_appointment_id AS old_appointment_id;
END;
$$;

-- ============================================================
-- [29] sp_mark_no_show
-- Función   : Marca una cita como No Show si el paciente no asistió
-- Recibe    : p_appointment_id INT
-- Devuelve  : success, message
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_mark_no_show(
    IN p_appointment_id INT,
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql
AS $$
BEGIN

    UPDATE appointments
    SET
        appointment_status = 'No Show',
        appointment_notes =
            COALESCE(appointment_notes || E'\n', '')
            || '[' || CURRENT_DATE || '] Paciente no asistió.'
    WHERE appointment_id = p_appointment_id;

    OPEN p_results FOR
    SELECT
        appointment_id,
        patient_schedule_id,
        clinic_id,
        scheduled_at,
        appointment_status,
        appointment_notes
    FROM appointments
    WHERE appointment_id = p_appointment_id;

END;
$$;

-- ============================================================
-- [DEPRECADO] sp_complete_appointment
-- Reemplazado por trg_complete_appointment_on_vaccination (trigger 15).
-- El trigger maneja la transición 'Completada' automáticamente
-- al insertar en vaccination_records. Ya no se llama este SP.
-- Movido al fondo. Ver sección DEPRECATED.
-- ============================================================


-- ============================================================
-- MÓDULO: REPORTERÍA, ALERTAS Y BÚSQUEDA
-- ============================================================

-- ============================================================
-- [73] sp_get_pending_alerts
-- Función   : Alertas pendientes del sistema (dosis atrasadas, stock bajo) para el panel de alertas
-- Recibe    : p_results REFCURSOR
-- Devuelve  : Filas de alertas con tipo, mensaje y patient_id
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_pending_alerts(

    INOUT p_results REFCURSOR

)

LANGUAGE plpgsql AS $$

BEGIN

    OPEN p_results FOR

        SELECT * FROM scheme_completion_alerts

        WHERE status = 'Pendiente'

        ORDER BY due_date ASC;

END;

$$;

-- ============================================================
-- [39] sp_update_patient_nfc_id
-- Función   : Actualiza el nfc_card_id interno del paciente al asignarle una tarjeta
-- Recibe    : p_patient_id INT, p_nfc_card_id INT
-- Devuelve  : success, message
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_update_patient_nfc_id(
    IN p_patient_id INT,
    IN p_new_nfc_id VARCHAR(50)
)
LANGUAGE plpgsql AS $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM patients
        WHERE nfc_id = p_new_nfc_id AND patient_id <> p_patient_id
    ) THEN
        RAISE EXCEPTION 'nfc_id % ya está asignado a otro paciente', p_new_nfc_id;
    END IF;

    UPDATE patients
    SET nfc_id     = p_new_nfc_id,
        updated_at = NOW()
    WHERE patient_id = p_patient_id;
END;
$$;

-- ============================================================
-- [40] sp_clear_patient_nfc_id
-- Función   : Desvincula la tarjeta NFC de un paciente limpiando su nfc_card_id
-- Recibe    : p_patient_id INT
-- Devuelve  : success, message
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_clear_patient_nfc_id(
    IN p_patient_id INT
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE patients
    SET nfc_id     = NULL,
        updated_at = NOW()
    WHERE patient_id = p_patient_id;
END;
$$;

-- ============================================================
-- [87] sp_global_search
-- Función   : Búsqueda global de pacientes, trabajadores y vacunas por texto libre
-- Recibe    : p_query TEXT, p_results REFCURSOR
-- Devuelve  : Filas de resultados con tipo y datos básicos
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_global_search(

    IN    p_query   VARCHAR,

    INOUT p_results REFCURSOR

)

LANGUAGE plpgsql AS $$

BEGIN

    OPEN p_results FOR

    -- Si la query es solo dígitos, priorizar búsqueda por nfc_id
    SELECT

        patient_id AS id,

        full_name AS name,

        'patient' AS type,

        birth_date::text AS metadata,

        CASE
            WHEN p_query ~ '^[0-9]+$' AND nfc_id = p_query THEN 0
            ELSE 1
        END AS sort_priority

    FROM v_patients_full

    WHERE full_name ILIKE '%' || p_query || '%'
       OR curp ILIKE '%' || p_query || '%'
       OR nfc_id ILIKE '%' || p_query || '%'



    UNION ALL



    SELECT

        worker_id AS id,

        (first_name || ' ' || last_name) AS name,

        'worker' AS type,

        NULL AS metadata,

        1 AS sort_priority

    FROM workers

    WHERE (first_name || ' ' || last_name) ILIKE '%' || p_query || '%'



    UNION ALL



    SELECT

        vaccine_id AS id,

        name AS name,

        'vaccine' AS type,

        NULL AS metadata,

        1 AS sort_priority

    FROM vaccines

    WHERE name ILIKE '%' || p_query || '%' OR commercial_name ILIKE '%' || p_query || '%'



    UNION ALL



    SELECT

        clinic_id AS id,

        name AS name,

        'clinic' AS type,

        NULL AS metadata,

        1 AS sort_priority

    FROM clinics

    WHERE name ILIKE '%' || p_query || '%'



    ORDER BY sort_priority, type, name

    LIMIT 50;

END;

$$;

-- ============================================================
-- MÓDULO: CATÁLOGOS
-- ============================================================

-- ============================================================
-- [76] sp_get_blood_types
-- Función   : Devuelve el catálogo de tipos de sangre
-- Recibe    : p_results REFCURSOR
-- Devuelve  : Filas de blood_types
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_blood_types(

    INOUT p_results REFCURSOR

)

LANGUAGE plpgsql AS $$

BEGIN

    OPEN p_results FOR

        SELECT blood_type_id, blood_type FROM blood_types ORDER BY blood_type_id;

END;

$$;

-- ============================================================
-- [77] sp_get_manufacturers
-- Función   : Devuelve el catálogo de fabricantes de vacunas
-- Recibe    : p_results REFCURSOR
-- Devuelve  : Filas de manufacturers
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_manufacturers(

    INOUT p_results REFCURSOR

)

LANGUAGE plpgsql AS $$

BEGIN

    OPEN p_results FOR

        SELECT manufacturer_id, name FROM manufacturers ORDER BY name;

END;

$$;

-- ============================================================
-- [78] sp_get_vaccine_vias
-- Función   : Devuelve el catálogo de vías de administración de vacunas
-- Recibe    : p_results REFCURSOR
-- Devuelve  : Filas de vaccine_vias
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_vaccine_vias(

    INOUT p_results REFCURSOR

)

LANGUAGE plpgsql AS $$

BEGIN

    OPEN p_results FOR

        SELECT via_id, via FROM vaccine_vias ORDER BY via;

END;

$$;

-- ============================================================
-- [79] sp_get_roles
-- Función   : Devuelve el catálogo de roles del sistema
-- Recibe    : p_results REFCURSOR
-- Devuelve  : Filas de roles
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_roles(

    INOUT p_results REFCURSOR

)

LANGUAGE plpgsql AS $$

BEGIN

    OPEN p_results FOR

        SELECT role_id, name FROM roles ORDER BY name;

END;

$$;

-- ============================================================
-- [80] sp_get_clinics
-- Función   : Devuelve clínicas activas simplificadas para selectores
-- Recibe    : p_results REFCURSOR
-- Devuelve  : clinic_id y name de clinics activas
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_clinics(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT clinic_id, name FROM clinics WHERE is_active = TRUE ORDER BY name;
END;
$$;

-- ============================================================
-- [68] sp_get_workers_for_dropdown
-- Función   : Lista simplificada de trabajadores activos para selectores de formularios
-- Recibe    : p_clinic_id INT opcional, p_role_name VARCHAR opcional
-- Devuelve  : worker_id y full_name filtrados
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_workers_for_dropdown(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT w.worker_id, w.first_name || ' ' || w.last_name AS name, r.name AS role
        FROM workers w
        LEFT JOIN roles r ON w.role_id = r.role_id
        ORDER BY w.first_name, w.last_name;
END;
$$;

-- ============================================================
-- [82] sp_get_vaccine_lots_available
-- Función   : Lotes disponibles con stock vigente para un selector de lotes al aplicar vacunas
-- Recibe    : p_vaccine_id INT, p_clinic_id INT
-- Devuelve  : Filas de vaccine_lots con stock > 0 y no vencidos
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_vaccine_lots_available(
    IN    p_vaccine_id INT,
    INOUT p_results    REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT lot_id, lot_number, quantity_available, expiration_date
        FROM vaccine_lots
        WHERE vaccine_id = p_vaccine_id AND quantity_available > 0 AND expiration_date > NOW()::DATE
        ORDER BY expiration_date ASC;
END;
$$;

-- ============================================================
-- [83] sp_get_application_sites
-- Función   : Devuelve el catálogo de sitios de aplicación de vacunas
-- Recibe    : p_results REFCURSOR
-- Devuelve  : Filas de application_sites
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_application_sites(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT application_site_id, application_site FROM application_sites ORDER BY application_site;
END;
$$;

-- ============================================================
-- [84] sp_get_countries
-- Función   : Devuelve el catálogo de países
-- Recibe    : p_results REFCURSOR
-- Devuelve  : Filas de countries
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_countries(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT country_id, name, iso_code FROM countries ORDER BY name;
END;
$$;

-- ============================================================
-- [85] sp_get_states
-- Función   : Devuelve estados/provincias filtrados por país
-- Recibe    : p_country_id INT opcional
-- Devuelve  : Filas de states
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_states(
    IN    p_country_id INT,
    INOUT p_results    REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT state_id, name, code FROM states WHERE country_id = p_country_id ORDER BY name;
END;
$$;

-- ============================================================
-- [86] sp_get_municipalities
-- Función   : Devuelve municipios filtrados por estado
-- Recibe    : p_state_id INT opcional
-- Devuelve  : Filas de municipalities
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_municipalities(
    IN    p_state_id INT,
    INOUT p_results  REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT municipality_id, name FROM municipalities WHERE state_id = p_state_id ORDER BY name;
END;
$$;







-- ============================================================
-- MÓDULO: LECTURA GENERAL
-- ============================================================

-- ============================================================
-- [88] sp_get_vaccines_full
-- Función   : Lista completa de vacunas con fabricante, vía y stock total
-- Recibe    : p_results REFCURSOR
-- Devuelve  : Filas de vaccines con datos enriquecidos de fabricante y stock
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_vaccines_full(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            v.vaccine_id,
            v.name,
            v.commercial_name,
            v.disease_prevented,
            v.ideal_age_months,
            COALESCE(m.name, '—')  AS manufacturer,
            COALESCE(vv.via, '—')  AS route
        FROM vaccines v
        LEFT JOIN manufacturers m  ON m.manufacturer_id = v.manufacturer_id
        LEFT JOIN vaccine_vias  vv ON vv.via_id          = v.via_id
        ORDER BY v.name;
END;
$$;

-- ============================================================
-- [89] sp_get_vaccination_records_full
-- Función   : Historial completo de vacunaciones del sistema
-- Recibe    : p_results REFCURSOR
-- Devuelve  : Filas de v_vaccination_records_full
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_vaccination_records_full(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT * FROM v_vaccination_records_full
        ORDER BY applied_date DESC;
END;
$$;

-- ============================================================
-- [69] sp_get_workers_full
-- Función   : Lista completa de trabajadores con rol, emails y clínica
-- Recibe    : p_results REFCURSOR
-- Devuelve  : Filas de vw_worker_full con datos completos
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_workers_full(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            w.worker_id,
            w.first_name,
            w.last_name,
            TRIM(w.first_name || ' ' || w.last_name) AS full_name,
            r.name    AS role_name,
            r.role_id,
            we.email,
            we.email  AS mail,
            r.name    AS role
        FROM workers w
        LEFT JOIN roles r ON r.role_id = w.role_id
        LEFT JOIN worker_emails we
               ON we.worker_id = w.worker_id
              AND we.is_primary = TRUE
        ORDER BY w.last_name, w.first_name;
END;
$$;

-- ============================================================
-- [23] sp_get_esquema_vacunacion
-- Función   : Devuelve el catálogo de vacunas con sus dosis del esquema nacional
-- Recibe    : p_results REFCURSOR
-- Devuelve  : Filas de vaccines + scheme_doses ordenadas
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_esquema_vacunacion(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            v.vaccine_id,
            v.name            AS vaccine_name,
            v.commercial_name,
            v.disease_prevented,
            sd.dose_id,
            sd.dose_label,
            sd.dose_number,
            sd.ideal_age_months
        FROM vaccines v
        JOIN scheme_doses sd ON sd.vaccine_id = v.vaccine_id
        ORDER BY v.name, sd.ideal_age_months, sd.dose_number;
END;
$$;

-- ============================================================
-- [12] sp_get_pending_scheme_doses
-- Función   : Dosis pendientes y atrasadas de todos los pacientes activos para alertas masivas
-- Recibe    : p_results REFCURSOR
-- Devuelve  : Filas con patient_id, vaccine_name, due_date y días de retraso
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_pending_scheme_doses(
    IN    p_patient_id INT,
    INOUT p_results    REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            v.name            AS vaccine_name,
            sd.dose_label,
            sd.ideal_age_months,
            (p.birth_date + (sd.ideal_age_months || ' months')::INTERVAL)::DATE AS ideal_date
        FROM patients p
        CROSS JOIN scheme_doses sd
        JOIN vaccines v ON v.vaccine_id = sd.vaccine_id
        WHERE p.patient_id = p_patient_id
          AND p.is_active   = TRUE
          AND NOT EXISTS (
              SELECT 1 FROM vaccination_records vr
              WHERE vr.patient_id    = p_patient_id
                AND vr.scheme_dose_id = sd.dose_id
          )
        ORDER BY sd.ideal_age_months, sd.dose_number;
END;
$$;

-- ============================================================
-- [90] sp_get_inventory_status
-- Función   : Estado del inventario de insumos clínicos
-- Recibe    : p_results REFCURSOR
-- Devuelve  : Filas de v_inventory_status
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_inventory_status(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT * FROM v_inventory_status
        ORDER BY clinic_name, supply_category, supply_name;
END;
$$;

-- ============================================================
-- MÓDULO: NFC
-- ============================================================

-- ============================================================
-- [41] sp_get_nfc_cards_full
-- Función   : Lista completa de tarjetas NFC con datos del paciente vinculado
-- Recibe    : p_results REFCURSOR
-- Devuelve  : Filas de nfc_cards con patient_name, status y last_scanned_at
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_nfc_cards_full(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            nc.nfc_card_id,
            nc.uid,
            nc.card_type,
            nc.issued_date,
            nc.status,
            nc.last_scanned_at,
            nc.nfc_card_notes,
            nc.patient_id,

            -- Paciente
            TRIM(p.first_name || ' ' || p.last_name)          AS patient_name,
            p.birth_date                                       AS patient_birth_date,
            DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT
                                                               AS patient_age,

            -- Trabajador que emitio la tarjeta
            COALESCE(TRIM(wi.first_name || ' ' || wi.last_name), '-')
                                                               AS issued_by_name,

            -- Estado clinico actual (visita activa hoy)
            pcv.visit_status                                   AS current_visit_status,

            -- Estadisticas de uso
            (SELECT COUNT(*) FROM nfc_scan_events se
             WHERE se.nfc_card_id = nc.nfc_card_id)            AS total_scans,

            (SELECT COUNT(*) FROM nfc_scan_events se
             WHERE se.nfc_card_id = nc.nfc_card_id
               AND se.scanned_at >= CURRENT_DATE - INTERVAL '30 days')
                                                               AS scans_last_30d,

            -- Dias desde ultimo escaneo
            CASE
                WHEN nc.last_scanned_at IS NOT NULL
                THEN (CURRENT_DATE - nc.last_scanned_at::DATE)
                ELSE NULL
            END                                                AS days_since_scan,

            -- Alerta: tarjeta activa sin uso por mas de 90 dias
            CASE
                WHEN nc.status = 'Activa'
                     AND (nc.last_scanned_at IS NULL
                          OR nc.last_scanned_at < CURRENT_DATE - INTERVAL '90 days')
                THEN TRUE
                ELSE FALSE
            END                                                AS alert_inactive

        FROM nfc_cards nc
        JOIN  patients p  ON p.patient_id  = nc.patient_id
        LEFT JOIN workers wi ON wi.worker_id = nc.issued_by
        LEFT JOIN LATERAL (
            SELECT visit_status
            FROM   patient_clinic_visits
            WHERE  patient_id  = p.patient_id
              AND  visit_status NOT IN ('Finalizado','Abandono','Cancelado')
            ORDER BY checked_in_at DESC
            LIMIT 1
        ) pcv ON TRUE
        ORDER BY
            CASE nc.status
                WHEN 'Activa'   THEN 1
                WHEN 'Inactiva' THEN 2
                WHEN 'Perdida'  THEN 3
                WHEN 'Robada'   THEN 4
            END,
            nc.issued_date DESC;
END;
$$;

-- ============================================================
-- [42] sp_get_nfc_scans_full
-- Función   : Historial completo de escaneos NFC
-- Recibe    : p_results REFCURSOR
-- Devuelve  : Filas de nfc_scan_events con datos de paciente, trabajador y clínica
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_nfc_scans_full(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            se.scan_event_id,
            se.nfc_card_id,
            se.scanned_at,
            se.action_triggered,
            -- Contexto clínico (sistema nuevo) o resultado legacy
            COALESCE(se.scan_context, se.action_triggered, '-')    AS scan_context,
            COALESCE(se.resolved_action, se.nfc_scan_result, '-')  AS resolved_action,
            se.error_reason,
            se.nfc_scan_result,

            -- Tarjeta
            nc.uid                                                 AS card_uid,
            nc.status                                              AS card_status,

            -- Paciente (a traves de la tarjeta)
            nc.patient_id,
            TRIM(p.first_name || ' ' || p.last_name)              AS patient_name,
            DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT
                                                                   AS patient_age,

            -- Trabajador que escaneo
            COALESCE(TRIM(w.first_name || ' ' || w.last_name), '-')
                                                                   AS worker_name,
            COALESCE(TRIM(w.first_name || ' ' || w.last_name), '-')
                                                                   AS scanned_by_name,

            -- Ubicacion
            c.name                                                 AS clinic_name,
            COALESCE(ca.name, '-')                                 AS area_name,

            -- Resultado unificado para la UI
            CASE
                -- Sistema nuevo: resolved_action indica éxito
                WHEN se.resolved_action IN ('visit_created','consulta_started',
                                            'expedient_opened','checkout_done')
                THEN 'Éxito'
                -- Sistema nuevo: error
                WHEN se.error_reason IS NOT NULL
                THEN 'Error'
                -- Legacy
                WHEN se.nfc_scan_result ILIKE '%exito%'
                  OR se.nfc_scan_result ILIKE '%ok%'
                  OR se.nfc_scan_result ILIKE '%acceso%'
                THEN 'Éxito'
                WHEN se.nfc_scan_result ILIKE '%error%'
                  OR se.nfc_scan_result ILIKE '%fallo%'
                  OR se.nfc_scan_result ILIKE '%rechaz%'
                THEN 'Error'
                ELSE 'Éxito'
            END                                                    AS result

        FROM nfc_scan_events se
        JOIN  nfc_cards  nc ON nc.nfc_card_id = se.nfc_card_id
        JOIN  patients   p  ON p.patient_id   = nc.patient_id
        JOIN  clinics    c  ON c.clinic_id    = se.clinic_id
        LEFT JOIN workers      w  ON w.worker_id  = se.scanned_by
        LEFT JOIN clinic_areas ca ON ca.area_id   = se.area_id
        LEFT JOIN nfc_devices  nd ON nd.device_id = se.device_id
        ORDER BY se.scanned_at DESC;
END;
$$;

-- ============================================================
-- [43] sp_get_nfc_card_history
-- Función   : Historial de una tarjeta NFC específica
-- Recibe    : p_nfc_uid VARCHAR
-- Devuelve  : Eventos de escaneo de esa tarjeta ordenados por fecha
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_nfc_card_history(
    IN    p_nfc_card_id INT,
    INOUT p_results     REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM nfc_cards WHERE nfc_card_id = p_nfc_card_id) THEN
        RAISE EXCEPTION 'Tarjeta NFC % no encontrada', p_nfc_card_id;
    END IF;

    OPEN p_results FOR
        SELECT
            se.scan_event_id,
            se.scanned_at,
            se.action_triggered,
            se.nfc_scan_result,
            c.name                                                    AS clinic_name,
            COALESCE(ca.name, '-')                                    AS area_name,
            COALESCE(TRIM(w.first_name || ' ' || w.last_name), '-')  AS worker_name
        FROM nfc_scan_events se
        JOIN  clinics    c  ON c.clinic_id   = se.clinic_id
        LEFT JOIN workers      w  ON w.worker_id = se.scanned_by
        LEFT JOIN clinic_areas ca ON ca.area_id  = se.area_id
        WHERE se.nfc_card_id = p_nfc_card_id
        ORDER BY se.scanned_at DESC;
END;
$$;


-- ============================================================
-- MÓDULO: NFC
-- ============================================================

-- ============================================================
-- [36] sp_assign_nfc_card
-- Función   : Asigna una tarjeta NFC a un paciente o actualiza la asignación existente
-- Recibe    : p_nfc_uid VARCHAR, p_patient_id INT
-- Devuelve  : success, message, nfc_uid, patient_id
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_assign_nfc_card(
    IN    p_patient_id  INT,
    IN    p_uid         VARCHAR,
    IN    p_card_type   VARCHAR,
    IN    p_issued_by   INT,
    IN    p_notes       TEXT,
    INOUT p_results     REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_nfc_card_id INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM patients WHERE patient_id = p_patient_id) THEN
        RAISE EXCEPTION 'El paciente % no existe', p_patient_id;
    END IF;

    IF TRIM(COALESCE(p_uid, '')) = '' THEN
        RAISE EXCEPTION 'El UID de la tarjeta es obligatorio';
    END IF;

    IF EXISTS (SELECT 1 FROM nfc_cards WHERE uid = TRIM(p_uid) AND status = 'Activa') THEN
        RAISE EXCEPTION 'Ya existe una tarjeta activa con el UID %', p_uid;
    END IF;

    IF EXISTS (
        SELECT 1 FROM nfc_cards
        WHERE patient_id = p_patient_id AND status = 'Activa'
    ) THEN
        RAISE EXCEPTION 'El paciente ya tiene una tarjeta NFC activa. Desactivala antes de asignar una nueva.';
    END IF;

    IF p_issued_by IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM workers WHERE worker_id = p_issued_by
    ) THEN
        RAISE EXCEPTION 'El trabajador emisor % no existe', p_issued_by;
    END IF;

    INSERT INTO nfc_cards (
        patient_id, uid, card_type,
        issued_date, issued_by, status, nfc_card_notes
    )
    VALUES (
        p_patient_id,
        TRIM(p_uid),
        NULLIF(TRIM(COALESCE(p_card_type, '')), ''),
        CURRENT_DATE,
        p_issued_by,
        'Activa',
        NULLIF(TRIM(COALESCE(p_notes, '')), '')
    )
    RETURNING nfc_card_id INTO v_nfc_card_id;

    OPEN p_results FOR
        SELECT TRUE          AS success,
               'Tarjeta NFC asignada correctamente' AS message,
               v_nfc_card_id AS nfc_card_id,
               TRIM(p_uid)   AS uid;

EXCEPTION WHEN OTHERS THEN
    OPEN p_results FOR
        SELECT FALSE AS success, SQLERRM AS message,
               NULL::INT AS nfc_card_id, NULL::VARCHAR AS uid;
END;
$$;

-- ============================================================
-- [37] sp_update_nfc_card_status
-- Función   : Actualiza el status de una tarjeta NFC (Activa, Inactiva, Perdida)
-- Recibe    : p_nfc_uid VARCHAR, p_status VARCHAR
-- Devuelve  : success, message
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_update_nfc_card_status(
    IN    p_nfc_card_id INT,
    IN    p_new_status  VARCHAR,
    IN    p_worker_id   INT,
    IN    p_notes       TEXT,
    INOUT p_results     REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_current_status VARCHAR;
    v_patient_id     INT;
BEGIN
    SELECT status, patient_id
    INTO   v_current_status, v_patient_id
    FROM   nfc_cards
    WHERE  nfc_card_id = p_nfc_card_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tarjeta NFC % no encontrada', p_nfc_card_id;
    END IF;

    IF p_new_status NOT IN ('Activa', 'Inactiva', 'Perdida', 'Robada') THEN
        RAISE EXCEPTION 'Estado invalido: %. Valores permitidos: Activa, Inactiva, Perdida, Robada', p_new_status;
    END IF;

    -- Regla clinica: tarjeta Perdida o Robada no puede reactivarse directamente
    IF v_current_status IN ('Perdida', 'Robada') AND p_new_status = 'Activa' THEN
        RAISE EXCEPTION 'Una tarjeta % no puede reactivarse directamente. Asigna una nueva al paciente.', v_current_status;
    END IF;

    -- Si se activa, verificar que no haya otra activa para el mismo paciente
    IF p_new_status = 'Activa' AND EXISTS (
        SELECT 1 FROM nfc_cards
        WHERE  patient_id  = v_patient_id
          AND  status      = 'Activa'
          AND  nfc_card_id <> p_nfc_card_id
    ) THEN
        RAISE EXCEPTION 'El paciente ya tiene otra tarjeta NFC activa';
    END IF;

    UPDATE nfc_cards
    SET
        status         = p_new_status,
        nfc_card_notes = CASE
                            WHEN p_notes IS NOT NULL AND TRIM(p_notes) <> ''
                            THEN COALESCE(nfc_card_notes || ' | ', '') ||
                                 TO_CHAR(CURRENT_DATE, 'YYYY-MM-DD') || ': ' || TRIM(p_notes)
                            ELSE nfc_card_notes
                         END
    WHERE nfc_card_id = p_nfc_card_id;

    OPEN p_results FOR
        SELECT TRUE          AS success,
               'Estado actualizado a ' || p_new_status AS message,
               p_nfc_card_id AS nfc_card_id,
               p_new_status  AS new_status,
               v_patient_id  AS patient_id;

EXCEPTION WHEN OTHERS THEN
    OPEN p_results FOR
        SELECT FALSE AS success, SQLERRM AS message,
               p_nfc_card_id AS nfc_card_id,
               NULL::VARCHAR AS new_status,
               NULL::INT     AS patient_id;
END;
$$;

-- ============================================================
-- [38] sp_register_nfc_scan
-- Función   : Registra un evento de escaneo NFC con contexto de clínica y tipo de scan
-- Recibe    : p_nfc_uid, p_clinic_id, p_scan_type, p_worker_id
-- Devuelve  : success, scan_id, patient_id, message
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_register_nfc_scan(
    IN    p_uid             VARCHAR,
    IN    p_worker_id       INT,
    IN    p_clinic_id       INT,
    IN    p_area_id         INT,
    IN    p_device_id       VARCHAR,
    IN    p_action          VARCHAR,
    INOUT p_results         REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_nfc_card_id   INT;
    v_patient_id    INT;
    v_card_status   VARCHAR;
    v_scan_result   VARCHAR;
    v_scan_event_id INT;
BEGIN
    -- Buscar tarjeta por UID
    SELECT nfc_card_id, patient_id, status
    INTO   v_nfc_card_id, v_patient_id, v_card_status
    FROM   nfc_cards
    WHERE  uid = TRIM(p_uid);

    IF NOT FOUND THEN
        v_scan_result := 'Error: UID no registrado';

        -- Registrar el intento fallido igualmente
        INSERT INTO nfc_scan_events (
            nfc_card_id, scanned_by, clinic_id, area_id,
            scanned_at, action_triggered, device_id, nfc_scan_result
        )
        SELECT -1, p_worker_id, p_clinic_id, p_area_id,
               NOW(), p_action, p_device_id, v_scan_result
        WHERE FALSE; -- no se inserta, tarjeta no existe

        OPEN p_results FOR
            SELECT FALSE AS success, v_scan_result AS message,
                   NULL::INT AS nfc_card_id, NULL::INT AS patient_id,
                   NULL::VARCHAR AS patient_name, NULL::TEXT AS card_status;
        RETURN;
    END IF;

    -- Validar estado de la tarjeta
    IF v_card_status IN ('Perdida', 'Robada') THEN
        v_scan_result := 'Error: tarjeta ' || v_card_status || ' - contactar seguridad';

        INSERT INTO nfc_scan_events (
            nfc_card_id, scanned_by, clinic_id, area_id,
            scanned_at, action_triggered, device_id, nfc_scan_result
        )
        VALUES (
            v_nfc_card_id, p_worker_id, p_clinic_id, p_area_id,
            NOW(), p_action, p_device_id, v_scan_result
        )
        RETURNING scan_event_id INTO v_scan_event_id;

        OPEN p_results FOR
            SELECT FALSE AS success, v_scan_result AS message,
                   v_nfc_card_id AS nfc_card_id, v_patient_id AS patient_id,
                   NULL::VARCHAR AS patient_name, v_card_status AS card_status;
        RETURN;
    END IF;

    IF v_card_status = 'Inactiva' THEN
        v_scan_result := 'Error: tarjeta inactiva';

        INSERT INTO nfc_scan_events (
            nfc_card_id, scanned_by, clinic_id, area_id,
            scanned_at, action_triggered, device_id, nfc_scan_result
        )
        VALUES (
            v_nfc_card_id, p_worker_id, p_clinic_id, p_area_id,
            NOW(), p_action, p_device_id, v_scan_result
        )
        RETURNING scan_event_id INTO v_scan_event_id;

        OPEN p_results FOR
            SELECT FALSE AS success, v_scan_result AS message,
                   v_nfc_card_id AS nfc_card_id, v_patient_id AS patient_id,
                   NULL::VARCHAR AS patient_name, v_card_status AS card_status;
        RETURN;
    END IF;

    -- Validar clínica
    IF NOT EXISTS (SELECT 1 FROM clinics WHERE clinic_id = p_clinic_id AND is_active = TRUE) THEN
        RAISE EXCEPTION 'Clinica % no encontrada o inactiva', p_clinic_id;
    END IF;

    -- Validar trabajador si se proporciona
    IF p_worker_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM workers WHERE worker_id = p_worker_id
    ) THEN
        RAISE EXCEPTION 'Trabajador % no encontrado', p_worker_id;
    END IF;

    v_scan_result := 'Exito';

    -- Registrar escaneo exitoso
    INSERT INTO nfc_scan_events (
        nfc_card_id, scanned_by, clinic_id, area_id,
        scanned_at, action_triggered, device_id, nfc_scan_result
    )
    VALUES (
        v_nfc_card_id, p_worker_id, p_clinic_id, p_area_id,
        NOW(), COALESCE(p_action, 'Consulta'), p_device_id, v_scan_result
    )
    RETURNING scan_event_id INTO v_scan_event_id;

    -- Actualizar last_scanned_at en la tarjeta
    UPDATE nfc_cards
    SET last_scanned_at = NOW()
    WHERE nfc_card_id = v_nfc_card_id;

    -- Devolver datos del paciente para mostrar en pantalla
    OPEN p_results FOR
        SELECT
            TRUE                                              AS success,
            'Acceso concedido'                               AS message,
            v_scan_event_id                                  AS scan_event_id,
            v_nfc_card_id                                    AS nfc_card_id,
            v_patient_id                                     AS patient_id,
            TRIM(p.first_name || ' ' || p.last_name)        AS patient_name,
            p.birth_date,
            DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT AS age_years,
            COALESCE(bt.blood_type, '-')                    AS blood_type,
            v_card_status                                    AS card_status,
            -- Próximas 3 dosis pendientes del paciente (JSON)
            (
                SELECT JSON_AGG(sub)
                FROM (
                    SELECT
                        v2.name                                         AS vaccine,
                        sd2.dose_label                                  AS dose,
                        (p2.birth_date + (sd2.ideal_age_months || ' months')::INTERVAL)::DATE
                                                                        AS due_date
                    FROM scheme_doses sd2
                    JOIN vaccines v2 ON v2.vaccine_id = sd2.vaccine_id
                    JOIN patients  p2 ON p2.patient_id = v_patient_id
                    WHERE NOT EXISTS (
                        SELECT 1 FROM vaccination_records vr2
                        WHERE vr2.patient_id    = v_patient_id
                          AND vr2.scheme_dose_id = sd2.dose_id
                    )
                    ORDER BY sd2.ideal_age_months
                    LIMIT 3
                ) sub
            )                                               AS pending_doses
        FROM patients p
        LEFT JOIN blood_types bt ON bt.blood_type_id = p.blood_type_id
        WHERE p.patient_id = v_patient_id;

EXCEPTION WHEN OTHERS THEN
    OPEN p_results FOR
        SELECT FALSE AS success, SQLERRM AS message,
               NULL::INT AS scan_event_id, NULL::INT AS nfc_card_id,
               NULL::INT AS patient_id,   NULL::VARCHAR AS patient_name,
               NULL::DATE AS birth_date,  NULL::INT AS age_years,
               NULL::VARCHAR AS blood_type, NULL::VARCHAR AS card_status,
               NULL::JSON AS pending_doses;
END;
$$;

-- ============================================================
-- [81] sp_get_clinics_full
-- Función   : Devuelve todas las clínicas con datos completos incluyendo dirección y área
-- Recibe    : p_results REFCURSOR
-- Devuelve  : Filas completas de clinics
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_clinics_full(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            c.clinic_id,
            c.name,
            c.phone,
            c.institution_type,
            c.is_active,
            COALESCE(mu.name || ', ' || st.name, '—') AS address_str,
            COALESCE(areas_sub.areas, '[]'::json)      AS areas
        FROM clinics c
        LEFT JOIN addresses      ad  ON ad.address_id      = c.address_id
        LEFT JOIN neighborhoods  nb  ON nb.neighborhood_id = ad.neighborhood_id
        LEFT JOIN municipalities mu  ON mu.municipality_id = nb.municipality_id
        LEFT JOIN states         st  ON st.state_id        = mu.state_id
        LEFT JOIN LATERAL (
            SELECT json_agg(
                json_build_object(
                    'name',      ca.name,
                    'floor',     ca.floor,
                    'capacity',  ca.capacity
                ) ORDER BY ca.name
            ) AS areas
            FROM clinic_areas ca
            WHERE ca.clinic_id = c.clinic_id
        ) areas_sub ON TRUE
        WHERE c.is_active = TRUE
        ORDER BY c.name;
END;
$$;

-- ============================================================
-- [70] sp_get_schema_alerts_full
-- Función   : Devuelve todas las alertas de esquema vacunal desde v_scheme_alerts_full
-- Recibe    : p_results REFCURSOR
-- Devuelve  : Filas de v_scheme_alerts_full
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_schema_alerts_full(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            sca.alert_id,
            sca.patient_id,
            sca.schedule_id,
            sca.alert_type,
            sca.due_date,
            sca.status,
            sca.notified_at,
            sca.read_at,
            TRIM(p.first_name || ' ' || p.last_name) AS patient_name,
            v.name      AS vaccine_name,
            sd.dose_label
        FROM scheme_completion_alerts sca
        JOIN patients                p  ON p.patient_id    = sca.patient_id
        JOIN patient_vaccine_schedule pvs ON pvs.schedule_id = sca.schedule_id
        JOIN scheme_doses            sd ON sd.dose_id      = pvs.scheme_dose_id
        JOIN vaccines                v  ON v.vaccine_id   = sd.vaccine_id
        ORDER BY sca.due_date ASC;
END;
$$;


-- ============================================================
-- [18] sp_delete_vaccine
-- Función   : Elimina (o desactiva) una vacuna del catálogo
-- Recibe    : p_vaccine_id INT
-- Devuelve  : success
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_delete_vaccine(
    IN    p_vaccine_id INT,
    INOUT p_results    REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM vaccines WHERE vaccine_id = p_vaccine_id) THEN
        RAISE EXCEPTION 'Vacuna % no encontrada', p_vaccine_id;
    END IF;

    DELETE FROM vaccines WHERE vaccine_id = p_vaccine_id;

    OPEN p_results FOR
        SELECT TRUE AS success, 'Vacuna eliminada' AS message, p_vaccine_id AS vaccine_id;
EXCEPTION
WHEN OTHERS THEN
    OPEN p_results FOR
        SELECT FALSE AS success, SQLERRM AS message, p_vaccine_id AS vaccine_id;
END;
$$;

-- ============================================================
-- MÓDULO: TRABAJADORES
-- ============================================================

-- ============================================================
-- [66] sp_register_worker
-- Función   : Registra un nuevo trabajador con rol y correo electrónico
-- Recibe    : nombre, apellido, role_id, email, password_hash, clinic_id
-- Devuelve  : success, worker_id, message
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_register_worker(
    IN    p_role_id      INT,
    IN    p_first_name   VARCHAR,
    IN    p_last_name    VARCHAR,
    IN    p_hire_date    DATE,
    IN    p_password     VARCHAR,
    IN    p_email        VARCHAR,
    IN    p_phone        VARCHAR,
    INOUT p_results      REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_worker_id INT;
    v_user_id   INT;
BEGIN
    INSERT INTO workers (role_id, first_name, last_name, hire_date)
    VALUES (p_role_id, p_first_name, p_last_name, p_hire_date)
    RETURNING worker_id INTO v_worker_id;

    IF p_email IS NOT NULL AND TRIM(p_email) <> '' THEN
        INSERT INTO worker_emails (worker_id, email, is_primary)
        VALUES (v_worker_id, p_email, TRUE);
    END IF;

    INSERT INTO users (worker_id, username, password_hash, is_active)
    VALUES (v_worker_id, COALESCE(p_email, 'user_' || v_worker_id),
            p_password, TRUE)
    RETURNING user_id INTO v_user_id;

    OPEN p_results FOR
        SELECT TRUE AS success, 'Trabajador registrado' AS message, v_worker_id AS worker_id;
EXCEPTION
WHEN OTHERS THEN
    OPEN p_results FOR
        SELECT FALSE AS success, SQLERRM AS message, NULL::INT AS worker_id;
END;
$$;

-- ============================================================
-- [67] sp_update_worker
-- Función   : Actualiza datos de un trabajador existente
-- Recibe    : p_worker_id y campos opcionales
-- Devuelve  : success, message
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_update_worker(
    IN    p_worker_id  INT,
    IN    p_first_name VARCHAR,
    IN    p_last_name  VARCHAR,
    IN    p_role_id    INT,
    IN    p_email      VARCHAR,
    INOUT p_results    REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM workers WHERE worker_id = p_worker_id) THEN
        RAISE EXCEPTION 'Trabajador % no encontrado', p_worker_id;
    END IF;

    UPDATE workers
    SET first_name = COALESCE(NULLIF(TRIM(p_first_name), ''), first_name),
        last_name  = COALESCE(NULLIF(TRIM(p_last_name),  ''), last_name),
        role_id    = COALESCE(p_role_id, role_id)
    WHERE worker_id = p_worker_id;

    IF p_email IS NOT NULL AND TRIM(p_email) <> '' THEN
        UPDATE worker_emails
        SET email = p_email
        WHERE worker_id = p_worker_id AND is_primary = TRUE;

        IF NOT FOUND THEN
            INSERT INTO worker_emails (worker_id, email, is_primary)
            VALUES (p_worker_id, p_email, TRUE);
        END IF;
    END IF;

    OPEN p_results FOR
        SELECT TRUE AS success, 'Trabajador actualizado' AS message, p_worker_id AS worker_id;
EXCEPTION
WHEN OTHERS THEN
    OPEN p_results FOR
        SELECT FALSE AS success, SQLERRM AS message, NULL::INT AS worker_id;
END;
$$;

-- ============================================================
-- [15] sp_register_guardian_account
-- Función   : Crea o actualiza la cuenta de portal de un tutor
-- Recibe    : datos del guardián y credenciales
-- Devuelve  : success, guardian_id, message
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_register_guardian_account(
    IN p_guardian_id INT,
    IN p_email VARCHAR,
    IN p_password_hash VARCHAR,
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_account_id INT;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM guardians
        WHERE guardian_id = p_guardian_id
    ) THEN
        RAISE EXCEPTION
        'El tutor no existe';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM guardian_accounts
        WHERE guardian_id = p_guardian_id
    ) THEN
        RAISE EXCEPTION
        'El tutor ya tiene una cuenta registrada';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM guardian_accounts
        WHERE LOWER(email) = LOWER(TRIM(p_email))
    ) THEN

        RAISE EXCEPTION
        'El correo ya está registrado';

    END IF;

    INSERT INTO guardian_accounts (

        guardian_id,
        email,
        password_hash

    )
    VALUES (

        p_guardian_id,
        LOWER(TRIM(p_email)),
        p_password_hash

    )
    RETURNING guardian_account_id
    INTO v_account_id;

    OPEN p_results FOR

    SELECT
        v_account_id AS guardian_account_id;

END;
$$;

-- ============================================================
-- [71] sp_reportes_resumen
-- Función   : Resumen de reportes por período: vacunaciones, pacientes, coberturas
-- Recibe    : p_start_date DATE, p_end_date DATE, p_clinic_id INT opcional
-- Devuelve  : métricas del período
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_reportes_resumen(
    IN    p_from    DATE,
    IN    p_to      DATE,
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_total_doses       BIGINT;
    v_reached           BIGINT;
    v_target            BIGINT;
    v_coverage          NUMERIC(5,1);
    v_avg_delay         NUMERIC(6,1);
    v_reaction_rate     NUMERIC(5,1);
    v_completed_scheme  BIGINT;
    v_delayed_patients  BIGINT;
    v_appt_rate         NUMERIC(5,1);
    v_low_stock         BIGINT;
    v_new_patients      BIGINT;
    v_active_workers    BIGINT;
    v_expiring_lots     BIGINT;
    v_pending_alerts    BIGINT;
    v_active_zones      BIGINT;
    v_vaccines_json     JSON;
    v_monthly_json      JSON;
    v_zones_json        JSON;
BEGIN

    -- ── Dosis aplicadas y pacientes únicos en el período ──────────────────────
    SELECT COUNT(*) INTO v_total_doses
    FROM v_reportes_vaccination_geo
    WHERE applied_date BETWEEN p_from AND p_to;

    SELECT COUNT(DISTINCT patient_id) INTO v_reached
    FROM v_reportes_vaccination_geo
    WHERE applied_date BETWEEN p_from AND p_to;

    SELECT COUNT(DISTINCT patient_id) INTO v_target
    FROM v_patient_vaccination_scheme_base;

    v_coverage := CASE
        WHEN v_target > 0 THEN ROUND((v_reached::NUMERIC / v_target) * 100, 1)
        ELSE 0
    END;

    -- ── Lotes próximos a vencer (≤30 días con stock disponible) ─────────────
    SELECT COUNT(*) INTO v_expiring_lots
    FROM v_vaccine_lots_detail
    WHERE is_expiring_soon = TRUE
      AND quantity_available > 0;

    -- ── Tasa de reacciones adversas ───────────────────────────────────────────
    SELECT CASE
        WHEN COUNT(*) > 0
        THEN ROUND(COUNT(*) FILTER (WHERE had_reaction = TRUE)::NUMERIC / COUNT(*) * 100, 1)
        ELSE 0
    END INTO v_reaction_rate
    FROM v_reportes_vaccination_geo
    WHERE applied_date BETWEEN p_from AND p_to;

    -- ── Pacientes con esquema completo ────────────────────────────────────────
    SELECT COUNT(*) INTO v_completed_scheme
    FROM (
        SELECT patient_id
        FROM v_patient_vaccination_scheme_base
        GROUP BY patient_id
        HAVING COUNT(*) FILTER (WHERE vaccination_status IN ('Pendiente', 'Atrasada')) = 0
    ) sub;

    -- ── Pacientes con vacunas atrasadas ───────────────────────────────────────
    SELECT COUNT(DISTINCT patient_id) INTO v_delayed_patients
    FROM v_patient_vaccination_scheme_base
    WHERE vaccination_status = 'Atrasada';

    -- ── Tasa de cumplimiento de citas ─────────────────────────────────────────
    SELECT CASE
        WHEN COUNT(*) > 0
        THEN ROUND(
            COUNT(*) FILTER (WHERE appointment_status = 'Completada')::NUMERIC
            / COUNT(*) * 100, 1)
        ELSE NULL
    END INTO v_appt_rate
    FROM v_appointments_full
    WHERE scheduled_at::DATE BETWEEN p_from AND p_to;

    -- ── Lotes en stock bajo (≤ 10 unidades) ──────────────────────────────────
    SELECT COUNT(*) INTO v_low_stock
    FROM v_vaccine_lots_detail
    WHERE is_low_stock = TRUE
      AND expiration_date >= CURRENT_DATE;

    -- ── Alertas de esquema pendientes (no resueltas ni leídas) ───────────────
    BEGIN
        SELECT COUNT(*) INTO v_pending_alerts
        FROM v_scheme_alerts_full
        WHERE alert_status NOT IN ('Resuelta', 'Le' || CHR(237) || 'da');
    EXCEPTION WHEN undefined_table THEN
        v_pending_alerts := NULL;
    END;

    -- ── Nuevos pacientes en el período ────────────────────────────────────────
    BEGIN
        SELECT COUNT(*) INTO v_new_patients
        FROM vw_patients
        WHERE created_at::DATE BETWEEN p_from AND p_to;
    EXCEPTION WHEN undefined_column THEN
        v_new_patients := NULL;
    END;

    -- ── Trabajadores activos que aplicaron en el período ──────────────────────
    SELECT COUNT(DISTINCT worker_id) INTO v_active_workers
    FROM v_reportes_vaccination_geo
    WHERE applied_date BETWEEN p_from AND p_to;

    -- ── Retraso promedio (días entre due_date y applied_date) ─────────────────
    SELECT ROUND(AVG(applied_date - due_date), 1) INTO v_avg_delay
    FROM v_reportes_scheme_delay
    WHERE applied_date BETWEEN p_from AND p_to;

    -- ── Zonas activas (municipios con al menos una dosis en el período) ───────
    SELECT COUNT(DISTINCT neighborhood_id) INTO v_active_zones
    FROM v_reportes_vaccination_geo
    WHERE applied_date BETWEEN p_from AND p_to;

    -- ── JSON: vacunas (top 50 por dosis aplicadas) ────────────────────────────
    SELECT json_agg(t) INTO v_vaccines_json FROM (
        SELECT
            vaccine_name,
            COUNT(record_id)                AS doses_applied,
            COUNT(DISTINCT patient_id)      AS unique_patients,
            ROUND(
                COUNT(record_id)::NUMERIC
                / NULLIF(v_total_doses, 0) * 100, 1
            )                               AS share_percent
        FROM v_reportes_vaccination_geo
        WHERE applied_date BETWEEN p_from AND p_to
        GROUP BY vaccine_id, vaccine_name
        ORDER BY doses_applied DESC
        LIMIT 50
    ) t;

    -- ── JSON: resumen mensual ─────────────────────────────────────────────────
    SELECT json_agg(t ORDER BY t.period_label) INTO v_monthly_json FROM (
        SELECT
            TO_CHAR(applied_date, 'YYYY-MM') AS period_label,
            COUNT(*)                          AS doses_applied,
            COUNT(DISTINCT patient_id)        AS unique_patients
        FROM v_reportes_vaccination_geo
        WHERE applied_date BETWEEN p_from AND p_to
        GROUP BY TO_CHAR(applied_date, 'YYYY-MM')
    ) t;

    -- ── JSON: zonas (municipios) ──────────────────────────────────────────────
    SELECT json_agg(t ORDER BY t.doses_applied DESC) INTO v_zones_json FROM (
        SELECT
            municipality_name               AS zone_name,
            COUNT(record_id)                AS doses_applied,
            COUNT(DISTINCT patient_id)      AS unique_patients,
            CASE
                WHEN COUNT(DISTINCT patient_id) >= 100 THEN 'low'
                WHEN COUNT(DISTINCT patient_id) >= 30  THEN 'medium'
                ELSE 'high'
            END                             AS risk_level,
            CASE
                WHEN COUNT(DISTINCT patient_id) >= 100 THEN 'Bajo'
                WHEN COUNT(DISTINCT patient_id) >= 30  THEN 'Medio'
                ELSE 'Alto'
            END                             AS risk_label
        FROM v_reportes_vaccination_geo
        WHERE applied_date BETWEEN p_from AND p_to
        GROUP BY municipality_id, municipality_name
    ) t;

    OPEN p_results FOR SELECT
        v_total_doses                           AS total_doses_applied,
        v_target                                AS target_population,
        v_reached                               AS reached_population,
        v_coverage                              AS coverage_percent,
        COALESCE(v_avg_delay, 0.0)              AS avg_delay_days,
        v_active_zones                          AS active_zones,
        v_reaction_rate                         AS reaction_rate,
        v_completed_scheme                      AS completed_scheme,
        v_delayed_patients                      AS delayed_patients,
        v_appt_rate                             AS appointment_completion_rate,
        v_low_stock                             AS low_stock_count,
        v_new_patients                          AS new_patients,
        v_active_workers                        AS active_workers,
        v_expiring_lots                         AS expiring_lots,
        v_pending_alerts                        AS pending_alerts,
        COALESCE(v_vaccines_json, '[]'::JSON)   AS vaccines,
        COALESCE(v_monthly_json,  '[]'::JSON)   AS monthly,
        COALESCE(v_zones_json,    '[]'::JSON)   AS zones;

END;
$$;


-- ============================================================
-- ============================================================
--  NUEVOS SPs — ARQUITECTURA REFACTORIZADA
--  Separación: dominio médico / operativo / notificaciones
-- ============================================================
-- ============================================================

-- ============================================================
-- [25] sp_apply_vaccine
-- Función   : Versión simplificada de aplicación de vacuna para el flujo NFC clínico
-- Recibe    : patient_id, vaccine_id, worker_id, clinic_id, lot_id, scheme_dose_id y parámetros clínicos
-- Devuelve  : success, record_id, message
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_apply_vaccine(
    IN    p_patient_id          INT,
    IN    p_vaccine_id          INT,
    IN    p_worker_id           INT,
    IN    p_clinic_id           INT,
    IN    p_lot_id              INT,
    IN    p_scheme_dose_id      INT,
    IN    p_appointment_id      INT,
    IN    p_application_site_id INT,
    IN    p_patient_temp_c      NUMERIC,
    IN    p_had_reaction        BOOLEAN,
    INOUT p_results             REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_record_id     INT;
    v_schedule_id   INT;
    v_birth_date    DATE;
    v_age_months    INT;
    v_ideal_months  INT;
    v_min_interval  INT;
    v_last_applied  DATE;
BEGIN
    -- Paciente activo
    SELECT birth_date INTO v_birth_date
    FROM   patients
    WHERE  patient_id = p_patient_id AND is_active = TRUE;
    IF v_birth_date IS NULL THEN
        RAISE EXCEPTION 'El paciente no existe o está inactivo';
    END IF;

    -- Personal autorizado
    IF NOT EXISTS (
        SELECT 1 FROM workers w JOIN roles r ON r.role_id = w.role_id
        WHERE  w.worker_id = p_worker_id AND w.is_active = TRUE
          AND  r.name IN ('Medico','Enfermero')
    ) THEN
        RAISE EXCEPTION 'Solo médicos o enfermeros pueden aplicar vacunas';
    END IF;

    -- Lote válido, no vencido, con stock, pertenece a la clínica
    IF NOT EXISTS (
        SELECT 1 FROM vaccine_lots
        WHERE  lot_id = p_lot_id AND clinic_id = p_clinic_id
          AND  expiration_date >= CURRENT_DATE AND quantity_available > 0
    ) THEN
        RAISE EXCEPTION 'Lote no encontrado, vencido, sin stock o no pertenece a esta clínica';
    END IF;

    -- Dosis no duplicada
    IF p_scheme_dose_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM vaccination_records
        WHERE  patient_id = p_patient_id AND scheme_dose_id = p_scheme_dose_id
    ) THEN
        RAISE EXCEPTION 'Esta dosis ya fue aplicada a este paciente';
    END IF;

    -- Validar edad mínima para la dosis
    IF p_scheme_dose_id IS NOT NULL THEN
        SELECT ideal_age_months INTO v_ideal_months
        FROM   scheme_doses WHERE dose_id = p_scheme_dose_id;

        v_age_months := (EXTRACT(YEAR  FROM AGE(CURRENT_DATE, v_birth_date)) * 12
                       + EXTRACT(MONTH FROM AGE(CURRENT_DATE, v_birth_date)))::INT;

        IF v_ideal_months IS NOT NULL AND v_age_months < v_ideal_months THEN
            RAISE EXCEPTION 'El paciente no cumple la edad mínima requerida para esta dosis';
        END IF;

        -- Validar intervalo mínimo entre dosis de la misma vacuna
        SELECT min_interval_days INTO v_min_interval
        FROM   scheme_doses WHERE dose_id = p_scheme_dose_id;

        SELECT MAX(applied_date) INTO v_last_applied
        FROM   vaccination_records
        WHERE  patient_id = p_patient_id AND vaccine_id = p_vaccine_id;

        IF v_last_applied IS NOT NULL AND v_min_interval IS NOT NULL
           AND (CURRENT_DATE - v_last_applied) < v_min_interval THEN
            RAISE EXCEPTION 'No se cumple el intervalo mínimo entre dosis (% días)', v_min_interval;
        END IF;

        -- Obtener schedule_id correspondiente
        SELECT schedule_id INTO v_schedule_id
        FROM   patient_vaccine_schedule
        WHERE  patient_id = p_patient_id AND scheme_dose_id = p_scheme_dose_id;
    END IF;

    -- Temperatura válida
    IF p_patient_temp_c IS NOT NULL AND (p_patient_temp_c < 30 OR p_patient_temp_c > 45) THEN
        RAISE EXCEPTION 'Temperatura corporal inválida (debe estar entre 30 y 45 °C)';
    END IF;

    -- Insertar registro
    INSERT INTO vaccination_records (
        patient_id, vaccine_id, worker_id, clinic_id, lot_id,
        scheme_dose_id, applied_date, application_site_id,
        appointment_id, patient_schedule_id,
        patient_temp_c, had_reaction, created_at
    )
    VALUES (
        p_patient_id, p_vaccine_id, p_worker_id, p_clinic_id, p_lot_id,
        p_scheme_dose_id, CURRENT_DATE, p_application_site_id,
        p_appointment_id, v_schedule_id,
        p_patient_temp_c, COALESCE(p_had_reaction, FALSE), NOW()
    )
    RETURNING record_id INTO v_record_id;

    -- Los triggers 12 y 15 actualizan patient_vaccine_schedule y appointments

    OPEN p_results FOR
        SELECT TRUE          AS success,
               v_record_id   AS record_id,
               'Vacuna registrada correctamente' AS message;

EXCEPTION WHEN OTHERS THEN
    OPEN p_results FOR
        SELECT FALSE AS success, SQLERRM AS message, NULL::INT AS record_id;
END;
$$;

-- ============================================================
-- [11] sp_get_pending_doses
-- Función   : Dosis pendientes o atrasadas de un paciente específico
-- Recibe    : p_patient_id INT
-- Devuelve  : Filas de dosis no aplicadas con días de retraso
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_pending_doses(
    IN    p_patient_id INT,
    INOUT p_results    REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM patients WHERE patient_id = p_patient_id AND is_active = TRUE) THEN
        RAISE EXCEPTION 'Paciente no existe o está inactivo';
    END IF;

    OPEN p_results FOR
        SELECT
            pvs.schedule_id,
            pvs.patient_id,
            pvs.due_date,
            pvs.status                  AS dose_status,
            sd.dose_id,
            sd.dose_label,
            sd.dose_number,
            sd.ideal_age_months,
            v.vaccine_id,
            v.name                      AS vaccine_name,
            v.disease_prevented,
            -- Cita activa vinculada (puede ser NULL)
            ca.appointment_id,
            ca.scheduled_at             AS appointment_date,
            ca.appointment_status,
            -- Días de retraso (0 si no está atrasada)
            CASE
                WHEN pvs.due_date < CURRENT_DATE
                THEN (CURRENT_DATE - pvs.due_date)
                ELSE 0
            END                         AS days_overdue,
            -- Urgencia legible
            CASE
                WHEN pvs.due_date < CURRENT_DATE          THEN 'Atrasada'
                WHEN pvs.due_date <= CURRENT_DATE + 30    THEN 'Próxima'
                ELSE                                           'Futura'
            END                         AS urgency
        FROM   patient_vaccine_schedule pvs
        JOIN   scheme_doses sd ON sd.dose_id   = pvs.scheme_dose_id
        JOIN   vaccines     v  ON v.vaccine_id = sd.vaccine_id
        LEFT JOIN LATERAL (
            SELECT appointment_id, scheduled_at, appointment_status
            FROM   appointments
            WHERE  patient_schedule_id = pvs.schedule_id
              AND  appointment_status NOT IN ('Cancelada','No Show','Completada','Reagendada')
            ORDER  BY scheduled_at DESC
            LIMIT  1
        ) ca ON TRUE
        WHERE  pvs.patient_id = p_patient_id
          AND  pvs.status    <> 'Aplicada'
        ORDER  BY pvs.due_date ASC;
END;
$$;

-- ============================================================
-- [16] sp_dashboard_tutor
-- Función   : Dashboard del portal tutor con KPIs de vacunación y próximas citas de sus hijos
-- Recibe    : p_guardian_id INT
-- Devuelve  : KPIs y filas de hijos con estado vacunal
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_dashboard_tutor(
    IN    p_guardian_id INT,
    INOUT p_results     REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM guardians WHERE guardian_id = p_guardian_id) THEN
        RAISE EXCEPTION 'Tutor no encontrado';
    END IF;

    OPEN p_results FOR
    WITH
    pacientes_tutor AS (
        SELECT DISTINCT pgr.patient_id
        FROM   patient_guardian_relations pgr
        WHERE  pgr.guardian_id = p_guardian_id
    ),
    -- KPIs totales por paciente (incluyendo dosis ya Aplicadas)
    kpi_por_paciente AS (
        SELECT
            pvs2.patient_id,
            SUM(CASE WHEN pvs2.status = 'Aplicada'  THEN 1 ELSE 0 END) AS total_applied,
            COUNT(*)                                                     AS total_doses,
            SUM(CASE WHEN pvs2.status <> 'Aplicada' THEN 1 ELSE 0 END) AS total_pending,
            SUM(CASE WHEN pvs2.status = 'Atrasada'  THEN 1 ELSE 0 END) AS delayed_count,
            CASE
                WHEN COUNT(*) = 0 THEN 0
                ELSE SUM(CASE WHEN pvs2.status = 'Aplicada' THEN 1 ELSE 0 END) * 100 / COUNT(*)
            END                                                          AS pct
        FROM patient_vaccine_schedule pvs2
        GROUP BY pvs2.patient_id
    )
    SELECT
        pvs.schedule_id,
        pvs.patient_id,
        pvs.due_date,
        pvs.status                                               AS dose_status,
        sd.dose_label,
        sd.ideal_age_months,
        v.name                                                   AS vaccine_name,
        v.disease_prevented,
        -- full_name: alias que lee Flask (antes: patient_name)
        TRIM(p.first_name || ' ' || p.last_name)                AS full_name,
        p.birth_date,
        p.photo,
        DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT  AS age_years,
        -- dias_retraso: alias que lee Flask (antes: days_overdue)
        CASE
            WHEN pvs.due_date < CURRENT_DATE
            THEN (CURRENT_DATE - pvs.due_date)
            ELSE NULL
        END                                                      AS dias_retraso,
        -- Cita activa vinculada a esta dosis
        ca.appointment_id,
        -- scheduled_at: alias que lee Flask (antes: cita_fecha)
        ca.scheduled_at,
        -- appointment_status: alias que lee Flask (antes: cita_status)
        ca.appointment_status,
        -- Estado de accion para el frontend
        CASE
            WHEN pvs.status = 'Atrasada' AND ca.appointment_id IS NULL
                THEN 'ATRASADA_SIN_CITA'
            WHEN pvs.status = 'Atrasada' AND ca.appointment_id IS NOT NULL
                THEN 'ATRASADA_CON_CITA'
            WHEN pvs.due_date <= CURRENT_DATE + 30 AND ca.appointment_id IS NULL
                THEN 'PROXIMA_SIN_CITA'
            WHEN pvs.due_date <= CURRENT_DATE + 30 AND ca.appointment_id IS NOT NULL
                THEN 'PROXIMA_CON_CITA'
            ELSE 'FUTURA'
        END                                                      AS action_state,
        -- KPIs del paciente (Flask los leia pero el SP no los devolvía, siempre 0)
        kpi.total_applied,
        kpi.total_doses,
        kpi.total_pending,
        kpi.delayed_count,
        kpi.pct
    FROM   patient_vaccine_schedule pvs
    JOIN   pacientes_tutor          pt  ON pt.patient_id   = pvs.patient_id
    JOIN   patients                 p   ON p.patient_id    = pvs.patient_id
    JOIN   scheme_doses             sd  ON sd.dose_id      = pvs.scheme_dose_id
    JOIN   vaccines                 v   ON v.vaccine_id    = sd.vaccine_id
    LEFT JOIN kpi_por_paciente      kpi ON kpi.patient_id  = pvs.patient_id
    LEFT JOIN LATERAL (
        SELECT appointment_id, scheduled_at, appointment_status
        FROM   appointments
        WHERE  patient_id     = pvs.patient_id
          AND  scheme_dose_id = pvs.scheme_dose_id
          AND  appointment_status NOT IN ('Cancelada', 'No Show', 'Completada', 'Reagendada', 'Pendiente confirmacion')
        ORDER  BY scheduled_at DESC
        LIMIT  1
    ) ca ON TRUE
    WHERE  pvs.status <> 'Aplicada'
      AND  p.is_active = TRUE
    ORDER BY
        CASE pvs.status WHEN 'Atrasada' THEN 0 ELSE 1 END,
        pvs.due_date ASC;
END;
$$;

-- ============================================================
-- [33] sp_dashboard_clinica
-- Función   : Dashboard administrativo con KPIs del día, lista de citas y gráficas semanales
-- Recibe    : p_clinic_id INT, p_results REFCURSOR
-- Devuelve  : conteos y filas de citas del día
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_dashboard_clinica(
    IN    p_clinic_id INT,
    IN    p_fecha     DATE,
    INOUT p_results   REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_fecha DATE := COALESCE(p_fecha, CURRENT_DATE);
BEGIN
    IF NOT EXISTS (SELECT 1 FROM clinics WHERE clinic_id = p_clinic_id AND is_active = TRUE) THEN
        RAISE EXCEPTION 'Clínica no encontrada o inactiva';
    END IF;

    OPEN p_results FOR
        SELECT
            a.appointment_id,
            a.scheduled_at,
            a.appointment_status,
            a.reason,
            a.duration_min,
            a.created_by_role,
            a.appointment_notes,
            a.cancel_reason,
            -- Paciente
            p.patient_id,
            TRIM(p.first_name || ' ' || p.last_name)                    AS patient_name,
            p.birth_date,
            DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT      AS age_years,
            -- Médico asignado
            COALESCE(TRIM(w.first_name || ' ' || w.last_name), 'Sin asignar') AS worker_name,
            -- Vacuna del esquema (si aplica)
            COALESCE(v.name, 'No especificada')                          AS vaccine_name,
            COALESCE(sd.dose_label, '—')                                 AS dose_label,
            -- Área
            COALESCE(ca.name, '—')                                       AS area_name,
            -- Tutor principal
            COALESCE(TRIM(g.first_name || ' ' || g.last_name), 'Sin tutor') AS guardian_name,
            COALESCE(
                (SELECT gp.phone FROM guardian_phones gp
                 WHERE  gp.guardian_id = g.guardian_id
                 ORDER  BY gp.is_primary DESC LIMIT 1),
                '—'
            )                                                             AS guardian_phone
        FROM   appointments a
        JOIN   patients     p  ON p.patient_id   = a.patient_id
        LEFT JOIN workers   w  ON w.worker_id    = a.worker_id
        LEFT JOIN clinic_areas ca ON ca.area_id  = a.area_id
        LEFT JOIN patient_vaccine_schedule pvs ON pvs.schedule_id = a.patient_schedule_id
        LEFT JOIN scheme_doses sd ON sd.dose_id  = pvs.scheme_dose_id
        LEFT JOIN vaccines     v  ON v.vaccine_id = sd.vaccine_id
        LEFT JOIN LATERAL (
            SELECT grd.guardian_id, grd.first_name, grd.last_name
            FROM   patient_guardian_relations pgr
            JOIN   guardians grd ON grd.guardian_id = pgr.guardian_id
            WHERE  pgr.patient_id = a.patient_id
            ORDER  BY pgr.is_primary DESC LIMIT 1
        ) g ON TRUE
        WHERE  a.clinic_id          = p_clinic_id
          AND  a.scheduled_at::DATE = v_fecha
          AND  a.appointment_status NOT IN ('Cancelada','No Show')
        ORDER  BY a.scheduled_at ASC;
END;
$$;

-- ============================================================
-- [75] sp_refresh_overdue_statuses
-- Función   : Actualiza masivamente el status de patient_vaccine_schedule a 'Atrasada' para dosis con due_date pasado
-- Recibe    : p_results REFCURSOR
-- Devuelve  : count de filas actualizadas
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_refresh_overdue_statuses(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_updated INT;
BEGIN
    UPDATE patient_vaccine_schedule
    SET    status     = 'Atrasada',
           updated_at = NOW()
    WHERE  status   = 'Pendiente'
      AND  due_date < CURRENT_DATE;

    GET DIAGNOSTICS v_updated = ROW_COUNT;

    OPEN p_results FOR
        SELECT TRUE      AS success,
               v_updated  AS updated_count,
               NOW()      AS executed_at;
END;
$$;

-- ============================================================
-- [74] sp_generate_alerts
-- Función   : Genera o actualiza alertas de scheme_completion_alerts para dosis atrasadas
-- Recibe    : p_results REFCURSOR
-- Devuelve  : count de alertas generadas
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_generate_alerts(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_inserted INT := 0;
    v_tmp      INT;
BEGIN
    -- Alertas de Atraso
    INSERT INTO scheme_completion_alerts
        (patient_id, schedule_id, alert_type, due_date, status, created_at)
    SELECT pvs.patient_id, pvs.schedule_id, 'Atraso', pvs.due_date, 'Pendiente', NOW()
    FROM   patient_vaccine_schedule pvs
    WHERE  pvs.status = 'Atrasada'
      AND  NOT EXISTS (
               SELECT 1 FROM scheme_completion_alerts sca
               WHERE  sca.schedule_id = pvs.schedule_id
                 AND  sca.alert_type  = 'Atraso'
                 AND  sca.status     <> 'Leida'
           );
    GET DIAGNOSTICS v_tmp = ROW_COUNT;
    v_inserted := v_inserted + v_tmp;

    -- Alertas de Proximidad (próximos 30 días)
    INSERT INTO scheme_completion_alerts
        (patient_id, schedule_id, alert_type, due_date, status, created_at)
    SELECT pvs.patient_id, pvs.schedule_id, 'Proximidad', pvs.due_date, 'Pendiente', NOW()
    FROM   patient_vaccine_schedule pvs
    WHERE  pvs.status  = 'Pendiente'
      AND  pvs.due_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 30
      AND  NOT EXISTS (
               SELECT 1 FROM scheme_completion_alerts sca
               WHERE  sca.schedule_id = pvs.schedule_id
                 AND  sca.alert_type  = 'Proximidad'
                 AND  sca.status     <> 'Leida'
           );
    GET DIAGNOSTICS v_tmp = ROW_COUNT;
    v_inserted := v_inserted + v_tmp;

    OPEN p_results FOR
        SELECT TRUE        AS success,
               v_inserted   AS alerts_generated,
               NOW()        AS executed_at;
END;
$$;

-- ============================================================
-- [34] sp_get_citas_admin
-- Función   : Lista de citas filtrable para vista administrativa
-- Recibe    : filtros opcionales (fecha, estado, clínica)
-- Devuelve  : Filas de citas con datos de paciente y trabajador
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_citas_admin(
    IN    p_clinic_id  INT,
    IN    p_date_from  DATE,
    IN    p_date_to    DATE,
    INOUT p_results    REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    -- Validar solo si se proporciona un clinic_id especifico
    IF p_clinic_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM clinics WHERE clinic_id = p_clinic_id AND is_active = TRUE
    ) THEN
        RAISE EXCEPTION 'Clinica no encontrada o inactiva (id=%)', p_clinic_id;
    END IF;

    OPEN p_results FOR
    SELECT
        af.appointment_id,
        af.patient_id,
        af.worker_id,
        af.area_id,
        af.patient_schedule_id,
        af.scheduled_at,
        af.duration_min,
        af.reason,
        af.appointment_status,
        af.appointment_notes,
        af.cancel_reason,
        af.created_by_role,
        af.rescheduled_from_id,
        af.patient_name,
        af.worker_name,
        af.clinic_name,
        af.area_name,
        af.vaccine_name,
        af.dose_label,
        af.dose_due_date,
        af.dose_status,
        -- Tutor principal del paciente
        COALESCE(TRIM(g.first_name || ' ' || g.last_name), 'Sin tutor') AS guardian_name,
        COALESCE(
            (SELECT gp.phone
             FROM   guardian_phones gp
             WHERE  gp.guardian_id = g.guardian_id
             ORDER  BY gp.is_primary DESC LIMIT 1),
            '—'
        ) AS guardian_phone
    FROM   v_appointments_full af
    LEFT JOIN LATERAL (
        SELECT grd.guardian_id, grd.first_name, grd.last_name
        FROM   patient_guardian_relations pgr
        JOIN   guardians grd ON grd.guardian_id = pgr.guardian_id
        WHERE  pgr.patient_id = af.patient_id
        ORDER  BY pgr.is_primary DESC LIMIT 1
    ) g ON TRUE
    WHERE  (p_clinic_id IS NULL OR af.clinic_id = p_clinic_id)
      AND  af.scheduled_at::DATE BETWEEN COALESCE(p_date_from, CURRENT_DATE)
                                     AND COALESCE(p_date_to,   CURRENT_DATE + 30)
    ORDER  BY af.scheduled_at ASC;
END;
$$;

-- ============================================================
-- [32] sp_get_agenda_form_data
-- Función   : Datos necesarios para renderizar el formulario de nueva cita (clínicas, trabajadores, áreas, horarios)
-- Recibe    : p_clinic_id INT opcional
-- Devuelve  : catálogos necesarios para el formulario
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_agenda_form_data(
    IN    p_clinic_id    INT,
    INOUT p_patients_cur REFCURSOR,
    INOUT p_workers_cur  REFCURSOR,
    INOUT p_areas_cur    REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    -- Pacientes activos (ligero: solo id + nombre)
    OPEN p_patients_cur FOR
        SELECT patient_id,
               TRIM(first_name || ' ' || last_name) AS full_name
        FROM   patients
        WHERE  is_active = TRUE
        ORDER  BY last_name, first_name;

    -- Trabajadores con rol Medico o Enfermero con horario en esta clinica
    -- Solo estos roles pueden ser asignados a citas de vacunacion
    -- ORDER BY debe usar columnas del SELECT cuando hay DISTINCT
    OPEN p_workers_cur FOR
        SELECT DISTINCT
               w.worker_id,
               TRIM(w.first_name || ' ' || w.last_name) AS full_name,
               r.name                                    AS role_name
        FROM   workers w
        JOIN   roles r ON r.role_id = w.role_id
        JOIN   worker_schedules ws
               ON  ws.worker_id = w.worker_id
               AND ws.clinic_id = p_clinic_id
        WHERE  r.name IN ('Medico', 'Enfermero')
        ORDER  BY full_name;

    -- Areas de la clinica
    OPEN p_areas_cur FOR
        SELECT area_id,
               name,
               capacity
        FROM   clinic_areas
        WHERE  clinic_id = p_clinic_id
        ORDER  BY name;
END;
$$;

-- ============================================================
-- [31] sp_get_appointment_detail
-- Función   : Detalle completo de una sola cita con datos de paciente, vacuna y trabajador
-- Recibe    : p_appointment_id INT
-- Devuelve  : Una fila enriquecida de v_appointments_full
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_appointment_detail(
    IN    p_appointment_id INT,
    INOUT p_result         REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM appointments WHERE appointment_id = p_appointment_id
    ) THEN
        RAISE EXCEPTION 'Cita no encontrada (id=%)', p_appointment_id;
    END IF;

    OPEN p_result FOR
    SELECT
        af.appointment_id,
        af.patient_id,
        af.patient_name,
        af.clinic_id,
        af.clinic_name,
        af.worker_id,
        af.worker_name,
        af.area_id,
        af.area_name,
        af.patient_schedule_id,
        af.scheduled_at,
        af.duration_min,
        af.reason,
        af.appointment_status,
        af.appointment_notes,
        af.vaccine_name,
        af.dose_label
    FROM v_appointments_full af
    WHERE af.appointment_id = p_appointment_id;
END;
$$;

-- ============================================================
-- [30] sp_update_appointment
-- Función   : Actualiza campos editables de una cita existente (trabajador, área, notas)
-- Recibe    : p_appointment_id y campos opcionales
-- Devuelve  : success, message
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_update_appointment(
    IN    p_appointment_id  INT,
    IN    p_worker_id       INT,
    IN    p_area_id         INT,
    IN    p_scheduled_at    TIMESTAMP,
    IN    p_reason          TEXT,
    IN    p_notes           TEXT,
    IN    p_status          VARCHAR(30),
    IN    p_duration_min    SMALLINT,
    INOUT p_result          REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_clinic_id INT;
BEGIN
    -- Verificar que la cita existe y obtener su clinica
    SELECT clinic_id INTO v_clinic_id
    FROM   appointments
    WHERE  appointment_id = p_appointment_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cita no encontrada (id=%)', p_appointment_id;
    END IF;

    -- Verificar solapamiento del trabajador (excluye la cita que se esta editando)
    IF p_worker_id IS NOT NULL AND p_scheduled_at IS NOT NULL THEN
        IF EXISTS (
            SELECT 1 FROM appointments a
            WHERE  a.worker_id           = p_worker_id
              AND  a.appointment_id     <> p_appointment_id
              AND  a.appointment_status NOT IN ('Cancelada', 'No Show', 'Reagendada')
              AND  a.scheduled_at < p_scheduled_at + (COALESCE(p_duration_min, 20) * INTERVAL '1 minute')
              AND  a.scheduled_at + (a.duration_min * INTERVAL '1 minute') > p_scheduled_at
        ) THEN
            RAISE EXCEPTION 'El trabajador ya tiene una cita que se solapa en ese horario';
        END IF;
    END IF;

    -- Actualizar solo los campos editables
    -- area_id puede ser NULL (sin area), por eso no usa COALESCE
    UPDATE appointments SET
        worker_id          = COALESCE(p_worker_id,    worker_id),
        area_id            = p_area_id,
        scheduled_at       = COALESCE(p_scheduled_at, scheduled_at),
        reason             = COALESCE(p_reason,       reason),
        appointment_notes  = p_notes,
        appointment_status = COALESCE(p_status,       appointment_status),
        duration_min       = COALESCE(p_duration_min, duration_min)
    WHERE appointment_id = p_appointment_id;

    OPEN p_result FOR
        SELECT TRUE             AS success,
               p_appointment_id AS appointment_id,
               'Cita actualizada correctamente' AS message;

EXCEPTION WHEN OTHERS THEN
    OPEN p_result FOR
        SELECT FALSE AS success,
               SQLERRM AS message,
               NULL::INT AS appointment_id;
END;
$$;

-- ============================================================
-- [72] sp_dashboard_charts
-- Función   : Datos para gráficas del dashboard (vacunaciones por semana, por vacuna, cobertura)
-- Recibe    : p_clinic_id INT opcional, p_results REFCURSOR
-- Devuelve  : series de datos para Highcharts
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_dashboard_charts(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
    WITH coverage_by_age AS (
        SELECT
            CASE
                WHEN DATE_PART('year', AGE(p.birth_date)) < 1  THEN '< 1 a' || chr(241) || 'o'
                WHEN DATE_PART('year', AGE(p.birth_date)) < 3  THEN '1-2 a' || chr(241) || 'os'
                WHEN DATE_PART('year', AGE(p.birth_date)) < 6  THEN '3-5 a' || chr(241) || 'os'
                WHEN DATE_PART('year', AGE(p.birth_date)) < 12 THEN '6-11 a' || chr(241) || 'os'
                ELSE '12+ a' || chr(241) || 'os'
            END AS label,
            COUNT(vr.record_id)::NUMERIC AS value,
            MIN(DATE_PART('year', AGE(p.birth_date))) AS row_order,
            1 AS chart_order
        FROM vaccination_records vr
        JOIN patients p ON vr.patient_id = p.patient_id
        WHERE p.is_active = TRUE
        GROUP BY label
    ),
    monthly_doses AS (
        SELECT
            TO_CHAR(DATE_TRUNC('month', applied_date), 'Mon YY') AS label,
            COUNT(*)::NUMERIC AS value,
            EXTRACT(EPOCH FROM DATE_TRUNC('month', applied_date)) AS row_order,
            2 AS chart_order
        FROM vaccination_records
        WHERE applied_date >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '11 months'
        GROUP BY DATE_TRUNC('month', applied_date)
    ),
    delay_all AS (
        SELECT
            v.name AS label,
            ROUND(
                COUNT(DISTINCT CASE
                    WHEN (p.birth_date + (sd.ideal_age_months || ' months')::INTERVAL)::DATE < CURRENT_DATE
                         AND NOT EXISTS (
                             SELECT 1 FROM vaccination_records vr2
                             WHERE vr2.patient_id    = p.patient_id
                               AND vr2.scheme_dose_id = sd.dose_id
                         )
                    THEN p.patient_id
                END)::NUMERIC /
                NULLIF(COUNT(DISTINCT p.patient_id)::NUMERIC, 0) * 100
            , 1) AS value
        FROM patients p
        CROSS JOIN scheme_doses sd
        JOIN vaccines v ON sd.vaccine_id = v.vaccine_id
        WHERE p.is_active = TRUE
        GROUP BY v.name
    ),
    delay_top5 AS (
        SELECT label, value,
               ROW_NUMBER() OVER (ORDER BY value DESC) AS row_order,
               3 AS chart_order
        FROM delay_all
        ORDER BY value DESC
        LIMIT 5
    )
    SELECT chart_order, row_order, 'coverage'::TEXT AS chart, label, value
    FROM coverage_by_age
    UNION ALL
    SELECT chart_order, row_order, 'monthly'::TEXT, label, value
    FROM monthly_doses
    UNION ALL
    SELECT chart_order, row_order, 'delay'::TEXT, label, value
    FROM delay_top5
    ORDER BY chart_order, row_order;

END;
$$;


-- ============================================================
-- MÓDULO: FLUJO CLÍNICO NFC
-- Estos SPs manejan la presencia física del paciente dentro
-- de la clínica a través de escaneos de tarjeta NFC.
-- ============================================================

-- ============================================================
-- [44] sp_nfc_checkin
-- Función   : Registra el check-in de un paciente por escaneo NFC en recepción
-- Recibe    : p_nfc_uid VARCHAR, p_clinic_id INT, p_worker_id INT
-- Devuelve  : success, visit_id, patient_id, patient_name, message
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_nfc_checkin(
    IN    p_nfc_uid    VARCHAR(30),
    IN    p_worker_id  INT,
    IN    p_device_id  VARCHAR(30),
    IN    p_clinic_id  INT,
    INOUT p_result     REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_card_id         INT;
    v_patient_id      INT;
    v_card_status     VARCHAR(20);
    v_existing_visit  INT;
    v_visit_id        INT;
    v_scan_id         INT;
    v_area_id         INT;
    v_appointment_id  INT;
BEGIN
    -- 1. Validar que el NFC existe y está activo
    SELECT nc.nfc_card_id, nc.patient_id, nc.status
    INTO   v_card_id, v_patient_id, v_card_status
    FROM   nfc_cards nc
    WHERE  nc.uid = p_nfc_uid;

    IF NOT FOUND THEN
        OPEN p_result FOR
            SELECT FALSE AS success, 'NFC no registrado en el sistema' AS message,
                   NULL::INT AS visit_id, NULL::INT AS patient_id,
                   NULL::TEXT AS full_name, NULL::TEXT AS visit_status;
        RETURN;
    END IF;

    IF v_card_status <> 'Activa' THEN
        OPEN p_result FOR
            SELECT FALSE AS success,
                   FORMAT('Tarjeta con estado "%s" — no se puede usar', v_card_status) AS message,
                   NULL::INT AS visit_id, v_patient_id,
                   NULL::TEXT AS full_name, NULL::TEXT AS visit_status;
        RETURN;
    END IF;

    -- 2. Verificar que no hay visita activa previa para este paciente
    SELECT visit_id INTO v_existing_visit
    FROM   patient_clinic_visits
    WHERE  patient_id   = v_patient_id
      AND  visit_status NOT IN ('Finalizado','Abandono','Cancelado')
    LIMIT 1;

    IF FOUND THEN
        OPEN p_result FOR
            SELECT FALSE AS success,
                   'El paciente ya tiene una visita activa en curso' AS message,
                   v_existing_visit AS visit_id, v_patient_id,
                   NULL::TEXT AS full_name, NULL::TEXT AS visit_status;
        RETURN;
    END IF;

    -- 3. Obtener área de recepción de la clínica
    SELECT ca.area_id INTO v_area_id
    FROM   clinic_areas ca
    JOIN   clinic_area_types cat ON cat.area_type_id = ca.area_type_id
    WHERE  ca.clinic_id = p_clinic_id
      AND  UPPER(cat.code) = 'RECEPTION'
    LIMIT 1;

    -- 4. Registrar el evento de escaneo NFC
    INSERT INTO nfc_scan_events (
        nfc_card_id, scanned_by, clinic_id, area_id,
        scanned_at, action_triggered, device_id,
        scan_context, resolved_action
    )
    VALUES (
        v_card_id, p_worker_id, p_clinic_id, v_area_id,
        NOW(), 'CHECKIN', p_device_id,
        'checkin', 'pending'
    )
    RETURNING scan_event_id INTO v_scan_id;

    -- 5. Buscar cita activa del paciente para hoy en esta clínica
    SELECT appointment_id INTO v_appointment_id
    FROM   appointments
    WHERE  patient_id          = v_patient_id
      AND  clinic_id           = p_clinic_id
      AND  DATE(scheduled_at)  = CURRENT_DATE
      AND  appointment_status  IN ('Programada','Confirmada')
    ORDER  BY scheduled_at
    LIMIT  1;

    -- 6. Crear la visita clínica (directamente en sala de espera)
    INSERT INTO patient_clinic_visits (
        patient_id, clinic_id, appointment_id,
        visit_status, current_area_id,
        waiting_since,
        checkin_by_worker_id, checkin_nfc_scan_id,
        visit_type, checked_in_at, created_at, updated_at
    )
    VALUES (
        v_patient_id, p_clinic_id, v_appointment_id,
        'En espera', v_area_id,
        NOW(),
        p_worker_id, v_scan_id,
        CASE WHEN v_appointment_id IS NOT NULL THEN 'Programada' ELSE 'Espontanea' END,
        NOW(), NOW(), NOW()
    )
    RETURNING visit_id INTO v_visit_id;

    -- 7. Registrar el primer movimiento (entrada directa a sala de espera)
    INSERT INTO visit_area_movements (
        visit_id, from_area_id, to_area_id,
        from_status, to_status,
        moved_at, moved_by, nfc_scan_id, movement_notes
    )
    VALUES (
        v_visit_id, NULL, v_area_id,
        NULL, 'En espera',
        NOW(), p_worker_id, v_scan_id, 'Check-in — ingresa a sala de espera'
    );

    -- 8. Actualizar scan event con el visit_id creado
    UPDATE nfc_scan_events
    SET    visit_id        = v_visit_id,
           resolved_action = 'visit_created'
    WHERE  scan_event_id   = v_scan_id;

    -- 9. Actualizar last_scanned_at de la tarjeta
    UPDATE nfc_cards
    SET    last_scanned_at = NOW()
    WHERE  nfc_card_id     = v_card_id;

    -- 10. Auditoría
    INSERT INTO audit_log (table_name, record_id, action, changed_data, worker_id, changed_at)
    VALUES (
        'patient_clinic_visits', v_visit_id, 'INSERT',
        jsonb_build_object(
            'action',     'checkin',
            'patient_id', v_patient_id,
            'worker_id',  p_worker_id,
            'clinic_id',  p_clinic_id,
            'visit_type', CASE WHEN v_appointment_id IS NOT NULL THEN 'Programada' ELSE 'Espontanea' END
        ),
        p_worker_id, NOW()
    );

    -- 11. Resultado con datos completos del paciente para la UI
    OPEN p_result FOR
        SELECT
            TRUE  AS success,
            'Check-in realizado correctamente' AS message,
            v_visit_id          AS visit_id,
            v_scan_id           AS scan_id,
            p.patient_id,
            TRIM(p.first_name || ' ' || p.last_name)                    AS full_name,
            p.birth_date,
            DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT     AS age,
            p.gender,
            p.photo,
            COALESCE(bt.blood_type, '—')                                AS blood_type,
            p.premature,
            v_appointment_id                                             AS appointment_id,
            COALESCE(
                (SELECT STRING_AGG(al.name || ' (' || COALESCE(pa.severity,'?') || ')', ' | ')
                 FROM   patient_allergies pa
                 JOIN   allergies al ON al.allergy_id = pa.allergy_id
                 WHERE  pa.patient_id = p.patient_id),
                'Sin alergias'
            )                                                            AS allergies,
            (SELECT COUNT(*) FROM patient_vaccine_schedule pvs
             WHERE pvs.patient_id = p.patient_id AND pvs.status = 'Pendiente')::INT AS pending_doses,
            (SELECT COUNT(*) FROM patient_vaccine_schedule pvs
             WHERE pvs.patient_id = p.patient_id AND pvs.status = 'Atrasada')::INT  AS overdue_doses,
            'En espera'::TEXT                                            AS visit_status
        FROM   patients p
        LEFT JOIN blood_types bt ON bt.blood_type_id = p.blood_type_id
        WHERE  p.patient_id = v_patient_id;

EXCEPTION WHEN unique_violation THEN
    OPEN p_result FOR
        SELECT FALSE AS success,
               'El paciente ya tiene una visita activa (violación de unicidad)' AS message,
               NULL::INT AS visit_id, v_patient_id,
               NULL::TEXT AS full_name, NULL::TEXT AS visit_status;
WHEN OTHERS THEN
    OPEN p_result FOR
        SELECT FALSE AS success, SQLERRM AS message,
               NULL::INT AS visit_id, NULL::INT AS patient_id,
               NULL::TEXT AS full_name, NULL::TEXT AS visit_status;
END;
$$;

-- ============================================================
-- [45] sp_visit_transition
-- Función   : Avanza el estado clínico de una visita (En espera → En consulta → En vacunación → Finalizado)
-- Recibe    : p_visit_id INT, p_new_status VARCHAR, p_worker_id INT
-- Devuelve  : success, visit_id, new_status, message
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_visit_transition(
    IN    p_visit_id    INT,
    IN    p_new_status  visit_status,
    IN    p_new_area_id INT,
    IN    p_worker_id   INT,
    IN    p_scan_id     INT,
    IN    p_notes       TEXT,
    INOUT p_result      REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_current_status  visit_status;
    v_current_area    INT;
    v_patient_id      INT;
    v_allowed         BOOLEAN := FALSE;
BEGIN
    -- Obtener estado actual con lock para evitar concurrencia
    SELECT visit_status, current_area_id, patient_id
    INTO   v_current_status, v_current_area, v_patient_id
    FROM   patient_clinic_visits
    WHERE  visit_id = p_visit_id
    FOR UPDATE;

    IF NOT FOUND THEN
        OPEN p_result FOR
            SELECT FALSE AS success, 'Visita no encontrada' AS message,
                   NULL::INT AS visit_id, NULL::INT AS patient_id;
        RETURN;
    END IF;

    -- Validar que la visita no esté ya cerrada
    IF v_current_status IN ('Finalizado','Abandono','Cancelado') THEN
        OPEN p_result FOR
            SELECT FALSE AS success,
                   FORMAT('La visita ya está cerrada con estado: %s', v_current_status) AS message,
                   p_visit_id AS visit_id, v_patient_id;
        RETURN;
    END IF;

    -- Validar transición permitida
    v_allowed := (
        (v_current_status = 'En recepcion'   AND p_new_status = 'En espera')     OR
        (v_current_status = 'En espera'      AND p_new_status = 'En consulta')   OR
        (v_current_status = 'En espera'      AND p_new_status = 'Finalizado')    OR
        (v_current_status = 'En consulta'    AND p_new_status = 'En vacunacion') OR
        (v_current_status = 'En consulta'    AND p_new_status = 'Finalizado')    OR
        (v_current_status = 'En vacunacion'  AND p_new_status = 'Finalizado')    OR
        -- Salidas de emergencia desde cualquier estado activo
        (v_current_status NOT IN ('Finalizado','Abandono','Cancelado')
                                             AND p_new_status IN ('Abandono','Cancelado'))
    );

    IF NOT v_allowed THEN
        OPEN p_result FOR
            SELECT FALSE AS success,
                   FORMAT('Transición no permitida: %s → %s', v_current_status, p_new_status) AS message,
                   p_visit_id AS visit_id, v_patient_id;
        RETURN;
    END IF;

    -- Registrar el movimiento en el historial
    INSERT INTO visit_area_movements (
        visit_id, from_area_id, to_area_id,
        from_status, to_status,
        moved_at, moved_by, nfc_scan_id, movement_notes
    )
    VALUES (
        p_visit_id, v_current_area, COALESCE(p_new_area_id, v_current_area),
        v_current_status, p_new_status,
        NOW(), p_worker_id, p_scan_id, p_notes
    );

    -- Actualizar la visita con timestamps específicos por estado
    UPDATE patient_clinic_visits SET
        visit_status        = p_new_status,
        current_area_id     = COALESCE(p_new_area_id, current_area_id),
        assigned_worker_id  = p_worker_id,
        updated_at          = NOW(),
        waiting_since       = CASE WHEN p_new_status = 'En espera'
                                   THEN NOW() ELSE waiting_since END,
        consultation_start  = CASE WHEN p_new_status = 'En consulta'
                                   THEN NOW() ELSE consultation_start END,
        vaccination_start   = CASE WHEN p_new_status = 'En vacunacion'
                                   THEN NOW() ELSE vaccination_start END
    WHERE visit_id = p_visit_id;

    -- Auditoría del cambio de estado
    INSERT INTO audit_log (table_name, record_id, action, changed_data, worker_id, changed_at)
    VALUES (
        'patient_clinic_visits', p_visit_id, 'UPDATE',
        jsonb_build_object(
            'from_status', v_current_status,
            'to_status',   p_new_status,
            'worker_id',   p_worker_id
        ),
        p_worker_id, NOW()
    );

    OPEN p_result FOR
        SELECT TRUE AS success,
               FORMAT('Estado actualizado: %s → %s', v_current_status, p_new_status) AS message,
               p_visit_id   AS visit_id,
               v_patient_id AS patient_id,
               p_new_status::TEXT AS new_status;

EXCEPTION WHEN OTHERS THEN
    OPEN p_result FOR
        SELECT FALSE AS success, SQLERRM AS message,
               p_visit_id AS visit_id, NULL::INT AS patient_id,
               NULL::TEXT AS new_status;
END;
$$;

-- ============================================================
-- [46] sp_nfc_medical_scan
-- Función   : Escaneo NFC en área médica que abre el expediente del paciente en visita activa
-- Recibe    : p_nfc_uid VARCHAR, p_clinic_id INT, p_worker_id INT
-- Devuelve  : success, patient_id y datos de la visita activa
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_nfc_medical_scan(
    IN    p_nfc_uid    VARCHAR(30),
    IN    p_worker_id  INT,
    IN    p_device_id  VARCHAR(30),
    IN    p_clinic_id  INT,
    INOUT p_result     REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_card_id        INT;
    v_patient_id     INT;
    v_visit_id       INT;
    v_visit_status   visit_status;
    v_scan_id        INT;
    v_action         TEXT;
BEGIN
    -- Validar tarjeta activa
    SELECT nfc_card_id, patient_id
    INTO   v_card_id, v_patient_id
    FROM   nfc_cards
    WHERE  uid = p_nfc_uid AND status = 'Activa';

    IF NOT FOUND THEN
        OPEN p_result FOR
            SELECT FALSE AS success, 'NFC no válido o inactivo' AS message,
                   NULL::INT AS visit_id, NULL::INT AS patient_id, NULL::TEXT AS full_name;
        RETURN;
    END IF;

    -- Buscar visita activa del paciente (con lock si hay visita)
    SELECT visit_id, visit_status
    INTO   v_visit_id, v_visit_status
    FROM   patient_clinic_visits
    WHERE  patient_id   = v_patient_id
      AND  visit_status NOT IN ('Finalizado','Abandono','Cancelado')
    LIMIT 1;

    -- Si el paciente está En espera, transicionar a En consulta automáticamente
    IF v_visit_id IS NOT NULL AND v_visit_status = 'En espera' THEN
        UPDATE patient_clinic_visits SET
            visit_status       = 'En consulta',
            consultation_start = NOW(),
            assigned_worker_id = p_worker_id,
            updated_at         = NOW()
        WHERE visit_id = v_visit_id;

        INSERT INTO visit_area_movements (
            visit_id, from_status, to_status,
            moved_at, moved_by, movement_notes
        )
        VALUES (
            v_visit_id, 'En espera', 'En consulta',
            NOW(), p_worker_id, 'NFC médico — inicia consulta'
        );

        INSERT INTO audit_log (table_name, record_id, action, changed_data, worker_id, changed_at)
        VALUES (
            'patient_clinic_visits', v_visit_id, 'UPDATE',
            jsonb_build_object('from_status','En espera','to_status','En consulta','worker_id',p_worker_id),
            p_worker_id, NOW()
        );

        v_action := 'consulta_started';
    ELSE
        v_action := CASE WHEN v_visit_id IS NOT NULL THEN 'expedient_opened' ELSE 'no_active_visit' END;
    END IF;

    -- Registrar el scan
    INSERT INTO nfc_scan_events (
        nfc_card_id, scanned_by, clinic_id,
        scanned_at, action_triggered, device_id,
        scan_context, visit_id, resolved_action
    )
    VALUES (
        v_card_id, p_worker_id, p_clinic_id,
        NOW(), 'MEDICAL_OPEN', p_device_id,
        'medical_open', v_visit_id, v_action
    )
    RETURNING scan_event_id INTO v_scan_id;

    UPDATE nfc_cards SET last_scanned_at = NOW() WHERE nfc_card_id = v_card_id;

    -- Devolver expediente completo del paciente
    OPEN p_result FOR
        SELECT
            TRUE AS success,
            'Expediente abierto' AS message,
            v_visit_id AS visit_id,
            v_scan_id  AS scan_id,
            p.patient_id,
            TRIM(p.first_name || ' ' || p.last_name)                    AS full_name,
            p.birth_date,
            DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT     AS age,
            p.gender,
            p.weight_kg,
            p.photo,
            COALESCE(bt.blood_type, '—')                                AS blood_type,
            p.premature,
            pcv.visit_status::TEXT,
            pcv.checked_in_at,
            pcv.waiting_since,
            pcv.appointment_id,
            a.scheduled_at,
            a.reason AS appointment_reason,
            -- Alergias con severidad
            COALESCE(
                (SELECT STRING_AGG(al.name || ' (' || COALESCE(pa.severity,'?') || ')', ' | ')
                 FROM   patient_allergies pa
                 JOIN   allergies al ON al.allergy_id = pa.allergy_id
                 WHERE  pa.patient_id = p.patient_id),
                'Sin alergias registradas'
            ) AS allergies,
            -- Conteos de esquema
            (SELECT COUNT(*) FROM patient_vaccine_schedule pvs
             WHERE pvs.patient_id = p.patient_id AND pvs.status = 'Pendiente')::INT AS pending_doses,
            (SELECT COUNT(*) FROM patient_vaccine_schedule pvs
             WHERE pvs.patient_id = p.patient_id AND pvs.status = 'Atrasada')::INT  AS overdue_doses,
            -- Última vacuna aplicada
            (SELECT MAX(vr.applied_date) FROM vaccination_records vr
             WHERE vr.patient_id = p.patient_id)                        AS last_vaccine_date
        FROM   patients p
        LEFT   JOIN blood_types bt ON bt.blood_type_id = p.blood_type_id
        LEFT   JOIN patient_clinic_visits pcv ON pcv.visit_id = v_visit_id
        LEFT   JOIN appointments a ON a.appointment_id = pcv.appointment_id
        WHERE  p.patient_id = v_patient_id;

EXCEPTION WHEN OTHERS THEN
    OPEN p_result FOR
        SELECT FALSE AS success, SQLERRM AS message,
               NULL::INT AS visit_id, NULL::INT AS patient_id, NULL::TEXT AS full_name;
END;
$$;

-- ============================================================
-- [47] sp_nfc_checkout
-- Función   : Registra el checkout del paciente por escaneo NFC cerrando la visita como Finalizado
-- Recibe    : p_nfc_uid VARCHAR, p_clinic_id INT, p_worker_id INT
-- Devuelve  : success, visit_id, message
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_nfc_checkout(
    IN    p_nfc_uid    VARCHAR(30),
    IN    p_worker_id  INT,
    IN    p_device_id  VARCHAR(30),
    IN    p_clinic_id  INT,
    INOUT p_result     REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_card_id      INT;
    v_patient_id   INT;
    v_visit_id     INT;
    v_scan_id      INT;
    v_checkin_at   TIMESTAMP;
    v_duration_min INT;
    v_cur_status   visit_status;
BEGIN
    -- Validar tarjeta
    SELECT nfc_card_id, patient_id
    INTO   v_card_id, v_patient_id
    FROM   nfc_cards
    WHERE  uid = p_nfc_uid AND status = 'Activa';

    IF NOT FOUND THEN
        OPEN p_result FOR
            SELECT FALSE AS success, 'NFC no válido o inactivo' AS message,
                   NULL::INT AS visit_id, NULL::INT AS duration_minutes;
        RETURN;
    END IF;

    -- Buscar visita activa con lock
    SELECT visit_id, checked_in_at, visit_status
    INTO   v_visit_id, v_checkin_at, v_cur_status
    FROM   patient_clinic_visits
    WHERE  patient_id   = v_patient_id
      AND  visit_status NOT IN ('Finalizado','Abandono','Cancelado')
    FOR UPDATE
    LIMIT 1;

    IF NOT FOUND THEN
        OPEN p_result FOR
            SELECT FALSE AS success,
                   'No hay visita activa para este paciente' AS message,
                   NULL::INT AS visit_id, NULL::INT AS duration_minutes;
        RETURN;
    END IF;

    v_duration_min := ROUND(EXTRACT(EPOCH FROM (NOW() - v_checkin_at)) / 60)::INT;

    -- Registrar scan de salida
    INSERT INTO nfc_scan_events (
        nfc_card_id, scanned_by, clinic_id,
        scanned_at, action_triggered, device_id,
        scan_context, visit_id, resolved_action
    )
    VALUES (
        v_card_id, p_worker_id, p_clinic_id,
        NOW(), 'CHECKOUT', p_device_id,
        'checkout', v_visit_id, 'visit_closed'
    )
    RETURNING scan_event_id INTO v_scan_id;

    -- Registrar movimiento de salida
    INSERT INTO visit_area_movements (
        visit_id, from_status, to_status,
        moved_at, moved_by, nfc_scan_id, movement_notes
    )
    SELECT visit_id, visit_status, 'Finalizado',
           NOW(), p_worker_id, v_scan_id, 'Check-out NFC'
    FROM   patient_clinic_visits
    WHERE  visit_id = v_visit_id;

    -- Cerrar la visita
    UPDATE patient_clinic_visits SET
        visit_status          = 'Finalizado',
        checked_out_at        = NOW(),
        checkout_by_worker_id = p_worker_id,
        checkout_nfc_scan_id  = v_scan_id,
        updated_at            = NOW()
    WHERE visit_id = v_visit_id;

    UPDATE nfc_cards SET last_scanned_at = NOW() WHERE nfc_card_id = v_card_id;

    -- Auditoría
    INSERT INTO audit_log (table_name, record_id, action, changed_data, worker_id, changed_at)
    VALUES (
        'patient_clinic_visits', v_visit_id, 'UPDATE',
        jsonb_build_object(
            'action',           'checkout',
            'duration_minutes', v_duration_min,
            'patient_id',       v_patient_id,
            'from_status',      v_cur_status
        ),
        p_worker_id, NOW()
    );

    OPEN p_result FOR
        SELECT
            TRUE            AS success,
            'Check-out registrado correctamente' AS message,
            v_visit_id      AS visit_id,
            v_patient_id    AS patient_id,
            v_duration_min  AS duration_minutes,
            v_checkin_at    AS checkin_at,
            NOW()           AS checkout_at;

EXCEPTION WHEN OTHERS THEN
    OPEN p_result FOR
        SELECT FALSE AS success, SQLERRM AS message,
               NULL::INT AS visit_id, NULL::INT AS duration_minutes;
END;
$$;

-- ============================================================
-- [48] sp_reception_realtime
-- Función   : Estado en tiempo real de la sala de espera para el monitor de recepción
-- Recibe    : p_clinic_id INT
-- Devuelve  : Filas de visitas activas con estado, paciente y tiempos
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_reception_realtime(
    IN    p_clinic_id  INT,
    INOUT p_result     REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_result FOR
        SELECT
            pcv.visit_id,
            pcv.visit_status::TEXT,
            pcv.visit_type,
            pcv.checked_in_at,
            pcv.waiting_since,
            pcv.consultation_start,
            pcv.vaccination_start,
            ROUND(EXTRACT(EPOCH FROM (NOW() - pcv.checked_in_at)) / 60)::INT AS minutes_in_clinic,
            CASE
                WHEN pcv.waiting_since IS NOT NULL
                THEN ROUND(EXTRACT(EPOCH FROM (NOW() - pcv.waiting_since)) / 60)::INT
                ELSE NULL
            END                                                              AS minutes_waiting,
            p.patient_id,
            TRIM(p.first_name || ' ' || p.last_name)                        AS full_name,
            DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT         AS age,
            p.photo,
            COALESCE(ca.name, 'Sin área')                                   AS current_area,
            COALESCE(TRIM(w.first_name || ' ' || w.last_name), 'Sin asignar') AS assigned_worker,
            pcv.appointment_id,
            a.scheduled_at,
            a.appointment_status,
            -- Alertas clínicas
            (SELECT COUNT(*) FROM patient_vaccine_schedule pvs
             WHERE pvs.patient_id = p.patient_id AND pvs.status = 'Atrasada') > 0 AS has_overdue_vaccines,
            EXISTS(SELECT 1 FROM patient_allergies WHERE patient_id = p.patient_id) AS has_allergies,
            -- Color de estado para la UI
            CASE pcv.visit_status
                WHEN 'En recepcion'  THEN '#3B82F6'
                WHEN 'En espera'     THEN '#F59E0B'
                WHEN 'En consulta'   THEN '#8B5CF6'
                WHEN 'En vacunacion' THEN '#10B981'
                ELSE                      '#6B7280'
            END                                                              AS status_color,
            -- Alerta si lleva más de 30 minutos esperando
            CASE
                WHEN pcv.waiting_since IS NOT NULL
                 AND EXTRACT(EPOCH FROM (NOW() - pcv.waiting_since)) / 60 > 30
                THEN TRUE
                ELSE FALSE
            END                                                              AS wait_time_alert
        FROM   patient_clinic_visits pcv
        JOIN   patients p    ON p.patient_id    = pcv.patient_id
        LEFT   JOIN clinic_areas ca ON ca.area_id = pcv.current_area_id
        LEFT   JOIN workers w       ON w.worker_id = pcv.assigned_worker_id
        LEFT   JOIN appointments a  ON a.appointment_id = pcv.appointment_id
        WHERE  pcv.clinic_id    = p_clinic_id
          AND  pcv.visit_status NOT IN ('Finalizado','Abandono','Cancelado')
        ORDER  BY
            CASE pcv.visit_status
                WHEN 'En vacunacion' THEN 1
                WHEN 'En consulta'   THEN 2
                WHEN 'En espera'     THEN 3
                WHEN 'En recepcion'  THEN 4
            END,
            pcv.waiting_since NULLS LAST,
            pcv.checked_in_at;
END;
$$;

-- ============================================================
-- [49] sp_visit_patient_summary
-- Función   : Resumen clínico del paciente en visita activa (historial, alergias, dosis pendientes)
-- Recibe    : p_visit_id INT
-- Devuelve  : datos del paciente, visita y últimas vacunas aplicadas
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_visit_patient_summary(
    IN    p_visit_id  INT,
    INOUT p_result    REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_result FOR
        SELECT
            pcv.visit_id,
            pcv.visit_status::TEXT,
            pcv.checked_in_at,
            pcv.waiting_since,
            pcv.consultation_start,
            pcv.vaccination_start,
            pcv.appointment_id,
            p.patient_id,
            TRIM(p.first_name || ' ' || p.last_name)                AS full_name,
            p.birth_date,
            DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT AS age,
            p.gender,
            p.weight_kg,
            p.photo,
            p.premature,
            COALESCE(bt.blood_type, '—')                            AS blood_type,
            -- Alergias detalladas
            COALESCE(
                (SELECT STRING_AGG(
                    al.name || ' — ' || COALESCE(pa.severity,'?') ||
                    COALESCE(' (' || pa.reaction_desc || ')',''), ' | '
                )
                 FROM   patient_allergies pa
                 JOIN   allergies al ON al.allergy_id = pa.allergy_id
                 WHERE  pa.patient_id = p.patient_id),
                'Sin alergias registradas'
            )                                                        AS allergies,
            -- Conteos de esquema de vacunación
            (SELECT COUNT(*) FROM patient_vaccine_schedule pvs
             WHERE pvs.patient_id = p.patient_id AND pvs.status = 'Pendiente')::INT AS pending_doses,
            (SELECT COUNT(*) FROM patient_vaccine_schedule pvs
             WHERE pvs.patient_id = p.patient_id AND pvs.status = 'Atrasada')::INT  AS overdue_doses,
            (SELECT COUNT(*) FROM patient_vaccine_schedule pvs
             WHERE pvs.patient_id = p.patient_id AND pvs.status = 'Aplicada')::INT  AS applied_doses,
            -- Última vacuna
            (SELECT MAX(vr.applied_date) FROM vaccination_records vr
             WHERE vr.patient_id = p.patient_id)                    AS last_vaccine_date,
            -- Datos de la cita vinculada
            a.scheduled_at,
            a.reason AS appointment_reason,
            a.appointment_notes,
            -- Tutor principal
            COALESCE(TRIM(g.first_name || ' ' || g.last_name), 'Sin tutor') AS guardian_name,
            COALESCE(
                (SELECT gp.phone FROM guardian_phones gp
                 WHERE gp.guardian_id = g.guardian_id
                 ORDER BY gp.is_primary DESC LIMIT 1),
                '—'
            )                                                        AS guardian_phone
        FROM   patient_clinic_visits pcv
        JOIN   patients p   ON p.patient_id    = pcv.patient_id
        LEFT   JOIN blood_types bt ON bt.blood_type_id = p.blood_type_id
        LEFT   JOIN appointments a ON a.appointment_id = pcv.appointment_id
        LEFT   JOIN LATERAL (
            SELECT pgr.guardian_id FROM patient_guardian_relations pgr
            WHERE  pgr.patient_id = p.patient_id
            ORDER  BY pgr.is_primary DESC LIMIT 1
        ) rel ON TRUE
        LEFT   JOIN guardians g ON g.guardian_id = rel.guardian_id
        WHERE  pcv.visit_id = p_visit_id;
END;
$$;

-- ============================================================
-- [50] sp_patient_pending_doses
-- Función   : Dosis pendientes o atrasadas del paciente para mostrar durante la visita
-- Recibe    : p_patient_id INT
-- Devuelve  : Filas de dosis no aplicadas con vacuna y días de retraso
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_patient_pending_doses(
    IN    p_patient_id  INT,
    INOUT p_result      REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_result FOR
        SELECT
            pvs.schedule_id,
            pvs.status,
            pvs.due_date,
            CASE
                WHEN pvs.due_date < CURRENT_DATE
                THEN (CURRENT_DATE - pvs.due_date)
                ELSE 0
            END                                    AS days_overdue,
            v.vaccine_id,
            v.name                                 AS vaccine_name,
            v.commercial_name,
            sd.dose_number,
            sd.dose_label,
            sd.ideal_age_months,
            vv.via                                 AS application_via,
            -- Lote disponible más cercano a vencer (FEFO)
            (SELECT vl.lot_id FROM vaccine_lots vl
             WHERE  vl.vaccine_id         = v.vaccine_id
               AND  vl.quantity_available > 0
               AND  vl.expiration_date    >= CURRENT_DATE
               AND  vl.is_active          = TRUE
             ORDER  BY vl.expiration_date LIMIT 1)  AS recommended_lot_id,
            (SELECT vl.lot_number FROM vaccine_lots vl
             WHERE  vl.vaccine_id         = v.vaccine_id
               AND  vl.quantity_available > 0
               AND  vl.expiration_date    >= CURRENT_DATE
               AND  vl.is_active          = TRUE
             ORDER  BY vl.expiration_date LIMIT 1)  AS recommended_lot_number,
            (SELECT vl.quantity_available FROM vaccine_lots vl
             WHERE  vl.vaccine_id         = v.vaccine_id
               AND  vl.quantity_available > 0
               AND  vl.expiration_date    >= CURRENT_DATE
               AND  vl.is_active          = TRUE
             ORDER  BY vl.expiration_date LIMIT 1)  AS lot_available_qty,
            (SELECT vl.expiration_date FROM vaccine_lots vl
             WHERE  vl.vaccine_id         = v.vaccine_id
               AND  vl.quantity_available > 0
               AND  vl.expiration_date    >= CURRENT_DATE
               AND  vl.is_active          = TRUE
             ORDER  BY vl.expiration_date LIMIT 1)  AS lot_expiration_date
        FROM   patient_vaccine_schedule pvs
        JOIN   scheme_doses sd ON sd.dose_id     = pvs.scheme_dose_id
        JOIN   vaccines v      ON v.vaccine_id   = sd.vaccine_id
        LEFT   JOIN vaccine_vias vv ON vv.via_id = v.via_id
        WHERE  pvs.patient_id = p_patient_id
          AND  pvs.status IN ('Pendiente','Atrasada')
        ORDER  BY pvs.status DESC, pvs.due_date;
END;
$$;

-- ============================================================
-- [35] sp_get_citas_medico
-- Función   : Agenda del día del médico con datos de pacientes y estado de vacunación
-- Recibe    : p_worker_id INT, p_date DATE
-- Devuelve  : Filas de citas del médico en esa fecha
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_citas_medico(
    IN    p_worker_id  INT,
    IN    p_date_from  DATE,
    IN    p_date_to    DATE,
    INOUT p_results    REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
    SELECT
        af.appointment_id,
        af.patient_id,
        af.worker_id,
        af.clinic_id,
        af.area_id,
        af.patient_schedule_id,
        af.scheduled_at,
        af.duration_min,
        af.reason,
        af.appointment_status,
        af.appointment_notes,
        af.cancel_reason,
        af.created_by_role,
        af.rescheduled_from_id,
        af.patient_name,
        af.worker_name,
        af.clinic_name,
        af.area_name,
        af.vaccine_name,
        af.dose_label,
        af.dose_due_date,
        af.dose_status,
        COALESCE(TRIM(g.first_name || ' ' || g.last_name), 'Sin tutor') AS guardian_name,
        COALESCE(
            (SELECT gp.phone
             FROM   guardian_phones gp
             WHERE  gp.guardian_id = g.guardian_id
             ORDER  BY gp.is_primary DESC LIMIT 1),
            '—'
        ) AS guardian_phone
    FROM   v_appointments_full af
    LEFT JOIN LATERAL (
        SELECT grd.guardian_id, grd.first_name, grd.last_name
        FROM   patient_guardian_relations pgr
        JOIN   guardians grd ON grd.guardian_id = pgr.guardian_id
        WHERE  pgr.patient_id = af.patient_id
        ORDER  BY pgr.is_primary DESC LIMIT 1
    ) g ON TRUE
    WHERE  af.worker_id = p_worker_id
      AND  af.scheduled_at::DATE BETWEEN
               COALESCE(p_date_from, '2015-01-01'::DATE)
           AND COALESCE(p_date_to,   CURRENT_DATE + INTERVAL '365 days')
    ORDER  BY af.scheduled_at DESC;
END;
$$;

-- ============================================================
-- MÓDULO: ALMACÉN
-- ============================================================

-- ============================================================
-- [51] sp_almacen_dashboard
-- Función   : Dashboard del almacén con KPIs de lotes, stock y alertas
-- Recibe    : p_clinic_id INT, p_results REFCURSOR
-- Devuelve  : conteos de lotes disponibles, vencidos, con bajo stock y transferencias pendientes
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_almacen_dashboard(
    IN    p_clinic_id       INT,
    INOUT p_kpis            REFCURSOR,
    INOUT p_alertas         REFCURSOR,
    INOUT p_movimientos     REFCURSOR,
    INOUT p_lotes_criticos  REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    -- KPIs
    OPEN p_kpis FOR
        SELECT
            COUNT(*) FILTER (WHERE lot_status = 'Disponible')                        AS lotes_activos,
            COALESCE(SUM(quantity_available) FILTER (WHERE lot_status = 'Disponible'), 0) AS dosis_disponibles,
            COUNT(*) FILTER (WHERE lot_status = 'Disponible'
                               AND expiration_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 30) AS lotes_por_vencer,
            COUNT(*) FILTER (WHERE lot_status = 'Agotado')                           AS lotes_agotados,
            COUNT(*) FILTER (WHERE lot_status = 'Caducado')                          AS lotes_caducados,
            COUNT(*) FILTER (WHERE lot_status = 'Disponible'
                               AND (quantity_available <= 5
                                    OR expiration_date <= CURRENT_DATE + 7))          AS alertas_criticas
        FROM vaccine_lots
        WHERE (p_clinic_id IS NULL OR clinic_id = p_clinic_id);

    -- Alertas (crítico primero)
    OPEN p_alertas FOR
        SELECT
            vl.lot_id, vl.lot_number, vl.quantity_available,
            vl.expiration_date,
            (vl.expiration_date - CURRENT_DATE) AS days_to_expiry,
            v.name AS vaccine_name,
            c.name AS clinic_name,
            CASE
                WHEN vl.expiration_date <= CURRENT_DATE + 7 THEN 'Critico'
                WHEN vl.quantity_available <= 5             THEN 'Critico'
                ELSE 'Advertencia'
            END AS alert_type,
            CASE
                WHEN vl.expiration_date < CURRENT_DATE
                    THEN 'Lote vencido'
                WHEN vl.expiration_date <= CURRENT_DATE + 7
                    THEN 'Vence en ' || (vl.expiration_date - CURRENT_DATE) || ' día(s)'
                WHEN vl.quantity_available <= 5
                    THEN 'Stock crítico: ' || vl.quantity_available || ' dosis'
                ELSE 'Stock bajo: ' || vl.quantity_available || ' dosis'
            END AS alert_reason
        FROM vaccine_lots vl
        JOIN vaccines v ON v.vaccine_id = vl.vaccine_id
        JOIN clinics  c ON c.clinic_id  = vl.clinic_id
        WHERE vl.lot_status = 'Disponible'
          AND (p_clinic_id IS NULL OR vl.clinic_id = p_clinic_id)
          AND (vl.expiration_date <= CURRENT_DATE + 30 OR vl.quantity_available <= 10)
        ORDER BY
            CASE WHEN vl.expiration_date <= CURRENT_DATE + 7 OR vl.quantity_available <= 5
                 THEN 0 ELSE 1 END,
            vl.expiration_date;

    -- Movimientos recientes (últimos 20)
    OPEN p_movimientos FOR
        SELECT
            im.movement_id, im.created_at, im.movement_type,
            im.quantity, im.quantity_before, im.quantity_after, im.reason,
            vl.lot_number,
            v.name AS vaccine_name,
            c.name AS clinic_name,
            (w.first_name || ' ' || w.last_name) AS worker_name
        FROM inventory_movements im
        JOIN vaccine_lots vl ON vl.lot_id     = im.lot_id
        JOIN vaccines     v  ON v.vaccine_id  = im.vaccine_id
        JOIN clinics      c  ON c.clinic_id   = im.clinic_id
        LEFT JOIN workers w  ON w.worker_id   = im.worker_id
        WHERE (p_clinic_id IS NULL OR im.clinic_id = p_clinic_id)
        ORDER BY im.created_at DESC
        LIMIT 20;

    -- Lotes críticos para gráfica
    OPEN p_lotes_criticos FOR
        SELECT
            vl.lot_id, vl.lot_number, vl.quantity_available,
            vl.expiration_date,
            v.name AS vaccine_name
        FROM vaccine_lots vl
        JOIN vaccines v ON v.vaccine_id = vl.vaccine_id
        WHERE vl.lot_status = 'Disponible'
          AND (p_clinic_id IS NULL OR vl.clinic_id = p_clinic_id)
          AND (vl.quantity_available <= 10 OR vl.expiration_date <= CURRENT_DATE + 30)
        ORDER BY vl.quantity_available ASC
        LIMIT 10;
END;
$$;

-- ============================================================
-- [52] sp_get_movements_full
-- Función   : Historial completo de movimientos de inventario
-- Recibe    : p_clinic_id INT opcional, p_results REFCURSOR
-- Devuelve  : Filas de inventory_movements con datos de lote y trabajador
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_movements_full(
    IN    p_clinic_id    INT,
    IN    p_lot_id       INT,
    IN    p_date_from    DATE,
    IN    p_date_to      DATE,
    IN    p_type_filter  VARCHAR,
    INOUT p_results      REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            im.movement_id, im.created_at, im.movement_type,
            im.quantity, im.quantity_before, im.quantity_after,
            im.reason, im.reference_type, im.reference_id,
            vl.lot_number,
            v.name AS vaccine_name,
            c.name AS clinic_name,
            (w.first_name || ' ' || w.last_name) AS worker_name
        FROM inventory_movements im
        JOIN vaccine_lots vl ON vl.lot_id    = im.lot_id
        JOIN vaccines     v  ON v.vaccine_id = im.vaccine_id
        JOIN clinics      c  ON c.clinic_id  = im.clinic_id
        LEFT JOIN workers w  ON w.worker_id  = im.worker_id
        WHERE
            (p_clinic_id   IS NULL OR im.clinic_id     = p_clinic_id)
            AND (p_lot_id  IS NULL OR im.lot_id        = p_lot_id)
            AND (p_date_from IS NULL OR im.created_at::DATE >= p_date_from)
            AND (p_date_to   IS NULL OR im.created_at::DATE <= p_date_to)
            AND (p_type_filter IS NULL OR im.movement_type = p_type_filter)
        ORDER BY im.created_at DESC;
END;
$$;

-- ============================================================
-- [53] sp_register_manual_movement
-- Función   : Registra un movimiento manual de entrada o ajuste de inventario
-- Recibe    : lot_id, clinic_id, worker_id, movement_type, quantity, notes
-- Devuelve  : success, movement_id, message
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_register_manual_movement(
    IN    p_lot_id        INT,
    IN    p_worker_id     INT,
    IN    p_movement_type VARCHAR,
    IN    p_quantity      INT,
    IN    p_reason        TEXT,
    INOUT p_results       REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_lot           RECORD;
    v_qty_before    INT;
    v_qty_after     INT;
    v_movement_id   INT;
    v_allowed_types TEXT[] := ARRAY['Ajuste_Positivo','Ajuste_Negativo','Salida_Merma','Salida_Caducidad'];
BEGIN
    IF NOT (p_movement_type = ANY(v_allowed_types)) THEN
        OPEN p_results FOR SELECT FALSE AS success,
            'Tipo de movimiento no permitido: ' || p_movement_type AS message,
            NULL::INT AS movement_id, NULL::INT AS quantity_after;
        RETURN;
    END IF;

    SELECT vl.lot_id, vl.vaccine_id, vl.clinic_id, vl.quantity_available, vl.lot_status
    INTO v_lot
    FROM vaccine_lots vl
    WHERE vl.lot_id = p_lot_id FOR UPDATE;

    IF NOT FOUND THEN
        OPEN p_results FOR SELECT FALSE AS success, 'Lote no encontrado.' AS message,
            NULL::INT AS movement_id, NULL::INT AS quantity_after;
        RETURN;
    END IF;

    v_qty_before := v_lot.quantity_available;

    IF p_movement_type IN ('Ajuste_Negativo','Salida_Merma','Salida_Caducidad') THEN
        IF v_qty_before < p_quantity THEN
            OPEN p_results FOR SELECT FALSE AS success,
                'Stock insuficiente. Disponible: ' || v_qty_before AS message,
                NULL::INT AS movement_id, NULL::INT AS quantity_after;
            RETURN;
        END IF;
        v_qty_after := v_qty_before - p_quantity;
    ELSE
        v_qty_after := v_qty_before + p_quantity;
    END IF;

    UPDATE vaccine_lots
    SET quantity_available = v_qty_after,
        lot_status = CASE
            WHEN v_qty_after = 0 THEN 'Agotado'
            WHEN v_qty_after > 0 AND lot_status = 'Agotado' AND expiration_date >= CURRENT_DATE THEN 'Disponible'
            ELSE lot_status
        END
    WHERE lot_id = p_lot_id;

    INSERT INTO inventory_movements (
        lot_id, vaccine_id, clinic_id, worker_id,
        movement_type, quantity, quantity_before, quantity_after,
        reference_type, reason
    ) VALUES (
        p_lot_id, v_lot.vaccine_id, v_lot.clinic_id, p_worker_id,
        p_movement_type, p_quantity, v_qty_before, v_qty_after,
        'manual', p_reason
    ) RETURNING movement_id INTO v_movement_id;

    OPEN p_results FOR SELECT TRUE AS success,
        'Movimiento registrado correctamente.' AS message,
        v_movement_id AS movement_id, v_qty_after AS quantity_after;
END;
$$;

-- ============================================================
-- [54] sp_update_lot_status
-- Función   : Cambia manualmente el lot_status de un lote (Bloqueado, Retirado, Disponible)
-- Recibe    : p_lot_id INT, p_new_status VARCHAR, p_worker_id INT
-- Devuelve  : success, message
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_update_lot_status(
    IN    p_lot_id      INT,
    IN    p_new_status  VARCHAR,
    IN    p_worker_id   INT,
    IN    p_reason      TEXT,
    INOUT p_results     REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_old_status VARCHAR(30);
BEGIN
    SELECT lot_status INTO v_old_status
    FROM vaccine_lots WHERE lot_id = p_lot_id FOR UPDATE;

    IF NOT FOUND THEN
        OPEN p_results FOR SELECT FALSE AS success, 'Lote no encontrado.' AS message;
        RETURN;
    END IF;

    IF v_old_status = p_new_status THEN
        OPEN p_results FOR SELECT FALSE AS success,
            'El lote ya tiene ese estado.' AS message;
        RETURN;
    END IF;

    UPDATE vaccine_lots SET lot_status = p_new_status WHERE lot_id = p_lot_id;

    INSERT INTO audit_log (table_name, record_id, action, worker_id, changed_data)
    VALUES ('vaccine_lots', p_lot_id, 'UPDATE', p_worker_id,
            jsonb_build_object('from_status', v_old_status,
                               'to_status',   p_new_status,
                               'reason',      p_reason));

    OPEN p_results FOR SELECT TRUE AS success,
        'Estado actualizado a ' || p_new_status || '.' AS message;
END;
$$;

-- ============================================================
-- [55] sp_get_almacen_alerts
-- Función   : Alertas de almacén: lotes con bajo stock, vencidos o próximos a vencer
-- Recibe    : p_clinic_id INT, p_results REFCURSOR
-- Devuelve  : Filas de alertas de vaccine_lots con tipo y mensaje
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_almacen_alerts(
    IN    p_clinic_id INT,
    INOUT p_results   REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            vl.lot_id, vl.lot_number, vl.quantity_available,
            vl.expiration_date,
            (vl.expiration_date - CURRENT_DATE) AS days_to_expiry,
            v.name AS vaccine_name,
            c.name AS clinic_name,
            CASE
                WHEN vl.expiration_date <= CURRENT_DATE + 7 THEN 'Critico'
                WHEN vl.quantity_available <= 5             THEN 'Critico'
                ELSE 'Advertencia'
            END AS alert_type,
            CASE
                WHEN vl.expiration_date < CURRENT_DATE
                    THEN 'Lote vencido'
                WHEN vl.expiration_date <= CURRENT_DATE + 7
                    THEN 'Vence en ' || (vl.expiration_date - CURRENT_DATE) || ' día(s)'
                WHEN vl.quantity_available <= 5
                    THEN 'Stock crítico: ' || vl.quantity_available || ' dosis'
                ELSE 'Stock bajo: ' || vl.quantity_available || ' dosis'
            END AS alert_reason
        FROM vaccine_lots vl
        JOIN vaccines v ON v.vaccine_id = vl.vaccine_id
        JOIN clinics  c ON c.clinic_id  = vl.clinic_id
        WHERE vl.lot_status = 'Disponible'
          AND (p_clinic_id IS NULL OR vl.clinic_id = p_clinic_id)
          AND (vl.expiration_date <= CURRENT_DATE + 30 OR vl.quantity_available <= 10)
        ORDER BY
            CASE WHEN vl.expiration_date <= CURRENT_DATE + 7 OR vl.quantity_available <= 5
                 THEN 0 ELSE 1 END,
            vl.expiration_date;
END;
$$;

-- ============================================================
-- [56] sp_get_lot_detail
-- Función   : Detalle completo de un lote con historial de movimientos
-- Recibe    : p_lot_id INT
-- Devuelve  : datos del lote y sus últimos movimientos de inventory_movements
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_lot_detail(
    IN    p_lot_id  INT,
    INOUT p_lot     REFCURSOR,
    INOUT p_movs    REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_lot FOR
        SELECT
            vl.*,
            v.name AS vaccine_name, v.commercial_name,
            c.name AS clinic_name,
            m.name AS manufacturer,
            (vl.quantity_received - vl.quantity_available) AS dosis_aplicadas
        FROM vaccine_lots vl
        JOIN vaccines  v ON v.vaccine_id    = vl.vaccine_id
        JOIN clinics   c ON c.clinic_id     = vl.clinic_id
        LEFT JOIN manufacturers m ON m.manufacturer_id = v.manufacturer_id
        WHERE vl.lot_id = p_lot_id;

    OPEN p_movs FOR
        SELECT
            im.movement_id, im.created_at, im.movement_type,
            im.quantity, im.quantity_before, im.quantity_after,
            im.reason, im.reference_type, im.reference_id,
            (w.first_name || ' ' || w.last_name) AS worker_name
        FROM inventory_movements im
        LEFT JOIN workers w ON w.worker_id = im.worker_id
        WHERE im.lot_id = p_lot_id
        ORDER BY im.created_at DESC;
END;
$$;

-- ============================================================
-- STORED PROCEDURES — Fase 2 (Transferencias)
-- ============================================================

-- ============================================================
-- [57] sp_get_transfers
-- Función   : Lista de transferencias de lotes entre clínicas
-- Recibe    : p_clinic_id INT opcional, p_results REFCURSOR
-- Devuelve  : Filas de inventory_transfers con estado y clínicas origen/destino
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_transfers(
    IN    p_clinic_id      INT,
    IN    p_status_filter  VARCHAR,
    INOUT p_results        REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            t.transfer_id, t.lot_id, t.quantity, t.transfer_status,
            t.reason, t.notes, t.requested_at, t.resolved_at,
            t.from_clinic_id, t.to_clinic_id,
            vl.lot_number,
            v.name AS vaccine_name,
            cf.name  AS from_clinic_name,
            ct.name  AS to_clinic_name,
            (wr.first_name || ' ' || wr.last_name) AS requested_by_name,
            (wa.first_name || ' ' || wa.last_name) AS approved_by_name,
            vl.quantity_available
        FROM inventory_transfers t
        JOIN vaccine_lots  vl ON vl.lot_id      = t.lot_id
        JOIN vaccines       v ON v.vaccine_id   = t.vaccine_id
        JOIN clinics        cf ON cf.clinic_id  = t.from_clinic_id
        JOIN clinics        ct ON ct.clinic_id  = t.to_clinic_id
        JOIN workers        wr ON wr.worker_id  = t.requested_by
        LEFT JOIN workers   wa ON wa.worker_id  = t.approved_by
        WHERE
            (p_clinic_id     IS NULL OR t.from_clinic_id = p_clinic_id OR t.to_clinic_id = p_clinic_id)
            AND (p_status_filter IS NULL OR t.transfer_status = p_status_filter)
        ORDER BY t.requested_at DESC;
END;
$$;

-- ============================================================
-- [58] sp_create_transfer
-- Función   : Crea una solicitud de transferencia de lote entre clínicas
-- Recibe    : lot_id, source_clinic_id, dest_clinic_id, quantity, worker_id
-- Devuelve  : success, transfer_id, message
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_create_transfer(
    IN    p_lot_id        INT,
    IN    p_to_clinic_id  INT,
    IN    p_quantity      INT,
    IN    p_worker_id     INT,
    IN    p_reason        TEXT,
    INOUT p_results       REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_lot         RECORD;
    v_transfer_id INT;
BEGIN
    SELECT vl.lot_id, vl.vaccine_id, vl.clinic_id,
           vl.quantity_available, vl.lot_status,
           v.name AS vaccine_name, c.name AS clinic_name
    INTO v_lot
    FROM vaccine_lots vl
    JOIN vaccines v ON v.vaccine_id = vl.vaccine_id
    JOIN clinics  c ON c.clinic_id  = vl.clinic_id
    WHERE vl.lot_id = p_lot_id;

    IF NOT FOUND THEN
        OPEN p_results FOR SELECT FALSE AS success, 'Lote no encontrado.' AS message, NULL::INT AS transfer_id;
        RETURN;
    END IF;

    IF v_lot.lot_status <> 'Disponible' THEN
        OPEN p_results FOR SELECT FALSE AS success,
            'El lote está en estado ' || v_lot.lot_status || ' y no puede transferirse.' AS message,
            NULL::INT AS transfer_id;
        RETURN;
    END IF;

    IF v_lot.quantity_available < p_quantity THEN
        OPEN p_results FOR SELECT FALSE AS success,
            'Stock insuficiente. Disponible: ' || v_lot.quantity_available || ', solicitado: ' || p_quantity AS message,
            NULL::INT AS transfer_id;
        RETURN;
    END IF;

    IF v_lot.clinic_id = p_to_clinic_id THEN
        OPEN p_results FOR SELECT FALSE AS success,
            'La clínica destino debe ser diferente a la clínica origen.' AS message,
            NULL::INT AS transfer_id;
        RETURN;
    END IF;

    INSERT INTO inventory_transfers (
        lot_id, vaccine_id, from_clinic_id, to_clinic_id,
        quantity, transfer_status, requested_by, reason
    ) VALUES (
        p_lot_id, v_lot.vaccine_id, v_lot.clinic_id, p_to_clinic_id,
        p_quantity, 'Pendiente', p_worker_id, p_reason
    ) RETURNING transfer_id INTO v_transfer_id;

    OPEN p_results FOR SELECT TRUE AS success,
        'Transferencia #' || v_transfer_id || ' creada correctamente.' AS message,
        v_transfer_id AS transfer_id;
END;
$$;

-- ============================================================
-- [59] sp_accept_transfer
-- Función   : Acepta una transferencia pendiente, descuenta stock del origen y crea/actualiza lote en destino
-- Recibe    : p_transfer_id INT, p_worker_id INT
-- Devuelve  : success, transfer_id, message
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_accept_transfer(
    IN    p_transfer_id  INT,
    IN    p_worker_id    INT,
    IN    p_notes        TEXT,
    INOUT p_results      REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_t              RECORD;
    v_src_lot        RECORD;
    v_qty_before     INT;
    v_qty_after      INT;
    v_dest_lot_id    INT;
    v_dest_qty_before INT;
BEGIN
    SELECT t.transfer_id, t.lot_id, t.vaccine_id,
           t.from_clinic_id, t.to_clinic_id,
           t.quantity, t.transfer_status
    INTO v_t
    FROM inventory_transfers t
    WHERE t.transfer_id = p_transfer_id FOR UPDATE;

    IF NOT FOUND THEN
        OPEN p_results FOR SELECT FALSE AS success, 'Transferencia no encontrada.' AS message;
        RETURN;
    END IF;

    IF v_t.transfer_status NOT IN ('Pendiente', 'En_Transito') THEN
        OPEN p_results FOR SELECT FALSE AS success,
            'Solo se pueden aceptar transferencias Pendientes o En_Transito. Estado actual: ' || v_t.transfer_status AS message;
        RETURN;
    END IF;

    -- Leer lote origen completo (para clonar datos al destino si hace falta)
    SELECT * INTO v_src_lot FROM vaccine_lots WHERE lot_id = v_t.lot_id FOR UPDATE;
    v_qty_before := v_src_lot.quantity_available;

    IF v_qty_before < v_t.quantity THEN
        OPEN p_results FOR SELECT FALSE AS success,
            'Stock insuficiente en lote origen. Disponible: ' || v_qty_before AS message;
        RETURN;
    END IF;

    v_qty_after := v_qty_before - v_t.quantity;

    -- Descontar del lote origen
    UPDATE vaccine_lots
    SET quantity_available = v_qty_after,
        lot_status = CASE WHEN v_qty_after = 0 THEN 'Agotado' ELSE lot_status END
    WHERE lot_id = v_t.lot_id;

    -- Buscar lote con mismo número en clínica destino
    -- (requiere constraint UNIQUE(lot_number, clinic_id))
    SELECT lot_id, quantity_available INTO v_dest_lot_id, v_dest_qty_before
    FROM vaccine_lots
    WHERE clinic_id  = v_t.to_clinic_id
      AND lot_number = v_src_lot.lot_number;

    IF v_dest_lot_id IS NOT NULL THEN
        -- Sumar al lote existente en destino
        UPDATE vaccine_lots
        SET quantity_available = quantity_available + v_t.quantity,
            lot_status = 'Disponible'
        WHERE lot_id = v_dest_lot_id;
    ELSE
        -- Crear nuevo lote en la clínica destino
        INSERT INTO vaccine_lots (
            vaccine_id, clinic_id, lot_number,
            quantity_received, quantity_available,
            expiration_date, received_date, is_active, lot_status
        ) VALUES (
            v_src_lot.vaccine_id, v_t.to_clinic_id, v_src_lot.lot_number,
            v_t.quantity, v_t.quantity,
            v_src_lot.expiration_date, NOW()::DATE, TRUE, 'Disponible'
        )
        RETURNING lot_id INTO v_dest_lot_id;

        v_dest_qty_before := 0;
    END IF;

    -- Movimiento: salida de clínica origen
    INSERT INTO inventory_movements (
        lot_id, vaccine_id, clinic_id, worker_id,
        movement_type, quantity, quantity_before, quantity_after,
        reference_id, reference_type, reason
    ) VALUES (
        v_t.lot_id, v_t.vaccine_id, v_t.from_clinic_id, p_worker_id,
        'Transferencia_Salida', v_t.quantity, v_qty_before, v_qty_after,
        p_transfer_id, 'transfer',
        'Transferencia #' || p_transfer_id || ' aceptada'
    );

    -- Movimiento: entrada en clínica destino
    INSERT INTO inventory_movements (
        lot_id, vaccine_id, clinic_id, worker_id,
        movement_type, quantity, quantity_before, quantity_after,
        reference_id, reference_type, reason
    ) VALUES (
        v_dest_lot_id, v_t.vaccine_id, v_t.to_clinic_id, p_worker_id,
        'Transferencia_Entrada', v_t.quantity, v_dest_qty_before, v_dest_qty_before + v_t.quantity,
        p_transfer_id, 'transfer',
        'Transferencia #' || p_transfer_id || ' recibida'
    );

    UPDATE inventory_transfers
    SET transfer_status = 'Recibido',
        approved_by     = p_worker_id,
        notes           = COALESCE(p_notes, notes),
        resolved_at     = NOW()
    WHERE transfer_id = p_transfer_id;

    OPEN p_results FOR SELECT TRUE AS success,
        'Transferencia #' || p_transfer_id || ' recibida correctamente.' AS message;
END;
$$;

-- ============================================================
-- [60] sp_reject_transfer
-- Función   : Rechaza una transferencia pendiente con motivo
-- Recibe    : p_transfer_id INT, p_worker_id INT, p_reason TEXT
-- Devuelve  : success, message
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_reject_transfer(
    IN    p_transfer_id  INT,
    IN    p_worker_id    INT,
    IN    p_reason       TEXT,
    INOUT p_results      REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR(20);
BEGIN
    SELECT transfer_status INTO v_status
    FROM inventory_transfers WHERE transfer_id = p_transfer_id FOR UPDATE;

    IF NOT FOUND THEN
        OPEN p_results FOR SELECT FALSE AS success, 'Transferencia no encontrada.' AS message;
        RETURN;
    END IF;

    IF v_status <> 'Pendiente' THEN
        OPEN p_results FOR SELECT FALSE AS success,
            'Solo se pueden rechazar transferencias Pendientes. Estado actual: ' || v_status AS message;
        RETURN;
    END IF;

    UPDATE inventory_transfers
    SET transfer_status = 'Rechazado',
        approved_by     = p_worker_id,
        notes           = p_reason,
        resolved_at     = NOW()
    WHERE transfer_id = p_transfer_id;

    OPEN p_results FOR SELECT TRUE AS success,
        'Transferencia #' || p_transfer_id || ' rechazada.' AS message;
END;
$$;

-- ============================================================
-- [61] sp_cancel_transfer
-- Función   : Cancela una transferencia pendiente
-- Recibe    : p_transfer_id INT, p_worker_id INT
-- Devuelve  : success, message
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_cancel_transfer(
    IN    p_transfer_id  INT,
    IN    p_worker_id    INT,
    IN    p_reason       TEXT,
    INOUT p_results      REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR(20);
BEGIN
    SELECT transfer_status INTO v_status
    FROM inventory_transfers WHERE transfer_id = p_transfer_id FOR UPDATE;

    IF NOT FOUND THEN
        OPEN p_results FOR SELECT FALSE AS success, 'Transferencia no encontrada.' AS message;
        RETURN;
    END IF;

    IF v_status <> 'Pendiente' THEN
        OPEN p_results FOR SELECT FALSE AS success,
            'Solo se pueden cancelar transferencias Pendientes. Estado actual: ' || v_status AS message;
        RETURN;
    END IF;

    UPDATE inventory_transfers
    SET transfer_status = 'Cancelado',
        notes           = p_reason,
        resolved_at     = NOW()
    WHERE transfer_id = p_transfer_id;

    OPEN p_results FOR SELECT TRUE AS success,
        'Transferencia #' || p_transfer_id || ' cancelada.' AS message;
END;
$$;

-- ============================================================
-- MÓDULO: RECEPCIONISTA
-- ============================================================

-- ============================================================
-- [62] sp_recepcionista_kpis
-- Función   : KPIs del dashboard de recepcionista: citas de hoy por estado y pacientes nuevos
-- Recibe    : p_results REFCURSOR
-- Devuelve  : Una fila con conteos del día y de la semana
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_recepcionista_kpis(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            -- Citas de hoy por estado
            COUNT(*) FILTER (
                WHERE DATE(a.scheduled_at) = CURRENT_DATE
            )                                                          AS citas_hoy_total,

            COUNT(*) FILTER (
                WHERE DATE(a.scheduled_at) = CURRENT_DATE
                  AND a.appointment_status = 'Completada'
            )                                                          AS citas_hoy_completadas,

            COUNT(*) FILTER (
                WHERE DATE(a.scheduled_at) = CURRENT_DATE
                  AND a.appointment_status IN ('Programada', 'Confirmada')
            )                                                          AS citas_hoy_pendientes,

            COUNT(*) FILTER (
                WHERE DATE(a.scheduled_at) = CURRENT_DATE
                  AND a.appointment_status = 'Cancelada'
            )                                                          AS citas_hoy_canceladas,

            COUNT(*) FILTER (
                WHERE DATE(a.scheduled_at) = CURRENT_DATE
                  AND a.appointment_status = 'No Show'
            )                                                          AS citas_hoy_no_show,

            -- Pacientes nuevos hoy
            (SELECT COUNT(*)
             FROM patients
             WHERE DATE(created_at) = CURRENT_DATE
               AND is_active = TRUE
            )                                                          AS pacientes_hoy,

            -- Pacientes nuevos esta semana (lun-dom)
            (SELECT COUNT(*)
             FROM patients
             WHERE created_at >= DATE_TRUNC('week', CURRENT_DATE)
               AND created_at <  DATE_TRUNC('week', CURRENT_DATE) + INTERVAL '7 days'
               AND is_active = TRUE
            )                                                          AS pacientes_semana

        FROM appointments a;
END;
$$;

-- ============================================================
-- [63] sp_recepcionista_citas_hoy
-- Función   : Citas de hoy con datos de paciente, médico y alerta de tardía
-- Recibe    : p_results REFCURSOR
-- Devuelve  : Filas de citas del día ordenadas por hora con flag alerta_tardia
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_recepcionista_citas_hoy(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            a.appointment_id,
            a.scheduled_at,
            a.appointment_status,
            a.patient_id,
            (p.first_name || ' ' || p.last_name)          AS patient_name,
            COALESCE(cat.name, '—')                        AS area_name,
            COALESCE(w.first_name || ' ' || w.last_name,
                     '—')                                  AS worker_name,
            -- ¿Tiene vacuna programada en el esquema?
            EXISTS (
                SELECT 1 FROM patient_vaccine_schedule pvs
                WHERE pvs.patient_id = a.patient_id
                  AND pvs.status = 'Pendiente'
                  AND pvs.due_date <= CURRENT_DATE
            )                                              AS vacuna_programada,
            -- Alerta: hora ya pasó y aún no se registró asistencia
            (
                a.scheduled_at < NOW()
                AND a.appointment_status IN ('Programada', 'Confirmada')
            )                                              AS alerta_tardia
        FROM appointments a
        JOIN patients p ON p.patient_id = a.patient_id
        LEFT JOIN clinic_areas       ca  ON ca.area_id   = a.area_id
        LEFT JOIN clinic_area_types  cat ON cat.area_type_id = ca.area_type_id
        LEFT JOIN workers            w   ON w.worker_id  = a.worker_id
        WHERE DATE(a.scheduled_at) = CURRENT_DATE
        ORDER BY a.scheduled_at ASC;
END;
$$;

-- ============================================================
-- [64] sp_recepcionista_actividad_reciente
-- Función   : Últimas N acciones en las últimas 24 h (citas agendadas y pacientes registrados)
-- Recibe    : p_limit INT, p_results REFCURSOR
-- Devuelve  : Filas con tipo, descripcion y timestamp
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_recepcionista_actividad_reciente(
    IN    p_limit   INT,
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT tipo, descripcion, ts
        FROM (
            -- Citas agendadas en las últimas 24 h
            SELECT
                'Cita agendada'                             AS tipo,
                'Cita para ' || p.first_name || ' ' || p.last_name
                    || ' a las ' || TO_CHAR(a.scheduled_at, 'HH24:MI')
                                                            AS descripcion,
                a.created_at                                AS ts
            FROM appointments a
            JOIN patients p ON p.patient_id = a.patient_id
            WHERE a.created_at >= NOW() - INTERVAL '24 hours'

            UNION ALL

            -- Pacientes registrados en las últimas 24 h
            SELECT
                'Paciente registrado'                       AS tipo,
                'Nuevo paciente: ' || p.first_name || ' ' || p.last_name
                                                            AS descripcion,
                p.created_at                                AS ts
            FROM patients p
            WHERE p.created_at >= NOW() - INTERVAL '24 hours'
              AND p.is_active = TRUE
        ) actividad
        ORDER BY ts DESC
        LIMIT p_limit;
END;
$$;

-- ============================================================
-- [65] sp_recepcionista_pacientes_semana
-- Función   : Pacientes registrados por día en la semana actual para gráfica de Highcharts
-- Recibe    : p_results REFCURSOR
-- Devuelve  : Filas con dia, dia_label y total por día
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_recepcionista_pacientes_semana(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        WITH dias AS (
            SELECT generate_series(
                DATE_TRUNC('week', CURRENT_DATE),
                CURRENT_DATE,
                INTERVAL '1 day'
            )::DATE AS dia
        )
        SELECT
            d.dia,
            TO_CHAR(d.dia, 'Dy')   AS dia_label,
            COUNT(p.patient_id)    AS total
        FROM dias d
        LEFT JOIN patients p
               ON p.created_at::DATE = d.dia
              AND p.is_active = TRUE
        GROUP BY d.dia
        ORDER BY d.dia;
END;
$$;


-- ============================================================
-- ============================================================
--  DEPRECATED — SPs ELIMINADOS (referencia histórica)
--  NO ejecutar. Solo para auditoría y rollback si se necesita.
-- ============================================================
-- ============================================================

/*
-- ── sp_get_tutor_pending_citas ────────────────────────────────
-- Razón de eliminación: filtraba por tutor_accepted IS NULL,
-- semántica que ya no existe en el nuevo flujo de citas.
CREATE OR REPLACE PROCEDURE sp_get_tutor_pending_citas(
    IN p_guardian_id INT, INOUT p_results REFCURSOR) ...
*/

/*
-- ── sp_get_tutor_citas_history ────────────────────────────────
-- Razón de eliminación: usaba tutor_accepted, ya eliminado.
CREATE OR REPLACE PROCEDURE sp_get_tutor_citas_history(
    IN p_guardian_id INT, INOUT p_results REFCURSOR) ...
*/

/*
-- ── sp_get_admin_pending_confirmation ────────────────────────
-- Razón de eliminación: filtraba tutor_accepted IS NULL.
-- Reemplazado por sp_dashboard_clinica.
CREATE OR REPLACE PROCEDURE sp_get_admin_pending_confirmation(
    INOUT p_results REFCURSOR) ...
*/

/*
-- ── sp_get_admin_upcoming_citas ──────────────────────────────
-- Razón de eliminación: mezclaba esquema médico con agenda clínica.
-- Reemplazado por sp_dashboard_clinica.
CREATE OR REPLACE PROCEDURE sp_get_admin_upcoming_citas(
    INOUT p_results REFCURSOR) ...
*/

/*
-- ── sp_confirm_appointment ───────────────────────────────────
-- Razón de eliminación: era para confirmar citas auto-generadas
-- via tutor_accepted. Ya no existe 'Pendiente confirmación'.
CREATE OR REPLACE PROCEDURE sp_confirm_appointment(
    IN p_appointment_id INT, INOUT p_results REFCURSOR) ...
*/

/*
-- ── sp_complete_appointment ──────────────────────────────────
-- Razón de eliminación: reemplazado por trigger 15
-- (trg_complete_appointment_on_vaccination).
-- Marcar una cita como Completada ocurre automáticamente al
-- insertar un vaccination_record.
CREATE OR REPLACE PROCEDURE sp_complete_appointment(
    IN p_appointment_id INT, INOUT p_results REFCURSOR) ...
*/

/*
-- ── sp_record_vaccine_reaction ───────────────────────────────
-- Razón de eliminación: columnas incorrectas (vaccination_record_id,
-- reaction_description, reported_at no existen en post_vaccine_reactions).
-- La tabla usa: record_id, symptom, severity, onset_hours, treatment.
CREATE OR REPLACE PROCEDURE sp_record_vaccine_reaction(
    IN p_vaccination_record_id INT, IN p_reaction_desc TEXT,
    IN p_severity VARCHAR, INOUT p_results REFCURSOR) ...
*/

/*
-- ── sp_get_pending_scheme_doses ──────────────────────────────
-- Razón de eliminación: usaba CROSS JOIN patients × scheme_doses
-- ignorando patient_vaccine_schedule (tabla fuente de verdad).
-- Reemplazado por sp_get_pending_doses.
CREATE OR REPLACE PROCEDURE sp_get_pending_scheme_doses(
    IN p_patient_id INT, INOUT p_results REFCURSOR) ...
*/
