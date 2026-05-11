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

CREATE OR REPLACE PROCEDURE sp_dashboard_kpis(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR 
        SELECT * FROM vw_dashboard_kpis;
END ;
$$ ;

BEGIN;
CALL sp_dashboard_kpis('p_results');
FETCH ALL FROM p_results;
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

-- v_dashboard_metrics (sin fechas) + recálculo acotado si hay rango

CREATE OR REPLACE PROCEDURE sp_dashboard_metrics(
    IN    p_date_from   DATE DEFAULT NULL,
    IN    p_date_to     DATE DEFAULT NULL,
    INOUT p_resultados  REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    IF p_date_from IS NULL AND p_date_to IS NULL THEN
        -- Sin filtro: usar directamente la vista
        OPEN p_resultados FOR
            SELECT * FROM v_dashboard_metrics;
    ELSE
        -- Con filtro de fechas: recalcular solo vaccination_records acotado
        OPEN p_resultados FOR
            SELECT
                COUNT(DISTINCT p.patient_id)::BIGINT AS total_patients,
                COUNT(DISTINCT vr.patient_id)::BIGINT AS vaccinated_patients,
                COUNT(DISTINCT a.appointment_id)   FILTER (WHERE a.appointment_status = 'Programada')::BIGINT AS pending_appointments,
                COUNT(DISTINCT ci.inventory_id)    FILTER (WHERE ci.quantity < ci.min_stock)::BIGINT AS low_stock_items,
                COUNT(DISTINCT sca.alert_id)       FILTER (WHERE sca.status  = 'Pendiente')::BIGINT AS pending_alerts,
                ROUND(
                    COUNT(DISTINCT vr.patient_id)::NUMERIC /
                    NULLIF(COUNT(DISTINCT p.patient_id)::NUMERIC, 0) * 100, 2
                )::NUMERIC  AS coverage_percentage
            FROM patients p
            LEFT JOIN vaccination_records vr  ON p.patient_id = vr.patient_id
                AND vr.applied_date >= p_date_from
                AND vr.applied_date <= p_date_to
            LEFT JOIN appointments a ON p.patient_id = a.patient_id
            LEFT JOIN clinic_inventory ci ON ci.quantity   < ci.min_stock
            LEFT JOIN scheme_completion_alerts sca ON p.patient_id  = sca.patient_id;
    END IF;
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

    -- ── Validaciones del paciente ─────────────────────────────────────────

    IF TRIM(p_first_name) = '' THEN
        RAISE EXCEPTION 'El nombre es obligatorio';
    END IF;

    IF TRIM(p_last_name) = '' THEN
        RAISE EXCEPTION 'El apellido es obligatorio';
    END IF;

    IF p_birth_date > CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha de nacimiento no puede ser futura';
    END IF;

    v_age_years := DATE_PART('year', AGE(CURRENT_DATE, p_birth_date));

    IF v_age_years > 10 THEN
        RAISE EXCEPTION 'El paciente excede la edad pediatrica permitida';
    END IF;

    IF p_gender NOT IN ('M', 'F') THEN
        RAISE EXCEPTION 'Genero invalido';
    END IF;

    IF p_curp IS NOT NULL AND LENGTH(TRIM(p_curp)) <> 18 THEN
        RAISE EXCEPTION 'CURP invalida';
    END IF;

    IF p_curp IS NOT NULL AND EXISTS (
        SELECT 1 FROM patients WHERE curp = p_curp
    ) THEN
        RAISE EXCEPTION 'El CURP ya existe';
    END IF;

    IF p_weight_kg IS NOT NULL AND (p_weight_kg <= 0 OR p_weight_kg > 80) THEN
        RAISE EXCEPTION 'Peso fuera de rango pediatrico';
    END IF;

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
            IF LENGTH(TRIM(p_guardian_phone)) < 10 THEN
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

    OPEN p_results FOR
        SELECT TRUE  AS success,
               'Paciente registrado correctamente' AS message,
               v_patient_id  AS patient_id,
               v_guardian_id AS guardian_id;

EXCEPTION
WHEN OTHERS THEN
    OPEN p_results FOR
        SELECT FALSE AS success,
               SQLERRM   AS message,
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


-- (APPLICADO) Actualizar paciente
CREATE OR REPLACE PROCEDURE sp_update_patient(
    IN    p_patient_id      INT,
    IN    p_first_name      VARCHAR,
    IN    p_last_name       VARCHAR,
    IN    p_blood_type_id   INT,
    IN    p_weight_kg       NUMERIC,
    INOUT p_results         REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_exists BOOLEAN;
BEGIN
    
    SELECT EXISTS(
        SELECT 1
        FROM patients
        WHERE patient_id = p_patient_id
        AND is_active = TRUE
    )
    INTO v_exists;

    IF NOT v_exists THEN
        RAISE EXCEPTION 'El paciente no existe o esta inactivo';
    END IF;

    IF p_first_name IS NOT NULL THEN
        IF LENGTH(TRIM(p_first_name)) < 2 THEN
            RAISE EXCEPTION 'Nombre invalido';
        END IF;
    END IF;

    IF p_last_name IS NOT NULL THEN
        IF LENGTH(TRIM(p_last_name)) < 2 THEN
            RAISE EXCEPTION 'Apellido invalido';
        END IF;
    END IF;

    IF p_weight_kg IS NOT NULL THEN

        IF p_weight_kg <= 0 OR p_weight_kg > 80 THEN
            RAISE EXCEPTION 'Peso fuera de rango pediatrico';
        END IF;

    END IF;

    IF p_blood_type_id IS NOT NULL THEN

        IF NOT EXISTS (
            SELECT 1
            FROM blood_types
            WHERE blood_type_id = p_blood_type_id
        ) THEN
            RAISE EXCEPTION 'Tipo sanguineo inexistente';
        END IF;

    END IF;

    UPDATE patients
    SET
        first_name = COALESCE(NULLIF(TRIM(p_first_name), ''), first_name),
        last_name = COALESCE(NULLIF(TRIM(p_last_name), ''), last_name),
        blood_type_id = COALESCE(
            p_blood_type_id,
            blood_type_id
        ),
        weight_kg = COALESCE(
            p_weight_kg,
            weight_kg
        ),
        updated_at = NOW()
    WHERE patient_id = p_patient_id;

    OPEN p_results FOR
    SELECT
        TRUE AS success,
        'Paciente actualizado correctamente' AS message,
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
        FROM appointments
        WHERE patient_id = p_patient_id
        AND scheduled_at >= CURRENT_DATE
        AND appointment_status NOT IN ('Cancelada', 'Completada')
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
LANGUAGE plpgsql AS $$
DECLARE
    v_exists BOOLEAN;
BEGIN
 
    -- -------------------------------------------------------------------------
    -- Validación 1: el paciente debe existir
    -- -------------------------------------------------------------------------
    SELECT EXISTS(
        SELECT 1 FROM patients
        WHERE patient_id = p_patient_id
    )
    INTO v_exists;
 
    IF NOT v_exists THEN
        RAISE EXCEPTION 'El paciente con ID % no existe', p_patient_id;
    END IF;
 
    -- -------------------------------------------------------------------------
    -- Validación 2: el paciente debe estar activo
    -- -------------------------------------------------------------------------
    SELECT EXISTS(
        SELECT 1 FROM patients
        WHERE patient_id = p_patient_id
          AND is_active = TRUE
    )
    INTO v_exists;
 
    IF NOT v_exists THEN
        RAISE EXCEPTION 'El paciente con ID % está inactivo', p_patient_id;
    END IF;
 
    OPEN p_results FOR
    SELECT
        -- Identificadores
        patient_id,
        dose_id,
        vaccine_id,
        record_id,
 
        -- Paciente
        full_name,
        birth_date,
        age_years,
 
        -- Vacuna / dosis
        vaccine_name                                     AS name,
        disease_prevented,
        dose_label                                       AS dose,
        dose_number,
        ideal_age_months,
        ideal_date,
 
        -- Aplicación
        applied_date                                     AS date,
        doctor,
        application_site,
        had_reaction,
        patient_temp_c,
 
        -- Estado
        estado,
        dias_retraso,
 
        -- Próxima dosis de la misma vacuna
        CASE
            WHEN next_dose_age_months IS NOT NULL THEN
                'A los ' || next_dose_age_months || ' meses'
            ELSE NULL
        END                                              AS next_date,
 
        -- Etiqueta de edad ideal legible
        CASE
            WHEN ideal_age_months = 0  THEN 'Al nacer'
            WHEN ideal_age_months >= 12 THEN
                (ideal_age_months / 12) || ' año(s)'
            ELSE
                ideal_age_months || ' meses'
        END                                              AS edad_ideal_label,
 
        -- Alerta de retraso
        CASE
            WHEN record_id IS NULL AND dias_retraso > 0 THEN
                'Retraso de ' || dias_retraso || ' días'
            WHEN record_id IS NULL AND dias_retraso <= 0 THEN
                'Programada en ' || ABS(dias_retraso) || ' días'
            ELSE NULL
        END                                              AS alerta_retraso
 
    FROM v_patient_vaccination_scheme_base
    WHERE patient_id = p_patient_id
    ORDER BY ideal_age_months, dose_number;
END;
$$;
 

BEGIN;
CALL sp_get_patient_scheme(1, 'cur_esquema');
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
        quantity_received, quantity_available, expiration_date, received_date
    )
    VALUES (
        p_vaccine_id, p_clinic_id, p_lot_number,
        p_quantity_received, p_quantity_received, p_expiration_date, NOW()::DATE
    )
    RETURNING vaccine_lots.lot_id INTO v_lot_id;

    OPEN p_results FOR
        SELECT v_lot_id AS lot_id;
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


CREATE OR REPLACE PROCEDURE sp_record_vaccine_reaction(
    IN    p_vaccination_record_id  INT,
    IN    p_reaction_desc          TEXT,
    IN    p_severity               VARCHAR,
    INOUT p_results                REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_reaction_id INT;
BEGIN
    INSERT INTO post_vaccine_reactions (
        vaccination_record_id, reaction_description, severity, reported_at
    )

    VALUES (
        p_vaccination_record_id, p_reaction_desc, p_severity, NOW()
    )
    RETURNING post_vaccine_reactions.reaction_id INTO v_reaction_id;

    OPEN p_results FOR
        SELECT v_reaction_id AS reaction_id;
END;
$$;


-- ==============================================

-- MÓDULO: CITAS (CRUD)

-- ==============================================



CREATE OR REPLACE PROCEDURE sp_create_appointment(
    IN    p_patient_id    INT,
    IN    p_worker_id     INT,
    IN    p_clinic_id     INT,
    IN    p_area_id       INT,
    IN    p_scheduled_at  TIMESTAMP,
    IN    p_reason        VARCHAR,
    INOUT p_results       REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_appointment_id INT;
BEGIN
    INSERT INTO appointments (
        patient_id, worker_id, clinic_id, area_id,
        scheduled_at, appointment_status, reason, duration_min
    )

    VALUES (
        p_patient_id, p_worker_id, p_clinic_id, p_area_id,
        p_scheduled_at, 'Programada', p_reason, 15
    )
    RETURNING appointments.appointment_id INTO v_appointment_id;

    OPEN p_results FOR
        SELECT v_appointment_id AS appointment_id;
END;
$$;



CREATE OR REPLACE PROCEDURE sp_update_appointment(

    IN    p_appointment_id INT,

    IN    p_status         VARCHAR,

    INOUT p_results        REFCURSOR

)

LANGUAGE plpgsql AS $$

BEGIN

    UPDATE appointments SET

        appointment_status = p_status

    WHERE appointment_id = p_appointment_id;



    OPEN p_results FOR

        SELECT FOUND AS success WHERE p_status IN ('Programada', 'Completada', 'Cancelada');

END;

$$;



CREATE OR REPLACE PROCEDURE sp_delete_appointment(

    IN    p_appointment_id INT,

    INOUT p_results        REFCURSOR

)

LANGUAGE plpgsql AS $$

BEGIN

    DELETE FROM appointments WHERE appointment_id = p_appointment_id;

    OPEN p_results FOR

        SELECT FOUND AS success;

END;

$$;





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



CREATE OR REPLACE PROCEDURE sp_global_search(

    IN    p_query   VARCHAR,

    INOUT p_results REFCURSOR

)

LANGUAGE plpgsql AS $$

BEGIN

    OPEN p_results FOR

    SELECT

        patient_id AS id,

        full_name AS name,

        'patient' AS type,

        birth_date::text AS metadata

    FROM v_patients_full

    WHERE full_name ILIKE '%' || p_query || '%' OR curp ILIKE '%' || p_query || '%'



    UNION ALL



    SELECT

        worker_id AS id,

        (first_name || ' ' || last_name) AS name,

        'worker' AS type,

        NULL AS metadata

    FROM workers

    WHERE (first_name || ' ' || last_name) ILIKE '%' || p_query || '%'



    UNION ALL



    SELECT

        vaccine_id AS id,

        name AS name,

        'vaccine' AS type,

        NULL AS metadata

    FROM vaccines

    WHERE name ILIKE '%' || p_query || '%' OR commercial_name ILIKE '%' || p_query || '%'



    UNION ALL



    SELECT

        clinic_id AS id,

        name AS name,

        'clinic' AS type,

        NULL AS metadata

    FROM clinics

    WHERE name ILIKE '%' || p_query || '%'



    ORDER BY type, name

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

-- Esquema de un paciente (alias de sp_get_patient_scheme)
CREATE OR REPLACE PROCEDURE sp_get_esquema_paciente(
    IN    p_patient_id INT,
    INOUT p_results    REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_exists BOOLEAN;
BEGIN
    SELECT EXISTS(SELECT 1 FROM patients WHERE patient_id = p_patient_id AND is_active = TRUE)
    INTO v_exists;
    IF NOT v_exists THEN
        RAISE EXCEPTION 'Paciente % no encontrado o inactivo', p_patient_id;
    END IF;

    OPEN p_results FOR
        SELECT
            patient_id, dose_id, vaccine_id, record_id,
            full_name, birth_date, age_years,
            vaccine_name AS name,
            disease_prevented,
            dose_label   AS dose,
            dose_number,
            ideal_age_months,
            ideal_date,
            applied_date AS date,
            doctor,
            application_site,
            had_reaction,
            patient_temp_c,
            estado,
            dias_retraso,
            CASE
                WHEN next_dose_age_months IS NOT NULL
                    THEN 'A los ' || next_dose_age_months || ' meses'
                ELSE NULL
            END AS next_date,
            CASE
                WHEN ideal_age_months = 0  THEN 'Al nacer'
                WHEN ideal_age_months >= 12 THEN (ideal_age_months / 12) || ' año(s)'
                ELSE ideal_age_months || ' meses'
            END AS edad_ideal_label,
            CASE
                WHEN record_id IS NULL AND dias_retraso > 0
                    THEN 'Retraso de ' || dias_retraso || ' días'
                WHEN record_id IS NULL AND dias_retraso <= 0
                    THEN 'Programada en ' || ABS(dias_retraso) || ' días'
                ELSE NULL
            END AS alerta_retraso
        FROM v_patient_vaccination_scheme_base
        WHERE patient_id = p_patient_id
        ORDER BY ideal_age_months, dose_number;
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

-- Alertas de esquema completas (usada en /api/alertas-esquema)
CREATE OR REPLACE PROCEDURE sp_get_schema_alerts_full(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            sca.alert_id,
            sca.patient_id,
            sca.scheme_dose_id,
            sca.due_date,
            sca.status,
            sca.notified_at,
            TRIM(p.first_name || ' ' || p.last_name) AS patient_name,
            v.name    AS vaccine_name,
            sd.dose_label
        FROM scheme_completion_alerts sca
        JOIN patients     p  ON p.patient_id  = sca.patient_id
        JOIN scheme_doses sd ON sd.dose_id    = sca.scheme_dose_id
        JOIN vaccines     v  ON v.vaccine_id  = sd.vaccine_id
        ORDER BY sca.due_date;
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