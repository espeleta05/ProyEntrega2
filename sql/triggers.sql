-- ============================================================
--  TRIGGERS DE VALIDACION CLINICA (PostgreSQL)
-- ============================================================

-- Trigger 1: Validar edad minima segun scheme_doses.ideal_age_months
CREATE OR REPLACE FUNCTION fn_validate_vaccination_age()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_patient_age_months INT;
    v_ideal_age_months   SMALLINT;
    v_birth_date         DATE;
BEGIN
    SELECT birth_date INTO v_birth_date
    FROM patients
    WHERE patient_id = NEW.patient_id;

    IF NEW.scheme_dose_id IS NOT NULL THEN
        SELECT ideal_age_months INTO v_ideal_age_months
        FROM scheme_doses
        WHERE dose_id = NEW.scheme_dose_id;

        v_patient_age_months :=
            (EXTRACT(YEAR FROM NEW.applied_date)::INT * 12 + EXTRACT(MONTH FROM NEW.applied_date)::INT)
            -
            (EXTRACT(YEAR FROM v_birth_date)::INT * 12 + EXTRACT(MONTH FROM v_birth_date)::INT);

        IF v_ideal_age_months IS NOT NULL AND v_patient_age_months < v_ideal_age_months THEN
            RAISE EXCEPTION
                'El paciente no cumple la edad minima. Edad actual: % meses, edad requerida: % meses',
                v_patient_age_months,
                v_ideal_age_months;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_vaccination_age ON vaccination_records;
CREATE TRIGGER trg_validate_vaccination_age
BEFORE INSERT ON vaccination_records
FOR EACH ROW
EXECUTE FUNCTION fn_validate_vaccination_age();


-- Trigger 2: Validar intervalo minimo entre dosis segun scheme_doses.min_interval_days
CREATE OR REPLACE FUNCTION fn_validate_vaccination_interval()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_min_interval_days           SMALLINT;
    v_last_vaccination_date       DATE;
    v_days_since_last_vaccination INT;
BEGIN
    IF NEW.scheme_dose_id IS NOT NULL THEN
        SELECT min_interval_days INTO v_min_interval_days
        FROM scheme_doses
        WHERE dose_id = NEW.scheme_dose_id;

        SELECT MAX(applied_date) INTO v_last_vaccination_date
        FROM vaccination_records
        WHERE patient_id = NEW.patient_id
          AND vaccine_id = NEW.vaccine_id;

        IF v_last_vaccination_date IS NOT NULL AND v_min_interval_days IS NOT NULL THEN
            v_days_since_last_vaccination := NEW.applied_date - v_last_vaccination_date;

            IF v_days_since_last_vaccination < v_min_interval_days THEN
                RAISE EXCEPTION
                    'Intervalo insuficiente entre dosis. Dias desde ultima dosis: %, minimo requerido: %',
                    v_days_since_last_vaccination,
                    v_min_interval_days;
            END IF;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_vaccination_interval ON vaccination_records;
CREATE TRIGGER trg_validate_vaccination_interval
BEFORE INSERT ON vaccination_records
FOR EACH ROW
EXECUTE FUNCTION fn_validate_vaccination_interval();


-- Trigger 3: Validar consistencia entre lot_id y clinic_id
CREATE OR REPLACE FUNCTION fn_validate_lot_clinic_consistency()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_lot_clinic_id INT;
BEGIN
    IF NEW.lot_id IS NOT NULL THEN
        SELECT clinic_id INTO v_lot_clinic_id
        FROM vaccine_lots
        WHERE lot_id = NEW.lot_id;

        IF v_lot_clinic_id IS NULL THEN
            RAISE EXCEPTION 'El lote % no existe', NEW.lot_id;
        END IF;

        IF v_lot_clinic_id <> NEW.clinic_id THEN
            RAISE EXCEPTION
                'El lote % no pertenece a la clinica %. Pertenece a clinica %',
                NEW.lot_id,
                NEW.clinic_id,
                v_lot_clinic_id;
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_lot_clinic_consistency ON vaccination_records;
CREATE TRIGGER trg_validate_lot_clinic_consistency
BEFORE INSERT ON vaccination_records
FOR EACH ROW
EXECUTE FUNCTION fn_validate_lot_clinic_consistency();


