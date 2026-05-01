-- ==============================================
-- Stored Procedures Adicionales - FASE 3
-- SPs críticos para CRUD + Autenticación
-- ==============================================

-- CRUD PACIENTES
-- 9. Crear un nuevo paciente (simplificado)
CREATE OR REPLACE PROCEDURE sp_create_patient(
    p_first_name     VARCHAR,
    p_last_name      VARCHAR,
    p_birth_date     DATE,
    p_blood_type_id  INT,
    p_gender         CHAR(1),
    p_curp           VARCHAR,
    p_weight_kg      NUMERIC,
    p_premature      BOOLEAN
)
RETURNS TABLE (patient_id INT)
LANGUAGE plpgsql
AS $$
DECLARE
    v_patient_id INT;
BEGIN
    INSERT INTO patients (
        first_name, last_name, birth_date, blood_type_id,
        gender, curp, weight_kg, premature, created_at
    )
    VALUES (
        p_first_name, p_last_name, p_birth_date, p_blood_type_id,
        p_gender, p_curp, p_weight_kg, p_premature, NOW()
    )
    RETURNING patients.patient_id INTO v_patient_id;

    RETURN QUERY SELECT v_patient_id;
END;
$$;


-- 10. Actualizar paciente
CREATE OR REPLACE PROCEDURE sp_update_patient(
    p_patient_id     INT,
    p_first_name     VARCHAR,
    p_last_name      VARCHAR,
    p_blood_type_id  INT,
    p_weight_kg      NUMERIC
)
RETURNS TABLE (success BOOLEAN)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE patients SET
        first_name = COALESCE(p_first_name, first_name),
        last_name = COALESCE(p_last_name, last_name),
        blood_type_id = COALESCE(p_blood_type_id, blood_type_id),
        weight_kg = COALESCE(p_weight_kg, weight_kg)
    WHERE patient_id = p_patient_id;

    RETURN QUERY SELECT FOUND;
END;
$$;


-- 11. Eliminar paciente (cascada controlada)
CREATE OR REPLACE PROCEDURE sp_delete_patient(p_patient_id INT)
RETURNS TABLE (success BOOLEAN)
LANGUAGE plpgsql
AS $$
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

    RETURN QUERY SELECT FOUND;
END;
$$;


-- 12. Obtener un paciente por ID
CREATE OR REPLACE PROCEDURE sp_get_patient(p_patient_id INT)
RETURNS SETOF v_patients_full
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT * FROM v_patients_full
    WHERE patient_id = p_patient_id;
END;
$$;


-- CRUD CITAS
-- 13. Crear cita
CREATE OR REPLACE PROCEDURE sp_create_appointment(
    p_patient_id    INT,
    p_worker_id     INT,
    p_clinic_id     INT,
    p_area_id       INT,
    p_scheduled_at  TIMESTAMP,
    p_reason        VARCHAR
)
RETURNS TABLE (appointment_id INT)
LANGUAGE plpgsql
AS $$
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

    RETURN QUERY SELECT v_appointment_id;
END;
$$;


-- 14. Actualizar estado de cita
CREATE OR REPLACE PROCEDURE sp_update_appointment(
    p_appointment_id INT,
    p_status         VARCHAR
)
RETURNS TABLE (success BOOLEAN)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE appointments SET
        appointment_status = p_status
    WHERE appointment_id = p_appointment_id;

    RETURN QUERY SELECT FOUND;
END;
$$;


-- 15. Eliminar cita
CREATE OR REPLACE PROCEDURE sp_delete_appointment(p_appointment_id INT)
RETURNS TABLE (success BOOLEAN)
LANGUAGE plpgsql
AS $$
BEGIN
    DELETE FROM appointments WHERE appointment_id = p_appointment_id;
    RETURN QUERY SELECT FOUND;
END;
$$;


-- CRUD VACUNAS
-- 16. Crear lote de vacunas
CREATE OR REPLACE PROCEDURE sp_create_vaccine_lot(
    p_vaccine_id           INT,
    p_clinic_id            INT,
    p_lot_number           VARCHAR,
    p_quantity_received    INT,
    p_expiration_date      DATE
)
RETURNS TABLE (lot_id INT)
LANGUAGE plpgsql
AS $$
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

    RETURN QUERY SELECT v_lot_id;
END;
$$;


-- 17. Actualizar stock de lote
CREATE OR REPLACE PROCEDURE sp_update_vaccine_lot_stock(
    p_lot_id             INT,
    p_quantity_available INT
)
RETURNS TABLE (success BOOLEAN)
LANGUAGE plpgsql
AS $$
BEGIN
    UPDATE vaccine_lots SET
        quantity_available = p_quantity_available
    WHERE lot_id = p_lot_id;

    RETURN QUERY SELECT FOUND;
END;
$$;


-- 18. Registrar reacción adversa post-vacunación
CREATE OR REPLACE PROCEDURE sp_record_vaccine_reaction(
    p_vaccination_record_id INT,
    p_reaction_desc         TEXT,
    p_severity              VARCHAR
)
RETURNS TABLE (reaction_id INT)
LANGUAGE plpgsql
AS $$
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

    RETURN QUERY SELECT v_reaction_id;
