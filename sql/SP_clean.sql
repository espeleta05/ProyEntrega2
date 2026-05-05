-- VER SPs EN POSTGRES
SELECT routine_name 
FROM information_schema.routines 
WHERE routine_type = 'PROCEDURE' 
AND routine_schema = 'public';

-- =====================================
-- WRAPPERS DE VISTAS
-- =====================================

-- (APLICADA) vw_patient
CREATE OR REPLACE PROCEDURE sp_get_patients(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT *
        FROM vw_patients
        ORDER BY patient_id;
END;
$$;

-- v_vaccination_records_full
CREATE OR REPLACE PROCEDURE sp_get_vaccination_records_full(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT *
        FROM v_vaccination_records_full
        ORDER BY applied_date DESC, record_id DESC;
END;
$$;


-- v_pending_scheme_doses (con filtro opcional por paciente)
CREATE OR REPLACE PROCEDURE sp_get_pending_scheme_doses(
    IN p_patient_id INT DEFAULT NULL,
    INOUT p_results
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            patient_id,
            vaccine_name,
            dose_label,
            ideal_age_months
        FROM v_pending_scheme_doses
        WHERE p_patient_id IS NULL OR patient_id = p_patient_id
        ORDER BY patient_id, ideal_age_months NULLS LAST, vaccine_name;
END;
$$;



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



-- v_delayed_patients (con umbral de días)
CREATE OR REPLACE PROCEDURE sp_delayed_patients(
    IN    p_days_threshold  INT DEFAULT 30,
    INOUT p_resultados      REFCURSOR

)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_resultados FOR
        SELECT *
        FROM v_delayed_patients
        WHERE days_late >= p_days_threshold
        ORDER BY days_late DESC;
END;
$$;


-- v_low_stock_items (filtro opcional por clínica)
CREATE OR REPLACE PROCEDURE sp_low_stock_items(
    IN    p_clinic_id   INT DEFAULT NULL,
    INOUT p_resultados  REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_resultados FOR
        SELECT inventory_id, clinic_name, supply_name, quantity, min_stock
        FROM v_low_stock_items
        WHERE p_clinic_id IS NULL OR clinic_id = p_clinic_id
        ORDER BY clinic_name, supply_name;
END;
$$;



-- v_inventory_status
CREATE OR REPLACE PROCEDURE sp_get_inventory_status(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT *
        FROM v_inventory_status
        ORDER BY clinic_name, supply_name;
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
    IN    p_guardian_phone   VARCHAR,
    INOUT p_results          REFCURSOR
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_guardian_id INT;
    v_patient_id  INT;
    v_age_years   INT;
BEGIN

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

    IF LENGTH(TRIM(p_curp)) <> 18 THEN
        RAISE EXCEPTION 'CURP invalida';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM patients
        WHERE curp = p_curp
    ) THEN
        RAISE EXCEPTION 'El CURP ya existe';
    END IF;

    IF p_weight_kg <= 0 OR p_weight_kg > 80 THEN
        RAISE EXCEPTION 'Peso fuera de rango pediatrico';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM blood_types
        WHERE blood_type_id = p_blood_type_id
    ) THEN
        RAISE EXCEPTION 'Tipo sanguineo inexistente';
    END IF;

    SELECT guardian_id
    INTO v_guardian_id
    FROM guardians
    WHERE first_name = p_guardian_name
    AND last_name = p_guardian_last
    LIMIT 1;

    IF v_guardian_id IS NULL THEN

        INSERT INTO guardians (
            first_name,
            last_name
        )
        VALUES (
            p_guardian_name,
            p_guardian_last
        )
        RETURNING guardian_id
        INTO v_guardian_id;

    END IF;

    IF p_guardian_phone IS NOT NULL THEN

        IF LENGTH(TRIM(p_guardian_phone)) < 10 THEN
            RAISE EXCEPTION 'Telefono invalido';
        END IF;

        INSERT INTO guardian_phones (
            guardian_id,
            phone,
            phone_type,
            is_primary
        )
        VALUES (
            v_guardian_id,
            p_guardian_phone,
            'Celular',
            TRUE
        );

    END IF;

    INSERT INTO patients (
        first_name,
        last_name,
        curp,
        birth_date,
        gender,
        blood_type_id,
        weight_kg,
        premature,
        created_at,
        is_active
    )
    VALUES (
        p_first_name,
        p_last_name,
        p_curp,
        p_birth_date,
        p_gender,
        p_blood_type_id,
        p_weight_kg,
        p_premature,
        NOW(),
        TRUE
    )
    RETURNING patient_id
    INTO v_patient_id;

    INSERT INTO patient_guardian_relations (
        patient_id,
        guardian_id,
        relation_type,
        is_primary,
        has_custody
    )
    VALUES (
        v_patient_id,
        v_guardian_id,
        'Tutor',
        TRUE,
        TRUE
    );

    OPEN p_results FOR
    SELECT
        TRUE AS success,
        'Paciente registrado correctamente' AS message,
        v_patient_id AS patient_id;

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
CALL sp_register_patient(
    'Diana',
    'Ross',
    'DIAR350503YGFERT06',
    '2025-05-12',
    'F',
    4,
    34.6,
    FALSE,
    'Mike',
    'Ross',
    '8110000019',
    'p_results'
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

LANGUAGE plpgsql AS $$

DECLARE

    v_record_id INT;

BEGIN

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

        had_reaction

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

        COALESCE(p_had_reaction, FALSE)

    )

    RETURNING vaccination_records.record_id INTO v_record_id;



    OPEN p_results FOR

        SELECT v_record_id AS record_id;

END;

$$;



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

-- FIN STORED PROCEDURES

-- ==============================================

