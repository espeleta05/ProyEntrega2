-- ==============================================
-- STORED PROCEDURES - Sistema de Vacunación
-- Consolidado: SP.sql + SP_nuevos_fase3.sql
-- ==============================================

-- ================================================
-- VISTAS - Para consultas enriquecidas y reportes
-- ================================================
-- 4. Obtener pacientes enriquecidos (wrapper de vista)
CREATE OR REPLACE FUNCTION sp_get_patients_full()
RETURNS SETOF v_patients_full
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT *
    FROM v_patients_full
    ORDER BY patient_id;
END;
$$;

-- 10. Obtener historial de vacunación enriquecido (wrapper de vista)
CREATE OR REPLACE FUNCTION sp_get_vaccination_records_full()
RETURNS SETOF v_vaccination_records_full
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT *
    FROM v_vaccination_records_full
    ORDER BY applied_date DESC, record_id DESC;
END;
$$;

-- 11. Obtener dosis pendientes (wrapper de vista)
CREATE OR REPLACE FUNCTION sp_get_pending_scheme_doses(p_patient_id INT DEFAULT NULL)
RETURNS TABLE (
    patient_id INT,
    vaccine_name VARCHAR,
    dose_label VARCHAR,
    ideal_age_months SMALLINT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        v.patient_id,
        v.vaccine_name,
        v.dose_label,
        v.ideal_age_months
    FROM v_pending_scheme_doses v
    WHERE p_patient_id IS NULL OR v.patient_id = p_patient_id
    ORDER BY v.patient_id, v.ideal_age_months NULLS LAST, v.vaccine_name;
END;
$$;

-- 16. Obtener citas enriquecidas (wrapper de vista)
CREATE OR REPLACE FUNCTION sp_get_appointments_full()
RETURNS SETOF v_appointments_full
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT *
    FROM v_appointments_full
    ORDER BY scheduled_at DESC;
END;
$$;


-- ==============================================
-- MÓDULO: PACIENTES (CRUD)
-- ==============================================

-- 1. Registrar nuevo paciente
CREATE OR REPLACE PROCEDURE sp_register_patient(
    IN    p_first_name     VARCHAR,
    IN    p_last_name      VARCHAR,
    IN    p_curp           VARCHAR,
    IN    p_birth_date     DATE,
    IN    p_gender         CHAR(1),
    IN    p_blood_type_id  INT,
    IN    p_weight_kg      NUMERIC,
    IN    p_premature      BOOLEAN,
    IN    p_guardian_name  VARCHAR,
    IN    p_guardian_last  VARCHAR,
    IN    p_guardian_phone VARCHAR,
    INOUT p_results     REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_guardian_id INT;
    v_patient_id  INT;
BEGIN
    -- 1. Insertar guardián
    INSERT INTO guardians (first_name, last_name)
    VALUES (p_guardian_name, p_guardian_last)
    RETURNING guardian_id INTO v_guardian_id;

    -- 2. Insertar teléfono del guardián
    IF p_guardian_phone IS NOT NULL THEN
        INSERT INTO guardian_phones (guardian_id, phone, phone_type, is_primary)
        VALUES (v_guardian_id, p_guardian_phone, 'Celular', TRUE);
    END IF;

    -- 3. Insertar paciente
    INSERT INTO patients (first_name, last_name, curp, birth_date, gender, blood_type_id, weight_kg, premature, created_at)
    VALUES (p_first_name, p_last_name, p_curp, p_birth_date, p_gender, COALESCE(p_blood_type_id, 1), p_weight_kg, p_premature, NOW())
    RETURNING patients.patient_id INTO v_patient_id;

    -- 4. Crear relación paciente-tutor
    INSERT INTO patient_guardian_relations (patient_id, guardian_id, relation_type, is_primary, has_custody)
    VALUES (v_patient_id, v_guardian_id, 'Tutor', TRUE, TRUE);

    OPEN p_results FOR
        SELECT v_patient_id AS patient_id;
END;
$$;

BEGIN ;
CALL
sp_register_patient(
    'Juan', 
    'Pérez', 
    'JUAP850101HDFRRL09', 
    '2024-01-01', 
    'M', 
    2, 
    75.5, 
    FALSE,
    'María', 
    'Pérez', 
    '8110000016',
    'p_results'
);
FETCH ALL FROM p_results;
COMMIT ;


-- 2. Actualizar paciente
CREATE OR REPLACE PROCEDURE sp_update_patient(
    IN    p_patient_id     INT,
    IN    p_first_name     VARCHAR,
    IN    p_last_name      VARCHAR,
    IN    p_blood_type_id  INT,
    IN    p_weight_kg      NUMERIC,
    INOUT p_results        REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE patients SET
        first_name    = COALESCE(p_first_name, first_name),
        last_name     = COALESCE(p_last_name, last_name),
        blood_type_id = COALESCE(p_blood_type_id, blood_type_id),
        weight_kg     = COALESCE(p_weight_kg, weight_kg)
    WHERE patient_id = p_patient_id;

    OPEN p_results FOR
        SELECT FOUND AS success;
END;
$$;

BEGIN ; 
CALL
sp_update_patient(
    16,
    'Juan',
    'Pérez',
    2,
    80.0,
    'p_results'
);
FETCH ALL FROM p_results;
COMMIT ;

-- 3. Eliminar paciente (cascada controlada)
CREATE OR REPLACE PROCEDURE sp_delete_patient(
    IN    p_patient_id  INT,
    INOUT p_results     REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    -- Eliminar en orden de dependencias (FKs)
    DELETE FROM patient_allergies WHERE patient_id = p_patient_id;
    DELETE FROM patient_guardian_relations WHERE patient_id = p_patient_id;
    DELETE FROM scheme_completion_alerts WHERE patient_id = p_patient_id;
    DELETE FROM nfc_scan_events WHERE nfc_card_id IN
        (SELECT nfc_card_id FROM nfc_cards WHERE patient_id = p_patient_id);
    DELETE FROM nfc_cards WHERE patient_id = p_patient_id;
    DELETE FROM appointments WHERE patient_id = p_patient_id;
    DELETE FROM post_vaccine_reactions WHERE vaccination_record_id IN
        (SELECT record_id FROM vaccination_records WHERE patient_id = p_patient_id);
    DELETE FROM vaccination_records WHERE patient_id = p_patient_id;
    DELETE FROM patients WHERE patient_id = p_patient_id;

    OPEN p_results FOR
        SELECT FOUND AS success;
END;
$$;

-- 5. Calcular adherencia del paciente al esquema
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

-- ==============================================
-- MÓDULO: VACUNAS (CRUD)
-- ==============================================

-- 6. Registrar vacuna
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

-- 7. Crear lote de vacunas
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

-- 8. Actualizar stock de lote
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
-- MÓDULO: VACUNACIÓN (REGISTROS)
-- ==============================================

-- 9. Registrar aplicación de vacuna
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

-- 12. Registrar reacción adversa post-vacunación
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

-- 13. Crear cita
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

-- 14. Actualizar estado de cita
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

-- 15. Eliminar cita
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
-- MÓDULO: AUTENTICACIÓN
-- ==============================================

-- 17. Autenticar trabajador (valida username/email + password con bcrypt)
CREATE OR REPLACE PROCEDURE sp_authenticate_worker(
    IN    p_login       VARCHAR,   -- acepta username O email
    IN    p_password    VARCHAR,
    INOUT p_results     REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            w.worker_id,
            r.name                                  AS role_name,
            CONCAT(w.first_name, ' ', w.last_name)  AS full_name,
            we.email
        FROM workers w
        JOIN roles r ON w.role_id = r.role_id
        LEFT JOIN worker_emails we ON we.worker_id = w.worker_id AND we.is_primary = TRUE
        WHERE (
            LOWER(COALESCE(we.email, '')) = LOWER(p_login)
            OR LOWER(w.username) = LOWER(p_login)
        )
        LIMIT 1;
END;
$$;

-- ==============================================
-- MÓDULO: REPORTERÍA Y MÉTRICAS
-- ==============================================

-- 18. Obtener métricas del dashboard (wrapper de vista, con filtro opcional)
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
                COUNT(DISTINCT p.patient_id)::BIGINT                                                          AS total_patients,
                COUNT(DISTINCT vr.patient_id)::BIGINT                                                         AS vaccinated_patients,
                COUNT(DISTINCT a.appointment_id)   FILTER (WHERE a.appointment_status = 'Programada')::BIGINT AS pending_appointments,
                COUNT(DISTINCT ci.inventory_id)    FILTER (WHERE ci.quantity < ci.min_stock)::BIGINT           AS low_stock_items,
                COUNT(DISTINCT sca.alert_id)       FILTER (WHERE sca.status  = 'Pendiente')::BIGINT            AS pending_alerts,
                ROUND(
                    COUNT(DISTINCT vr.patient_id)::NUMERIC /
                    NULLIF(COUNT(DISTINCT p.patient_id)::NUMERIC, 0) * 100, 2
                )::NUMERIC                                                                                     AS coverage_percentage
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

-- 19. Obtener pacientes retrasados (wrapper de vista, con umbral de días)
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

-- 20. Obtener insumos con bajo stock (wrapper de vista, con filtro opcional)
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

-- 21. Obtener alertas pendientes
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

-- 22. Búsqueda global unificada
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
-- MÓDULO: INVENTARIO
-- ==============================================

-- 23. Obtener status de inventario (wrapper de vista)
CREATE OR REPLACE FUNCTION sp_get_inventory_status()
RETURNS SETOF v_inventory_status
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT *
    FROM v_inventory_status
    ORDER BY clinic_name, supply_name;
END;
$$;

-- ==============================================
-- MÓDULO: DATOS DINÁMICOS PARA FORMULARIOS
-- ==============================================

-- 24. Obtener tipos de sangre
CREATE OR REPLACE PROCEDURE sp_get_blood_types(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT blood_type_id, blood_type FROM blood_types ORDER BY blood_type_id;
END;
$$;

-- 25. Obtener fabricantes de vacunas
CREATE OR REPLACE PROCEDURE sp_get_manufacturers(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT manufacturer_id, name FROM manufacturers ORDER BY name;
END;
$$;

-- 26. Obtener vías de administración
CREATE OR REPLACE PROCEDURE sp_get_vaccine_vias(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT via_id, via FROM vaccine_vias ORDER BY via;
END;
$$;

-- 27. Obtener roles
CREATE OR REPLACE PROCEDURE sp_get_roles(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT role_id, name FROM roles ORDER BY name;
END;
$$;

-- 28. Obtener clínicas
CREATE OR REPLACE PROCEDURE sp_get_clinics(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT clinic_id, name FROM clinics WHERE is_active = TRUE ORDER BY name;
END;
$$;

-- 29. Obtener trabajadores para dropdown
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

-- 30. Obtener lotes disponibles de una vacuna
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

-- 31. Obtener sitios de aplicación
CREATE OR REPLACE PROCEDURE sp_get_application_sites(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT application_site_id, application_site FROM application_sites ORDER BY application_site;
END;
$$;

-- 32. Obtener países
CREATE OR REPLACE PROCEDURE sp_get_countries(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT country_id, name, iso_code FROM countries ORDER BY name;
END;
$$;

-- 33. Obtener estados por país
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

-- 34. Obtener municipios por estado
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
