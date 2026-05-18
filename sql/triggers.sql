-- ============================================================
-- ARCHIVO: triggers.sql
-- Total de objetos: 20
-- ============================================================

SET client_encoding = 'UTF8';

-- ===================================================
-- TRIGGERS PARA EL SISTEMA CLÍNICO DE VACUNACIÓN
-- ===================================================

-- ============================================================
-- MÓDULO: INVENTARIO DE VACUNAS
-- ============================================================

-- ============================================================
-- [1] fn_validate_lot_clinic_consistency
-- Función   : Valida que el lote usado en un registro de vacunación pertenezca a la misma clínica del registro
-- Recibe    : NEW.lot_id, NEW.clinic_id (vaccination_records BEFORE INSERT)
-- Devuelve  : Excepción si el lote no existe o no pertenece a la clínica; NEW si es válido
-- ============================================================
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


-- ============================================================
-- [2] fn_decrement_vaccine_lot_stock
-- Función   : Descuenta 1 dosis del lote usado al registrar una vacunación y genera movimiento en inventory_movements
-- Recibe    : NEW.lot_id, NEW.vaccine_id, NEW.clinic_id, NEW.worker_id, NEW.record_id (vaccination_records AFTER INSERT)
-- Devuelve  : Excepción si el lote no tiene stock; actualiza vaccine_lots e inserta en inventory_movements
-- ============================================================
CREATE OR REPLACE FUNCTION fn_decrement_vaccine_lot_stock()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_qty_before INT;
    v_qty_after  INT;
BEGIN
    IF NEW.lot_id IS NULL THEN RETURN NEW; END IF;

    SELECT quantity_available INTO v_qty_before
    FROM vaccine_lots WHERE lot_id = NEW.lot_id FOR UPDATE;

    IF v_qty_before IS NULL THEN
        RAISE EXCEPTION 'Lote % no encontrado', NEW.lot_id;
    END IF;
    IF v_qty_before <= 0 THEN
        RAISE EXCEPTION 'El lote % no tiene stock disponible', NEW.lot_id;
    END IF;

    v_qty_after := v_qty_before - 1;

    UPDATE vaccine_lots
    SET quantity_available = v_qty_after,
        lot_status = CASE WHEN v_qty_after = 0 THEN 'Agotado' ELSE lot_status END
    WHERE lot_id = NEW.lot_id;

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

DROP TRIGGER IF EXISTS trg_decrement_vaccine_lot_stock ON vaccination_records;
CREATE TRIGGER trg_decrement_vaccine_lot_stock
AFTER INSERT ON vaccination_records
FOR EACH ROW
EXECUTE FUNCTION fn_decrement_vaccine_lot_stock();

-- ============================================================
-- [3] fn_auto_lot_status
-- Función   : Gestiona automáticamente lot_status en vaccine_lots según caducidad y stock disponible
-- Recibe    : NEW.expiration_date, NEW.quantity_available, NEW.lot_status, OLD.lot_status (vaccine_lots BEFORE UPDATE)
-- Devuelve  : NEW con lot_status ajustado a Caducado, Agotado o Disponible según corresponda
-- ============================================================
CREATE OR REPLACE FUNCTION fn_auto_lot_status()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$

BEGIN
    IF NEW.expiration_date < CURRENT_DATE
       AND NEW.lot_status NOT IN ('Bloqueado', 'Retirado') THEN
        NEW.lot_status := 'Caducado';
    ELSIF NEW.quantity_available = 0 AND NEW.lot_status = 'Disponible' THEN
        NEW.lot_status := 'Agotado';
    ELSIF NEW.quantity_available > 0 AND OLD.lot_status = 'Agotado'
          AND NEW.expiration_date >= CURRENT_DATE THEN
        NEW.lot_status := 'Disponible';
    END IF;
    RETURN NEW;
END;

DROP TRIGGER IF EXISTS trg_auto_lot_status ON vaccine_lots;
CREATE TRIGGER trg_auto_lot_status
BEFORE UPDATE ON vaccine_lots
FOR EACH ROW EXECUTE FUNCTION fn_auto_lot_status();


