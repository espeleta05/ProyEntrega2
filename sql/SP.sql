-- ==============================================
-- Stored Procedures
--===============================================

--  1. Registrar a un nuevo paciente
CREATE OR REPLACE FUNCTION sp_register_patient(
    p_first_name     VARCHAR,
    p_last_name      VARCHAR,
    p_curp           VARCHAR,
    p_birth_date     DATE,
    p_gender         CHAR(1),
    p_weight_kg      NUMERIC,
    p_premature      BOOLEAN,
    p_guardian_name  VARCHAR,
    p_guardian_last  VARCHAR,
    p_guardian_phone VARCHAR
)
RETURNS TABLE (patient_id INT)
LANGUAGE plpgsql AS $$
DECLARE
    v_guardian_id INT;
    v_patient_id INT;
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
    INSERT INTO patients (first_name, last_name, curp, birth_date, gender, weight_kg, premature, blood_type_id)
    VALUES (p_first_name, p_last_name, p_curp, p_birth_date, p_gender, p_weight_kg, p_premature, 1)
    RETURNING patients.patient_id INTO v_patient_id;

    -- 4. Crear relación paciente-tutor
    INSERT INTO patient_guardian_relations (patient_id, guardian_id, relation_type, is_primary, has_custody)
    VALUES (v_patient_id, v_guardian_id, 'Tutor', TRUE, TRUE);

    RETURN QUERY SELECT v_patient_id;
END;
$$;


--  2. Obtener pacientes enriquecidos (wrapper de vista)
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


--  3. Obtener historial de vacunación enriquecido (wrapper de vista)
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


--  4. Obtener status de inventario (wrapper de vista)
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


--  5. Obtener citas enriquecidas (wrapper de vista)
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


--  6. Obtener dosis pendientes (wrapper de vista)
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


--  7. Registrar vacuna
CREATE OR REPLACE FUNCTION sp_register_vaccine(
    p_name              VARCHAR,
    p_commercial_name   VARCHAR,
    p_manufacturer_id   INT,
    p_via_id            INT,
    p_ideal_age_months  SMALLINT,
    p_disease_prevented TEXT
)
RETURNS TABLE (vaccine_id INT)
LANGUAGE plpgsql
AS $$
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

    RETURN QUERY SELECT v_vaccine_id;
END;
$$;


--  8. Registrar aplicación de vacuna
CREATE OR REPLACE FUNCTION sp_register_vaccination_record(
    p_patient_id           INT,
    p_vaccine_id           INT,
    p_worker_id            INT,
    p_clinic_id            INT,
    p_lot_id               INT,
    p_scheme_dose_id       INT,
    p_applied_date         DATE,
    p_application_site_id  INT,
    p_patient_temp_c       NUMERIC,
    p_had_reaction         BOOLEAN
)
RETURNS TABLE (record_id INT)
LANGUAGE plpgsql
AS $$
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

    RETURN QUERY SELECT v_record_id;
END;
$$;