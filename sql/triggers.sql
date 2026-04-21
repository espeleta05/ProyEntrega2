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
