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
        INSERT INTO audit_log (table_name, action, record_id, changed_data, changed_at)
        VALUES ('patients', 'INSERT', NEW.patient_id, row_to_json(NEW)::JSONB, NOW());
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, action, record_id, changed_data, changed_at)
        VALUES ('patients', 'UPDATE', NEW.patient_id, jsonb_build_object(
            'old', row_to_json(OLD),
            'new', row_to_json(NEW)
        ), NOW());
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, action, record_id, changed_data, changed_at)
        VALUES ('patients', 'DELETE', OLD.patient_id, row_to_json(OLD)::JSONB, NOW());
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
        INSERT INTO audit_log (table_name, action, record_id, changed_data, changed_at)
        VALUES ('vaccination_records', 'INSERT', NEW.record_id, row_to_json(NEW)::JSONB, NOW());
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, action, record_id, changed_data, changed_at)
        VALUES ('vaccination_records', 'UPDATE', NEW.record_id, jsonb_build_object(
            'old', row_to_json(OLD),
            'new', row_to_json(NEW)
        ), NOW());
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, action, record_id, changed_data, changed_at)
        VALUES ('vaccination_records', 'DELETE', OLD.record_id, row_to_json(OLD)::JSONB, NOW());
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
        INSERT INTO audit_log (table_name, action, record_id, changed_data, changed_at)
        VALUES ('workers', 'INSERT', NEW.worker_id, row_to_json(NEW)::JSONB, NOW());
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, action, record_id, changed_data, changed_at)
        VALUES ('workers', 'UPDATE', NEW.worker_id, jsonb_build_object(
            'old', row_to_json(OLD),
            'new', row_to_json(NEW)
        ), NOW());
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, action, record_id, changed_data, changed_at)
        VALUES ('workers', 'DELETE', OLD.worker_id, row_to_json(OLD)::JSONB, NOW());
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
    SET status = 'Pendiente',
        applied_record_id = NULL
    WHERE patient_id = OLD.patient_id
        AND scheme_dose_id = OLD.scheme_dose_id;
    RETURN OLD;
END ;
$$;

CREATE TRIGGER trg_update_expected_vaccination_scheme_after_cancel_appointment
AFTER DELETE ON appointments 
FOR EACH ROW
EXECUTE FUNCTION fn_update_expected_vaccination_scheme_after_cancel_appointment();


-- TRIGGER 14
CREATE OR REPLACE FUNCTION fn_prevent_negative_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN

    IF NEW.quantity_available < 0 THEN

        RAISE EXCEPTION
        'El inventario no puede quedar negativo';

    END IF;

    RETURN NEW;

END;
$$;


DROP TRIGGER IF EXISTS trg_prevent_negative_stock
ON vaccine_lots;

CREATE TRIGGER trg_prevent_negative_stock
BEFORE UPDATE
ON vaccine_lots
FOR EACH ROW
EXECUTE FUNCTION fn_prevent_negative_stock();



-- ============================================================
-- TRIGGER FALTANTE 2
-- ALERTA DE STOCK BAJO
-- ============================================================

CREATE OR REPLACE FUNCTION fn_generate_low_stock_alert()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN

    IF NEW.quantity_available <= 10 THEN

        INSERT INTO audit_log (
            table_name,
            action,
            record_id,
            changed_data,
            changed_at
        )
        VALUES (
            'vaccine_lots',
            'UPDATE',
            NEW.lot_id,
            jsonb_build_object(
                'alerta', 'stock_bajo',
                'lot_id', NEW.lot_id,
                'remaining_stock', NEW.quantity_available
            ),
            NOW()
        );

    END IF;

    RETURN NEW;

END;
$$;


DROP TRIGGER IF EXISTS trg_generate_low_stock_alert
ON vaccine_lots;

CREATE TRIGGER trg_generate_low_stock_alert
AFTER UPDATE
ON vaccine_lots
FOR EACH ROW
EXECUTE FUNCTION fn_generate_low_stock_alert();



-- ============================================================
-- TRIGGER FALTANTE 3
-- VALIDAR CADUCIDAD DEL LOTE
-- ============================================================

