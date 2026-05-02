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


-- ============================================================
-- FIN TRIGGERS
-- ============================================================
