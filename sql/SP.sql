SET client_encoding = 'UTF8';

-- VER SPs EN POSTGRES
/*
SELECT routine_name 
FROM information_schema.routines 
WHERE routine_type = 'PROCEDURE' 
AND routine_schema = 'public';
*/

-- =====================================
-- WRAPPERS DE VISTAS
-- =====================================

-- Pacientes completos — sin depender de vw_patients
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

BEGIN ;
CALL sp_get_patients_full(NULL, 'patients_cursor');
FETCH ALL FROM patients_cursor;
COMMIT;


-- v_appointments_full
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


--=========================================================================
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



-- ==============================================
-- MÓDULO: PACIENTES (CRUD y adherencia)
-- ==============================================

-- (APPLICADO) Registrar nuevo paciente
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

    -- ── Tutor: buscar o crear ─────────────────────────────────────────────

    -- 1. Buscar por CURP (identificador unico, mas confiable)
    IF p_guardian_curp IS NOT NULL AND TRIM(p_guardian_curp) <> '' THEN
        SELECT guardian_id INTO v_guardian_id
        FROM   guardians
        WHERE  curp = TRIM(p_guardian_curp)
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

    -- 3. Si no existe, crear tutor nuevo
    IF v_guardian_id IS NULL AND p_guardian_name IS NOT NULL AND TRIM(p_guardian_name) <> '' THEN
        INSERT INTO guardians (first_name, last_name, curp)
        VALUES (
            TRIM(p_guardian_name),
            TRIM(COALESCE(p_guardian_last, '')),
            NULLIF(TRIM(COALESCE(p_guardian_curp, '')), '')
        )
        RETURNING guardian_id INTO v_guardian_id;
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

BEGIN;
CALL sp_register_patient(
    'Diana',           -- first_name
    'Ross',            -- last_name
    'DIAR350503YGFERT06', -- curp
    '2025-05-12',      -- birth_date
    'F',               -- gender
    4,                 -- blood_type_id
    34.6,              -- weight_kg
    FALSE,             -- premature
    'Mike',            -- guardian_name
    'Ross',            -- guardian_last
    NULL,              -- guardian_curp
    '8110000019',      -- guardian_phone
    NULL,              -- guardian_email
    'p_results'        -- cursor
);
FETCH ALL FROM p_results;
COMMIT;


-- Actualizar paciente (firma expandida: curp + birth_date)
DROP PROCEDURE IF EXISTS sp_update_patient(INT, VARCHAR, VARCHAR, INT, NUMERIC, REFCURSOR);

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

BEGIN;
CALL sp_update_patient(
    16,
    'Juan',
    'Perez',
    2,
    35.5,
    'p_results'
);
FETCH ALL FROM p_results;
COMMIT;


-- (CORREGIR) Eliminar paciente (cascada controlada)
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

BEGIN ;
CALL sp_delete_patient(16, 'p_results');
FETCH ALL FROM p_results;
COMMIT ;


-- Calcular adherencia del paciente al esquema
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
 

BEGIN;
CALL sp_get_patient_scheme(11, 'cur_esquema');
FETCH ALL FROM cur_esquema;
COMMIT;



-- ==============================================

-- MÓDULO: VACUNAS (CRUD)

-- ==============================================

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

-- =====================================
-- [DEPRECADO] CITAS — VISTA ADMIN (flujo tutor_accepted)
-- Movidos al fondo del archivo. Ver sección DEPRECATED.
-- Reemplazados por: sp_dashboard_clinica
-- =====================================
-- sp_get_admin_pending_confirmation → DEPRECATED (usaba tutor_accepted IS NULL)
-- sp_get_admin_upcoming_citas       → DEPRECATED (usaba tutor_accepted)


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


-- Editar datos de un lote existente.
-- Si la nueva fecha de vencimiento es futura, reactiva el lote automáticamente.
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


-- Desactivar (soft-delete) un lote vencido. No elimina el registro.
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


-- ==============================================

-- MÓDULO: VACUNACIÓN (REGISTROS Y REACCIONES)

-- ==============================================

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

BEGIN;
CALL sp_register_vaccination_record(
    1,
    3,
    2,
    1,
    3,
    3,
    CURRENT_DATE,
    1,
    36.5,
    FALSE,
    'p_results'

);
FETCH ALL FROM p_results;
COMMIT;