-- ============================================================
-- MÓDULO: PACIENTES
-- ============================================================

-- ============================================================
-- [4] fn_set_created_at
-- Función   : Establece created_at al momento actual si no viene en el INSERT de pacientes
-- Recibe    : NEW.created_at (patients BEFORE INSERT)
-- Devuelve  : NEW con created_at = NOW() si era NULL
-- ============================================================
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


-- ============================================================
-- [5] fn_set_updated_at
-- Función   : Actualiza updated_at al momento actual en cada UPDATE de pacientes
-- Recibe    : NEW (patients BEFORE UPDATE)
-- Devuelve  : NEW con updated_at = NOW()
-- ============================================================
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


-- ============================================================
-- MÓDULO: AUDITORÍA
-- ============================================================

-- ============================================================
-- [6] fn_audit_patient_changes
-- Función   : Registra en audit_log cada INSERT, UPDATE o DELETE sobre la tabla patients
-- Recibe    : NEW / OLD (patients AFTER INSERT OR UPDATE OR DELETE)
-- Devuelve  : Inserta fila en audit_log con table_name, action, record_id y changed_at
-- ============================================================
CREATE OR REPLACE FUNCTION fn_audit_patient_changes()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
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
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_patients ON patients;
CREATE TRIGGER trg_audit_patients
AFTER INSERT OR UPDATE OR DELETE ON patients
FOR EACH ROW
EXECUTE FUNCTION fn_audit_patient_changes();


-- ============================================================
-- [7] fn_audit_vaccination_records
-- Función   : Registra en audit_log cada INSERT, UPDATE o DELETE sobre vaccination_records
-- Recibe    : NEW / OLD (vaccination_records AFTER INSERT OR UPDATE OR DELETE)
-- Devuelve  : Inserta fila en audit_log con table_name, action, record_id y changed_at
-- ============================================================
CREATE OR REPLACE FUNCTION fn_audit_vaccination_records()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
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
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_vaccination_records ON vaccination_records;
CREATE TRIGGER trg_audit_vaccination_records
AFTER INSERT OR UPDATE OR DELETE ON vaccination_records
FOR EACH ROW
EXECUTE FUNCTION fn_audit_vaccination_records();


-- ============================================================
-- [8] fn_audit_worker_changes
-- Función   : Registra en audit_log cada INSERT, UPDATE o DELETE sobre la tabla workers
-- Recibe    : NEW / OLD (workers AFTER INSERT OR UPDATE OR DELETE)
-- Devuelve  : Inserta fila en audit_log con table_name, action, record_id y changed_at
-- ============================================================
CREATE OR REPLACE FUNCTION fn_audit_worker_changes()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
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
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;
    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_audit_workers ON workers;
CREATE TRIGGER trg_audit_workers
AFTER INSERT OR UPDATE OR DELETE ON workers
FOR EACH ROW
EXECUTE FUNCTION fn_audit_worker_changes();


-- ============================================================
-- MÓDULO: ESQUEMA DE VACUNACIÓN
-- ============================================================

-- ============================================================
-- [9] fn_generate_expected_vaccination_scheme
-- Función   : Genera el esquema vacunal esperado al insertar un nuevo paciente, creando una fila en patient_vaccine_schedule por cada dosis del catálogo
-- Recibe    : NEW.patient_id, NEW.birth_date (patients AFTER INSERT)
-- Devuelve  : Inserta filas en patient_vaccine_schedule con due_date y status iniciales; usa ON CONFLICT DO NOTHING
-- ============================================================
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
-- [10] fn_update_expected_vaccination_scheme
-- Función   : Marca la dosis del esquema como Aplicada al insertar un registro de vacunación vinculado
-- Recibe    : NEW.patient_schedule_id (vaccination_records AFTER INSERT)
-- Devuelve  : Actualiza patient_vaccine_schedule.status = 'Aplicada' y updated_at si no estaba ya aplicada
-- ============================================================
-- [CORREGIDO] Eliminada referencia a applied_record_id (FK circular removida).
--             Ahora solo actualiza status y updated_at.
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