-- Trigger 4: Descontar inventario del lote al registrar una aplicacion
CREATE OR REPLACE FUNCTION fn_decrement_vaccine_lot_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_current_stock INT;
BEGIN
    IF NEW.lot_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT quantity_available INTO v_current_stock
    FROM vaccine_lots
    WHERE lot_id = NEW.lot_id
    FOR UPDATE;

    IF v_current_stock IS NULL THEN
        RAISE EXCEPTION 'No se encontro el lote % para ajustar stock', NEW.lot_id;
    END IF;

    IF v_current_stock <= 0 THEN
        RAISE EXCEPTION 'El lote % no tiene stock disponible', NEW.lot_id;
    END IF;

    UPDATE vaccine_lots
    SET quantity_available = quantity_available - 1
    WHERE lot_id = NEW.lot_id;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_decrement_vaccine_lot_stock ON vaccination_records;
CREATE TRIGGER trg_decrement_vaccine_lot_stock
AFTER INSERT ON vaccination_records
FOR EACH ROW
EXECUTE FUNCTION fn_decrement_vaccine_lot_stock();


-- Trigger 5: Actualizar timestamp created_at automáticamente
CREATE OR REPLACE FUNCTION fn_set_created_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.created_at IS NULL THEN
        NEW.created_at := NOW();
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_created_at_patients ON patients;
CREATE TRIGGER trg_set_created_at_patients
BEFORE INSERT ON patients
FOR EACH ROW
EXECUTE FUNCTION fn_set_created_at();


-- Trigger 6: Actualizar timestamp updated_at automáticamente
CREATE OR REPLACE FUNCTION fn_set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_updated_at_patients ON patients;
CREATE TRIGGER trg_set_updated_at_patients
BEFORE UPDATE ON patients
FOR EACH ROW
EXECUTE FUNCTION fn_set_updated_at();


-- Trigger 7: Auditoría de cambios en pacientes
CREATE OR REPLACE FUNCTION fn_audit_patient_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (table_name, operation, record_id, changed_data, changed_at)
        VALUES ('patients', 'INSERT', NEW.patient_id, row_to_json(NEW), NOW());
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, operation, record_id, changed_data, changed_at)
        VALUES ('patients', 'UPDATE', NEW.patient_id, jsonb_build_object(
            'old', row_to_json(OLD),
            'new', row_to_json(NEW)
        ), NOW());
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, operation, record_id, changed_data, changed_at)
        VALUES ('patients', 'DELETE', OLD.patient_id, row_to_json(OLD), NOW());
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_patients ON patients;
CREATE TRIGGER trg_audit_patients
AFTER INSERT OR UPDATE OR DELETE ON patients
FOR EACH ROW
EXECUTE FUNCTION fn_audit_patient_changes();


-- Trigger 8: Auditoría de cambios en registros de vacunación
CREATE OR REPLACE FUNCTION fn_audit_vaccination_records()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (table_name, operation, record_id, changed_data, changed_at)
        VALUES ('vaccination_records', 'INSERT', NEW.record_id, row_to_json(NEW), NOW());
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, operation, record_id, changed_data, changed_at)
        VALUES ('vaccination_records', 'UPDATE', NEW.record_id, jsonb_build_object(
            'old', row_to_json(OLD),
            'new', row_to_json(NEW)
        ), NOW());
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, operation, record_id, changed_data, changed_at)
        VALUES ('vaccination_records', 'DELETE', OLD.record_id, row_to_json(OLD), NOW());
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_vaccination_records ON vaccination_records;
CREATE TRIGGER trg_audit_vaccination_records
AFTER INSERT OR UPDATE OR DELETE ON vaccination_records
FOR EACH ROW
EXECUTE FUNCTION fn_audit_vaccination_records();


-- Trigger 9: Auditoría de cambios en trabajadores
CREATE OR REPLACE FUNCTION fn_audit_worker_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (table_name, operation, record_id, changed_data, changed_at)
        VALUES ('workers', 'INSERT', NEW.worker_id, row_to_json(NEW), NOW());
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, operation, record_id, changed_data, changed_at)
        VALUES ('workers', 'UPDATE', NEW.worker_id, jsonb_build_object(
            'old', row_to_json(OLD),
            'new', row_to_json(NEW)
        ), NOW());
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, operation, record_id, changed_data, changed_at)
        VALUES ('workers', 'DELETE', OLD.worker_id, row_to_json(OLD), NOW());
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_workers ON workers;
CREATE TRIGGER trg_audit_workers
AFTER INSERT OR UPDATE OR DELETE ON workers
FOR EACH ROW
EXECUTE FUNCTION fn_audit_worker_changes();

