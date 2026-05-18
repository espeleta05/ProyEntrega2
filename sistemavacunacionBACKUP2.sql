--
-- PostgreSQL database dump
--

\restrict lEVBQ8NjIASKTAlsDeGELS3Sg8nux1ZTOaqh1toX3FCLphahlaCaBWSTfRAPLwj

-- Dumped from database version 18.1
-- Dumped by pg_dump version 18.1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: visit_status; Type: TYPE; Schema: public; Owner: postgres
--

CREATE TYPE public.visit_status AS ENUM (
    'En recepcion',
    'En espera',
    'En consulta',
    'En vacunacion',
    'Finalizado',
    'Abandono',
    'Cancelado'
);


ALTER TYPE public.visit_status OWNER TO postgres;

--
-- Name: fn_audit_patient_changes(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_audit_patient_changes() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


ALTER FUNCTION public.fn_audit_patient_changes() OWNER TO postgres;

--
-- Name: fn_audit_vaccination_records(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_audit_vaccination_records() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


ALTER FUNCTION public.fn_audit_vaccination_records() OWNER TO postgres;

--
-- Name: fn_audit_worker_changes(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_audit_worker_changes() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


ALTER FUNCTION public.fn_audit_worker_changes() OWNER TO postgres;

--
-- Name: fn_auto_assign_worker_area(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_auto_assign_worker_area() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_worker_id  INT;
    v_area_id    INT;
BEGIN
    -- Solo actuar en citas de tutor sin trabajador asignado
    IF NEW.created_by_role <> 'Tutor' OR NEW.worker_id IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- Buscar trabajador (M‚dico o Enfermero) activo con horario en esa
    -- cl¡nica/d¡a/hora y sin cita que se solape en ventana de 20 min.
    -- Se elige el que tenga menos citas activas ese d¡a (menor carga).
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

    -- Si se encontr¢ trabajador, buscar  rea libre en esa cl¡nica a esa hora
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


ALTER FUNCTION public.fn_auto_assign_worker_area() OWNER TO postgres;

--
-- Name: fn_auto_lot_status(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_auto_lot_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.fn_auto_lot_status() OWNER TO postgres;

--
-- Name: fn_complete_appointment_on_vaccination(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_complete_appointment_on_vaccination() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


ALTER FUNCTION public.fn_complete_appointment_on_vaccination() OWNER TO postgres;

--
-- Name: fn_confirm_appointment_on_tutor_acceptance(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_confirm_appointment_on_tutor_acceptance() RETURNS trigger
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

    -- ÄÄ CASO 1: El tutor ACEPTA la cita ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
    IF NEW.tutor_accepted = TRUE THEN

        -- Rechazar si la cita ya est  en un estado terminal
        IF OLD.appointment_status IN ('Completada', 'Cancelada', 'No Show') THEN
            RAISE EXCEPTION
                'La cita del paciente "%" ya est  en estado "%" y no puede ser confirmada.',
                v_patient_name, OLD.appointment_status;
        END IF;

        -- Rechazar si la fecha programada ya pas¢ (no tiene sentido confirmar
        -- una cita que nunca se podr  atender)
        IF NEW.scheduled_at < NOW() THEN
            RAISE EXCEPTION
                'No se puede confirmar la cita del paciente "%": la fecha programada (%) ya pas¢. '
                'Reagende la cita antes de confirmarla.',
                v_patient_name, NEW.scheduled_at::DATE;
        END IF;

        -- Confirmar: activar en el calendario cl¡nico
        NEW.appointment_status := 'Programada';
        NEW.appointment_notes  :=
            COALESCE(NEW.appointment_notes || E'\n', '')
            || '[' || NOW()::DATE || '] Cita confirmada por el tutor.';

    -- ÄÄ CASO 2: El tutor RECHAZA la cita ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
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

    -- Registrar el cambio en auditor¡a
    INSERT INTO audit_log (table_name, record_id, action, changed_at)
    VALUES ('appointments', NEW.appointment_id, 'UPDATE', NOW());

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_confirm_appointment_on_tutor_acceptance() OWNER TO postgres;

--
-- Name: fn_decrement_vaccine_lot_stock(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_decrement_vaccine_lot_stock() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.fn_decrement_vaccine_lot_stock() OWNER TO postgres;

--
-- Name: fn_generate_appointment_for_schedule(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_generate_appointment_for_schedule() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_clinic_id INT;
BEGIN

    -- Solo generar citas cercanas o atrasadas
    IF NEW.due_date > CURRENT_DATE + INTERVAL '30 days' THEN
        RETURN NEW;
    END IF;

    -- Buscar cl¡nica activa
    SELECT clinic_id
    INTO v_clinic_id
    FROM clinics
    WHERE is_active = TRUE
    LIMIT 1;

    -- Crear cita sugerida
    INSERT INTO appointments (
        patient_schedule_id,
        clinic_id,
        scheduled_at,
        appointment_status,
        created_at
    )
    VALUES (
        NEW.schedule_id,
        v_clinic_id,
        NEW.due_date + TIME '09:00',
        'Pendiente confirmaci¢n',
        CURRENT_TIMESTAMP
    );

    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_generate_appointment_for_schedule() OWNER TO postgres;

--
-- Name: fn_generate_expected_vaccination_scheme(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_generate_expected_vaccination_scheme() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
$$;


ALTER FUNCTION public.fn_generate_expected_vaccination_scheme() OWNER TO postgres;

--
-- Name: fn_generate_low_stock_alert(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_generate_low_stock_alert() RETURNS trigger
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


ALTER FUNCTION public.fn_generate_low_stock_alert() OWNER TO postgres;

--
-- Name: fn_prevent_negative_stock(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_prevent_negative_stock() RETURNS trigger
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


ALTER FUNCTION public.fn_prevent_negative_stock() OWNER TO postgres;

--
-- Name: fn_set_initial_schedule_status(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_set_initial_schedule_status() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.due_date < CURRENT_DATE AND NEW.status = 'Pendiente' THEN
        NEW.status := 'Atrasada';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_set_initial_schedule_status() OWNER TO postgres;

--
-- Name: fn_update_expected_vaccination_scheme(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_update_expected_vaccination_scheme() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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


ALTER FUNCTION public.fn_update_expected_vaccination_scheme() OWNER TO postgres;

--
-- Name: fn_validate_lot_expiration(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validate_lot_expiration() RETURNS trigger
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


ALTER FUNCTION public.fn_validate_lot_expiration() OWNER TO postgres;

--
-- Name: fn_validate_vaccine_application(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_validate_vaccine_application() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
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
        'La vacuna (dose_id=%) no est  en el esquema del paciente (%)',
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
$$;


ALTER FUNCTION public.fn_validate_vaccine_application() OWNER TO postgres;

--
-- Name: sp_accept_transfer(integer, integer, text, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_accept_transfer(IN p_transfer_id integer, IN p_worker_id integer, IN p_notes text, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_t              RECORD;
    v_src_lot        RECORD;
    v_qty_before     INT;
    v_qty_after      INT;
    v_dest_lot_id    INT;
    v_dest_qty_before INT;
BEGIN
    SELECT t.transfer_id, t.lot_id, t.vaccine_id,
           t.from_clinic_id, t.to_clinic_id,
           t.quantity, t.transfer_status
    INTO v_t
    FROM inventory_transfers t
    WHERE t.transfer_id = p_transfer_id FOR UPDATE;

    IF NOT FOUND THEN
        OPEN p_results FOR SELECT FALSE AS success, 'Transferencia no encontrada.' AS message;
        RETURN;
    END IF;

    IF v_t.transfer_status NOT IN ('Pendiente', 'En_Transito') THEN
        OPEN p_results FOR SELECT FALSE AS success,
            'Solo se pueden aceptar transferencias Pendientes o En_Transito. Estado actual: ' || v_t.transfer_status AS message;
        RETURN;
    END IF;

    -- Leer lote origen completo (para clonar datos al destino si hace falta)
    SELECT * INTO v_src_lot FROM vaccine_lots WHERE lot_id = v_t.lot_id FOR UPDATE;
    v_qty_before := v_src_lot.quantity_available;

    IF v_qty_before < v_t.quantity THEN
        OPEN p_results FOR SELECT FALSE AS success,
            'Stock insuficiente en lote origen. Disponible: ' || v_qty_before AS message;
        RETURN;
    END IF;

    v_qty_after := v_qty_before - v_t.quantity;

    -- Descontar del lote origen
    UPDATE vaccine_lots
    SET quantity_available = v_qty_after,
        lot_status = CASE WHEN v_qty_after = 0 THEN 'Agotado' ELSE lot_status END
    WHERE lot_id = v_t.lot_id;

    -- Buscar lote con mismo n£mero en cl¡nica destino
    -- (requiere constraint UNIQUE(lot_number, clinic_id))
    SELECT lot_id, quantity_available INTO v_dest_lot_id, v_dest_qty_before
    FROM vaccine_lots
    WHERE clinic_id  = v_t.to_clinic_id
      AND lot_number = v_src_lot.lot_number;

    IF v_dest_lot_id IS NOT NULL THEN
        -- Sumar al lote existente en destino
        UPDATE vaccine_lots
        SET quantity_available = quantity_available + v_t.quantity,
            lot_status = 'Disponible'
        WHERE lot_id = v_dest_lot_id;
    ELSE
        -- Crear nuevo lote en la cl¡nica destino
        INSERT INTO vaccine_lots (
            vaccine_id, clinic_id, lot_number,
            quantity_received, quantity_available,
            expiration_date, received_date, is_active, lot_status
        ) VALUES (
            v_src_lot.vaccine_id, v_t.to_clinic_id, v_src_lot.lot_number,
            v_t.quantity, v_t.quantity,
            v_src_lot.expiration_date, NOW()::DATE, TRUE, 'Disponible'
        )
        RETURNING lot_id INTO v_dest_lot_id;

        v_dest_qty_before := 0;
    END IF;

    -- Movimiento: salida de cl¡nica origen
    INSERT INTO inventory_movements (
        lot_id, vaccine_id, clinic_id, worker_id,
        movement_type, quantity, quantity_before, quantity_after,
        reference_id, reference_type, reason
    ) VALUES (
        v_t.lot_id, v_t.vaccine_id, v_t.from_clinic_id, p_worker_id,
        'Transferencia_Salida', v_t.quantity, v_qty_before, v_qty_after,
        p_transfer_id, 'transfer',
        'Transferencia #' || p_transfer_id || ' aceptada'
    );

    -- Movimiento: entrada en cl¡nica destino
    INSERT INTO inventory_movements (
        lot_id, vaccine_id, clinic_id, worker_id,
        movement_type, quantity, quantity_before, quantity_after,
        reference_id, reference_type, reason
    ) VALUES (
        v_dest_lot_id, v_t.vaccine_id, v_t.to_clinic_id, p_worker_id,
        'Transferencia_Entrada', v_t.quantity, v_dest_qty_before, v_dest_qty_before + v_t.quantity,
        p_transfer_id, 'transfer',
        'Transferencia #' || p_transfer_id || ' recibida'
    );

    UPDATE inventory_transfers
    SET transfer_status = 'Recibido',
        approved_by     = p_worker_id,
        notes           = COALESCE(p_notes, notes),
        resolved_at     = NOW()
    WHERE transfer_id = p_transfer_id;

    OPEN p_results FOR SELECT TRUE AS success,
        'Transferencia #' || p_transfer_id || ' recibida correctamente.' AS message;
END;
$$;


ALTER PROCEDURE public.sp_accept_transfer(IN p_transfer_id integer, IN p_worker_id integer, IN p_notes text, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_almacen_dashboard(integer, refcursor, refcursor, refcursor, refcursor); Type: PROCEDURE; Schema: public; Owner: vaccine_user
--

CREATE PROCEDURE public.sp_almacen_dashboard(IN p_clinic_id integer, INOUT p_kpis refcursor, INOUT p_alertas refcursor, INOUT p_movimientos refcursor, INOUT p_lotes_criticos refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- KPIs
    OPEN p_kpis FOR
        SELECT
            COUNT(*) FILTER (WHERE lot_status = 'Disponible')                        AS lotes_activos,
            COALESCE(SUM(quantity_available) FILTER (WHERE lot_status = 'Disponible'), 0) AS dosis_disponibles,
            COUNT(*) FILTER (WHERE lot_status = 'Disponible'
                               AND expiration_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 30) AS lotes_por_vencer,
            COUNT(*) FILTER (WHERE lot_status = 'Agotado')                           AS lotes_agotados,
            COUNT(*) FILTER (WHERE lot_status = 'Caducado')                          AS lotes_caducados,
            COUNT(*) FILTER (WHERE lot_status = 'Disponible'
                               AND (quantity_available <= 5
                                    OR expiration_date <= CURRENT_DATE + 7))          AS alertas_criticas
        FROM vaccine_lots
        WHERE (p_clinic_id IS NULL OR clinic_id = p_clinic_id);

    -- Alertas (crÃ­tico primero)
    OPEN p_alertas FOR
        SELECT
            vl.lot_id, vl.lot_number, vl.quantity_available,
            vl.expiration_date,
            (vl.expiration_date - CURRENT_DATE) AS days_to_expiry,
            v.name AS vaccine_name,
            c.name AS clinic_name,
            CASE
                WHEN vl.expiration_date <= CURRENT_DATE + 7 THEN 'Critico'
                WHEN vl.quantity_available <= 5             THEN 'Critico'
                ELSE 'Advertencia'
            END AS alert_type,
            CASE
                WHEN vl.expiration_date < CURRENT_DATE
                    THEN 'Lote vencido'
                WHEN vl.expiration_date <= CURRENT_DATE + 7
                    THEN 'Vence en ' || (vl.expiration_date - CURRENT_DATE) || ' dÃ­a(s)'
                WHEN vl.quantity_available <= 5
                    THEN 'Stock crÃ­tico: ' || vl.quantity_available || ' dosis'
                ELSE 'Stock bajo: ' || vl.quantity_available || ' dosis'
            END AS alert_reason
        FROM vaccine_lots vl
        JOIN vaccines v ON v.vaccine_id = vl.vaccine_id
        JOIN clinics  c ON c.clinic_id  = vl.clinic_id
        WHERE vl.lot_status = 'Disponible'
          AND (p_clinic_id IS NULL OR vl.clinic_id = p_clinic_id)
          AND (vl.expiration_date <= CURRENT_DATE + 30 OR vl.quantity_available <= 10)
        ORDER BY
            CASE WHEN vl.expiration_date <= CURRENT_DATE + 7 OR vl.quantity_available <= 5
                 THEN 0 ELSE 1 END,
            vl.expiration_date;

    -- Movimientos recientes (Ãºltimos 20)
    OPEN p_movimientos FOR
        SELECT
            im.movement_id, im.created_at, im.movement_type,
            im.quantity, im.quantity_before, im.quantity_after, im.reason,
            vl.lot_number,
            v.name AS vaccine_name,
            c.name AS clinic_name,
            (w.first_name || ' ' || w.last_name) AS worker_name
        FROM inventory_movements im
        JOIN vaccine_lots vl ON vl.lot_id     = im.lot_id
        JOIN vaccines     v  ON v.vaccine_id  = im.vaccine_id
        JOIN clinics      c  ON c.clinic_id   = im.clinic_id
        LEFT JOIN workers w  ON w.worker_id   = im.worker_id
        WHERE (p_clinic_id IS NULL OR im.clinic_id = p_clinic_id)
        ORDER BY im.created_at DESC
        LIMIT 20;

    -- Lotes crÃ­ticos para grÃ¡fica
    OPEN p_lotes_criticos FOR
        SELECT
            vl.lot_id, vl.lot_number, vl.quantity_available,
            vl.expiration_date,
            v.name AS vaccine_name
        FROM vaccine_lots vl
        JOIN vaccines v ON v.vaccine_id = vl.vaccine_id
        WHERE vl.lot_status = 'Disponible'
          AND (p_clinic_id IS NULL OR vl.clinic_id = p_clinic_id)
          AND (vl.quantity_available <= 10 OR vl.expiration_date <= CURRENT_DATE + 30)
        ORDER BY vl.quantity_available ASC
        LIMIT 10;
END;
$$;


ALTER PROCEDURE public.sp_almacen_dashboard(IN p_clinic_id integer, INOUT p_kpis refcursor, INOUT p_alertas refcursor, INOUT p_movimientos refcursor, INOUT p_lotes_criticos refcursor) OWNER TO vaccine_user;

--
-- Name: sp_apply_vaccine(integer, integer, integer, integer, integer, integer, integer, integer, numeric, boolean, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_apply_vaccine(IN p_patient_id integer, IN p_vaccine_id integer, IN p_worker_id integer, IN p_clinic_id integer, IN p_lot_id integer, IN p_scheme_dose_id integer, IN p_appointment_id integer, IN p_application_site_id integer, IN p_patient_temp_c numeric, IN p_had_reaction boolean, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_record_id     INT;
    v_schedule_id   INT;
    v_birth_date    DATE;
    v_age_months    INT;
    v_ideal_months  INT;
    v_min_interval  INT;
    v_last_applied  DATE;
BEGIN
    -- Paciente activo
    SELECT birth_date INTO v_birth_date
    FROM   patients
    WHERE  patient_id = p_patient_id AND is_active = TRUE;
    IF v_birth_date IS NULL THEN
        RAISE EXCEPTION 'El paciente no existe o est  inactivo';
    END IF;

    -- Personal autorizado
    IF NOT EXISTS (
        SELECT 1 FROM workers w JOIN roles r ON r.role_id = w.role_id
        WHERE  w.worker_id = p_worker_id AND w.is_active = TRUE
          AND  r.name IN ('Medico','Enfermero')
    ) THEN
        RAISE EXCEPTION 'Solo m‚dicos o enfermeros pueden aplicar vacunas';
    END IF;

    -- Lote v lido, no vencido, con stock, pertenece a la cl¡nica
    IF NOT EXISTS (
        SELECT 1 FROM vaccine_lots
        WHERE  lot_id = p_lot_id AND clinic_id = p_clinic_id
          AND  expiration_date >= CURRENT_DATE AND quantity_available > 0
    ) THEN
        RAISE EXCEPTION 'Lote no encontrado, vencido, sin stock o no pertenece a esta cl¡nica';
    END IF;

    -- Dosis no duplicada
    IF p_scheme_dose_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM vaccination_records
        WHERE  patient_id = p_patient_id AND scheme_dose_id = p_scheme_dose_id
    ) THEN
        RAISE EXCEPTION 'Esta dosis ya fue aplicada a este paciente';
    END IF;

    -- Validar edad m¡nima para la dosis
    IF p_scheme_dose_id IS NOT NULL THEN
        SELECT ideal_age_months INTO v_ideal_months
        FROM   scheme_doses WHERE dose_id = p_scheme_dose_id;

        v_age_months := (EXTRACT(YEAR  FROM AGE(CURRENT_DATE, v_birth_date)) * 12
                       + EXTRACT(MONTH FROM AGE(CURRENT_DATE, v_birth_date)))::INT;

        IF v_ideal_months IS NOT NULL AND v_age_months < v_ideal_months THEN
            RAISE EXCEPTION 'El paciente no cumple la edad m¡nima requerida para esta dosis';
        END IF;

        -- Validar intervalo m¡nimo entre dosis de la misma vacuna
        SELECT min_interval_days INTO v_min_interval
        FROM   scheme_doses WHERE dose_id = p_scheme_dose_id;

        SELECT MAX(applied_date) INTO v_last_applied
        FROM   vaccination_records
        WHERE  patient_id = p_patient_id AND vaccine_id = p_vaccine_id;

        IF v_last_applied IS NOT NULL AND v_min_interval IS NOT NULL
           AND (CURRENT_DATE - v_last_applied) < v_min_interval THEN
            RAISE EXCEPTION 'No se cumple el intervalo m¡nimo entre dosis (% d¡as)', v_min_interval;
        END IF;

        -- Obtener schedule_id correspondiente
        SELECT schedule_id INTO v_schedule_id
        FROM   patient_vaccine_schedule
        WHERE  patient_id = p_patient_id AND scheme_dose_id = p_scheme_dose_id;
    END IF;

    -- Temperatura v lida
    IF p_patient_temp_c IS NOT NULL AND (p_patient_temp_c < 30 OR p_patient_temp_c > 45) THEN
        RAISE EXCEPTION 'Temperatura corporal inv lida (debe estar entre 30 y 45 øC)';
    END IF;

    -- Insertar registro
    INSERT INTO vaccination_records (
        patient_id, vaccine_id, worker_id, clinic_id, lot_id,
        scheme_dose_id, applied_date, application_site_id,
        appointment_id, patient_schedule_id,
        patient_temp_c, had_reaction, created_at
    )
    VALUES (
        p_patient_id, p_vaccine_id, p_worker_id, p_clinic_id, p_lot_id,
        p_scheme_dose_id, CURRENT_DATE, p_application_site_id,
        p_appointment_id, v_schedule_id,
        p_patient_temp_c, COALESCE(p_had_reaction, FALSE), NOW()
    )
    RETURNING record_id INTO v_record_id;

    -- Los triggers 12 y 15 actualizan patient_vaccine_schedule y appointments

    OPEN p_results FOR
        SELECT TRUE          AS success,
               v_record_id   AS record_id,
               'Vacuna registrada correctamente' AS message;

EXCEPTION WHEN OTHERS THEN
    OPEN p_results FOR
        SELECT FALSE AS success, SQLERRM AS message, NULL::INT AS record_id;
END;
$$;


ALTER PROCEDURE public.sp_apply_vaccine(IN p_patient_id integer, IN p_vaccine_id integer, IN p_worker_id integer, IN p_clinic_id integer, IN p_lot_id integer, IN p_scheme_dose_id integer, IN p_appointment_id integer, IN p_application_site_id integer, IN p_patient_temp_c numeric, IN p_had_reaction boolean, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_assign_nfc_card(integer, character varying, character varying, integer, text, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_assign_nfc_card(IN p_patient_id integer, IN p_uid character varying, IN p_card_type character varying, IN p_issued_by integer, IN p_notes text, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_new_card_id INT;
BEGIN
    IF TRIM(COALESCE(p_uid, '')) = '' THEN
        RAISE EXCEPTION 'El UID de la tarjeta es obligatorio';
    END IF;

    -- Solo bloquear si existe tarjeta ACTIVA con ese UID
    IF EXISTS (SELECT 1 FROM nfc_cards WHERE uid = TRIM(p_uid) AND status = 'Activa') THEN
        RAISE EXCEPTION 'Ya existe una tarjeta activa con el UID %', p_uid;
    END IF;

    IF EXISTS (
        SELECT 1 FROM nfc_cards
        WHERE patient_id = p_patient_id AND status = 'Activa'
    ) THEN
        RAISE EXCEPTION 'El paciente ya tiene una tarjeta NFC activa. Desactívala antes de asignar una nueva.';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM workers WHERE worker_id = p_issued_by
    ) THEN
        RAISE EXCEPTION 'El trabajador emisor % no existe', p_issued_by;
    END IF;

    INSERT INTO nfc_cards (
        patient_id, uid, card_type,
        issued_date, issued_by, status, nfc_card_notes
    )
    VALUES (
        p_patient_id,
        TRIM(p_uid),
        NULLIF(TRIM(COALESCE(p_card_type, '')), ''),
        CURRENT_DATE,
        p_issued_by,
        'Activa',
        NULLIF(TRIM(COALESCE(p_notes, '')), '')
    )
    RETURNING nfc_card_id INTO v_new_card_id;

    -- Sincronizar patients.nfc_id
    UPDATE patients
    SET nfc_id     = TRIM(p_uid),
        updated_at = NOW()
    WHERE patient_id = p_patient_id;

    OPEN p_results FOR
        SELECT
            TRUE          AS success,
            'Tarjeta NFC asignada correctamente' AS message,
            v_new_card_id AS nfc_card_id;
END;
$$;


ALTER PROCEDURE public.sp_assign_nfc_card(IN p_patient_id integer, IN p_uid character varying, IN p_card_type character varying, IN p_issued_by integer, IN p_notes text, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_calculate_patient_adherence(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_calculate_patient_adherence(IN p_patient_id integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
    WITH esquema_actual AS (
        SELECT sd.dose_id, sd.vaccine_id, v.name AS vacuna
        FROM scheme_doses sd
        JOIN vaccination_scheme vs ON sd.scheme_id = vs.scheme_id
        JOIN vaccines v ON sd.vaccine_id = v.vaccine_id
        WHERE vs.is_current = TRUE
    ),
    dosis_aplicadas AS (
        SELECT patient_id, vaccine_id, COUNT(*) as total_aplicadas
        FROM vaccination_records
        GROUP BY patient_id, vaccine_id
    )
    SELECT
        p.curp,
        p.first_name || ' ' || p.last_name AS paciente,
        COUNT(ea.dose_id) AS dosis_requeridas,
        COALESCE(SUM(da.total_aplicadas), 0) AS dosis_totales_recibidas,
        ROUND((COALESCE(SUM(da.total_aplicadas), 0) * 100.0 / COUNT(ea.dose_id)), 2) || '%' AS porcentaje_adherencia
    FROM patients p
    CROSS JOIN esquema_actual ea
    LEFT JOIN dosis_aplicadas da ON p.patient_id = da.patient_id AND ea.vaccine_id = da.vaccine_id
    WHERE p.patient_id = p_patient_id
    GROUP BY p.patient_id;
END;
$$;


ALTER PROCEDURE public.sp_calculate_patient_adherence(IN p_patient_id integer, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_cancel_appointment(integer, text, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_cancel_appointment(IN p_appointment_id integer, IN p_reason text, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN

    IF EXISTS (
        SELECT 1
        FROM appointments
        WHERE appointment_id = p_appointment_id
          AND appointment_status = 'Completada'
    ) THEN
        RAISE EXCEPTION
            'No se puede cancelar una cita completada.';
    END IF;

    UPDATE appointments
    SET
        appointment_status = 'Cancelada',
        cancel_reason = p_reason,
        appointment_notes =
            COALESCE(appointment_notes || E'\n', '')
            || '[' || CURRENT_DATE || '] Cancelada. Motivo: '
            || COALESCE(p_reason, 'Sin motivo')
    WHERE appointment_id = p_appointment_id;

    OPEN p_results FOR
    SELECT
        appointment_id,
        patient_schedule_id,
        clinic_id,
        scheduled_at,
        appointment_status,
        cancel_reason,
        appointment_notes
    FROM appointments
    WHERE appointment_id = p_appointment_id;

END;
$$;


ALTER PROCEDURE public.sp_cancel_appointment(IN p_appointment_id integer, IN p_reason text, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_cancel_transfer(integer, integer, text, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_cancel_transfer(IN p_transfer_id integer, IN p_worker_id integer, IN p_reason text, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE v_status VARCHAR(20);
BEGIN
    SELECT transfer_status INTO v_status
    FROM inventory_transfers WHERE transfer_id = p_transfer_id FOR UPDATE;

    IF NOT FOUND THEN
        OPEN p_results FOR SELECT FALSE AS success, 'Transferencia no encontrada.' AS message;
        RETURN;
    END IF;

    IF v_status <> 'Pendiente' THEN
        OPEN p_results FOR SELECT FALSE AS success,
            'Solo se pueden cancelar transferencias Pendientes. Estado actual: ' || v_status AS message;
        RETURN;
    END IF;

    UPDATE inventory_transfers
    SET transfer_status = 'Cancelado',
        notes           = p_reason,
        resolved_at     = NOW()
    WHERE transfer_id = p_transfer_id;

    OPEN p_results FOR SELECT TRUE AS success,
        'Transferencia #' || p_transfer_id || ' cancelada.' AS message;
END;
$$;


ALTER PROCEDURE public.sp_cancel_transfer(IN p_transfer_id integer, IN p_worker_id integer, IN p_reason text, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_complete_appointment(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_complete_appointment(IN p_appointment_id integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_schedule_id INT;
BEGIN

    SELECT patient_schedule_id
    INTO v_schedule_id
    FROM appointments
    WHERE appointment_id = p_appointment_id;

    UPDATE appointments
    SET appointment_status = 'Completada'
    WHERE appointment_id = p_appointment_id;

    UPDATE patient_vaccine_schedule
    SET status = 'Aplicada'
    WHERE schedule_id = v_schedule_id;

    OPEN p_results FOR
    SELECT
        a.appointment_id,
        a.patient_schedule_id,
        a.clinic_id,
        a.scheduled_at,
        a.appointment_status,
        pvs.status AS vaccine_status
    FROM appointments a
    JOIN patient_vaccine_schedule pvs
        ON a.patient_schedule_id = pvs.schedule_id
    WHERE a.appointment_id = p_appointment_id;

END;
$$;


ALTER PROCEDURE public.sp_complete_appointment(IN p_appointment_id integer, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_confirm_appointment(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_confirm_appointment(IN p_appointment_id integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN

    IF NOT EXISTS (
        SELECT 1
        FROM appointments
        WHERE appointment_id = p_appointment_id
          AND appointment_status = 'Pendiente confirmaci¢n'
    ) THEN
        RAISE EXCEPTION
            'La cita no puede confirmarse.';
    END IF;

    UPDATE appointments
    SET
        appointment_status = 'Confirmada',
        confirmed_at = CURRENT_TIMESTAMP,
        appointment_notes =
            COALESCE(appointment_notes || E'\n', '')
            || '[' || CURRENT_DATE || '] Confirmada por tutor.'
    WHERE appointment_id = p_appointment_id;

    OPEN p_results FOR
    SELECT
        appointment_id,
        patient_schedule_id,
        clinic_id,
        scheduled_at,
        appointment_status,
        confirmed_at,
        appointment_notes
    FROM appointments
    WHERE appointment_id = p_appointment_id;

END;
$$;


ALTER PROCEDURE public.sp_confirm_appointment(IN p_appointment_id integer, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_create_appointment(integer, integer, integer, integer, timestamp without time zone, character varying, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_create_appointment(IN p_patient_id integer, IN p_worker_id integer, IN p_clinic_id integer, IN p_area_id integer, IN p_scheduled_at timestamp without time zone, IN p_reason character varying, INOUT p_results refcursor)
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



    OPEN p_results FOR

        SELECT v_appointment_id AS appointment_id;

END;

$$;


ALTER PROCEDURE public.sp_create_appointment(IN p_patient_id integer, IN p_worker_id integer, IN p_clinic_id integer, IN p_area_id integer, IN p_scheduled_at timestamp without time zone, IN p_reason character varying, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_create_appointment(integer, integer, integer, integer, timestamp without time zone, character varying, boolean, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_create_appointment(IN p_patient_id integer, IN p_worker_id integer, IN p_clinic_id integer, IN p_area_id integer, IN p_scheduled_at timestamp without time zone, IN p_reason character varying, IN p_requires_tutor boolean, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_appointment_id INT;
    v_initial_status VARCHAR(50);
BEGIN
    -- Las citas generadas autom ticamente por el esquema de vacunaci¢n
    -- arrancan en 'Pendiente confirmaci¢n'; las manuales van directo a 'Programada'.
    v_initial_status := CASE WHEN p_requires_tutor THEN 'Pendiente confirmaci¢n'
                             ELSE 'Programada'
                        END;

    INSERT INTO appointments (
        patient_id, worker_id, clinic_id, area_id,
        scheduled_at, appointment_status, reason, duration_min
    )
    VALUES (
        p_patient_id, p_worker_id, p_clinic_id, p_area_id,
        p_scheduled_at, v_initial_status, p_reason, 15
    )
    RETURNING appointments.appointment_id INTO v_appointment_id;

    OPEN p_results FOR
        SELECT v_appointment_id AS appointment_id;
END;
$$;


ALTER PROCEDURE public.sp_create_appointment(IN p_patient_id integer, IN p_worker_id integer, IN p_clinic_id integer, IN p_area_id integer, IN p_scheduled_at timestamp without time zone, IN p_reason character varying, IN p_requires_tutor boolean, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_create_appointment(integer, integer, integer, timestamp without time zone, character varying, boolean, integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_create_appointment(IN p_worker_id integer, IN p_clinic_id integer, IN p_area_id integer, IN p_scheduled_at timestamp without time zone, IN p_reason character varying, IN p_requires_tutor boolean, IN p_patient_schedule_id integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_appointment_id INT;
    v_initial_status VARCHAR(50);
    v_patient_id INT;
BEGIN

    --VALIDAR QUE EL PATIENT SCHEDULE EXISTA
    SELECT patient_id
    INTO v_patient_id
    FROM patient_vaccine_schedule
    WHERE schedule_id = p_patient_schedule_id;

    IF v_patient_id IS NULL THEN
        RAISE EXCEPTION
            'El esquema de vacunaci¢n especificado no existe.';
    END IF;


    --VALIDAR FECHA
    IF p_scheduled_at < NOW() THEN
        RAISE EXCEPTION
            'No se puede agendar una cita en una fecha pasada.';
    END IF;


    --VALIDAR DISPONIBILIDAD DEL AREA
    IF EXISTS (
        SELECT 1
        FROM appointments
        WHERE clinic_id = p_clinic_id
          AND area_id = p_area_id
          AND scheduled_at = p_scheduled_at
          AND appointment_status NOT IN (
                'Cancelada',
                'No Show',
                'Reagendada'
          )
    ) THEN
        RAISE EXCEPTION
            'Ya existe una cita programada para esa  rea y horario.';
    END IF;


    --VALIDAR DISPONIBILIDAD DEL TRABAJADOR
    IF EXISTS (
        SELECT 1
        FROM appointments
        WHERE worker_id = p_worker_id
          AND scheduled_at = p_scheduled_at
          AND appointment_status NOT IN (
                'Cancelada',
                'No Show',
                'Reagendada'
          )
    ) THEN
        RAISE EXCEPTION
            'El trabajador ya tiene una cita asignada en ese horario.';
    END IF;


    --VALIDAR QUE EL ESQUEMA NO ESTE APLICADO
    IF EXISTS (
        SELECT 1
        FROM patient_vaccine_schedule
        WHERE schedule_id = p_patient_schedule_id
          AND status = 'Aplicada'
    ) THEN
        RAISE EXCEPTION
            'La dosis seleccionada ya fue aplicada.';
    END IF;


    --VALIDAR QUE NO EXISTA OTRA CITA ACTIVA PARA ESA DOSIS
    IF EXISTS (
        SELECT 1
        FROM appointments
        WHERE patient_schedule_id = p_patient_schedule_id
          AND appointment_status IN (
                'Pendiente confirmaci¢n',
                'Confirmada',
                'Programada'
          )
    ) THEN
        RAISE EXCEPTION
            'Ya existe una cita activa para esta dosis.';
    END IF;


    --DEFINIR ESTADO INICIAL
    v_initial_status :=
        CASE
            WHEN p_requires_tutor THEN
                'Pendiente confirmaci¢n'
            ELSE
                'Confirmada'
        END;


    --CREAR CITA
    INSERT INTO appointments (
        patient_schedule_id,
        worker_id,
        clinic_id,
        area_id,
        scheduled_at,
        appointment_status,
        reason,
        duration_min,
        created_at,
        confirmed_at
    )
    VALUES (
        p_patient_schedule_id,
        p_worker_id,
        p_clinic_id,
        p_area_id,
        p_scheduled_at,
        v_initial_status,
        p_reason,
        15,
        CURRENT_TIMESTAMP,

        CASE
            WHEN p_requires_tutor THEN NULL
            ELSE CURRENT_TIMESTAMP
        END
    )
    RETURNING appointment_id
    INTO v_appointment_id;


    --RETORNAR RESULTADO
    OPEN p_results FOR
    SELECT
        a.appointment_id,
        a.patient_schedule_id,
        p.patient_id,
        TRIM(p.first_name || ' ' || p.last_name) AS patient_name,
        a.worker_id,
        a.clinic_id,
        a.area_id,
        a.scheduled_at,
        a.appointment_status,
        a.reason,
        a.duration_min,
        a.created_at,
        a.confirmed_at
    FROM appointments a
    JOIN patient_vaccine_schedule pvs
        ON a.patient_schedule_id = pvs.schedule_id
    JOIN patients p
        ON pvs.patient_id = p.patient_id
    WHERE a.appointment_id = v_appointment_id;

END;
$$;


ALTER PROCEDURE public.sp_create_appointment(IN p_worker_id integer, IN p_clinic_id integer, IN p_area_id integer, IN p_scheduled_at timestamp without time zone, IN p_reason character varying, IN p_requires_tutor boolean, IN p_patient_schedule_id integer, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_create_appointment(integer, integer, integer, integer, timestamp without time zone, text, integer, character varying, integer, integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_create_appointment(IN p_patient_id integer, IN p_clinic_id integer, IN p_area_id integer, IN p_worker_id integer, IN p_scheduled_at timestamp without time zone, IN p_reason text, IN p_patient_schedule_id integer, IN p_created_by_role character varying, IN p_created_by_worker_id integer, IN p_created_by_guardian_id integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
    DECLARE
        v_appointment_id INT;
    BEGIN
        -- Validar paciente activo
        IF NOT EXISTS (
            SELECT 1 FROM patients WHERE patient_id = p_patient_id AND is_active = TRUE
        ) THEN
            RAISE EXCEPTION 'El paciente no existe o est  inactivo';
        END IF;

        -- Validar cl¡nica activa
        IF NOT EXISTS (
            SELECT 1 FROM clinics WHERE clinic_id = p_clinic_id AND is_active = TRUE
        ) THEN
            RAISE EXCEPTION 'La cl¡nica no existe o est  inactiva';
        END IF;

        -- Validar fecha futura
        IF p_scheduled_at <= NOW() THEN
            RAISE EXCEPTION 'La cita debe ser en el futuro';
        END IF;

        -- Validar que el schedule_id corresponde al paciente y no est  aplicado
        IF p_patient_schedule_id IS NOT NULL THEN
            IF NOT EXISTS (
                SELECT 1 FROM patient_vaccine_schedule
                WHERE  schedule_id = p_patient_schedule_id
                AND  patient_id  = p_patient_id
                AND  status     <> 'Aplicada'
            ) THEN
                RAISE EXCEPTION 'La dosis no pertenece a este paciente o ya fue aplicada';
            END IF;

            -- Verificar que no exista ya una cita activa para esta dosis
            IF EXISTS (
                SELECT 1 FROM appointments
                WHERE  patient_schedule_id = p_patient_schedule_id
                AND  appointment_status NOT IN ('Cancelada', 'No Show', 'Completada', 'Reagendada')
            ) THEN
                RAISE EXCEPTION 'Ya existe una cita activa para esta dosis';
            END IF;
        END IF;

        -- Validar que el paciente no tenga otra cita activa que se solape
        IF EXISTS (
            SELECT 1 FROM appointments
            WHERE  patient_id = p_patient_id
            AND    appointment_status NOT IN ('Cancelada', 'No Show', 'Completada', 'Reagendada')
            AND    scheduled_at < p_scheduled_at + (duration_min * INTERVAL '1 minute')
            AND    scheduled_at + (duration_min * INTERVAL '1 minute') > p_scheduled_at
        ) THEN
            RAISE EXCEPTION 'El paciente ya tiene una cita programada que se solapa con ese horario';
        END IF;

        -- Verificar horario laboral solo si el trabajador tiene horarios configurados en esa cl¡nica
        IF p_worker_id IS NOT NULL THEN
            IF EXISTS (
                SELECT 1 FROM worker_schedules
                WHERE worker_id = p_worker_id AND clinic_id = p_clinic_id
            ) THEN
                IF NOT EXISTS (
                    SELECT 1
                    FROM   worker_schedules ws
                    WHERE  ws.worker_id   = p_worker_id
                    AND    ws.clinic_id   = p_clinic_id
                    AND    ws.day_of_week = EXTRACT(ISODOW FROM p_scheduled_at)::SMALLINT
                    AND    ws.entry_time  <= p_scheduled_at::TIME
                    AND    ws.exit_time   >  p_scheduled_at::TIME
                ) THEN
                    RAISE EXCEPTION 'El trabajador no tiene horario laboral en esa clinica para la fecha y hora indicadas';
                END IF;
            END IF;
        END IF;

        -- Verificar solapamiento por duracion del trabajador (ventana de 20 min)
        IF p_worker_id IS NOT NULL THEN
            IF EXISTS (
                SELECT 1
                FROM   appointments a
                WHERE  a.worker_id          = p_worker_id
                AND  a.appointment_status NOT IN ('Cancelada', 'No Show', 'Reagendada')
                AND  a.scheduled_at < p_scheduled_at + (20 * INTERVAL '1 minute')
                AND  a.scheduled_at + (a.duration_min * INTERVAL '1 minute') > p_scheduled_at
                AND  a.scheduled_at <> p_scheduled_at
            ) THEN
                RAISE EXCEPTION 'El trabajador ya tiene una cita que se solapa en ese rango horario';
            END IF;
        END IF;

        -- Verificar disponibilidad exacta del trabajador (constraint UNIQUE)
        IF p_worker_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM appointments
            WHERE  worker_id         = p_worker_id
            AND  scheduled_at      = p_scheduled_at
            AND  appointment_status NOT IN ('Cancelada', 'No Show', 'Reagendada')
        ) THEN
            RAISE EXCEPTION 'El trabajador ya tiene una cita agendada exactamente a esa hora';
        END IF;

        -- Verificar capacidad concurrente del area
        IF p_area_id IS NOT NULL THEN
            IF EXISTS (
                SELECT 1 FROM clinic_areas ca
                WHERE  ca.area_id  = p_area_id
                AND  ca.capacity IS NOT NULL
            ) THEN
                IF (
                    SELECT COUNT(*)
                    FROM   appointments a
                    WHERE  a.clinic_id          = p_clinic_id
                    AND  a.area_id            = p_area_id
                    AND  a.appointment_status NOT IN ('Cancelada', 'No Show', 'Reagendada')
                    AND  a.scheduled_at < p_scheduled_at + (20 * INTERVAL '1 minute')
                    AND  a.scheduled_at + (a.duration_min * INTERVAL '1 minute') > p_scheduled_at
                ) >= (
                    SELECT ca.capacity FROM clinic_areas ca WHERE ca.area_id = p_area_id
                )
                THEN
                    RAISE EXCEPTION 'El area ha alcanzado su capacidad maxima de citas en ese horario';
                END IF;
            END IF;
        END IF;

        -- Verificar disponibilidad exacta del area (constraint UNIQUE)
        IF p_area_id IS NOT NULL AND EXISTS (
            SELECT 1 FROM appointments
            WHERE  clinic_id         = p_clinic_id
            AND  area_id           = p_area_id
            AND  scheduled_at      = p_scheduled_at
            AND  appointment_status NOT IN ('Cancelada', 'No Show', 'Reagendada')
        ) THEN
            RAISE EXCEPTION 'El area no esta disponible en ese horario exacto';
        END IF;

        INSERT INTO appointments (
            patient_id, clinic_id, area_id, worker_id,
            patient_schedule_id, scheduled_at, reason,
            appointment_status, duration_min,
            created_by_role, created_by_worker_id, created_by_guardian_id,
            created_at
        )
        VALUES (
            p_patient_id, p_clinic_id, p_area_id, p_worker_id,
            p_patient_schedule_id, p_scheduled_at, p_reason,
            'Programada', 20,
            p_created_by_role, p_created_by_worker_id, p_created_by_guardian_id,
            NOW()
        )
        RETURNING appointment_id INTO v_appointment_id;

        OPEN p_results FOR
            SELECT TRUE              AS success,
                v_appointment_id  AS appointment_id,
                'Cita creada correctamente' AS message;

    EXCEPTION WHEN OTHERS THEN
        OPEN p_results FOR
            SELECT FALSE AS success, SQLERRM AS message, NULL::INT AS appointment_id;
    END;
    $$;


ALTER PROCEDURE public.sp_create_appointment(IN p_patient_id integer, IN p_clinic_id integer, IN p_area_id integer, IN p_worker_id integer, IN p_scheduled_at timestamp without time zone, IN p_reason text, IN p_patient_schedule_id integer, IN p_created_by_role character varying, IN p_created_by_worker_id integer, IN p_created_by_guardian_id integer, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_create_transfer(integer, integer, integer, integer, text, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_create_transfer(IN p_lot_id integer, IN p_to_clinic_id integer, IN p_quantity integer, IN p_worker_id integer, IN p_reason text, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_lot         RECORD;
    v_transfer_id INT;
BEGIN
    SELECT vl.lot_id, vl.vaccine_id, vl.clinic_id,
           vl.quantity_available, vl.lot_status,
           v.name AS vaccine_name, c.name AS clinic_name
    INTO v_lot
    FROM vaccine_lots vl
    JOIN vaccines v ON v.vaccine_id = vl.vaccine_id
    JOIN clinics  c ON c.clinic_id  = vl.clinic_id
    WHERE vl.lot_id = p_lot_id;

    IF NOT FOUND THEN
        OPEN p_results FOR SELECT FALSE AS success, 'Lote no encontrado.' AS message, NULL::INT AS transfer_id;
        RETURN;
    END IF;

    IF v_lot.lot_status <> 'Disponible' THEN
        OPEN p_results FOR SELECT FALSE AS success,
            'El lote estÃ¡ en estado ' || v_lot.lot_status || ' y no puede transferirse.' AS message,
            NULL::INT AS transfer_id;
        RETURN;
    END IF;

    IF v_lot.quantity_available < p_quantity THEN
        OPEN p_results FOR SELECT FALSE AS success,
            'Stock insuficiente. Disponible: ' || v_lot.quantity_available || ', solicitado: ' || p_quantity AS message,
            NULL::INT AS transfer_id;
        RETURN;
    END IF;

    IF v_lot.clinic_id = p_to_clinic_id THEN
        OPEN p_results FOR SELECT FALSE AS success,
            'La clÃ­nica destino debe ser diferente a la clÃ­nica origen.' AS message,
            NULL::INT AS transfer_id;
        RETURN;
    END IF;

    INSERT INTO inventory_transfers (
        lot_id, vaccine_id, from_clinic_id, to_clinic_id,
        quantity, transfer_status, requested_by, reason
    ) VALUES (
        p_lot_id, v_lot.vaccine_id, v_lot.clinic_id, p_to_clinic_id,
        p_quantity, 'Pendiente', p_worker_id, p_reason
    ) RETURNING transfer_id INTO v_transfer_id;

    OPEN p_results FOR SELECT TRUE AS success,
        'Transferencia #' || v_transfer_id || ' creada correctamente.' AS message,
        v_transfer_id AS transfer_id;
END;
$$;


ALTER PROCEDURE public.sp_create_transfer(IN p_lot_id integer, IN p_to_clinic_id integer, IN p_quantity integer, IN p_worker_id integer, IN p_reason text, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_create_vaccine_lot(integer, integer, character varying, integer, date, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_create_vaccine_lot(IN p_vaccine_id integer, IN p_clinic_id integer, IN p_lot_number character varying, IN p_quantity_received integer, IN p_expiration_date date, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_lot_id INT;
BEGIN
    INSERT INTO vaccine_lots (
        vaccine_id, clinic_id, lot_number,
        quantity_received, quantity_available, expiration_date, received_date, is_active
    )
    VALUES (
        p_vaccine_id, p_clinic_id, p_lot_number,
        p_quantity_received, p_quantity_received, p_expiration_date, NOW()::DATE,
        (p_expiration_date >= NOW()::DATE)
    )
    RETURNING vaccine_lots.lot_id INTO v_lot_id;

    OPEN p_results FOR
        SELECT v_lot_id AS lot_id;
END;
$$;


ALTER PROCEDURE public.sp_create_vaccine_lot(IN p_vaccine_id integer, IN p_clinic_id integer, IN p_lot_number character varying, IN p_quantity_received integer, IN p_expiration_date date, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_dashboard_charts(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_dashboard_charts(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
    WITH age_groups AS (
        SELECT
            p.patient_id,
            CASE
                WHEN DATE_PART('year', AGE(p.birth_date)) < 1  THEN U&'< 1 a\00F1o'
                WHEN DATE_PART('year', AGE(p.birth_date)) < 3  THEN U&'1-2 a\00F1os'
                WHEN DATE_PART('year', AGE(p.birth_date)) < 6  THEN U&'3-5 a\00F1os'
                WHEN DATE_PART('year', AGE(p.birth_date)) < 12 THEN U&'6-11 a\00F1os'
                ELSE U&'12+ a\00F1os'
            END AS age_group,
            DATE_PART('year', AGE(p.birth_date)) AS age_years
        FROM patients p
        WHERE p.is_active = TRUE
    ),
    complete_patients AS (
        SELECT p.patient_id
        FROM patients p
        WHERE p.is_active = TRUE
          AND NOT EXISTS (
              SELECT 1 FROM scheme_doses sd
              WHERE NOT EXISTS (
                  SELECT 1 FROM vaccination_records vr
                  WHERE vr.patient_id    = p.patient_id
                    AND vr.scheme_dose_id = sd.dose_id
              )
          )
    ),
    coverage_by_age AS (
        SELECT
            ag.age_group AS label,
            ROUND(
                COUNT(DISTINCT cp.patient_id)::NUMERIC /
                NULLIF(COUNT(DISTINCT ag.patient_id)::NUMERIC, 0) * 100
            , 1) AS value,
            MIN(ag.age_years) AS row_order,
            1 AS chart_order
        FROM age_groups ag
        LEFT JOIN complete_patients cp ON ag.patient_id = cp.patient_id
        GROUP BY ag.age_group
    ),
    monthly_doses AS (
        SELECT
            TO_CHAR(DATE_TRUNC('month', applied_date), 'Mon YY') AS label,
            COUNT(*)::NUMERIC AS value,
            EXTRACT(EPOCH FROM DATE_TRUNC('month', applied_date)) AS row_order,
            2 AS chart_order
        FROM vaccination_records
        WHERE applied_date >= DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '11 months'
        GROUP BY DATE_TRUNC('month', applied_date)
    ),
    delay_all AS (
        SELECT
            v.name AS label,
            ROUND(
                COUNT(DISTINCT CASE
                    WHEN (p.birth_date + (sd.ideal_age_months || ' months')::INTERVAL)::DATE < CURRENT_DATE
                         AND NOT EXISTS (
                             SELECT 1 FROM vaccination_records vr2
                             WHERE vr2.patient_id    = p.patient_id
                               AND vr2.scheme_dose_id = sd.dose_id
                         )
                    THEN p.patient_id
                END)::NUMERIC /
                NULLIF(COUNT(DISTINCT p.patient_id)::NUMERIC, 0) * 100
            , 1) AS value
        FROM patients p
        CROSS JOIN scheme_doses sd
        JOIN vaccines v ON sd.vaccine_id = v.vaccine_id
        WHERE p.is_active = TRUE
        GROUP BY v.name
    ),
    delay_top5 AS (
        SELECT label, value,
               ROW_NUMBER() OVER (ORDER BY value DESC) AS row_order,
               3 AS chart_order
        FROM delay_all
        ORDER BY value DESC
        LIMIT 5
    )
    SELECT chart_order, row_order, 'coverage'::TEXT AS chart, label, value
    FROM coverage_by_age
    UNION ALL
    SELECT chart_order, row_order, 'monthly'::TEXT, label, value
    FROM monthly_doses
    UNION ALL
    SELECT chart_order, row_order, 'delay'::TEXT, label, value
    FROM delay_top5
    ORDER BY chart_order, row_order;

END;
$$;


ALTER PROCEDURE public.sp_dashboard_charts(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_dashboard_clinica(integer, date, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_dashboard_clinica(IN p_clinic_id integer, IN p_fecha date, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_fecha DATE := COALESCE(p_fecha, CURRENT_DATE);
BEGIN
    IF NOT EXISTS (SELECT 1 FROM clinics WHERE clinic_id = p_clinic_id AND is_active = TRUE) THEN
        RAISE EXCEPTION 'Cl¡nica no encontrada o inactiva';
    END IF;

    OPEN p_results FOR
        SELECT
            a.appointment_id,
            a.scheduled_at,
            a.appointment_status,
            a.reason,
            a.duration_min,
            a.created_by_role,
            a.appointment_notes,
            a.cancel_reason,
            -- Paciente
            p.patient_id,
            TRIM(p.first_name || ' ' || p.last_name)                    AS patient_name,
            p.birth_date,
            DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT      AS age_years,
            -- M‚dico asignado
            COALESCE(TRIM(w.first_name || ' ' || w.last_name), 'Sin asignar') AS worker_name,
            -- Vacuna del esquema (si aplica)
            COALESCE(v.name, 'No especificada')                          AS vaccine_name,
            COALESCE(sd.dose_label, '-')                                 AS dose_label,
            -- µrea
            COALESCE(ca.name, '-')                                       AS area_name,
            -- Tutor principal
            COALESCE(TRIM(g.first_name || ' ' || g.last_name), 'Sin tutor') AS guardian_name,
            COALESCE(
                (SELECT gp.phone FROM guardian_phones gp
                 WHERE  gp.guardian_id = g.guardian_id
                 ORDER  BY gp.is_primary DESC LIMIT 1),
                '-'
            )                                                             AS guardian_phone
        FROM   appointments a
        JOIN   patients     p  ON p.patient_id   = a.patient_id
        LEFT JOIN workers   w  ON w.worker_id    = a.worker_id
        LEFT JOIN clinic_areas ca ON ca.area_id  = a.area_id
        LEFT JOIN patient_vaccine_schedule pvs ON pvs.schedule_id = a.patient_schedule_id
        LEFT JOIN scheme_doses sd ON sd.dose_id  = pvs.scheme_dose_id
        LEFT JOIN vaccines     v  ON v.vaccine_id = sd.vaccine_id
        LEFT JOIN LATERAL (
            SELECT grd.guardian_id, grd.first_name, grd.last_name
            FROM   patient_guardian_relations pgr
            JOIN   guardians grd ON grd.guardian_id = pgr.guardian_id
            WHERE  pgr.patient_id = a.patient_id
            ORDER  BY pgr.is_primary DESC LIMIT 1
        ) g ON TRUE
        WHERE  a.clinic_id          = p_clinic_id
          AND  a.scheduled_at::DATE = v_fecha
          AND  a.appointment_status NOT IN ('Cancelada','No Show')
        ORDER  BY a.scheduled_at ASC;
END;
$$;


ALTER PROCEDURE public.sp_dashboard_clinica(IN p_clinic_id integer, IN p_fecha date, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_dashboard_kpis(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_dashboard_kpis(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_today            DATE := CURRENT_DATE;
    v_first_of_month   DATE := DATE_TRUNC('month', CURRENT_DATE)::DATE;
    v_first_of_week    DATE := DATE_TRUNC('week',  CURRENT_DATE)::DATE;
    v_prev_month_start DATE := (DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 month')::DATE;
    v_prev_month_end   DATE := (DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '1 day')::DATE;
BEGIN
    OPEN p_results FOR
    WITH
 
    -- Total pacientes activos
    total AS (
        SELECT COUNT(*)::INT AS total_patients
        FROM   patients
        WHERE  is_active = TRUE
    ),
 
    -- Cobertura: % de pacientes con todas las dosis del esquema aplicadas
    coverage AS (
        SELECT
            ROUND(
                COUNT(DISTINCT CASE
                    WHEN NOT EXISTS (
                        SELECT 1 FROM scheme_doses sd
                        WHERE NOT EXISTS (
                            SELECT 1 FROM vaccination_records vr
                            WHERE vr.patient_id     = p.patient_id
                              AND vr.scheme_dose_id  = sd.dose_id
                        )
                    ) THEN p.patient_id
                END)::NUMERIC
                / NULLIF(COUNT(DISTINCT p.patient_id)::NUMERIC, 0) * 100
            , 1)::NUMERIC AS coverage_pct,
 
            -- Tendencia: dosis este mes menos dosis mes anterior
            (
                SELECT COUNT(*) FROM vaccination_records
                WHERE applied_date >= v_first_of_month
                  AND applied_date <= v_today
            ) -
            (
                SELECT COUNT(*) FROM vaccination_records
                WHERE applied_date >= v_prev_month_start
                  AND applied_date <= v_prev_month_end
            )                 AS coverage_trend_raw
        FROM patients p
        WHERE p.is_active = TRUE
    ),
 
    -- Pacientes con al menos 1 dosis atrasada
    delayed AS (
        SELECT COUNT(DISTINCT p.patient_id)::INT AS delayed_patients
        FROM   patients p
        JOIN   scheme_doses sd ON TRUE
        WHERE  p.is_active = TRUE
          AND  (p.birth_date + (sd.ideal_age_months || ' months')::INTERVAL)::DATE < v_today
          AND  NOT EXISTS (
                   SELECT 1 FROM vaccination_records vr
                   WHERE vr.patient_id     = p.patient_id
                     AND vr.scheme_dose_id  = sd.dose_id
               )
    ),
 
    -- Pacientes con 2+ dosis atrasadas (críticos)
    critical AS (
        SELECT COUNT(*)::INT AS patients_critical
        FROM (
            SELECT p.patient_id
            FROM   patients p
            JOIN   scheme_doses sd ON TRUE
            WHERE  p.is_active = TRUE
              AND  (p.birth_date + (sd.ideal_age_months || ' months')::INTERVAL)::DATE < v_today
              AND  NOT EXISTS (
                       SELECT 1 FROM vaccination_records vr
                       WHERE vr.patient_id     = p.patient_id
                         AND vr.scheme_dose_id  = sd.dose_id
                   )
            GROUP  BY p.patient_id
            HAVING COUNT(*) >= 2
        ) sub
    ),
 
    -- Dosis aplicadas: hoy / semana / mes
    doses AS (
        SELECT
            COUNT(*) FILTER (WHERE applied_date = v_today)           ::INT AS applications_today,
            COUNT(*) FILTER (WHERE applied_date >= v_first_of_week)  ::INT AS doses_this_week,
            COUNT(*) FILTER (WHERE applied_date >= v_first_of_month) ::INT AS doses_this_month
        FROM vaccination_records
    ),
 
    -- Tendencia mensual %
    monthly_trend AS (
        SELECT
            CASE
                WHEN prev.cnt = 0 THEN 0
                ELSE ROUND((curr.cnt - prev.cnt)::NUMERIC / prev.cnt * 100, 1)::INT
            END AS monthly_trend
        FROM (
            SELECT COUNT(*)::NUMERIC AS cnt
            FROM   vaccination_records
            WHERE  applied_date >= v_first_of_month
              AND  applied_date <= v_today
        ) curr,
        (
            SELECT COUNT(*)::NUMERIC AS cnt
            FROM   vaccination_records
            WHERE  applied_date >= v_prev_month_start
              AND  applied_date <= v_prev_month_end
        ) prev
    ),
 
    -- Pacientes con alguna dosis ya vencida (fecha ideal pasada, sin aplicar)
    expired AS (
        SELECT COUNT(DISTINCT p.patient_id)::INT AS expired_doses
        FROM   patients p
        JOIN   scheme_doses sd ON TRUE
        WHERE  p.is_active = TRUE
          AND  (p.birth_date + (sd.ideal_age_months || ' months')::INTERVAL)::DATE < v_today
          AND  NOT EXISTS (
                   SELECT 1 FROM vaccination_records vr
                   WHERE vr.patient_id     = p.patient_id
                     AND vr.scheme_dose_id  = sd.dose_id
               )
    ),
 
    -- Nuevos pacientes registrados este mes
    new_patients AS (
        SELECT COUNT(*)::INT AS new_patients_month
        FROM   patients
        WHERE  is_active   = TRUE
          AND  created_at::DATE >= v_first_of_month
    ),
 
    -- Lotes que vencen en los próximos 7 días
    expiring_lots AS (
        SELECT COUNT(*)::INT AS expiring_lots_week
        FROM   vaccine_lots
        WHERE  expiration_date >= v_today
          AND  expiration_date <= v_today + INTERVAL '7 days'
          AND  quantity_available > 0
    ),
 
    -- Insumos con stock bajo
    low_stock AS (
        SELECT COUNT(*)::INT AS low_stock_count
        FROM   clinic_inventory
        WHERE  quantity < min_stock
    ),
 
    -- Alertas de esquema pendientes
    alerts AS (
        SELECT COUNT(*)::INT AS pending_alerts
        FROM   scheme_completion_alerts
        WHERE  status = 'Pendiente'
    )
 
    SELECT
        t.total_patients,
        c.coverage_pct,
        COALESCE(c.coverage_trend_raw, 0)::INT  AS coverage_trend,
        d.delayed_patients,
        ds.applications_today,
        ds.doses_this_week,
        ds.doses_this_month,
        mt.monthly_trend,
        ex.expired_doses,
        np.new_patients_month,
        el.expiring_lots_week,
        ls.low_stock_count,
        al.pending_alerts,
        cr.patients_critical
    FROM total         t
    CROSS JOIN coverage      c
    CROSS JOIN delayed       d
    CROSS JOIN critical      cr
    CROSS JOIN doses         ds
    CROSS JOIN monthly_trend mt
    CROSS JOIN expired       ex
    CROSS JOIN new_patients  np
    CROSS JOIN expiring_lots el
    CROSS JOIN low_stock     ls
    CROSS JOIN alerts        al;
END;
$$;


ALTER PROCEDURE public.sp_dashboard_kpis(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_dashboard_tutor(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_dashboard_tutor(IN p_guardian_id integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM guardians WHERE guardian_id = p_guardian_id) THEN
        RAISE EXCEPTION 'Tutor no encontrado';
    END IF;

    OPEN p_results FOR
    WITH
    pacientes_tutor AS (
        SELECT DISTINCT pgr.patient_id
        FROM   patient_guardian_relations pgr
        WHERE  pgr.guardian_id = p_guardian_id
    ),
    -- KPIs totales por paciente (incluyendo dosis ya Aplicadas)
    kpi_por_paciente AS (
        SELECT
            pvs2.patient_id,
            SUM(CASE WHEN pvs2.status = 'Aplicada'  THEN 1 ELSE 0 END) AS total_applied,
            COUNT(*)                                                     AS total_doses,
            SUM(CASE WHEN pvs2.status <> 'Aplicada' THEN 1 ELSE 0 END) AS total_pending,
            SUM(CASE WHEN pvs2.status = 'Atrasada'  THEN 1 ELSE 0 END) AS delayed_count,
            CASE
                WHEN COUNT(*) = 0 THEN 0
                ELSE SUM(CASE WHEN pvs2.status = 'Aplicada' THEN 1 ELSE 0 END) * 100 / COUNT(*)
            END                                                          AS pct
        FROM patient_vaccine_schedule pvs2
        GROUP BY pvs2.patient_id
    )
    SELECT
        pvs.schedule_id,
        pvs.patient_id,
        pvs.due_date,
        pvs.status                                               AS dose_status,
        sd.dose_label,
        sd.ideal_age_months,
        v.name                                                   AS vaccine_name,
        v.disease_prevented,
        -- full_name: alias que lee Flask (antes: patient_name)
        TRIM(p.first_name || ' ' || p.last_name)                AS full_name,
        p.birth_date,
        p.photo,
        DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT  AS age_years,
        -- dias_retraso: alias que lee Flask (antes: days_overdue)
        CASE
            WHEN pvs.due_date < CURRENT_DATE
            THEN (CURRENT_DATE - pvs.due_date)
            ELSE NULL
        END                                                      AS dias_retraso,
        -- Cita activa vinculada a esta dosis
        ca.appointment_id,
        -- scheduled_at: alias que lee Flask (antes: cita_fecha)
        ca.scheduled_at,
        -- appointment_status: alias que lee Flask (antes: cita_status)
        ca.appointment_status,
        -- Estado de accion para el frontend
        CASE
            WHEN pvs.status = 'Atrasada' AND ca.appointment_id IS NULL
                THEN 'ATRASADA_SIN_CITA'
            WHEN pvs.status = 'Atrasada' AND ca.appointment_id IS NOT NULL
                THEN 'ATRASADA_CON_CITA'
            WHEN pvs.due_date <= CURRENT_DATE + 30 AND ca.appointment_id IS NULL
                THEN 'PROXIMA_SIN_CITA'
            WHEN pvs.due_date <= CURRENT_DATE + 30 AND ca.appointment_id IS NOT NULL
                THEN 'PROXIMA_CON_CITA'
            ELSE 'FUTURA'
        END                                                      AS action_state,
        -- KPIs del paciente (Flask los leia pero el SP no los devolv¡a, siempre 0)
        kpi.total_applied,
        kpi.total_doses,
        kpi.total_pending,
        kpi.delayed_count,
        kpi.pct
    FROM   patient_vaccine_schedule pvs
    JOIN   pacientes_tutor          pt  ON pt.patient_id   = pvs.patient_id
    JOIN   patients                 p   ON p.patient_id    = pvs.patient_id
    JOIN   scheme_doses             sd  ON sd.dose_id      = pvs.scheme_dose_id
    JOIN   vaccines                 v   ON v.vaccine_id    = sd.vaccine_id
    LEFT JOIN kpi_por_paciente      kpi ON kpi.patient_id  = pvs.patient_id
    LEFT JOIN LATERAL (
        SELECT appointment_id, scheduled_at, appointment_status
        FROM   appointments
        WHERE  patient_schedule_id = pvs.schedule_id
          AND  appointment_status NOT IN ('Cancelada', 'No Show', 'Completada', 'Reagendada', 'Pendiente confirmacion')
        ORDER  BY scheduled_at DESC
        LIMIT  1
    ) ca ON TRUE
    WHERE  pvs.status <> 'Aplicada'
      AND  p.is_active = TRUE
    ORDER BY
        CASE pvs.status WHEN 'Atrasada' THEN 0 ELSE 1 END,
        pvs.due_date ASC;
END;
$$;


ALTER PROCEDURE public.sp_dashboard_tutor(IN p_guardian_id integer, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_deactivate_vaccine_lot(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_deactivate_vaccine_lot(IN p_lot_id integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_rows INT;
BEGIN
    UPDATE vaccine_lots
    SET    is_active = FALSE
    WHERE  lot_id          = p_lot_id
      AND  expiration_date <= NOW()::DATE;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    OPEN p_results FOR
        SELECT (v_rows > 0) AS success;
END;
$$;


ALTER PROCEDURE public.sp_deactivate_vaccine_lot(IN p_lot_id integer, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_delete_patient(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_delete_patient(IN p_patient_id integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_exists                BOOLEAN;
    v_has_future_appointments BOOLEAN;
BEGIN

    SELECT EXISTS(
        SELECT 1
        FROM patients
        WHERE patient_id = p_patient_id
        AND is_active = TRUE
    )
    INTO v_exists;

    IF NOT v_exists THEN
        RAISE EXCEPTION 'El paciente no existe o ya fue eliminado';
    END IF;

    SELECT EXISTS(
        SELECT 1
        FROM appointments
        WHERE patient_id = p_patient_id
        AND scheduled_at >= CURRENT_DATE
        AND appointment_status NOT IN ('Cancelada', 'Completada')
    )
    INTO v_has_future_appointments;

    IF v_has_future_appointments THEN
        RAISE EXCEPTION 'El paciente tiene citas futuras pendientes';
    END IF;


    UPDATE patients
    SET
        is_active = FALSE,
        deleted_at = NOW(),
        updated_at = NOW()
    WHERE patient_id = p_patient_id;

    OPEN p_results FOR
    SELECT
        TRUE AS success,
        'Paciente desactivado correctamente' AS message,
        p_patient_id AS patient_id;

EXCEPTION
WHEN OTHERS THEN

    OPEN p_results FOR
    SELECT
        FALSE AS success,
        SQLERRM AS message,
        NULL::INT AS patient_id;
END;
$$;


ALTER PROCEDURE public.sp_delete_patient(IN p_patient_id integer, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_delete_vaccine(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_delete_vaccine(IN p_vaccine_id integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM vaccines WHERE vaccine_id = p_vaccine_id) THEN
        RAISE EXCEPTION 'Vacuna % no encontrada', p_vaccine_id;
    END IF;

    DELETE FROM vaccines WHERE vaccine_id = p_vaccine_id;

    OPEN p_results FOR
        SELECT TRUE AS success, 'Vacuna eliminada' AS message, p_vaccine_id AS vaccine_id;
EXCEPTION
WHEN OTHERS THEN
    OPEN p_results FOR
        SELECT FALSE AS success, SQLERRM AS message, p_vaccine_id AS vaccine_id;
END;
$$;


ALTER PROCEDURE public.sp_delete_vaccine(IN p_vaccine_id integer, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_edit_vaccine_lot(integer, integer, character varying, integer, date, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_edit_vaccine_lot(IN p_lot_id integer, IN p_clinic_id integer, IN p_lot_number character varying, IN p_quantity_received integer, IN p_expiration_date date, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_rows INT;
BEGIN
    UPDATE vaccine_lots SET
        clinic_id         = p_clinic_id,
        lot_number        = p_lot_number,
        quantity_received = p_quantity_received,
        expiration_date   = p_expiration_date,
        is_active         = (p_expiration_date >= NOW()::DATE)
    WHERE lot_id = p_lot_id;

    GET DIAGNOSTICS v_rows = ROW_COUNT;

    OPEN p_results FOR
        SELECT (v_rows > 0) AS success;
END;
$$;


ALTER PROCEDURE public.sp_edit_vaccine_lot(IN p_lot_id integer, IN p_clinic_id integer, IN p_lot_number character varying, IN p_quantity_received integer, IN p_expiration_date date, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_generate_alerts(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_generate_alerts(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_inserted INT := 0;
    v_tmp      INT;
BEGIN
    -- Alertas de Atraso
    INSERT INTO scheme_completion_alerts
        (patient_id, schedule_id, alert_type, due_date, status, created_at)
    SELECT pvs.patient_id, pvs.schedule_id, 'Atraso', pvs.due_date, 'Pendiente', NOW()
    FROM   patient_vaccine_schedule pvs
    WHERE  pvs.status = 'Atrasada'
      AND  NOT EXISTS (
               SELECT 1 FROM scheme_completion_alerts sca
               WHERE  sca.schedule_id = pvs.schedule_id
                 AND  sca.alert_type  = 'Atraso'
                 AND  sca.status     <> 'Leida'
           );
    GET DIAGNOSTICS v_tmp = ROW_COUNT;
    v_inserted := v_inserted + v_tmp;

    -- Alertas de Proximidad (pr¢ximos 30 d¡as)
    INSERT INTO scheme_completion_alerts
        (patient_id, schedule_id, alert_type, due_date, status, created_at)
    SELECT pvs.patient_id, pvs.schedule_id, 'Proximidad', pvs.due_date, 'Pendiente', NOW()
    FROM   patient_vaccine_schedule pvs
    WHERE  pvs.status  = 'Pendiente'
      AND  pvs.due_date BETWEEN CURRENT_DATE AND CURRENT_DATE + 30
      AND  NOT EXISTS (
               SELECT 1 FROM scheme_completion_alerts sca
               WHERE  sca.schedule_id = pvs.schedule_id
                 AND  sca.alert_type  = 'Proximidad'
                 AND  sca.status     <> 'Leida'
           );
    GET DIAGNOSTICS v_tmp = ROW_COUNT;
    v_inserted := v_inserted + v_tmp;

    OPEN p_results FOR
        SELECT TRUE        AS success,
               v_inserted   AS alerts_generated,
               NOW()        AS executed_at;
END;
$$;


ALTER PROCEDURE public.sp_generate_alerts(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_admin_pending_confirmation(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_admin_pending_confirmation(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            a.appointment_id,
            a.scheduled_at,
            a.appointment_status,
            a.tutor_accepted,
            a.reason,
            pvs.patient_id,
            TRIM(p.first_name || ' ' || p.last_name)                AS patient_name,
            COALESCE(TRIM(w.first_name || ' ' || w.last_name), '-') AS worker_name,
            COALESCE(c.name, '-')                                   AS clinic_name,
            COALESCE(ca.name, '-')                                  AS area_name,
            COALESCE(v.name, '-')                                   AS vaccine_name,
            COALESCE(sd.dose_label, '-')                            AS dose_label,
            COALESCE(TRIM(g.first_name || ' ' || g.last_name), '-') AS guardian_name
        FROM   appointments a
        JOIN   patient_vaccine_schedule pvs ON pvs.schedule_id = a.patient_schedule_id
        JOIN   patients p                   ON p.patient_id    = pvs.patient_id
        LEFT JOIN LATERAL (
            SELECT grd.first_name, grd.last_name
            FROM   patient_guardian_relations pgr
            JOIN   guardians grd ON grd.guardian_id = pgr.guardian_id
            WHERE  pgr.patient_id = pvs.patient_id
            ORDER  BY pgr.is_primary DESC
            LIMIT  1
        ) g ON TRUE
        LEFT JOIN workers w       ON w.worker_id   = a.worker_id
        LEFT JOIN clinics c       ON c.clinic_id   = a.clinic_id
        LEFT JOIN clinic_areas ca ON ca.area_id    = a.area_id
        LEFT JOIN scheme_doses sd ON sd.dose_id    = pvs.scheme_dose_id
        LEFT JOIN vaccines v      ON v.vaccine_id  = sd.vaccine_id
        WHERE  a.tutor_accepted     IS NULL
          AND  a.appointment_status = 'Programada'
          AND  a.scheduled_at::DATE BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '90 days'
        ORDER  BY a.scheduled_at ASC;
END;
$$;


ALTER PROCEDURE public.sp_get_admin_pending_confirmation(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_admin_upcoming_citas(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_admin_upcoming_citas(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            a.appointment_id,
            a.scheduled_at,
            a.appointment_status,
            a.tutor_accepted,
            a.reason,
            pvs.patient_id,
            TRIM(p.first_name || ' ' || p.last_name)                AS patient_name,
            COALESCE(TRIM(w.first_name || ' ' || w.last_name), '-') AS worker_name,
            COALESCE(c.name, '-')                                   AS clinic_name,
            COALESCE(ca.name, '-')                                  AS area_name,
            COALESCE(v.name, '-')                                   AS vaccine_name,
            COALESCE(sd.dose_label, '-')                            AS dose_label
        FROM   appointments a
        JOIN   patient_vaccine_schedule pvs ON pvs.schedule_id = a.patient_schedule_id
        JOIN   patients p                   ON p.patient_id    = pvs.patient_id
        LEFT JOIN workers w       ON w.worker_id   = a.worker_id
        LEFT JOIN clinics c       ON c.clinic_id   = a.clinic_id
        LEFT JOIN clinic_areas ca ON ca.area_id    = a.area_id
        LEFT JOIN scheme_doses sd ON sd.dose_id    = pvs.scheme_dose_id
        LEFT JOIN vaccines v      ON v.vaccine_id  = sd.vaccine_id
        WHERE  a.scheduled_at::DATE BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '90 days'
          AND  a.appointment_status NOT IN ('Cancelada', 'No Show')
        ORDER  BY a.scheduled_at ASC;
END;
$$;


ALTER PROCEDURE public.sp_get_admin_upcoming_citas(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_agenda_form_data(integer, refcursor, refcursor, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_agenda_form_data(IN p_clinic_id integer, INOUT p_patients_cur refcursor, INOUT p_workers_cur refcursor, INOUT p_areas_cur refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Pacientes activos (ligero: solo id + nombre)
    OPEN p_patients_cur FOR
        SELECT patient_id,
               TRIM(first_name || ' ' || last_name) AS full_name
        FROM   patients
        WHERE  is_active = TRUE
        ORDER  BY last_name, first_name;

    -- Trabajadores con rol Medico o Enfermero con horario en esta clinica
    -- Solo estos roles pueden ser asignados a citas de vacunacion
    -- ORDER BY debe usar columnas del SELECT cuando hay DISTINCT
    OPEN p_workers_cur FOR
        SELECT DISTINCT
               w.worker_id,
               TRIM(w.first_name || ' ' || w.last_name) AS full_name,
               r.name                                    AS role_name
        FROM   workers w
        JOIN   roles r ON r.role_id = w.role_id
        JOIN   worker_schedules ws
               ON  ws.worker_id = w.worker_id
               AND ws.clinic_id = p_clinic_id
        WHERE  r.name IN ('Medico', 'Enfermero')
        ORDER  BY full_name;

    -- Areas de la clinica
    OPEN p_areas_cur FOR
        SELECT area_id,
               name,
               capacity
        FROM   clinic_areas
        WHERE  clinic_id = p_clinic_id
        ORDER  BY name;
END;
$$;


ALTER PROCEDURE public.sp_get_agenda_form_data(IN p_clinic_id integer, INOUT p_patients_cur refcursor, INOUT p_workers_cur refcursor, INOUT p_areas_cur refcursor) OWNER TO postgres;

--
-- Name: sp_get_almacen_alerts(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: vaccine_user
--

CREATE PROCEDURE public.sp_get_almacen_alerts(IN p_clinic_id integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            vl.lot_id, vl.lot_number, vl.quantity_available,
            vl.expiration_date,
            (vl.expiration_date - CURRENT_DATE) AS days_to_expiry,
            v.name AS vaccine_name,
            c.name AS clinic_name,
            CASE
                WHEN vl.expiration_date <= CURRENT_DATE + 7 THEN 'Critico'
                WHEN vl.quantity_available <= 5             THEN 'Critico'
                ELSE 'Advertencia'
            END AS alert_type,
            CASE
                WHEN vl.expiration_date < CURRENT_DATE
                    THEN 'Lote vencido'
                WHEN vl.expiration_date <= CURRENT_DATE + 7
                    THEN 'Vence en ' || (vl.expiration_date - CURRENT_DATE) || ' dÃ­a(s)'
                WHEN vl.quantity_available <= 5
                    THEN 'Stock crÃ­tico: ' || vl.quantity_available || ' dosis'
                ELSE 'Stock bajo: ' || vl.quantity_available || ' dosis'
            END AS alert_reason
        FROM vaccine_lots vl
        JOIN vaccines v ON v.vaccine_id = vl.vaccine_id
        JOIN clinics  c ON c.clinic_id  = vl.clinic_id
        WHERE vl.lot_status = 'Disponible'
          AND (p_clinic_id IS NULL OR vl.clinic_id = p_clinic_id)
          AND (vl.expiration_date <= CURRENT_DATE + 30 OR vl.quantity_available <= 10)
        ORDER BY
            CASE WHEN vl.expiration_date <= CURRENT_DATE + 7 OR vl.quantity_available <= 5
                 THEN 0 ELSE 1 END,
            vl.expiration_date;
END;
$$;


ALTER PROCEDURE public.sp_get_almacen_alerts(IN p_clinic_id integer, INOUT p_results refcursor) OWNER TO vaccine_user;

--
-- Name: sp_get_application_sites(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_application_sites(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$

BEGIN

    OPEN p_results FOR

        SELECT application_site_id, application_site FROM application_sites ORDER BY application_site;

END;

$$;


ALTER PROCEDURE public.sp_get_application_sites(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_appointment_detail(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_appointment_detail(IN p_appointment_id integer, INOUT p_result refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM appointments WHERE appointment_id = p_appointment_id
    ) THEN
        RAISE EXCEPTION 'Cita no encontrada (id=%)', p_appointment_id;
    END IF;

    OPEN p_result FOR
    SELECT
        af.appointment_id,
        af.patient_id,
        af.patient_name,
        af.clinic_id,
        af.clinic_name,
        af.worker_id,
        af.worker_name,
        af.area_id,
        af.area_name,
        af.patient_schedule_id,
        af.scheduled_at,
        af.duration_min,
        af.reason,
        af.appointment_status,
        af.appointment_notes,
        af.vaccine_name,
        af.dose_label
    FROM v_appointments_full af
    WHERE af.appointment_id = p_appointment_id;
END;
$$;


ALTER PROCEDURE public.sp_get_appointment_detail(IN p_appointment_id integer, INOUT p_result refcursor) OWNER TO postgres;

--
-- Name: sp_get_appointments_full(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_appointments_full(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
        SELECT *
        FROM v_appointments_full
        ORDER BY scheduled_at DESC;
END;
$$;


ALTER PROCEDURE public.sp_get_appointments_full(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_blood_types(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_blood_types(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$

BEGIN

    OPEN p_results FOR

        SELECT blood_type_id, blood_type FROM blood_types ORDER BY blood_type_id;

END;

$$;


ALTER PROCEDURE public.sp_get_blood_types(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_citas_admin(integer, date, date, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_citas_admin(IN p_clinic_id integer, IN p_date_from date, IN p_date_to date, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Validar solo si se proporciona un clinic_id especifico
    IF p_clinic_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM clinics WHERE clinic_id = p_clinic_id AND is_active = TRUE
    ) THEN
        RAISE EXCEPTION 'Clinica no encontrada o inactiva (id=%)', p_clinic_id;
    END IF;

    OPEN p_results FOR
    SELECT
        af.appointment_id,
        af.patient_id,
        af.worker_id,
        af.area_id,
        af.patient_schedule_id,
        af.scheduled_at,
        af.duration_min,
        af.reason,
        af.appointment_status,
        af.appointment_notes,
        af.cancel_reason,
        af.created_by_role,
        af.rescheduled_from_id,
        af.patient_name,
        af.worker_name,
        af.clinic_name,
        af.area_name,
        af.vaccine_name,
        af.dose_label,
        af.dose_due_date,
        af.dose_status,
        -- Tutor principal del paciente
        COALESCE(TRIM(g.first_name || ' ' || g.last_name), 'Sin tutor') AS guardian_name,
        COALESCE(
            (SELECT gp.phone
             FROM   guardian_phones gp
             WHERE  gp.guardian_id = g.guardian_id
             ORDER  BY gp.is_primary DESC LIMIT 1),
            '-'
        ) AS guardian_phone
    FROM   v_appointments_full af
    LEFT JOIN LATERAL (
        SELECT grd.guardian_id, grd.first_name, grd.last_name
        FROM   patient_guardian_relations pgr
        JOIN   guardians grd ON grd.guardian_id = pgr.guardian_id
        WHERE  pgr.patient_id = af.patient_id
        ORDER  BY pgr.is_primary DESC LIMIT 1
    ) g ON TRUE
    WHERE  (p_clinic_id IS NULL OR af.clinic_id = p_clinic_id)
      AND  af.scheduled_at::DATE BETWEEN COALESCE(p_date_from, CURRENT_DATE)
                                     AND COALESCE(p_date_to,   CURRENT_DATE + 30)
    ORDER  BY af.scheduled_at ASC;
END;
$$;


ALTER PROCEDURE public.sp_get_citas_admin(IN p_clinic_id integer, IN p_date_from date, IN p_date_to date, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_citas_medico(integer, date, date, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_citas_medico(IN p_worker_id integer, IN p_date_from date, IN p_date_to date, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
    SELECT
        af.appointment_id,
        af.patient_id,
        af.worker_id,
        af.clinic_id,
        af.area_id,
        af.patient_schedule_id,
        af.scheduled_at,
        af.duration_min,
        af.reason,
        af.appointment_status,
        af.appointment_notes,
        af.cancel_reason,
        af.created_by_role,
        af.rescheduled_from_id,
        af.patient_name,
        af.worker_name,
        af.clinic_name,
        af.area_name,
        af.vaccine_name,
        af.dose_label,
        af.dose_due_date,
        af.dose_status,
        COALESCE(TRIM(g.first_name || ' ' || g.last_name), 'Sin tutor') AS guardian_name,
        COALESCE(
            (SELECT gp.phone
             FROM   guardian_phones gp
             WHERE  gp.guardian_id = g.guardian_id
             ORDER  BY gp.is_primary DESC LIMIT 1),
            '-'
        ) AS guardian_phone
    FROM   v_appointments_full af
    LEFT JOIN LATERAL (
        SELECT grd.guardian_id, grd.first_name, grd.last_name
        FROM   patient_guardian_relations pgr
        JOIN   guardians grd ON grd.guardian_id = pgr.guardian_id
        WHERE  pgr.patient_id = af.patient_id
        ORDER  BY pgr.is_primary DESC LIMIT 1
    ) g ON TRUE
    WHERE  af.worker_id = p_worker_id
      AND  af.scheduled_at::DATE BETWEEN
               COALESCE(p_date_from, '2015-01-01'::DATE)
           AND COALESCE(p_date_to,   CURRENT_DATE + INTERVAL '365 days')
    ORDER  BY af.scheduled_at DESC;
END;
$$;


ALTER PROCEDURE public.sp_get_citas_medico(IN p_worker_id integer, IN p_date_from date, IN p_date_to date, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_clinics(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_clinics(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
        SELECT clinic_id, name FROM clinics WHERE is_active = TRUE ORDER BY name;
END;
$$;


ALTER PROCEDURE public.sp_get_clinics(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_clinics_full(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_clinics_full(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            c.clinic_id,
            c.name,
            c.phone,
            c.institution_type,
            c.is_active,
            COALESCE(
                mu.name || ', ' || st.name,
                '—'
            ) AS location
        FROM clinics c
        LEFT JOIN addresses  ad ON ad.address_id    = c.address_id
        LEFT JOIN municipalities mu ON mu.municipality_id = ad.municipality_id
        LEFT JOIN states     st ON st.state_id      = mu.state_id
        WHERE c.is_active = TRUE
        ORDER BY c.name;
END;
$$;


ALTER PROCEDURE public.sp_get_clinics_full(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_countries(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_countries(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$

BEGIN

    OPEN p_results FOR

        SELECT country_id, name, iso_code FROM countries ORDER BY name;

END;

$$;


ALTER PROCEDURE public.sp_get_countries(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_esquema_paciente(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_esquema_paciente(IN p_patient_id integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_exists BOOLEAN;
BEGIN
    SELECT EXISTS(SELECT 1 FROM patients WHERE patient_id = p_patient_id AND is_active = TRUE)
    INTO v_exists;
    IF NOT v_exists THEN
        RAISE EXCEPTION 'Paciente % no encontrado o inactivo', p_patient_id;
    END IF;

    OPEN p_results FOR
        SELECT
            base.patient_id, base.dose_id, base.vaccine_id, base.record_id,
            base.full_name, base.birth_date, base.age_years,
            pat.photo,
            base.vaccine_name AS name,
            base.disease_prevented,
            base.dose_label   AS dose,
            base.dose_number,
            base.ideal_age_months,
            base.ideal_date,
            base.applied_date AS date,
            base.doctor,
            base.application_site,
            base.had_reaction,
            base.patient_temp_c,
            base.estado,
            base.dias_retraso,
            CASE
                WHEN base.next_dose_age_months IS NOT NULL
                    THEN 'A los ' || base.next_dose_age_months || ' meses'
                ELSE NULL
            END AS next_date,
            CASE
                WHEN base.ideal_age_months = 0  THEN 'Al nacer'
                WHEN base.ideal_age_months >= 12 THEN (base.ideal_age_months / 12) || ' a¤o(s)'
                ELSE base.ideal_age_months || ' meses'
            END AS edad_ideal_label,
            CASE
                WHEN base.record_id IS NULL AND base.dias_retraso > 0
                    THEN 'Retraso de ' || base.dias_retraso || ' d¡as'
                WHEN base.record_id IS NULL AND base.dias_retraso <= 0
                    THEN 'Programada en ' || ABS(base.dias_retraso) || ' d¡as'
                ELSE NULL
            END AS alerta_retraso,
            -- Cita m s reciente no cancelada para esta dosis
            appt.scheduled_at::DATE AS fecha_cita,
            appt.appointment_status AS cita_estado,
            appt.tutor_accepted     AS cita_aceptada_tutor
        FROM v_patient_vaccination_scheme_base base
        JOIN patients pat ON pat.patient_id = base.patient_id
        LEFT JOIN LATERAL (
            SELECT scheduled_at, appointment_status, tutor_accepted
            FROM appointments
            WHERE patient_id   = base.patient_id
              AND scheme_dose_id = base.dose_id
            ORDER BY scheduled_at DESC
            LIMIT 1
        ) appt ON TRUE
        WHERE base.patient_id = p_patient_id
        ORDER BY base.ideal_age_months, base.dose_number;
END;
$$;


ALTER PROCEDURE public.sp_get_esquema_paciente(IN p_patient_id integer, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_esquema_vacunacion(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_esquema_vacunacion(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            v.vaccine_id,
            v.name            AS vaccine_name,
            v.commercial_name,
            v.disease_prevented,
            sd.dose_id,
            sd.dose_label,
            sd.dose_number,
            sd.ideal_age_months
        FROM vaccines v
        JOIN scheme_doses sd ON sd.vaccine_id = v.vaccine_id
        ORDER BY v.name, sd.ideal_age_months, sd.dose_number;
END;
$$;


ALTER PROCEDURE public.sp_get_esquema_vacunacion(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_inventory_status(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_inventory_status(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
        SELECT * FROM v_inventory_status
        ORDER BY clinic_name, supply_category, supply_name;
END;
$$;


ALTER PROCEDURE public.sp_get_inventory_status(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_last_applications(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_last_applications(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
    SELECT
        vr.record_id,
        vr.applied_date,
        TRIM(p.first_name || ' ' || p.last_name)  AS patient_name,
        p.patient_id,
        v.name                                     AS vaccine_name,
        COALESCE(sd.dose_label, 'Dosis £nica')    AS dose_label,
        TRIM(w.first_name || ' ' || w.last_name)  AS worker_name,
        c.name                                     AS clinic_name
        FROM   vaccination_records vr
        JOIN   patients   p  ON p.patient_id  = vr.patient_id
        JOIN   vaccines   v  ON v.vaccine_id  = vr.vaccine_id
        LEFT   JOIN scheme_doses sd ON sd.dose_id   = vr.scheme_dose_id
        LEFT   JOIN workers   w  ON w.worker_id  = vr.worker_id
        LEFT   JOIN clinics   c  ON c.clinic_id  = vr.clinic_id
        ORDER  BY vr.applied_date DESC, vr.record_id DESC
        LIMIT  10;
END;
$$;


ALTER PROCEDURE public.sp_get_last_applications(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_lot_detail(integer, refcursor, refcursor); Type: PROCEDURE; Schema: public; Owner: vaccine_user
--

CREATE PROCEDURE public.sp_get_lot_detail(IN p_lot_id integer, INOUT p_lot refcursor, INOUT p_movs refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_lot FOR
        SELECT
            vl.*,
            v.name AS vaccine_name, v.commercial_name,
            c.name AS clinic_name,
            m.name AS manufacturer,
            (vl.quantity_received - vl.quantity_available) AS dosis_aplicadas
        FROM vaccine_lots vl
        JOIN vaccines  v ON v.vaccine_id    = vl.vaccine_id
        JOIN clinics   c ON c.clinic_id     = vl.clinic_id
        LEFT JOIN manufacturers m ON m.manufacturer_id = v.manufacturer_id
        WHERE vl.lot_id = p_lot_id;

    OPEN p_movs FOR
        SELECT
            im.movement_id, im.created_at, im.movement_type,
            im.quantity, im.quantity_before, im.quantity_after,
            im.reason, im.reference_type, im.reference_id,
            (w.first_name || ' ' || w.last_name) AS worker_name
        FROM inventory_movements im
        LEFT JOIN workers w ON w.worker_id = im.worker_id
        WHERE im.lot_id = p_lot_id
        ORDER BY im.created_at DESC;
END;
$$;


ALTER PROCEDURE public.sp_get_lot_detail(IN p_lot_id integer, INOUT p_lot refcursor, INOUT p_movs refcursor) OWNER TO vaccine_user;

--
-- Name: sp_get_manufacturers(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_manufacturers(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$

BEGIN

    OPEN p_results FOR

        SELECT manufacturer_id, name FROM manufacturers ORDER BY name;

END;

$$;


ALTER PROCEDURE public.sp_get_manufacturers(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_movements_full(integer, integer, date, date, character varying, refcursor); Type: PROCEDURE; Schema: public; Owner: vaccine_user
--

CREATE PROCEDURE public.sp_get_movements_full(IN p_clinic_id integer, IN p_lot_id integer, IN p_date_from date, IN p_date_to date, IN p_type_filter character varying, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            im.movement_id, im.created_at, im.movement_type,
            im.quantity, im.quantity_before, im.quantity_after,
            im.reason, im.reference_type, im.reference_id,
            vl.lot_number,
            v.name AS vaccine_name,
            c.name AS clinic_name,
            (w.first_name || ' ' || w.last_name) AS worker_name
        FROM inventory_movements im
        JOIN vaccine_lots vl ON vl.lot_id    = im.lot_id
        JOIN vaccines     v  ON v.vaccine_id = im.vaccine_id
        JOIN clinics      c  ON c.clinic_id  = im.clinic_id
        LEFT JOIN workers w  ON w.worker_id  = im.worker_id
        WHERE
            (p_clinic_id   IS NULL OR im.clinic_id     = p_clinic_id)
            AND (p_lot_id  IS NULL OR im.lot_id        = p_lot_id)
            AND (p_date_from IS NULL OR im.created_at::DATE >= p_date_from)
            AND (p_date_to   IS NULL OR im.created_at::DATE <= p_date_to)
            AND (p_type_filter IS NULL OR im.movement_type = p_type_filter)
        ORDER BY im.created_at DESC;
END;
$$;


ALTER PROCEDURE public.sp_get_movements_full(IN p_clinic_id integer, IN p_lot_id integer, IN p_date_from date, IN p_date_to date, IN p_type_filter character varying, INOUT p_results refcursor) OWNER TO vaccine_user;

--
-- Name: sp_get_municipalities(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_municipalities(IN p_state_id integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$

BEGIN

    OPEN p_results FOR

        SELECT municipality_id, name FROM municipalities WHERE state_id = p_state_id ORDER BY name;

END;

$$;


ALTER PROCEDURE public.sp_get_municipalities(IN p_state_id integer, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_nfc_card_history(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_nfc_card_history(IN p_nfc_card_id integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM nfc_cards WHERE nfc_card_id = p_nfc_card_id) THEN
        RAISE EXCEPTION 'Tarjeta NFC % no encontrada', p_nfc_card_id;
    END IF;

    OPEN p_results FOR
        SELECT
            se.scan_event_id,
            se.scanned_at,
            se.action_triggered,
            se.nfc_scan_result,
            c.name                                                    AS clinic_name,
            COALESCE(ca.name, '-')                                    AS area_name,
            COALESCE(TRIM(w.first_name || ' ' || w.last_name), '-')  AS worker_name
        FROM nfc_scan_events se
        JOIN  clinics    c  ON c.clinic_id   = se.clinic_id
        LEFT JOIN workers      w  ON w.worker_id = se.scanned_by
        LEFT JOIN clinic_areas ca ON ca.area_id  = se.area_id
        WHERE se.nfc_card_id = p_nfc_card_id
        ORDER BY se.scanned_at DESC;
END;
$$;


ALTER PROCEDURE public.sp_get_nfc_card_history(IN p_nfc_card_id integer, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_nfc_cards_full(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_nfc_cards_full(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            nc.nfc_card_id,
            nc.uid,
            nc.card_type,
            nc.issued_date,
            nc.status,
            nc.last_scanned_at,
            nc.nfc_card_notes,
            nc.patient_id,

            TRIM(p.first_name || ' ' || p.last_name)          AS patient_name,
            p.birth_date                                       AS patient_birth_date,
            DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT
                                                               AS patient_age,

            COALESCE(TRIM(wi.first_name || ' ' || wi.last_name), '-')
                                                               AS issued_by_name,

            -- Estado clínico actual (visita activa del paciente)
            pcv.visit_status                                   AS current_visit_status,

            (SELECT COUNT(*) FROM nfc_scan_events se
             WHERE se.nfc_card_id = nc.nfc_card_id)            AS total_scans,

            (SELECT COUNT(*) FROM nfc_scan_events se
             WHERE se.nfc_card_id = nc.nfc_card_id
               AND se.scanned_at >= CURRENT_DATE - INTERVAL '30 days')
                                                               AS scans_last_30d,

            CASE
                WHEN nc.last_scanned_at IS NOT NULL
                THEN (CURRENT_DATE - nc.last_scanned_at::DATE)
                ELSE NULL
            END                                                AS days_since_scan,

            CASE
                WHEN nc.status = 'Activa'
                     AND (nc.last_scanned_at IS NULL
                          OR nc.last_scanned_at < CURRENT_DATE - INTERVAL '90 days')
                THEN TRUE
                ELSE FALSE
            END                                                AS alert_inactive

        FROM nfc_cards nc
        JOIN  patients p  ON p.patient_id  = nc.patient_id
        LEFT JOIN workers wi ON wi.worker_id = nc.issued_by
        LEFT JOIN LATERAL (
            SELECT visit_status
            FROM   patient_clinic_visits
            WHERE  patient_id  = p.patient_id
              AND  visit_status NOT IN ('Finalizado','Abandono','Cancelado')
            ORDER BY checked_in_at DESC
            LIMIT 1
        ) pcv ON TRUE
        ORDER BY
            CASE nc.status
                WHEN 'Activa'   THEN 1
                WHEN 'Inactiva' THEN 2
                WHEN 'Perdida'  THEN 3
                WHEN 'Robada'   THEN 4
            END,
            nc.issued_date DESC;
END;
$$;


ALTER PROCEDURE public.sp_get_nfc_cards_full(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_nfc_scans_full(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_nfc_scans_full(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            se.scan_event_id,
            se.nfc_card_id,
            se.scanned_at,
            se.action_triggered,
            se.nfc_scan_result                                 AS result,
            se.nfc_scan_result,

            -- Tarjeta
            nc.uid                                             AS card_uid,
            nc.status                                          AS card_status,

            -- Paciente (a traves de la tarjeta)
            nc.patient_id,
            TRIM(p.first_name || ' ' || p.last_name)          AS patient_name,
            DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT
                                                               AS patient_age,

            -- Trabajador que escaneo
            COALESCE(TRIM(w.first_name || ' ' || w.last_name), '-')
                                                               AS worker_name,
            COALESCE(TRIM(w.first_name || ' ' || w.last_name), '-')
                                                               AS scanned_by_name,

            -- Ubicacion
            c.name                                             AS clinic_name,
            COALESCE(ca.name, '-')                             AS area_name,

            -- Dispositivo
            COALESCE(nd.device_name, '-')                     AS device_name,
            nd.model                                           AS device_model,

            -- Clasificacion del resultado
            CASE
                WHEN se.nfc_scan_result ILIKE '%exito%'
                  OR se.nfc_scan_result ILIKE '%exitoso%'
                  OR se.nfc_scan_result ILIKE '%ok%'
                  OR se.nfc_scan_result ILIKE '%acceso%'
                THEN 'Exitoso'
                WHEN se.nfc_scan_result ILIKE '%error%'
                  OR se.nfc_scan_result ILIKE '%fallo%'
                  OR se.nfc_scan_result ILIKE '%rechaz%'
                  OR se.nfc_scan_result ILIKE '%denegado%'
                THEN 'Error'
                ELSE COALESCE(se.nfc_scan_result, '-')
            END                                                AS resultado_display

        FROM nfc_scan_events se
        JOIN  nfc_cards  nc ON nc.nfc_card_id = se.nfc_card_id
        JOIN  patients   p  ON p.patient_id   = nc.patient_id
        JOIN  clinics    c  ON c.clinic_id    = se.clinic_id
        LEFT JOIN workers      w  ON w.worker_id  = se.scanned_by
        LEFT JOIN clinic_areas ca ON ca.area_id   = se.area_id
        LEFT JOIN nfc_devices  nd ON nd.device_id = se.device_id
        ORDER BY se.scanned_at DESC;
END;
$$;


ALTER PROCEDURE public.sp_get_nfc_scans_full(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_patient_scheme(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_patient_scheme(IN p_patient_id integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_patient_active BOOLEAN;
BEGIN

    -- ============================================================
    -- VALIDAR PACIENTE
    -- ============================================================

    SELECT is_active
    INTO v_patient_active
    FROM patients
    WHERE patient_id = p_patient_id;

    -- No existe
    IF v_patient_active IS NULL THEN
        RAISE EXCEPTION
            'El paciente con ID % no existe.',
            p_patient_id;
    END IF;

    -- Existe pero est  inactivo
    IF v_patient_active = FALSE THEN
        RAISE EXCEPTION
            'El paciente con ID % est  inactivo.',
            p_patient_id;
    END IF;


    -- ============================================================
    -- RETORNAR ESQUEMA COMPLETO
    -- ============================================================

    OPEN p_results FOR

    -- [CORREGIDO] Filtrar citas en estado final para no mostrar citas canceladas
    --             como "cita activa" de una dosis pendiente
    WITH latest_appointments AS (
        SELECT
            a.*,

            ROW_NUMBER() OVER (
                PARTITION BY a.patient_schedule_id
                ORDER BY a.created_at DESC
            ) AS rn

        FROM appointments a
        WHERE a.appointment_status NOT IN ('Cancelada', 'No Show', 'Completada', 'Reagendada', 'Pendiente confirmacion')
    )

    SELECT

        -- ========================================================
        -- IDENTIFICADORES
        -- ========================================================

        v.schedule_id,
        v.patient_id,
        v.dose_id,
        v.vaccine_id,
        v.record_id,

        la.appointment_id,


        -- ========================================================
        -- PACIENTE
        -- ========================================================

        v.full_name,
        v.birth_date,
        v.age_years,


        -- ========================================================
        -- VACUNA / DOSIS
        -- [CORREGIDO] aliases que lee Flask: name, dose (antes: vaccine_name, dose_label)
        -- ========================================================

        v.vaccine_name                                   AS name,
        v.disease_prevented,
        v.dose_label                                     AS dose,
        v.dose_number,
        v.ideal_age_months,
        v.ideal_date,


        -- ========================================================
        -- APLICACION
        -- [CORREGIDO] alias que lee Flask: date (antes: applied_date)
        -- ========================================================

        v.applied_date                                   AS date,
        v.doctor,
        v.application_site,
        v.had_reaction,
        v.patient_temp_c,


        -- ========================================================
        -- ESTADO CLINICO
        -- [CORREGIDO] columna "estado" con valores que espera Flask/template:
        --   Atrasada  -> 'Pendiente con retraso'
        --   Aplicada  -> 'Aplicada'
        --   Pendiente -> 'Pendiente'
        -- ========================================================

        CASE
            WHEN v.vaccination_status = 'Aplicada' THEN 'Aplicada'
            WHEN v.vaccination_status = 'Atrasada' THEN 'Pendiente con retraso'
            ELSE 'Pendiente'
        END                                              AS estado,
        v.dias_retraso,


        -- ========================================================
        -- CITA
        -- [CORREGIDO] aliases que lee Flask: fecha_cita, cita_estado
        --   (antes: appointment_date, appointment_status)
        -- ========================================================

        la.scheduled_at::DATE                            AS fecha_cita,
        la.appointment_status                            AS cita_estado,
        c.name AS clinic_name,


        -- ========================================================
        -- PRàXIMA DOSIS
        -- ========================================================

        CASE
            WHEN v.next_dose_age_months IS NOT NULL THEN
                'A los '
                || v.next_dose_age_months
                || ' meses'
            ELSE NULL
        END AS next_dose_label,


        -- ========================================================
        -- EDAD IDEAL LEGIBLE
        -- ========================================================

        CASE
            WHEN v.ideal_age_months = 0 THEN
                'Al nacer'

            WHEN v.ideal_age_months >= 12 THEN
                (v.ideal_age_months / 12)
                || ' a¤o(s)'

            ELSE
                v.ideal_age_months
                || ' meses'
        END AS edad_ideal_label,


        -- ========================================================
        -- ALERTA DE RETRASO
        -- ========================================================

        CASE

            WHEN v.record_id IS NULL
                 AND v.dias_retraso > 0 THEN

                'Retraso de '
                || v.dias_retraso
                || ' d¡as'

            WHEN v.record_id IS NULL
                 AND v.dias_retraso <= 0 THEN

                'Programada en '
                || ABS(v.dias_retraso)
                || ' d¡as'

            ELSE NULL

        END AS alerta_retraso

    FROM v_patient_vaccination_scheme_base v

    LEFT JOIN latest_appointments la
        ON v.schedule_id = la.patient_schedule_id
       AND la.rn = 1

    LEFT JOIN clinics c
        ON la.clinic_id = c.clinic_id

    WHERE v.patient_id = p_patient_id

    ORDER BY
        v.ideal_age_months,
        v.dose_number;

END;
$$;


ALTER PROCEDURE public.sp_get_patient_scheme(IN p_patient_id integer, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_patients_full(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_patients_full(IN p_limit integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_query TEXT;
BEGIN
    IF p_limit IS NOT NULL AND p_limit > 0 THEN
        OPEN p_results FOR
            SELECT
                p.patient_id,
                p.first_name,
                p.last_name,
                TRIM(p.first_name || ' ' || p.last_name)                AS full_name,
                p.curp,
                p.birth_date,
                p.gender,
                p.weight_kg,
                p.premature,
                p.created_at,
                p.photo,
                p.blood_type_id,
                COALESCE(bt.blood_type, '-')                            AS blood_type,
                DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT AS age,
                COALESCE(TRIM(g.first_name || ' ' || g.last_name), 'Sin tutor') AS guardian,
                COALESCE(
                    (SELECT gp.phone FROM guardian_phones gp
                     WHERE gp.guardian_id = g.guardian_id
                     ORDER BY gp.is_primary DESC LIMIT 1),
                    '-'
                )                                                        AS contact,
                'N/A'::TEXT                                              AS risk,
                COALESCE(
                    NULLIF((
                        SELECT STRING_AGG(al.name, ', ' ORDER BY al.name)
                        FROM patient_allergies pa
                        JOIN allergies al ON al.allergy_id = pa.allergy_id
                        WHERE pa.patient_id = p.patient_id
                    ), ''),
                    'Ninguna'
                )                                                        AS allergies
            FROM patients p
            LEFT JOIN blood_types bt ON bt.blood_type_id = p.blood_type_id
            LEFT JOIN LATERAL (
                SELECT pgr.guardian_id
                FROM   patient_guardian_relations pgr
                WHERE  pgr.patient_id = p.patient_id
                ORDER  BY pgr.is_primary DESC LIMIT 1
            ) rel ON TRUE
            LEFT JOIN guardians g ON g.guardian_id = rel.guardian_id
            WHERE p.is_active != FALSE
            ORDER BY p.created_at DESC
            LIMIT p_limit;
    ELSE
        OPEN p_results FOR
            SELECT
                p.patient_id,
                p.first_name,
                p.last_name,
                TRIM(p.first_name || ' ' || p.last_name)                AS full_name,
                p.curp,
                p.birth_date,
                p.gender,
                p.weight_kg,
                p.premature,
                p.created_at,
                p.photo,
                p.blood_type_id,
                COALESCE(bt.blood_type, '-')                            AS blood_type,
                DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT AS age,
                COALESCE(TRIM(g.first_name || ' ' || g.last_name), 'Sin tutor') AS guardian,
                COALESCE(
                    (SELECT gp.phone FROM guardian_phones gp
                     WHERE gp.guardian_id = g.guardian_id
                     ORDER BY gp.is_primary DESC LIMIT 1),
                    '-'
                )                                                        AS contact,
                'N/A'::TEXT                                              AS risk,
                COALESCE(
                    NULLIF((
                        SELECT STRING_AGG(al.name, ', ' ORDER BY al.name)
                        FROM patient_allergies pa
                        JOIN allergies al ON al.allergy_id = pa.allergy_id
                        WHERE pa.patient_id = p.patient_id
                    ), ''),
                    'Ninguna'
                )                                                        AS allergies
            FROM patients p
            LEFT JOIN blood_types bt ON bt.blood_type_id = p.blood_type_id
            LEFT JOIN LATERAL (
                SELECT pgr.guardian_id
                FROM   patient_guardian_relations pgr
                WHERE  pgr.patient_id = p.patient_id
                ORDER  BY pgr.is_primary DESC LIMIT 1
            ) rel ON TRUE
            LEFT JOIN guardians g ON g.guardian_id = rel.guardian_id
            WHERE p.is_active != FALSE
            ORDER BY p.last_name, p.first_name;
    END IF;
END;
$$;


ALTER PROCEDURE public.sp_get_patients_full(IN p_limit integer, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_pending_alerts(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_pending_alerts(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$

BEGIN

    OPEN p_results FOR

        SELECT * FROM scheme_completion_alerts

        WHERE status = 'Pendiente'

        ORDER BY due_date ASC;

END;

$$;


ALTER PROCEDURE public.sp_get_pending_alerts(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_pending_doses(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_pending_doses(IN p_patient_id integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM patients WHERE patient_id = p_patient_id AND is_active = TRUE) THEN
        RAISE EXCEPTION 'Paciente no existe o est  inactivo';
    END IF;

    OPEN p_results FOR
        SELECT
            pvs.schedule_id,
            pvs.patient_id,
            pvs.due_date,
            pvs.status                  AS dose_status,
            sd.dose_id,
            sd.dose_label,
            sd.dose_number,
            sd.ideal_age_months,
            v.vaccine_id,
            v.name                      AS vaccine_name,
            v.disease_prevented,
            -- Cita activa vinculada (puede ser NULL)
            ca.appointment_id,
            ca.scheduled_at             AS appointment_date,
            ca.appointment_status,
            -- D¡as de retraso (0 si no est  atrasada)
            CASE
                WHEN pvs.due_date < CURRENT_DATE
                THEN (CURRENT_DATE - pvs.due_date)
                ELSE 0
            END                         AS days_overdue,
            -- Urgencia legible
            CASE
                WHEN pvs.due_date < CURRENT_DATE          THEN 'Atrasada'
                WHEN pvs.due_date <= CURRENT_DATE + 30    THEN 'Pr¢xima'
                ELSE                                           'Futura'
            END                         AS urgency
        FROM   patient_vaccine_schedule pvs
        JOIN   scheme_doses sd ON sd.dose_id   = pvs.scheme_dose_id
        JOIN   vaccines     v  ON v.vaccine_id = sd.vaccine_id
        LEFT JOIN LATERAL (
            SELECT appointment_id, scheduled_at, appointment_status
            FROM   appointments
            WHERE  patient_schedule_id = pvs.schedule_id
              AND  appointment_status NOT IN ('Cancelada','No Show','Completada','Reagendada')
            ORDER  BY scheduled_at DESC
            LIMIT  1
        ) ca ON TRUE
        WHERE  pvs.patient_id = p_patient_id
          AND  pvs.status    <> 'Aplicada'
        ORDER  BY pvs.due_date ASC;
END;
$$;


ALTER PROCEDURE public.sp_get_pending_doses(IN p_patient_id integer, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_pending_scheme_doses(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_pending_scheme_doses(IN p_patient_id integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            v.name            AS vaccine_name,
            sd.dose_label,
            sd.ideal_age_months,
            (p.birth_date + (sd.ideal_age_months || ' months')::INTERVAL)::DATE AS ideal_date
        FROM patients p
        CROSS JOIN scheme_doses sd
        JOIN vaccines v ON v.vaccine_id = sd.vaccine_id
        WHERE p.patient_id = p_patient_id
          AND p.is_active   = TRUE
          AND NOT EXISTS (
              SELECT 1 FROM vaccination_records vr
              WHERE vr.patient_id    = p_patient_id
                AND vr.scheme_dose_id = sd.dose_id
          )
        ORDER BY sd.ideal_age_months, sd.dose_number;
END;
$$;


ALTER PROCEDURE public.sp_get_pending_scheme_doses(IN p_patient_id integer, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_roles(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_roles(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$

BEGIN

    OPEN p_results FOR

        SELECT role_id, name FROM roles ORDER BY name;

END;

$$;


ALTER PROCEDURE public.sp_get_roles(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_schema_alerts_full(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_schema_alerts_full(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            sca.alert_id,
            sca.patient_id,
            sca.scheme_dose_id,
            sca.due_date,
            sca.status,
            sca.notified_at,
            TRIM(p.first_name || ' ' || p.last_name) AS patient_name,
            v.name    AS vaccine_name,
            sd.dose_label
        FROM scheme_completion_alerts sca
        JOIN patients     p  ON p.patient_id  = sca.patient_id
        JOIN scheme_doses sd ON sd.dose_id    = sca.scheme_dose_id
        JOIN vaccines     v  ON v.vaccine_id  = sd.vaccine_id
        ORDER BY sca.due_date;
END;
$$;


ALTER PROCEDURE public.sp_get_schema_alerts_full(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_states(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_states(IN p_country_id integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$

BEGIN

    OPEN p_results FOR

        SELECT state_id, name, code FROM states WHERE country_id = p_country_id ORDER BY name;

END;

$$;


ALTER PROCEDURE public.sp_get_states(IN p_country_id integer, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_transfers(integer, character varying, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_transfers(IN p_clinic_id integer, IN p_status_filter character varying, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            t.transfer_id, t.lot_id, t.quantity, t.transfer_status,
            t.reason, t.notes, t.requested_at, t.resolved_at,
            t.from_clinic_id, t.to_clinic_id,
            vl.lot_number,
            v.name AS vaccine_name,
            cf.name  AS from_clinic_name,
            ct.name  AS to_clinic_name,
            (wr.first_name || ' ' || wr.last_name) AS requested_by_name,
            (wa.first_name || ' ' || wa.last_name) AS approved_by_name,
            vl.quantity_available
        FROM inventory_transfers t
        JOIN vaccine_lots  vl ON vl.lot_id      = t.lot_id
        JOIN vaccines       v ON v.vaccine_id   = t.vaccine_id
        JOIN clinics        cf ON cf.clinic_id  = t.from_clinic_id
        JOIN clinics        ct ON ct.clinic_id  = t.to_clinic_id
        JOIN workers        wr ON wr.worker_id  = t.requested_by
        LEFT JOIN workers   wa ON wa.worker_id  = t.approved_by
        WHERE
            (p_clinic_id     IS NULL OR t.from_clinic_id = p_clinic_id OR t.to_clinic_id = p_clinic_id)
            AND (p_status_filter IS NULL OR t.transfer_status = p_status_filter)
        ORDER BY t.requested_at DESC;
END;
$$;


ALTER PROCEDURE public.sp_get_transfers(IN p_clinic_id integer, IN p_status_filter character varying, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_tutor_children(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_tutor_children(IN p_guardian_id integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM guardians WHERE guardian_id = p_guardian_id) THEN
        RAISE EXCEPTION 'Tutor no encontrado';
    END IF;

    OPEN p_results FOR
    SELECT
        p.patient_id,
        TRIM(p.first_name || ' ' || p.last_name)                    AS full_name,
        p.first_name,
        p.last_name,
        p.birth_date,
        DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT      AS age_years,
        COALESCE(p.curp, '')                                         AS curp,
        p.photo,
        p.gender,
        p.weight_kg,
        p.premature,
        COALESCE(bt.blood_type, '')                                  AS blood_type,
        -- KPIs de vacunaci¢n
        COALESCE(kpi.total_doses,   0)                               AS total_doses,
        COALESCE(kpi.total_applied, 0)                               AS total_applied,
        COALESCE(kpi.total_pending, 0)                               AS total_pending,
        COALESCE(kpi.delayed_count, 0)                               AS delayed_count,
        COALESCE(kpi.pct,           0)                               AS pct
    FROM patient_guardian_relations pgr
    JOIN   patients    p   ON p.patient_id    = pgr.patient_id
    LEFT JOIN blood_types bt ON bt.blood_type_id = p.blood_type_id
    LEFT JOIN LATERAL (
        SELECT
            COUNT(*)                                                               AS total_doses,
            SUM(CASE WHEN pvs.status = 'Aplicada' THEN 1 ELSE 0 END)              AS total_applied,
            SUM(CASE WHEN pvs.status <> 'Aplicada' THEN 1 ELSE 0 END)             AS total_pending,
            SUM(CASE WHEN pvs.status = 'Atrasada'  THEN 1 ELSE 0 END)             AS delayed_count,
            CASE
                WHEN COUNT(*) = 0 THEN 0
                ELSE SUM(CASE WHEN pvs.status = 'Aplicada' THEN 1 ELSE 0 END) * 100 / COUNT(*)
            END                                                                    AS pct
        FROM patient_vaccine_schedule pvs
        WHERE pvs.patient_id = p.patient_id
    ) kpi ON TRUE
    WHERE pgr.guardian_id = p_guardian_id
      AND p.is_active = TRUE
    ORDER BY p.patient_id ASC;
END;
$$;


ALTER PROCEDURE public.sp_get_tutor_children(IN p_guardian_id integer, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_tutor_citas_history(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_tutor_citas_history(IN p_guardian_id integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            a.appointment_id,
            a.scheduled_at,
            a.appointment_status,
            a.tutor_accepted,
            a.reason,
            TRIM(p.first_name || ' ' || p.last_name)                AS patient_name,
            COALESCE(TRIM(w.first_name || ' ' || w.last_name), '-') AS worker_name,
            COALESCE(c.name, '-')                                   AS clinic_name,
            COALESCE(ca.name, '-')                                  AS area_name,
            COALESCE(v.name, '-')                                   AS vaccine_name,
            COALESCE(sd.dose_label, '-')                            AS dose_label
        FROM   appointments a
        JOIN   patient_vaccine_schedule pvs ON pvs.schedule_id = a.patient_schedule_id
        JOIN   patients p                   ON p.patient_id    = pvs.patient_id
        JOIN   patient_guardian_relations pgr ON pgr.patient_id = pvs.patient_id
        LEFT JOIN workers w       ON w.worker_id   = a.worker_id
        LEFT JOIN clinics c       ON c.clinic_id   = a.clinic_id
        LEFT JOIN clinic_areas ca ON ca.area_id    = a.area_id
        LEFT JOIN scheme_doses sd ON sd.dose_id    = pvs.scheme_dose_id
        LEFT JOIN vaccines v      ON v.vaccine_id  = sd.vaccine_id
        WHERE  pgr.guardian_id = p_guardian_id
          AND  (
                a.scheduled_at::DATE < CURRENT_DATE
                OR a.appointment_status IN ('Completada', 'Cancelada', 'No Show')
          )
        ORDER  BY a.scheduled_at DESC;
END;
$$;


ALTER PROCEDURE public.sp_get_tutor_citas_history(IN p_guardian_id integer, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_tutor_pending_citas(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_tutor_pending_citas(IN p_guardian_id integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            a.appointment_id,
            a.scheduled_at,
            a.appointment_status,
            a.tutor_accepted,
            a.reason,
            TRIM(p.first_name || ' ' || p.last_name)                AS patient_name,
            COALESCE(TRIM(w.first_name || ' ' || w.last_name), '-') AS worker_name,
            COALESCE(c.name, '-')                                   AS clinic_name,
            COALESCE(ca.name, '-')                                  AS area_name,
            COALESCE(v.name, '-')                                   AS vaccine_name,
            COALESCE(sd.dose_label, '-')                            AS dose_label
        FROM   appointments a
        JOIN   patient_vaccine_schedule pvs ON pvs.schedule_id = a.patient_schedule_id
        JOIN   patients p                   ON p.patient_id    = pvs.patient_id
        JOIN   patient_guardian_relations pgr ON pgr.patient_id = pvs.patient_id
        LEFT JOIN workers w       ON w.worker_id   = a.worker_id
        LEFT JOIN clinics c       ON c.clinic_id   = a.clinic_id
        LEFT JOIN clinic_areas ca ON ca.area_id    = a.area_id
        LEFT JOIN scheme_doses sd ON sd.dose_id    = pvs.scheme_dose_id
        LEFT JOIN vaccines v      ON v.vaccine_id  = sd.vaccine_id
        WHERE  pgr.guardian_id      = p_guardian_id
          AND  a.tutor_accepted     IS NULL
          AND  a.appointment_status = 'Programada'
          AND  a.scheduled_at::DATE BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '90 days'
        ORDER  BY a.scheduled_at ASC;
END;
$$;


ALTER PROCEDURE public.sp_get_tutor_pending_citas(IN p_guardian_id integer, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_vaccination_record(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_vaccination_record(IN p_record_id integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
    SELECT
        vr.record_id,
        vr.patient_id,
        vr.applied_date,
        vr.patient_temp_c,
        vr.had_reaction,
        TRIM(p.first_name || ' ' || p.last_name)                    AS patient_name,
        p.curp,
        p.birth_date,
        DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT      AS age_years,
        v.name                                                        AS vaccine_name,
        v.commercial_name,
        COALESCE(TRIM(w.first_name || ' ' || w.last_name), '-')      AS worker_name,
        COALESCE(sd.dose_label, '-')                                  AS dose_label,
        COALESCE(aps.application_site, '-')                           AS application_site,
        c.name                                                        AS clinic_name,
        COALESCE(vl.lot_number, '-')                                  AS lot_number
    FROM   vaccination_records vr
    JOIN   patients            p   ON p.patient_id           = vr.patient_id
    JOIN   vaccines            v   ON v.vaccine_id           = vr.vaccine_id
    JOIN   workers             w   ON w.worker_id            = vr.worker_id
    JOIN   clinics             c   ON c.clinic_id            = vr.clinic_id
    LEFT JOIN scheme_doses     sd  ON sd.dose_id             = vr.scheme_dose_id
    LEFT JOIN application_sites aps ON aps.application_site_id = vr.application_site_id
    LEFT JOIN vaccine_lots     vl  ON vl.lot_id              = vr.lot_id
    WHERE  vr.record_id = p_record_id
    LIMIT  1;
END;
$$;


ALTER PROCEDURE public.sp_get_vaccination_record(IN p_record_id integer, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_vaccination_records_full(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_vaccination_records_full(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
        SELECT * FROM v_vaccination_records_full
        ORDER BY applied_date DESC;
END;
$$;


ALTER PROCEDURE public.sp_get_vaccination_records_full(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_vaccine_lots_available(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_vaccine_lots_available(IN p_vaccine_id integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$

BEGIN

    OPEN p_results FOR

        SELECT lot_id, lot_number, quantity_available, expiration_date

        FROM vaccine_lots

        WHERE vaccine_id = p_vaccine_id AND quantity_available > 0 AND expiration_date > NOW()::DATE

        ORDER BY expiration_date ASC;

END;

$$;


ALTER PROCEDURE public.sp_get_vaccine_lots_available(IN p_vaccine_id integer, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_vaccine_vias(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_vaccine_vias(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$

BEGIN

    OPEN p_results FOR

        SELECT via_id, via FROM vaccine_vias ORDER BY via;

END;

$$;


ALTER PROCEDURE public.sp_get_vaccine_vias(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_vaccines_full(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_vaccines_full(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            v.vaccine_id,
            v.name,
            v.commercial_name,
            v.disease_prevented,
            v.ideal_age_months,
            COALESCE(m.name, '—')  AS manufacturer,
            COALESCE(vv.via, '—')  AS route
        FROM vaccines v
        LEFT JOIN manufacturers m  ON m.manufacturer_id = v.manufacturer_id
        LEFT JOIN vaccine_vias  vv ON vv.via_id          = v.via_id
        ORDER BY v.name;
END;
$$;


ALTER PROCEDURE public.sp_get_vaccines_full(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_workers_for_dropdown(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_workers_for_dropdown(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$

BEGIN

    OPEN p_results FOR

        SELECT w.worker_id, w.first_name || ' ' || w.last_name AS name, r.name AS role

        FROM workers w

        LEFT JOIN roles r ON w.role_id = r.role_id

        ORDER BY w.first_name, w.last_name;

END;

$$;


ALTER PROCEDURE public.sp_get_workers_for_dropdown(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_get_workers_full(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_get_workers_full(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            w.worker_id,
            w.first_name,
            w.last_name,
            TRIM(w.first_name || ' ' || w.last_name) AS full_name,
            r.name    AS role_name,
            r.role_id,
            we.email,
            we.email  AS mail,
            r.name    AS role
        FROM workers w
        LEFT JOIN roles r ON r.role_id = w.role_id
        LEFT JOIN worker_emails we
               ON we.worker_id = w.worker_id
              AND we.is_primary = TRUE
        ORDER BY w.last_name, w.first_name;
END;
$$;


ALTER PROCEDURE public.sp_get_workers_full(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_global_search(character varying, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_global_search(IN p_query character varying, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$

BEGIN

    OPEN p_results FOR

    SELECT

        patient_id AS id,

        full_name AS name,

        'patient' AS type,

        birth_date::text AS metadata

    FROM v_patients_full

    WHERE full_name ILIKE '%' || p_query || '%' OR curp ILIKE '%' || p_query || '%'



    UNION ALL



    SELECT

        worker_id AS id,

        (first_name || ' ' || last_name) AS name,

        'worker' AS type,

        NULL AS metadata

    FROM workers

    WHERE (first_name || ' ' || last_name) ILIKE '%' || p_query || '%'



    UNION ALL



    SELECT

        vaccine_id AS id,

        name AS name,

        'vaccine' AS type,

        NULL AS metadata

    FROM vaccines

    WHERE name ILIKE '%' || p_query || '%' OR commercial_name ILIKE '%' || p_query || '%'



    UNION ALL



    SELECT

        clinic_id AS id,

        name AS name,

        'clinic' AS type,

        NULL AS metadata

    FROM clinics

    WHERE name ILIKE '%' || p_query || '%'



    ORDER BY type, name

    LIMIT 50;

END;

$$;


ALTER PROCEDURE public.sp_global_search(IN p_query character varying, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_mark_no_show(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_mark_no_show(IN p_appointment_id integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN

    UPDATE appointments
    SET
        appointment_status = 'No Show',
        appointment_notes =
            COALESCE(appointment_notes || E'\n', '')
            || '[' || CURRENT_DATE || '] Paciente no asisti¢.'
    WHERE appointment_id = p_appointment_id;

    OPEN p_results FOR
    SELECT
        appointment_id,
        patient_schedule_id,
        clinic_id,
        scheduled_at,
        appointment_status,
        appointment_notes
    FROM appointments
    WHERE appointment_id = p_appointment_id;

END;
$$;


ALTER PROCEDURE public.sp_mark_no_show(IN p_appointment_id integer, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_nfc_checkin(character varying, integer, character varying, integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_nfc_checkin(IN p_nfc_uid character varying, IN p_worker_id integer, IN p_device_id character varying, IN p_clinic_id integer, INOUT p_result refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_card_id         INT;
    v_patient_id      INT;
    v_card_status     VARCHAR(20);
    v_existing_visit  INT;
    v_visit_id        INT;
    v_scan_id         INT;
    v_area_id         INT;
    v_appointment_id  INT;
BEGIN
    -- 1. Validar que el NFC existe y est  activo
    SELECT nc.nfc_card_id, nc.patient_id, nc.status
    INTO   v_card_id, v_patient_id, v_card_status
    FROM   nfc_cards nc
    WHERE  nc.uid = p_nfc_uid;

    IF NOT FOUND THEN
        OPEN p_result FOR
            SELECT FALSE AS success, 'NFC no registrado en el sistema' AS message,
                   NULL::INT AS visit_id, NULL::INT AS patient_id,
                   NULL::TEXT AS full_name, NULL::TEXT AS visit_status;
        RETURN;
    END IF;

    IF v_card_status <> 'Activa' THEN
        OPEN p_result FOR
            SELECT FALSE AS success,
                   FORMAT('Tarjeta con estado "%s" - no se puede usar', v_card_status) AS message,
                   NULL::INT AS visit_id, v_patient_id,
                   NULL::TEXT AS full_name, NULL::TEXT AS visit_status;
        RETURN;
    END IF;

    -- 2. Verificar que no hay visita activa previa para este paciente
    SELECT visit_id INTO v_existing_visit
    FROM   patient_clinic_visits
    WHERE  patient_id   = v_patient_id
      AND  visit_status NOT IN ('Finalizado','Abandono','Cancelado')
    LIMIT 1;

    IF FOUND THEN
        OPEN p_result FOR
            SELECT FALSE AS success,
                   'El paciente ya tiene una visita activa en curso' AS message,
                   v_existing_visit AS visit_id, v_patient_id,
                   NULL::TEXT AS full_name, NULL::TEXT AS visit_status;
        RETURN;
    END IF;

    -- 3. Obtener  rea de recepci¢n de la cl¡nica
    SELECT ca.area_id INTO v_area_id
    FROM   clinic_areas ca
    JOIN   clinic_area_types cat ON cat.area_type_id = ca.area_type_id
    WHERE  ca.clinic_id = p_clinic_id
      AND  UPPER(cat.code) = 'RECEPTION'
    LIMIT 1;

    -- 4. Registrar el evento de escaneo NFC
    INSERT INTO nfc_scan_events (
        nfc_card_id, scanned_by, clinic_id, area_id,
        scanned_at, action_triggered, device_id,
        scan_context, resolved_action
    )
    VALUES (
        v_card_id, p_worker_id, p_clinic_id, v_area_id,
        NOW(), 'CHECKIN', p_device_id,
        'checkin', 'pending'
    )
    RETURNING scan_event_id INTO v_scan_id;

    -- 5. Buscar cita activa del paciente para hoy en esta cl¡nica
    SELECT appointment_id INTO v_appointment_id
    FROM   appointments
    WHERE  patient_id          = v_patient_id
      AND  clinic_id           = p_clinic_id
      AND  DATE(scheduled_at)  = CURRENT_DATE
      AND  appointment_status  IN ('Programada','Confirmada')
    ORDER  BY scheduled_at
    LIMIT  1;

    -- 6. Crear la visita cl¡nica (directamente en sala de espera)
    INSERT INTO patient_clinic_visits (
        patient_id, clinic_id, appointment_id,
        visit_status, current_area_id,
        waiting_since,
        checkin_by_worker_id, checkin_nfc_scan_id,
        visit_type, checked_in_at, created_at, updated_at
    )
    VALUES (
        v_patient_id, p_clinic_id, v_appointment_id,
        'En espera', v_area_id,
        NOW(),
        p_worker_id, v_scan_id,
        CASE WHEN v_appointment_id IS NOT NULL THEN 'Programada' ELSE 'Espontanea' END,
        NOW(), NOW(), NOW()
    )
    RETURNING visit_id INTO v_visit_id;

    -- 7. Registrar el primer movimiento (entrada directa a sala de espera)
    INSERT INTO visit_area_movements (
        visit_id, from_area_id, to_area_id,
        from_status, to_status,
        moved_at, moved_by, nfc_scan_id, movement_notes
    )
    VALUES (
        v_visit_id, NULL, v_area_id,
        NULL, 'En espera',
        NOW(), p_worker_id, v_scan_id, 'Check-in - ingresa a sala de espera'
    );

    -- 8. Actualizar scan event con el visit_id creado
    UPDATE nfc_scan_events
    SET    visit_id        = v_visit_id,
           resolved_action = 'visit_created'
    WHERE  scan_event_id   = v_scan_id;

    -- 9. Actualizar last_scanned_at de la tarjeta
    UPDATE nfc_cards
    SET    last_scanned_at = NOW()
    WHERE  nfc_card_id     = v_card_id;

    -- 10. Auditor¡a
    INSERT INTO audit_log (table_name, record_id, action, changed_data, worker_id, changed_at)
    VALUES (
        'patient_clinic_visits', v_visit_id, 'INSERT',
        jsonb_build_object(
            'action',     'checkin',
            'patient_id', v_patient_id,
            'worker_id',  p_worker_id,
            'clinic_id',  p_clinic_id,
            'visit_type', CASE WHEN v_appointment_id IS NOT NULL THEN 'Programada' ELSE 'Espontanea' END
        ),
        p_worker_id, NOW()
    );

    -- 11. Resultado con datos completos del paciente para la UI
    OPEN p_result FOR
        SELECT
            TRUE  AS success,
            'Check-in realizado correctamente' AS message,
            v_visit_id          AS visit_id,
            v_scan_id           AS scan_id,
            p.patient_id,
            TRIM(p.first_name || ' ' || p.last_name)                    AS full_name,
            p.birth_date,
            DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT     AS age,
            p.gender,
            p.photo,
            COALESCE(bt.blood_type, '-')                                AS blood_type,
            p.premature,
            v_appointment_id                                             AS appointment_id,
            COALESCE(
                (SELECT STRING_AGG(al.name || ' (' || COALESCE(pa.severity,'?') || ')', ' | ')
                 FROM   patient_allergies pa
                 JOIN   allergies al ON al.allergy_id = pa.allergy_id
                 WHERE  pa.patient_id = p.patient_id),
                'Sin alergias'
            )                                                            AS allergies,
            (SELECT COUNT(*) FROM patient_vaccine_schedule pvs
             WHERE pvs.patient_id = p.patient_id AND pvs.status = 'Pendiente')::INT AS pending_doses,
            (SELECT COUNT(*) FROM patient_vaccine_schedule pvs
             WHERE pvs.patient_id = p.patient_id AND pvs.status = 'Atrasada')::INT  AS overdue_doses,
            'En espera'::TEXT                                            AS visit_status
        FROM   patients p
        LEFT JOIN blood_types bt ON bt.blood_type_id = p.blood_type_id
        WHERE  p.patient_id = v_patient_id;

EXCEPTION WHEN unique_violation THEN
    OPEN p_result FOR
        SELECT FALSE AS success,
               'El paciente ya tiene una visita activa (violaci¢n de unicidad)' AS message,
               NULL::INT AS visit_id, v_patient_id,
               NULL::TEXT AS full_name, NULL::TEXT AS visit_status;
WHEN OTHERS THEN
    OPEN p_result FOR
        SELECT FALSE AS success, SQLERRM AS message,
               NULL::INT AS visit_id, NULL::INT AS patient_id,
               NULL::TEXT AS full_name, NULL::TEXT AS visit_status;
END;
$$;


ALTER PROCEDURE public.sp_nfc_checkin(IN p_nfc_uid character varying, IN p_worker_id integer, IN p_device_id character varying, IN p_clinic_id integer, INOUT p_result refcursor) OWNER TO postgres;

--
-- Name: sp_recepcionista_actividad_reciente(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_recepcionista_actividad_reciente(IN p_limit integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
        SELECT tipo, descripcion, ts
        FROM (
            -- Citas agendadas en las Ãºltimas 24 h
            SELECT
                'Cita agendada'                             AS tipo,
                'Cita para ' || p.first_name || ' ' || p.last_name
                    || ' a las ' || TO_CHAR(a.scheduled_at, 'HH24:MI')
                                                            AS descripcion,
                a.created_at                                AS ts
            FROM appointments a
            JOIN patients p ON p.patient_id = a.patient_id
            WHERE a.created_at >= NOW() - INTERVAL '24 hours'

            UNION ALL

            -- Pacientes registrados en las Ãºltimas 24 h
            SELECT
                'Paciente registrado'                       AS tipo,
                'Nuevo paciente: ' || p.first_name || ' ' || p.last_name
                                                            AS descripcion,
                p.created_at                                AS ts
            FROM patients p
            WHERE p.created_at >= NOW() - INTERVAL '24 hours'
              AND p.is_active = TRUE
        ) actividad
        ORDER BY ts DESC
        LIMIT p_limit;
END;
$$;


ALTER PROCEDURE public.sp_recepcionista_actividad_reciente(IN p_limit integer, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_recepcionista_citas_hoy(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_recepcionista_citas_hoy(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            a.appointment_id,
            a.scheduled_at,
            a.appointment_status,
            a.patient_id,
            (p.first_name || ' ' || p.last_name)          AS patient_name,
            COALESCE(cat.name, 'â€”')                        AS area_name,
            COALESCE(w.first_name || ' ' || w.last_name,
                     'â€”')                                  AS worker_name,
            -- Â¿Tiene vacuna programada en el esquema?
            EXISTS (
                SELECT 1 FROM patient_vaccine_schedule pvs
                WHERE pvs.patient_id = a.patient_id
                  AND pvs.status = 'Pendiente'
                  AND pvs.due_date <= CURRENT_DATE
            )                                              AS vacuna_programada,
            -- Alerta: hora ya pasÃ³ y aÃºn no se registrÃ³ asistencia
            (
                a.scheduled_at < NOW()
                AND a.appointment_status IN ('Programada', 'Confirmada')
            )                                              AS alerta_tardia
        FROM appointments a
        JOIN patients p ON p.patient_id = a.patient_id
        LEFT JOIN clinic_areas       ca  ON ca.area_id   = a.area_id
        LEFT JOIN clinic_area_types  cat ON cat.area_type_id = ca.area_type_id
        LEFT JOIN workers            w   ON w.worker_id  = a.worker_id
        WHERE DATE(a.scheduled_at) = CURRENT_DATE
        ORDER BY a.scheduled_at ASC;
END;
$$;


ALTER PROCEDURE public.sp_recepcionista_citas_hoy(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_recepcionista_kpis(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_recepcionista_kpis(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            -- Citas de hoy por estado
            COUNT(*) FILTER (
                WHERE DATE(a.scheduled_at) = CURRENT_DATE
            )                                                          AS citas_hoy_total,

            COUNT(*) FILTER (
                WHERE DATE(a.scheduled_at) = CURRENT_DATE
                  AND a.appointment_status = 'Completada'
            )                                                          AS citas_hoy_completadas,

            COUNT(*) FILTER (
                WHERE DATE(a.scheduled_at) = CURRENT_DATE
                  AND a.appointment_status IN ('Programada', 'Confirmada')
            )                                                          AS citas_hoy_pendientes,

            COUNT(*) FILTER (
                WHERE DATE(a.scheduled_at) = CURRENT_DATE
                  AND a.appointment_status = 'Cancelada'
            )                                                          AS citas_hoy_canceladas,

            COUNT(*) FILTER (
                WHERE DATE(a.scheduled_at) = CURRENT_DATE
                  AND a.appointment_status = 'No Show'
            )                                                          AS citas_hoy_no_show,

            -- Pacientes nuevos hoy
            (SELECT COUNT(*)
             FROM patients
             WHERE DATE(created_at) = CURRENT_DATE
               AND is_active = TRUE
            )                                                          AS pacientes_hoy,

            -- Pacientes nuevos esta semana (lun-dom)
            (SELECT COUNT(*)
             FROM patients
             WHERE created_at >= DATE_TRUNC('week', CURRENT_DATE)
               AND created_at <  DATE_TRUNC('week', CURRENT_DATE) + INTERVAL '7 days'
               AND is_active = TRUE
            )                                                          AS pacientes_semana

        FROM appointments a;
END;
$$;


ALTER PROCEDURE public.sp_recepcionista_kpis(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_recepcionista_pacientes_semana(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_recepcionista_pacientes_semana(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_results FOR
        WITH dias AS (
            SELECT generate_series(
                DATE_TRUNC('week', CURRENT_DATE),
                CURRENT_DATE,
                INTERVAL '1 day'
            )::DATE AS dia
        )
        SELECT
            d.dia,
            TO_CHAR(d.dia, 'Dy')   AS dia_label,
            COUNT(p.patient_id)    AS total
        FROM dias d
        LEFT JOIN patients p
               ON p.created_at::DATE = d.dia
              AND p.is_active = TRUE
        GROUP BY d.dia
        ORDER BY d.dia;
END;
$$;


ALTER PROCEDURE public.sp_recepcionista_pacientes_semana(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_reception_realtime(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_reception_realtime(IN p_clinic_id integer, INOUT p_result refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_result FOR
        SELECT
            pcv.visit_id,
            pcv.visit_status::TEXT,
            pcv.visit_type,
            pcv.checked_in_at,
            pcv.waiting_since,
            pcv.consultation_start,
            pcv.vaccination_start,
            ROUND(EXTRACT(EPOCH FROM (NOW() - pcv.checked_in_at)) / 60)::INT AS minutes_in_clinic,
            CASE
                WHEN pcv.waiting_since IS NOT NULL
                THEN ROUND(EXTRACT(EPOCH FROM (NOW() - pcv.waiting_since)) / 60)::INT
                ELSE NULL
            END                                                              AS minutes_waiting,
            p.patient_id,
            TRIM(p.first_name || ' ' || p.last_name)                        AS full_name,
            DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT         AS age,
            p.photo,
            COALESCE(ca.name, 'Sin  rea')                                   AS current_area,
            COALESCE(TRIM(w.first_name || ' ' || w.last_name), 'Sin asignar') AS assigned_worker,
            pcv.appointment_id,
            a.scheduled_at,
            a.appointment_status,
            -- Alertas cl¡nicas
            (SELECT COUNT(*) FROM patient_vaccine_schedule pvs
             WHERE pvs.patient_id = p.patient_id AND pvs.status = 'Atrasada') > 0 AS has_overdue_vaccines,
            EXISTS(SELECT 1 FROM patient_allergies WHERE patient_id = p.patient_id) AS has_allergies,
            -- Color de estado para la UI
            CASE pcv.visit_status
                WHEN 'En recepcion'  THEN '#3B82F6'
                WHEN 'En espera'     THEN '#F59E0B'
                WHEN 'En consulta'   THEN '#8B5CF6'
                WHEN 'En vacunacion' THEN '#10B981'
                ELSE                      '#6B7280'
            END                                                              AS status_color,
            -- Alerta si lleva m s de 30 minutos esperando
            CASE
                WHEN pcv.waiting_since IS NOT NULL
                 AND EXTRACT(EPOCH FROM (NOW() - pcv.waiting_since)) / 60 > 30
                THEN TRUE
                ELSE FALSE
            END                                                              AS wait_time_alert
        FROM   patient_clinic_visits pcv
        JOIN   patients p    ON p.patient_id    = pcv.patient_id
        LEFT   JOIN clinic_areas ca ON ca.area_id = pcv.current_area_id
        LEFT   JOIN workers w       ON w.worker_id = pcv.assigned_worker_id
        LEFT   JOIN appointments a  ON a.appointment_id = pcv.appointment_id
        WHERE  pcv.clinic_id    = p_clinic_id
          AND  pcv.visit_status NOT IN ('Finalizado','Abandono','Cancelado')
        ORDER  BY
            CASE pcv.visit_status
                WHEN 'En vacunacion' THEN 1
                WHEN 'En consulta'   THEN 2
                WHEN 'En espera'     THEN 3
                WHEN 'En recepcion'  THEN 4
            END,
            pcv.waiting_since NULLS LAST,
            pcv.checked_in_at;
END;
$$;


ALTER PROCEDURE public.sp_reception_realtime(IN p_clinic_id integer, INOUT p_result refcursor) OWNER TO postgres;

--
-- Name: sp_record_vaccine_reaction(integer, text, character varying, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_record_vaccine_reaction(IN p_vaccination_record_id integer, IN p_reaction_desc text, IN p_severity character varying, INOUT p_results refcursor)
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



    OPEN p_results FOR

        SELECT v_reaction_id AS reaction_id;

END;

$$;


ALTER PROCEDURE public.sp_record_vaccine_reaction(IN p_vaccination_record_id integer, IN p_reaction_desc text, IN p_severity character varying, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_refresh_overdue_statuses(refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_refresh_overdue_statuses(INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_updated INT;
BEGIN
    UPDATE patient_vaccine_schedule
    SET    status     = 'Atrasada',
           updated_at = NOW()
    WHERE  status   = 'Pendiente'
      AND  due_date < CURRENT_DATE;

    GET DIAGNOSTICS v_updated = ROW_COUNT;

    OPEN p_results FOR
        SELECT TRUE      AS success,
               v_updated  AS updated_count,
               NOW()      AS executed_at;
END;
$$;


ALTER PROCEDURE public.sp_refresh_overdue_statuses(INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_register_guardian_account(integer, character varying, character varying, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_register_guardian_account(IN p_guardian_id integer, IN p_email character varying, IN p_password_hash character varying, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_account_id INT;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM guardians
        WHERE guardian_id = p_guardian_id
    ) THEN
        RAISE EXCEPTION
        'El tutor no existe';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM guardian_accounts
        WHERE guardian_id = p_guardian_id
    ) THEN
        RAISE EXCEPTION
        'El tutor ya tiene una cuenta registrada';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM guardian_accounts
        WHERE LOWER(email) = LOWER(TRIM(p_email))
    ) THEN

        RAISE EXCEPTION
        'El correo ya est  registrado';

    END IF;

    INSERT INTO guardian_accounts (

        guardian_id,
        email,
        password_hash

    )
    VALUES (

        p_guardian_id,
        LOWER(TRIM(p_email)),
        p_password_hash

    )
    RETURNING guardian_account_id
    INTO v_account_id;

    OPEN p_results FOR

    SELECT
        v_account_id AS guardian_account_id;

END;
$$;


ALTER PROCEDURE public.sp_register_guardian_account(IN p_guardian_id integer, IN p_email character varying, IN p_password_hash character varying, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_register_manual_movement(integer, integer, character varying, integer, text, refcursor); Type: PROCEDURE; Schema: public; Owner: vaccine_user
--

CREATE PROCEDURE public.sp_register_manual_movement(IN p_lot_id integer, IN p_worker_id integer, IN p_movement_type character varying, IN p_quantity integer, IN p_reason text, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_lot           RECORD;
    v_qty_before    INT;
    v_qty_after     INT;
    v_movement_id   INT;
    v_allowed_types TEXT[] := ARRAY['Ajuste_Positivo','Ajuste_Negativo','Salida_Merma','Salida_Caducidad'];
BEGIN
    IF NOT (p_movement_type = ANY(v_allowed_types)) THEN
        OPEN p_results FOR SELECT FALSE AS success,
            'Tipo de movimiento no permitido: ' || p_movement_type AS message,
            NULL::INT AS movement_id, NULL::INT AS quantity_after;
        RETURN;
    END IF;

    SELECT vl.lot_id, vl.vaccine_id, vl.clinic_id, vl.quantity_available, vl.lot_status
    INTO v_lot
    FROM vaccine_lots vl
    WHERE vl.lot_id = p_lot_id FOR UPDATE;

    IF NOT FOUND THEN
        OPEN p_results FOR SELECT FALSE AS success, 'Lote no encontrado.' AS message,
            NULL::INT AS movement_id, NULL::INT AS quantity_after;
        RETURN;
    END IF;

    v_qty_before := v_lot.quantity_available;

    IF p_movement_type IN ('Ajuste_Negativo','Salida_Merma','Salida_Caducidad') THEN
        IF v_qty_before < p_quantity THEN
            OPEN p_results FOR SELECT FALSE AS success,
                'Stock insuficiente. Disponible: ' || v_qty_before AS message,
                NULL::INT AS movement_id, NULL::INT AS quantity_after;
            RETURN;
        END IF;
        v_qty_after := v_qty_before - p_quantity;
    ELSE
        v_qty_after := v_qty_before + p_quantity;
    END IF;

    UPDATE vaccine_lots
    SET quantity_available = v_qty_after,
        lot_status = CASE
            WHEN v_qty_after = 0 THEN 'Agotado'
            WHEN v_qty_after > 0 AND lot_status = 'Agotado' AND expiration_date >= CURRENT_DATE THEN 'Disponible'
            ELSE lot_status
        END
    WHERE lot_id = p_lot_id;

    INSERT INTO inventory_movements (
        lot_id, vaccine_id, clinic_id, worker_id,
        movement_type, quantity, quantity_before, quantity_after,
        reference_type, reason
    ) VALUES (
        p_lot_id, v_lot.vaccine_id, v_lot.clinic_id, p_worker_id,
        p_movement_type, p_quantity, v_qty_before, v_qty_after,
        'manual', p_reason
    ) RETURNING movement_id INTO v_movement_id;

    OPEN p_results FOR SELECT TRUE AS success,
        'Movimiento registrado correctamente.' AS message,
        v_movement_id AS movement_id, v_qty_after AS quantity_after;
END;
$$;


ALTER PROCEDURE public.sp_register_manual_movement(IN p_lot_id integer, IN p_worker_id integer, IN p_movement_type character varying, IN p_quantity integer, IN p_reason text, INOUT p_results refcursor) OWNER TO vaccine_user;

--
-- Name: sp_register_nfc_scan(character varying, integer, integer, integer, character varying, character varying, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_register_nfc_scan(IN p_uid character varying, IN p_worker_id integer, IN p_clinic_id integer, IN p_area_id integer, IN p_device_id character varying, IN p_action character varying, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_nfc_card_id   INT;
    v_patient_id    INT;
    v_card_status   VARCHAR;
    v_scan_result   VARCHAR;
    v_scan_event_id INT;
BEGIN
    -- Buscar tarjeta por UID
    SELECT nfc_card_id, patient_id, status
    INTO   v_nfc_card_id, v_patient_id, v_card_status
    FROM   nfc_cards
    WHERE  uid = TRIM(p_uid);

    IF NOT FOUND THEN
        v_scan_result := 'Error: UID no registrado';

        -- Registrar el intento fallido igualmente
        INSERT INTO nfc_scan_events (
            nfc_card_id, scanned_by, clinic_id, area_id,
            scanned_at, action_triggered, device_id, nfc_scan_result
        )
        SELECT -1, p_worker_id, p_clinic_id, p_area_id,
               NOW(), p_action, p_device_id, v_scan_result
        WHERE FALSE; -- no se inserta, tarjeta no existe

        OPEN p_results FOR
            SELECT FALSE AS success, v_scan_result AS message,
                   NULL::INT AS nfc_card_id, NULL::INT AS patient_id,
                   NULL::VARCHAR AS patient_name, NULL::TEXT AS card_status;
        RETURN;
    END IF;

    -- Validar estado de la tarjeta
    IF v_card_status IN ('Perdida', 'Robada') THEN
        v_scan_result := 'Error: tarjeta ' || v_card_status || ' - contactar seguridad';

        INSERT INTO nfc_scan_events (
            nfc_card_id, scanned_by, clinic_id, area_id,
            scanned_at, action_triggered, device_id, nfc_scan_result
        )
        VALUES (
            v_nfc_card_id, p_worker_id, p_clinic_id, p_area_id,
            NOW(), p_action, p_device_id, v_scan_result
        )
        RETURNING scan_event_id INTO v_scan_event_id;

        OPEN p_results FOR
            SELECT FALSE AS success, v_scan_result AS message,
                   v_nfc_card_id AS nfc_card_id, v_patient_id AS patient_id,
                   NULL::VARCHAR AS patient_name, v_card_status AS card_status;
        RETURN;
    END IF;

    IF v_card_status = 'Inactiva' THEN
        v_scan_result := 'Error: tarjeta inactiva';

        INSERT INTO nfc_scan_events (
            nfc_card_id, scanned_by, clinic_id, area_id,
            scanned_at, action_triggered, device_id, nfc_scan_result
        )
        VALUES (
            v_nfc_card_id, p_worker_id, p_clinic_id, p_area_id,
            NOW(), p_action, p_device_id, v_scan_result
        )
        RETURNING scan_event_id INTO v_scan_event_id;

        OPEN p_results FOR
            SELECT FALSE AS success, v_scan_result AS message,
                   v_nfc_card_id AS nfc_card_id, v_patient_id AS patient_id,
                   NULL::VARCHAR AS patient_name, v_card_status AS card_status;
        RETURN;
    END IF;

    -- Validar clínica
    IF NOT EXISTS (SELECT 1 FROM clinics WHERE clinic_id = p_clinic_id AND is_active = TRUE) THEN
        RAISE EXCEPTION 'Clinica % no encontrada o inactiva', p_clinic_id;
    END IF;

    -- Validar trabajador si se proporciona
    IF p_worker_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM workers WHERE worker_id = p_worker_id
    ) THEN
        RAISE EXCEPTION 'Trabajador % no encontrado', p_worker_id;
    END IF;

    v_scan_result := 'Exito';

    -- Registrar escaneo exitoso
    INSERT INTO nfc_scan_events (
        nfc_card_id, scanned_by, clinic_id, area_id,
        scanned_at, action_triggered, device_id, nfc_scan_result
    )
    VALUES (
        v_nfc_card_id, p_worker_id, p_clinic_id, p_area_id,
        NOW(), COALESCE(p_action, 'Consulta'), p_device_id, v_scan_result
    )
    RETURNING scan_event_id INTO v_scan_event_id;

    -- Actualizar last_scanned_at en la tarjeta
    UPDATE nfc_cards
    SET last_scanned_at = NOW()
    WHERE nfc_card_id = v_nfc_card_id;

    -- Devolver datos del paciente para mostrar en pantalla
    OPEN p_results FOR
        SELECT
            TRUE                                              AS success,
            'Acceso concedido'                               AS message,
            v_scan_event_id                                  AS scan_event_id,
            v_nfc_card_id                                    AS nfc_card_id,
            v_patient_id                                     AS patient_id,
            TRIM(p.first_name || ' ' || p.last_name)        AS patient_name,
            p.birth_date,
            DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT AS age_years,
            COALESCE(bt.blood_type, '-')                    AS blood_type,
            v_card_status                                    AS card_status,
            -- Próximas 3 dosis pendientes del paciente (JSON)
            (
                SELECT JSON_AGG(sub)
                FROM (
                    SELECT
                        v2.name                                         AS vaccine,
                        sd2.dose_label                                  AS dose,
                        (p2.birth_date + (sd2.ideal_age_months || ' months')::INTERVAL)::DATE
                                                                        AS due_date
                    FROM scheme_doses sd2
                    JOIN vaccines v2 ON v2.vaccine_id = sd2.vaccine_id
                    JOIN patients  p2 ON p2.patient_id = v_patient_id
                    WHERE NOT EXISTS (
                        SELECT 1 FROM vaccination_records vr2
                        WHERE vr2.patient_id    = v_patient_id
                          AND vr2.scheme_dose_id = sd2.dose_id
                    )
                    ORDER BY sd2.ideal_age_months
                    LIMIT 3
                ) sub
            )                                               AS pending_doses
        FROM patients p
        LEFT JOIN blood_types bt ON bt.blood_type_id = p.blood_type_id
        WHERE p.patient_id = v_patient_id;

EXCEPTION WHEN OTHERS THEN
    OPEN p_results FOR
        SELECT FALSE AS success, SQLERRM AS message,
               NULL::INT AS scan_event_id, NULL::INT AS nfc_card_id,
               NULL::INT AS patient_id,   NULL::VARCHAR AS patient_name,
               NULL::DATE AS birth_date,  NULL::INT AS age_years,
               NULL::VARCHAR AS blood_type, NULL::VARCHAR AS card_status,
               NULL::JSON AS pending_doses;
END;
$$;


ALTER PROCEDURE public.sp_register_nfc_scan(IN p_uid character varying, IN p_worker_id integer, IN p_clinic_id integer, IN p_area_id integer, IN p_device_id character varying, IN p_action character varying, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_register_patient(character varying, character varying, character varying, date, character, integer, numeric, boolean, character varying, character varying, character varying, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_register_patient(IN p_first_name character varying, IN p_last_name character varying, IN p_curp character varying, IN p_birth_date date, IN p_gender character, IN p_blood_type_id integer, IN p_weight_kg numeric, IN p_premature boolean, IN p_guardian_name character varying, IN p_guardian_last character varying, IN p_guardian_phone character varying, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_guardian_id INT;
    v_patient_id  INT;
    v_age_years   INT;
BEGIN

    IF TRIM(p_first_name) = '' THEN
        RAISE EXCEPTION 'El nombre es obligatorio';
    END IF;

    IF TRIM(p_last_name) = '' THEN
        RAISE EXCEPTION 'El apellido es obligatorio';
    END IF;

    IF p_birth_date > CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha de nacimiento no puede ser futura';
    END IF;

    v_age_years := DATE_PART('year', AGE(CURRENT_DATE, p_birth_date));

    IF v_age_years > 10 THEN
        RAISE EXCEPTION 'El paciente excede la edad pediatrica permitida';
    END IF;

    IF p_gender NOT IN ('M', 'F') THEN
        RAISE EXCEPTION 'Genero invalido';
    END IF;

    IF LENGTH(TRIM(p_curp)) <> 18 THEN
        RAISE EXCEPTION 'CURP invalida';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM patients
        WHERE curp = p_curp
    ) THEN
        RAISE EXCEPTION 'El CURP ya existe';
    END IF;

    IF p_weight_kg <= 0 OR p_weight_kg > 80 THEN
        RAISE EXCEPTION 'Peso fuera de rango pediatrico';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM blood_types
        WHERE blood_type_id = p_blood_type_id
    ) THEN
        RAISE EXCEPTION 'Tipo sanguineo inexistente';
    END IF;

    SELECT guardian_id
    INTO v_guardian_id
    FROM guardians
    WHERE first_name = p_guardian_name
    AND last_name = p_guardian_last
    LIMIT 1;

    IF v_guardian_id IS NULL THEN

        INSERT INTO guardians (
            first_name,
            last_name
        )
        VALUES (
            p_guardian_name,
            p_guardian_last
        )
        RETURNING guardian_id
        INTO v_guardian_id;

    END IF;

    IF p_guardian_phone IS NOT NULL THEN

        IF LENGTH(TRIM(p_guardian_phone)) < 10 THEN
            RAISE EXCEPTION 'Telefono invalido';
        END IF;

        INSERT INTO guardian_phones (
            guardian_id,
            phone,
            phone_type,
            is_primary
        )
        VALUES (
            v_guardian_id,
            p_guardian_phone,
            'Celular',
            TRUE
        );

    END IF;

    INSERT INTO patients (
        first_name,
        last_name,
        curp,
        birth_date,
        gender,
        blood_type_id,
        weight_kg,
        premature,
        created_at,
        is_active
    )
    VALUES (
        p_first_name,
        p_last_name,
        p_curp,
        p_birth_date,
        p_gender,
        p_blood_type_id,
        p_weight_kg,
        p_premature,
        NOW(),
        TRUE
    )
    RETURNING patient_id
    INTO v_patient_id;

    INSERT INTO patient_guardian_relations (
        patient_id,
        guardian_id,
        relation_type,
        is_primary,
        has_custody
    )
    VALUES (
        v_patient_id,
        v_guardian_id,
        'Tutor',
        TRUE,
        TRUE
    );

    OPEN p_results FOR
    SELECT
        TRUE AS success,
        'Paciente registrado correctamente' AS message,
        v_patient_id AS patient_id;

EXCEPTION
WHEN OTHERS THEN

    OPEN p_results FOR
    SELECT
        FALSE AS success,
        SQLERRM AS message,
        NULL::INT AS patient_id;

END;
$$;


ALTER PROCEDURE public.sp_register_patient(IN p_first_name character varying, IN p_last_name character varying, IN p_curp character varying, IN p_birth_date date, IN p_gender character, IN p_blood_type_id integer, IN p_weight_kg numeric, IN p_premature boolean, IN p_guardian_name character varying, IN p_guardian_last character varying, IN p_guardian_phone character varying, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_register_patient(character varying, character varying, character varying, date, character, integer, numeric, boolean, character varying, character varying, character varying, character varying, character varying, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_register_patient(IN p_first_name character varying, IN p_last_name character varying, IN p_curp character varying, IN p_birth_date date, IN p_gender character, IN p_blood_type_id integer, IN p_weight_kg numeric, IN p_premature boolean, IN p_guardian_name character varying, IN p_guardian_last character varying, IN p_guardian_curp character varying, IN p_guardian_phone character varying, IN p_guardian_email character varying, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_guardian_id INT;
    v_patient_id  INT;
    v_age_years   INT;
BEGIN

    -- Reglas de negocio y clinicas (Flask ya valido formato basico)

    -- Fecha no puede ser futura (regla de negocio)
    IF p_birth_date IS NULL OR p_birth_date > CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha de nacimiento no puede ser futura';
    END IF;

    -- Edad maxima pediatrica (regla clinica)
    v_age_years := DATE_PART('year', AGE(CURRENT_DATE, p_birth_date));
    IF v_age_years > 15 THEN
        RAISE EXCEPTION 'El paciente excede la edad pediatrica permitida';
    END IF;

    -- CURP duplicado (integridad)
    IF p_curp IS NOT NULL AND EXISTS (
        SELECT 1 FROM patients WHERE curp = p_curp
    ) THEN
        RAISE EXCEPTION 'El CURP ya existe';
    END IF;

    -- Peso fuera de rango (regla clinica)
    IF p_weight_kg IS NOT NULL AND (p_weight_kg <= 0 OR p_weight_kg > 80) THEN
        RAISE EXCEPTION 'Peso fuera de rango pediatrico';
    END IF;

    -- Tipo de sangre inexistente (integridad referencial)
    IF p_blood_type_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM blood_types WHERE blood_type_id = p_blood_type_id
    ) THEN
        RAISE EXCEPTION 'Tipo sanguineo inexistente';
    END IF;

    -- ÄÄ Tutor: buscar o crear ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ

    -- 1. Buscar por CURP (identificador unico, mas confiable)
    IF p_guardian_curp IS NOT NULL AND TRIM(p_guardian_curp) <> '' THEN
        SELECT guardian_id INTO v_guardian_id
        FROM   guardians
        WHERE  curp = UPPER(TRIM(p_guardian_curp))
        LIMIT  1;
    END IF;

    -- 2. Fallback: buscar por nombre completo si no hubo match por CURP
    IF v_guardian_id IS NULL
       AND p_guardian_name IS NOT NULL AND TRIM(p_guardian_name) <> ''
       AND p_guardian_last IS NOT NULL AND TRIM(p_guardian_last) <> ''
    THEN
        SELECT guardian_id INTO v_guardian_id
        FROM   guardians
        WHERE  first_name = TRIM(p_guardian_name)
          AND  last_name  = TRIM(p_guardian_last)
        LIMIT  1;
    END IF;

    -- 3. Si no existe, crear tutor nuevo (con manejo de race condition en CURP)
    IF v_guardian_id IS NULL AND p_guardian_name IS NOT NULL AND TRIM(p_guardian_name) <> '' THEN
        BEGIN
            INSERT INTO guardians (first_name, last_name, curp)
            VALUES (
                TRIM(p_guardian_name),
                TRIM(COALESCE(p_guardian_last, '')),
                NULLIF(UPPER(TRIM(COALESCE(p_guardian_curp, ''))), '')
            )
            RETURNING guardian_id INTO v_guardian_id;
        EXCEPTION
            WHEN unique_violation THEN
                -- CURP ya registrado; recuperar el guardian existente sin modificarlo
                SELECT guardian_id INTO v_guardian_id
                FROM   guardians
                WHERE  curp = NULLIF(UPPER(TRIM(COALESCE(p_guardian_curp, ''))), '');
        END;
    END IF;

    -- 4. Agregar contacto solo si no existe ya (ON CONFLICT DO NOTHING evita duplicados)
    --    Esto aplica tanto a tutores nuevos como a tutores ya existentes.
    IF v_guardian_id IS NOT NULL THEN

        IF p_guardian_phone IS NOT NULL AND TRIM(p_guardian_phone) <> '' THEN
            -- Contar solo digitos para validar longitud minima (regla clinica)
            IF LENGTH(REGEXP_REPLACE(p_guardian_phone, '[^0-9]', '', 'g')) < 10 THEN
                RAISE EXCEPTION 'Telefono invalido';
            END IF;
            INSERT INTO guardian_phones (guardian_id, phone, phone_type, is_primary)
            VALUES (v_guardian_id, TRIM(p_guardian_phone), 'Celular', TRUE)
            ON CONFLICT (guardian_id, phone) DO NOTHING;
        END IF;

        IF p_guardian_email IS NOT NULL AND TRIM(p_guardian_email) <> '' THEN
            INSERT INTO guardian_emails (guardian_id, email, is_primary)
            VALUES (v_guardian_id, TRIM(p_guardian_email), TRUE)
            ON CONFLICT (guardian_id, email) DO NOTHING;
        END IF;

    END IF;

    -- ÄÄ Insertar paciente ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ

    INSERT INTO patients (
        first_name, last_name, curp, birth_date, gender,
        blood_type_id, weight_kg, premature, created_at, is_active
    )
    VALUES (
        TRIM(p_first_name),
        TRIM(p_last_name),
        NULLIF(TRIM(COALESCE(p_curp, '')), ''),
        p_birth_date,
        p_gender,
        p_blood_type_id,
        p_weight_kg,
        COALESCE(p_premature, FALSE),
        NOW(),
        TRUE
    )
    RETURNING patient_id INTO v_patient_id;

    -- ÄÄ Vincular paciente con tutor ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ

    IF v_guardian_id IS NOT NULL THEN
        INSERT INTO patient_guardian_relations (
            patient_id, guardian_id, relation_type, is_primary, has_custody
        )
        VALUES (v_patient_id, v_guardian_id, 'Tutor', TRUE, TRUE)
        ON CONFLICT DO NOTHING;
    END IF;

    -- Resultado exitoso
    OPEN p_results FOR
        SELECT TRUE                                AS success,
               'Paciente registrado correctamente' AS message,
               v_patient_id                        AS patient_id,
               v_guardian_id                       AS guardian_id;

EXCEPTION
WHEN OTHERS THEN
    -- Cualquier error de negocio/integridad regresa como fila, no como excepcion
    OPEN p_results FOR
        SELECT FALSE    AS success,
               SQLERRM  AS message,
               NULL::INT AS patient_id,
               NULL::INT AS guardian_id;
END;
$$;


ALTER PROCEDURE public.sp_register_patient(IN p_first_name character varying, IN p_last_name character varying, IN p_curp character varying, IN p_birth_date date, IN p_gender character, IN p_blood_type_id integer, IN p_weight_kg numeric, IN p_premature boolean, IN p_guardian_name character varying, IN p_guardian_last character varying, IN p_guardian_curp character varying, IN p_guardian_phone character varying, IN p_guardian_email character varying, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_register_vaccination_record(integer, integer, integer, integer, integer, integer, date, integer, numeric, boolean, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_register_vaccination_record(IN p_patient_id integer, IN p_vaccine_id integer, IN p_worker_id integer, IN p_clinic_id integer, IN p_lot_id integer, IN p_scheme_dose_id integer, IN p_applied_date date, IN p_application_site_id integer, IN p_patient_temp_c numeric, IN p_had_reaction boolean, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE

    v_record_id                  INT;

    v_birth_date                 DATE;
    v_patient_age_months         INT;

    v_ideal_age_months           INT;
    v_min_interval_days          INT;

    v_last_application_date      DATE;
    v_days_since_last_dose       INT;

    v_schedule_status            TEXT;

BEGIN

    -- =====================================================
    -- VALIDAR PACIENTE
    -- =====================================================

    SELECT birth_date
    INTO v_birth_date
    FROM patients
    WHERE patient_id = p_patient_id
    AND is_active = TRUE;

    IF v_birth_date IS NULL THEN
        RAISE EXCEPTION
        'El paciente no existe o est  inactivo';
    END IF;

    -- =====================================================
    -- VALIDAR PERSONAL AUTORIZADO
    -- =====================================================

    IF NOT EXISTS (

        SELECT 1
        FROM workers w
        JOIN roles r
            ON r.role_id = w.role_id
        WHERE w.worker_id = p_worker_id
        AND w.is_active = TRUE
        AND r.name IN ('Medico', 'Enfermero')

    ) THEN

        RAISE EXCEPTION
        'Solo medicos o enfermeros pueden aplicar vacunas';

    END IF;

    -- =====================================================
    -- VALIDAR CLÖNICA
    -- =====================================================

    IF NOT EXISTS (

        SELECT 1
        FROM clinics
        WHERE clinic_id = p_clinic_id

    ) THEN

        RAISE EXCEPTION
        'La cl¡nica no existe';

    END IF;

    -- =====================================================
    -- VALIDAR VACUNA
    -- =====================================================

    IF NOT EXISTS (

        SELECT 1
        FROM vaccines
        WHERE vaccine_id = p_vaccine_id

    ) THEN

        RAISE EXCEPTION
        'La vacuna no existe';

    END IF;

    -- =====================================================
    -- VALIDAR LOTE
    -- =====================================================

    IF NOT EXISTS (

        SELECT 1
        FROM vaccine_lots
        WHERE lot_id = p_lot_id
        AND expiration_date >= CURRENT_DATE
        AND quantity_available > 0

    ) THEN

        RAISE EXCEPTION
        'El lote no existe, est  vencido o no tiene stock';

    END IF;

    -- =====================================================
    -- VALIDAR QUE EL LOTE PERTENEZCA A LA CLÖNICA
    -- =====================================================

    IF NOT EXISTS (

        SELECT 1
        FROM vaccine_lots
        WHERE lot_id = p_lot_id
        AND clinic_id = p_clinic_id

    ) THEN

        RAISE EXCEPTION
        'El lote no pertenece a la cl¡nica seleccionada';

    END IF;

    -- =====================================================
    -- VALIDAR FECHA
    -- =====================================================

    IF p_applied_date > CURRENT_DATE THEN

        RAISE EXCEPTION
        'La fecha de aplicaci¢n no puede ser futura';

    END IF;

    -- =====================================================
    -- VALIDAR TEMPERATURA
    -- =====================================================

    IF p_patient_temp_c IS NOT NULL THEN

        IF p_patient_temp_c < 30
        OR p_patient_temp_c > 45 THEN

            RAISE EXCEPTION
            'Temperatura corporal inv lida';

        END IF;

    END IF;

    -- =====================================================
    -- VALIDAR SITIO DE APLICACIàN
    -- =====================================================

    IF NOT EXISTS (

        SELECT 1
        FROM application_sites
        WHERE application_site_id = p_application_site_id

    ) THEN

        RAISE EXCEPTION
        'El sitio de aplicaci¢n no existe';

    END IF;

    -- =====================================================
    -- VALIDAR ESQUEMA DEL PACIENTE
    -- =====================================================

    SELECT status
    INTO v_schedule_status
    FROM patient_vaccine_schedule
    WHERE patient_id = p_patient_id
    AND scheme_dose_id = p_scheme_dose_id;

    IF v_schedule_status IS NULL THEN

        RAISE EXCEPTION
        'La dosis no pertenece al esquema del paciente';

    END IF;

    -- =====================================================
    -- VALIDAR DOSIS DUPLICADA
    -- =====================================================

    IF EXISTS (

        SELECT 1
        FROM vaccination_records
        WHERE patient_id = p_patient_id
        AND scheme_dose_id = p_scheme_dose_id

    ) THEN

        RAISE EXCEPTION
        'La dosis ya fue aplicada al paciente';

    END IF;

    -- =====================================================
    -- VALIDAR EDAD MÖNIMA
    -- =====================================================

    SELECT ideal_age_months
    INTO v_ideal_age_months
    FROM scheme_doses
    WHERE dose_id = p_scheme_dose_id;

    v_patient_age_months :=

        (
            EXTRACT(YEAR FROM AGE(p_applied_date, v_birth_date)) * 12
        )
        +
        EXTRACT(MONTH FROM AGE(p_applied_date, v_birth_date));

    IF v_ideal_age_months IS NOT NULL
    AND v_patient_age_months < v_ideal_age_months THEN

        RAISE EXCEPTION
        'El paciente no cumple la edad m¡nima requerida';

    END IF;

    -- =====================================================
    -- VALIDAR INTERVALO ENTRE DOSIS
    -- =====================================================

    SELECT min_interval_days
    INTO v_min_interval_days
    FROM scheme_doses
    WHERE dose_id = p_scheme_dose_id;

    SELECT MAX(applied_date)
    INTO v_last_application_date
    FROM vaccination_records
    WHERE patient_id = p_patient_id
    AND vaccine_id = p_vaccine_id;

    IF v_last_application_date IS NOT NULL
    AND v_min_interval_days IS NOT NULL THEN

        v_days_since_last_dose :=
            p_applied_date - v_last_application_date;

        IF v_days_since_last_dose < v_min_interval_days THEN

            RAISE EXCEPTION
            'No se cumple el intervalo m¡nimo entre dosis';

        END IF;

    END IF;

    -- =====================================================
    -- INSERTAR APLICACIàN
    -- =====================================================

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
        had_reaction,
        created_at

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
        COALESCE(p_had_reaction, FALSE),
        NOW()

    )
    RETURNING record_id
    INTO v_record_id;

    -- =====================================================
    -- RESPUESTA
    -- =====================================================

    OPEN p_results FOR

    SELECT
        TRUE  AS success,
        'Vacuna aplicada correctamente' AS message,
        v_record_id AS record_id;

END;
$$;


ALTER PROCEDURE public.sp_register_vaccination_record(IN p_patient_id integer, IN p_vaccine_id integer, IN p_worker_id integer, IN p_clinic_id integer, IN p_lot_id integer, IN p_scheme_dose_id integer, IN p_applied_date date, IN p_application_site_id integer, IN p_patient_temp_c numeric, IN p_had_reaction boolean, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_register_vaccine(character varying, character varying, integer, integer, smallint, text, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_register_vaccine(IN p_name character varying, IN p_commercial_name character varying, IN p_manufacturer_id integer, IN p_via_id integer, IN p_ideal_age_months smallint, IN p_disease_prevented text, INOUT p_results refcursor)
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

    OPEN p_results FOR
        SELECT v_vaccine_id AS vaccine_id;
END;
$$;


ALTER PROCEDURE public.sp_register_vaccine(IN p_name character varying, IN p_commercial_name character varying, IN p_manufacturer_id integer, IN p_via_id integer, IN p_ideal_age_months smallint, IN p_disease_prevented text, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_register_worker(integer, character varying, character varying, date, character varying, character varying, character varying, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_register_worker(IN p_role_id integer, IN p_first_name character varying, IN p_last_name character varying, IN p_hire_date date, IN p_password character varying, IN p_email character varying, IN p_phone character varying, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_worker_id INT;
    v_user_id   INT;
BEGIN
    INSERT INTO workers (role_id, first_name, last_name, hire_date)
    VALUES (p_role_id, p_first_name, p_last_name, p_hire_date)
    RETURNING worker_id INTO v_worker_id;

    IF p_email IS NOT NULL AND TRIM(p_email) <> '' THEN
        INSERT INTO worker_emails (worker_id, email, is_primary)
        VALUES (v_worker_id, p_email, TRUE);
    END IF;

    INSERT INTO users (worker_id, username, password_hash, is_active)
    VALUES (v_worker_id, COALESCE(p_email, 'user_' || v_worker_id),
            p_password, TRUE)
    RETURNING user_id INTO v_user_id;

    OPEN p_results FOR
        SELECT TRUE AS success, 'Trabajador registrado' AS message, v_worker_id AS worker_id;
EXCEPTION
WHEN OTHERS THEN
    OPEN p_results FOR
        SELECT FALSE AS success, SQLERRM AS message, NULL::INT AS worker_id;
END;
$$;


ALTER PROCEDURE public.sp_register_worker(IN p_role_id integer, IN p_first_name character varying, IN p_last_name character varying, IN p_hire_date date, IN p_password character varying, IN p_email character varying, IN p_phone character varying, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_reject_transfer(integer, integer, text, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_reject_transfer(IN p_transfer_id integer, IN p_worker_id integer, IN p_reason text, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE v_status VARCHAR(20);
BEGIN
    SELECT transfer_status INTO v_status
    FROM inventory_transfers WHERE transfer_id = p_transfer_id FOR UPDATE;

    IF NOT FOUND THEN
        OPEN p_results FOR SELECT FALSE AS success, 'Transferencia no encontrada.' AS message;
        RETURN;
    END IF;

    IF v_status <> 'Pendiente' THEN
        OPEN p_results FOR SELECT FALSE AS success,
            'Solo se pueden rechazar transferencias Pendientes. Estado actual: ' || v_status AS message;
        RETURN;
    END IF;

    UPDATE inventory_transfers
    SET transfer_status = 'Rechazado',
        approved_by     = p_worker_id,
        notes           = p_reason,
        resolved_at     = NOW()
    WHERE transfer_id = p_transfer_id;

    OPEN p_results FOR SELECT TRUE AS success,
        'Transferencia #' || p_transfer_id || ' rechazada.' AS message;
END;
$$;


ALTER PROCEDURE public.sp_reject_transfer(IN p_transfer_id integer, IN p_worker_id integer, IN p_reason text, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_reportes_resumen(date, date, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_reportes_resumen(IN p_from date, IN p_to date, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_total_doses       BIGINT;
    v_reached           BIGINT;
    v_target            BIGINT;
    v_coverage          NUMERIC(5,1);
    v_avg_delay         NUMERIC(6,1);
    v_reaction_rate     NUMERIC(5,1);
    v_completed_scheme  BIGINT;
    v_delayed_patients  BIGINT;
    v_appt_rate         NUMERIC(5,1);
    v_low_stock         BIGINT;
    v_new_patients      BIGINT;
    v_active_workers    BIGINT;
    v_avg_temp          NUMERIC(4,1);
    v_active_zones      BIGINT;
    v_vaccines_json     JSON;
    v_monthly_json      JSON;
    v_zones_json        JSON;
BEGIN

    -- ÄÄ Dosis aplicadas y pacientes £nicos en el per¡odo ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
    SELECT
        COUNT(*)                        INTO v_total_doses
    FROM vaccination_records
    WHERE applied_date BETWEEN p_from AND p_to;

    SELECT
        COUNT(DISTINCT patient_id)      INTO v_reached
    FROM vaccination_records
    WHERE applied_date BETWEEN p_from AND p_to;

    SELECT COUNT(*)                     INTO v_target
    FROM patients
    WHERE is_active = TRUE;

    v_coverage := CASE
        WHEN v_target > 0 THEN ROUND((v_reached::NUMERIC / v_target) * 100, 1)
        ELSE 0
    END;

    -- ÄÄ Temperatura promedio ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
    SELECT ROUND(AVG(patient_temp_c), 1) INTO v_avg_temp
    FROM vaccination_records
    WHERE applied_date BETWEEN p_from AND p_to
      AND patient_temp_c IS NOT NULL;

    -- ÄÄ Tasa de reacciones adversas ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
    SELECT CASE
        WHEN COUNT(*) > 0
        THEN ROUND(COUNT(*) FILTER (WHERE had_reaction = TRUE)::NUMERIC / COUNT(*) * 100, 1)
        ELSE 0
    END INTO v_reaction_rate
    FROM vaccination_records
    WHERE applied_date BETWEEN p_from AND p_to;

    -- ÄÄ Pacientes con esquema completo ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
    -- Se considera completo quien no tiene ninguna dosis en estado 'Pendiente' o 'Atrasada'
    SELECT COUNT(DISTINCT patient_id) INTO v_completed_scheme
    FROM patients p
    WHERE is_active = TRUE
      AND NOT EXISTS (
          SELECT 1 FROM patient_vaccine_schedule pvs
          WHERE pvs.patient_id = p.patient_id
            AND pvs.status IN ('Pendiente', 'Atrasada')
      );

    -- ÄÄ Pacientes con vacunas atrasadas ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
    SELECT COUNT(DISTINCT patient_id) INTO v_delayed_patients
    FROM patient_vaccine_schedule
    WHERE status = 'Atrasada';

    -- ÄÄ Tasa de cumplimiento de citas ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
    SELECT CASE
        WHEN COUNT(*) > 0
        THEN ROUND(
            COUNT(*) FILTER (WHERE appointment_status = 'Completada')::NUMERIC
            / COUNT(*) * 100, 1)
        ELSE NULL
    END INTO v_appt_rate
    FROM appointments
    WHERE scheduled_at::DATE BETWEEN p_from AND p_to;

    -- ÄÄ Lotes en stock bajo (= 10 unidades) ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
    SELECT COUNT(*) INTO v_low_stock
    FROM vaccine_lots
    WHERE quantity_available <= 10
      AND expiration_date >= CURRENT_DATE;

    -- ÄÄ Nuevos pacientes en el per¡odo ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
    SELECT COUNT(*) INTO v_new_patients
    FROM patients
    WHERE created_at::DATE BETWEEN p_from AND p_to;

    -- ÄÄ Trabajadores activos que aplicaron en el per¡odo ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
    SELECT COUNT(DISTINCT worker_id) INTO v_active_workers
    FROM vaccination_records
    WHERE applied_date BETWEEN p_from AND p_to;

    -- ÄÄ Retraso promedio (d¡as entre due_date y applied_date) ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
    SELECT ROUND(AVG(
        EXTRACT(EPOCH FROM (vr.applied_date - pvs.due_date)) / 86400
    ), 1) INTO v_avg_delay
    FROM vaccination_records vr
    JOIN patient_vaccine_schedule pvs
      ON vr.patient_id = pvs.patient_id
     AND vr.scheme_dose_id = pvs.scheme_dose_id
    WHERE vr.applied_date BETWEEN p_from AND p_to
      AND vr.applied_date > pvs.due_date;

    -- ÄÄ Zonas activas (municipios con al menos una dosis en el per¡odo) ÄÄÄÄÄÄÄ
    SELECT COUNT(DISTINCT a.neighborhood_id) INTO v_active_zones
    FROM vaccination_records vr
    JOIN clinics c   ON vr.clinic_id  = c.clinic_id
    JOIN addresses a ON c.address_id  = a.address_id
    WHERE vr.applied_date BETWEEN p_from AND p_to;

    -- ÄÄ JSON: vacunas (top 50 por dosis aplicadas) ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
    SELECT json_agg(t) INTO v_vaccines_json FROM (
        SELECT
            v.name                                          AS vaccine_name,
            COUNT(vr.record_id)                             AS doses_applied,
            COUNT(DISTINCT vr.patient_id)                   AS unique_patients,
            ROUND(
                COUNT(vr.record_id)::NUMERIC
                / NULLIF(v_total_doses, 0) * 100, 1
            )                                               AS share_percent
        FROM vaccination_records vr
        JOIN vaccines v ON vr.vaccine_id = v.vaccine_id
        WHERE vr.applied_date BETWEEN p_from AND p_to
        GROUP BY v.vaccine_id, v.name
        ORDER BY doses_applied DESC
        LIMIT 50
    ) t;

    -- ÄÄ JSON: resumen mensual ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
    SELECT json_agg(t ORDER BY t.period_label) INTO v_monthly_json FROM (
        SELECT
            TO_CHAR(applied_date, 'YYYY-MM')    AS period_label,
            COUNT(*)                             AS doses_applied,
            COUNT(DISTINCT patient_id)           AS unique_patients
        FROM vaccination_records
        WHERE applied_date BETWEEN p_from AND p_to
        GROUP BY TO_CHAR(applied_date, 'YYYY-MM')
    ) t;

    -- ÄÄ JSON: zonas (municipios) ÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄÄ
    SELECT json_agg(t ORDER BY t.doses_applied DESC) INTO v_zones_json FROM (
        SELECT
            m.name                              AS zone_name,
            COUNT(vr.record_id)                 AS doses_applied,
            COUNT(DISTINCT vr.patient_id)       AS unique_patients,
            CASE
                WHEN COUNT(DISTINCT vr.patient_id) >= 100 THEN 'low'
                WHEN COUNT(DISTINCT vr.patient_id) >= 30  THEN 'medium'
                ELSE 'high'
            END                                 AS risk_level,
            CASE
                WHEN COUNT(DISTINCT vr.patient_id) >= 100 THEN 'Bajo'
                WHEN COUNT(DISTINCT vr.patient_id) >= 30  THEN 'Medio'
                ELSE 'Alto'
            END                                 AS risk_label
        FROM vaccination_records vr
        JOIN clinics c         ON vr.clinic_id      = c.clinic_id
        JOIN addresses a       ON c.address_id       = a.address_id
        JOIN neighborhoods n   ON a.neighborhood_id  = n.neighborhood_id
        JOIN municipalities m  ON n.municipality_id  = m.municipality_id
        WHERE vr.applied_date BETWEEN p_from AND p_to
        GROUP BY m.municipality_id, m.name
    ) t;

    OPEN p_results FOR SELECT
        v_total_doses                           AS total_doses_applied,
        v_target                                AS target_population,
        v_reached                               AS reached_population,
        v_coverage                              AS coverage_percent,
        COALESCE(v_avg_delay, 0.0)              AS avg_delay_days,
        v_active_zones                          AS active_zones,
        v_reaction_rate                         AS reaction_rate,
        v_completed_scheme                      AS completed_scheme,
        v_delayed_patients                      AS delayed_patients,
        v_appt_rate                             AS appointment_completion_rate,
        v_low_stock                             AS low_stock_count,
        v_new_patients                          AS new_patients,
        v_active_workers                        AS active_workers,
        v_avg_temp                              AS avg_temp_c,
        COALESCE(v_vaccines_json, '[]'::JSON)   AS vaccines,
        COALESCE(v_monthly_json,  '[]'::JSON)   AS monthly,
        COALESCE(v_zones_json,    '[]'::JSON)   AS zones;

END;
$$;


ALTER PROCEDURE public.sp_reportes_resumen(IN p_from date, IN p_to date, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_reschedule_appointment(integer, timestamp without time zone, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_reschedule_appointment(IN p_appointment_id integer, IN p_new_datetime timestamp without time zone, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_schedule_id INT;
    v_clinic_id INT;
    v_new_appointment_id INT;
BEGIN

    SELECT
        patient_schedule_id,
        clinic_id
    INTO
        v_schedule_id,
        v_clinic_id
    FROM appointments
    WHERE appointment_id = p_appointment_id;

    UPDATE appointments
    SET
        appointment_status = 'Reagendada',
        appointment_notes =
            COALESCE(appointment_notes || E'\n', '')
            || '[' || CURRENT_DATE || '] Reagendada.'
    WHERE appointment_id = p_appointment_id;

    INSERT INTO appointments (
        patient_schedule_id,
        clinic_id,
        scheduled_at,
        appointment_status,
        rescheduled_from_id,
        created_at
    )
    VALUES (
        v_schedule_id,
        v_clinic_id,
        p_new_datetime,
        'Pendiente confirmaci¢n',
        p_appointment_id,
        CURRENT_TIMESTAMP
    )
    RETURNING appointment_id
    INTO v_new_appointment_id;

    OPEN p_results FOR
    SELECT
        appointment_id,
        patient_schedule_id,
        clinic_id,
        scheduled_at,
        appointment_status,
        rescheduled_from_id,
        appointment_notes
    FROM appointments
    WHERE appointment_id = v_new_appointment_id;

END;
$$;


ALTER PROCEDURE public.sp_reschedule_appointment(IN p_appointment_id integer, IN p_new_datetime timestamp without time zone, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_tutor_register_child(integer, character varying, character varying, date, character, character varying, integer, numeric, boolean, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_tutor_register_child(IN p_guardian_id integer, IN p_first_name character varying, IN p_last_name character varying, IN p_birth_date date, IN p_gender character, IN p_curp character varying, IN p_blood_type_id integer, IN p_weight_kg numeric, IN p_premature boolean, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_patient_id INT;
    v_age_years  INT;
BEGIN
    -- Validaciones de negocio (paralelas a sp_register_patient)
    IF p_first_name IS NULL OR TRIM(p_first_name) = '' THEN
        RAISE EXCEPTION 'El nombre es obligatorio';
    END IF;
    IF p_last_name IS NULL OR TRIM(p_last_name) = '' THEN
        RAISE EXCEPTION 'El apellido es obligatorio';
    END IF;
    IF p_birth_date IS NULL OR p_birth_date > CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha de nacimiento no puede ser futura';
    END IF;
    v_age_years := DATE_PART('year', AGE(CURRENT_DATE, p_birth_date));
    IF v_age_years > 15 THEN
        RAISE EXCEPTION 'El paciente excede la edad pedi trica permitida';
    END IF;
    IF p_gender NOT IN ('M', 'F') THEN
        RAISE EXCEPTION 'El g‚nero debe ser M o F';
    END IF;
    IF p_curp IS NOT NULL AND TRIM(p_curp) <> '' AND EXISTS (
        SELECT 1 FROM patients WHERE curp = UPPER(TRIM(p_curp))
    ) THEN
        RAISE EXCEPTION 'Ya existe un paciente registrado con esa CURP';
    END IF;
    IF p_weight_kg IS NOT NULL AND (p_weight_kg <= 0 OR p_weight_kg > 80) THEN
        RAISE EXCEPTION 'Peso fuera de rango pedi trico';
    END IF;
    IF p_blood_type_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM blood_types WHERE blood_type_id = p_blood_type_id
    ) THEN
        RAISE EXCEPTION 'Tipo sangu¡neo inexistente';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM guardians WHERE guardian_id = p_guardian_id) THEN
        RAISE EXCEPTION 'Tutor no encontrado';
    END IF;

    -- Insertar paciente (trigger genera esquema de vacunaci¢n autom ticamente)
    INSERT INTO patients (
        first_name, last_name, curp, birth_date, gender,
        blood_type_id, weight_kg, premature, is_active, created_at
    )
    VALUES (
        TRIM(p_first_name),
        TRIM(p_last_name),
        NULLIF(UPPER(TRIM(COALESCE(p_curp, ''))), ''),
        p_birth_date,
        p_gender,
        p_blood_type_id,
        p_weight_kg,
        COALESCE(p_premature, FALSE),
        TRUE,
        NOW()
    )
    RETURNING patient_id INTO v_patient_id;

    -- Vincular paciente con el tutor
    INSERT INTO patient_guardian_relations (patient_id, guardian_id, relation_type, is_primary, has_custody)
    VALUES (v_patient_id, p_guardian_id, 'Tutor', TRUE, TRUE)
    ON CONFLICT DO NOTHING;

    OPEN p_results FOR
    SELECT TRUE  AS success,
           'Paciente registrado correctamente' AS message,
           v_patient_id AS patient_id;

EXCEPTION
WHEN OTHERS THEN
    OPEN p_results FOR
    SELECT FALSE AS success, SQLERRM AS message, NULL::INT AS patient_id;
END;
$$;


ALTER PROCEDURE public.sp_tutor_register_child(IN p_guardian_id integer, IN p_first_name character varying, IN p_last_name character varying, IN p_birth_date date, IN p_gender character, IN p_curp character varying, IN p_blood_type_id integer, IN p_weight_kg numeric, IN p_premature boolean, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_update_appointment(integer, integer, integer, timestamp without time zone, text, text, character varying, smallint, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_update_appointment(IN p_appointment_id integer, IN p_worker_id integer, IN p_area_id integer, IN p_scheduled_at timestamp without time zone, IN p_reason text, IN p_notes text, IN p_status character varying, IN p_duration_min smallint, INOUT p_result refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_clinic_id INT;
BEGIN
    -- Verificar que la cita existe y obtener su clinica
    SELECT clinic_id INTO v_clinic_id
    FROM   appointments
    WHERE  appointment_id = p_appointment_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Cita no encontrada (id=%)', p_appointment_id;
    END IF;

    -- Verificar solapamiento del trabajador (excluye la cita que se esta editando)
    IF p_worker_id IS NOT NULL AND p_scheduled_at IS NOT NULL THEN
        IF EXISTS (
            SELECT 1 FROM appointments a
            WHERE  a.worker_id           = p_worker_id
              AND  a.appointment_id     <> p_appointment_id
              AND  a.appointment_status NOT IN ('Cancelada', 'No Show', 'Reagendada')
              AND  a.scheduled_at < p_scheduled_at + (COALESCE(p_duration_min, 20) * INTERVAL '1 minute')
              AND  a.scheduled_at + (a.duration_min * INTERVAL '1 minute') > p_scheduled_at
        ) THEN
            RAISE EXCEPTION 'El trabajador ya tiene una cita que se solapa en ese horario';
        END IF;
    END IF;

    -- Actualizar solo los campos editables
    -- area_id puede ser NULL (sin area), por eso no usa COALESCE
    UPDATE appointments SET
        worker_id          = COALESCE(p_worker_id,    worker_id),
        area_id            = p_area_id,
        scheduled_at       = COALESCE(p_scheduled_at, scheduled_at),
        reason             = COALESCE(p_reason,       reason),
        appointment_notes  = p_notes,
        appointment_status = COALESCE(p_status,       appointment_status),
        duration_min       = COALESCE(p_duration_min, duration_min)
    WHERE appointment_id = p_appointment_id;

    OPEN p_result FOR
        SELECT TRUE             AS success,
               p_appointment_id AS appointment_id,
               'Cita actualizada correctamente' AS message;

EXCEPTION WHEN OTHERS THEN
    OPEN p_result FOR
        SELECT FALSE AS success,
               SQLERRM AS message,
               NULL::INT AS appointment_id;
END;
$$;


ALTER PROCEDURE public.sp_update_appointment(IN p_appointment_id integer, IN p_worker_id integer, IN p_area_id integer, IN p_scheduled_at timestamp without time zone, IN p_reason text, IN p_notes text, IN p_status character varying, IN p_duration_min smallint, INOUT p_result refcursor) OWNER TO postgres;

--
-- Name: sp_update_lot_status(integer, character varying, integer, text, refcursor); Type: PROCEDURE; Schema: public; Owner: vaccine_user
--

CREATE PROCEDURE public.sp_update_lot_status(IN p_lot_id integer, IN p_new_status character varying, IN p_worker_id integer, IN p_reason text, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_old_status VARCHAR(30);
BEGIN
    SELECT lot_status INTO v_old_status
    FROM vaccine_lots WHERE lot_id = p_lot_id FOR UPDATE;

    IF NOT FOUND THEN
        OPEN p_results FOR SELECT FALSE AS success, 'Lote no encontrado.' AS message;
        RETURN;
    END IF;

    IF v_old_status = p_new_status THEN
        OPEN p_results FOR SELECT FALSE AS success,
            'El lote ya tiene ese estado.' AS message;
        RETURN;
    END IF;

    UPDATE vaccine_lots SET lot_status = p_new_status WHERE lot_id = p_lot_id;

    INSERT INTO audit_log (table_name, record_id, action, worker_id, changed_data)
    VALUES ('vaccine_lots', p_lot_id, 'UPDATE', p_worker_id,
            jsonb_build_object('from_status', v_old_status,
                               'to_status',   p_new_status,
                               'reason',      p_reason));

    OPEN p_results FOR SELECT TRUE AS success,
        'Estado actualizado a ' || p_new_status || '.' AS message;
END;
$$;


ALTER PROCEDURE public.sp_update_lot_status(IN p_lot_id integer, IN p_new_status character varying, IN p_worker_id integer, IN p_reason text, INOUT p_results refcursor) OWNER TO vaccine_user;

--
-- Name: sp_update_nfc_card_status(integer, character varying, integer, text, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_update_nfc_card_status(IN p_nfc_card_id integer, IN p_new_status character varying, IN p_worker_id integer, IN p_notes text, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_current_status VARCHAR;
    v_patient_id     INT;
BEGIN
    SELECT status, patient_id
    INTO   v_current_status, v_patient_id
    FROM   nfc_cards
    WHERE  nfc_card_id = p_nfc_card_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Tarjeta NFC % no encontrada', p_nfc_card_id;
    END IF;

    IF p_new_status NOT IN ('Activa', 'Inactiva', 'Perdida', 'Robada') THEN
        RAISE EXCEPTION 'Estado invalido: %. Valores permitidos: Activa, Inactiva, Perdida, Robada', p_new_status;
    END IF;

    -- Regla clinica: tarjeta Perdida o Robada no puede reactivarse directamente
    IF v_current_status IN ('Perdida', 'Robada') AND p_new_status = 'Activa' THEN
        RAISE EXCEPTION 'Una tarjeta % no puede reactivarse directamente. Asigna una nueva al paciente.', v_current_status;
    END IF;

    -- Si se activa, verificar que no haya otra activa para el mismo paciente
    IF p_new_status = 'Activa' AND EXISTS (
        SELECT 1 FROM nfc_cards
        WHERE  patient_id  = v_patient_id
          AND  status      = 'Activa'
          AND  nfc_card_id <> p_nfc_card_id
    ) THEN
        RAISE EXCEPTION 'El paciente ya tiene otra tarjeta NFC activa';
    END IF;

    UPDATE nfc_cards
    SET
        status         = p_new_status,
        nfc_card_notes = CASE
                            WHEN p_notes IS NOT NULL AND TRIM(p_notes) <> ''
                            THEN COALESCE(nfc_card_notes || ' | ', '') ||
                                 TO_CHAR(CURRENT_DATE, 'YYYY-MM-DD') || ': ' || TRIM(p_notes)
                            ELSE nfc_card_notes
                         END
    WHERE nfc_card_id = p_nfc_card_id;

    OPEN p_results FOR
        SELECT TRUE          AS success,
               'Estado actualizado a ' || p_new_status AS message,
               p_nfc_card_id AS nfc_card_id,
               p_new_status  AS new_status,
               v_patient_id  AS patient_id;

EXCEPTION WHEN OTHERS THEN
    OPEN p_results FOR
        SELECT FALSE AS success, SQLERRM AS message,
               p_nfc_card_id AS nfc_card_id,
               NULL::VARCHAR AS new_status,
               NULL::INT     AS patient_id;
END;
$$;


ALTER PROCEDURE public.sp_update_nfc_card_status(IN p_nfc_card_id integer, IN p_new_status character varying, IN p_worker_id integer, IN p_notes text, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_update_patient(integer, character varying, character varying, character varying, date, integer, numeric, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_update_patient(IN p_patient_id integer, IN p_first_name character varying, IN p_last_name character varying, IN p_curp character varying, IN p_birth_date date, IN p_blood_type_id integer, IN p_weight_kg numeric, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_exists BOOLEAN;
BEGIN

    SELECT EXISTS(
        SELECT 1 FROM patients
        WHERE patient_id = p_patient_id AND is_active = TRUE
    ) INTO v_exists;

    IF NOT v_exists THEN
        RAISE EXCEPTION 'El paciente no existe o esta inactivo';
    END IF;

    IF p_first_name IS NOT NULL AND LENGTH(TRIM(p_first_name)) < 2 THEN
        RAISE EXCEPTION 'Nombre invalido';
    END IF;

    IF p_last_name IS NOT NULL AND LENGTH(TRIM(p_last_name)) < 2 THEN
        RAISE EXCEPTION 'Apellido invalido';
    END IF;

    IF p_curp IS NOT NULL AND TRIM(p_curp) <> '' THEN
        IF LENGTH(TRIM(p_curp)) <> 18 THEN
            RAISE EXCEPTION 'CURP invalida';
        END IF;
        IF EXISTS (
            SELECT 1 FROM patients
            WHERE curp = TRIM(p_curp) AND patient_id <> p_patient_id
        ) THEN
            RAISE EXCEPTION 'El CURP ingresado ya esta registrado';
        END IF;
    END IF;

    IF p_birth_date IS NOT NULL AND p_birth_date > CURRENT_DATE THEN
        RAISE EXCEPTION 'La fecha de nacimiento no puede ser futura';
    END IF;

    IF p_weight_kg IS NOT NULL AND (p_weight_kg <= 0 OR p_weight_kg > 80) THEN
        RAISE EXCEPTION 'Peso fuera de rango pediatrico';
    END IF;

    IF p_blood_type_id IS NOT NULL THEN
        IF NOT EXISTS (SELECT 1 FROM blood_types WHERE blood_type_id = p_blood_type_id) THEN
            RAISE EXCEPTION 'Tipo sanguineo inexistente';
        END IF;
    END IF;

    UPDATE patients
    SET
        first_name    = COALESCE(NULLIF(TRIM(p_first_name), ''), first_name),
        last_name     = COALESCE(NULLIF(TRIM(p_last_name),  ''), last_name),
        curp          = COALESCE(NULLIF(TRIM(p_curp),       ''), curp),
        birth_date    = COALESCE(p_birth_date,    birth_date),
        blood_type_id = COALESCE(p_blood_type_id, blood_type_id),
        weight_kg     = COALESCE(p_weight_kg,     weight_kg),
        updated_at    = NOW()
    WHERE patient_id = p_patient_id;

    OPEN p_results FOR
    SELECT TRUE AS success, 'Paciente actualizado correctamente' AS message, p_patient_id AS patient_id;

EXCEPTION WHEN OTHERS THEN
    OPEN p_results FOR
    SELECT FALSE AS success, SQLERRM AS message, NULL::INT AS patient_id;
END;
$$;


ALTER PROCEDURE public.sp_update_patient(IN p_patient_id integer, IN p_first_name character varying, IN p_last_name character varying, IN p_curp character varying, IN p_birth_date date, IN p_blood_type_id integer, IN p_weight_kg numeric, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_update_vaccine_lot_stock(integer, integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_update_vaccine_lot_stock(IN p_lot_id integer, IN p_quantity_available integer, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE vaccine_lots SET
        quantity_available = p_quantity_available
    WHERE lot_id = p_lot_id;

    OPEN p_results FOR
        SELECT FOUND AS success;
END;
$$;


ALTER PROCEDURE public.sp_update_vaccine_lot_stock(IN p_lot_id integer, IN p_quantity_available integer, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_update_worker(integer, character varying, character varying, integer, character varying, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_update_worker(IN p_worker_id integer, IN p_first_name character varying, IN p_last_name character varying, IN p_role_id integer, IN p_email character varying, INOUT p_results refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM workers WHERE worker_id = p_worker_id) THEN
        RAISE EXCEPTION 'Trabajador % no encontrado', p_worker_id;
    END IF;

    UPDATE workers
    SET first_name = COALESCE(NULLIF(TRIM(p_first_name), ''), first_name),
        last_name  = COALESCE(NULLIF(TRIM(p_last_name),  ''), last_name),
        role_id    = COALESCE(p_role_id, role_id)
    WHERE worker_id = p_worker_id;

    IF p_email IS NOT NULL AND TRIM(p_email) <> '' THEN
        UPDATE worker_emails
        SET email = p_email
        WHERE worker_id = p_worker_id AND is_primary = TRUE;

        IF NOT FOUND THEN
            INSERT INTO worker_emails (worker_id, email, is_primary)
            VALUES (p_worker_id, p_email, TRUE);
        END IF;
    END IF;

    OPEN p_results FOR
        SELECT TRUE AS success, 'Trabajador actualizado' AS message, p_worker_id AS worker_id;
EXCEPTION
WHEN OTHERS THEN
    OPEN p_results FOR
        SELECT FALSE AS success, SQLERRM AS message, NULL::INT AS worker_id;
END;
$$;


ALTER PROCEDURE public.sp_update_worker(IN p_worker_id integer, IN p_first_name character varying, IN p_last_name character varying, IN p_role_id integer, IN p_email character varying, INOUT p_results refcursor) OWNER TO postgres;

--
-- Name: sp_visit_patient_summary(integer, refcursor); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_visit_patient_summary(IN p_visit_id integer, INOUT p_result refcursor)
    LANGUAGE plpgsql
    AS $$
BEGIN
    OPEN p_result FOR
        SELECT
            pcv.visit_id,
            pcv.visit_status::TEXT,
            pcv.checked_in_at,
            pcv.waiting_since,
            pcv.consultation_start,
            pcv.vaccination_start,
            pcv.appointment_id,
            p.patient_id,
            TRIM(p.first_name || ' ' || p.last_name)                AS full_name,
            p.birth_date,
            DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT AS age,
            p.gender,
            p.weight_kg,
            p.photo,
            p.premature,
            COALESCE(bt.blood_type, '-')                            AS blood_type,
            -- Alergias detalladas
            COALESCE(
                (SELECT STRING_AGG(
                    al.name || ' - ' || COALESCE(pa.severity,'?') ||
                    COALESCE(' (' || pa.reaction_desc || ')',''), ' | '
                )
                 FROM   patient_allergies pa
                 JOIN   allergies al ON al.allergy_id = pa.allergy_id
                 WHERE  pa.patient_id = p.patient_id),
                'Sin alergias registradas'
            )                                                        AS allergies,
            -- Conteos de esquema de vacunaci¢n
            (SELECT COUNT(*) FROM patient_vaccine_schedule pvs
             WHERE pvs.patient_id = p.patient_id AND pvs.status = 'Pendiente')::INT AS pending_doses,
            (SELECT COUNT(*) FROM patient_vaccine_schedule pvs
             WHERE pvs.patient_id = p.patient_id AND pvs.status = 'Atrasada')::INT  AS overdue_doses,
            (SELECT COUNT(*) FROM patient_vaccine_schedule pvs
             WHERE pvs.patient_id = p.patient_id AND pvs.status = 'Aplicada')::INT  AS applied_doses,
            -- éltima vacuna
            (SELECT MAX(vr.applied_date) FROM vaccination_records vr
             WHERE vr.patient_id = p.patient_id)                    AS last_vaccine_date,
            -- Datos de la cita vinculada
            a.scheduled_at,
            a.reason AS appointment_reason,
            a.appointment_notes,
            -- Tutor principal
            COALESCE(TRIM(g.first_name || ' ' || g.last_name), 'Sin tutor') AS guardian_name,
            COALESCE(
                (SELECT gp.phone FROM guardian_phones gp
                 WHERE gp.guardian_id = g.guardian_id
                 ORDER BY gp.is_primary DESC LIMIT 1),
                '-'
            )                                                        AS guardian_phone
        FROM   patient_clinic_visits pcv
        JOIN   patients p   ON p.patient_id    = pcv.patient_id
        LEFT   JOIN blood_types bt ON bt.blood_type_id = p.blood_type_id
        LEFT   JOIN appointments a ON a.appointment_id = pcv.appointment_id
        LEFT   JOIN LATERAL (
            SELECT pgr.guardian_id FROM patient_guardian_relations pgr
            WHERE  pgr.patient_id = p.patient_id
            ORDER  BY pgr.is_primary DESC LIMIT 1
        ) rel ON TRUE
        LEFT   JOIN guardians g ON g.guardian_id = rel.guardian_id
        WHERE  pcv.visit_id = p_visit_id;
END;
$$;


ALTER PROCEDURE public.sp_visit_patient_summary(IN p_visit_id integer, INOUT p_result refcursor) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: addresses; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.addresses (
    address_id integer NOT NULL,
    neighborhood_id integer NOT NULL,
    street character varying(200) NOT NULL,
    ext_number character varying(20),
    cross_street_1 character varying(200),
    latitude numeric(9,4),
    longitude numeric(9,4)
);


ALTER TABLE public.addresses OWNER TO vaccine_user;

--
-- Name: addresses_address_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.addresses_address_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.addresses_address_id_seq OWNER TO vaccine_user;

--
-- Name: addresses_address_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.addresses_address_id_seq OWNED BY public.addresses.address_id;


--
-- Name: allergies; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.allergies (
    allergy_id integer NOT NULL,
    name character varying(100) NOT NULL,
    allergy_type character varying(50)
);


ALTER TABLE public.allergies OWNER TO vaccine_user;

--
-- Name: allergies_allergy_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.allergies_allergy_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.allergies_allergy_id_seq OWNER TO vaccine_user;

--
-- Name: allergies_allergy_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.allergies_allergy_id_seq OWNED BY public.allergies.allergy_id;


--
-- Name: application_sites; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.application_sites (
    application_site_id integer NOT NULL,
    application_site character varying(50) NOT NULL
);


ALTER TABLE public.application_sites OWNER TO vaccine_user;

--
-- Name: application_sites_application_site_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.application_sites_application_site_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.application_sites_application_site_id_seq OWNER TO vaccine_user;

--
-- Name: application_sites_application_site_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.application_sites_application_site_id_seq OWNED BY public.application_sites.application_site_id;


--
-- Name: appointments; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.appointments (
    appointment_id integer NOT NULL,
    clinic_id integer NOT NULL,
    area_id integer,
    worker_id integer,
    scheduled_at timestamp without time zone NOT NULL,
    duration_min smallint,
    reason text,
    appointment_status character varying(50),
    appointment_notes text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    patient_schedule_id integer,
    confirmed_at timestamp without time zone,
    cancel_reason text,
    rescheduled_from_id integer,
    created_by_role character varying(20),
    created_by_worker_id integer,
    created_by_guardian_id integer,
    patient_id integer NOT NULL,
    CONSTRAINT appointments_appointment_status_check CHECK (((appointment_status)::text = ANY ((ARRAY['Pendiente confirmaci¢n'::character varying, 'Confirmada'::character varying, 'Programada'::character varying, 'Reagendada'::character varying, 'Completada'::character varying, 'Cancelada'::character varying, 'No Show'::character varying])::text[])))
);


ALTER TABLE public.appointments OWNER TO vaccine_user;

--
-- Name: appointments_appointment_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.appointments_appointment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.appointments_appointment_id_seq OWNER TO vaccine_user;

--
-- Name: appointments_appointment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.appointments_appointment_id_seq OWNED BY public.appointments.appointment_id;


--
-- Name: area_equipment; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.area_equipment (
    area_equipment_id integer NOT NULL,
    area_id integer NOT NULL,
    equipment_id integer NOT NULL,
    quantity smallint DEFAULT 1 NOT NULL,
    serial_number character varying(50),
    condition character varying(50)
);


ALTER TABLE public.area_equipment OWNER TO vaccine_user;

--
-- Name: area_equipment_area_equipment_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.area_equipment_area_equipment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.area_equipment_area_equipment_id_seq OWNER TO vaccine_user;

--
-- Name: area_equipment_area_equipment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.area_equipment_area_equipment_id_seq OWNED BY public.area_equipment.area_equipment_id;


--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.audit_log (
    audit_id integer NOT NULL,
    table_name character varying(100) NOT NULL,
    record_id integer NOT NULL,
    action character varying(20) NOT NULL,
    worker_id integer,
    changed_at timestamp without time zone DEFAULT now() NOT NULL,
    ip_address character varying(45),
    CONSTRAINT audit_log_action_check CHECK (((action)::text = ANY ((ARRAY['INSERT'::character varying, 'UPDATE'::character varying, 'DELETE'::character varying])::text[])))
);


ALTER TABLE public.audit_log OWNER TO vaccine_user;

--
-- Name: audit_log_audit_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.audit_log_audit_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.audit_log_audit_id_seq OWNER TO vaccine_user;

--
-- Name: audit_log_audit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.audit_log_audit_id_seq OWNED BY public.audit_log.audit_id;


--
-- Name: blood_types; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.blood_types (
    blood_type_id integer NOT NULL,
    blood_type character varying(5) NOT NULL
);


ALTER TABLE public.blood_types OWNER TO vaccine_user;

--
-- Name: blood_types_blood_type_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.blood_types_blood_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.blood_types_blood_type_id_seq OWNER TO vaccine_user;

--
-- Name: blood_types_blood_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.blood_types_blood_type_id_seq OWNED BY public.blood_types.blood_type_id;


--
-- Name: clinic_area_types; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.clinic_area_types (
    area_type_id integer NOT NULL,
    area_type character varying(50) NOT NULL,
    code character varying(20) NOT NULL
);


ALTER TABLE public.clinic_area_types OWNER TO vaccine_user;

--
-- Name: clinic_area_types_area_type_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.clinic_area_types_area_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.clinic_area_types_area_type_id_seq OWNER TO vaccine_user;

--
-- Name: clinic_area_types_area_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.clinic_area_types_area_type_id_seq OWNED BY public.clinic_area_types.area_type_id;


--
-- Name: clinic_areas; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.clinic_areas (
    area_id integer NOT NULL,
    clinic_id integer NOT NULL,
    name character varying(200) NOT NULL,
    area_type_id integer NOT NULL,
    floor smallint,
    capacity smallint,
    code character varying(20)
);


ALTER TABLE public.clinic_areas OWNER TO vaccine_user;

--
-- Name: clinic_areas_area_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.clinic_areas_area_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.clinic_areas_area_id_seq OWNER TO vaccine_user;

--
-- Name: clinic_areas_area_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.clinic_areas_area_id_seq OWNED BY public.clinic_areas.area_id;


--
-- Name: clinic_inventory; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.clinic_inventory (
    inventory_id integer NOT NULL,
    clinic_id integer NOT NULL,
    supply_id integer NOT NULL,
    quantity integer DEFAULT 0 NOT NULL,
    min_stock integer DEFAULT 0 NOT NULL,
    last_updated date
);


ALTER TABLE public.clinic_inventory OWNER TO vaccine_user;

--
-- Name: clinic_inventory_inventory_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.clinic_inventory_inventory_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.clinic_inventory_inventory_id_seq OWNER TO vaccine_user;

--
-- Name: clinic_inventory_inventory_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.clinic_inventory_inventory_id_seq OWNED BY public.clinic_inventory.inventory_id;


--
-- Name: clinics; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.clinics (
    clinic_id integer NOT NULL,
    name character varying(200) NOT NULL,
    address_id integer NOT NULL,
    phone character varying(20),
    institution_type character varying(50),
    is_active boolean DEFAULT true NOT NULL
);


ALTER TABLE public.clinics OWNER TO vaccine_user;

--
-- Name: clinics_clinic_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.clinics_clinic_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.clinics_clinic_id_seq OWNER TO vaccine_user;

--
-- Name: clinics_clinic_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.clinics_clinic_id_seq OWNED BY public.clinics.clinic_id;


--
-- Name: countries; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.countries (
    country_id integer NOT NULL,
    name character varying(100) NOT NULL,
    iso_code character(2) NOT NULL
);


ALTER TABLE public.countries OWNER TO vaccine_user;

--
-- Name: countries_country_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.countries_country_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.countries_country_id_seq OWNER TO vaccine_user;

--
-- Name: countries_country_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.countries_country_id_seq OWNED BY public.countries.country_id;


--
-- Name: equipment_catalog; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.equipment_catalog (
    equipment_id integer NOT NULL,
    name character varying(200) NOT NULL,
    category character varying(100),
    requires_calibration boolean DEFAULT false NOT NULL
);


ALTER TABLE public.equipment_catalog OWNER TO vaccine_user;

--
-- Name: equipment_catalog_equipment_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.equipment_catalog_equipment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.equipment_catalog_equipment_id_seq OWNER TO vaccine_user;

--
-- Name: equipment_catalog_equipment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.equipment_catalog_equipment_id_seq OWNED BY public.equipment_catalog.equipment_id;


--
-- Name: guardian_accounts; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.guardian_accounts (
    guardian_account_id integer NOT NULL,
    guardian_id integer NOT NULL,
    email character varying(120) NOT NULL,
    password_hash character varying(255) NOT NULL,
    is_active boolean DEFAULT true,
    email_verified boolean DEFAULT false,
    last_login timestamp without time zone,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.guardian_accounts OWNER TO vaccine_user;

--
-- Name: guardian_accounts_guardian_account_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.guardian_accounts_guardian_account_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.guardian_accounts_guardian_account_id_seq OWNER TO vaccine_user;

--
-- Name: guardian_accounts_guardian_account_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.guardian_accounts_guardian_account_id_seq OWNED BY public.guardian_accounts.guardian_account_id;


--
-- Name: guardian_emails; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.guardian_emails (
    email_id integer NOT NULL,
    guardian_id integer NOT NULL,
    email character varying(150) NOT NULL,
    is_primary boolean DEFAULT false NOT NULL
);


ALTER TABLE public.guardian_emails OWNER TO vaccine_user;

--
-- Name: guardian_emails_email_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.guardian_emails_email_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.guardian_emails_email_id_seq OWNER TO vaccine_user;

--
-- Name: guardian_emails_email_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.guardian_emails_email_id_seq OWNED BY public.guardian_emails.email_id;


--
-- Name: guardian_phones; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.guardian_phones (
    phone_id integer NOT NULL,
    guardian_id integer NOT NULL,
    phone character varying(20) NOT NULL,
    phone_type character varying(30),
    is_primary boolean DEFAULT false NOT NULL
);


ALTER TABLE public.guardian_phones OWNER TO vaccine_user;

--
-- Name: guardian_phones_phone_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.guardian_phones_phone_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.guardian_phones_phone_id_seq OWNER TO vaccine_user;

--
-- Name: guardian_phones_phone_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.guardian_phones_phone_id_seq OWNED BY public.guardian_phones.phone_id;


--
-- Name: guardians; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.guardians (
    guardian_id integer NOT NULL,
    first_name character varying(100) NOT NULL,
    last_name character varying(100) NOT NULL,
    curp character(18),
    address_id integer,
    marital_status_id integer,
    occupation integer
);


ALTER TABLE public.guardians OWNER TO vaccine_user;

--
-- Name: guardians_guardian_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.guardians_guardian_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.guardians_guardian_id_seq OWNER TO vaccine_user;

--
-- Name: guardians_guardian_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.guardians_guardian_id_seq OWNED BY public.guardians.guardian_id;


--
-- Name: institutions; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.institutions (
    institution_id integer NOT NULL,
    institution_name character varying(200) NOT NULL,
    address_id integer
);


ALTER TABLE public.institutions OWNER TO vaccine_user;

--
-- Name: institutions_institution_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.institutions_institution_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.institutions_institution_id_seq OWNER TO vaccine_user;

--
-- Name: institutions_institution_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.institutions_institution_id_seq OWNED BY public.institutions.institution_id;


--
-- Name: inventory_movements; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.inventory_movements (
    movement_id integer NOT NULL,
    lot_id integer NOT NULL,
    vaccine_id integer NOT NULL,
    clinic_id integer NOT NULL,
    worker_id integer,
    movement_type character varying(30) NOT NULL,
    quantity integer NOT NULL,
    quantity_before integer NOT NULL,
    quantity_after integer NOT NULL,
    reference_id integer,
    reference_type character varying(30),
    reason text,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT inventory_movements_movement_type_check CHECK (((movement_type)::text = ANY ((ARRAY['Entrada'::character varying, 'Salida_Aplicacion'::character varying, 'Salida_Merma'::character varying, 'Salida_Caducidad'::character varying, 'Ajuste_Positivo'::character varying, 'Ajuste_Negativo'::character varying, 'Transferencia_Salida'::character varying, 'Transferencia_Entrada'::character varying])::text[]))),
    CONSTRAINT inventory_movements_quantity_check CHECK ((quantity > 0)),
    CONSTRAINT inventory_movements_reference_type_check CHECK (((reference_type)::text = ANY ((ARRAY['vaccination_record'::character varying, 'transfer'::character varying, 'manual'::character varying])::text[])))
);


ALTER TABLE public.inventory_movements OWNER TO vaccine_user;

--
-- Name: inventory_movements_movement_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.inventory_movements_movement_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.inventory_movements_movement_id_seq OWNER TO vaccine_user;

--
-- Name: inventory_movements_movement_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.inventory_movements_movement_id_seq OWNED BY public.inventory_movements.movement_id;


--
-- Name: inventory_transfers; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.inventory_transfers (
    transfer_id integer NOT NULL,
    lot_id integer NOT NULL,
    vaccine_id integer NOT NULL,
    from_clinic_id integer NOT NULL,
    to_clinic_id integer NOT NULL,
    quantity integer NOT NULL,
    transfer_status character varying(20) DEFAULT 'Pendiente'::character varying NOT NULL,
    requested_by integer NOT NULL,
    approved_by integer,
    reason text,
    notes text,
    requested_at timestamp without time zone DEFAULT now() NOT NULL,
    resolved_at timestamp without time zone,
    CONSTRAINT chk_transfer_different_clinics CHECK ((from_clinic_id <> to_clinic_id)),
    CONSTRAINT inventory_transfers_quantity_check CHECK ((quantity > 0)),
    CONSTRAINT inventory_transfers_transfer_status_check CHECK (((transfer_status)::text = ANY ((ARRAY['Pendiente'::character varying, 'En_Transito'::character varying, 'Recibido'::character varying, 'Cancelado'::character varying, 'Rechazado'::character varying])::text[])))
);


ALTER TABLE public.inventory_transfers OWNER TO postgres;

--
-- Name: inventory_transfers_transfer_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.inventory_transfers_transfer_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.inventory_transfers_transfer_id_seq OWNER TO postgres;

--
-- Name: inventory_transfers_transfer_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.inventory_transfers_transfer_id_seq OWNED BY public.inventory_transfers.transfer_id;


--
-- Name: manufacturers; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.manufacturers (
    manufacturer_id integer NOT NULL,
    name character varying(200) NOT NULL,
    country_id integer,
    contact_email character varying(150)
);


ALTER TABLE public.manufacturers OWNER TO vaccine_user;

--
-- Name: manufacturers_manufacturer_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.manufacturers_manufacturer_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.manufacturers_manufacturer_id_seq OWNER TO vaccine_user;

--
-- Name: manufacturers_manufacturer_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.manufacturers_manufacturer_id_seq OWNED BY public.manufacturers.manufacturer_id;


--
-- Name: marital_status; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.marital_status (
    marital_status_id integer NOT NULL,
    marital_status character varying(50) NOT NULL,
    CONSTRAINT marital_status_marital_status_check CHECK (((marital_status)::text = ANY ((ARRAY['Soltero'::character varying, 'Casado'::character varying, 'Divorciado'::character varying, 'Viudo'::character varying])::text[])))
);


ALTER TABLE public.marital_status OWNER TO vaccine_user;

--
-- Name: marital_status_marital_status_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.marital_status_marital_status_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.marital_status_marital_status_id_seq OWNER TO vaccine_user;

--
-- Name: marital_status_marital_status_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.marital_status_marital_status_id_seq OWNED BY public.marital_status.marital_status_id;


--
-- Name: municipalities; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.municipalities (
    municipality_id integer NOT NULL,
    state_id integer NOT NULL,
    name character varying(100) NOT NULL
);


ALTER TABLE public.municipalities OWNER TO vaccine_user;

--
-- Name: municipalities_municipality_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.municipalities_municipality_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.municipalities_municipality_id_seq OWNER TO vaccine_user;

--
-- Name: municipalities_municipality_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.municipalities_municipality_id_seq OWNED BY public.municipalities.municipality_id;


--
-- Name: neighborhoods; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.neighborhoods (
    neighborhood_id integer NOT NULL,
    municipality_id integer NOT NULL,
    name character varying(100) NOT NULL,
    zip_code character varying(10)
);


ALTER TABLE public.neighborhoods OWNER TO vaccine_user;

--
-- Name: neighborhoods_neighborhood_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.neighborhoods_neighborhood_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.neighborhoods_neighborhood_id_seq OWNER TO vaccine_user;

--
-- Name: neighborhoods_neighborhood_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.neighborhoods_neighborhood_id_seq OWNED BY public.neighborhoods.neighborhood_id;


--
-- Name: nfc_cards; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.nfc_cards (
    nfc_card_id integer NOT NULL,
    patient_id integer NOT NULL,
    uid character varying(30) NOT NULL,
    card_type character varying(30),
    issued_date date,
    issued_by integer,
    status character varying(20) DEFAULT 'Activa'::character varying NOT NULL,
    last_scanned_at timestamp without time zone,
    nfc_card_notes text,
    CONSTRAINT nfc_cards_status_check CHECK (((status)::text = ANY ((ARRAY['Activa'::character varying, 'Inactiva'::character varying, 'Perdida'::character varying, 'Robada'::character varying])::text[])))
);


ALTER TABLE public.nfc_cards OWNER TO vaccine_user;

--
-- Name: nfc_cards_nfc_card_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.nfc_cards_nfc_card_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.nfc_cards_nfc_card_id_seq OWNER TO vaccine_user;

--
-- Name: nfc_cards_nfc_card_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.nfc_cards_nfc_card_id_seq OWNED BY public.nfc_cards.nfc_card_id;


--
-- Name: nfc_devices; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.nfc_devices (
    device_id character varying(30) NOT NULL,
    clinic_id integer NOT NULL,
    area_id integer,
    device_name character varying(100),
    model character varying(50),
    serial_number character varying(50),
    nfc_device_status character varying(20) DEFAULT 'Activo'::character varying NOT NULL,
    registered_at date,
    CONSTRAINT nfc_devices_nfc_device_status_check CHECK (((nfc_device_status)::text = ANY ((ARRAY['Activo'::character varying, 'Inactivo'::character varying, 'Mantenimiento'::character varying])::text[])))
);


ALTER TABLE public.nfc_devices OWNER TO vaccine_user;

--
-- Name: nfc_relations; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.nfc_relations AS
 SELECT uid AS nfc_id,
    patient_id,
    issued_date,
    last_scanned_at,
    status
   FROM public.nfc_cards;


ALTER VIEW public.nfc_relations OWNER TO postgres;

--
-- Name: nfc_scan_events; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.nfc_scan_events (
    scan_event_id integer NOT NULL,
    nfc_card_id integer NOT NULL,
    scanned_by integer,
    clinic_id integer NOT NULL,
    area_id integer,
    scanned_at timestamp without time zone NOT NULL,
    action_triggered character varying(50),
    device_id character varying(30),
    nfc_scan_result character varying(100),
    visit_id integer,
    scan_context character varying(30),
    resolved_action character varying(50),
    error_reason text,
    CONSTRAINT nfc_scan_events_scan_context_check CHECK (((scan_context)::text = ANY ((ARRAY['checkin'::character varying, 'area_change'::character varying, 'medical_open'::character varying, 'vaccination_start'::character varying, 'checkout'::character varying, 'info_only'::character varying])::text[])))
);


ALTER TABLE public.nfc_scan_events OWNER TO vaccine_user;

--
-- Name: nfc_scan_events_scan_event_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.nfc_scan_events_scan_event_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.nfc_scan_events_scan_event_id_seq OWNER TO vaccine_user;

--
-- Name: nfc_scan_events_scan_event_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.nfc_scan_events_scan_event_id_seq OWNED BY public.nfc_scan_events.scan_event_id;


--
-- Name: occupations; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.occupations (
    occupation_id integer NOT NULL,
    occupation_name character varying(100) NOT NULL
);


ALTER TABLE public.occupations OWNER TO vaccine_user;

--
-- Name: occupations_occupation_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.occupations_occupation_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.occupations_occupation_id_seq OWNER TO vaccine_user;

--
-- Name: occupations_occupation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.occupations_occupation_id_seq OWNED BY public.occupations.occupation_id;


--
-- Name: patient_allergies; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.patient_allergies (
    patient_allergy_id integer NOT NULL,
    patient_id integer NOT NULL,
    allergy_id integer NOT NULL,
    severity character varying(50),
    reaction_desc text
);


ALTER TABLE public.patient_allergies OWNER TO vaccine_user;

--
-- Name: patient_allergies_patient_allergy_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.patient_allergies_patient_allergy_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.patient_allergies_patient_allergy_id_seq OWNER TO vaccine_user;

--
-- Name: patient_allergies_patient_allergy_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.patient_allergies_patient_allergy_id_seq OWNED BY public.patient_allergies.patient_allergy_id;


--
-- Name: patient_clinic_visits; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.patient_clinic_visits (
    visit_id integer NOT NULL,
    patient_id integer NOT NULL,
    clinic_id integer NOT NULL,
    appointment_id integer,
    visit_status public.visit_status DEFAULT 'En recepcion'::public.visit_status NOT NULL,
    current_area_id integer,
    assigned_worker_id integer,
    checked_in_at timestamp without time zone DEFAULT now() NOT NULL,
    waiting_since timestamp without time zone,
    consultation_start timestamp without time zone,
    vaccination_start timestamp without time zone,
    checked_out_at timestamp without time zone,
    checkin_by_worker_id integer NOT NULL,
    checkout_by_worker_id integer,
    checkin_nfc_scan_id integer,
    checkout_nfc_scan_id integer,
    visit_type character varying(20) DEFAULT 'Programada'::character varying NOT NULL,
    visit_notes text,
    created_at timestamp without time zone DEFAULT now() NOT NULL,
    updated_at timestamp without time zone DEFAULT now() NOT NULL,
    CONSTRAINT patient_clinic_visits_visit_type_check CHECK (((visit_type)::text = ANY ((ARRAY['Programada'::character varying, 'Espontanea'::character varying, 'Urgencia'::character varying])::text[])))
);


ALTER TABLE public.patient_clinic_visits OWNER TO postgres;

--
-- Name: patient_clinic_visits_visit_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.patient_clinic_visits_visit_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.patient_clinic_visits_visit_id_seq OWNER TO postgres;

--
-- Name: patient_clinic_visits_visit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.patient_clinic_visits_visit_id_seq OWNED BY public.patient_clinic_visits.visit_id;


--
-- Name: patient_guardian_relations; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.patient_guardian_relations (
    relation_id integer NOT NULL,
    patient_id integer NOT NULL,
    guardian_id integer NOT NULL,
    relation_type character varying(50),
    is_primary boolean DEFAULT false NOT NULL,
    has_custody boolean DEFAULT false NOT NULL
);


ALTER TABLE public.patient_guardian_relations OWNER TO vaccine_user;

--
-- Name: patient_guardian_relations_relation_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.patient_guardian_relations_relation_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.patient_guardian_relations_relation_id_seq OWNER TO vaccine_user;

--
-- Name: patient_guardian_relations_relation_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.patient_guardian_relations_relation_id_seq OWNED BY public.patient_guardian_relations.relation_id;


--
-- Name: patient_vaccine_schedule; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.patient_vaccine_schedule (
    schedule_id integer NOT NULL,
    patient_id integer NOT NULL,
    scheme_dose_id integer NOT NULL,
    due_date date NOT NULL,
    status character varying(20) DEFAULT 'Pendiente'::character varying,
    updated_at timestamp without time zone DEFAULT now(),
    CONSTRAINT patient_vaccine_schedule_status_check CHECK (((status)::text = ANY ((ARRAY['Pendiente'::character varying, 'Aplicada'::character varying, 'Atrasada'::character varying])::text[])))
);


ALTER TABLE public.patient_vaccine_schedule OWNER TO vaccine_user;

--
-- Name: patient_vaccine_schedule_schedule_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.patient_vaccine_schedule_schedule_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.patient_vaccine_schedule_schedule_id_seq OWNER TO vaccine_user;

--
-- Name: patient_vaccine_schedule_schedule_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.patient_vaccine_schedule_schedule_id_seq OWNED BY public.patient_vaccine_schedule.schedule_id;


--
-- Name: patients; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.patients (
    patient_id integer NOT NULL,
    first_name character varying(100) NOT NULL,
    last_name character varying(100) NOT NULL,
    birth_date date NOT NULL,
    blood_type_id integer,
    gender character(1),
    nfc_token character varying(50),
    curp character varying(18),
    weight_kg numeric(5,2),
    premature boolean DEFAULT false NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    is_active boolean DEFAULT true NOT NULL,
    deleted_at timestamp without time zone,
    updated_at timestamp without time zone,
    photo character varying(255),
    CONSTRAINT patients_gender_check CHECK ((gender = ANY (ARRAY['M'::bpchar, 'F'::bpchar, 'O'::bpchar])))
);


ALTER TABLE public.patients OWNER TO vaccine_user;

--
-- Name: patients_patient_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.patients_patient_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.patients_patient_id_seq OWNER TO vaccine_user;

--
-- Name: patients_patient_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.patients_patient_id_seq OWNED BY public.patients.patient_id;


--
-- Name: post_vaccine_reactions; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.post_vaccine_reactions (
    reaction_id integer NOT NULL,
    record_id integer NOT NULL,
    reported_by integer,
    symptom text,
    severity character varying(30),
    onset_hours smallint,
    treatment text,
    notified_authority boolean DEFAULT false NOT NULL
);


ALTER TABLE public.post_vaccine_reactions OWNER TO vaccine_user;

--
-- Name: post_vaccine_reactions_reaction_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.post_vaccine_reactions_reaction_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.post_vaccine_reactions_reaction_id_seq OWNER TO vaccine_user;

--
-- Name: post_vaccine_reactions_reaction_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.post_vaccine_reactions_reaction_id_seq OWNED BY public.post_vaccine_reactions.reaction_id;


--
-- Name: roles; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.roles (
    role_id integer NOT NULL,
    name character varying(100) NOT NULL,
    description text,
    CONSTRAINT roles_name_check CHECK (((name)::text = ANY ((ARRAY['Administrador'::character varying, 'Enfermero'::character varying, 'Medico'::character varying, 'Recepcionista'::character varying, 'Almacen'::character varying, 'Tutor'::character varying])::text[])))
);


ALTER TABLE public.roles OWNER TO vaccine_user;

--
-- Name: roles_role_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.roles_role_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.roles_role_id_seq OWNER TO vaccine_user;

--
-- Name: roles_role_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.roles_role_id_seq OWNED BY public.roles.role_id;


--
-- Name: scheme_completion_alerts; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.scheme_completion_alerts (
    alert_id integer NOT NULL,
    patient_id integer NOT NULL,
    scheme_dose_id integer NOT NULL,
    due_date date NOT NULL,
    status character varying(30) DEFAULT 'Pendiente'::character varying NOT NULL,
    notified_at timestamp without time zone,
    alert_type character varying(30),
    read_at timestamp without time zone,
    schedule_id integer NOT NULL,
    CONSTRAINT scheme_completion_alerts_alert_type_check CHECK (((alert_type)::text = ANY ((ARRAY['Proximidad'::character varying, 'Atraso'::character varying, 'Critico'::character varying])::text[]))),
    CONSTRAINT scheme_completion_alerts_status_check CHECK (((status)::text = ANY ((ARRAY['Pendiente'::character varying, 'Enviada'::character varying, 'Leida'::character varying, 'Ignorada'::character varying])::text[])))
);


ALTER TABLE public.scheme_completion_alerts OWNER TO vaccine_user;

--
-- Name: scheme_completion_alerts_alert_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.scheme_completion_alerts_alert_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.scheme_completion_alerts_alert_id_seq OWNER TO vaccine_user;

--
-- Name: scheme_completion_alerts_alert_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.scheme_completion_alerts_alert_id_seq OWNED BY public.scheme_completion_alerts.alert_id;


--
-- Name: scheme_doses; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.scheme_doses (
    dose_id integer NOT NULL,
    scheme_id integer NOT NULL,
    vaccine_id integer NOT NULL,
    dose_number smallint NOT NULL,
    dose_label character varying(100),
    ideal_age_months smallint,
    min_interval_days smallint
);


ALTER TABLE public.scheme_doses OWNER TO vaccine_user;

--
-- Name: scheme_doses_dose_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.scheme_doses_dose_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.scheme_doses_dose_id_seq OWNER TO vaccine_user;

--
-- Name: scheme_doses_dose_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.scheme_doses_dose_id_seq OWNED BY public.scheme_doses.dose_id;


--
-- Name: specialties; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.specialties (
    specialty_id integer NOT NULL,
    name character varying(100) NOT NULL
);


ALTER TABLE public.specialties OWNER TO vaccine_user;

--
-- Name: specialties_specialty_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.specialties_specialty_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.specialties_specialty_id_seq OWNER TO vaccine_user;

--
-- Name: specialties_specialty_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.specialties_specialty_id_seq OWNED BY public.specialties.specialty_id;


--
-- Name: states; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.states (
    state_id integer NOT NULL,
    country_id integer NOT NULL,
    name character varying(100) NOT NULL,
    code character varying(10)
);


ALTER TABLE public.states OWNER TO vaccine_user;

--
-- Name: states_state_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.states_state_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.states_state_id_seq OWNER TO vaccine_user;

--
-- Name: states_state_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.states_state_id_seq OWNED BY public.states.state_id;


--
-- Name: supply_catalog; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.supply_catalog (
    supply_id integer NOT NULL,
    name character varying(200) NOT NULL,
    unit character varying(30),
    category character varying(50)
);


ALTER TABLE public.supply_catalog OWNER TO vaccine_user;

--
-- Name: supply_catalog_supply_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.supply_catalog_supply_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.supply_catalog_supply_id_seq OWNER TO vaccine_user;

--
-- Name: supply_catalog_supply_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.supply_catalog_supply_id_seq OWNED BY public.supply_catalog.supply_id;


--
-- Name: users; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.users (
    user_id integer NOT NULL,
    worker_id integer,
    username character varying(50) NOT NULL,
    password_hash character varying(255) NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


ALTER TABLE public.users OWNER TO vaccine_user;

--
-- Name: users_user_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.users_user_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.users_user_id_seq OWNER TO vaccine_user;

--
-- Name: users_user_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.users_user_id_seq OWNED BY public.users.user_id;


--
-- Name: vaccines; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.vaccines (
    vaccine_id integer NOT NULL,
    name character varying(100) NOT NULL,
    commercial_name character varying(100),
    manufacturer_id integer,
    via_id integer,
    ideal_age_months smallint,
    disease_prevented text
);


ALTER TABLE public.vaccines OWNER TO vaccine_user;

--
-- Name: workers; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.workers (
    worker_id integer NOT NULL,
    role_id integer NOT NULL,
    first_name character varying(100) NOT NULL,
    last_name character varying(100) NOT NULL,
    curp character(18),
    address_id integer,
    birth_date date,
    hire_date date,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    is_active boolean DEFAULT true NOT NULL
);


ALTER TABLE public.workers OWNER TO vaccine_user;

--
-- Name: v_appointments_full; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_appointments_full AS
 SELECT a.appointment_id,
    a.patient_id,
    a.patient_schedule_id,
    a.worker_id,
    a.clinic_id,
    a.area_id,
    a.scheduled_at,
    a.duration_min,
    a.reason,
    a.appointment_status,
    a.appointment_notes,
    a.cancel_reason,
    a.confirmed_at,
    a.rescheduled_from_id,
    a.created_by_role,
    a.created_by_worker_id,
    a.created_by_guardian_id,
    COALESCE(TRIM(BOTH FROM (((p.first_name)::text || ' '::text) || (p.last_name)::text)), '-'::text) AS patient_name,
    COALESCE(TRIM(BOTH FROM (((w.first_name)::text || ' '::text) || (w.last_name)::text)), '-'::text) AS worker_name,
    c.name AS clinic_name,
    COALESCE(ca.name, '-'::character varying) AS area_name,
    pvs.scheme_dose_id,
    COALESCE(v.name, '-'::character varying) AS vaccine_name,
    COALESCE(sd.dose_label, '-'::character varying) AS dose_label,
    pvs.due_date AS dose_due_date,
    pvs.status AS dose_status
   FROM (((((((public.appointments a
     JOIN public.patients p ON ((p.patient_id = a.patient_id)))
     LEFT JOIN public.patient_vaccine_schedule pvs ON ((pvs.schedule_id = a.patient_schedule_id)))
     LEFT JOIN public.scheme_doses sd ON ((sd.dose_id = pvs.scheme_dose_id)))
     LEFT JOIN public.vaccines v ON ((v.vaccine_id = sd.vaccine_id)))
     LEFT JOIN public.workers w ON ((w.worker_id = a.worker_id)))
     JOIN public.clinics c ON ((c.clinic_id = a.clinic_id)))
     LEFT JOIN public.clinic_areas ca ON ((ca.area_id = a.area_id)));


ALTER VIEW public.v_appointments_full OWNER TO postgres;

--
-- Name: v_delayed_patients; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_delayed_patients AS
 SELECT p.patient_id,
    (((p.first_name)::text || ' '::text) || (p.last_name)::text) AS patient_name,
    v.name AS vaccine_name,
    sca.due_date,
    ((now())::date - sca.due_date) AS days_late
   FROM (((public.patients p
     JOIN public.scheme_completion_alerts sca ON ((p.patient_id = sca.patient_id)))
     JOIN public.scheme_doses sd ON ((sca.scheme_dose_id = sd.dose_id)))
     JOIN public.vaccines v ON ((sd.vaccine_id = v.vaccine_id)))
  WHERE (((sca.status)::text = 'Pendiente'::text) AND ((now())::date > sca.due_date));


ALTER VIEW public.v_delayed_patients OWNER TO postgres;

--
-- Name: vaccination_records; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.vaccination_records (
    record_id integer NOT NULL,
    patient_id integer NOT NULL,
    vaccine_id integer NOT NULL,
    worker_id integer NOT NULL,
    clinic_id integer NOT NULL,
    lot_id integer,
    scheme_dose_id integer,
    applied_date date NOT NULL,
    application_site_id integer,
    appointment_id integer,
    patient_temp_c numeric(4,1),
    had_reaction boolean DEFAULT false NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    patient_schedule_id integer,
    visit_id integer
);


ALTER TABLE public.vaccination_records OWNER TO vaccine_user;

--
-- Name: v_esquema_paciente_base; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_esquema_paciente_base AS
 SELECT p.patient_id,
    sd.dose_id,
    p.first_name,
    p.last_name,
    TRIM(BOTH FROM (((p.first_name)::text || ' '::text) || (p.last_name)::text)) AS full_name,
    p.birth_date,
    (date_part('year'::text, age((CURRENT_DATE)::timestamp with time zone, (p.birth_date)::timestamp with time zone)))::integer AS age_years,
    v.vaccine_id,
    v.name AS vaccine_name,
    v.disease_prevented,
    sd.dose_label,
    sd.dose_number,
    sd.ideal_age_months,
    ((p.birth_date + ((sd.ideal_age_months || ' months'::text))::interval))::date AS ideal_date,
    vr.record_id,
    vr.applied_date,
    vr.had_reaction,
    vr.patient_temp_c,
    vr.lot_id,
    COALESCE(TRIM(BOTH FROM (((w.first_name)::text || ' '::text) || (w.last_name)::text)), '—'::text) AS doctor,
    COALESCE(aps.application_site, '—'::character varying) AS application_site,
        CASE
            WHEN (vr.record_id IS NOT NULL) THEN 'Aplicada'::text
            WHEN (((p.birth_date + ((sd.ideal_age_months || ' months'::text))::interval))::date < CURRENT_DATE) THEN 'Pendiente con retraso'::text
            ELSE 'Pendiente'::text
        END AS estado,
        CASE
            WHEN (vr.record_id IS NOT NULL) THEN 0
            ELSE (CURRENT_DATE - ((p.birth_date + ((sd.ideal_age_months || ' months'::text))::interval))::date)
        END AS dias_retraso,
    ( SELECT min(sd2.ideal_age_months) AS min
           FROM public.scheme_doses sd2
          WHERE ((sd2.vaccine_id = sd.vaccine_id) AND (sd2.dose_number > sd.dose_number) AND (NOT (EXISTS ( SELECT 1
                   FROM public.vaccination_records vr2
                  WHERE ((vr2.patient_id = p.patient_id) AND (vr2.scheme_dose_id = sd2.dose_id))))))) AS next_dose_age_months
   FROM (((((public.patients p
     CROSS JOIN public.scheme_doses sd)
     JOIN public.vaccines v ON ((v.vaccine_id = sd.vaccine_id)))
     LEFT JOIN public.vaccination_records vr ON (((vr.patient_id = p.patient_id) AND (vr.scheme_dose_id = sd.dose_id))))
     LEFT JOIN public.workers w ON ((w.worker_id = vr.worker_id)))
     LEFT JOIN public.application_sites aps ON ((aps.application_site_id = vr.application_site_id)))
  WHERE (p.is_active = true)
  ORDER BY p.patient_id, sd.ideal_age_months, sd.dose_number;


ALTER VIEW public.v_esquema_paciente_base OWNER TO postgres;

--
-- Name: v_inventory_status; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_inventory_status AS
 SELECT ci.inventory_id,
    ci.quantity,
    ci.min_stock,
    ci.last_updated,
    (ci.quantity < ci.min_stock) AS low_stock,
    sc.name AS supply_name,
    sc.unit AS supply_unit,
    sc.category AS supply_category,
    c.name AS clinic_name,
    c.clinic_id
   FROM ((public.clinic_inventory ci
     JOIN public.supply_catalog sc ON ((sc.supply_id = ci.supply_id)))
     JOIN public.clinics c ON ((c.clinic_id = ci.clinic_id)));


ALTER VIEW public.v_inventory_status OWNER TO postgres;

--
-- Name: v_low_stock_items; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_low_stock_items AS
 SELECT ci.inventory_id,
    c.clinic_id,
    c.name AS clinic_name,
    sc.name AS supply_name,
    ci.quantity,
    ci.min_stock
   FROM ((public.clinic_inventory ci
     JOIN public.clinics c ON ((ci.clinic_id = c.clinic_id)))
     JOIN public.supply_catalog sc ON ((ci.supply_id = sc.supply_id)))
  WHERE (ci.quantity < ci.min_stock);


ALTER VIEW public.v_low_stock_items OWNER TO postgres;

--
-- Name: v_patient_vaccination_scheme_base; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_patient_vaccination_scheme_base AS
 SELECT pvs.schedule_id,
    p.patient_id,
    sd.dose_id,
    v.vaccine_id,
    p.first_name,
    p.last_name,
    TRIM(BOTH FROM (((p.first_name)::text || ' '::text) || (p.last_name)::text)) AS full_name,
    p.birth_date,
    (date_part('year'::text, age((CURRENT_DATE)::timestamp with time zone, (p.birth_date)::timestamp with time zone)))::integer AS age_years,
    v.name AS vaccine_name,
    v.disease_prevented,
    sd.dose_label,
    sd.dose_number,
    sd.ideal_age_months,
    ((p.birth_date + ((sd.ideal_age_months || ' months'::text))::interval))::date AS ideal_date,
    vr.record_id,
    vr.applied_date,
    vr.had_reaction,
    vr.patient_temp_c,
    vr.lot_id,
    COALESCE(TRIM(BOTH FROM (((w.first_name)::text || ' '::text) || (w.last_name)::text)), '-'::text) AS doctor,
    COALESCE(aps.application_site, '-'::character varying) AS application_site,
        CASE
            WHEN (vr.record_id IS NOT NULL) THEN 'Aplicada'::text
            WHEN (pvs.due_date < CURRENT_DATE) THEN 'Atrasada'::text
            ELSE 'Pendiente'::text
        END AS vaccination_status,
        CASE
            WHEN (vr.record_id IS NOT NULL) THEN 0
            ELSE (CURRENT_DATE - pvs.due_date)
        END AS dias_retraso,
    ( SELECT min(sd2.ideal_age_months) AS min
           FROM public.scheme_doses sd2
          WHERE ((sd2.vaccine_id = sd.vaccine_id) AND (sd2.dose_number > sd.dose_number) AND (NOT (EXISTS ( SELECT 1
                   FROM public.vaccination_records vr2
                  WHERE ((vr2.patient_id = p.patient_id) AND (vr2.scheme_dose_id = sd2.dose_id))))))) AS next_dose_age_months
   FROM ((((((public.patient_vaccine_schedule pvs
     JOIN public.patients p ON ((pvs.patient_id = p.patient_id)))
     JOIN public.scheme_doses sd ON ((pvs.scheme_dose_id = sd.dose_id)))
     JOIN public.vaccines v ON ((sd.vaccine_id = v.vaccine_id)))
     LEFT JOIN public.vaccination_records vr ON (((vr.patient_id = p.patient_id) AND (vr.scheme_dose_id = sd.dose_id))))
     LEFT JOIN public.workers w ON ((w.worker_id = vr.worker_id)))
     LEFT JOIN public.application_sites aps ON ((aps.application_site_id = vr.application_site_id)))
  WHERE (p.is_active = true);


ALTER VIEW public.v_patient_vaccination_scheme_base OWNER TO postgres;

--
-- Name: v_pending_scheme_doses; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_pending_scheme_doses AS
 SELECT p.patient_id,
    v.name AS vaccine_name,
    v.vaccine_id,
    sd.dose_label,
    sd.ideal_age_months,
    sd.dose_id
   FROM ((public.patients p
     CROSS JOIN public.scheme_doses sd)
     JOIN public.vaccines v ON ((v.vaccine_id = sd.vaccine_id)))
  WHERE (NOT (EXISTS ( SELECT 1
           FROM public.vaccination_records vr
          WHERE ((vr.patient_id = p.patient_id) AND (vr.scheme_dose_id = sd.dose_id)))));


ALTER VIEW public.v_pending_scheme_doses OWNER TO postgres;

--
-- Name: v_vaccination_records_full; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_vaccination_records_full AS
 SELECT vr.record_id,
    vr.patient_id,
    vr.vaccine_id,
    vr.applied_date,
    vr.patient_temp_c,
    vr.had_reaction,
    (((p.first_name)::text || ' '::text) || (p.last_name)::text) AS patient_name,
    v.name AS vaccine_name,
    (((w.first_name)::text || ' '::text) || (w.last_name)::text) AS worker_name,
    sd.dose_label,
    aps.application_site,
    c.name AS clinic_name
   FROM ((((((public.vaccination_records vr
     JOIN public.patients p ON ((p.patient_id = vr.patient_id)))
     JOIN public.vaccines v ON ((v.vaccine_id = vr.vaccine_id)))
     JOIN public.workers w ON ((w.worker_id = vr.worker_id)))
     LEFT JOIN public.scheme_doses sd ON ((sd.dose_id = vr.scheme_dose_id)))
     LEFT JOIN public.application_sites aps ON ((aps.application_site_id = vr.application_site_id)))
     JOIN public.clinics c ON ((c.clinic_id = vr.clinic_id)));


ALTER VIEW public.v_vaccination_records_full OWNER TO postgres;

--
-- Name: vaccine_lots; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.vaccine_lots (
    lot_id integer NOT NULL,
    vaccine_id integer NOT NULL,
    clinic_id integer NOT NULL,
    lot_number character varying(50) NOT NULL,
    quantity_received integer NOT NULL,
    quantity_available integer NOT NULL,
    expiration_date date NOT NULL,
    received_date date,
    is_active boolean DEFAULT true NOT NULL,
    lot_status character varying(30) DEFAULT 'Disponible'::character varying NOT NULL,
    CONSTRAINT vaccine_lots_lot_status_check CHECK (((lot_status)::text = ANY ((ARRAY['Disponible'::character varying, 'Agotado'::character varying, 'Caducado'::character varying, 'Bloqueado'::character varying, 'Retirado'::character varying])::text[])))
);


ALTER TABLE public.vaccine_lots OWNER TO vaccine_user;

--
-- Name: vaccine_vias; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.vaccine_vias (
    via_id integer NOT NULL,
    via character varying(50) NOT NULL
);


ALTER TABLE public.vaccine_vias OWNER TO vaccine_user;

--
-- Name: v_vaccine_stock; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_vaccine_stock AS
 SELECT v.vaccine_id,
    v.name,
    v.commercial_name,
    m.name AS manufacturer,
    vv.via AS route,
    sum(vl.quantity_available) AS total_stock,
    min(vl.expiration_date) AS nearest_expiration
   FROM (((public.vaccines v
     LEFT JOIN public.manufacturers m ON ((m.manufacturer_id = v.manufacturer_id)))
     LEFT JOIN public.vaccine_vias vv ON ((vv.via_id = v.via_id)))
     LEFT JOIN public.vaccine_lots vl ON ((vl.vaccine_id = v.vaccine_id)))
  GROUP BY v.vaccine_id, v.name, v.commercial_name, m.name, vv.via;


ALTER VIEW public.v_vaccine_stock OWNER TO postgres;

--
-- Name: worker_emails; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.worker_emails (
    email_id integer NOT NULL,
    worker_id integer NOT NULL,
    email character varying(150) NOT NULL,
    is_primary boolean DEFAULT false NOT NULL
);


ALTER TABLE public.worker_emails OWNER TO vaccine_user;

--
-- Name: v_worker_full; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.v_worker_full AS
 SELECT w.worker_id,
    w.first_name,
    w.last_name,
    (((w.first_name)::text || ' '::text) || (w.last_name)::text) AS full_name,
    r.name AS role_name,
    r.role_id,
    we.email,
    we.is_primary AS is_primary_email
   FROM ((public.workers w
     LEFT JOIN public.roles r ON ((w.role_id = r.role_id)))
     LEFT JOIN public.worker_emails we ON ((we.worker_id = w.worker_id)));


ALTER VIEW public.v_worker_full OWNER TO postgres;

--
-- Name: vaccination_records_record_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.vaccination_records_record_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.vaccination_records_record_id_seq OWNER TO vaccine_user;

--
-- Name: vaccination_records_record_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.vaccination_records_record_id_seq OWNED BY public.vaccination_records.record_id;


--
-- Name: vaccination_scheme; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.vaccination_scheme (
    scheme_id integer NOT NULL,
    name character varying(200) NOT NULL,
    issuing_body character varying(100),
    year smallint,
    is_current boolean DEFAULT false NOT NULL
);


ALTER TABLE public.vaccination_scheme OWNER TO vaccine_user;

--
-- Name: vaccination_scheme_scheme_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.vaccination_scheme_scheme_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.vaccination_scheme_scheme_id_seq OWNER TO vaccine_user;

--
-- Name: vaccination_scheme_scheme_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.vaccination_scheme_scheme_id_seq OWNED BY public.vaccination_scheme.scheme_id;


--
-- Name: vaccine_lots_lot_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.vaccine_lots_lot_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.vaccine_lots_lot_id_seq OWNER TO vaccine_user;

--
-- Name: vaccine_lots_lot_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.vaccine_lots_lot_id_seq OWNED BY public.vaccine_lots.lot_id;


--
-- Name: vaccine_vias_via_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.vaccine_vias_via_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.vaccine_vias_via_id_seq OWNER TO vaccine_user;

--
-- Name: vaccine_vias_via_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.vaccine_vias_via_id_seq OWNED BY public.vaccine_vias.via_id;


--
-- Name: vaccines_vaccine_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.vaccines_vaccine_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.vaccines_vaccine_id_seq OWNER TO vaccine_user;

--
-- Name: vaccines_vaccine_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.vaccines_vaccine_id_seq OWNED BY public.vaccines.vaccine_id;


--
-- Name: visit_area_movements; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.visit_area_movements (
    movement_id integer NOT NULL,
    visit_id integer NOT NULL,
    from_area_id integer,
    to_area_id integer,
    from_status public.visit_status,
    to_status public.visit_status NOT NULL,
    moved_at timestamp without time zone DEFAULT now() NOT NULL,
    moved_by integer NOT NULL,
    nfc_scan_id integer,
    movement_notes text
);


ALTER TABLE public.visit_area_movements OWNER TO postgres;

--
-- Name: visit_area_movements_movement_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.visit_area_movements_movement_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.visit_area_movements_movement_id_seq OWNER TO postgres;

--
-- Name: visit_area_movements_movement_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.visit_area_movements_movement_id_seq OWNED BY public.visit_area_movements.movement_id;


--
-- Name: vw_dashboard_kpis; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_dashboard_kpis AS
 SELECT (( SELECT count(*) AS count
           FROM public.patients
          WHERE (patients.is_active = true)))::integer AS total_patients,
    (( SELECT count(*) AS count
           FROM public.vaccination_records
          WHERE (vaccination_records.applied_date = CURRENT_DATE)))::integer AS vaccinations_today,
    (( SELECT count(*) AS count
           FROM (public.patient_vaccine_schedule pvs
             JOIN public.patients p ON ((p.patient_id = pvs.patient_id)))
          WHERE (((pvs.status)::text = 'Atrasada'::text) AND (p.is_active = true))))::integer AS overdue_doses,
    (( SELECT count(*) AS count
           FROM public.appointments
          WHERE (((appointments.appointment_status)::text = ANY ((ARRAY['Programada'::character varying, 'Confirmada'::character varying])::text[])) AND (date(appointments.scheduled_at) = CURRENT_DATE))))::integer AS appointments_today,
    (( SELECT count(*) AS count
           FROM public.vaccine_lots
          WHERE ((vaccine_lots.quantity_available <= 10) AND (vaccine_lots.expiration_date >= CURRENT_DATE))))::integer AS low_stock_lots,
    (( SELECT count(*) AS count
           FROM public.vaccine_lots
          WHERE (((vaccine_lots.expiration_date >= CURRENT_DATE) AND (vaccine_lots.expiration_date <= (CURRENT_DATE + 30))) AND (vaccine_lots.quantity_available > 0))))::integer AS expiring_lots;


ALTER VIEW public.vw_dashboard_kpis OWNER TO postgres;

--
-- Name: vw_patients; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_patients AS
SELECT
    NULL::integer AS patient_id,
    NULL::character varying(100) AS first_name,
    NULL::character varying(100) AS last_name,
    NULL::text AS full_name,
    NULL::date AS birth_date,
    NULL::character(1) AS gender,
    NULL::numeric(5,2) AS weight_kg,
    NULL::boolean AS premature,
    NULL::character varying(18) AS curp,
    NULL::character varying(5) AS blood_type,
    NULL::text AS guardian_name,
    NULL::character varying(20) AS guardian_phone,
    NULL::text AS allergies;


ALTER VIEW public.vw_patients OWNER TO postgres;

--
-- Name: vw_worker_full; Type: VIEW; Schema: public; Owner: postgres
--

CREATE VIEW public.vw_worker_full AS
 SELECT w.worker_id,
    w.first_name,
    w.last_name,
    (((w.first_name)::text || ' '::text) || (w.last_name)::text) AS full_name,
    r.name AS role_name,
    r.role_id,
    we.email,
    we.is_primary AS is_primary_email
   FROM ((public.workers w
     LEFT JOIN public.roles r ON ((w.role_id = r.role_id)))
     LEFT JOIN public.worker_emails we ON ((we.worker_id = w.worker_id)));


ALTER VIEW public.vw_worker_full OWNER TO postgres;

--
-- Name: worker_clinic_assignment; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.worker_clinic_assignment (
    assignment_id integer NOT NULL,
    worker_id integer NOT NULL,
    clinic_id integer NOT NULL,
    area_id integer,
    start_date date NOT NULL,
    end_date date,
    is_active boolean DEFAULT true NOT NULL
);


ALTER TABLE public.worker_clinic_assignment OWNER TO vaccine_user;

--
-- Name: worker_clinic_assignment_assignment_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.worker_clinic_assignment_assignment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.worker_clinic_assignment_assignment_id_seq OWNER TO vaccine_user;

--
-- Name: worker_clinic_assignment_assignment_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.worker_clinic_assignment_assignment_id_seq OWNED BY public.worker_clinic_assignment.assignment_id;


--
-- Name: worker_emails_email_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.worker_emails_email_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.worker_emails_email_id_seq OWNER TO vaccine_user;

--
-- Name: worker_emails_email_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.worker_emails_email_id_seq OWNED BY public.worker_emails.email_id;


--
-- Name: worker_phones; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.worker_phones (
    phone_id integer NOT NULL,
    worker_id integer NOT NULL,
    phone character varying(20) NOT NULL,
    phone_type character varying(30),
    is_primary boolean DEFAULT false NOT NULL
);


ALTER TABLE public.worker_phones OWNER TO vaccine_user;

--
-- Name: worker_phones_phone_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.worker_phones_phone_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.worker_phones_phone_id_seq OWNER TO vaccine_user;

--
-- Name: worker_phones_phone_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.worker_phones_phone_id_seq OWNED BY public.worker_phones.phone_id;


--
-- Name: worker_professional; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.worker_professional (
    worker_id integer NOT NULL,
    cedula_profesional character varying(20),
    specialty_id integer NOT NULL,
    institution_id integer
);


ALTER TABLE public.worker_professional OWNER TO vaccine_user;

--
-- Name: worker_schedules; Type: TABLE; Schema: public; Owner: vaccine_user
--

CREATE TABLE public.worker_schedules (
    schedule_id integer NOT NULL,
    worker_id integer NOT NULL,
    clinic_id integer NOT NULL,
    day_of_week smallint NOT NULL,
    entry_time time without time zone NOT NULL,
    exit_time time without time zone NOT NULL,
    shift_type character varying(30),
    CONSTRAINT worker_schedules_day_of_week_check CHECK (((day_of_week >= 1) AND (day_of_week <= 7)))
);


ALTER TABLE public.worker_schedules OWNER TO vaccine_user;

--
-- Name: worker_schedules_schedule_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.worker_schedules_schedule_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.worker_schedules_schedule_id_seq OWNER TO vaccine_user;

--
-- Name: worker_schedules_schedule_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.worker_schedules_schedule_id_seq OWNED BY public.worker_schedules.schedule_id;


--
-- Name: workers_worker_id_seq; Type: SEQUENCE; Schema: public; Owner: vaccine_user
--

CREATE SEQUENCE public.workers_worker_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.workers_worker_id_seq OWNER TO vaccine_user;

--
-- Name: workers_worker_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: vaccine_user
--

ALTER SEQUENCE public.workers_worker_id_seq OWNED BY public.workers.worker_id;


--
-- Name: addresses address_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.addresses ALTER COLUMN address_id SET DEFAULT nextval('public.addresses_address_id_seq'::regclass);


--
-- Name: allergies allergy_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.allergies ALTER COLUMN allergy_id SET DEFAULT nextval('public.allergies_allergy_id_seq'::regclass);


--
-- Name: application_sites application_site_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.application_sites ALTER COLUMN application_site_id SET DEFAULT nextval('public.application_sites_application_site_id_seq'::regclass);


--
-- Name: appointments appointment_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.appointments ALTER COLUMN appointment_id SET DEFAULT nextval('public.appointments_appointment_id_seq'::regclass);


--
-- Name: area_equipment area_equipment_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.area_equipment ALTER COLUMN area_equipment_id SET DEFAULT nextval('public.area_equipment_area_equipment_id_seq'::regclass);


--
-- Name: audit_log audit_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.audit_log ALTER COLUMN audit_id SET DEFAULT nextval('public.audit_log_audit_id_seq'::regclass);


--
-- Name: blood_types blood_type_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.blood_types ALTER COLUMN blood_type_id SET DEFAULT nextval('public.blood_types_blood_type_id_seq'::regclass);


--
-- Name: clinic_area_types area_type_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.clinic_area_types ALTER COLUMN area_type_id SET DEFAULT nextval('public.clinic_area_types_area_type_id_seq'::regclass);


--
-- Name: clinic_areas area_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.clinic_areas ALTER COLUMN area_id SET DEFAULT nextval('public.clinic_areas_area_id_seq'::regclass);


--
-- Name: clinic_inventory inventory_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.clinic_inventory ALTER COLUMN inventory_id SET DEFAULT nextval('public.clinic_inventory_inventory_id_seq'::regclass);


--
-- Name: clinics clinic_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.clinics ALTER COLUMN clinic_id SET DEFAULT nextval('public.clinics_clinic_id_seq'::regclass);


--
-- Name: countries country_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.countries ALTER COLUMN country_id SET DEFAULT nextval('public.countries_country_id_seq'::regclass);


--
-- Name: equipment_catalog equipment_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.equipment_catalog ALTER COLUMN equipment_id SET DEFAULT nextval('public.equipment_catalog_equipment_id_seq'::regclass);


--
-- Name: guardian_accounts guardian_account_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.guardian_accounts ALTER COLUMN guardian_account_id SET DEFAULT nextval('public.guardian_accounts_guardian_account_id_seq'::regclass);


--
-- Name: guardian_emails email_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.guardian_emails ALTER COLUMN email_id SET DEFAULT nextval('public.guardian_emails_email_id_seq'::regclass);


--
-- Name: guardian_phones phone_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.guardian_phones ALTER COLUMN phone_id SET DEFAULT nextval('public.guardian_phones_phone_id_seq'::regclass);


--
-- Name: guardians guardian_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.guardians ALTER COLUMN guardian_id SET DEFAULT nextval('public.guardians_guardian_id_seq'::regclass);


--
-- Name: institutions institution_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.institutions ALTER COLUMN institution_id SET DEFAULT nextval('public.institutions_institution_id_seq'::regclass);


--
-- Name: inventory_movements movement_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.inventory_movements ALTER COLUMN movement_id SET DEFAULT nextval('public.inventory_movements_movement_id_seq'::regclass);


--
-- Name: inventory_transfers transfer_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_transfers ALTER COLUMN transfer_id SET DEFAULT nextval('public.inventory_transfers_transfer_id_seq'::regclass);


--
-- Name: manufacturers manufacturer_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.manufacturers ALTER COLUMN manufacturer_id SET DEFAULT nextval('public.manufacturers_manufacturer_id_seq'::regclass);


--
-- Name: marital_status marital_status_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.marital_status ALTER COLUMN marital_status_id SET DEFAULT nextval('public.marital_status_marital_status_id_seq'::regclass);


--
-- Name: municipalities municipality_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.municipalities ALTER COLUMN municipality_id SET DEFAULT nextval('public.municipalities_municipality_id_seq'::regclass);


--
-- Name: neighborhoods neighborhood_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.neighborhoods ALTER COLUMN neighborhood_id SET DEFAULT nextval('public.neighborhoods_neighborhood_id_seq'::regclass);


--
-- Name: nfc_cards nfc_card_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.nfc_cards ALTER COLUMN nfc_card_id SET DEFAULT nextval('public.nfc_cards_nfc_card_id_seq'::regclass);


--
-- Name: nfc_scan_events scan_event_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.nfc_scan_events ALTER COLUMN scan_event_id SET DEFAULT nextval('public.nfc_scan_events_scan_event_id_seq'::regclass);


--
-- Name: occupations occupation_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.occupations ALTER COLUMN occupation_id SET DEFAULT nextval('public.occupations_occupation_id_seq'::regclass);


--
-- Name: patient_allergies patient_allergy_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.patient_allergies ALTER COLUMN patient_allergy_id SET DEFAULT nextval('public.patient_allergies_patient_allergy_id_seq'::regclass);


--
-- Name: patient_clinic_visits visit_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patient_clinic_visits ALTER COLUMN visit_id SET DEFAULT nextval('public.patient_clinic_visits_visit_id_seq'::regclass);


--
-- Name: patient_guardian_relations relation_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.patient_guardian_relations ALTER COLUMN relation_id SET DEFAULT nextval('public.patient_guardian_relations_relation_id_seq'::regclass);


--
-- Name: patient_vaccine_schedule schedule_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.patient_vaccine_schedule ALTER COLUMN schedule_id SET DEFAULT nextval('public.patient_vaccine_schedule_schedule_id_seq'::regclass);


--
-- Name: patients patient_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.patients ALTER COLUMN patient_id SET DEFAULT nextval('public.patients_patient_id_seq'::regclass);


--
-- Name: post_vaccine_reactions reaction_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.post_vaccine_reactions ALTER COLUMN reaction_id SET DEFAULT nextval('public.post_vaccine_reactions_reaction_id_seq'::regclass);


--
-- Name: roles role_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.roles ALTER COLUMN role_id SET DEFAULT nextval('public.roles_role_id_seq'::regclass);


--
-- Name: scheme_completion_alerts alert_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.scheme_completion_alerts ALTER COLUMN alert_id SET DEFAULT nextval('public.scheme_completion_alerts_alert_id_seq'::regclass);


--
-- Name: scheme_doses dose_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.scheme_doses ALTER COLUMN dose_id SET DEFAULT nextval('public.scheme_doses_dose_id_seq'::regclass);


--
-- Name: specialties specialty_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.specialties ALTER COLUMN specialty_id SET DEFAULT nextval('public.specialties_specialty_id_seq'::regclass);


--
-- Name: states state_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.states ALTER COLUMN state_id SET DEFAULT nextval('public.states_state_id_seq'::regclass);


--
-- Name: supply_catalog supply_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.supply_catalog ALTER COLUMN supply_id SET DEFAULT nextval('public.supply_catalog_supply_id_seq'::regclass);


--
-- Name: users user_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.users ALTER COLUMN user_id SET DEFAULT nextval('public.users_user_id_seq'::regclass);


--
-- Name: vaccination_records record_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccination_records ALTER COLUMN record_id SET DEFAULT nextval('public.vaccination_records_record_id_seq'::regclass);


--
-- Name: vaccination_scheme scheme_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccination_scheme ALTER COLUMN scheme_id SET DEFAULT nextval('public.vaccination_scheme_scheme_id_seq'::regclass);


--
-- Name: vaccine_lots lot_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccine_lots ALTER COLUMN lot_id SET DEFAULT nextval('public.vaccine_lots_lot_id_seq'::regclass);


--
-- Name: vaccine_vias via_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccine_vias ALTER COLUMN via_id SET DEFAULT nextval('public.vaccine_vias_via_id_seq'::regclass);


--
-- Name: vaccines vaccine_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccines ALTER COLUMN vaccine_id SET DEFAULT nextval('public.vaccines_vaccine_id_seq'::regclass);


--
-- Name: visit_area_movements movement_id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.visit_area_movements ALTER COLUMN movement_id SET DEFAULT nextval('public.visit_area_movements_movement_id_seq'::regclass);


--
-- Name: worker_clinic_assignment assignment_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.worker_clinic_assignment ALTER COLUMN assignment_id SET DEFAULT nextval('public.worker_clinic_assignment_assignment_id_seq'::regclass);


--
-- Name: worker_emails email_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.worker_emails ALTER COLUMN email_id SET DEFAULT nextval('public.worker_emails_email_id_seq'::regclass);


--
-- Name: worker_phones phone_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.worker_phones ALTER COLUMN phone_id SET DEFAULT nextval('public.worker_phones_phone_id_seq'::regclass);


--
-- Name: worker_schedules schedule_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.worker_schedules ALTER COLUMN schedule_id SET DEFAULT nextval('public.worker_schedules_schedule_id_seq'::regclass);


--
-- Name: workers worker_id; Type: DEFAULT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.workers ALTER COLUMN worker_id SET DEFAULT nextval('public.workers_worker_id_seq'::regclass);


--
-- Data for Name: addresses; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.addresses (address_id, neighborhood_id, street, ext_number, cross_street_1, latitude, longitude) FROM stdin;
1	1	Av. Constitución	100	Av. Pino Suárez	25.6686	-100.3092
2	2	Calle Ruiz Cortines	320	Blvd. Las Torres	25.7804	-100.1880
3	3	Blvd. Díaz Ordaz	890	Av. Universidad	25.7319	-100.2988
4	4	Av. Miguel Alemán	450	Calle Nogal	25.6826	-100.2197
5	5	Av. Vasconcelos	230	Av. Morones Prieto	25.6506	-100.3951
6	6	Blvd. Escobedo	1100	Av. Las Torres	25.7990	-100.3210
7	7	Av. Santa Catarina	500	Calle Los Pinos	25.6729	-100.4591
8	8	Calle Benito Juárez	75	Av. Juárez	25.6427	-100.0869
9	9	Av. Ignacio Morones	210	Calle Tamaulipas	25.6692	-100.3325
10	10	Calle Las Flores	88	Blvd. Solidaridad	25.7890	-100.1760
11	11	Calle Moctezuma	55	Av. Zaragoza	25.6720	-100.3100
12	12	Av. Churubusco	430	Calle Independencia	25.7300	-100.3010
13	13	Av. Vallarta	202	Chapultepec	20.6736	-103.3440
14	14	Insurgentes Sur	303	Félix Cuevas	19.3889	-99.1680
15	15	Venustiano Carranza	404	Allende	25.4267	-100.9950
16	16	Hidalgo	505	Juárez	26.0806	-98.2883
17	17	Morelos	606	Rosales	29.0729	-110.9559
18	18	Tecnológico	707	Homero	28.6353	-106.0889
19	19	Paseo Montejo	808	Colón	20.9674	-89.5926
20	20	Juárez	909	5 de Mayo	19.0414	-98.2063
21	21	Antea	111	Universidad	20.5888	-100.3899
\.


--
-- Data for Name: allergies; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.allergies (allergy_id, name, allergy_type) FROM stdin;
1	Penicilina	Medicamento
2	Polen	Ambiental
3	Lácteos	Alimento
4	Maní	Alimento
5	Mariscos	Alimento
6	Polvo	Ambiental
7	Latex	Contacto
8	Huevos	Alimento
9	Picadura de abeja	Insecto
10	Ibuprofeno	Medicamento
11	Gluten	Alimento
12	Perfume	Químico
13	Soya	Alimento
14	Pelo de gato	Animal
15	Amoxicilina	Medicamento
\.


--
-- Data for Name: application_sites; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.application_sites (application_site_id, application_site) FROM stdin;
1	Muslo_Izq
2	Muslo_Der
3	Brazo_Izq
4	Brazo_Der
5	Oral
6	Intradermica_Hombro_Der
7	Gluteo_Izq
8	Gluteo_Der
\.


--
-- Data for Name: appointments; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.appointments (appointment_id, clinic_id, area_id, worker_id, scheduled_at, duration_min, reason, appointment_status, appointment_notes, created_at, patient_schedule_id, confirmed_at, cancel_reason, rescheduled_from_id, created_by_role, created_by_worker_id, created_by_guardian_id, patient_id) FROM stdin;
1	1	3	3	2018-03-15 09:00:00	20	BCG + Hep B nacimiento	Completada	\N	2026-05-16 17:14:58.698042	\N	\N	\N	\N	Medico	3	\N	1
2	1	3	3	2019-07-20 09:00:00	20	BCG + Hep B nacimiento	Completada	\N	2026-05-16 17:14:58.698042	\N	\N	\N	\N	Medico	3	\N	2
4	1	3	3	2017-11-05 09:00:00	20	Hep B 1ra dosis nacimiento	Completada	\N	2026-05-16 17:14:58.698042	\N	\N	\N	\N	Medico	3	\N	4
6	1	3	3	2018-08-18 09:00:00	20	BCG nacimiento	Completada	\N	2026-05-16 17:14:58.698042	\N	\N	\N	\N	Medico	3	\N	6
8	1	3	3	2020-09-14 09:00:00	20	BCG nacimiento	Completada	\N	2026-05-16 17:14:58.698042	\N	\N	\N	\N	Medico	3	\N	8
9	1	3	3	2017-12-30 09:00:00	20	BCG + Hep B nacimiento	Completada	\N	2026-05-16 17:14:58.698042	\N	\N	\N	\N	Medico	3	\N	9
11	1	3	3	2018-05-03 09:00:00	20	BCG nacimiento	Completada	\N	2026-05-16 17:14:58.698042	\N	\N	\N	\N	Medico	3	\N	11
13	1	3	3	2020-09-01 09:00:00	20	Pentavalente 1ra dosis - 2m	Completada	\N	2026-05-16 17:14:58.698042	\N	\N	\N	\N	Medico	3	\N	13
14	1	3	3	2017-09-27 09:00:00	20	BCG nacimiento	Completada	\N	2026-05-16 17:14:58.698042	\N	\N	\N	\N	Medico	3	\N	14
3	1	2	2	2020-01-10 09:00:00	20	BCG nacimiento	Completada	\N	2026-05-16 17:14:58.698042	\N	\N	\N	\N	Enfermero	2	\N	3
5	1	2	2	2021-06-12 09:00:00	20	BCG nacimiento	Completada	\N	2026-05-16 17:14:58.698042	\N	\N	\N	\N	Enfermero	2	\N	5
7	1	2	2	2019-04-09 09:00:00	20	Hep B 1ra dosis nacimiento	Completada	\N	2026-05-16 17:14:58.698042	\N	\N	\N	\N	Enfermero	2	\N	7
10	1	2	2	2021-02-25 09:00:00	20	Hep B 1ra dosis nacimiento	Completada	\N	2026-05-16 17:14:58.698042	\N	\N	\N	\N	Enfermero	2	\N	10
12	1	2	2	2019-10-16 09:00:00	20	BCG nacimiento	Completada	\N	2026-05-16 17:14:58.698042	\N	\N	\N	\N	Enfermero	2	\N	12
15	1	2	2	2021-04-11 09:00:00	20	BCG nacimiento	Completada	\N	2026-05-16 17:14:58.698042	\N	\N	\N	\N	Enfermero	2	\N	15
16	1	3	3	2026-05-18 08:00:00	20	\N	Programada	\N	2026-05-17 01:49:40.170568	444	\N	\N	\N	Administrador	1	\N	18
17	1	2	2	2026-05-18 08:00:00	20	\N	Cancelada	[2026-05-17] Cancelada. Motivo: Cancelada por tutor	2026-05-17 01:56:33.004647	448	\N	Cancelada por tutor	\N	Tutor	\N	20	18
18	1	2	2	2026-05-19 08:00:00	20	\N	Programada	\N	2026-05-17 02:04:21.257399	448	\N	\N	\N	Tutor	\N	20	18
19	1	2	2	2026-05-18 08:30:00	20	\N	Programada	\N	2026-05-17 13:22:47.83689	469	\N	\N	\N	Tutor	\N	20	19
20	1	3	2	2026-05-18 09:00:00	20	\N	Programada	\N	2026-05-17 13:31:55.843943	26	\N	\N	\N	Enfermero	2	\N	11
21	1	3	2	2026-05-18 09:30:00	20	\N	Programada	\N	2026-05-17 13:36:56.157824	16	\N	\N	\N	Enfermero	2	\N	1
\.


--
-- Data for Name: area_equipment; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.area_equipment (area_equipment_id, area_id, equipment_id, quantity, serial_number, condition) FROM stdin;
1	4	1	2	REF-2024-001	Bueno
2	4	6	1	CON-2023-002	Bueno
3	3	2	2	SIL-2022-003	Bueno
4	3	3	2	TER-2023-004	Bueno
5	3	4	1	BAS-2022-005	Regular
6	3	5	1	CAR-2024-006	Bueno
7	2	2	1	SIL-2021-007	Bueno
8	2	7	1	TEN-2023-008	Bueno
9	2	10	1	ESC-2020-009	Regular
10	9	1	1	REF-2024-010	Bueno
\.


--
-- Data for Name: audit_log; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.audit_log (audit_id, table_name, record_id, action, worker_id, changed_at, ip_address) FROM stdin;
2	vaccination_records	1	INSERT	\N	2026-05-16 17:25:31.438879	\N
3	vaccination_records	2	INSERT	\N	2026-05-16 17:25:31.438879	\N
4	vaccination_records	3	INSERT	\N	2026-05-16 17:25:31.438879	\N
5	vaccination_records	4	INSERT	\N	2026-05-16 17:25:31.438879	\N
6	vaccination_records	5	INSERT	\N	2026-05-16 17:25:31.438879	\N
7	vaccination_records	6	INSERT	\N	2026-05-16 17:25:31.438879	\N
8	vaccination_records	7	INSERT	\N	2026-05-16 17:25:31.438879	\N
9	vaccination_records	8	INSERT	\N	2026-05-16 17:25:31.438879	\N
10	vaccination_records	9	INSERT	\N	2026-05-16 17:25:31.438879	\N
11	vaccination_records	10	INSERT	\N	2026-05-16 17:25:31.438879	\N
12	vaccination_records	11	INSERT	\N	2026-05-16 17:25:31.438879	\N
13	vaccination_records	12	INSERT	\N	2026-05-16 17:25:31.438879	\N
14	vaccination_records	13	INSERT	\N	2026-05-16 17:25:31.438879	\N
15	vaccination_records	14	INSERT	\N	2026-05-16 17:25:31.438879	\N
16	vaccination_records	15	INSERT	\N	2026-05-16 17:25:31.438879	\N
17	vaccination_records	16	INSERT	\N	2026-05-16 17:25:31.438879	\N
18	vaccination_records	17	INSERT	\N	2026-05-16 17:25:31.438879	\N
19	vaccination_records	18	INSERT	\N	2026-05-16 17:25:31.438879	\N
20	vaccination_records	19	INSERT	\N	2026-05-16 17:25:31.438879	\N
21	vaccination_records	20	INSERT	\N	2026-05-16 17:25:31.438879	\N
22	vaccination_records	21	INSERT	\N	2026-05-16 17:25:31.438879	\N
23	vaccination_records	22	INSERT	\N	2026-05-16 17:25:31.438879	\N
24	vaccination_records	23	INSERT	\N	2026-05-16 17:25:31.438879	\N
25	vaccination_records	24	INSERT	\N	2026-05-16 17:25:31.438879	\N
26	vaccination_records	25	INSERT	\N	2026-05-16 17:25:31.438879	\N
27	vaccination_records	26	INSERT	\N	2026-05-16 17:25:31.438879	\N
28	vaccination_records	27	INSERT	\N	2026-05-16 17:25:31.438879	\N
29	vaccination_records	28	INSERT	\N	2026-05-16 17:25:31.438879	\N
30	vaccination_records	29	INSERT	\N	2026-05-16 17:25:31.438879	\N
31	vaccination_records	30	INSERT	\N	2026-05-16 17:25:31.438879	\N
32	vaccination_records	31	INSERT	\N	2026-05-16 17:25:31.438879	\N
33	vaccination_records	32	INSERT	\N	2026-05-16 17:25:31.438879	\N
34	vaccination_records	33	INSERT	\N	2026-05-16 17:25:31.438879	\N
35	vaccination_records	34	INSERT	\N	2026-05-16 17:25:31.438879	\N
36	vaccination_records	35	INSERT	\N	2026-05-16 17:25:31.438879	\N
37	vaccination_records	36	INSERT	\N	2026-05-16 17:25:31.438879	\N
38	vaccination_records	37	INSERT	\N	2026-05-16 17:25:31.438879	\N
39	vaccination_records	38	INSERT	\N	2026-05-16 17:25:31.438879	\N
40	vaccination_records	39	INSERT	\N	2026-05-16 17:25:31.438879	\N
41	vaccination_records	40	INSERT	\N	2026-05-16 17:25:31.438879	\N
42	vaccination_records	41	INSERT	\N	2026-05-16 17:25:31.438879	\N
43	vaccination_records	42	INSERT	\N	2026-05-16 17:25:31.438879	\N
44	vaccination_records	43	INSERT	\N	2026-05-16 17:25:31.438879	\N
45	vaccination_records	44	INSERT	\N	2026-05-16 17:25:31.438879	\N
46	vaccination_records	45	INSERT	\N	2026-05-16 17:25:31.438879	\N
47	vaccination_records	46	INSERT	\N	2026-05-16 17:25:31.438879	\N
48	vaccination_records	47	INSERT	\N	2026-05-16 17:25:31.438879	\N
49	vaccination_records	48	INSERT	\N	2026-05-16 17:25:31.438879	\N
50	vaccination_records	49	INSERT	\N	2026-05-16 17:25:31.438879	\N
51	vaccination_records	50	INSERT	\N	2026-05-16 17:25:31.438879	\N
52	vaccination_records	51	INSERT	\N	2026-05-16 17:25:31.438879	\N
53	vaccination_records	52	INSERT	\N	2026-05-16 17:25:31.438879	\N
54	vaccination_records	53	INSERT	\N	2026-05-16 17:25:31.438879	\N
55	vaccination_records	54	INSERT	\N	2026-05-16 17:25:31.438879	\N
56	vaccination_records	55	INSERT	\N	2026-05-16 17:25:31.438879	\N
57	vaccination_records	56	INSERT	\N	2026-05-16 17:25:31.438879	\N
58	vaccination_records	57	INSERT	\N	2026-05-16 17:25:31.438879	\N
59	vaccination_records	58	INSERT	\N	2026-05-16 17:25:31.438879	\N
60	vaccination_records	59	INSERT	\N	2026-05-16 17:25:31.438879	\N
61	vaccination_records	60	INSERT	\N	2026-05-16 17:25:31.438879	\N
62	vaccination_records	61	INSERT	\N	2026-05-16 17:25:31.438879	\N
63	vaccination_records	62	INSERT	\N	2026-05-16 17:25:31.438879	\N
64	vaccine_lots	8	UPDATE	\N	2026-05-16 17:25:31.438879	\N
65	vaccination_records	63	INSERT	\N	2026-05-16 17:25:31.438879	\N
66	vaccination_records	64	INSERT	\N	2026-05-16 17:25:31.438879	\N
67	vaccination_records	65	INSERT	\N	2026-05-16 17:25:31.438879	\N
68	vaccination_records	66	INSERT	\N	2026-05-16 17:25:31.438879	\N
69	vaccination_records	67	INSERT	\N	2026-05-16 17:25:31.438879	\N
70	vaccine_lots	8	UPDATE	\N	2026-05-16 17:25:31.438879	\N
71	vaccination_records	68	INSERT	\N	2026-05-16 17:25:31.438879	\N
72	vaccination_records	69	INSERT	\N	2026-05-16 17:25:31.438879	\N
73	vaccination_records	70	INSERT	\N	2026-05-16 17:25:31.438879	\N
74	vaccination_records	71	INSERT	\N	2026-05-16 17:25:31.438879	\N
75	vaccination_records	72	INSERT	\N	2026-05-16 17:25:31.438879	\N
76	vaccination_records	73	INSERT	\N	2026-05-16 17:25:31.438879	\N
77	vaccine_lots	8	UPDATE	\N	2026-05-16 17:25:31.438879	\N
78	vaccination_records	74	INSERT	\N	2026-05-16 17:25:31.438879	\N
79	vaccination_records	75	INSERT	\N	2026-05-16 17:25:31.438879	\N
80	vaccine_lots	8	UPDATE	\N	2026-05-16 17:25:31.438879	\N
81	vaccination_records	76	INSERT	\N	2026-05-16 17:25:31.438879	\N
82	vaccination_records	77	INSERT	\N	2026-05-16 17:25:31.438879	\N
83	vaccination_records	78	INSERT	\N	2026-05-16 17:25:31.438879	\N
84	vaccine_lots	8	UPDATE	\N	2026-05-16 17:25:31.438879	\N
85	vaccination_records	79	INSERT	\N	2026-05-16 17:25:31.438879	\N
86	vaccination_records	80	INSERT	\N	2026-05-16 17:25:31.438879	\N
87	vaccine_lots	8	UPDATE	\N	2026-05-16 17:25:31.438879	\N
88	vaccination_records	81	INSERT	\N	2026-05-16 17:25:31.438879	\N
89	vaccination_records	82	INSERT	\N	2026-05-16 17:25:31.438879	\N
90	vaccination_records	83	INSERT	\N	2026-05-16 17:25:31.438879	\N
91	vaccine_lots	8	UPDATE	\N	2026-05-16 17:25:31.438879	\N
92	vaccination_records	84	INSERT	\N	2026-05-16 17:25:31.438879	\N
93	vaccination_records	85	INSERT	\N	2026-05-16 17:25:31.438879	\N
94	vaccination_records	86	INSERT	\N	2026-05-16 17:25:31.438879	\N
95	vaccination_records	87	INSERT	\N	2026-05-16 17:25:31.438879	\N
96	vaccine_lots	8	UPDATE	\N	2026-05-16 17:25:31.438879	\N
97	vaccination_records	88	INSERT	\N	2026-05-16 17:25:31.438879	\N
98	vaccination_records	89	INSERT	\N	2026-05-16 17:25:31.438879	\N
99	vaccination_records	90	INSERT	\N	2026-05-16 17:25:31.438879	\N
100	vaccine_lots	8	UPDATE	\N	2026-05-16 17:25:31.438879	\N
101	vaccination_records	91	INSERT	\N	2026-05-16 17:25:31.438879	\N
102	vaccination_records	92	INSERT	\N	2026-05-16 17:25:31.438879	\N
103	vaccination_records	93	INSERT	\N	2026-05-16 17:25:31.438879	\N
104	vaccination_records	94	INSERT	\N	2026-05-16 17:25:31.438879	\N
105	vaccine_lots	8	UPDATE	\N	2026-05-16 17:25:31.438879	\N
106	vaccination_records	95	INSERT	\N	2026-05-16 17:25:31.438879	\N
107	vaccination_records	96	INSERT	\N	2026-05-16 17:25:31.438879	\N
108	workers	1	UPDATE	\N	2026-05-16 21:20:31.770927	\N
109	workers	2	UPDATE	\N	2026-05-16 21:20:31.867408	\N
110	workers	7	UPDATE	\N	2026-05-16 21:20:31.869825	\N
111	workers	9	UPDATE	\N	2026-05-16 21:20:31.871682	\N
112	workers	10	UPDATE	\N	2026-05-16 21:20:31.877963	\N
113	workers	11	UPDATE	\N	2026-05-16 21:20:31.879947	\N
114	workers	12	UPDATE	\N	2026-05-16 21:20:33.73647	\N
115	patients	16	INSERT	\N	2026-05-17 00:21:21.918684	\N
116	patients	17	INSERT	\N	2026-05-17 00:28:03.399482	\N
117	patients	16	UPDATE	\N	2026-05-17 00:31:35.731314	\N
118	patients	17	UPDATE	\N	2026-05-17 00:31:41.345002	\N
119	patients	18	INSERT	\N	2026-05-17 00:33:11.833123	\N
120	vaccination_records	97	INSERT	\N	2026-05-17 00:44:12.063684	\N
121	patients	19	INSERT	\N	2026-05-17 13:21:11.16144	\N
123	vaccine_lots	10	UPDATE	\N	2026-05-17 16:58:44.19143	\N
124	vaccination_records	98	INSERT	\N	2026-05-17 19:37:17.485671	\N
125	vaccination_records	99	INSERT	\N	2026-05-17 19:38:57.474474	\N
\.


--
-- Data for Name: blood_types; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.blood_types (blood_type_id, blood_type) FROM stdin;
1	A+
2	A-
3	B+
4	B-
5	AB+
6	AB-
7	O+
8	O-
\.


--
-- Data for Name: clinic_area_types; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.clinic_area_types (area_type_id, area_type, code) FROM stdin;
1	Sala de Espera	WAIT
2	Área de Vacunación	VACC
3	Consultorio	CONS
4	Enfermería	NURS
5	Recepción	RECP
6	Almacén	STOR
\.


--
-- Data for Name: clinic_areas; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.clinic_areas (area_id, clinic_id, name, area_type_id, floor, capacity, code) FROM stdin;
1	1	Sala de Espera Principal	1	1	30	WAIT-01
2	1	Consultorio 1 — Pediatría	2	1	4	CONS-01
3	1	Área de Vacunación	6	1	6	VACC-01
4	1	Almacén de Biológicos	4	1	2	STOR-01
5	1	Recepción	5	1	3	RECP-01
6	2	Sala de Espera A	1	1	25	WAIT-02
7	2	Consultorio 1 — Vacunación	2	1	4	CONS-02
8	2	Área de Vacunación	6	1	6	VACC-02
9	2	Almacén de Biológicos	4	1	2	STOR-02
10	3	Sala de Espera B	1	1	20	WAIT-03
11	3	Consultorio Pediátrico	2	1	4	CONS-03
12	3	Área de Vacunación	6	1	5	VACC-03
13	3	Sala de Espera C	1	1	20	WAIT-04
14	4	Área de Vacunación	6	1	5	VACC-04
15	4	Sala de Espera D	1	1	20	WAIT-05
16	4	Consultorio Pediátrico	2	1	4	CONS-04
\.


--
-- Data for Name: clinic_inventory; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.clinic_inventory (inventory_id, clinic_id, supply_id, quantity, min_stock, last_updated) FROM stdin;
1	1	1	500	100	2025-03-20
2	1	2	300	80	2025-03-20
3	1	3	800	200	2025-03-20
4	1	5	150	50	2025-03-20
5	1	7	400	100	2025-03-20
6	1	9	20	5	2025-03-20
7	2	1	350	80	2025-03-22
8	2	3	600	150	2025-03-22
9	2	5	120	40	2025-03-22
10	3	1	250	80	2025-03-18
11	3	3	400	100	2025-03-18
12	4	1	200	80	2025-03-15
\.


--
-- Data for Name: clinics; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.clinics (clinic_id, name, address_id, phone, institution_type, is_active) FROM stdin;
1	Clínica Immunicare Centro	1	81-2000-0101	SSA	t
2	Clínica Immunicare Monterrey	2	81-2000-0102	SSA	t
3	Clínica Immunicare Apodaca	3	81-2000-0103	SSA	t
4	Clínica Immunicare San Nicolás	4	81-2000-0104	SSA	t
5	Clínica Immunicare Guadalupe	5	81-2000-0105	SSA	t
6	Clínica Immunicare San Pedro	6	81-2000-0106	SSA	t
7	Clínica Immunicare Escobedo	7	81-2000-0107	SSA	t
8	Clínica Immunicare Santa Catarina	8	81-2000-0108	SSA	t
9	Clínica Immunicare Juárez	9	81-2000-0109	SSA	t
10	Clínica Immunicare Obispado	10	81-2000-0110	SSA	t
\.


--
-- Data for Name: countries; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.countries (country_id, name, iso_code) FROM stdin;
1	México	MX
2	Rusia	RU
3	Japón	JP
4	Alemania	DE
5	Reino Unido	GB
6	Francia	FR
7	Italia	IT
8	China	CN
\.


--
-- Data for Name: equipment_catalog; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.equipment_catalog (equipment_id, name, category, requires_calibration) FROM stdin;
1	Refrigerador Haier 2-8°C	Refrigeración	t
2	Silla de Exploración Pediátrica	Mobiliario	f
3	Termómetro Digital Infrarrojo	Diagnóstico	t
4	Báscula Pediátrica Digital	Diagnóstico	t
5	Carro de Vacunación	Mobiliario	f
6	Congelador de Vacunas -20°C	Refrigeración	t
7	Tensiómetro Pediátrico	Diagnóstico	t
8	Esterilizador UV portátil	Esterilización	t
9	Negatoscopio	Diagnóstico	f
10	Escritorio Clínico	Mobiliario	f
\.


--
-- Data for Name: guardian_accounts; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.guardian_accounts (guardian_account_id, guardian_id, email, password_hash, is_active, email_verified, last_login, created_at) FROM stdin;
1	1	carlos.garcia@gmail.com	$2a$06$UrM52TAg4n1r5YPCIQzrfeJMdx6UbSGp2oLE.yqmbpEvGGXXSU8HC	t	t	\N	2026-05-15 14:00:13.495052
3	20	mauricio.olvera@gmail.com	$2a$06$WpeLQlVpt2uR1xEbE00M2ecO9L/hhxuCLWb3Z6RSVymNfjdxTQ.2q	t	t	\N	2026-05-17 01:41:58.711997
\.


--
-- Data for Name: guardian_emails; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.guardian_emails (email_id, guardian_id, email, is_primary) FROM stdin;
1	1	carlos.garcia@gmail.com	t
2	2	maria.martinez@gmail.com	t
3	3	luis.lopez@gmail.com	t
4	4	ana.hernandez@gmail.com	t
5	5	jorge.ramirez@gmail.com	t
6	6	laura.torres@gmail.com	t
7	7	pedro.flores@gmail.com	t
8	8	elena.rivera@gmail.com	t
9	9	miguel.gomez@gmail.com	t
10	10	patricia.diaz@gmail.com	t
11	11	fernando.castro@gmail.com	t
12	12	gabriela.ortiz@gmail.com	t
13	13	ricardo.morales@gmail.com	t
14	14	daniela.ruiz@gmail.com	t
15	15	hugo.navarro@gmail.com	t
16	20	mauricio.olvera@gmail.com	t
\.


--
-- Data for Name: guardian_phones; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.guardian_phones (phone_id, guardian_id, phone, phone_type, is_primary) FROM stdin;
1	1	8110000001	Móvil	t
2	2	8110000002	Móvil	t
3	3	8110000003	Casa	t
4	4	8110000004	Móvil	t
5	5	8110000005	Trabajo	t
6	6	8110000006	Casa	t
7	7	8110000007	Móvil	t
8	8	8110000008	Trabajo	t
9	9	8110000009	Casa	t
10	10	8110000010	Móvil	t
11	11	8110000011	Trabajo	t
12	12	8110000012	Casa	t
13	13	8110000013	Móvil	t
14	14	8110000014	Trabajo	t
15	15	8110000015	Casa	t
20	20	8110000016	Celular	t
\.


--
-- Data for Name: guardians; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.guardians (guardian_id, first_name, last_name, curp, address_id, marital_status_id, occupation) FROM stdin;
1	Carlos	García	GACC850101HNLRRL01	1	2	1
2	María	Martínez	MARM860202MNLRRS02	2	2	2
3	Luis	López	LOLU870303HNLRPS03	3	1	3
4	Ana	Hernández	HEAA880404MNLRRN04	4	2	4
5	Jorge	Ramírez	RAJO890505HNLRMR05	5	2	5
6	Laura	Torres	TOLA900606MNLRRR06	6	1	6
7	Pedro	Flores	FOPP910707HNLRLD07	7	2	7
8	Elena	Rivera	RIEE920808MNLRVL08	8	2	8
9	Miguel	Gómez	GOMM930909HNLRMR09	9	1	9
10	Patricia	Díaz	DIPP941010MNLRZT10	10	2	10
11	Fernando	Castro	CAFF951111HNLRRS11	11	2	11
12	Gabriela	Ortiz	ORGG961212MNLRRB12	12	1	12
13	Ricardo	Morales	MORR970101HNLRRC13	13	2	13
14	Daniela	Ruiz	RUDD980202MNLRZN14	14	2	14
15	Hugo	Navarro	NAHH990303HNLRVG15	15	1	15
20	Mauricio	Olvera	MAUO103954MAKDLQ21	\N	\N	\N
\.


--
-- Data for Name: institutions; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.institutions (institution_id, institution_name, address_id) FROM stdin;
1	UANL	1
2	UNAM	2
3	IPN	3
4	TEC	4
5	UDEM	5
6	BUAP	6
7	UDG	7
\.


--
-- Data for Name: inventory_movements; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.inventory_movements (movement_id, lot_id, vaccine_id, clinic_id, worker_id, movement_type, quantity, quantity_before, quantity_after, reference_id, reference_type, reason, created_at) FROM stdin;
281	1	1	1	3	Salida_Aplicacion	1	171	170	1	vaccination_record	\N	2026-05-16 17:25:31.438879
282	2	2	1	3	Salida_Aplicacion	1	115	114	2	vaccination_record	\N	2026-05-16 17:25:31.438879
283	3	3	1	3	Salida_Aplicacion	1	78	77	3	vaccination_record	\N	2026-05-16 17:25:31.438879
284	4	4	1	3	Salida_Aplicacion	1	90	89	4	vaccination_record	\N	2026-05-16 17:25:31.438879
285	5	5	1	3	Salida_Aplicacion	1	55	54	5	vaccination_record	\N	2026-05-16 17:25:31.438879
286	6	6	1	3	Salida_Aplicacion	1	85	84	6	vaccination_record	\N	2026-05-16 17:25:31.438879
287	3	3	1	3	Salida_Aplicacion	1	77	76	7	vaccination_record	\N	2026-05-16 17:25:31.438879
288	5	5	1	3	Salida_Aplicacion	1	54	53	8	vaccination_record	\N	2026-05-16 17:25:31.438879
289	6	6	1	3	Salida_Aplicacion	1	84	83	9	vaccination_record	\N	2026-05-16 17:25:31.438879
290	3	3	1	2	Salida_Aplicacion	1	76	75	10	vaccination_record	\N	2026-05-16 17:25:31.438879
291	4	4	1	2	Salida_Aplicacion	1	89	88	11	vaccination_record	\N	2026-05-16 17:25:31.438879
292	5	5	1	2	Salida_Aplicacion	1	53	52	12	vaccination_record	\N	2026-05-16 17:25:31.438879
293	7	7	1	2	Salida_Aplicacion	1	151	150	13	vaccination_record	\N	2026-05-16 17:25:31.438879
294	7	7	1	2	Salida_Aplicacion	1	150	149	14	vaccination_record	\N	2026-05-16 17:25:31.438879
295	8	8	1	3	Salida_Aplicacion	1	24	23	15	vaccination_record	\N	2026-05-16 17:25:31.438879
296	6	6	1	3	Salida_Aplicacion	1	83	82	16	vaccination_record	\N	2026-05-16 17:25:31.438879
297	9	9	2	3	Salida_Aplicacion	1	61	60	17	vaccination_record	\N	2026-05-16 17:25:31.438879
298	7	7	1	3	Salida_Aplicacion	1	149	148	18	vaccination_record	\N	2026-05-16 17:25:31.438879
299	1	1	1	3	Salida_Aplicacion	1	170	169	19	vaccination_record	\N	2026-05-16 17:25:31.438879
300	2	2	1	3	Salida_Aplicacion	1	114	113	20	vaccination_record	\N	2026-05-16 17:25:31.438879
301	6	6	1	3	Salida_Aplicacion	1	82	81	21	vaccination_record	\N	2026-05-16 17:25:31.438879
302	8	8	1	3	Salida_Aplicacion	1	23	22	22	vaccination_record	\N	2026-05-16 17:25:31.438879
303	9	9	2	3	Salida_Aplicacion	1	60	59	23	vaccination_record	\N	2026-05-16 17:25:31.438879
304	10	10	2	3	Salida_Aplicacion	1	53	52	24	vaccination_record	\N	2026-05-16 17:25:31.438879
305	8	8	1	3	Salida_Aplicacion	1	22	21	25	vaccination_record	\N	2026-05-16 17:25:31.438879
306	1	1	1	3	Salida_Aplicacion	1	169	168	26	vaccination_record	\N	2026-05-16 17:25:31.438879
307	2	2	1	3	Salida_Aplicacion	1	113	112	27	vaccination_record	\N	2026-05-16 17:25:31.438879
308	6	6	1	3	Salida_Aplicacion	1	81	80	28	vaccination_record	\N	2026-05-16 17:25:31.438879
309	8	8	1	3	Salida_Aplicacion	1	21	20	29	vaccination_record	\N	2026-05-16 17:25:31.438879
310	9	9	2	3	Salida_Aplicacion	1	59	58	30	vaccination_record	\N	2026-05-16 17:25:31.438879
311	8	8	1	3	Salida_Aplicacion	1	20	19	31	vaccination_record	\N	2026-05-16 17:25:31.438879
312	1	1	1	2	Salida_Aplicacion	1	168	167	32	vaccination_record	\N	2026-05-16 17:25:31.438879
313	3	3	1	2	Salida_Aplicacion	1	75	74	33	vaccination_record	\N	2026-05-16 17:25:31.438879
314	6	6	1	2	Salida_Aplicacion	1	80	79	34	vaccination_record	\N	2026-05-16 17:25:31.438879
315	8	8	1	2	Salida_Aplicacion	1	19	18	35	vaccination_record	\N	2026-05-16 17:25:31.438879
316	10	10	2	2	Salida_Aplicacion	1	52	51	36	vaccination_record	\N	2026-05-16 17:25:31.438879
317	2	2	1	3	Salida_Aplicacion	1	112	111	37	vaccination_record	\N	2026-05-16 17:25:31.438879
318	4	4	1	3	Salida_Aplicacion	1	88	87	38	vaccination_record	\N	2026-05-16 17:25:31.438879
319	8	8	1	3	Salida_Aplicacion	1	18	17	39	vaccination_record	\N	2026-05-16 17:25:31.438879
320	9	9	2	3	Salida_Aplicacion	1	58	57	40	vaccination_record	\N	2026-05-16 17:25:31.438879
321	8	8	1	3	Salida_Aplicacion	1	17	16	41	vaccination_record	\N	2026-05-16 17:25:31.438879
322	1	1	1	2	Salida_Aplicacion	1	167	166	42	vaccination_record	\N	2026-05-16 17:25:31.438879
323	3	3	1	2	Salida_Aplicacion	1	74	73	43	vaccination_record	\N	2026-05-16 17:25:31.438879
324	5	5	1	2	Salida_Aplicacion	1	52	51	44	vaccination_record	\N	2026-05-16 17:25:31.438879
325	3	3	1	2	Salida_Aplicacion	1	73	72	45	vaccination_record	\N	2026-05-16 17:25:31.438879
326	8	8	1	2	Salida_Aplicacion	1	16	15	46	vaccination_record	\N	2026-05-16 17:25:31.438879
327	9	9	2	2	Salida_Aplicacion	1	57	56	47	vaccination_record	\N	2026-05-16 17:25:31.438879
328	10	10	2	2	Salida_Aplicacion	1	51	50	48	vaccination_record	\N	2026-05-16 17:25:31.438879
329	1	1	1	3	Salida_Aplicacion	1	166	165	49	vaccination_record	\N	2026-05-16 17:25:31.438879
330	6	6	1	3	Salida_Aplicacion	1	79	78	50	vaccination_record	\N	2026-05-16 17:25:31.438879
331	8	8	1	3	Salida_Aplicacion	1	15	14	51	vaccination_record	\N	2026-05-16 17:25:31.438879
332	6	6	1	3	Salida_Aplicacion	1	78	77	52	vaccination_record	\N	2026-05-16 17:25:31.438879
333	10	10	2	3	Salida_Aplicacion	1	50	49	53	vaccination_record	\N	2026-05-16 17:25:31.438879
334	8	8	1	3	Salida_Aplicacion	1	14	13	54	vaccination_record	\N	2026-05-16 17:25:31.438879
335	2	2	1	2	Salida_Aplicacion	1	111	110	55	vaccination_record	\N	2026-05-16 17:25:31.438879
336	3	3	1	2	Salida_Aplicacion	1	72	71	56	vaccination_record	\N	2026-05-16 17:25:31.438879
337	8	8	1	2	Salida_Aplicacion	1	13	12	57	vaccination_record	\N	2026-05-16 17:25:31.438879
338	9	9	2	2	Salida_Aplicacion	1	56	55	58	vaccination_record	\N	2026-05-16 17:25:31.438879
339	8	8	1	2	Salida_Aplicacion	1	12	11	59	vaccination_record	\N	2026-05-16 17:25:31.438879
340	1	1	1	3	Salida_Aplicacion	1	165	164	60	vaccination_record	\N	2026-05-16 17:25:31.438879
341	6	6	1	3	Salida_Aplicacion	1	77	76	61	vaccination_record	\N	2026-05-16 17:25:31.438879
342	8	8	1	3	Salida_Aplicacion	1	11	10	62	vaccination_record	\N	2026-05-16 17:25:31.438879
343	9	9	2	3	Salida_Aplicacion	1	55	54	63	vaccination_record	\N	2026-05-16 17:25:31.438879
344	10	10	2	3	Salida_Aplicacion	1	49	48	64	vaccination_record	\N	2026-05-16 17:25:31.438879
345	2	2	1	2	Salida_Aplicacion	1	110	109	65	vaccination_record	\N	2026-05-16 17:25:31.438879
346	5	5	1	2	Salida_Aplicacion	1	51	50	66	vaccination_record	\N	2026-05-16 17:25:31.438879
347	8	8	1	2	Salida_Aplicacion	1	10	9	67	vaccination_record	\N	2026-05-16 17:25:31.438879
348	9	9	2	2	Salida_Aplicacion	1	54	53	68	vaccination_record	\N	2026-05-16 17:25:31.438879
349	10	10	2	2	Salida_Aplicacion	1	48	47	69	vaccination_record	\N	2026-05-16 17:25:31.438879
350	1	1	1	3	Salida_Aplicacion	1	164	163	70	vaccination_record	\N	2026-05-16 17:25:31.438879
351	3	3	1	3	Salida_Aplicacion	1	71	70	71	vaccination_record	\N	2026-05-16 17:25:31.438879
352	7	7	1	3	Salida_Aplicacion	1	148	147	72	vaccination_record	\N	2026-05-16 17:25:31.438879
353	8	8	1	3	Salida_Aplicacion	1	9	8	73	vaccination_record	\N	2026-05-16 17:25:31.438879
354	10	10	2	3	Salida_Aplicacion	1	47	46	74	vaccination_record	\N	2026-05-16 17:25:31.438879
355	8	8	1	3	Salida_Aplicacion	1	8	7	75	vaccination_record	\N	2026-05-16 17:25:31.438879
356	1	1	1	2	Salida_Aplicacion	1	163	162	76	vaccination_record	\N	2026-05-16 17:25:31.438879
357	6	6	1	2	Salida_Aplicacion	1	76	75	77	vaccination_record	\N	2026-05-16 17:25:31.438879
358	8	8	1	2	Salida_Aplicacion	1	7	6	78	vaccination_record	\N	2026-05-16 17:25:31.438879
359	6	6	1	2	Salida_Aplicacion	1	75	74	79	vaccination_record	\N	2026-05-16 17:25:31.438879
360	8	8	1	2	Salida_Aplicacion	1	6	5	80	vaccination_record	\N	2026-05-16 17:25:31.438879
361	3	3	1	3	Salida_Aplicacion	1	70	69	81	vaccination_record	\N	2026-05-16 17:25:31.438879
362	6	6	1	3	Salida_Aplicacion	1	74	73	82	vaccination_record	\N	2026-05-16 17:25:31.438879
363	8	8	1	3	Salida_Aplicacion	1	5	4	83	vaccination_record	\N	2026-05-16 17:25:31.438879
364	9	9	2	3	Salida_Aplicacion	1	53	52	84	vaccination_record	\N	2026-05-16 17:25:31.438879
365	10	10	2	3	Salida_Aplicacion	1	46	45	85	vaccination_record	\N	2026-05-16 17:25:31.438879
366	1	1	1	3	Salida_Aplicacion	1	162	161	86	vaccination_record	\N	2026-05-16 17:25:31.438879
367	8	8	1	3	Salida_Aplicacion	1	4	3	87	vaccination_record	\N	2026-05-16 17:25:31.438879
368	9	9	2	3	Salida_Aplicacion	1	52	51	88	vaccination_record	\N	2026-05-16 17:25:31.438879
369	10	10	2	3	Salida_Aplicacion	1	45	44	89	vaccination_record	\N	2026-05-16 17:25:31.438879
370	8	8	1	3	Salida_Aplicacion	1	3	2	90	vaccination_record	\N	2026-05-16 17:25:31.438879
371	1	1	1	2	Salida_Aplicacion	1	161	160	91	vaccination_record	\N	2026-05-16 17:25:31.438879
372	5	5	1	2	Salida_Aplicacion	1	50	49	92	vaccination_record	\N	2026-05-16 17:25:31.438879
373	6	6	1	2	Salida_Aplicacion	1	73	72	93	vaccination_record	\N	2026-05-16 17:25:31.438879
374	8	8	1	2	Salida_Aplicacion	1	2	1	94	vaccination_record	\N	2026-05-16 17:25:31.438879
375	9	9	2	2	Salida_Aplicacion	1	51	50	95	vaccination_record	\N	2026-05-16 17:25:31.438879
376	10	10	2	2	Salida_Aplicacion	1	44	43	96	vaccination_record	\N	2026-05-16 17:25:31.438879
377	13	1	1	3	Salida_Aplicacion	1	100	99	97	vaccination_record	\N	2026-05-17 00:44:12.063684
378	14	1	1	1	Entrada	100	0	100	\N	manual	Recepci¢n inicial de lote	2026-05-17 14:22:57.668176
379	14	1	1	1	Salida_Aplicacion	10	100	90	\N	manual	Aplicaciones jornada vacunaci¢n	2026-04-27 14:23:04.932737
380	14	1	1	1	Salida_Aplicacion	12	90	78	\N	manual	Aplicaciones semana 2	2026-05-04 14:23:10.889626
381	14	1	1	1	Salida_Merma	3	78	75	\N	manual	Frascos da¤ados en refrigeraci¢n	2026-05-10 14:23:18.596383
382	14	1	1	1	Ajuste_Positivo	3	69	72	\N	manual	Correcci¢n de conteo f¡sico	2026-05-14 14:23:29.514421
383	15	2	1	1	Entrada	50	0	50	\N	manual	Recepci¢n inicial de lote BCG	2026-03-18 14:23:29.521793
384	15	2	1	1	Salida_Aplicacion	42	50	8	\N	manual	Aplicaciones acumuladas	2026-05-12 14:23:29.528277
385	18	4	1	1	Salida_Caducidad	40	40	0	\N	manual	Retiro de lote vencido por control de calidad	2026-05-08 14:23:29.536019
386	10	10	2	5	Transferencia_Salida	30	43	13	5	transfer	Transferencia #5 aceptada	2026-05-17 16:40:15.753618
387	10	10	1	5	Transferencia_Entrada	30	0	30	5	transfer	Transferencia #5 recibida	2026-05-17 16:40:15.753618
388	10	10	2	5	Transferencia_Salida	6	13	7	6	transfer	Transferencia #6 aceptada	2026-05-17 16:58:44.19143
389	22	10	1	5	Transferencia_Entrada	6	0	6	6	transfer	Transferencia #6 recibida	2026-05-17 16:58:44.19143
390	2	2	1	3	Salida_Aplicacion	1	109	108	98	vaccination_record	\N	2026-05-17 19:37:17.485671
391	4	4	1	3	Salida_Aplicacion	1	87	86	99	vaccination_record	\N	2026-05-17 19:38:57.474474
\.


--
-- Data for Name: inventory_transfers; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.inventory_transfers (transfer_id, lot_id, vaccine_id, from_clinic_id, to_clinic_id, quantity, transfer_status, requested_by, approved_by, reason, notes, requested_at, resolved_at) FROM stdin;
1	14	1	1	2	20	Pendiente	1	\N	Redistribuci¢n por exceso de stock en cl¡nica Norte	\N	2026-05-15 14:23:42.003867	\N
2	16	3	1	2	15	Recibido	1	1	Cobertura campa¤a vacunaci¢n cl¡nica Sur	Recibido en buen estado, cadena de fr¡o conservada	2026-05-02 14:23:42.01458	2026-05-04 14:23:42.01458
3	15	2	2	1	10	Rechazado	1	1	Pr‚stamo temporal por campa¤a	Stock insuficiente en cl¡nica origen para cubrir la solicitud	2026-05-09 14:23:42.025212	2026-05-10 14:23:42.025212
4	14	1	1	2	5	Cancelado	1	\N	Solicitud por error de sistema	\N	2026-04-27 14:23:43.30961	2026-04-28 14:23:43.30961
5	10	10	2	1	30	Recibido	5	5	Redistribución por falta de stock en clinica de destino	Buen estado	2026-05-17 16:38:58.742246	2026-05-17 16:40:15.753618
6	10	10	2	1	6	Recibido	1	5	Stock insuficiente	Buen estado	2026-05-17 16:53:29.194432	2026-05-17 16:58:44.19143
\.


--
-- Data for Name: manufacturers; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.manufacturers (manufacturer_id, name, country_id, contact_email) FROM stdin;
1	Pfizer	1	pfizer@gmail.com
2	AstraZeneca	5	astra@mail.com
3	Sanofi	6	sanofi@gmail.com
4	GSK	5	gsk@mail.com
5	Bayer	4	bayer@mail.com
6	BioNTech	4	bio@gmail.com
7	Sinovac	8	sino@mail.com
8	Sputnik	2	sputnik@gmail.com
9	Abbott	2	abbott@gmail.com
10	Takeda	3	takeda@mail.com
\.


--
-- Data for Name: marital_status; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.marital_status (marital_status_id, marital_status) FROM stdin;
1	Soltero
2	Casado
3	Divorciado
4	Viudo
\.


--
-- Data for Name: municipalities; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.municipalities (municipality_id, state_id, name) FROM stdin;
1	1	Monterrey
2	2	Guadalajara
3	3	Benito Juárez
4	4	Saltillo
5	5	Reynosa
6	6	Hermosillo
7	7	Chihuahua
8	8	Mérida
9	9	Puebla
10	10	Querétaro
\.


--
-- Data for Name: neighborhoods; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.neighborhoods (neighborhood_id, municipality_id, name, zip_code) FROM stdin;
1	1	Centro	64000
2	1	Monterrey	64010
3	1	Apodaca	66600
4	1	San Nicolás de los Garza	64020
5	1	Guadalupe	64030
6	1	San Pedro Garza García	64040
7	1	Escobedo	64050
8	1	Santa Catarina	64060
9	1	Cuauhtémoc	64070
10	1	García	64080
11	1	Cadereyta Jiménez	64090
12	1	Santiago	64100
13	1	Allende	64120
14	1	Anáhuac	64130
15	2	Americana	44160
16	3	Del Valle	03100
17	4	República	25280
18	5	Vista Hermosa	88710
19	6	Centro	83000
20	7	Panamericana	31210
21	8	Montecristo	97133
22	9	La Paz	72160
23	10	Juriquilla	76230
\.


--
-- Data for Name: nfc_cards; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.nfc_cards (nfc_card_id, patient_id, uid, card_type, issued_date, issued_by, status, last_scanned_at, nfc_card_notes) FROM stdin;
\.


--
-- Data for Name: nfc_devices; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.nfc_devices (device_id, clinic_id, area_id, device_name, model, serial_number, nfc_device_status, registered_at) FROM stdin;
TABLET-REC-01	1	5	Recepción Principal Sede Centro	ACR122U	SN-001	Activo	2023-01-10
TABLET-VAC-01	1	3	Área Vacunación Sede Centro	ACR1252U	SN-002	Activo	2023-01-10
TABLET-REC-02	2	6	Recepción Sede Apodaca	ACR122U	SN-003	Activo	2023-06-15
TABLET-VAC-02	2	8	Área Vacunación Sede Apodaca	ACR1252U	SN-004	Activo	2023-06-15
TABLET-REC-03	3	10	Recepción Sede San Nicolás	ACR122U	SN-005	Activo	2023-09-01
TABLET-VAC-03	3	12	Área Vacunación Sede San Nicolás	ACR1252U	SN-006	Activo	2023-09-01
TABLET-REC-04	4	13	Recepción Sede Guadalupe	ACR122U	SN-007	Activo	2024-01-15
TABLET-VAC-04	4	14	Área Vacunación Sede Guadalupe	ACR1252U	SN-008	Activo	2024-01-15
TABLET-REC-05	5	15	Recepción Sede San Pedro	ACR122U	SN-009	Activo	2024-03-01
TABLET-CONS-01	1	2	Consultorio 1 Sede Centro	ACR1252U	SN-010	Activo	2023-01-10
\.


--
-- Data for Name: nfc_scan_events; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.nfc_scan_events (scan_event_id, nfc_card_id, scanned_by, clinic_id, area_id, scanned_at, action_triggered, device_id, nfc_scan_result, visit_id, scan_context, resolved_action, error_reason) FROM stdin;
\.


--
-- Data for Name: occupations; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.occupations (occupation_id, occupation_name) FROM stdin;
1	Ingeniero
2	Doctor
3	Maestro
4	Abogado
5	Contador
6	Arquitecto
7	Enfermero
8	Chofer
9	Chef
10	Programador
11	Diseñador
12	Comerciante
13	Mecánico
14	Psicólogo
15	Administrador
\.


--
-- Data for Name: patient_allergies; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.patient_allergies (patient_allergy_id, patient_id, allergy_id, severity, reaction_desc) FROM stdin;
1	3	2	Moderada	Eritema cutáneo en zona de aplicación
2	5	4	Leve	Urticaria leve post-ingesta
3	7	3	Severa	Anafilaxia documentada en 2020
4	9	1	Moderada	Erupción cutánea y prurito generalizado
5	11	5	Leve	Náuseas leves
6	13	6	Leve	Estornudos y lagrimeo
7	14	8	Moderada	Dolor abdominal e inflamación
10	8	10	Leve	Eritema leve
11	10	11	Moderada	Diarrea y dolor abdominal
12	12	12	Leve	Irritación cutánea leve
13	1	13	Moderada	Inflamación local y fiebre
14	4	14	Leve	Estornudos y congestión nasal
15	15	15	Severa	Anafilaxia documentada en 2021
\.


--
-- Data for Name: patient_clinic_visits; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.patient_clinic_visits (visit_id, patient_id, clinic_id, appointment_id, visit_status, current_area_id, assigned_worker_id, checked_in_at, waiting_since, consultation_start, vaccination_start, checked_out_at, checkin_by_worker_id, checkout_by_worker_id, checkin_nfc_scan_id, checkout_nfc_scan_id, visit_type, visit_notes, created_at, updated_at) FROM stdin;
\.


--
-- Data for Name: patient_guardian_relations; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.patient_guardian_relations (relation_id, patient_id, guardian_id, relation_type, is_primary, has_custody) FROM stdin;
1	1	1	Padre	t	t
2	2	2	Madre	t	t
3	3	3	Padre	t	t
4	4	4	Madre	t	t
5	5	5	Padre	t	t
6	6	6	Madre	t	t
7	7	7	Padre	t	t
8	8	8	Madre	t	t
9	9	9	Padre	t	t
10	10	10	Madre	t	t
11	11	11	Padre	t	t
12	12	12	Madre	t	t
13	13	13	Padre	t	t
14	14	14	Madre	t	t
15	15	15	Padre	t	t
16	16	20	Tutor	t	t
17	17	20	Tutor	t	t
18	18	20	Tutor	t	t
19	19	20	Tutor	t	t
\.


--
-- Data for Name: patient_vaccine_schedule; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.patient_vaccine_schedule (schedule_id, patient_id, scheme_dose_id, due_date, status, updated_at) FROM stdin;
2	2	1	2019-07-20	Atrasada	2026-05-15 14:12:15.481805
3	3	1	2020-01-10	Atrasada	2026-05-15 14:12:15.481805
4	4	1	2017-11-05	Atrasada	2026-05-15 14:12:15.481805
5	5	1	2021-06-12	Atrasada	2026-05-15 14:12:15.481805
6	6	1	2018-08-18	Atrasada	2026-05-15 14:12:15.481805
7	7	1	2019-04-09	Atrasada	2026-05-15 14:12:15.481805
8	8	1	2020-09-14	Atrasada	2026-05-15 14:12:15.481805
9	9	1	2017-12-30	Atrasada	2026-05-15 14:12:15.481805
10	10	1	2021-02-25	Atrasada	2026-05-15 14:12:15.481805
11	11	1	2018-05-03	Atrasada	2026-05-15 14:12:15.481805
12	12	1	2019-10-16	Atrasada	2026-05-15 14:12:15.481805
13	13	1	2020-07-01	Atrasada	2026-05-15 14:12:15.481805
14	14	1	2017-09-27	Atrasada	2026-05-15 14:12:15.481805
16	1	2	2018-03-15	Atrasada	2026-05-15 14:12:15.481805
18	3	2	2020-01-10	Atrasada	2026-05-15 14:12:15.481805
19	4	2	2017-11-05	Atrasada	2026-05-15 14:12:15.481805
20	5	2	2021-06-12	Atrasada	2026-05-15 14:12:15.481805
21	6	2	2018-08-18	Atrasada	2026-05-15 14:12:15.481805
22	7	2	2019-04-09	Atrasada	2026-05-15 14:12:15.481805
24	9	2	2017-12-30	Atrasada	2026-05-15 14:12:15.481805
25	10	2	2021-02-25	Atrasada	2026-05-15 14:12:15.481805
26	11	2	2018-05-03	Atrasada	2026-05-15 14:12:15.481805
27	12	2	2019-10-16	Atrasada	2026-05-15 14:12:15.481805
28	13	2	2020-07-01	Atrasada	2026-05-15 14:12:15.481805
29	14	2	2017-09-27	Atrasada	2026-05-15 14:12:15.481805
30	15	2	2021-04-11	Atrasada	2026-05-15 14:12:15.481805
31	1	3	2018-05-15	Atrasada	2026-05-15 14:12:15.481805
32	2	3	2019-09-20	Atrasada	2026-05-15 14:12:15.481805
34	4	3	2018-01-05	Atrasada	2026-05-15 14:12:15.481805
35	5	3	2021-08-12	Atrasada	2026-05-15 14:12:15.481805
36	6	3	2018-10-18	Atrasada	2026-05-15 14:12:15.481805
37	7	3	2019-06-09	Atrasada	2026-05-15 14:12:15.481805
38	8	3	2020-11-14	Atrasada	2026-05-15 14:12:15.481805
39	9	3	2018-02-28	Atrasada	2026-05-15 14:12:15.481805
40	10	3	2021-04-25	Atrasada	2026-05-15 14:12:15.481805
41	11	3	2018-07-03	Atrasada	2026-05-15 14:12:15.481805
42	12	3	2019-12-16	Atrasada	2026-05-15 14:12:15.481805
43	13	3	2020-09-01	Atrasada	2026-05-15 14:12:15.481805
44	14	3	2017-11-27	Atrasada	2026-05-15 14:12:15.481805
45	15	3	2021-06-11	Atrasada	2026-05-15 14:12:15.481805
46	1	4	2018-05-15	Atrasada	2026-05-15 14:12:15.481805
47	2	4	2019-09-20	Atrasada	2026-05-15 14:12:15.481805
48	3	4	2020-03-10	Atrasada	2026-05-15 14:12:15.481805
50	5	4	2021-08-12	Atrasada	2026-05-15 14:12:15.481805
51	6	4	2018-10-18	Atrasada	2026-05-15 14:12:15.481805
52	7	4	2019-06-09	Atrasada	2026-05-15 14:12:15.481805
54	9	4	2018-02-28	Atrasada	2026-05-15 14:12:15.481805
55	10	4	2021-04-25	Atrasada	2026-05-15 14:12:15.481805
56	11	4	2018-07-03	Atrasada	2026-05-15 14:12:15.481805
57	12	4	2019-12-16	Atrasada	2026-05-15 14:12:15.481805
58	13	4	2020-09-01	Atrasada	2026-05-15 14:12:15.481805
59	14	4	2017-11-27	Atrasada	2026-05-15 14:12:15.481805
60	15	4	2021-06-11	Atrasada	2026-05-15 14:12:15.481805
61	1	5	2018-05-15	Atrasada	2026-05-15 14:12:15.481805
62	2	5	2019-09-20	Atrasada	2026-05-15 14:12:15.481805
63	3	5	2020-03-10	Atrasada	2026-05-15 14:12:15.481805
64	4	5	2018-01-05	Atrasada	2026-05-15 14:12:15.481805
66	6	5	2018-10-18	Atrasada	2026-05-15 14:12:15.481805
67	7	5	2019-06-09	Atrasada	2026-05-15 14:12:15.481805
68	8	5	2020-11-14	Atrasada	2026-05-15 14:12:15.481805
69	9	5	2018-02-28	Atrasada	2026-05-15 14:12:15.481805
70	10	5	2021-04-25	Atrasada	2026-05-15 14:12:15.481805
71	11	5	2018-07-03	Atrasada	2026-05-15 14:12:15.481805
72	12	5	2019-12-16	Atrasada	2026-05-15 14:12:15.481805
73	13	5	2020-09-01	Atrasada	2026-05-15 14:12:15.481805
74	14	5	2017-11-27	Atrasada	2026-05-15 14:12:15.481805
75	15	5	2021-06-11	Atrasada	2026-05-15 14:12:15.481805
76	1	6	2018-05-15	Atrasada	2026-05-15 14:12:15.481805
77	2	6	2019-09-20	Atrasada	2026-05-15 14:12:15.481805
78	3	6	2020-03-10	Atrasada	2026-05-15 14:12:15.481805
79	4	6	2018-01-05	Atrasada	2026-05-15 14:12:15.481805
80	5	6	2021-08-12	Atrasada	2026-05-15 14:12:15.481805
82	7	6	2019-06-09	Atrasada	2026-05-15 14:12:15.481805
83	8	6	2020-11-14	Atrasada	2026-05-15 14:12:15.481805
84	9	6	2018-02-28	Atrasada	2026-05-15 14:12:15.481805
85	10	6	2021-04-25	Atrasada	2026-05-15 14:12:15.481805
86	11	6	2018-07-03	Atrasada	2026-05-15 14:12:15.481805
87	12	6	2019-12-16	Atrasada	2026-05-15 14:12:15.481805
88	13	6	2020-09-01	Atrasada	2026-05-15 14:12:15.481805
89	14	6	2017-11-27	Atrasada	2026-05-15 14:12:15.481805
90	15	6	2021-06-11	Atrasada	2026-05-15 14:12:15.481805
91	1	7	2018-07-15	Atrasada	2026-05-15 14:12:15.481805
92	2	7	2019-11-20	Atrasada	2026-05-15 14:12:15.481805
93	3	7	2020-05-10	Atrasada	2026-05-15 14:12:15.481805
94	4	7	2018-03-05	Atrasada	2026-05-15 14:12:15.481805
95	5	7	2021-10-12	Atrasada	2026-05-15 14:12:15.481805
96	6	7	2018-12-18	Atrasada	2026-05-15 14:12:15.481805
98	8	7	2021-01-14	Atrasada	2026-05-15 14:12:15.481805
99	9	7	2018-04-30	Atrasada	2026-05-15 14:12:15.481805
100	10	7	2021-06-25	Atrasada	2026-05-15 14:12:15.481805
101	11	7	2018-09-03	Atrasada	2026-05-15 14:12:15.481805
102	12	7	2020-02-16	Atrasada	2026-05-15 14:12:15.481805
103	13	7	2020-11-01	Atrasada	2026-05-15 14:12:15.481805
104	14	7	2018-01-27	Atrasada	2026-05-15 14:12:15.481805
105	15	7	2021-08-11	Atrasada	2026-05-15 14:12:15.481805
106	1	8	2018-07-15	Atrasada	2026-05-15 14:12:15.481805
107	2	8	2019-11-20	Atrasada	2026-05-15 14:12:15.481805
108	3	8	2020-05-10	Atrasada	2026-05-15 14:12:15.481805
109	4	8	2018-03-05	Atrasada	2026-05-15 14:12:15.481805
110	5	8	2021-10-12	Atrasada	2026-05-15 14:12:15.481805
111	6	8	2018-12-18	Atrasada	2026-05-15 14:12:15.481805
112	7	8	2019-08-09	Atrasada	2026-05-15 14:12:15.481805
114	9	8	2018-04-30	Atrasada	2026-05-15 14:12:15.481805
115	10	8	2021-06-25	Atrasada	2026-05-15 14:12:15.481805
116	11	8	2018-09-03	Atrasada	2026-05-15 14:12:15.481805
117	12	8	2020-02-16	Atrasada	2026-05-15 14:12:15.481805
118	13	8	2020-11-01	Atrasada	2026-05-15 14:12:15.481805
119	14	8	2018-01-27	Atrasada	2026-05-15 14:12:15.481805
120	15	8	2021-08-11	Atrasada	2026-05-15 14:12:15.481805
23	8	2	2020-09-14	Aplicada	2026-05-17 19:37:17.485671
53	8	4	2020-11-14	Aplicada	2026-05-17 19:38:57.474474
121	1	9	2018-07-15	Atrasada	2026-05-15 14:12:15.481805
122	2	9	2019-11-20	Atrasada	2026-05-15 14:12:15.481805
123	3	9	2020-05-10	Atrasada	2026-05-15 14:12:15.481805
124	4	9	2018-03-05	Atrasada	2026-05-15 14:12:15.481805
125	5	9	2021-10-12	Atrasada	2026-05-15 14:12:15.481805
126	6	9	2018-12-18	Atrasada	2026-05-15 14:12:15.481805
127	7	9	2019-08-09	Atrasada	2026-05-15 14:12:15.481805
128	8	9	2021-01-14	Atrasada	2026-05-15 14:12:15.481805
130	10	9	2021-06-25	Atrasada	2026-05-15 14:12:15.481805
131	11	9	2018-09-03	Atrasada	2026-05-15 14:12:15.481805
132	12	9	2020-02-16	Atrasada	2026-05-15 14:12:15.481805
133	13	9	2020-11-01	Atrasada	2026-05-15 14:12:15.481805
134	14	9	2018-01-27	Atrasada	2026-05-15 14:12:15.481805
135	15	9	2021-08-11	Atrasada	2026-05-15 14:12:15.481805
136	1	10	2018-09-15	Atrasada	2026-05-15 14:12:15.481805
137	2	10	2020-01-20	Atrasada	2026-05-15 14:12:15.481805
138	3	10	2020-07-10	Atrasada	2026-05-15 14:12:15.481805
139	4	10	2018-05-05	Atrasada	2026-05-15 14:12:15.481805
140	5	10	2021-12-12	Atrasada	2026-05-15 14:12:15.481805
141	6	10	2019-02-18	Atrasada	2026-05-15 14:12:15.481805
142	7	10	2019-10-09	Atrasada	2026-05-15 14:12:15.481805
143	8	10	2021-03-14	Atrasada	2026-05-15 14:12:15.481805
144	9	10	2018-06-30	Atrasada	2026-05-15 14:12:15.481805
146	11	10	2018-11-03	Atrasada	2026-05-15 14:12:15.481805
147	12	10	2020-04-16	Atrasada	2026-05-15 14:12:15.481805
148	13	10	2021-01-01	Atrasada	2026-05-15 14:12:15.481805
149	14	10	2018-03-27	Atrasada	2026-05-15 14:12:15.481805
150	15	10	2021-10-11	Atrasada	2026-05-15 14:12:15.481805
151	1	11	2018-09-15	Atrasada	2026-05-15 14:12:15.481805
152	2	11	2020-01-20	Atrasada	2026-05-15 14:12:15.481805
153	3	11	2020-07-10	Atrasada	2026-05-15 14:12:15.481805
154	4	11	2018-05-05	Atrasada	2026-05-15 14:12:15.481805
155	5	11	2021-12-12	Atrasada	2026-05-15 14:12:15.481805
156	6	11	2019-02-18	Atrasada	2026-05-15 14:12:15.481805
157	7	11	2019-10-09	Atrasada	2026-05-15 14:12:15.481805
158	8	11	2021-03-14	Atrasada	2026-05-15 14:12:15.481805
159	9	11	2018-06-30	Atrasada	2026-05-15 14:12:15.481805
160	10	11	2021-08-25	Atrasada	2026-05-15 14:12:15.481805
161	11	11	2018-11-03	Atrasada	2026-05-15 14:12:15.481805
162	12	11	2020-04-16	Atrasada	2026-05-15 14:12:15.481805
163	13	11	2021-01-01	Atrasada	2026-05-15 14:12:15.481805
164	14	11	2018-03-27	Atrasada	2026-05-15 14:12:15.481805
165	15	11	2021-10-11	Atrasada	2026-05-15 14:12:15.481805
166	1	12	2018-09-15	Atrasada	2026-05-15 14:12:15.481805
167	2	12	2020-01-20	Atrasada	2026-05-15 14:12:15.481805
168	3	12	2020-07-10	Atrasada	2026-05-15 14:12:15.481805
169	4	12	2018-05-05	Atrasada	2026-05-15 14:12:15.481805
170	5	12	2021-12-12	Atrasada	2026-05-15 14:12:15.481805
171	6	12	2019-02-18	Atrasada	2026-05-15 14:12:15.481805
172	7	12	2019-10-09	Atrasada	2026-05-15 14:12:15.481805
173	8	12	2021-03-14	Atrasada	2026-05-15 14:12:15.481805
174	9	12	2018-06-30	Atrasada	2026-05-15 14:12:15.481805
175	10	12	2021-08-25	Atrasada	2026-05-15 14:12:15.481805
176	11	12	2018-11-03	Atrasada	2026-05-15 14:12:15.481805
177	12	12	2020-04-16	Atrasada	2026-05-15 14:12:15.481805
178	13	12	2021-01-01	Atrasada	2026-05-15 14:12:15.481805
179	14	12	2018-03-27	Atrasada	2026-05-15 14:12:15.481805
180	15	12	2021-10-11	Atrasada	2026-05-15 14:12:15.481805
181	1	13	2018-09-15	Atrasada	2026-05-15 14:12:15.481805
182	2	13	2020-01-20	Atrasada	2026-05-15 14:12:15.481805
183	3	13	2020-07-10	Atrasada	2026-05-15 14:12:15.481805
184	4	13	2018-05-05	Atrasada	2026-05-15 14:12:15.481805
185	5	13	2021-12-12	Atrasada	2026-05-15 14:12:15.481805
186	6	13	2019-02-18	Atrasada	2026-05-15 14:12:15.481805
187	7	13	2019-10-09	Atrasada	2026-05-15 14:12:15.481805
188	8	13	2021-03-14	Atrasada	2026-05-15 14:12:15.481805
189	9	13	2018-06-30	Atrasada	2026-05-15 14:12:15.481805
190	10	13	2021-08-25	Atrasada	2026-05-15 14:12:15.481805
191	11	13	2018-11-03	Atrasada	2026-05-15 14:12:15.481805
192	12	13	2020-04-16	Atrasada	2026-05-15 14:12:15.481805
193	13	13	2021-01-01	Atrasada	2026-05-15 14:12:15.481805
194	14	13	2018-03-27	Atrasada	2026-05-15 14:12:15.481805
195	15	13	2021-10-11	Atrasada	2026-05-15 14:12:15.481805
196	1	14	2018-10-15	Atrasada	2026-05-15 14:12:15.481805
197	2	14	2020-02-20	Atrasada	2026-05-15 14:12:15.481805
198	3	14	2020-08-10	Atrasada	2026-05-15 14:12:15.481805
199	4	14	2018-06-05	Atrasada	2026-05-15 14:12:15.481805
200	5	14	2022-01-12	Atrasada	2026-05-15 14:12:15.481805
201	6	14	2019-03-18	Atrasada	2026-05-15 14:12:15.481805
202	7	14	2019-11-09	Atrasada	2026-05-15 14:12:15.481805
203	8	14	2021-04-14	Atrasada	2026-05-15 14:12:15.481805
204	9	14	2018-07-30	Atrasada	2026-05-15 14:12:15.481805
205	10	14	2021-09-25	Atrasada	2026-05-15 14:12:15.481805
206	11	14	2018-12-03	Atrasada	2026-05-15 14:12:15.481805
207	12	14	2020-05-16	Atrasada	2026-05-15 14:12:15.481805
208	13	14	2021-02-01	Atrasada	2026-05-15 14:12:15.481805
209	14	14	2018-04-27	Atrasada	2026-05-15 14:12:15.481805
210	15	14	2021-11-11	Atrasada	2026-05-15 14:12:15.481805
211	1	15	2019-03-15	Atrasada	2026-05-15 14:12:15.481805
212	2	15	2020-07-20	Atrasada	2026-05-15 14:12:15.481805
213	3	15	2021-01-10	Atrasada	2026-05-15 14:12:15.481805
214	4	15	2018-11-05	Atrasada	2026-05-15 14:12:15.481805
215	5	15	2022-06-12	Atrasada	2026-05-15 14:12:15.481805
216	6	15	2019-08-18	Atrasada	2026-05-15 14:12:15.481805
217	7	15	2020-04-09	Atrasada	2026-05-15 14:12:15.481805
218	8	15	2021-09-14	Atrasada	2026-05-15 14:12:15.481805
219	9	15	2018-12-30	Atrasada	2026-05-15 14:12:15.481805
220	10	15	2022-02-25	Atrasada	2026-05-15 14:12:15.481805
222	12	15	2020-10-16	Atrasada	2026-05-15 14:12:15.481805
224	14	15	2018-09-27	Atrasada	2026-05-15 14:12:15.481805
225	15	15	2022-04-11	Atrasada	2026-05-15 14:12:15.481805
226	1	16	2019-03-15	Atrasada	2026-05-15 14:12:15.481805
227	2	16	2020-07-20	Atrasada	2026-05-15 14:12:15.481805
228	3	16	2021-01-10	Atrasada	2026-05-15 14:12:15.481805
229	4	16	2018-11-05	Atrasada	2026-05-15 14:12:15.481805
230	5	16	2022-06-12	Atrasada	2026-05-15 14:12:15.481805
231	6	16	2019-08-18	Atrasada	2026-05-15 14:12:15.481805
232	7	16	2020-04-09	Atrasada	2026-05-15 14:12:15.481805
233	8	16	2021-09-14	Atrasada	2026-05-15 14:12:15.481805
234	9	16	2018-12-30	Atrasada	2026-05-15 14:12:15.481805
235	10	16	2022-02-25	Atrasada	2026-05-15 14:12:15.481805
236	11	16	2019-05-03	Atrasada	2026-05-15 14:12:15.481805
237	12	16	2020-10-16	Atrasada	2026-05-15 14:12:15.481805
238	13	16	2021-07-01	Atrasada	2026-05-15 14:12:15.481805
239	14	16	2018-09-27	Atrasada	2026-05-15 14:12:15.481805
240	15	16	2022-04-11	Atrasada	2026-05-15 14:12:15.481805
241	1	17	2019-09-15	Atrasada	2026-05-15 14:12:15.481805
242	2	17	2021-01-20	Atrasada	2026-05-15 14:12:15.481805
243	3	17	2021-07-10	Atrasada	2026-05-15 14:12:15.481805
244	4	17	2019-05-05	Atrasada	2026-05-15 14:12:15.481805
245	5	17	2022-12-12	Atrasada	2026-05-15 14:12:15.481805
246	6	17	2020-02-18	Atrasada	2026-05-15 14:12:15.481805
247	7	17	2020-10-09	Atrasada	2026-05-15 14:12:15.481805
248	8	17	2022-03-14	Atrasada	2026-05-15 14:12:15.481805
249	9	17	2019-06-30	Atrasada	2026-05-15 14:12:15.481805
250	10	17	2022-08-25	Atrasada	2026-05-15 14:12:15.481805
251	11	17	2019-11-03	Atrasada	2026-05-15 14:12:15.481805
252	12	17	2021-04-16	Atrasada	2026-05-15 14:12:15.481805
253	13	17	2022-01-01	Atrasada	2026-05-15 14:12:15.481805
254	14	17	2019-03-27	Atrasada	2026-05-15 14:12:15.481805
255	15	17	2022-10-11	Atrasada	2026-05-15 14:12:15.481805
256	1	18	2020-03-15	Atrasada	2026-05-15 14:12:15.481805
257	2	18	2021-07-20	Atrasada	2026-05-15 14:12:15.481805
258	3	18	2022-01-10	Atrasada	2026-05-15 14:12:15.481805
259	4	18	2019-11-05	Atrasada	2026-05-15 14:12:15.481805
260	5	18	2023-06-12	Atrasada	2026-05-15 14:12:15.481805
261	6	18	2020-08-18	Atrasada	2026-05-15 14:12:15.481805
262	7	18	2021-04-09	Atrasada	2026-05-15 14:12:15.481805
263	8	18	2022-09-14	Atrasada	2026-05-15 14:12:15.481805
264	9	18	2019-12-30	Atrasada	2026-05-15 14:12:15.481805
265	10	18	2023-02-25	Atrasada	2026-05-15 14:12:15.481805
266	11	18	2020-05-03	Atrasada	2026-05-15 14:12:15.481805
268	13	18	2022-07-01	Atrasada	2026-05-15 14:12:15.481805
269	14	18	2019-09-27	Atrasada	2026-05-15 14:12:15.481805
270	15	18	2023-04-11	Atrasada	2026-05-15 14:12:15.481805
271	1	19	2021-03-15	Atrasada	2026-05-15 14:12:15.481805
272	2	19	2022-07-20	Atrasada	2026-05-15 14:12:15.481805
273	3	19	2023-01-10	Atrasada	2026-05-15 14:12:15.481805
274	4	19	2020-11-05	Atrasada	2026-05-15 14:12:15.481805
275	5	19	2024-06-12	Atrasada	2026-05-15 14:12:15.481805
276	6	19	2021-08-18	Atrasada	2026-05-15 14:12:15.481805
277	7	19	2022-04-09	Atrasada	2026-05-15 14:12:15.481805
278	8	19	2023-09-14	Atrasada	2026-05-15 14:12:15.481805
279	9	19	2020-12-30	Atrasada	2026-05-15 14:12:15.481805
280	10	19	2024-02-25	Atrasada	2026-05-15 14:12:15.481805
281	11	19	2021-05-03	Atrasada	2026-05-15 14:12:15.481805
282	12	19	2022-10-16	Atrasada	2026-05-15 14:12:15.481805
283	13	19	2023-07-01	Atrasada	2026-05-15 14:12:15.481805
284	14	19	2020-09-27	Atrasada	2026-05-15 14:12:15.481805
285	15	19	2024-04-11	Atrasada	2026-05-15 14:12:15.481805
286	1	20	2022-03-15	Atrasada	2026-05-15 14:12:15.481805
287	2	20	2023-07-20	Atrasada	2026-05-15 14:12:15.481805
288	3	20	2024-01-10	Atrasada	2026-05-15 14:12:15.481805
289	4	20	2021-11-05	Atrasada	2026-05-15 14:12:15.481805
290	5	20	2025-06-12	Atrasada	2026-05-15 14:12:15.481805
291	6	20	2022-08-18	Atrasada	2026-05-15 14:12:15.481805
292	7	20	2023-04-09	Atrasada	2026-05-15 14:12:15.481805
293	8	20	2024-09-14	Atrasada	2026-05-15 14:12:15.481805
294	9	20	2021-12-30	Atrasada	2026-05-15 14:12:15.481805
295	10	20	2025-02-25	Atrasada	2026-05-15 14:12:15.481805
296	11	20	2022-05-03	Atrasada	2026-05-15 14:12:15.481805
297	12	20	2023-10-16	Atrasada	2026-05-15 14:12:15.481805
298	13	20	2024-07-01	Atrasada	2026-05-15 14:12:15.481805
300	15	20	2025-04-11	Atrasada	2026-05-15 14:12:15.481805
301	1	21	2022-03-15	Atrasada	2026-05-15 14:12:15.481805
302	2	21	2023-07-20	Atrasada	2026-05-15 14:12:15.481805
303	3	21	2024-01-10	Atrasada	2026-05-15 14:12:15.481805
304	4	21	2021-11-05	Atrasada	2026-05-15 14:12:15.481805
305	5	21	2025-06-12	Atrasada	2026-05-15 14:12:15.481805
306	6	21	2022-08-18	Atrasada	2026-05-15 14:12:15.481805
307	7	21	2023-04-09	Atrasada	2026-05-15 14:12:15.481805
308	8	21	2024-09-14	Atrasada	2026-05-15 14:12:15.481805
309	9	21	2021-12-30	Atrasada	2026-05-15 14:12:15.481805
310	10	21	2025-02-25	Atrasada	2026-05-15 14:12:15.481805
311	11	21	2022-05-03	Atrasada	2026-05-15 14:12:15.481805
312	12	21	2023-10-16	Atrasada	2026-05-15 14:12:15.481805
313	13	21	2024-07-01	Atrasada	2026-05-15 14:12:15.481805
314	14	21	2021-09-27	Atrasada	2026-05-15 14:12:15.481805
315	15	21	2025-04-11	Atrasada	2026-05-15 14:12:15.481805
316	1	22	2023-02-15	Atrasada	2026-05-15 14:12:15.481805
317	2	22	2024-06-20	Atrasada	2026-05-15 14:12:15.481805
318	3	22	2024-12-10	Atrasada	2026-05-15 14:12:15.481805
319	4	22	2022-10-05	Atrasada	2026-05-15 14:12:15.481805
320	5	22	2026-05-12	Atrasada	2026-05-15 14:12:15.481805
321	6	22	2023-07-18	Atrasada	2026-05-15 14:12:15.481805
322	7	22	2024-03-09	Atrasada	2026-05-15 14:12:15.481805
323	8	22	2025-08-14	Atrasada	2026-05-15 14:12:15.481805
324	9	22	2022-11-30	Atrasada	2026-05-15 14:12:15.481805
325	10	22	2026-01-25	Atrasada	2026-05-15 14:12:15.481805
326	11	22	2023-04-03	Atrasada	2026-05-15 14:12:15.481805
327	12	22	2024-09-16	Atrasada	2026-05-15 14:12:15.481805
328	13	22	2025-06-01	Atrasada	2026-05-15 14:12:15.481805
329	14	22	2022-08-27	Atrasada	2026-05-15 14:12:15.481805
330	15	22	2026-03-11	Atrasada	2026-05-15 14:12:15.481805
331	1	23	2023-03-15	Atrasada	2026-05-15 14:12:15.481805
332	2	23	2024-07-20	Atrasada	2026-05-15 14:12:15.481805
333	3	23	2025-01-10	Atrasada	2026-05-15 14:12:15.481805
334	4	23	2022-11-05	Atrasada	2026-05-15 14:12:15.481805
335	5	23	2026-06-12	Pendiente	2026-05-15 14:12:15.481805
336	6	23	2023-08-18	Atrasada	2026-05-15 14:12:15.481805
337	7	23	2024-04-09	Atrasada	2026-05-15 14:12:15.481805
338	8	23	2025-09-14	Atrasada	2026-05-15 14:12:15.481805
339	9	23	2022-12-30	Atrasada	2026-05-15 14:12:15.481805
340	10	23	2026-02-25	Atrasada	2026-05-15 14:12:15.481805
341	11	23	2023-05-03	Atrasada	2026-05-15 14:12:15.481805
342	12	23	2024-10-16	Atrasada	2026-05-15 14:12:15.481805
343	13	23	2025-07-01	Atrasada	2026-05-15 14:12:15.481805
344	14	23	2022-09-27	Atrasada	2026-05-15 14:12:15.481805
345	15	23	2026-04-11	Atrasada	2026-05-15 14:12:15.481805
346	1	24	2024-03-15	Atrasada	2026-05-15 14:12:15.481805
347	2	24	2025-07-20	Atrasada	2026-05-15 14:12:15.481805
348	3	24	2026-01-10	Atrasada	2026-05-15 14:12:15.481805
349	4	24	2023-11-05	Atrasada	2026-05-15 14:12:15.481805
350	5	24	2027-06-12	Pendiente	2026-05-15 14:12:15.481805
351	6	24	2024-08-18	Atrasada	2026-05-15 14:12:15.481805
352	7	24	2025-04-09	Atrasada	2026-05-15 14:12:15.481805
353	8	24	2026-09-14	Pendiente	2026-05-15 14:12:15.481805
354	9	24	2023-12-30	Atrasada	2026-05-15 14:12:15.481805
355	10	24	2027-02-25	Pendiente	2026-05-15 14:12:15.481805
356	11	24	2024-05-03	Atrasada	2026-05-15 14:12:15.481805
357	12	24	2025-10-16	Atrasada	2026-05-15 14:12:15.481805
358	13	24	2026-07-01	Pendiente	2026-05-15 14:12:15.481805
359	14	24	2023-09-27	Atrasada	2026-05-15 14:12:15.481805
360	15	24	2027-04-11	Pendiente	2026-05-15 14:12:15.481805
361	1	25	2029-03-15	Pendiente	2026-05-15 14:12:15.481805
362	2	25	2030-07-20	Pendiente	2026-05-15 14:12:15.481805
363	3	25	2031-01-10	Pendiente	2026-05-15 14:12:15.481805
364	4	25	2028-11-05	Pendiente	2026-05-15 14:12:15.481805
365	5	25	2032-06-12	Pendiente	2026-05-15 14:12:15.481805
366	6	25	2029-08-18	Pendiente	2026-05-15 14:12:15.481805
367	7	25	2030-04-09	Pendiente	2026-05-15 14:12:15.481805
368	8	25	2031-09-14	Pendiente	2026-05-15 14:12:15.481805
369	9	25	2028-12-30	Pendiente	2026-05-15 14:12:15.481805
370	10	25	2032-02-25	Pendiente	2026-05-15 14:12:15.481805
371	11	25	2029-05-03	Pendiente	2026-05-15 14:12:15.481805
372	12	25	2030-10-16	Pendiente	2026-05-15 14:12:15.481805
373	13	25	2031-07-01	Pendiente	2026-05-15 14:12:15.481805
374	14	25	2028-09-27	Pendiente	2026-05-15 14:12:15.481805
375	15	25	2032-04-11	Pendiente	2026-05-15 14:12:15.481805
376	1	26	2029-09-15	Pendiente	2026-05-15 14:12:15.481805
377	2	26	2031-01-20	Pendiente	2026-05-15 14:12:15.481805
378	3	26	2031-07-10	Pendiente	2026-05-15 14:12:15.481805
379	4	26	2029-05-05	Pendiente	2026-05-15 14:12:15.481805
380	5	26	2032-12-12	Pendiente	2026-05-15 14:12:15.481805
381	6	26	2030-02-18	Pendiente	2026-05-15 14:12:15.481805
382	7	26	2030-10-09	Pendiente	2026-05-15 14:12:15.481805
383	8	26	2032-03-14	Pendiente	2026-05-15 14:12:15.481805
384	9	26	2029-06-30	Pendiente	2026-05-15 14:12:15.481805
385	10	26	2032-08-25	Pendiente	2026-05-15 14:12:15.481805
386	11	26	2029-11-03	Pendiente	2026-05-15 14:12:15.481805
387	12	26	2031-04-16	Pendiente	2026-05-15 14:12:15.481805
388	13	26	2032-01-01	Pendiente	2026-05-15 14:12:15.481805
389	14	26	2029-03-27	Pendiente	2026-05-15 14:12:15.481805
390	15	26	2032-10-11	Pendiente	2026-05-15 14:12:15.481805
1	1	1	2018-03-15	Aplicada	2026-05-15 14:12:15.481805
15	15	1	2021-04-11	Aplicada	2026-05-15 14:12:15.481805
17	2	2	2019-07-20	Aplicada	2026-05-15 14:12:15.481805
33	3	3	2020-03-10	Aplicada	2026-05-15 14:12:15.481805
49	4	4	2018-01-05	Aplicada	2026-05-15 14:12:15.481805
65	5	5	2021-08-12	Aplicada	2026-05-15 14:12:15.481805
81	6	6	2018-10-18	Aplicada	2026-05-15 14:12:15.481805
97	7	7	2019-08-09	Aplicada	2026-05-15 14:12:15.481805
113	8	8	2021-01-14	Aplicada	2026-05-15 14:12:15.481805
129	9	9	2018-04-30	Aplicada	2026-05-15 14:12:15.481805
145	10	10	2021-08-25	Aplicada	2026-05-15 14:12:15.481805
221	11	15	2019-05-03	Aplicada	2026-05-15 14:12:15.481805
223	13	15	2021-07-01	Aplicada	2026-05-15 14:12:15.481805
267	12	18	2021-10-16	Aplicada	2026-05-15 14:12:15.481805
299	14	20	2021-09-27	Aplicada	2026-05-15 14:12:15.481805
391	16	1	2026-03-09	Atrasada	2026-05-17 00:21:21.918684
392	16	2	2026-03-09	Atrasada	2026-05-17 00:21:21.918684
393	16	3	2026-05-09	Atrasada	2026-05-17 00:21:21.918684
394	16	4	2026-05-09	Atrasada	2026-05-17 00:21:21.918684
395	16	5	2026-05-09	Atrasada	2026-05-17 00:21:21.918684
396	16	6	2026-05-09	Atrasada	2026-05-17 00:21:21.918684
397	16	7	2026-07-09	Pendiente	2026-05-17 00:21:21.918684
398	16	8	2026-07-09	Pendiente	2026-05-17 00:21:21.918684
399	16	9	2026-07-09	Pendiente	2026-05-17 00:21:21.918684
400	16	10	2026-09-09	Pendiente	2026-05-17 00:21:21.918684
401	16	11	2026-09-09	Pendiente	2026-05-17 00:21:21.918684
402	16	12	2026-09-09	Pendiente	2026-05-17 00:21:21.918684
403	16	13	2026-09-09	Pendiente	2026-05-17 00:21:21.918684
404	16	14	2026-10-09	Pendiente	2026-05-17 00:21:21.918684
405	16	15	2027-03-09	Pendiente	2026-05-17 00:21:21.918684
406	16	16	2027-03-09	Pendiente	2026-05-17 00:21:21.918684
407	16	17	2027-09-09	Pendiente	2026-05-17 00:21:21.918684
408	16	18	2028-03-09	Pendiente	2026-05-17 00:21:21.918684
409	16	19	2029-03-09	Pendiente	2026-05-17 00:21:21.918684
410	16	20	2030-03-09	Pendiente	2026-05-17 00:21:21.918684
411	16	21	2030-03-09	Pendiente	2026-05-17 00:21:21.918684
412	16	22	2031-02-09	Pendiente	2026-05-17 00:21:21.918684
413	16	23	2031-03-09	Pendiente	2026-05-17 00:21:21.918684
414	16	24	2032-03-09	Pendiente	2026-05-17 00:21:21.918684
415	16	25	2037-03-09	Pendiente	2026-05-17 00:21:21.918684
416	16	26	2037-09-09	Pendiente	2026-05-17 00:21:21.918684
417	17	1	2025-05-02	Atrasada	2026-05-17 00:28:03.399482
418	17	2	2025-05-02	Atrasada	2026-05-17 00:28:03.399482
419	17	3	2025-07-02	Atrasada	2026-05-17 00:28:03.399482
420	17	4	2025-07-02	Atrasada	2026-05-17 00:28:03.399482
421	17	5	2025-07-02	Atrasada	2026-05-17 00:28:03.399482
422	17	6	2025-07-02	Atrasada	2026-05-17 00:28:03.399482
423	17	7	2025-09-02	Atrasada	2026-05-17 00:28:03.399482
424	17	8	2025-09-02	Atrasada	2026-05-17 00:28:03.399482
425	17	9	2025-09-02	Atrasada	2026-05-17 00:28:03.399482
426	17	10	2025-11-02	Atrasada	2026-05-17 00:28:03.399482
427	17	11	2025-11-02	Atrasada	2026-05-17 00:28:03.399482
428	17	12	2025-11-02	Atrasada	2026-05-17 00:28:03.399482
429	17	13	2025-11-02	Atrasada	2026-05-17 00:28:03.399482
430	17	14	2025-12-02	Atrasada	2026-05-17 00:28:03.399482
431	17	15	2026-05-02	Atrasada	2026-05-17 00:28:03.399482
432	17	16	2026-05-02	Atrasada	2026-05-17 00:28:03.399482
433	17	17	2026-11-02	Pendiente	2026-05-17 00:28:03.399482
434	17	18	2027-05-02	Pendiente	2026-05-17 00:28:03.399482
435	17	19	2028-05-02	Pendiente	2026-05-17 00:28:03.399482
436	17	20	2029-05-02	Pendiente	2026-05-17 00:28:03.399482
437	17	21	2029-05-02	Pendiente	2026-05-17 00:28:03.399482
438	17	22	2030-04-02	Pendiente	2026-05-17 00:28:03.399482
439	17	23	2030-05-02	Pendiente	2026-05-17 00:28:03.399482
440	17	24	2031-05-02	Pendiente	2026-05-17 00:28:03.399482
441	17	25	2036-05-02	Pendiente	2026-05-17 00:28:03.399482
442	17	26	2036-11-02	Pendiente	2026-05-17 00:28:03.399482
444	18	2	2026-03-10	Atrasada	2026-05-17 00:33:11.833123
445	18	3	2026-05-10	Atrasada	2026-05-17 00:33:11.833123
446	18	4	2026-05-10	Atrasada	2026-05-17 00:33:11.833123
447	18	5	2026-05-10	Atrasada	2026-05-17 00:33:11.833123
448	18	6	2026-05-10	Atrasada	2026-05-17 00:33:11.833123
449	18	7	2026-07-10	Pendiente	2026-05-17 00:33:11.833123
450	18	8	2026-07-10	Pendiente	2026-05-17 00:33:11.833123
451	18	9	2026-07-10	Pendiente	2026-05-17 00:33:11.833123
452	18	10	2026-09-10	Pendiente	2026-05-17 00:33:11.833123
453	18	11	2026-09-10	Pendiente	2026-05-17 00:33:11.833123
454	18	12	2026-09-10	Pendiente	2026-05-17 00:33:11.833123
455	18	13	2026-09-10	Pendiente	2026-05-17 00:33:11.833123
456	18	14	2026-10-10	Pendiente	2026-05-17 00:33:11.833123
457	18	15	2027-03-10	Pendiente	2026-05-17 00:33:11.833123
458	18	16	2027-03-10	Pendiente	2026-05-17 00:33:11.833123
459	18	17	2027-09-10	Pendiente	2026-05-17 00:33:11.833123
460	18	18	2028-03-10	Pendiente	2026-05-17 00:33:11.833123
461	18	19	2029-03-10	Pendiente	2026-05-17 00:33:11.833123
462	18	20	2030-03-10	Pendiente	2026-05-17 00:33:11.833123
463	18	21	2030-03-10	Pendiente	2026-05-17 00:33:11.833123
464	18	22	2031-02-10	Pendiente	2026-05-17 00:33:11.833123
465	18	23	2031-03-10	Pendiente	2026-05-17 00:33:11.833123
466	18	24	2032-03-10	Pendiente	2026-05-17 00:33:11.833123
467	18	25	2037-03-10	Pendiente	2026-05-17 00:33:11.833123
468	18	26	2037-09-10	Pendiente	2026-05-17 00:33:11.833123
443	18	1	2026-03-10	Aplicada	2026-05-17 00:44:12.063684
469	19	1	2026-01-05	Atrasada	2026-05-17 13:21:11.16144
470	19	2	2026-01-05	Atrasada	2026-05-17 13:21:11.16144
471	19	3	2026-03-05	Atrasada	2026-05-17 13:21:11.16144
472	19	4	2026-03-05	Atrasada	2026-05-17 13:21:11.16144
473	19	5	2026-03-05	Atrasada	2026-05-17 13:21:11.16144
474	19	6	2026-03-05	Atrasada	2026-05-17 13:21:11.16144
475	19	7	2026-05-05	Atrasada	2026-05-17 13:21:11.16144
476	19	8	2026-05-05	Atrasada	2026-05-17 13:21:11.16144
477	19	9	2026-05-05	Atrasada	2026-05-17 13:21:11.16144
478	19	10	2026-07-05	Pendiente	2026-05-17 13:21:11.16144
479	19	11	2026-07-05	Pendiente	2026-05-17 13:21:11.16144
480	19	12	2026-07-05	Pendiente	2026-05-17 13:21:11.16144
481	19	13	2026-07-05	Pendiente	2026-05-17 13:21:11.16144
482	19	14	2026-08-05	Pendiente	2026-05-17 13:21:11.16144
483	19	15	2027-01-05	Pendiente	2026-05-17 13:21:11.16144
484	19	16	2027-01-05	Pendiente	2026-05-17 13:21:11.16144
485	19	17	2027-07-05	Pendiente	2026-05-17 13:21:11.16144
486	19	18	2028-01-05	Pendiente	2026-05-17 13:21:11.16144
487	19	19	2029-01-05	Pendiente	2026-05-17 13:21:11.16144
488	19	20	2030-01-05	Pendiente	2026-05-17 13:21:11.16144
489	19	21	2030-01-05	Pendiente	2026-05-17 13:21:11.16144
490	19	22	2030-12-05	Pendiente	2026-05-17 13:21:11.16144
491	19	23	2031-01-05	Pendiente	2026-05-17 13:21:11.16144
492	19	24	2032-01-05	Pendiente	2026-05-17 13:21:11.16144
493	19	25	2037-01-05	Pendiente	2026-05-17 13:21:11.16144
494	19	26	2037-07-05	Pendiente	2026-05-17 13:21:11.16144
\.


--
-- Data for Name: patients; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.patients (patient_id, first_name, last_name, birth_date, blood_type_id, gender, nfc_token, curp, weight_kg, premature, created_at, is_active, deleted_at, updated_at, photo) FROM stdin;
1	Mateo	García	2018-03-15	1	M	\N	GAMM180315HNLRTRA1	25.50	f	2026-05-15 14:00:13.419597	t	\N	\N	\N
2	Sofía	Martínez	2019-07-20	2	F	\N	MASS190720MNLRFBA2	22.10	f	2026-05-15 14:00:13.419597	t	\N	\N	\N
3	Diego	López	2020-01-10	3	M	\N	LODD200110HNLRPCA3	18.00	t	2026-05-15 14:00:13.419597	t	\N	\N	\N
4	Valentina	Hernández	2017-11-05	4	F	\N	HEVV171105MNLRLDA4	28.40	f	2026-05-15 14:00:13.419597	t	\N	\N	\N
5	Lucas	Ramírez	2021-06-12	5	M	\N	RALL210612HNLRMNA5	16.20	f	2026-05-15 14:00:13.419597	t	\N	\N	\N
6	Emma	Torres	2018-08-18	6	F	\N	TOEE180818MNLRRSA6	24.30	f	2026-05-15 14:00:13.419597	t	\N	\N	\N
7	Sebastián	Flores	2019-04-09	7	M	\N	FOSS190409HNLRBTA7	20.00	f	2026-05-15 14:00:13.419597	t	\N	\N	\N
8	Camila	Rivera	2020-09-14	8	F	\N	RICC200914MNLRVCA8	19.40	t	2026-05-15 14:00:13.419597	t	\N	\N	\N
9	Leonardo	Gómez	2017-12-30	1	M	\N	GOAL171230HNLRMDA9	29.10	f	2026-05-15 14:00:13.419597	t	\N	\N	\N
10	Renata	Díaz	2021-02-25	2	F	\N	DIRR210225MNLRZEA1	15.70	f	2026-05-15 14:00:13.419597	t	\N	\N	\N
11	Emiliano	Castro	2018-05-03	3	M	\N	CAEE180503HNLRMSA2	23.60	f	2026-05-15 14:00:13.419597	t	\N	\N	\N
12	Regina	Ortiz	2019-10-16	4	F	\N	OARR191016MNLRRGA3	21.80	f	2026-05-15 14:00:13.419597	t	\N	\N	\N
13	Daniel	Morales	2020-07-01	5	M	\N	MODD200701HNLRNTA4	17.90	t	2026-05-15 14:00:13.419597	t	\N	\N	\N
14	Victoria	Ruiz	2017-09-27	6	F	\N	RUVV170927MNLRKLA5	30.20	f	2026-05-15 14:00:13.419597	t	\N	\N	\N
15	Ángel	Navarro	2021-04-11	7	M	\N	NAAA210411HNLRVSA6	14.50	f	2026-05-15 14:00:13.419597	t	\N	\N	\N
16	Mariana	Olvera	2026-03-09	2	F	\N	\N	\N	f	2026-05-17 00:21:21.918684	f	2026-05-17 00:31:35.731314	2026-05-17 00:31:35.731314	\N
17	Andres	Olvera	2025-05-02	7	M	\N	\N	\N	f	2026-05-17 00:28:03.399482	f	2026-05-17 00:31:41.345002	2026-05-17 00:31:41.345002	\N
18	Mariana	Olvera	2026-03-10	1	F	\N	MARO401930MNLRVCA8	\N	f	2026-05-17 00:33:11.833123	t	\N	\N	\N
19	Ricardo	Olvera	2026-01-05	1	M	\N	RICO193817MADKVO20	32.80	f	2026-05-17 13:21:11.16144	t	\N	\N	\N
\.


--
-- Data for Name: post_vaccine_reactions; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.post_vaccine_reactions (reaction_id, record_id, reported_by, symptom, severity, onset_hours, treatment, notified_authority) FROM stdin;
\.


--
-- Data for Name: roles; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.roles (role_id, name, description) FROM stdin;
1	Administrador	Gestiona el sistema
2	Enfermero	Aplica vacunas
3	Medico	Supervisa pacientes
4	Recepcionista	Agenda citas
5	Almacen	Controla inventario
6	Tutor	Cuida pacientes
\.


--
-- Data for Name: scheme_completion_alerts; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.scheme_completion_alerts (alert_id, patient_id, scheme_dose_id, due_date, status, notified_at, alert_type, read_at, schedule_id) FROM stdin;
\.


--
-- Data for Name: scheme_doses; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.scheme_doses (dose_id, scheme_id, vaccine_id, dose_number, dose_label, ideal_age_months, min_interval_days) FROM stdin;
1	1	1	1	BCG — Dosis única	0	\N
2	1	2	1	Hepatitis B — 1ra dosis	0	\N
3	1	3	1	Pentavalente — 1ra dosis	2	\N
4	1	4	2	Hepatitis B — 2da dosis	2	56
5	1	5	1	Rotavirus — 1ra dosis	2	\N
6	1	6	1	Neumococo — 1ra dosis	2	\N
7	1	3	2	Pentavalente — 2da dosis	4	56
8	1	5	2	Rotavirus — 2da dosis	4	28
9	1	6	2	Neumococo — 2da dosis	4	56
10	1	3	3	Pentavalente — 3ra dosis	6	56
11	1	4	3	Hepatitis B — 3ra dosis	6	56
12	1	5	3	Rotavirus — 3ra dosis	6	28
13	1	7	1	Influenza — 1ra dosis	6	\N
14	1	7	2	Influenza — 2da dosis	7	28
15	1	8	1	SRP — 1ra dosis	12	\N
16	1	6	3	Neumococo — 3ra dosis	12	56
17	1	9	1	Pentavalente — Refuerzo	18	\N
18	1	7	3	Influenza refuerzo anual	24	365
19	1	7	4	Influenza refuerzo anual	36	365
20	1	10	1	DPT — Refuerzo	48	\N
21	1	7	5	Influenza refuerzo anual	48	365
22	1	7	6	Influenza refuerzo anual oct-ene	59	365
23	1	11	1	OPV — Semanas Nacionales Salud	60	\N
24	1	8	2	SRP — Refuerzo	72	\N
25	1	12	1	VPH — 1ra dosis	132	\N
26	1	12	2	VPH — 2da dosis	138	180
\.


--
-- Data for Name: specialties; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.specialties (specialty_id, name) FROM stdin;
1	Pediatría
2	Medicina General
3	Inmunología
4	Enfermería Pediátrica
5	Vacunología
6	Atención Primaria
7	Salud Pública
8	Infectología
9	Epidemiología
10	Medicina Familiar
11	Cuidados Intensivos
12	Medicina Preventiva
\.


--
-- Data for Name: states; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.states (state_id, country_id, name, code) FROM stdin;
1	1	Nuevo León	NL
2	1	Jalisco	JA
3	1	Ciudad de México	CDMX
4	1	Coahuila	COA
5	1	Tamaulipas	TAM
6	1	Sonora	SON
7	1	Chihuahua	CHI
8	1	Yucatán	YUC
9	1	Puebla	PUE
10	1	Querétaro	QRO
11	1	Guanajuato	GTO
12	1	Sinaloa	SIN
13	1	Durango	DGO
14	1	Veracruz	VER
15	1	Oaxaca	OAX
\.


--
-- Data for Name: supply_catalog; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.supply_catalog (supply_id, name, unit, category) FROM stdin;
1	Jeringa 0.5ml 25Gx1"	Pieza	Jeringa
2	Jeringa 1ml 23Gx1"	Pieza	Jeringa
3	Torunda de algodón con alcohol	Pieza	Desechable
4	Guante de látex talla S	Par	Desechable
5	Guante de látex talla M	Par	Desechable
6	Guante de látex talla L	Par	Desechable
7	Bandita adhesiva pediátrica	Pieza	Desechable
8	Cubre bocas tricapa	Pieza	Desechable
9	Contenedor de punzocortantes 1L	Pieza	Residuos
10	Solución salina 10ml	Ampolleta	Solución
11	Paracetamol 120mg/5ml gotas	Frasco	Medicamento
12	Adrenalina 1mg/ml jeringa prellenada	Pieza	Emergencia
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.users (user_id, worker_id, username, password_hash, is_active, created_at) FROM stdin;
1	1	jose.perez	$2a$06$mpkbjbq0Y14XGZw1EsgdeO6S/6J08QZUai3Nta/P/tAFF8vsc0Lc6	t	2026-05-16 17:04:27.63208
2	2	lucia.santos	$2a$06$Gd7szR5mqOcKc/1E8D6hL.fFEDD/rXdJ8G/H8L.vgMKp3JH5Hny2i	t	2026-05-16 17:04:27.63208
3	3	mario.luna	$2a$06$UuzSfw1nmWRBbfNZ.qG8FeDLH5gcmrJezLHWassAdRmnwNCWtlEf.	t	2026-05-16 17:04:27.63208
4	4	elisa.campos	$2a$06$kr5SCxvn/G4GejTrQEsF3.vxW/YiigMkLjoj4ydc7l8MY5ujXosGS	t	2026-05-16 17:04:27.63208
5	5	raul.mora	$2a$06$bCbIGnoy1lM1lMo8sNkJIuEleeIOH9qymLdLWxvIKh5lbvUEkVoQK	t	2026-05-16 17:04:27.63208
\.


--
-- Data for Name: vaccination_records; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.vaccination_records (record_id, patient_id, vaccine_id, worker_id, clinic_id, lot_id, scheme_dose_id, applied_date, application_site_id, appointment_id, patient_temp_c, had_reaction, created_at, patient_schedule_id, visit_id) FROM stdin;
1	9	1	3	1	1	1	2017-12-30	6	9	36.5	f	2026-05-16 17:25:31.438879	\N	\N
2	9	2	3	1	2	2	2017-12-30	1	\N	36.5	f	2026-05-16 17:25:31.438879	\N	\N
3	9	3	3	1	3	3	2018-02-28	1	\N	36.5	f	2026-05-16 17:25:31.438879	\N	\N
4	9	4	3	1	4	4	2018-02-28	2	\N	36.5	f	2026-05-16 17:25:31.438879	\N	\N
5	9	5	3	1	5	5	2018-02-28	5	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
6	9	6	3	1	6	6	2018-02-28	4	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
7	9	3	3	1	3	7	2018-04-30	1	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
8	9	5	3	1	5	8	2018-04-30	2	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
9	9	6	3	1	6	9	2018-04-30	4	\N	36.5	f	2026-05-16 17:25:31.438879	\N	\N
10	9	3	2	1	3	10	2018-06-30	1	\N	36.7	f	2026-05-16 17:25:31.438879	\N	\N
11	9	4	2	1	4	11	2018-06-30	2	\N	36.7	f	2026-05-16 17:25:31.438879	\N	\N
12	9	5	2	1	5	12	2018-06-30	5	\N	36.7	f	2026-05-16 17:25:31.438879	\N	\N
13	9	7	2	1	7	13	2018-06-30	3	\N	36.5	f	2026-05-16 17:25:31.438879	\N	\N
14	9	7	2	1	7	14	2018-07-30	3	\N	36.5	f	2026-05-16 17:25:31.438879	\N	\N
15	9	8	3	1	8	15	2018-12-30	3	\N	36.8	f	2026-05-16 17:25:31.438879	\N	\N
16	9	6	3	1	6	16	2018-12-30	1	\N	36.8	f	2026-05-16 17:25:31.438879	\N	\N
17	9	9	3	2	9	17	2019-06-30	1	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
18	9	7	3	1	7	18	2019-12-30	3	\N	36.5	f	2026-05-16 17:25:31.438879	\N	\N
19	1	1	3	1	1	1	2018-03-15	6	1	36.5	f	2026-05-16 17:25:31.438879	\N	\N
20	1	2	3	1	2	2	2018-03-15	1	\N	36.5	f	2026-05-16 17:25:31.438879	\N	\N
21	1	6	3	1	6	6	2018-05-15	4	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
22	1	8	3	1	8	15	2019-03-15	3	\N	36.7	f	2026-05-16 17:25:31.438879	\N	\N
23	1	9	3	2	9	17	2019-09-15	1	\N	36.5	f	2026-05-16 17:25:31.438879	\N	\N
24	1	10	3	2	10	20	2022-03-15	2	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
25	1	8	3	1	8	24	2024-03-15	3	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
26	2	1	3	1	1	1	2019-07-20	6	2	36.5	f	2026-05-16 17:25:31.438879	\N	\N
27	2	2	3	1	2	2	2019-07-20	1	\N	36.5	f	2026-05-16 17:25:31.438879	\N	\N
28	2	6	3	1	6	6	2019-09-20	4	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
29	2	8	3	1	8	15	2020-07-20	3	\N	36.7	f	2026-05-16 17:25:31.438879	\N	\N
30	2	9	3	2	9	17	2021-01-20	1	\N	36.5	f	2026-05-16 17:25:31.438879	\N	\N
31	2	8	3	1	8	24	2025-07-20	3	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
32	3	1	2	1	1	1	2020-01-10	6	3	36.5	f	2026-05-16 17:25:31.438879	\N	\N
33	3	3	2	1	3	3	2020-03-10	1	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
34	3	6	2	1	6	6	2020-03-10	4	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
35	3	8	2	1	8	15	2021-01-10	3	\N	36.7	f	2026-05-16 17:25:31.438879	\N	\N
36	3	10	2	2	10	20	2024-01-10	1	\N	36.5	f	2026-05-16 17:25:31.438879	\N	\N
37	4	2	3	1	2	2	2017-11-05	1	4	36.5	f	2026-05-16 17:25:31.438879	\N	\N
38	4	4	3	1	4	4	2018-01-05	2	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
39	4	8	3	1	8	15	2018-11-05	3	\N	36.7	f	2026-05-16 17:25:31.438879	\N	\N
40	4	9	3	2	9	17	2019-05-05	1	\N	36.5	f	2026-05-16 17:25:31.438879	\N	\N
41	4	8	3	1	8	24	2023-11-05	3	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
42	5	1	2	1	1	1	2021-06-12	6	5	36.5	f	2026-05-16 17:25:31.438879	\N	\N
43	5	3	2	1	3	3	2021-08-12	1	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
44	5	5	2	1	5	5	2021-08-12	5	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
45	5	3	2	1	3	7	2021-10-12	1	\N	36.5	f	2026-05-16 17:25:31.438879	\N	\N
46	5	8	2	1	8	15	2022-06-12	3	\N	36.7	f	2026-05-16 17:25:31.438879	\N	\N
47	5	9	2	2	9	17	2022-12-12	1	\N	36.5	f	2026-05-16 17:25:31.438879	\N	\N
48	5	10	2	2	10	20	2025-06-12	2	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
49	6	1	3	1	1	1	2018-08-18	6	6	36.5	f	2026-05-16 17:25:31.438879	\N	\N
50	6	6	3	1	6	6	2018-10-18	4	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
51	6	8	3	1	8	15	2019-08-18	3	\N	36.7	f	2026-05-16 17:25:31.438879	\N	\N
52	6	6	3	1	6	16	2019-08-18	1	\N	36.7	f	2026-05-16 17:25:31.438879	\N	\N
53	6	10	3	2	10	20	2022-08-18	2	\N	36.5	f	2026-05-16 17:25:31.438879	\N	\N
54	6	8	3	1	8	24	2024-08-18	3	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
55	7	2	2	1	2	2	2019-04-09	1	7	36.5	f	2026-05-16 17:25:31.438879	\N	\N
56	7	3	2	1	3	3	2019-06-09	2	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
57	7	8	2	1	8	15	2020-04-09	3	\N	36.7	f	2026-05-16 17:25:31.438879	\N	\N
58	7	9	2	2	9	17	2020-10-09	1	\N	36.5	f	2026-05-16 17:25:31.438879	\N	\N
59	7	8	2	1	8	24	2025-04-09	4	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
60	8	1	3	1	1	1	2020-09-14	6	8	36.5	f	2026-05-16 17:25:31.438879	\N	\N
61	8	6	3	1	6	6	2020-11-14	4	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
62	8	8	3	1	8	15	2021-09-14	3	\N	36.7	f	2026-05-16 17:25:31.438879	\N	\N
63	8	9	3	2	9	17	2022-03-14	1	\N	36.5	f	2026-05-16 17:25:31.438879	\N	\N
64	8	10	3	2	10	20	2024-09-14	2	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
65	10	2	2	1	2	2	2021-02-25	1	10	36.5	f	2026-05-16 17:25:31.438879	\N	\N
66	10	5	2	1	5	5	2021-04-25	5	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
67	10	8	2	1	8	15	2022-02-25	3	\N	36.7	f	2026-05-16 17:25:31.438879	\N	\N
68	10	9	2	2	9	17	2022-08-25	1	\N	36.5	f	2026-05-16 17:25:31.438879	\N	\N
69	10	10	2	2	10	20	2025-02-25	2	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
70	11	1	3	1	1	1	2018-05-03	6	11	36.5	f	2026-05-16 17:25:31.438879	\N	\N
71	11	3	3	1	3	3	2018-07-03	1	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
72	11	7	3	1	7	13	2018-11-03	3	\N	36.5	f	2026-05-16 17:25:31.438879	\N	\N
73	11	8	3	1	8	15	2019-05-03	3	\N	36.7	f	2026-05-16 17:25:31.438879	\N	\N
74	11	10	3	2	10	20	2022-05-03	2	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
75	11	8	3	1	8	24	2024-05-03	3	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
76	12	1	2	1	1	1	2019-10-16	6	12	36.5	f	2026-05-16 17:25:31.438879	\N	\N
77	12	6	2	1	6	6	2019-12-16	4	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
78	12	8	2	1	8	15	2020-10-16	3	\N	36.7	f	2026-05-16 17:25:31.438879	\N	\N
79	12	6	2	1	6	16	2020-10-16	1	\N	36.7	f	2026-05-16 17:25:31.438879	\N	\N
80	12	8	2	1	8	24	2025-10-16	3	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
81	13	3	3	1	3	3	2020-09-01	1	13	36.6	f	2026-05-16 17:25:31.438879	\N	\N
82	13	6	3	1	6	6	2020-09-01	4	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
83	13	8	3	1	8	15	2021-07-01	3	\N	36.7	f	2026-05-16 17:25:31.438879	\N	\N
84	13	9	3	2	9	17	2022-01-01	1	\N	36.5	f	2026-05-16 17:25:31.438879	\N	\N
85	13	10	3	2	10	20	2024-07-01	2	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
86	14	1	3	1	1	1	2017-09-27	6	14	36.5	f	2026-05-16 17:25:31.438879	\N	\N
87	14	8	3	1	8	15	2018-09-27	3	\N	36.7	f	2026-05-16 17:25:31.438879	\N	\N
88	14	9	3	2	9	17	2019-03-27	1	\N	36.5	f	2026-05-16 17:25:31.438879	\N	\N
89	14	10	3	2	10	20	2021-09-27	2	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
90	14	8	3	1	8	24	2023-09-27	3	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
91	15	1	2	1	1	1	2021-04-11	6	15	36.5	f	2026-05-16 17:25:31.438879	\N	\N
92	15	5	2	1	5	5	2021-06-11	5	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
93	15	6	2	1	6	6	2021-06-11	4	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
94	15	8	2	1	8	15	2022-04-11	3	\N	36.7	f	2026-05-16 17:25:31.438879	\N	\N
95	15	9	2	2	9	17	2022-10-11	1	\N	36.5	f	2026-05-16 17:25:31.438879	\N	\N
96	15	10	2	2	10	20	2025-04-11	2	\N	36.6	f	2026-05-16 17:25:31.438879	\N	\N
97	18	1	3	1	13	1	2026-05-17	\N	\N	\N	f	2026-05-17 00:44:12.063684	443	\N
98	8	2	3	1	2	2	2026-05-17	2	\N	\N	f	2026-05-17 19:37:17.485671	23	\N
99	8	4	3	1	4	4	2026-05-17	3	\N	\N	f	2026-05-17 19:38:57.474474	53	\N
\.


--
-- Data for Name: vaccination_scheme; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.vaccination_scheme (scheme_id, name, issuing_body, year, is_current) FROM stdin;
1	Cartilla Nacional de Vacunación 2024	SSA México	2024	t
2	Cartilla Nacional de Vacunación 2023	SSA México	2023	f
\.


--
-- Data for Name: vaccine_lots; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.vaccine_lots (lot_id, vaccine_id, clinic_id, lot_number, quantity_received, quantity_available, expiration_date, received_date, is_active, lot_status) FROM stdin;
13	1	1	BCG-2026-B002	100	99	2026-07-15	2026-05-15	t	Disponible
14	1	1	LOTE-HB-2024-001	100	72	2026-11-13	2026-04-17	t	Disponible
15	2	1	LOTE-BCG-2024-002	50	8	2026-06-11	2026-03-18	t	Disponible
16	3	2	LOTE-NEU-2024-003	80	5	2026-08-15	2026-04-02	t	Disponible
17	1	2	LOTE-HB-2024-004	60	0	2026-12-03	2026-04-27	t	Agotado
18	4	1	LOTE-VPH-2023-005	40	40	2026-05-07	2026-01-17	f	Caducado
11	11	3	OPV-2025-K001	100	88	2025-09-30	2025-01-10	f	Caducado
7	7	1	INFL-2025-G001	200	147	2025-06-30	2025-01-03	f	Caducado
20	5	1	ROT-2026-R002	50	50	2026-11-17	2026-05-17	t	Disponible
12	12	4	VPH-2025-L001	50	48	2027-06-30	2025-03-01	t	Disponible
22	10	1	DPT-2025-J001	6	6	2026-09-30	2026-05-17	t	Disponible
2	2	1	HEPB-2025-B001	150	108	2026-10-15	2025-01-05	t	Disponible
4	4	1	HEPBS-2025-D001	100	86	2026-10-15	2025-01-15	t	Disponible
3	3	1	PENT-2025-C001	100	69	2026-08-31	2025-01-15	t	Disponible
1	1	1	BCG-2025-A001	200	160	2026-03-31	2025-01-05	f	Caducado
5	5	1	ROTA-2025-E001	80	49	2025-12-15	2025-01-10	f	Caducado
19	7	1	INF-2026-I002	100	100	2026-10-17	2026-05-17	t	Disponible
10	10	2	DPT-2025-J001	70	7	2026-09-30	2025-02-10	t	Disponible
6	6	1	NEUM-2025-F001	120	72	2026-12-31	2025-01-20	t	Disponible
8	8	1	SRP-2025-H001	60	1	2026-06-30	2025-02-01	t	Disponible
9	9	2	PENTR-2025-I001	80	50	2026-08-31	2025-01-15	t	Disponible
\.


--
-- Data for Name: vaccine_vias; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.vaccine_vias (via_id, via) FROM stdin;
1	Intramuscular
2	Subcutánea
3	Oral
4	Intravenosa
5	Intradérmica
\.


--
-- Data for Name: vaccines; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.vaccines (vaccine_id, name, commercial_name, manufacturer_id, via_id, ideal_age_months, disease_prevented) FROM stdin;
1	BCG	BCG Birmex	1	1	0	Tuberculosis — dosis única al nacimiento
2	Hepatitis B	Engerix-B	5	2	0	Hepatitis B — primera dosis al nacimiento
3	Pentavalente acelular	Pentaxim	2	2	2	DPT + Hib + Polio inactivado — 3 dosis
4	Hepatitis B (serie)	Engerix-B pediátrica	5	2	2	Hepatitis B — dosis 2 y 3 de la serie
5	Rotavirus	RotaTeq	3	4	2	Diarrea por Rotavirus — 3 dosis orales
6	Neumococo conjugada	Prevenar 13	4	2	2	Neumococo 13V — 3 dosis + refuerzo
7	Influenza	Fluvax Pediátrica	10	2	6	Influenza estacional — anual desde 6 meses
8	SRP	M-M-R II	3	3	12	Sarampión, Rubeola, Parotiditis — 2 dosis
9	Pentavalente refuerzo	Pentaxim refuerzo	2	2	18	DPT + Hib + Polio — refuerzo 18 meses
10	DPT (refuerzo)	Tripacel	2	2	48	Difteria, Pertussis, Tétanos — refuerzo 4 años
11	OPV	Polio oral	1	4	60	Polio oral — Semanas Nacionales de Salud
12	VPH	Gardasil 9	3	2	132	Virus del Papiloma Humano — 5to grado primaria
\.


--
-- Data for Name: visit_area_movements; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.visit_area_movements (movement_id, visit_id, from_area_id, to_area_id, from_status, to_status, moved_at, moved_by, nfc_scan_id, movement_notes) FROM stdin;
\.


--
-- Data for Name: worker_clinic_assignment; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.worker_clinic_assignment (assignment_id, worker_id, clinic_id, area_id, start_date, end_date, is_active) FROM stdin;
1	1	1	5	2015-03-01	\N	t
2	2	1	2	2010-07-20	\N	t
3	3	1	3	2018-01-10	\N	t
4	4	1	4	2020-06-15	\N	t
5	5	2	7	2012-09-01	\N	t
6	6	2	8	2019-04-01	\N	t
7	7	3	12	2017-11-15	\N	t
8	8	3	11	2008-03-20	\N	t
9	9	2	9	2022-01-05	\N	t
10	10	4	13	2016-08-01	\N	t
11	11	4	14	2021-03-10	\N	t
12	12	5	15	2009-11-01	\N	t
13	13	5	14	2014-05-20	\N	t
14	14	1	3	2013-02-01	\N	t
15	15	1	2	2011-10-10	\N	t
\.


--
-- Data for Name: worker_emails; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.worker_emails (email_id, worker_id, email, is_primary) FROM stdin;
1	1	jose.perez@gmail.com	t
2	2	lucia.santos@gmail.com	t
3	3	mario.luna@gmail.com	t
4	4	elisa.campos@gmail.com	t
5	5	raul.mora@gmail.com	t
6	6	paty.rios@gmail.com	t
7	7	andres.leon@gmail.com	t
8	8	diana.paz@gmail.com	t
9	9	ivan.silva@gmail.com	t
10	10	karen.vega@gmail.com	t
11	11	tomas.gil@gmail.com	t
12	12	nora.reyes@gmail.com	t
13	13	alan.cruz@gmail.com	t
14	14	monica.pena@gmail.com	t
15	15	victor.soto@gmail.com	t
\.


--
-- Data for Name: worker_phones; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.worker_phones (phone_id, worker_id, phone, phone_type, is_primary) FROM stdin;
1	1	81-3001-1111	Celular	t
2	2	81-3001-2222	Celular	t
3	3	81-3001-3333	Celular	t
4	4	81-3001-4444	Celular	t
5	5	81-3001-5555	Celular	t
6	6	81-3001-6666	Celular	t
7	7	81-3001-7777	Celular	t
8	8	81-3001-8888	Celular	t
9	9	81-3001-9999	Celular	t
10	10	81-3002-0000	Celular	t
11	11	81-3002-1111	Celular	t
12	12	81-3002-2222	Celular	t
13	13	81-3002-3333	Celular	t
14	14	81-3002-4444	Celular	t
15	15	81-3002-5555	Celular	t
\.


--
-- Data for Name: worker_professional; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.worker_professional (worker_id, cedula_profesional, specialty_id, institution_id) FROM stdin;
1	5432109	1	1
1	5432109	5	2
2	5432876	1	1
2	5432876	3	3
3	6789012	2	6
4	4321098	4	4
5	4123456	1	2
5	4123456	4	5
6	7654321	5	5
7	8765432	8	7
8	3456789	1	3
8	3456789	6	3
9	6543210	2	3
10	7890123	4	5
11	9012345	2	6
12	2345678	1	1
13	2345678	7	4
14	5678901	3	4
15	6789012	5	2
\.


--
-- Data for Name: worker_schedules; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.worker_schedules (schedule_id, worker_id, clinic_id, day_of_week, entry_time, exit_time, shift_type) FROM stdin;
1	1	1	1	08:00:00	14:00:00	Matutino
2	1	1	2	08:00:00	14:00:00	Matutino
3	1	1	3	08:00:00	14:00:00	Matutino
4	2	1	1	08:00:00	15:00:00	Matutino
5	2	1	2	08:00:00	15:00:00	Matutino
6	3	1	1	08:00:00	14:00:00	Matutino
7	3	1	2	08:00:00	14:00:00	Matutino
8	4	1	1	08:00:00	14:00:00	Matutino
9	5	2	1	14:00:00	20:00:00	Vespertino
10	5	2	2	14:00:00	20:00:00	Vespertino
11	6	2	1	14:00:00	20:00:00	Vespertino
12	7	3	1	08:00:00	14:00:00	Matutino
13	7	3	2	08:00:00	14:00:00	Matutino
14	8	3	1	08:00:00	14:00:00	Matutino
15	9	2	1	14:00:00	20:00:00	Vespertino
16	10	4	1	08:00:00	14:00:00	Matutino
17	11	4	2	08:00:00	14:00:00	Matutino
18	12	5	1	14:00:00	20:00:00	Vespertino
19	13	5	2	14:00:00	20:00:00	Vespertino
20	14	1	1	08:00:00	14:00:00	Matutino
21	15	1	2	08:00:00	14:00:00	Matutino
22	1	1	5	08:00:00	14:00:00	Matutino
23	2	1	4	08:00:00	15:00:00	Matutino
24	2	1	5	08:00:00	15:00:00	Matutino
25	3	1	4	08:00:00	14:00:00	Matutino
26	3	1	5	08:00:00	14:00:00	Matutino
27	4	1	3	08:00:00	14:00:00	Matutino
28	4	1	4	08:00:00	14:00:00	Matutino
29	4	1	5	08:00:00	14:00:00	Matutino
30	5	2	4	14:00:00	20:00:00	Vespertino
31	5	2	5	14:00:00	20:00:00	Vespertino
32	6	2	3	14:00:00	20:00:00	Vespertino
33	6	2	4	14:00:00	20:00:00	Vespertino
34	6	2	5	14:00:00	20:00:00	Vespertino
35	7	3	4	08:00:00	14:00:00	Matutino
36	7	3	5	08:00:00	14:00:00	Matutino
37	8	3	3	08:00:00	14:00:00	Matutino
38	8	3	4	08:00:00	14:00:00	Matutino
39	8	3	5	08:00:00	14:00:00	Matutino
40	9	2	3	14:00:00	20:00:00	Vespertino
41	9	2	4	14:00:00	20:00:00	Vespertino
42	9	2	5	14:00:00	20:00:00	Vespertino
43	10	4	3	08:00:00	14:00:00	Matutino
44	10	4	4	08:00:00	14:00:00	Matutino
45	10	4	5	08:00:00	14:00:00	Matutino
46	11	4	3	08:00:00	14:00:00	Matutino
47	11	4	4	08:00:00	14:00:00	Matutino
48	11	4	5	08:00:00	14:00:00	Matutino
49	12	5	3	14:00:00	20:00:00	Vespertino
50	12	5	4	14:00:00	20:00:00	Vespertino
51	12	5	5	14:00:00	20:00:00	Vespertino
52	13	5	3	14:00:00	20:00:00	Vespertino
53	13	5	4	14:00:00	20:00:00	Vespertino
54	13	5	5	14:00:00	20:00:00	Vespertino
55	14	1	3	08:00:00	14:00:00	Matutino
56	14	1	4	08:00:00	14:00:00	Matutino
57	14	1	5	08:00:00	14:00:00	Matutino
58	15	1	3	08:00:00	14:00:00	Matutino
59	15	1	4	08:00:00	14:00:00	Matutino
60	15	1	5	08:00:00	14:00:00	Matutino
\.


--
-- Data for Name: workers; Type: TABLE DATA; Schema: public; Owner: vaccine_user
--

COPY public.workers (worker_id, role_id, first_name, last_name, curp, address_id, birth_date, hire_date, created_at, is_active) FROM stdin;
3	3	Mario	Luna	LUMM870303HNLRNR03	3	1987-03-03	2020-03-01	2026-05-16 17:04:27.551702	t
4	4	Elisa	Campos	CAEE880404MNLRML04	4	1988-04-04	2020-04-01	2026-05-16 17:04:27.551702	t
5	5	Ra£l	Mora	MORR890505HNLRRA05	5	1989-05-05	2020-05-01	2026-05-16 17:04:27.551702	t
6	1	Paty	R¡os	RIPP900606MNLRRT06	6	1990-06-06	2020-06-01	2026-05-16 17:04:27.551702	t
8	3	Diana	Paz	PADD920808MNLRDZ08	8	1992-08-08	2020-08-01	2026-05-16 17:04:27.551702	t
13	3	Alan	Cruz	CUAA970101HNLRRL13	13	1997-01-01	2021-01-01	2026-05-16 17:04:27.551702	t
14	4	M¢nica	Pe¤a	PEMM980202MNLRXN14	14	1998-02-02	2021-02-01	2026-05-16 17:04:27.551702	t
15	5	V¡ctor	Soto	SOVV990303HNLRCT15	15	1999-03-03	2021-03-01	2026-05-16 17:04:27.551702	t
1	1	Jos‚	P‚rez	PEPJ850101HNLRRS01	1	1985-01-01	2020-01-01	2026-05-16 17:04:27.551702	t
2	2	Luc¡a	Santos	SALU860202MNLRNC02	2	1986-02-02	2020-02-01	2026-05-16 17:04:27.551702	t
7	2	Andr‚s	Vega	LEAA910707HNLRNN07	7	1991-07-07	2020-07-01	2026-05-16 17:04:27.551702	t
9	4	Sof¡a	Ramos	SIII930909HNLRLV09	9	1993-09-09	2020-09-01	2026-05-16 17:04:27.551702	t
10	5	Ram¢n	Garc¡a	VEKK941010MNLRGR10	10	1994-10-10	2020-10-01	2026-05-16 17:04:27.551702	t
11	1	Ang‚lica	Fuentes	GITT951111HNLRLM11	11	1995-11-11	2020-11-01	2026-05-16 17:04:27.551702	t
12	2	Nora	T‚llez	RENN961212MNLRYR12	12	1996-12-12	2020-12-01	2026-05-16 17:04:27.551702	t
\.


--
-- Name: addresses_address_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.addresses_address_id_seq', 21, true);


--
-- Name: allergies_allergy_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.allergies_allergy_id_seq', 15, true);


--
-- Name: application_sites_application_site_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.application_sites_application_site_id_seq', 8, true);


--
-- Name: appointments_appointment_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.appointments_appointment_id_seq', 21, true);


--
-- Name: area_equipment_area_equipment_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.area_equipment_area_equipment_id_seq', 10, true);


--
-- Name: audit_log_audit_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.audit_log_audit_id_seq', 125, true);


--
-- Name: blood_types_blood_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.blood_types_blood_type_id_seq', 8, true);


--
-- Name: clinic_area_types_area_type_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.clinic_area_types_area_type_id_seq', 6, true);


--
-- Name: clinic_areas_area_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.clinic_areas_area_id_seq', 16, true);


--
-- Name: clinic_inventory_inventory_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.clinic_inventory_inventory_id_seq', 12, true);


--
-- Name: clinics_clinic_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.clinics_clinic_id_seq', 10, true);


--
-- Name: countries_country_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.countries_country_id_seq', 8, true);


--
-- Name: equipment_catalog_equipment_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.equipment_catalog_equipment_id_seq', 10, true);


--
-- Name: guardian_accounts_guardian_account_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.guardian_accounts_guardian_account_id_seq', 3, true);


--
-- Name: guardian_emails_email_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.guardian_emails_email_id_seq', 16, true);


--
-- Name: guardian_phones_phone_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.guardian_phones_phone_id_seq', 20, true);


--
-- Name: guardians_guardian_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.guardians_guardian_id_seq', 20, true);


--
-- Name: institutions_institution_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.institutions_institution_id_seq', 7, true);


--
-- Name: inventory_movements_movement_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.inventory_movements_movement_id_seq', 391, true);


--
-- Name: inventory_transfers_transfer_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.inventory_transfers_transfer_id_seq', 6, true);


--
-- Name: manufacturers_manufacturer_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.manufacturers_manufacturer_id_seq', 10, true);


--
-- Name: marital_status_marital_status_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.marital_status_marital_status_id_seq', 4, true);


--
-- Name: municipalities_municipality_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.municipalities_municipality_id_seq', 10, true);


--
-- Name: neighborhoods_neighborhood_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.neighborhoods_neighborhood_id_seq', 23, true);


--
-- Name: nfc_cards_nfc_card_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.nfc_cards_nfc_card_id_seq', 1, false);


--
-- Name: nfc_scan_events_scan_event_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.nfc_scan_events_scan_event_id_seq', 1, false);


--
-- Name: occupations_occupation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.occupations_occupation_id_seq', 15, true);


--
-- Name: patient_allergies_patient_allergy_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.patient_allergies_patient_allergy_id_seq', 15, true);


--
-- Name: patient_clinic_visits_visit_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.patient_clinic_visits_visit_id_seq', 1, false);


--
-- Name: patient_guardian_relations_relation_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.patient_guardian_relations_relation_id_seq', 19, true);


--
-- Name: patient_vaccine_schedule_schedule_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.patient_vaccine_schedule_schedule_id_seq', 494, true);


--
-- Name: patients_patient_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.patients_patient_id_seq', 19, true);


--
-- Name: post_vaccine_reactions_reaction_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.post_vaccine_reactions_reaction_id_seq', 1, false);


--
-- Name: roles_role_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.roles_role_id_seq', 7, true);


--
-- Name: scheme_completion_alerts_alert_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.scheme_completion_alerts_alert_id_seq', 1, false);


--
-- Name: scheme_doses_dose_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.scheme_doses_dose_id_seq', 26, true);


--
-- Name: specialties_specialty_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.specialties_specialty_id_seq', 12, true);


--
-- Name: states_state_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.states_state_id_seq', 15, true);


--
-- Name: supply_catalog_supply_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.supply_catalog_supply_id_seq', 12, true);


--
-- Name: users_user_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.users_user_id_seq', 5, true);


--
-- Name: vaccination_records_record_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.vaccination_records_record_id_seq', 99, true);


--
-- Name: vaccination_scheme_scheme_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.vaccination_scheme_scheme_id_seq', 2, true);


--
-- Name: vaccine_lots_lot_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.vaccine_lots_lot_id_seq', 22, true);


--
-- Name: vaccine_vias_via_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.vaccine_vias_via_id_seq', 5, true);


--
-- Name: vaccines_vaccine_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.vaccines_vaccine_id_seq', 12, true);


--
-- Name: visit_area_movements_movement_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.visit_area_movements_movement_id_seq', 1, false);


--
-- Name: worker_clinic_assignment_assignment_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.worker_clinic_assignment_assignment_id_seq', 15, true);


--
-- Name: worker_emails_email_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.worker_emails_email_id_seq', 15, true);


--
-- Name: worker_phones_phone_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.worker_phones_phone_id_seq', 15, true);


--
-- Name: worker_schedules_schedule_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.worker_schedules_schedule_id_seq', 60, true);


--
-- Name: workers_worker_id_seq; Type: SEQUENCE SET; Schema: public; Owner: vaccine_user
--

SELECT pg_catalog.setval('public.workers_worker_id_seq', 15, true);


--
-- Name: addresses addresses_neighborhood_id_street_ext_number_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.addresses
    ADD CONSTRAINT addresses_neighborhood_id_street_ext_number_key UNIQUE (neighborhood_id, street, ext_number);


--
-- Name: addresses addresses_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.addresses
    ADD CONSTRAINT addresses_pkey PRIMARY KEY (address_id);


--
-- Name: allergies allergies_name_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.allergies
    ADD CONSTRAINT allergies_name_key UNIQUE (name);


--
-- Name: allergies allergies_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.allergies
    ADD CONSTRAINT allergies_pkey PRIMARY KEY (allergy_id);


--
-- Name: application_sites application_sites_application_site_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.application_sites
    ADD CONSTRAINT application_sites_application_site_key UNIQUE (application_site);


--
-- Name: application_sites application_sites_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.application_sites
    ADD CONSTRAINT application_sites_pkey PRIMARY KEY (application_site_id);


--
-- Name: appointments appointments_clinic_id_area_id_scheduled_at_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_clinic_id_area_id_scheduled_at_key UNIQUE (clinic_id, area_id, scheduled_at);


--
-- Name: appointments appointments_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_pkey PRIMARY KEY (appointment_id);


--
-- Name: appointments appointments_worker_id_scheduled_at_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_worker_id_scheduled_at_key UNIQUE (worker_id, scheduled_at);


--
-- Name: area_equipment area_equipment_area_id_equipment_id_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.area_equipment
    ADD CONSTRAINT area_equipment_area_id_equipment_id_key UNIQUE (area_id, equipment_id);


--
-- Name: area_equipment area_equipment_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.area_equipment
    ADD CONSTRAINT area_equipment_pkey PRIMARY KEY (area_equipment_id);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (audit_id);


--
-- Name: blood_types blood_types_blood_type_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.blood_types
    ADD CONSTRAINT blood_types_blood_type_key UNIQUE (blood_type);


--
-- Name: blood_types blood_types_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.blood_types
    ADD CONSTRAINT blood_types_pkey PRIMARY KEY (blood_type_id);


--
-- Name: clinic_area_types clinic_area_types_area_type_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.clinic_area_types
    ADD CONSTRAINT clinic_area_types_area_type_key UNIQUE (area_type);


--
-- Name: clinic_area_types clinic_area_types_code_unique; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.clinic_area_types
    ADD CONSTRAINT clinic_area_types_code_unique UNIQUE (code);


--
-- Name: clinic_area_types clinic_area_types_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.clinic_area_types
    ADD CONSTRAINT clinic_area_types_pkey PRIMARY KEY (area_type_id);


--
-- Name: clinic_areas clinic_areas_clinic_id_name_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.clinic_areas
    ADD CONSTRAINT clinic_areas_clinic_id_name_key UNIQUE (clinic_id, name);


--
-- Name: clinic_areas clinic_areas_code_unique; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.clinic_areas
    ADD CONSTRAINT clinic_areas_code_unique UNIQUE (clinic_id, code);


--
-- Name: clinic_areas clinic_areas_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.clinic_areas
    ADD CONSTRAINT clinic_areas_pkey PRIMARY KEY (area_id);


--
-- Name: clinic_inventory clinic_inventory_clinic_id_supply_id_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.clinic_inventory
    ADD CONSTRAINT clinic_inventory_clinic_id_supply_id_key UNIQUE (clinic_id, supply_id);


--
-- Name: clinic_inventory clinic_inventory_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.clinic_inventory
    ADD CONSTRAINT clinic_inventory_pkey PRIMARY KEY (inventory_id);


--
-- Name: clinics clinics_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.clinics
    ADD CONSTRAINT clinics_pkey PRIMARY KEY (clinic_id);


--
-- Name: countries countries_iso_code_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.countries
    ADD CONSTRAINT countries_iso_code_key UNIQUE (iso_code);


--
-- Name: countries countries_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.countries
    ADD CONSTRAINT countries_pkey PRIMARY KEY (country_id);


--
-- Name: equipment_catalog equipment_catalog_name_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.equipment_catalog
    ADD CONSTRAINT equipment_catalog_name_key UNIQUE (name);


--
-- Name: equipment_catalog equipment_catalog_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.equipment_catalog
    ADD CONSTRAINT equipment_catalog_pkey PRIMARY KEY (equipment_id);


--
-- Name: guardian_accounts guardian_accounts_email_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.guardian_accounts
    ADD CONSTRAINT guardian_accounts_email_key UNIQUE (email);


--
-- Name: guardian_accounts guardian_accounts_guardian_id_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.guardian_accounts
    ADD CONSTRAINT guardian_accounts_guardian_id_key UNIQUE (guardian_id);


--
-- Name: guardian_accounts guardian_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.guardian_accounts
    ADD CONSTRAINT guardian_accounts_pkey PRIMARY KEY (guardian_account_id);


--
-- Name: guardian_emails guardian_emails_guardian_id_email_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.guardian_emails
    ADD CONSTRAINT guardian_emails_guardian_id_email_key UNIQUE (guardian_id, email);


--
-- Name: guardian_emails guardian_emails_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.guardian_emails
    ADD CONSTRAINT guardian_emails_pkey PRIMARY KEY (email_id);


--
-- Name: guardian_phones guardian_phones_guardian_id_phone_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.guardian_phones
    ADD CONSTRAINT guardian_phones_guardian_id_phone_key UNIQUE (guardian_id, phone);


--
-- Name: guardian_phones guardian_phones_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.guardian_phones
    ADD CONSTRAINT guardian_phones_pkey PRIMARY KEY (phone_id);


--
-- Name: guardians guardians_curp_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.guardians
    ADD CONSTRAINT guardians_curp_key UNIQUE (curp);


--
-- Name: guardians guardians_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.guardians
    ADD CONSTRAINT guardians_pkey PRIMARY KEY (guardian_id);


--
-- Name: institutions institutions_institution_name_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.institutions
    ADD CONSTRAINT institutions_institution_name_key UNIQUE (institution_name);


--
-- Name: institutions institutions_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.institutions
    ADD CONSTRAINT institutions_pkey PRIMARY KEY (institution_id);


--
-- Name: inventory_movements inventory_movements_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.inventory_movements
    ADD CONSTRAINT inventory_movements_pkey PRIMARY KEY (movement_id);


--
-- Name: inventory_transfers inventory_transfers_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_transfers
    ADD CONSTRAINT inventory_transfers_pkey PRIMARY KEY (transfer_id);


--
-- Name: manufacturers manufacturers_name_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.manufacturers
    ADD CONSTRAINT manufacturers_name_key UNIQUE (name);


--
-- Name: manufacturers manufacturers_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.manufacturers
    ADD CONSTRAINT manufacturers_pkey PRIMARY KEY (manufacturer_id);


--
-- Name: marital_status marital_status_marital_status_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.marital_status
    ADD CONSTRAINT marital_status_marital_status_key UNIQUE (marital_status);


--
-- Name: marital_status marital_status_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.marital_status
    ADD CONSTRAINT marital_status_pkey PRIMARY KEY (marital_status_id);


--
-- Name: municipalities municipalities_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.municipalities
    ADD CONSTRAINT municipalities_pkey PRIMARY KEY (municipality_id);


--
-- Name: municipalities municipalities_state_id_name_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.municipalities
    ADD CONSTRAINT municipalities_state_id_name_key UNIQUE (state_id, name);


--
-- Name: neighborhoods neighborhoods_municipality_id_name_zip_code_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.neighborhoods
    ADD CONSTRAINT neighborhoods_municipality_id_name_zip_code_key UNIQUE (municipality_id, name, zip_code);


--
-- Name: neighborhoods neighborhoods_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.neighborhoods
    ADD CONSTRAINT neighborhoods_pkey PRIMARY KEY (neighborhood_id);


--
-- Name: nfc_cards nfc_cards_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.nfc_cards
    ADD CONSTRAINT nfc_cards_pkey PRIMARY KEY (nfc_card_id);


--
-- Name: nfc_cards nfc_cards_uid_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.nfc_cards
    ADD CONSTRAINT nfc_cards_uid_key UNIQUE (uid);


--
-- Name: nfc_devices nfc_devices_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.nfc_devices
    ADD CONSTRAINT nfc_devices_pkey PRIMARY KEY (device_id);


--
-- Name: nfc_scan_events nfc_scan_events_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.nfc_scan_events
    ADD CONSTRAINT nfc_scan_events_pkey PRIMARY KEY (scan_event_id);


--
-- Name: occupations occupations_occupation_name_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.occupations
    ADD CONSTRAINT occupations_occupation_name_key UNIQUE (occupation_name);


--
-- Name: occupations occupations_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.occupations
    ADD CONSTRAINT occupations_pkey PRIMARY KEY (occupation_id);


--
-- Name: patient_allergies patient_allergies_patient_id_allergy_id_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.patient_allergies
    ADD CONSTRAINT patient_allergies_patient_id_allergy_id_key UNIQUE (patient_id, allergy_id);


--
-- Name: patient_allergies patient_allergies_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.patient_allergies
    ADD CONSTRAINT patient_allergies_pkey PRIMARY KEY (patient_allergy_id);


--
-- Name: patient_clinic_visits patient_clinic_visits_appointment_id_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patient_clinic_visits
    ADD CONSTRAINT patient_clinic_visits_appointment_id_key UNIQUE (appointment_id);


--
-- Name: patient_clinic_visits patient_clinic_visits_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patient_clinic_visits
    ADD CONSTRAINT patient_clinic_visits_pkey PRIMARY KEY (visit_id);


--
-- Name: patient_guardian_relations patient_guardian_relations_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.patient_guardian_relations
    ADD CONSTRAINT patient_guardian_relations_pkey PRIMARY KEY (relation_id);


--
-- Name: patient_vaccine_schedule patient_vaccine_schedule_patient_id_scheme_dose_id_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.patient_vaccine_schedule
    ADD CONSTRAINT patient_vaccine_schedule_patient_id_scheme_dose_id_key UNIQUE (patient_id, scheme_dose_id);


--
-- Name: patient_vaccine_schedule patient_vaccine_schedule_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.patient_vaccine_schedule
    ADD CONSTRAINT patient_vaccine_schedule_pkey PRIMARY KEY (schedule_id);


--
-- Name: patients patients_curp_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.patients
    ADD CONSTRAINT patients_curp_key UNIQUE (curp);


--
-- Name: patients patients_nfc_token_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.patients
    ADD CONSTRAINT patients_nfc_token_key UNIQUE (nfc_token);


--
-- Name: patients patients_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.patients
    ADD CONSTRAINT patients_pkey PRIMARY KEY (patient_id);


--
-- Name: post_vaccine_reactions post_vaccine_reactions_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.post_vaccine_reactions
    ADD CONSTRAINT post_vaccine_reactions_pkey PRIMARY KEY (reaction_id);


--
-- Name: roles roles_name_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_name_key UNIQUE (name);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (role_id);


--
-- Name: scheme_completion_alerts scheme_completion_alerts_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.scheme_completion_alerts
    ADD CONSTRAINT scheme_completion_alerts_pkey PRIMARY KEY (alert_id);


--
-- Name: scheme_doses scheme_doses_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.scheme_doses
    ADD CONSTRAINT scheme_doses_pkey PRIMARY KEY (dose_id);


--
-- Name: scheme_doses scheme_doses_scheme_id_vaccine_id_dose_number_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.scheme_doses
    ADD CONSTRAINT scheme_doses_scheme_id_vaccine_id_dose_number_key UNIQUE (scheme_id, vaccine_id, dose_number);


--
-- Name: specialties specialties_name_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.specialties
    ADD CONSTRAINT specialties_name_key UNIQUE (name);


--
-- Name: specialties specialties_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.specialties
    ADD CONSTRAINT specialties_pkey PRIMARY KEY (specialty_id);


--
-- Name: states states_country_id_code_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.states
    ADD CONSTRAINT states_country_id_code_key UNIQUE (country_id, code);


--
-- Name: states states_country_id_name_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.states
    ADD CONSTRAINT states_country_id_name_key UNIQUE (country_id, name);


--
-- Name: states states_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.states
    ADD CONSTRAINT states_pkey PRIMARY KEY (state_id);


--
-- Name: supply_catalog supply_catalog_name_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.supply_catalog
    ADD CONSTRAINT supply_catalog_name_key UNIQUE (name);


--
-- Name: supply_catalog supply_catalog_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.supply_catalog
    ADD CONSTRAINT supply_catalog_pkey PRIMARY KEY (supply_id);


--
-- Name: patient_vaccine_schedule unique_patient_dose; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.patient_vaccine_schedule
    ADD CONSTRAINT unique_patient_dose UNIQUE (patient_id, scheme_dose_id);


--
-- Name: vaccination_records uq_vaccination_patient_dose; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccination_records
    ADD CONSTRAINT uq_vaccination_patient_dose UNIQUE (patient_id, scheme_dose_id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- Name: users users_worker_id_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_worker_id_key UNIQUE (worker_id);


--
-- Name: vaccination_records vaccination_records_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccination_records
    ADD CONSTRAINT vaccination_records_pkey PRIMARY KEY (record_id);


--
-- Name: vaccination_scheme vaccination_scheme_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccination_scheme
    ADD CONSTRAINT vaccination_scheme_pkey PRIMARY KEY (scheme_id);


--
-- Name: vaccine_lots vaccine_lots_lot_number_clinic_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccine_lots
    ADD CONSTRAINT vaccine_lots_lot_number_clinic_key UNIQUE (lot_number, clinic_id);


--
-- Name: vaccine_lots vaccine_lots_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccine_lots
    ADD CONSTRAINT vaccine_lots_pkey PRIMARY KEY (lot_id);


--
-- Name: vaccine_vias vaccine_vias_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccine_vias
    ADD CONSTRAINT vaccine_vias_pkey PRIMARY KEY (via_id);


--
-- Name: vaccine_vias vaccine_vias_via_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccine_vias
    ADD CONSTRAINT vaccine_vias_via_key UNIQUE (via);


--
-- Name: vaccines vaccines_commercial_name_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccines
    ADD CONSTRAINT vaccines_commercial_name_key UNIQUE (commercial_name);


--
-- Name: vaccines vaccines_name_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccines
    ADD CONSTRAINT vaccines_name_key UNIQUE (name);


--
-- Name: vaccines vaccines_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccines
    ADD CONSTRAINT vaccines_pkey PRIMARY KEY (vaccine_id);


--
-- Name: visit_area_movements visit_area_movements_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.visit_area_movements
    ADD CONSTRAINT visit_area_movements_pkey PRIMARY KEY (movement_id);


--
-- Name: worker_clinic_assignment worker_clinic_assignment_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.worker_clinic_assignment
    ADD CONSTRAINT worker_clinic_assignment_pkey PRIMARY KEY (assignment_id);


--
-- Name: worker_emails worker_emails_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.worker_emails
    ADD CONSTRAINT worker_emails_pkey PRIMARY KEY (email_id);


--
-- Name: worker_emails worker_emails_worker_id_email_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.worker_emails
    ADD CONSTRAINT worker_emails_worker_id_email_key UNIQUE (worker_id, email);


--
-- Name: worker_phones worker_phones_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.worker_phones
    ADD CONSTRAINT worker_phones_pkey PRIMARY KEY (phone_id);


--
-- Name: worker_phones worker_phones_worker_id_phone_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.worker_phones
    ADD CONSTRAINT worker_phones_worker_id_phone_key UNIQUE (worker_id, phone);


--
-- Name: worker_professional worker_professional_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.worker_professional
    ADD CONSTRAINT worker_professional_pkey PRIMARY KEY (worker_id, specialty_id);


--
-- Name: worker_schedules worker_schedules_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.worker_schedules
    ADD CONSTRAINT worker_schedules_pkey PRIMARY KEY (schedule_id);


--
-- Name: workers workers_curp_key; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.workers
    ADD CONSTRAINT workers_curp_key UNIQUE (curp);


--
-- Name: workers workers_pkey; Type: CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.workers
    ADD CONSTRAINT workers_pkey PRIMARY KEY (worker_id);


--
-- Name: idx_alerts_due_date; Type: INDEX; Schema: public; Owner: vaccine_user
--

CREATE INDEX idx_alerts_due_date ON public.scheme_completion_alerts USING btree (due_date, status) WHERE ((status)::text = 'Pendiente'::text);


--
-- Name: idx_alerts_patient_status; Type: INDEX; Schema: public; Owner: vaccine_user
--

CREATE INDEX idx_alerts_patient_status ON public.scheme_completion_alerts USING btree (patient_id, status);


--
-- Name: idx_appointments_patient; Type: INDEX; Schema: public; Owner: vaccine_user
--

CREATE INDEX idx_appointments_patient ON public.appointments USING btree (patient_id, scheduled_at);


--
-- Name: idx_appointments_status_date; Type: INDEX; Schema: public; Owner: vaccine_user
--

CREATE INDEX idx_appointments_status_date ON public.appointments USING btree (appointment_status, scheduled_at) WHERE ((appointment_status)::text <> ALL ((ARRAY['Cancelada'::character varying, 'No Show'::character varying, 'Completada'::character varying])::text[]));


--
-- Name: idx_appointments_worker_date; Type: INDEX; Schema: public; Owner: vaccine_user
--

CREATE INDEX idx_appointments_worker_date ON public.appointments USING btree (worker_id, scheduled_at);


--
-- Name: idx_audit_log_table_record; Type: INDEX; Schema: public; Owner: vaccine_user
--

CREATE INDEX idx_audit_log_table_record ON public.audit_log USING btree (table_name, record_id);


--
-- Name: idx_lots_expiry_alert; Type: INDEX; Schema: public; Owner: vaccine_user
--

CREATE INDEX idx_lots_expiry_alert ON public.vaccine_lots USING btree (expiration_date, clinic_id) WHERE ((lot_status)::text = 'Disponible'::text);


--
-- Name: idx_lots_low_stock; Type: INDEX; Schema: public; Owner: vaccine_user
--

CREATE INDEX idx_lots_low_stock ON public.vaccine_lots USING btree (quantity_available, clinic_id) WHERE ((lot_status)::text = 'Disponible'::text);


--
-- Name: idx_movements_clinic; Type: INDEX; Schema: public; Owner: vaccine_user
--

CREATE INDEX idx_movements_clinic ON public.inventory_movements USING btree (clinic_id);


--
-- Name: idx_movements_date; Type: INDEX; Schema: public; Owner: vaccine_user
--

CREATE INDEX idx_movements_date ON public.inventory_movements USING btree (created_at DESC);


--
-- Name: idx_movements_lot; Type: INDEX; Schema: public; Owner: vaccine_user
--

CREATE INDEX idx_movements_lot ON public.inventory_movements USING btree (lot_id);


--
-- Name: idx_movements_ref; Type: INDEX; Schema: public; Owner: vaccine_user
--

CREATE INDEX idx_movements_ref ON public.inventory_movements USING btree (reference_id, reference_type);


--
-- Name: idx_movements_type; Type: INDEX; Schema: public; Owner: vaccine_user
--

CREATE INDEX idx_movements_type ON public.inventory_movements USING btree (movement_type);


--
-- Name: idx_movements_visit; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_movements_visit ON public.visit_area_movements USING btree (visit_id, moved_at);


--
-- Name: idx_movements_worker; Type: INDEX; Schema: public; Owner: vaccine_user
--

CREATE INDEX idx_movements_worker ON public.inventory_movements USING btree (worker_id);


--
-- Name: idx_nfc_scan_events_card; Type: INDEX; Schema: public; Owner: vaccine_user
--

CREATE INDEX idx_nfc_scan_events_card ON public.nfc_scan_events USING btree (nfc_card_id, scanned_at);


--
-- Name: idx_patients_active; Type: INDEX; Schema: public; Owner: vaccine_user
--

CREATE INDEX idx_patients_active ON public.patients USING btree (patient_id) WHERE (is_active = true);


--
-- Name: idx_patients_curp; Type: INDEX; Schema: public; Owner: vaccine_user
--

CREATE INDEX idx_patients_curp ON public.patients USING btree (curp);


--
-- Name: idx_patients_nfc_token; Type: INDEX; Schema: public; Owner: vaccine_user
--

CREATE INDEX idx_patients_nfc_token ON public.patients USING btree (nfc_token);


--
-- Name: idx_pvs_due_date_status; Type: INDEX; Schema: public; Owner: vaccine_user
--

CREATE INDEX idx_pvs_due_date_status ON public.patient_vaccine_schedule USING btree (due_date, status) WHERE ((status)::text = ANY ((ARRAY['Pendiente'::character varying, 'Atrasada'::character varying])::text[]));


--
-- Name: idx_pvs_patient_status; Type: INDEX; Schema: public; Owner: vaccine_user
--

CREATE INDEX idx_pvs_patient_status ON public.patient_vaccine_schedule USING btree (patient_id, status);


--
-- Name: idx_transfers_from; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_transfers_from ON public.inventory_transfers USING btree (from_clinic_id);


--
-- Name: idx_transfers_lot; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_transfers_lot ON public.inventory_transfers USING btree (lot_id);


--
-- Name: idx_transfers_requested; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_transfers_requested ON public.inventory_transfers USING btree (requested_at DESC);


--
-- Name: idx_transfers_requester; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_transfers_requester ON public.inventory_transfers USING btree (requested_by);


--
-- Name: idx_transfers_status; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_transfers_status ON public.inventory_transfers USING btree (transfer_status);


--
-- Name: idx_transfers_to; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_transfers_to ON public.inventory_transfers USING btree (to_clinic_id);


--
-- Name: idx_vaccination_records_date; Type: INDEX; Schema: public; Owner: vaccine_user
--

CREATE INDEX idx_vaccination_records_date ON public.vaccination_records USING btree (applied_date);


--
-- Name: idx_vaccination_records_pat; Type: INDEX; Schema: public; Owner: vaccine_user
--

CREATE INDEX idx_vaccination_records_pat ON public.vaccination_records USING btree (patient_id);


--
-- Name: idx_vaccination_records_schedule; Type: INDEX; Schema: public; Owner: vaccine_user
--

CREATE INDEX idx_vaccination_records_schedule ON public.vaccination_records USING btree (patient_schedule_id);


--
-- Name: idx_visits_active_clinic; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_visits_active_clinic ON public.patient_clinic_visits USING btree (clinic_id, visit_status) WHERE (visit_status <> ALL (ARRAY['Finalizado'::public.visit_status, 'Abandono'::public.visit_status, 'Cancelado'::public.visit_status]));


--
-- Name: idx_visits_active_patient; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_visits_active_patient ON public.patient_clinic_visits USING btree (patient_id, visit_status) WHERE (visit_status <> ALL (ARRAY['Finalizado'::public.visit_status, 'Abandono'::public.visit_status, 'Cancelado'::public.visit_status]));


--
-- Name: idx_visits_patient_date; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_visits_patient_date ON public.patient_clinic_visits USING btree (patient_id, checked_in_at DESC);


--
-- Name: idx_visits_waiting_since; Type: INDEX; Schema: public; Owner: postgres
--

CREATE INDEX idx_visits_waiting_since ON public.patient_clinic_visits USING btree (waiting_since) WHERE (visit_status = 'En espera'::public.visit_status);


--
-- Name: idx_vr_visit; Type: INDEX; Schema: public; Owner: vaccine_user
--

CREATE INDEX idx_vr_visit ON public.vaccination_records USING btree (visit_id);


--
-- Name: uq_one_active_visit_per_patient; Type: INDEX; Schema: public; Owner: postgres
--

CREATE UNIQUE INDEX uq_one_active_visit_per_patient ON public.patient_clinic_visits USING btree (patient_id) WHERE (visit_status <> ALL (ARRAY['Finalizado'::public.visit_status, 'Abandono'::public.visit_status, 'Cancelado'::public.visit_status]));


--
-- Name: vw_patients _RETURN; Type: RULE; Schema: public; Owner: postgres
--

CREATE OR REPLACE VIEW public.vw_patients AS
 SELECT p.patient_id,
    p.first_name,
    p.last_name,
    (((p.first_name)::text || ' '::text) || (p.last_name)::text) AS full_name,
    p.birth_date,
    p.gender,
    p.weight_kg,
    p.premature,
    p.curp,
    bt.blood_type,
    (((g.first_name)::text || ' '::text) || (g.last_name)::text) AS guardian_name,
    ph.phone AS guardian_phone,
    string_agg(DISTINCT (al.name)::text, ', '::text) AS allergies
   FROM ((((((public.patients p
     LEFT JOIN public.blood_types bt ON ((bt.blood_type_id = p.blood_type_id)))
     LEFT JOIN public.patient_guardian_relations pgr ON (((pgr.patient_id = p.patient_id) AND (pgr.is_primary = true))))
     LEFT JOIN public.guardians g ON ((g.guardian_id = pgr.guardian_id)))
     LEFT JOIN public.guardian_phones ph ON (((ph.guardian_id = g.guardian_id) AND (ph.is_primary = true))))
     LEFT JOIN public.patient_allergies pa ON ((pa.patient_id = p.patient_id)))
     LEFT JOIN public.allergies al ON ((al.allergy_id = pa.allergy_id)))
  GROUP BY p.patient_id, bt.blood_type, g.first_name, g.last_name, ph.phone;


--
-- Name: patients trg_audit_patients; Type: TRIGGER; Schema: public; Owner: vaccine_user
--

CREATE TRIGGER trg_audit_patients AFTER INSERT OR DELETE OR UPDATE ON public.patients FOR EACH ROW EXECUTE FUNCTION public.fn_audit_patient_changes();


--
-- Name: vaccination_records trg_audit_vaccination_records; Type: TRIGGER; Schema: public; Owner: vaccine_user
--

CREATE TRIGGER trg_audit_vaccination_records AFTER INSERT OR DELETE OR UPDATE ON public.vaccination_records FOR EACH ROW EXECUTE FUNCTION public.fn_audit_vaccination_records();


--
-- Name: workers trg_audit_workers; Type: TRIGGER; Schema: public; Owner: vaccine_user
--

CREATE TRIGGER trg_audit_workers AFTER INSERT OR DELETE OR UPDATE ON public.workers FOR EACH ROW EXECUTE FUNCTION public.fn_audit_worker_changes();


--
-- Name: appointments trg_auto_assign_worker_area; Type: TRIGGER; Schema: public; Owner: vaccine_user
--

CREATE TRIGGER trg_auto_assign_worker_area AFTER INSERT ON public.appointments FOR EACH ROW EXECUTE FUNCTION public.fn_auto_assign_worker_area();


--
-- Name: vaccine_lots trg_auto_lot_status; Type: TRIGGER; Schema: public; Owner: vaccine_user
--

CREATE TRIGGER trg_auto_lot_status BEFORE UPDATE ON public.vaccine_lots FOR EACH ROW EXECUTE FUNCTION public.fn_auto_lot_status();


--
-- Name: vaccination_records trg_complete_appointment_on_vaccination; Type: TRIGGER; Schema: public; Owner: vaccine_user
--

CREATE TRIGGER trg_complete_appointment_on_vaccination AFTER INSERT ON public.vaccination_records FOR EACH ROW EXECUTE FUNCTION public.fn_complete_appointment_on_vaccination();


--
-- Name: vaccination_records trg_decrement_vaccine_lot_stock; Type: TRIGGER; Schema: public; Owner: vaccine_user
--

CREATE TRIGGER trg_decrement_vaccine_lot_stock AFTER INSERT ON public.vaccination_records FOR EACH ROW EXECUTE FUNCTION public.fn_decrement_vaccine_lot_stock();


--
-- Name: patients trg_generate_expected_vaccination_scheme; Type: TRIGGER; Schema: public; Owner: vaccine_user
--

CREATE TRIGGER trg_generate_expected_vaccination_scheme AFTER INSERT ON public.patients FOR EACH ROW EXECUTE FUNCTION public.fn_generate_expected_vaccination_scheme();


--
-- Name: vaccine_lots trg_generate_low_stock_alert; Type: TRIGGER; Schema: public; Owner: vaccine_user
--

CREATE TRIGGER trg_generate_low_stock_alert AFTER UPDATE ON public.vaccine_lots FOR EACH ROW EXECUTE FUNCTION public.fn_generate_low_stock_alert();


--
-- Name: vaccine_lots trg_prevent_negative_stock; Type: TRIGGER; Schema: public; Owner: vaccine_user
--

CREATE TRIGGER trg_prevent_negative_stock BEFORE UPDATE ON public.vaccine_lots FOR EACH ROW EXECUTE FUNCTION public.fn_prevent_negative_stock();


--
-- Name: patient_vaccine_schedule trg_set_initial_schedule_status; Type: TRIGGER; Schema: public; Owner: vaccine_user
--

CREATE TRIGGER trg_set_initial_schedule_status BEFORE INSERT ON public.patient_vaccine_schedule FOR EACH ROW EXECUTE FUNCTION public.fn_set_initial_schedule_status();


--
-- Name: vaccination_records trg_update_expected_vaccination_scheme; Type: TRIGGER; Schema: public; Owner: vaccine_user
--

CREATE TRIGGER trg_update_expected_vaccination_scheme AFTER INSERT ON public.vaccination_records FOR EACH ROW EXECUTE FUNCTION public.fn_update_expected_vaccination_scheme();


--
-- Name: vaccination_records trg_validate_lot_expiration; Type: TRIGGER; Schema: public; Owner: vaccine_user
--

CREATE TRIGGER trg_validate_lot_expiration BEFORE INSERT ON public.vaccination_records FOR EACH ROW EXECUTE FUNCTION public.fn_validate_lot_expiration();


--
-- Name: vaccination_records trg_validate_vaccine_application; Type: TRIGGER; Schema: public; Owner: vaccine_user
--

CREATE TRIGGER trg_validate_vaccine_application BEFORE INSERT ON public.vaccination_records FOR EACH ROW EXECUTE FUNCTION public.fn_validate_vaccine_application();


--
-- Name: addresses addresses_neighborhood_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.addresses
    ADD CONSTRAINT addresses_neighborhood_id_fkey FOREIGN KEY (neighborhood_id) REFERENCES public.neighborhoods(neighborhood_id);


--
-- Name: appointments appointments_area_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_area_id_fkey FOREIGN KEY (area_id) REFERENCES public.clinic_areas(area_id);


--
-- Name: appointments appointments_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(clinic_id);


--
-- Name: appointments appointments_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(patient_id);


--
-- Name: appointments appointments_patient_schedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_patient_schedule_id_fkey FOREIGN KEY (patient_schedule_id) REFERENCES public.patient_vaccine_schedule(schedule_id);


--
-- Name: appointments appointments_rescheduled_from_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_rescheduled_from_id_fkey FOREIGN KEY (rescheduled_from_id) REFERENCES public.appointments(appointment_id);


--
-- Name: appointments appointments_worker_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT appointments_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES public.workers(worker_id);


--
-- Name: area_equipment area_equipment_area_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.area_equipment
    ADD CONSTRAINT area_equipment_area_id_fkey FOREIGN KEY (area_id) REFERENCES public.clinic_areas(area_id);


--
-- Name: area_equipment area_equipment_equipment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.area_equipment
    ADD CONSTRAINT area_equipment_equipment_id_fkey FOREIGN KEY (equipment_id) REFERENCES public.equipment_catalog(equipment_id);


--
-- Name: audit_log audit_log_worker_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES public.workers(worker_id);


--
-- Name: clinic_areas clinic_areas_area_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.clinic_areas
    ADD CONSTRAINT clinic_areas_area_type_id_fkey FOREIGN KEY (area_type_id) REFERENCES public.clinic_area_types(area_type_id);


--
-- Name: clinic_areas clinic_areas_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.clinic_areas
    ADD CONSTRAINT clinic_areas_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(clinic_id);


--
-- Name: clinic_inventory clinic_inventory_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.clinic_inventory
    ADD CONSTRAINT clinic_inventory_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(clinic_id);


--
-- Name: clinic_inventory clinic_inventory_supply_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.clinic_inventory
    ADD CONSTRAINT clinic_inventory_supply_id_fkey FOREIGN KEY (supply_id) REFERENCES public.supply_catalog(supply_id);


--
-- Name: clinics clinics_address_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.clinics
    ADD CONSTRAINT clinics_address_id_fkey FOREIGN KEY (address_id) REFERENCES public.addresses(address_id);


--
-- Name: appointments fk_appointments_schedule; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.appointments
    ADD CONSTRAINT fk_appointments_schedule FOREIGN KEY (patient_schedule_id) REFERENCES public.patient_vaccine_schedule(schedule_id);


--
-- Name: guardian_accounts guardian_accounts_guardian_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.guardian_accounts
    ADD CONSTRAINT guardian_accounts_guardian_id_fkey FOREIGN KEY (guardian_id) REFERENCES public.guardians(guardian_id) ON DELETE CASCADE;


--
-- Name: guardian_emails guardian_emails_guardian_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.guardian_emails
    ADD CONSTRAINT guardian_emails_guardian_id_fkey FOREIGN KEY (guardian_id) REFERENCES public.guardians(guardian_id);


--
-- Name: guardian_phones guardian_phones_guardian_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.guardian_phones
    ADD CONSTRAINT guardian_phones_guardian_id_fkey FOREIGN KEY (guardian_id) REFERENCES public.guardians(guardian_id);


--
-- Name: guardians guardians_address_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.guardians
    ADD CONSTRAINT guardians_address_id_fkey FOREIGN KEY (address_id) REFERENCES public.addresses(address_id);


--
-- Name: guardians guardians_marital_status_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.guardians
    ADD CONSTRAINT guardians_marital_status_id_fkey FOREIGN KEY (marital_status_id) REFERENCES public.marital_status(marital_status_id);


--
-- Name: guardians guardians_occupation_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.guardians
    ADD CONSTRAINT guardians_occupation_fkey FOREIGN KEY (occupation) REFERENCES public.occupations(occupation_id);


--
-- Name: institutions institutions_address_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.institutions
    ADD CONSTRAINT institutions_address_id_fkey FOREIGN KEY (address_id) REFERENCES public.addresses(address_id);


--
-- Name: inventory_movements inventory_movements_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.inventory_movements
    ADD CONSTRAINT inventory_movements_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(clinic_id);


--
-- Name: inventory_movements inventory_movements_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.inventory_movements
    ADD CONSTRAINT inventory_movements_lot_id_fkey FOREIGN KEY (lot_id) REFERENCES public.vaccine_lots(lot_id);


--
-- Name: inventory_movements inventory_movements_vaccine_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.inventory_movements
    ADD CONSTRAINT inventory_movements_vaccine_id_fkey FOREIGN KEY (vaccine_id) REFERENCES public.vaccines(vaccine_id);


--
-- Name: inventory_movements inventory_movements_worker_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.inventory_movements
    ADD CONSTRAINT inventory_movements_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES public.workers(worker_id);


--
-- Name: inventory_transfers inventory_transfers_approved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_transfers
    ADD CONSTRAINT inventory_transfers_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.workers(worker_id);


--
-- Name: inventory_transfers inventory_transfers_from_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_transfers
    ADD CONSTRAINT inventory_transfers_from_clinic_id_fkey FOREIGN KEY (from_clinic_id) REFERENCES public.clinics(clinic_id);


--
-- Name: inventory_transfers inventory_transfers_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_transfers
    ADD CONSTRAINT inventory_transfers_lot_id_fkey FOREIGN KEY (lot_id) REFERENCES public.vaccine_lots(lot_id);


--
-- Name: inventory_transfers inventory_transfers_requested_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_transfers
    ADD CONSTRAINT inventory_transfers_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES public.workers(worker_id);


--
-- Name: inventory_transfers inventory_transfers_to_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_transfers
    ADD CONSTRAINT inventory_transfers_to_clinic_id_fkey FOREIGN KEY (to_clinic_id) REFERENCES public.clinics(clinic_id);


--
-- Name: inventory_transfers inventory_transfers_vaccine_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.inventory_transfers
    ADD CONSTRAINT inventory_transfers_vaccine_id_fkey FOREIGN KEY (vaccine_id) REFERENCES public.vaccines(vaccine_id);


--
-- Name: manufacturers manufacturers_country_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.manufacturers
    ADD CONSTRAINT manufacturers_country_id_fkey FOREIGN KEY (country_id) REFERENCES public.countries(country_id);


--
-- Name: municipalities municipalities_state_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.municipalities
    ADD CONSTRAINT municipalities_state_id_fkey FOREIGN KEY (state_id) REFERENCES public.states(state_id);


--
-- Name: neighborhoods neighborhoods_municipality_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.neighborhoods
    ADD CONSTRAINT neighborhoods_municipality_id_fkey FOREIGN KEY (municipality_id) REFERENCES public.municipalities(municipality_id);


--
-- Name: nfc_cards nfc_cards_issued_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.nfc_cards
    ADD CONSTRAINT nfc_cards_issued_by_fkey FOREIGN KEY (issued_by) REFERENCES public.workers(worker_id);


--
-- Name: nfc_cards nfc_cards_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.nfc_cards
    ADD CONSTRAINT nfc_cards_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(patient_id);


--
-- Name: nfc_devices nfc_devices_area_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.nfc_devices
    ADD CONSTRAINT nfc_devices_area_id_fkey FOREIGN KEY (area_id) REFERENCES public.clinic_areas(area_id);


--
-- Name: nfc_devices nfc_devices_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.nfc_devices
    ADD CONSTRAINT nfc_devices_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(clinic_id);


--
-- Name: nfc_scan_events nfc_scan_events_area_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.nfc_scan_events
    ADD CONSTRAINT nfc_scan_events_area_id_fkey FOREIGN KEY (area_id) REFERENCES public.clinic_areas(area_id);


--
-- Name: nfc_scan_events nfc_scan_events_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.nfc_scan_events
    ADD CONSTRAINT nfc_scan_events_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(clinic_id);


--
-- Name: nfc_scan_events nfc_scan_events_device_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.nfc_scan_events
    ADD CONSTRAINT nfc_scan_events_device_id_fkey FOREIGN KEY (device_id) REFERENCES public.nfc_devices(device_id);


--
-- Name: nfc_scan_events nfc_scan_events_nfc_card_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.nfc_scan_events
    ADD CONSTRAINT nfc_scan_events_nfc_card_id_fkey FOREIGN KEY (nfc_card_id) REFERENCES public.nfc_cards(nfc_card_id);


--
-- Name: nfc_scan_events nfc_scan_events_scanned_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.nfc_scan_events
    ADD CONSTRAINT nfc_scan_events_scanned_by_fkey FOREIGN KEY (scanned_by) REFERENCES public.workers(worker_id);


--
-- Name: nfc_scan_events nfc_scan_events_visit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.nfc_scan_events
    ADD CONSTRAINT nfc_scan_events_visit_id_fkey FOREIGN KEY (visit_id) REFERENCES public.patient_clinic_visits(visit_id);


--
-- Name: patient_allergies patient_allergies_allergy_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.patient_allergies
    ADD CONSTRAINT patient_allergies_allergy_id_fkey FOREIGN KEY (allergy_id) REFERENCES public.allergies(allergy_id);


--
-- Name: patient_allergies patient_allergies_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.patient_allergies
    ADD CONSTRAINT patient_allergies_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(patient_id);


--
-- Name: patient_clinic_visits patient_clinic_visits_appointment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patient_clinic_visits
    ADD CONSTRAINT patient_clinic_visits_appointment_id_fkey FOREIGN KEY (appointment_id) REFERENCES public.appointments(appointment_id);


--
-- Name: patient_clinic_visits patient_clinic_visits_assigned_worker_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patient_clinic_visits
    ADD CONSTRAINT patient_clinic_visits_assigned_worker_id_fkey FOREIGN KEY (assigned_worker_id) REFERENCES public.workers(worker_id);


--
-- Name: patient_clinic_visits patient_clinic_visits_checkin_by_worker_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patient_clinic_visits
    ADD CONSTRAINT patient_clinic_visits_checkin_by_worker_id_fkey FOREIGN KEY (checkin_by_worker_id) REFERENCES public.workers(worker_id);


--
-- Name: patient_clinic_visits patient_clinic_visits_checkin_nfc_scan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patient_clinic_visits
    ADD CONSTRAINT patient_clinic_visits_checkin_nfc_scan_id_fkey FOREIGN KEY (checkin_nfc_scan_id) REFERENCES public.nfc_scan_events(scan_event_id);


--
-- Name: patient_clinic_visits patient_clinic_visits_checkout_by_worker_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patient_clinic_visits
    ADD CONSTRAINT patient_clinic_visits_checkout_by_worker_id_fkey FOREIGN KEY (checkout_by_worker_id) REFERENCES public.workers(worker_id);


--
-- Name: patient_clinic_visits patient_clinic_visits_checkout_nfc_scan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patient_clinic_visits
    ADD CONSTRAINT patient_clinic_visits_checkout_nfc_scan_id_fkey FOREIGN KEY (checkout_nfc_scan_id) REFERENCES public.nfc_scan_events(scan_event_id);


--
-- Name: patient_clinic_visits patient_clinic_visits_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patient_clinic_visits
    ADD CONSTRAINT patient_clinic_visits_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(clinic_id);


--
-- Name: patient_clinic_visits patient_clinic_visits_current_area_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patient_clinic_visits
    ADD CONSTRAINT patient_clinic_visits_current_area_id_fkey FOREIGN KEY (current_area_id) REFERENCES public.clinic_areas(area_id);


--
-- Name: patient_clinic_visits patient_clinic_visits_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.patient_clinic_visits
    ADD CONSTRAINT patient_clinic_visits_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(patient_id);


--
-- Name: patient_guardian_relations patient_guardian_relations_guardian_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.patient_guardian_relations
    ADD CONSTRAINT patient_guardian_relations_guardian_id_fkey FOREIGN KEY (guardian_id) REFERENCES public.guardians(guardian_id);


--
-- Name: patient_guardian_relations patient_guardian_relations_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.patient_guardian_relations
    ADD CONSTRAINT patient_guardian_relations_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(patient_id);


--
-- Name: patient_vaccine_schedule patient_vaccine_schedule_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.patient_vaccine_schedule
    ADD CONSTRAINT patient_vaccine_schedule_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(patient_id);


--
-- Name: patient_vaccine_schedule patient_vaccine_schedule_scheme_dose_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.patient_vaccine_schedule
    ADD CONSTRAINT patient_vaccine_schedule_scheme_dose_id_fkey FOREIGN KEY (scheme_dose_id) REFERENCES public.scheme_doses(dose_id);


--
-- Name: patients patients_blood_type_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.patients
    ADD CONSTRAINT patients_blood_type_id_fkey FOREIGN KEY (blood_type_id) REFERENCES public.blood_types(blood_type_id);


--
-- Name: post_vaccine_reactions post_vaccine_reactions_record_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.post_vaccine_reactions
    ADD CONSTRAINT post_vaccine_reactions_record_id_fkey FOREIGN KEY (record_id) REFERENCES public.vaccination_records(record_id);


--
-- Name: post_vaccine_reactions post_vaccine_reactions_reported_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.post_vaccine_reactions
    ADD CONSTRAINT post_vaccine_reactions_reported_by_fkey FOREIGN KEY (reported_by) REFERENCES public.workers(worker_id);


--
-- Name: scheme_completion_alerts scheme_completion_alerts_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.scheme_completion_alerts
    ADD CONSTRAINT scheme_completion_alerts_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(patient_id);


--
-- Name: scheme_completion_alerts scheme_completion_alerts_schedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.scheme_completion_alerts
    ADD CONSTRAINT scheme_completion_alerts_schedule_id_fkey FOREIGN KEY (schedule_id) REFERENCES public.patient_vaccine_schedule(schedule_id);


--
-- Name: scheme_completion_alerts scheme_completion_alerts_scheme_dose_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.scheme_completion_alerts
    ADD CONSTRAINT scheme_completion_alerts_scheme_dose_id_fkey FOREIGN KEY (scheme_dose_id) REFERENCES public.scheme_doses(dose_id);


--
-- Name: scheme_doses scheme_doses_scheme_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.scheme_doses
    ADD CONSTRAINT scheme_doses_scheme_id_fkey FOREIGN KEY (scheme_id) REFERENCES public.vaccination_scheme(scheme_id);


--
-- Name: scheme_doses scheme_doses_vaccine_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.scheme_doses
    ADD CONSTRAINT scheme_doses_vaccine_id_fkey FOREIGN KEY (vaccine_id) REFERENCES public.vaccines(vaccine_id);


--
-- Name: states states_country_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.states
    ADD CONSTRAINT states_country_id_fkey FOREIGN KEY (country_id) REFERENCES public.countries(country_id);


--
-- Name: users users_worker_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES public.workers(worker_id);


--
-- Name: vaccination_records vaccination_records_application_site_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccination_records
    ADD CONSTRAINT vaccination_records_application_site_id_fkey FOREIGN KEY (application_site_id) REFERENCES public.application_sites(application_site_id);


--
-- Name: vaccination_records vaccination_records_appointment_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccination_records
    ADD CONSTRAINT vaccination_records_appointment_id_fkey FOREIGN KEY (appointment_id) REFERENCES public.appointments(appointment_id);


--
-- Name: vaccination_records vaccination_records_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccination_records
    ADD CONSTRAINT vaccination_records_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(clinic_id);


--
-- Name: vaccination_records vaccination_records_lot_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccination_records
    ADD CONSTRAINT vaccination_records_lot_id_fkey FOREIGN KEY (lot_id) REFERENCES public.vaccine_lots(lot_id);


--
-- Name: vaccination_records vaccination_records_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccination_records
    ADD CONSTRAINT vaccination_records_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(patient_id);


--
-- Name: vaccination_records vaccination_records_patient_schedule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccination_records
    ADD CONSTRAINT vaccination_records_patient_schedule_id_fkey FOREIGN KEY (patient_schedule_id) REFERENCES public.patient_vaccine_schedule(schedule_id);


--
-- Name: vaccination_records vaccination_records_scheme_dose_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccination_records
    ADD CONSTRAINT vaccination_records_scheme_dose_id_fkey FOREIGN KEY (scheme_dose_id) REFERENCES public.scheme_doses(dose_id);


--
-- Name: vaccination_records vaccination_records_vaccine_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccination_records
    ADD CONSTRAINT vaccination_records_vaccine_id_fkey FOREIGN KEY (vaccine_id) REFERENCES public.vaccines(vaccine_id);


--
-- Name: vaccination_records vaccination_records_visit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccination_records
    ADD CONSTRAINT vaccination_records_visit_id_fkey FOREIGN KEY (visit_id) REFERENCES public.patient_clinic_visits(visit_id);


--
-- Name: vaccination_records vaccination_records_worker_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccination_records
    ADD CONSTRAINT vaccination_records_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES public.workers(worker_id);


--
-- Name: vaccine_lots vaccine_lots_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccine_lots
    ADD CONSTRAINT vaccine_lots_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(clinic_id);


--
-- Name: vaccine_lots vaccine_lots_vaccine_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccine_lots
    ADD CONSTRAINT vaccine_lots_vaccine_id_fkey FOREIGN KEY (vaccine_id) REFERENCES public.vaccines(vaccine_id);


--
-- Name: vaccines vaccines_manufacturer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccines
    ADD CONSTRAINT vaccines_manufacturer_id_fkey FOREIGN KEY (manufacturer_id) REFERENCES public.manufacturers(manufacturer_id);


--
-- Name: vaccines vaccines_via_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.vaccines
    ADD CONSTRAINT vaccines_via_id_fkey FOREIGN KEY (via_id) REFERENCES public.vaccine_vias(via_id);


--
-- Name: visit_area_movements visit_area_movements_from_area_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.visit_area_movements
    ADD CONSTRAINT visit_area_movements_from_area_id_fkey FOREIGN KEY (from_area_id) REFERENCES public.clinic_areas(area_id);


--
-- Name: visit_area_movements visit_area_movements_moved_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.visit_area_movements
    ADD CONSTRAINT visit_area_movements_moved_by_fkey FOREIGN KEY (moved_by) REFERENCES public.workers(worker_id);


--
-- Name: visit_area_movements visit_area_movements_nfc_scan_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.visit_area_movements
    ADD CONSTRAINT visit_area_movements_nfc_scan_id_fkey FOREIGN KEY (nfc_scan_id) REFERENCES public.nfc_scan_events(scan_event_id);


--
-- Name: visit_area_movements visit_area_movements_to_area_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.visit_area_movements
    ADD CONSTRAINT visit_area_movements_to_area_id_fkey FOREIGN KEY (to_area_id) REFERENCES public.clinic_areas(area_id);


--
-- Name: visit_area_movements visit_area_movements_visit_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.visit_area_movements
    ADD CONSTRAINT visit_area_movements_visit_id_fkey FOREIGN KEY (visit_id) REFERENCES public.patient_clinic_visits(visit_id);


--
-- Name: worker_clinic_assignment worker_clinic_assignment_area_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.worker_clinic_assignment
    ADD CONSTRAINT worker_clinic_assignment_area_id_fkey FOREIGN KEY (area_id) REFERENCES public.clinic_areas(area_id);


--
-- Name: worker_clinic_assignment worker_clinic_assignment_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.worker_clinic_assignment
    ADD CONSTRAINT worker_clinic_assignment_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(clinic_id);


--
-- Name: worker_clinic_assignment worker_clinic_assignment_worker_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.worker_clinic_assignment
    ADD CONSTRAINT worker_clinic_assignment_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES public.workers(worker_id);


--
-- Name: worker_emails worker_emails_worker_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.worker_emails
    ADD CONSTRAINT worker_emails_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES public.workers(worker_id);


--
-- Name: worker_phones worker_phones_worker_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.worker_phones
    ADD CONSTRAINT worker_phones_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES public.workers(worker_id);


--
-- Name: worker_professional worker_professional_institution_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.worker_professional
    ADD CONSTRAINT worker_professional_institution_id_fkey FOREIGN KEY (institution_id) REFERENCES public.institutions(institution_id);


--
-- Name: worker_professional worker_professional_specialty_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.worker_professional
    ADD CONSTRAINT worker_professional_specialty_id_fkey FOREIGN KEY (specialty_id) REFERENCES public.specialties(specialty_id);


--
-- Name: worker_professional worker_professional_worker_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.worker_professional
    ADD CONSTRAINT worker_professional_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES public.workers(worker_id);


--
-- Name: worker_schedules worker_schedules_clinic_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.worker_schedules
    ADD CONSTRAINT worker_schedules_clinic_id_fkey FOREIGN KEY (clinic_id) REFERENCES public.clinics(clinic_id);


--
-- Name: worker_schedules worker_schedules_worker_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.worker_schedules
    ADD CONSTRAINT worker_schedules_worker_id_fkey FOREIGN KEY (worker_id) REFERENCES public.workers(worker_id);


--
-- Name: workers workers_address_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.workers
    ADD CONSTRAINT workers_address_id_fkey FOREIGN KEY (address_id) REFERENCES public.addresses(address_id);


--
-- Name: workers workers_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: vaccine_user
--

ALTER TABLE ONLY public.workers
    ADD CONSTRAINT workers_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(role_id);


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: pg_database_owner
--

GRANT USAGE ON SCHEMA public TO vaccine_user;


--
-- Name: TABLE v_appointments_full; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.v_appointments_full TO vaccine_user;


--
-- Name: TABLE v_delayed_patients; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.v_delayed_patients TO vaccine_user;


--
-- Name: TABLE v_esquema_paciente_base; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.v_esquema_paciente_base TO vaccine_user;


--
-- Name: TABLE v_inventory_status; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.v_inventory_status TO vaccine_user;


--
-- Name: TABLE v_low_stock_items; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.v_low_stock_items TO vaccine_user;


--
-- Name: TABLE v_patient_vaccination_scheme_base; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.v_patient_vaccination_scheme_base TO vaccine_user;


--
-- Name: TABLE v_pending_scheme_doses; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.v_pending_scheme_doses TO vaccine_user;


--
-- Name: TABLE v_vaccination_records_full; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.v_vaccination_records_full TO vaccine_user;


--
-- Name: TABLE v_vaccine_stock; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.v_vaccine_stock TO vaccine_user;


--
-- Name: TABLE v_worker_full; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.v_worker_full TO vaccine_user;


--
-- Name: TABLE vw_dashboard_kpis; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.vw_dashboard_kpis TO vaccine_user;


--
-- Name: TABLE vw_patients; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.vw_patients TO vaccine_user;


--
-- Name: TABLE vw_worker_full; Type: ACL; Schema: public; Owner: postgres
--

GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.vw_worker_full TO vaccine_user;


--
-- PostgreSQL database dump complete
--

\unrestrict lEVBQ8NjIASKTAlsDeGELS3Sg8nux1ZTOaqh1toX3FCLphahlaCaBWSTfRAPLwj