-- ============================================================
-- [DEPRECADO] sp_record_vaccine_reaction
-- Columnas incorrectas: vaccination_record_id, reaction_description, reported_at
-- no existen en post_vaccine_reactions. La tabla usa: record_id, symptom.
-- Movido al fondo. Ver sección DEPRECATED.
-- ============================================================


-- ================================================================================

-- MÓDULO: CITAS (CRUD)

-- ===============================================================================

-- ============================================================
-- [REESCRITO] sp_create_appointment
-- CAMBIOS:
--   - Eliminado p_requires_tutor y lógica de 'Pendiente confirmación'
--   - Agregado p_patient_id directo (no solo via schedule)
--   - Agregado p_created_by_role, p_created_by_worker_id, p_created_by_guardian_id
--   - p_patient_schedule_id ahora es OPCIONAL (NULL para citas generales)
--   - Validaciones mejoradas: worker + área + dosis duplicada
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

        -- Verificar que el trabajador tiene horario laboral en esa clinica para ese dia/hora
        IF p_worker_id IS NOT NULL THEN
            IF NOT EXISTS (
                SELECT 1
                FROM   worker_schedules ws
                WHERE  ws.worker_id   = p_worker_id
                AND  ws.clinic_id   = p_clinic_id
                AND  ws.day_of_week = EXTRACT(ISODOW FROM p_scheduled_at)::SMALLINT
                AND  ws.entry_time  <= p_scheduled_at::TIME
                AND  ws.exit_time   >  p_scheduled_at::TIME
            ) THEN
                RAISE EXCEPTION 'El trabajador no tiene horario laboral en esa clinica para la fecha y hora indicadas';
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
-- [REESCRITO] sp_cancel_appointment
-- CAMBIOS: validaciones completas, manejo correcto de estados finales,
--          ya no depende de tutor_accepted.
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
-- [REESCRITO] sp_reschedule_appointment
-- CAMBIOS:
--   - La nueva cita arranca en 'Programada' (no 'Pendiente confirmación')
--   - Hereda patient_id directamente de la cita original
--   - Agregado p_reschedule_reason para trazabilidad
--   - Validaciones correctas de estado
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


-- SP: se hizo la cita pero el paciente no fue
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


-- ==============================================

-- MÓDULO: REPORTERÍA, ALERTAS Y BÚSQUEDA

-- (no son wrappers dedicados de una sola vista)

-- ==============================================



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



-- Asigna o actualiza el nfc_id de un paciente (valida UNIQUE)
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


-- Limpia el nfc_id de un paciente (lo pone en NULL)
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





-- ==============================================

-- MÓDULO: CATÁLOGOS Y DATOS PARA FORMULARIOS

-- ==============================================



CREATE OR REPLACE PROCEDURE sp_get_blood_types(

    INOUT p_results REFCURSOR

)

LANGUAGE plpgsql AS $$

BEGIN

    OPEN p_results FOR

        SELECT blood_type_id, blood_type FROM blood_types ORDER BY blood_type_id;

END;

$$;



CREATE OR REPLACE PROCEDURE sp_get_manufacturers(

    INOUT p_results REFCURSOR

)

LANGUAGE plpgsql AS $$

BEGIN

    OPEN p_results FOR

        SELECT manufacturer_id, name FROM manufacturers ORDER BY name;

END;

$$;



CREATE OR REPLACE PROCEDURE sp_get_vaccine_vias(

    INOUT p_results REFCURSOR

)

LANGUAGE plpgsql AS $$

BEGIN

    OPEN p_results FOR

        SELECT via_id, via FROM vaccine_vias ORDER BY via;

END;

$$;



CREATE OR REPLACE PROCEDURE sp_get_roles(

    INOUT p_results REFCURSOR

)

LANGUAGE plpgsql AS $$

BEGIN

    OPEN p_results FOR

        SELECT role_id, name FROM roles ORDER BY name;

END;

$$;



CREATE OR REPLACE PROCEDURE sp_get_clinics(

    INOUT p_results REFCURSOR

)

LANGUAGE plpgsql AS $$

BEGIN

    OPEN p_results FOR

        SELECT clinic_id, name FROM clinics WHERE is_active = TRUE ORDER BY name;

END;

$$;



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



CREATE OR REPLACE PROCEDURE sp_get_application_sites(

    INOUT p_results REFCURSOR

)

LANGUAGE plpgsql AS $$