--  (aplicado) Trigger 10: Después de insertar un nuevo paciente, generar un esquema de vacunacion esperado que tendria que tener segun su edad
CREATE OR REPLACE FUNCTION fn_generate_expected_vaccination_scheme()
RETURNS TRIGGER AS $$
DECLARE
    dosis RECORD;
    fecha_aplicacion DATE;
BEGIN
    FOR dosis IN
        SELECT dose_id, ideal_age_months
        FROM scheme_doses
    LOOP
        -- calcular fecha esperada
        fecha_aplicacion := NEW.birth_date 
                            + (dosis.ideal_age_months || ' months')::INTERVAL;

        INSERT INTO patient_vaccine_schedule (
            patient_id,
            scheme_dose_id,
            due_date,
            status
        )
        VALUES (
            NEW.patient_id,
            dosis.dose_id, 
            fecha_aplicacion,
            CASE 
                WHEN fecha_aplicacion < CURRENT_DATE THEN 'Atrasada'
                ELSE 'Pendiente'
            END
        )
        ON CONFLICT (patient_id, scheme_dose_id) DO NOTHING;
    END LOOP;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;


CREATE TRIGGER trg_generate_expected_vaccination_scheme
AFTER INSERT ON patients
FOR EACH ROW
EXECUTE FUNCTION fn_generate_expected_vaccination_scheme();


-- Trigger 11: Actualizar el estado del esquema de vacunacion esperado despues de aplicar una dosis
CREATE OR REPLACE FUNCTION fn_update_expected_vaccination_scheme()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
UPDATE patient_vaccine_schedule
    SET 
        status = 'Aplicada',
        applied_record_id = NEW.record_id
    WHERE patient_id = NEW.patient_id
      AND scheme_dose_id = NEW.scheme_dose_id;

    RETURN NEW;
END ;
$$ ;

CREATE TRIGGER trg_update_expected_vaccination_scheme
AFTER INSERT ON vaccination_records
FOR EACH ROW
EXECUTE FUNCTION fn_update_expected_vaccination_scheme();

-- (aplicado) Trigger 12: Actualizar el estado del esquema de vacunacion esperado despues de cancelar una cita
CREATE OR REPLACE FUNCTION fn_update_expected_vaccination_scheme_after_cancel_appointment()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE patient_vaccine_schedule
    SET status = 'Pendiente'
        AND applied_record_id IS NULL
    WHERE patient_id = NEW.patient_id
        AND scheme_dose_id = NEW.scheme_dose_id;
    RETURN NEW;
END ;
$$;

CREATE TRIGGER trg_update_expected_vaccination_scheme_after_cancel_appointment
AFTER DELETE ON appointments 
FOR EACH ROW
EXECUTE FUNCTION fn_update_expected_vaccination_scheme_after_cancel_appointment();

-- (aplicado) Trigger 13: Validar que no puedas aplicar una vacuna si no está en el esquema o ya fue aplicada
CREATE OR REPLACE FUNCTION fn_validate_vaccine_application()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    estado_actual TEXT;
    ya_existe INT;
BEGIN
    -- 1. Validar que exista en el esquema
    SELECT status
    INTO estado_actual
    FROM patient_vaccine_schedule
    WHERE patient_id = NEW.patient_id
      AND scheme_dose_id = NEW.scheme_dose_id;

    IF estado_actual IS NULL THEN
        RAISE EXCEPTION 
        'La vacuna (dose_id=%) no está en el esquema del paciente (%)',
        NEW.scheme_dose_id, NEW.patient_id;
    END IF;

    -- 2. Validar en registros reales (FUENTE DE VERDAD)
    SELECT COUNT(*)
    INTO ya_existe
    FROM vaccination_records
    WHERE patient_id = NEW.patient_id
      AND scheme_dose_id = NEW.scheme_dose_id;

    IF ya_existe > 0 THEN
        RAISE EXCEPTION 
        'La vacuna (dose_id=%) ya fue aplicada al paciente (%)',
        NEW.scheme_dose_id, NEW.patient_id;
    END IF;

    RETURN NEW;

END ; 
$$ ;

CREATE TRIGGER trg_validate_vaccine_application
BEFORE INSERT ON vaccination_records
FOR EACH ROW
EXECUTE FUNCTION fn_validate_vaccine_application();