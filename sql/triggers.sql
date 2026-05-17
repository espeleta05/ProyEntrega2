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


-- Trigger 4 (v2): Descontar inventario + registrar movimiento en inventory_movements
CREATE OR REPLACE FUNCTION fn_decrement_vaccine_lot_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_qty_before INT;
    v_qty_after  INT;
BEGIN
    IF NEW.lot_id IS NULL THEN
        RETURN NEW;
    END IF;

    SELECT quantity_available INTO v_qty_before
    FROM vaccine_lots
    WHERE lot_id = NEW.lot_id
    FOR UPDATE;

    IF v_qty_before IS NULL THEN
        RAISE EXCEPTION 'No se encontró el lote % para ajustar stock', NEW.lot_id;
    END IF;

    IF v_qty_before <= 0 THEN
        RAISE EXCEPTION 'El lote % no tiene stock disponible', NEW.lot_id;
    END IF;

    v_qty_after := v_qty_before - 1;

    -- Descontar stock y actualizar estado si llega a 0
    UPDATE vaccine_lots
    SET quantity_available = v_qty_after,
        lot_status = CASE WHEN v_qty_after = 0 THEN 'Agotado' ELSE lot_status END
    WHERE lot_id = NEW.lot_id;

    -- Registrar movimiento de trazabilidad
    INSERT INTO inventory_movements (
        lot_id, vaccine_id, clinic_id, worker_id,
        movement_type, quantity, quantity_before, quantity_after,
        reference_id, reference_type
    ) VALUES (
        NEW.lot_id, NEW.vaccine_id, NEW.clinic_id, NEW.worker_id,
        'Salida_Aplicacion', 1, v_qty_before, v_qty_after,
        NEW.record_id, 'vaccination_record'
    );

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
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (table_name, action, record_id, changed_at)
        VALUES ('patients', 'INSERT', NEW.patient_id, NOW());
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, action, record_id, changed_at)
        VALUES ('patients', 'UPDATE', NEW.patient_id, NOW());
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, action, record_id, changed_at)
        VALUES ('patients', 'DELETE', OLD.patient_id, NOW());
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
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (table_name, action, record_id, changed_at)
        VALUES ('vaccination_records', 'INSERT', NEW.record_id, NOW());
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, action, record_id, changed_at)
        VALUES ('vaccination_records', 'UPDATE', NEW.record_id, NOW());
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, action, record_id, changed_at)
        VALUES ('vaccination_records', 'DELETE', OLD.record_id, NOW());
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
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO audit_log (table_name, action, record_id, changed_at)
        VALUES ('workers', 'INSERT', NEW.worker_id, NOW());
    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (table_name, action, record_id, changed_at)
        VALUES ('workers', 'UPDATE', NEW.worker_id, NOW());
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (table_name, action, record_id, changed_at)
        VALUES ('workers', 'DELETE', OLD.worker_id, NOW());
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



-- ============================================================
-- [DEPRECADO] trigger 11: generación automática de citas
-- ELIMINADO: generaba miles de citas ficticias para dosis futuras,
-- mezclando dominio médico con dominio operativo clínico.
-- Las citas ahora SOLO se crean manualmente vía sp_create_appointment.
-- ============================================================
-- CREATE OR REPLACE FUNCTION fn_generate_appointment_for_schedule() ...
-- DROP TRIGGER IF EXISTS trg_generate_appointment_for_schedule ON patient_vaccine_schedule;
-- (ver sección DEPRECATED al fondo del archivo triggers.sql)




-- ============================================================
-- [CORREGIDO] Trigger 12: Marcar dosis como Aplicada en patient_vaccine_schedule
-- CAMBIO: eliminada referencia a applied_record_id (FK circular removida).
--         Ahora solo actualiza status y updated_at.
-- ============================================================
CREATE OR REPLACE FUNCTION fn_update_expected_vaccination_scheme()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.patient_schedule_id IS NOT NULL THEN
        UPDATE patient_vaccine_schedule
        SET    status     = 'Aplicada',
               updated_at = NOW()
        WHERE  schedule_id = NEW.patient_schedule_id
          AND  status     <> 'Aplicada';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_expected_vaccination_scheme ON vaccination_records;