-- ============================================================
-- [11] fn_prevent_negative_stock
-- Función   : Bloquea cualquier UPDATE que deje quantity_available negativo en vaccine_lots
-- Recibe    : NEW.quantity_available (vaccine_lots BEFORE UPDATE)
-- Devuelve  : Excepción si quantity_available < 0; NEW si es válido
-- ============================================================
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
-- [12] fn_generate_low_stock_alert
-- Función   : Registra una entrada en audit_log cuando el stock de un lote cae a 10 o menos
-- Recibe    : NEW.quantity_available, NEW.lot_id (vaccine_lots AFTER UPDATE)
-- Devuelve  : Inserta fila en audit_log si quantity_available <= 10
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
-- [13] fn_validate_lot_expiration
-- Función   : Impide aplicar una vacuna si el lote ya está vencido a la fecha de aplicación
-- Recibe    : NEW.lot_id, NEW.applied_date (vaccination_records BEFORE INSERT)
-- Devuelve  : Excepción si expiration_date < applied_date; NEW si es válido
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
-- MÓDULO: CITAS
-- ============================================================

-- ============================================================
-- [14] fn_complete_appointment_on_vaccination
-- Función   : Marca la cita como Completada automáticamente al registrar una vacunación vinculada
-- Recibe    : NEW.appointment_id (vaccination_records AFTER INSERT)
-- Devuelve  : Actualiza appointments.appointment_status = 'Completada' si no era final
-- ============================================================
-- [NUEVO] Separa el acto de vacunar (dominio médico) del estado de la cita
-- (dominio operativo) sin necesidad de llamar sp_complete_appointment.
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
-- [15] fn_set_initial_schedule_status
-- Función   : Corrige el status inicial de una dosis al insertarla en patient_vaccine_schedule si due_date ya pasó
-- Recibe    : NEW.due_date, NEW.status (patient_vaccine_schedule BEFORE INSERT)
-- Devuelve  : NEW con status = 'Atrasada' si due_date < CURRENT_DATE y status era 'Pendiente'
-- ============================================================
-- [NUEVO] Complementa a fn_generate_expected_vaccination_scheme para que
-- el status sea correcto desde el día de inserción.
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
-- MÓDULO: FLUJO CLÍNICO NFC
-- ============================================================

-- ============================================================
-- [16] fn_close_appointment_on_checkout
-- Función   : Al cerrar una visita clínica (Finalizado), marca la cita vinculada como Completada
-- Recibe    : NEW.visit_status, OLD.visit_status, NEW.appointment_id (patient_clinic_visits AFTER UPDATE)
-- Devuelve  : Actualiza appointments.appointment_status = 'Completada' si la visita transicionó a Finalizado
-- ============================================================
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


-- ============================================================
-- [17] fn_audit_visit_status
-- Función   : Audita cada cambio de estado clínico en patient_clinic_visits registrando el estado anterior y nuevo
-- Recibe    : NEW.visit_status, OLD.visit_status, NEW.visit_id, NEW.patient_id, NEW.assigned_worker_id (patient_clinic_visits AFTER UPDATE)
-- Devuelve  : Inserta fila en audit_log con jsonb de from_status / to_status si hubo cambio
-- ============================================================
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


-- ============================================================
-- [18] fn_prevent_inactive_patient_checkin
-- Función   : Bloquea el check-in clínico si el paciente está marcado como inactivo
-- Recibe    : NEW.patient_id (patient_clinic_visits BEFORE INSERT)
-- Devuelve  : Excepción si patients.is_active = FALSE para ese patient_id
-- ============================================================
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


