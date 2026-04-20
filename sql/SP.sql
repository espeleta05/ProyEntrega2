-- ==============================================
-- Stored Procedures
--===============================================

--  1. Registrar a un nuevo paciente
CREATE OR REPLACE PROCEDURE sp_register_patient(
    p_first_name     VARCHAR,
    p_last_name      VARCHAR,
    p_curp           VARCHAR,
    p_birth_date     DATE,
    p_gender         CHAR(1),
    p_weight_kg      NUMERIC,
    p_premature      BOOLEAN,
    p_guardian_name  VARCHAR,
    p_guardian_last  VARCHAR,
    p_guardian_phone VARCHAR,
    OUT p_patient_id INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_guardian_id INT;
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
    RETURNING patient_id INTO p_patient_id;

    -- 4. Crear relación paciente-tutor
    INSERT INTO patient_guardian_relations (patient_id, guardian_id, relation_type, is_primary, has_custody)
    VALUES (p_patient_id, v_guardian_id, 'Tutor', TRUE, TRUE);
END;
$$;