-- ============================================================
--  TRIGGERS DE VALIDACIÓN CLÍNICA
-- ============================================================

-- Trigger 1: Validar edad mínima según scheme_doses.ideal_age_months
DELIMITER $$
CREATE TRIGGER trg_validate_vaccination_age
BEFORE INSERT ON vaccination_records
FOR EACH ROW
BEGIN
    DECLARE v_patient_age_months INT;
    DECLARE v_ideal_age_months   SMALLINT;
    DECLARE v_birth_date         DATE;

    -- Obtener fecha de nacimiento del paciente
    SELECT birth_date INTO v_birth_date
    FROM patients
    WHERE patient_id = NEW.patient_id;

    -- Si tiene scheme_dose_id, validar edad mínima
    IF NEW.scheme_dose_id IS NOT NULL THEN

        SELECT ideal_age_months INTO v_ideal_age_months
        FROM scheme_doses
        WHERE dose_id = NEW.scheme_dose_id;

        -- Calcular edad en meses
        SET v_patient_age_months = (YEAR(NEW.applied_date) * 12 + MONTH(NEW.applied_date)) - (YEAR(v_birth_date) * 12 + MONTH(v_birth_date));

        -- Validar que la edad sea suficiente
        IF v_ideal_age_months IS NOT NULL AND v_patient_age_months < v_ideal_age_months THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = CONCAT(
                    'El paciente no cumple la edad mínima. Edad actual: ',
                    v_patient_age_months,
                    ' meses, edad requerida: ',
                    v_ideal_age_months,
                    ' meses'
                );
        END IF;
    END IF;
END $$
DELIMITER ;

-- Trigger 2: Validar intervalo mínimo entre dosis según scheme_doses.min_interval_days
DELIMITER $$
CREATE TRIGGER trg_validate_vaccination_interval
BEFORE INSERT ON vaccination_records
FOR EACH ROW
BEGIN
    DECLARE v_min_interval_days          SMALLINT;
    DECLARE v_last_vaccination_date      DATE;
    DECLARE v_days_since_last_vaccination INT;

    -- Si tiene scheme_dose_id, validar intervalo mínimo
    IF NEW.scheme_dose_id IS NOT NULL THEN

        SELECT min_interval_days INTO v_min_interval_days
        FROM scheme_doses
        WHERE dose_id = NEW.scheme_dose_id;

        -- Obtener fecha de última vacunación del mismo medicamento
        SELECT MAX(applied_date) INTO v_last_vaccination_date
        FROM vaccination_records
        WHERE patient_id = NEW.patient_id
          AND vaccine_id = NEW.vaccine_id;

        -- Si hay vacunación previa y existe intervalo mínimo, validar
        IF v_last_vaccination_date IS NOT NULL AND v_min_interval_days IS NOT NULL THEN

            SET v_days_since_last_vaccination = DATEDIFF(NEW.applied_date, v_last_vaccination_date);

            IF v_days_since_last_vaccination < v_min_interval_days THEN
                SIGNAL SQLSTATE '45000'
                    SET MESSAGE_TEXT = CONCAT(
                        'Intervalo insuficiente entre dosis. Días desde última dosis: ',
                        v_days_since_last_vaccination,
                        ', mínimo requerido: ',
                        v_min_interval_days
                    );
            END IF;
        END IF;
    END IF;
END $$
DELIMITER ;


-- Trigger 3: Validar consistencia entre lot_id y clinic_id
DELIMITER $$
CREATE TRIGGER trg_validate_lot_clinic_consistency
BEFORE INSERT ON vaccination_records
FOR EACH ROW
BEGIN
    DECLARE v_lot_clinic_id INT;

    -- Si hay lot_id, validar que pertenezca a la clínica
    IF NEW.lot_id IS NOT NULL THEN

        SELECT clinic_id INTO v_lot_clinic_id
        FROM vaccine_lots
        WHERE lot_id = NEW.lot_id;

        IF v_lot_clinic_id IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = CONCAT(
                    'El lote ', NEW.lot_id, ' no existe'
                );
        END IF;

        IF v_lot_clinic_id != NEW.clinic_id THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = CONCAT(
                    'El lote ', NEW.lot_id,
                    ' no pertenece a la clínica ', NEW.clinic_id,
                    '. Pertenece a clínica ', v_lot_clinic_id
                );
        END IF;
    END IF;
END $$
DELIMITER ;

-- Trigger 4: Programar una cita de seguimiento automática para la próxima dosis según scheme_doses.next_dose_interval_days
DELIMITER $$
CREATE TRIGGER trg_schedule_next_dose_appointment
AFTER INSERT ON vaccination_records
FOR EACH ROW
BEGIN
    DECLARE v_next_dose_interval_days SMALLINT;
    DECLARE v_next_dose_date DATE;

    -- Si tiene scheme_dose_id, programar cita para próxima dosis
    IF NEW.scheme_dose_id IS NOT NULL THEN

        SELECT next_dose_interval_days INTO v_next_dose_interval_days
        FROM scheme_doses
        WHERE dose_id = NEW.scheme_dose_id;

        IF v_next_dose_interval_days IS NOT NULL THEN
            SET v_next_dose_date = DATE_ADD(NEW.applied_date, INTERVAL v_next_dose_interval_days DAY);

            INSERT INTO appointments (patient_id, clinic_id, scheduled_at, reason)
            VALUES (NEW.patient_id, NEW.clinic_id, v_next_dose_date, CONCAT('Cita para próxima dosis de vacuna ', NEW.vaccine_id));
        END IF;
    END IF;
END $$
DELIMITER ;