CREATE TRIGGER trg_update_expected_vaccination_scheme
AFTER INSERT ON vaccination_records
FOR EACH ROW
EXECUTE FUNCTION fn_update_expected_vaccination_scheme();


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
            worker_id,
            changed_at,
            ip_address
        )
        VALUES (
            'vaccine_lots',
            'UPDATE',
            NEW.lot_id,
            NULL,
            NOW(),
            NULL
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
-- [NUEVO] Trigger 15: Marcar cita como Completada al registrar vacuna
-- Separa el acto de vacunar (dominio médico) del estado de la cita
-- (dominio operativo) sin necesidad de llamar sp_complete_appointment.
-- ============================================================
CREATE OR REPLACE FUNCTION fn_complete_appointment_on_vaccination()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.appointment_id IS NOT NULL THEN
        UPDATE appointments
        SET    appointment_status = 'Completada'
        WHERE  appointment_id    = NEW.appointment_id
          AND  appointment_status NOT IN ('Cancelada', 'No Show', 'Completada');
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_complete_appointment_on_vaccination ON vaccination_records;
CREATE TRIGGER trg_complete_appointment_on_vaccination
AFTER INSERT ON vaccination_records
FOR EACH ROW
EXECUTE FUNCTION fn_complete_appointment_on_vaccination();


-- ============================================================
-- [NUEVO] Trigger 16: Actualizar status de patient_vaccine_schedule
-- cuando se genera una nueva dosis en el esquema (ON INSERT).
-- Si due_date ya pasó → Atrasada, si no → Pendiente.
-- Complementa a fn_generate_expected_vaccination_scheme (trigger 10)
-- para que el status sea correcto desde el día de inserción.
-- ============================================================
CREATE OR REPLACE FUNCTION fn_set_initial_schedule_status()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.due_date < CURRENT_DATE AND NEW.status = 'Pendiente' THEN
        NEW.status := 'Atrasada';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_initial_schedule_status ON patient_vaccine_schedule;
CREATE TRIGGER trg_set_initial_schedule_status
BEFORE INSERT ON patient_vaccine_schedule
FOR EACH ROW
EXECUTE FUNCTION fn_set_initial_schedule_status();


-- ============================================================
-- MÓDULO: TRIGGERS FLUJO CLÍNICO NFC
-- ============================================================

-- Trigger 17: Al cerrar visita, marcar la cita vinculada como Completada
CREATE OR REPLACE FUNCTION fn_close_appointment_on_checkout()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.visit_status = 'Finalizado'
       AND OLD.visit_status <> 'Finalizado'
       AND NEW.appointment_id IS NOT NULL
    THEN
        UPDATE appointments
        SET    appointment_status = 'Completada'
        WHERE  appointment_id    = NEW.appointment_id
          AND  appointment_status NOT IN ('Cancelada','No Show','Completada');
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_close_appointment_on_checkout ON patient_clinic_visits;
CREATE TRIGGER trg_close_appointment_on_checkout
AFTER UPDATE ON patient_clinic_visits
FOR EACH ROW EXECUTE FUNCTION fn_close_appointment_on_checkout();


-- Trigger 18: Auditar cada cambio de estado clínico en visitas
CREATE OR REPLACE FUNCTION fn_audit_visit_status()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.visit_status <> OLD.visit_status THEN
        INSERT INTO audit_log (table_name, record_id, action, changed_data, worker_id, changed_at)
        VALUES (
            'patient_clinic_visits', NEW.visit_id, 'UPDATE',
            jsonb_build_object(
                'from_status', OLD.visit_status,
                'to_status',   NEW.visit_status,
                'patient_id',  NEW.patient_id,
                'ts',          NOW()
            ),
            NEW.assigned_worker_id, NOW()
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_visit_status ON patient_clinic_visits;
CREATE TRIGGER trg_audit_visit_status
AFTER UPDATE ON patient_clinic_visits
FOR EACH ROW EXECUTE FUNCTION fn_audit_visit_status();


-- Trigger 19: Bloquear check-in de pacientes inactivos
CREATE OR REPLACE FUNCTION fn_prevent_inactive_patient_checkin()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_active BOOLEAN;
BEGIN
    SELECT is_active INTO v_active FROM patients WHERE patient_id = NEW.patient_id;
    IF NOT COALESCE(v_active, FALSE) THEN
        RAISE EXCEPTION
            'No se puede hacer check-in del paciente id=% porque está inactivo',
            NEW.patient_id;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_inactive_patient_checkin ON patient_clinic_visits;
CREATE TRIGGER trg_prevent_inactive_patient_checkin
BEFORE INSERT ON patient_clinic_visits
FOR EACH ROW EXECUTE FUNCTION fn_prevent_inactive_patient_checkin();


-- Trigger 20: Actualizar updated_at en patient_clinic_visits automáticamente
CREATE OR REPLACE FUNCTION fn_set_visit_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_set_visit_updated_at ON patient_clinic_visits;
CREATE TRIGGER trg_set_visit_updated_at
BEFORE UPDATE ON patient_clinic_visits
FOR EACH ROW EXECUTE FUNCTION fn_set_visit_updated_at();


-- ============================================================
-- DEPRECATED — trigger 11 original (auto-generación de citas)
-- Guardado aquí como referencia histórica. NO ejecutar.
-- ============================================================
/*
CREATE OR REPLACE FUNCTION fn_generate_appointment_for_schedule()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_clinic_id INT;
BEGIN
    IF NEW.due_date > CURRENT_DATE + INTERVAL '30 days' THEN RETURN NEW; END IF;
    SELECT clinic_id INTO v_clinic_id FROM clinics WHERE is_active = TRUE LIMIT 1;
    INSERT INTO appointments (patient_schedule_id, clinic_id, scheduled_at, appointment_status, created_at)
    VALUES (NEW.schedule_id, v_clinic_id, NEW.due_date + TIME '09:00', 'Pendiente confirmación', CURRENT_TIMESTAMP);
    RETURN NEW;
END;
$$;
CREATE TRIGGER trg_generate_appointment_for_schedule
AFTER INSERT ON patient_vaccine_schedule
FOR EACH ROW EXECUTE FUNCTION fn_generate_appointment_for_schedule();


-- Trigger Almacén: Auto-gestionar lot_status en función de stock y caducidad
CREATE OR REPLACE FUNCTION fn_auto_lot_status()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- No modificar lotes Bloqueados o Retirados por reglas de stock
    IF NEW.lot_status IN ('Bloqueado', 'Retirado') THEN
        RETURN NEW;
    END IF;

    -- Auto-expirar si la fecha ya pasó
    IF NEW.expiration_date < CURRENT_DATE THEN
        NEW.lot_status := 'Caducado';
    -- Auto-agotar si llega a 0 dosis
    ELSIF NEW.quantity_available = 0 THEN
        NEW.lot_status := 'Agotado';
    -- Reactivar si se ajustó al alza y no está vencido
    ELSIF NEW.quantity_available > 0 AND OLD.lot_status = 'Agotado'
          AND NEW.expiration_date >= CURRENT_DATE THEN
        NEW.lot_status := 'Disponible';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_lot_status ON vaccine_lots;
CREATE TRIGGER trg_auto_lot_status
BEFORE UPDATE ON vaccine_lots
FOR EACH ROW
EXECUTE FUNCTION fn_auto_lot_status();
*/