BEGIN

    OPEN p_results FOR

        SELECT application_site_id, application_site FROM application_sites ORDER BY application_site;

END;

$$;



CREATE OR REPLACE PROCEDURE sp_get_countries(

    INOUT p_results REFCURSOR

)

LANGUAGE plpgsql AS $$

BEGIN

    OPEN p_results FOR

        SELECT country_id, name, iso_code FROM countries ORDER BY name;

END;

$$;



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





-- ==============================================
-- COLUMNAS FALTANTES EN PATIENTS
-- (ejecutar solo si la tabla ya existe sin estas columnas)
-- ==============================================
ALTER TABLE patients ADD COLUMN IF NOT EXISTS is_active   BOOLEAN   NOT NULL DEFAULT TRUE;
ALTER TABLE patients ADD COLUMN IF NOT EXISTS updated_at  TIMESTAMP;
ALTER TABLE patients ADD COLUMN IF NOT EXISTS deleted_at  TIMESTAMP;


-- ==============================================
-- SPs DE LECTURA FALTANTES
-- ==============================================

-- Vacunas completas (usada en /vacunas)
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


-- Registros de vacunación completos (usada en /historial, /aplicaciones)
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

-- Personal completo (usada en /personal)
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

-- Esquema general de vacunación (todas las vacunas × dosis)
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

-- Dosis pendientes de un paciente (usada en /historial)
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

-- Estado de inventario (usada en /inventario)
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

-- ==============================================
-- MODULO NFC: CONSULTAS
-- ==============================================

-- Tarjetas NFC - detalle completo
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


-- Eventos de escaneo NFC - detalle completo
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
            se.nfc_scan_result                                 AS result,
            se.nfc_scan_result,

            -- Tarjeta
            nc.uid                                             AS card_uid,
            nc.status                                          AS card_status,

            -- Paciente (a traves de la tarjeta)
            nc.patient_id,
            TRIM(p.first_name || ' ' || p.last_name)          AS patient_name,
            DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT
                                                               AS patient_age,

            -- Trabajador que escaneo
            COALESCE(TRIM(w.first_name || ' ' || w.last_name), '-')
                                                               AS worker_name,
            COALESCE(TRIM(w.first_name || ' ' || w.last_name), '-')
                                                               AS scanned_by_name,

            -- Ubicacion
            c.name                                             AS clinic_name,
            COALESCE(ca.name, '-')                             AS area_name,

            -- Dispositivo
            COALESCE(nd.device_name, '-')                     AS device_name,
            nd.model                                           AS device_model,

            -- Clasificacion del resultado
            CASE
                WHEN se.nfc_scan_result ILIKE '%exito%'
                  OR se.nfc_scan_result ILIKE '%exitoso%'
                  OR se.nfc_scan_result ILIKE '%ok%'
                  OR se.nfc_scan_result ILIKE '%acceso%'
                THEN 'Exitoso'
                WHEN se.nfc_scan_result ILIKE '%error%'
                  OR se.nfc_scan_result ILIKE '%fallo%'
                  OR se.nfc_scan_result ILIKE '%rechaz%'
                  OR se.nfc_scan_result ILIKE '%denegado%'
                THEN 'Error'
                ELSE COALESCE(se.nfc_scan_result, '-')
            END                                                AS resultado_display

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


-- Historial de escaneos de una tarjeta especifica
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


-- ==============================================
-- MODULO NFC: MUTACIONES
-- ==============================================

-- Asignar tarjeta NFC a un paciente
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

    IF EXISTS (SELECT 1 FROM nfc_cards WHERE uid = TRIM(p_uid)) THEN
        RAISE EXCEPTION 'Ya existe una tarjeta con el UID %', p_uid;
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


-- Actualizar estado de una tarjeta NFC
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


-- Registrar evento de escaneo NFC
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

-- Clínicas completas (usada en /clinicas)
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
            COALESCE(
                mu.name || ', ' || st.name,
                '—'
            ) AS location
        FROM clinics c
        LEFT JOIN addresses  ad ON ad.address_id    = c.address_id
        LEFT JOIN municipalities mu ON mu.municipality_id = ad.municipality_id
        LEFT JOIN states     st ON st.state_id      = mu.state_id
        WHERE c.is_active = TRUE
        ORDER BY c.name;
END;
$$;