-- ============================================================
-- [19] fn_set_visit_updated_at
-- Función   : Actualiza updated_at al momento actual en cada UPDATE de patient_clinic_visits
-- Recibe    : NEW (patient_clinic_visits BEFORE UPDATE)
-- Devuelve  : NEW con updated_at = NOW()
-- ============================================================
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
-- MÓDULO: CITAS (ASIGNACIÓN AUTOMÁTICA)
-- ============================================================

-- ============================================================
-- [20] fn_auto_assign_worker_area
-- Función   : Asigna automáticamente el trabajador con menor carga y un área libre a citas creadas por tutores sin trabajador asignado
-- Recibe    : NEW.created_by_role, NEW.worker_id, NEW.clinic_id, NEW.scheduled_at, NEW.duration_min, NEW.appointment_id (appointments AFTER INSERT)
-- Devuelve  : Actualiza appointments con worker_id y area_id encontrados; no hace nada si no es cita de tutor o ya tiene trabajador
-- ============================================================
CREATE OR REPLACE FUNCTION fn_auto_assign_worker_area()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_worker_id  INT;
    v_area_id    INT;
BEGIN
    -- Solo actuar en citas de tutor sin trabajador asignado
    IF NEW.created_by_role <> 'Tutor' OR NEW.worker_id IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- Buscar trabajador (Médico o Enfermero) activo con horario en esa
    -- clínica/día/hora y sin cita que se solape en ventana de 20 min.
    -- Se elige el que tenga menos citas activas ese día (menor carga).
    SELECT ws.worker_id
    INTO   v_worker_id
    FROM   worker_schedules ws
    JOIN   workers w ON w.worker_id = ws.worker_id
    JOIN   roles   r ON r.role_id   = w.role_id
    WHERE  ws.clinic_id   = NEW.clinic_id
    AND    r.name         IN ('Medico', 'Enfermero')
    AND    w.is_active    = TRUE
    AND    ws.day_of_week = EXTRACT(ISODOW FROM NEW.scheduled_at)::SMALLINT
    AND    ws.entry_time  <= NEW.scheduled_at::TIME
    AND    ws.exit_time   >  NEW.scheduled_at::TIME
    AND    NOT EXISTS (
        SELECT 1 FROM appointments a
        WHERE  a.worker_id        = ws.worker_id
        AND    a.appointment_id   <> NEW.appointment_id
        AND    a.appointment_status NOT IN ('Cancelada', 'No Show', 'Reagendada')
        AND    a.scheduled_at < NEW.scheduled_at + (NEW.duration_min * INTERVAL '1 minute')
        AND    a.scheduled_at + (a.duration_min * INTERVAL '1 minute') > NEW.scheduled_at
    )
    ORDER BY (
        SELECT COUNT(*)
        FROM   appointments a2
        WHERE  a2.worker_id = ws.worker_id
        AND    DATE(a2.scheduled_at) = DATE(NEW.scheduled_at)
        AND    a2.appointment_status NOT IN ('Cancelada', 'No Show', 'Reagendada')
    ) ASC
    LIMIT 1;

    -- Si se encontró trabajador, buscar área libre en esa clínica a esa hora
    IF v_worker_id IS NOT NULL THEN
        SELECT ca.area_id
        INTO   v_area_id
        FROM   clinic_areas ca
        WHERE  ca.clinic_id = NEW.clinic_id
        AND    NOT EXISTS (
            SELECT 1 FROM appointments a
            WHERE  a.area_id        = ca.area_id
            AND    a.clinic_id      = NEW.clinic_id
            AND    a.appointment_id <> NEW.appointment_id
            AND    a.appointment_status NOT IN ('Cancelada', 'No Show', 'Reagendada')
            AND    a.scheduled_at   = NEW.scheduled_at
        )
        LIMIT 1;

        UPDATE appointments
        SET    worker_id = v_worker_id,
               area_id   = v_area_id
        WHERE  appointment_id = NEW.appointment_id;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_assign_worker_area ON appointments;
CREATE TRIGGER trg_auto_assign_worker_area
AFTER INSERT ON appointments
FOR EACH ROW
EXECUTE FUNCTION fn_auto_assign_worker_area();


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