CREATE OR REPLACE FUNCTION fn_validate_lot_expiration()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_expiration_date DATE;
BEGIN

    SELECT expiration_date
    INTO v_expiration_date
    FROM vaccine_lots
    WHERE lot_id = NEW.lot_id;

    IF v_expiration_date < NEW.applied_date THEN

        RAISE EXCEPTION
        'No se puede aplicar una vacuna vencida';

    END IF;

    RETURN NEW;

END;
$$;


DROP TRIGGER IF EXISTS trg_validate_lot_expiration
ON vaccination_records;

CREATE TRIGGER trg_validate_lot_expiration
BEFORE INSERT
ON vaccination_records
FOR EACH ROW
EXECUTE FUNCTION fn_validate_lot_expiration();


-- ============================================================
-- TRIGGER 15: Confirmar o cancelar cita según respuesta del tutor
-- ============================================================
-- Flujo clínico:
--   1. Un appointment se crea con status = 'Pendiente confirmación'
--      (asignado por el sistema al generar el esquema automático).
--   2. El tutor actualiza tutor_accepted = TRUE  → status pasa a 'Programada'.
--   3. El tutor actualiza tutor_accepted = FALSE → status pasa a 'Cancelada'.
--   4. Se rechaza cualquier intento de cambiar una cita ya terminal
--      (Completada / Cancelada).
--   5. Se rechaza confirmar una cita con scheduled_at en el pasado
--      para evitar inconsistencias en el historial clínico.
-- ============================================================

CREATE OR REPLACE FUNCTION fn_confirm_appointment_on_tutor_acceptance()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_patient_name TEXT;
BEGIN
    -- Disparar solo cuando tutor_accepted realmente cambia de valor
    IF OLD.tutor_accepted IS NOT DISTINCT FROM NEW.tutor_accepted THEN
        RETURN NEW;
    END IF;

    -- Obtener nombre del paciente para mensajes de error legibles
    SELECT TRIM(first_name || ' ' || last_name)
    INTO v_patient_name
    FROM patients
    WHERE patient_id = NEW.patient_id;

    -- ── CASO 1: El tutor ACEPTA la cita ──────────────────────────────────────
    IF NEW.tutor_accepted = TRUE THEN

        -- Rechazar si la cita ya está en un estado terminal
        IF OLD.appointment_status IN ('Completada', 'Cancelada', 'No Show') THEN
            RAISE EXCEPTION
                'La cita del paciente "%" ya está en estado "%" y no puede ser confirmada.',
                v_patient_name, OLD.appointment_status;
        END IF;

        -- Rechazar si la fecha programada ya pasó (no tiene sentido confirmar
        -- una cita que nunca se podrá atender)
        IF NEW.scheduled_at < NOW() THEN
            RAISE EXCEPTION
                'No se puede confirmar la cita del paciente "%": la fecha programada (%) ya pasó. '
                'Reagende la cita antes de confirmarla.',
                v_patient_name, NEW.scheduled_at::DATE;
        END IF;

        -- Confirmar: activar en el calendario clínico
        NEW.appointment_status := 'Programada';
        NEW.appointment_notes  :=
            COALESCE(NEW.appointment_notes || E'\n', '')
            || '[' || NOW()::DATE || '] Cita confirmada por el tutor.';

    -- ── CASO 2: El tutor RECHAZA la cita ─────────────────────────────────────
    ELSIF NEW.tutor_accepted = FALSE THEN

        -- No cancelar lo que ya fue atendido
        IF OLD.appointment_status = 'Completada' THEN
            RAISE EXCEPTION
                'La cita del paciente "%" ya fue completada y no puede ser rechazada.',
                v_patient_name;
        END IF;

        -- Cancelar la cita
        NEW.appointment_status := 'Cancelada';
        NEW.appointment_notes  :=
            COALESCE(NEW.appointment_notes || E'\n', '')
            || '[' || NOW()::DATE || '] Cita cancelada por rechazo del tutor.';

    END IF;

    -- Registrar el cambio en auditoría
    INSERT INTO audit_log (table_name, record_id, action, changed_at)
    VALUES ('appointments', NEW.appointment_id, 'UPDATE', NOW());

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_confirm_appointment_on_tutor_acceptance ON appointments;
CREATE TRIGGER trg_confirm_appointment_on_tutor_acceptance
BEFORE UPDATE OF tutor_accepted
ON appointments
FOR EACH ROW
EXECUTE FUNCTION fn_confirm_appointment_on_tutor_acceptance();