-- ============================================================
-- [CORREGIDO] sp_get_schema_alerts_full
-- CAMBIOS: usa sca.schedule_id (no scheme_dose_id) para obtener
--          vacuna y dosis. Agrega alert_type y read_at.
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


-- ==============================================
-- SPs DE MUTACIÓN FALTANTES
-- ==============================================

-- Eliminar vacuna (borrado lógico o físico)
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

-- Registrar trabajador
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

-- Actualizar trabajador
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
-- SP: sp_reportes_resumen
-- Devuelve KPIs, vacunas por período y resumen mensual
-- para el módulo de Reportes Públicos.
-- Uso: SELECT * FROM sp_reportes_resumen('2024-01-01', '2024-12-31');
-- ============================================================

CREATE OR REPLACE FUNCTION sp_reportes_resumen(
    p_from DATE,
    p_to   DATE
)
RETURNS TABLE (
    -- KPIs principales
    total_doses_applied         BIGINT,
    target_population           BIGINT,
    reached_population          BIGINT,
    coverage_percent            NUMERIC(5,1),
    avg_delay_days              NUMERIC(6,1),
    active_zones                BIGINT,
    reaction_rate               NUMERIC(5,1),
    completed_scheme            BIGINT,
    delayed_patients            BIGINT,
    appointment_completion_rate NUMERIC(5,1),
    low_stock_count             BIGINT,
    new_patients                BIGINT,
    active_workers              BIGINT,
    avg_temp_c                  NUMERIC(4,1),
    -- Serializado como JSON para vaccines y monthly
    vaccines                    JSON,
    monthly                     JSON,
    zones                       JSON
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
    v_avg_temp          NUMERIC(4,1);
    v_active_zones      BIGINT;
    v_vaccines_json     JSON;
    v_monthly_json      JSON;
    v_zones_json        JSON;
BEGIN

    -- ── Dosis aplicadas y pacientes únicos en el período ──────────────────────
    SELECT
        COUNT(*)                        INTO v_total_doses
    FROM vaccination_records
    WHERE applied_date BETWEEN p_from AND p_to;

    SELECT
        COUNT(DISTINCT patient_id)      INTO v_reached
    FROM vaccination_records
    WHERE applied_date BETWEEN p_from AND p_to;

    SELECT COUNT(*)                     INTO v_target
    FROM patients
    WHERE is_active = TRUE;

    v_coverage := CASE
        WHEN v_target > 0 THEN ROUND((v_reached::NUMERIC / v_target) * 100, 1)
        ELSE 0
    END;

    -- ── Temperatura promedio ──────────────────────────────────────────────────
    SELECT ROUND(AVG(patient_temp_c), 1) INTO v_avg_temp
    FROM vaccination_records
    WHERE applied_date BETWEEN p_from AND p_to
      AND patient_temp_c IS NOT NULL;

    -- ── Tasa de reacciones adversas ───────────────────────────────────────────
    SELECT CASE
        WHEN COUNT(*) > 0
        THEN ROUND(COUNT(*) FILTER (WHERE had_reaction = TRUE)::NUMERIC / COUNT(*) * 100, 1)
        ELSE 0
    END INTO v_reaction_rate
    FROM vaccination_records
    WHERE applied_date BETWEEN p_from AND p_to;

    -- ── Pacientes con esquema completo ────────────────────────────────────────
    -- Se considera completo quien no tiene ninguna dosis en estado 'Pendiente' o 'Atrasada'
    SELECT COUNT(DISTINCT patient_id) INTO v_completed_scheme
    FROM patients p
    WHERE is_active = TRUE
      AND NOT EXISTS (
          SELECT 1 FROM patient_vaccine_schedule pvs
          WHERE pvs.patient_id = p.patient_id
            AND pvs.status IN ('Pendiente', 'Atrasada')
      );

    -- ── Pacientes con vacunas atrasadas ───────────────────────────────────────
    SELECT COUNT(DISTINCT patient_id) INTO v_delayed_patients
    FROM patient_vaccine_schedule
    WHERE status = 'Atrasada';

    -- ── Tasa de cumplimiento de citas ─────────────────────────────────────────
    SELECT CASE
        WHEN COUNT(*) > 0
        THEN ROUND(
            COUNT(*) FILTER (WHERE appointment_status = 'Completada')::NUMERIC
            / COUNT(*) * 100, 1)
        ELSE NULL
    END INTO v_appt_rate
    FROM appointments
    WHERE scheduled_at::DATE BETWEEN p_from AND p_to;

    -- ── Lotes en stock bajo (≤ 10 unidades) ──────────────────────────────────
    SELECT COUNT(*) INTO v_low_stock
    FROM vaccine_lots
    WHERE quantity_available <= 10
      AND expiration_date >= CURRENT_DATE;

    -- ── Nuevos pacientes en el período ────────────────────────────────────────
    SELECT COUNT(*) INTO v_new_patients
    FROM patients
    WHERE created_at::DATE BETWEEN p_from AND p_to;

    -- ── Trabajadores activos que aplicaron en el período ──────────────────────
    SELECT COUNT(DISTINCT worker_id) INTO v_active_workers
    FROM vaccination_records
    WHERE applied_date BETWEEN p_from AND p_to;

    -- ── Retraso promedio (días entre due_date y applied_date) ──────────────────
    SELECT ROUND(AVG(
        EXTRACT(EPOCH FROM (vr.applied_date - pvs.due_date)) / 86400
    ), 1) INTO v_avg_delay
    FROM vaccination_records vr
    JOIN patient_vaccine_schedule pvs
      ON vr.patient_id = pvs.patient_id
     AND vr.scheme_dose_id = pvs.scheme_dose_id
    WHERE vr.applied_date BETWEEN p_from AND p_to
      AND vr.applied_date > pvs.due_date;

    -- ── Zonas activas (municipios con al menos una dosis en el período) ───────
    SELECT COUNT(DISTINCT a.neighborhood_id) INTO v_active_zones
    FROM vaccination_records vr
    JOIN clinics c   ON vr.clinic_id  = c.clinic_id
    JOIN addresses a ON c.address_id  = a.address_id
    WHERE vr.applied_date BETWEEN p_from AND p_to;

    -- ── JSON: vacunas (top 50 por dosis aplicadas) ────────────────────────────
    SELECT json_agg(t) INTO v_vaccines_json FROM (
        SELECT
            v.name                                          AS vaccine_name,
            COUNT(vr.record_id)                             AS doses_applied,
            COUNT(DISTINCT vr.patient_id)                   AS unique_patients,
            ROUND(
                COUNT(vr.record_id)::NUMERIC
                / NULLIF(v_total_doses, 0) * 100, 1
            )                                               AS share_percent
        FROM vaccination_records vr
        JOIN vaccines v ON vr.vaccine_id = v.vaccine_id
        WHERE vr.applied_date BETWEEN p_from AND p_to
        GROUP BY v.vaccine_id, v.name
        ORDER BY doses_applied DESC
        LIMIT 50
    ) t;

    -- ── JSON: resumen mensual ─────────────────────────────────────────────────
    SELECT json_agg(t ORDER BY t.period_label) INTO v_monthly_json FROM (
        SELECT
            TO_CHAR(applied_date, 'YYYY-MM')    AS period_label,
            COUNT(*)                             AS doses_applied,
            COUNT(DISTINCT patient_id)           AS unique_patients
        FROM vaccination_records
        WHERE applied_date BETWEEN p_from AND p_to
        GROUP BY TO_CHAR(applied_date, 'YYYY-MM')
    ) t;

    -- ── JSON: zonas (municipios) ──────────────────────────────────────────────
    SELECT json_agg(t ORDER BY t.doses_applied DESC) INTO v_zones_json FROM (
        SELECT
            m.name                              AS zone_name,
            COUNT(vr.record_id)                 AS doses_applied,
            COUNT(DISTINCT vr.patient_id)       AS unique_patients,
            CASE
                WHEN COUNT(DISTINCT vr.patient_id) >= 100 THEN 'low'
                WHEN COUNT(DISTINCT vr.patient_id) >= 30  THEN 'medium'
                ELSE 'high'
            END                                 AS risk_level,
            CASE
                WHEN COUNT(DISTINCT vr.patient_id) >= 100 THEN 'Bajo'
                WHEN COUNT(DISTINCT vr.patient_id) >= 30  THEN 'Medio'
                ELSE 'Alto'
            END                                 AS risk_label
        FROM vaccination_records vr
        JOIN clinics c         ON vr.clinic_id      = c.clinic_id
        JOIN addresses a       ON c.address_id       = a.address_id
        JOIN neighborhoods n   ON a.neighborhood_id  = n.neighborhood_id
        JOIN municipalities m  ON n.municipality_id  = m.municipality_id
        WHERE vr.applied_date BETWEEN p_from AND p_to
        GROUP BY m.municipality_id, m.name
    ) t;

    RETURN QUERY SELECT
        v_total_doses,
        v_target,
        v_reached,
        v_coverage,
        COALESCE(v_avg_delay, 0.0),
        v_active_zones,
        v_reaction_rate,
        v_completed_scheme,
        v_delayed_patients,
        v_appt_rate,
        v_low_stock,
        v_new_patients,
        v_active_workers,
        v_avg_temp,
        COALESCE(v_vaccines_json, '[]'::JSON),
        COALESCE(v_monthly_json,  '[]'::JSON),
        COALESCE(v_zones_json,    '[]'::JSON);

END;
$$;


-- ============================================================
-- ============================================================
--  NUEVOS SPs — ARQUITECTURA REFACTORIZADA
--  Separación: dominio médico / operativo / notificaciones
-- ============================================================
-- ============================================================

-- ============================================================
-- [NUEVO] sp_apply_vaccine
-- Punto de entrada único para registrar una vacuna aplicada.
-- Reemplaza a sp_register_vaccination_record con mejor semántica:
--   - Acepta appointment_id opcional
--   - Delega actualización de schedule al trigger 12
--   - Delega marcar cita Completada al trigger 15
--   - NO descuenta stock (lo hace trigger 4)
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
-- [NUEVO] sp_get_pending_doses
-- Vacunas pendientes (Pendiente + Atrasada) de un paciente,
-- con indicación de urgencia y cita activa si existe.
-- Reemplaza sp_get_pending_scheme_doses (que usaba CROSS JOIN).
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
-- [NUEVO] sp_dashboard_tutor
-- Dashboard completo para el portal del tutor:
--   - Todas las dosis pendientes/atrasadas de sus hijos
--   - Cita activa vinculada a cada dosis (si existe)
--   - action_state para el frontend (qué mostrar/qué botón)
-- ============================================================
-- [CORREGIDO] sp_dashboard_tutor
-- CAMBIOS vs version anterior:
--   1. patient_name  -> full_name        (alias que lee Flask)
--   2. cita_fecha    -> scheduled_at     (alias que lee Flask)
--   3. cita_status   -> appointment_status (alias que lee Flask)
--   4. days_overdue  -> dias_retraso     (alias que lee Flask)
--   5. KPIs por paciente via subquery escalar (total_applied, total_doses,
--      total_pending, delayed_count, pct) que Flask leia pero el SP no devolvía.
--      Se usa SUM(CASE WHEN...) en lugar de FILTER para maxima compatibilidad.
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
        WHERE  patient_schedule_id = pvs.schedule_id
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
-- [NUEVO] sp_dashboard_clinica
-- Agenda clínica real por fecha:
--   - Solo citas reales creadas manualmente
--   - Nunca muestra dosis del esquema futuras
--   - Admite filtro por clínica y fecha
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
-- [NUEVO] sp_refresh_overdue_statuses
-- Job nocturno: pasa Pendiente → Atrasada donde due_date < hoy.
-- Ejecutar vía pg_cron o apscheduler Flask cada noche.
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
-- [NUEVO] sp_generate_alerts
-- Genera alertas de proximidad (≤30 días) y de atraso
-- sin duplicar alertas ya existentes.
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


-- ============================================================
-- [NUEVO] sp_get_citas_admin
-- Vista de citas para el portal admin: rango de fechas, todas
-- las clinicas asignadas a la sesion. Reemplaza al uso de
-- sp_dashboard_clinica (que solo devuelve un dia) en /citas.
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
-- [NUEVO] sp_get_agenda_form_data
-- Carga todos los datos necesarios para el formulario de nueva
-- cita en el portal admin: pacientes activos, trabajadores de
-- la clinica y areas disponibles.
-- Tres REFCURSOR en una sola llamada → sin SQL embebido en Flask.
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
-- sp_get_appointment_detail
-- Devuelve todos los campos de una cita para pre-llenar el
-- formulario de edicion en el portal admin.
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
-- sp_update_appointment
-- Edicion completa de una cita existente por el personal admin.
-- Campos editables: worker, area, scheduled_at, reason,
-- appointment_notes, appointment_status, duration_min.
-- Valida solapamiento de trabajador excluyendo la cita actual.
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