END;
$$;


-- AUTENTICACIÓN
-- 19. Autenticar trabajador (usa bcrypt)
CREATE OR REPLACE PROCEDURE sp_authenticate_worker(
    p_email      VARCHAR,
    p_password   VARCHAR
)
RETURNS TABLE (
    worker_id   INT,
    role_name   VARCHAR,
    full_name   VARCHAR
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        w.worker_id,
        r.name,
        CONCAT(w.first_name, ' ', w.last_name)
    FROM worker_emails we
    JOIN workers w ON we.worker_id = w.worker_id
    JOIN roles r ON w.role_id = r.role_id
    WHERE we.email = p_email
      AND w.password_hash = crypt(p_password, w.password_hash)
    LIMIT 1;
END;
$$;


-- ALERTAS
-- 20. Obtener alertas pendientes
CREATE OR REPLACE PROCEDURE sp_get_pending_alerts()
RETURNS TABLE (alert_id INT, patient_id INT, due_date DATE, status VARCHAR)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT * FROM scheme_completion_alerts
    WHERE status = 'Pendiente'
    ORDER BY due_date ASC;
END;
$$;


-- REPORTERÍA / MÉTRICAS
-- 21. Obtener métricas del dashboard (simplificado)
CREATE OR REPLACE PROCEDURE sp_dashboard_metrics(
    p_date_from DATE DEFAULT NULL,
    p_date_to   DATE DEFAULT NULL
)
RETURNS TABLE (
    total_patients           BIGINT,
    vaccinated_patients      BIGINT,
    pending_appointments     BIGINT,
    low_stock_items          BIGINT,
    pending_alerts           BIGINT,
    coverage_percentage      NUMERIC
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(DISTINCT p.patient_id)::BIGINT,
        COUNT(DISTINCT vr.patient_id)::BIGINT,
        COUNT(DISTINCT a.appointment_id) FILTER (WHERE a.appointment_status = 'Programada')::BIGINT,
        COUNT(DISTINCT ci.inventory_id) FILTER (WHERE ci.quantity < ci.min_stock)::BIGINT,
        COUNT(DISTINCT sca.alert_id) FILTER (WHERE sca.status = 'Pendiente')::BIGINT,
        ROUND(
            COUNT(DISTINCT vr.patient_id)::NUMERIC /
            NULLIF(COUNT(DISTINCT p.patient_id)::NUMERIC, 0) * 100, 2
        )::NUMERIC
    FROM patients p
    LEFT JOIN vaccination_records vr ON p.patient_id = vr.patient_id
        AND (p_date_from IS NULL OR vr.applied_date >= p_date_from)
        AND (p_date_to IS NULL OR vr.applied_date <= p_date_to)
    LEFT JOIN appointments a ON p.patient_id = a.patient_id
    LEFT JOIN clinic_inventory ci ON ci.quantity < ci.min_stock
    LEFT JOIN scheme_completion_alerts sca ON p.patient_id = sca.patient_id;
END;
$$;


-- 22. Obtener pacientes retrasados
CREATE OR REPLACE PROCEDURE sp_delayed_patients(p_days_threshold INT DEFAULT 30)
RETURNS TABLE (
    patient_id  INT,
    patient_name VARCHAR,
    vaccine_name VARCHAR,
    due_date    DATE,
    days_late   INT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.patient_id,
        CONCAT(p.first_name, ' ', p.last_name),
        v.name,
        sca.due_date,
        (NOW()::DATE - sca.due_date)::INT
    FROM patients p
    JOIN scheme_completion_alerts sca ON p.patient_id = sca.patient_id
    JOIN scheme_doses sd ON sca.scheme_dose_id = sd.dose_id
    JOIN vaccines v ON sd.vaccine_id = v.vaccine_id
    WHERE sca.status = 'Pendiente'
      AND (NOW()::DATE - sca.due_date) >= p_days_threshold
    ORDER BY (NOW()::DATE - sca.due_date) DESC;
END;
$$;


-- 23. Obtener insumos con bajo stock
CREATE OR REPLACE PROCEDURE sp_low_stock_items(p_clinic_id INT DEFAULT NULL)
RETURNS TABLE (
    inventory_id INT,
    clinic_name  VARCHAR,
    supply_name  VARCHAR,
    quantity     INT,
    min_stock    INT
)
LANGUAGE plpgsql
AS $$
BEGIN
    RETURN QUERY
    SELECT
        ci.inventory_id,
        c.name,
        sc.name,
        ci.quantity,
        ci.min_stock
    FROM clinic_inventory ci
    JOIN clinics c ON ci.clinic_id = c.clinic_id
    JOIN supply_catalog sc ON ci.supply_id = sc.supply_id
    WHERE ci.quantity < ci.min_stock
      AND (p_clinic_id IS NULL OR c.clinic_id = p_clinic_id)
    ORDER BY c.name, sc.name;
END;
$$;
