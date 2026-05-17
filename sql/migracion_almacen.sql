-- ============================================================
-- MIGRACIÓN COMPLETA — Módulo Almacén (Fases 1 y 2)
-- Ejecutar este archivo UNA VEZ contra la base de datos.
-- Es seguro re-ejecutar (usa IF NOT EXISTS y OR REPLACE).
-- ============================================================

-- ============================================================
-- FASE 1 — ESQUEMA: lot_status + inventory_movements
-- ============================================================

-- 1A. Columna lot_status en vaccine_lots
ALTER TABLE vaccine_lots
ADD COLUMN IF NOT EXISTS lot_status VARCHAR(30) NOT NULL DEFAULT 'Disponible'
CHECK (lot_status IN ('Disponible', 'Agotado', 'Caducado', 'Bloqueado', 'Retirado'));

-- 1B. Migrar datos existentes
UPDATE vaccine_lots
SET lot_status = 'Caducado'
WHERE expiration_date < CURRENT_DATE
  AND lot_status = 'Disponible';

UPDATE vaccine_lots
SET lot_status = 'Agotado'
WHERE quantity_available = 0
  AND expiration_date >= CURRENT_DATE
  AND lot_status = 'Disponible';

-- 1C. Tabla de movimientos de inventario
CREATE TABLE IF NOT EXISTS inventory_movements (
    movement_id     SERIAL PRIMARY KEY,
    lot_id          INT          NOT NULL REFERENCES vaccine_lots(lot_id),
    vaccine_id      INT          NOT NULL REFERENCES vaccines(vaccine_id),
    clinic_id       INT          NOT NULL REFERENCES clinics(clinic_id),
    worker_id       INT          REFERENCES workers(worker_id),
    movement_type   VARCHAR(30)  NOT NULL
                    CHECK (movement_type IN (
                        'Entrada',
                        'Salida_Aplicacion',
                        'Salida_Merma',
                        'Salida_Caducidad',
                        'Ajuste_Positivo',
                        'Ajuste_Negativo',
                        'Transferencia_Salida',
                        'Transferencia_Entrada'
                    )),
    quantity        INT          NOT NULL CHECK (quantity > 0),
    quantity_before INT          NOT NULL,
    quantity_after  INT          NOT NULL,
    reference_id    INT,
    reference_type  VARCHAR(30)  CHECK (reference_type IN ('vaccination_record', 'transfer', 'manual')),
    reason          TEXT,
    created_at      TIMESTAMP    NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_movements_lot      ON inventory_movements(lot_id);
CREATE INDEX IF NOT EXISTS idx_movements_clinic   ON inventory_movements(clinic_id);
CREATE INDEX IF NOT EXISTS idx_movements_type     ON inventory_movements(movement_type);
CREATE INDEX IF NOT EXISTS idx_movements_date     ON inventory_movements(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_movements_worker   ON inventory_movements(worker_id);
CREATE INDEX IF NOT EXISTS idx_movements_ref      ON inventory_movements(reference_id, reference_type);

-- Índices parciales para alertas (queries frecuentes)
CREATE INDEX IF NOT EXISTS idx_lots_expiry_alert
ON vaccine_lots(expiration_date, clinic_id)
WHERE lot_status = 'Disponible';

CREATE INDEX IF NOT EXISTS idx_lots_low_stock
ON vaccine_lots(quantity_available, clinic_id)
WHERE lot_status = 'Disponible' AND quantity_available <= 10;

-- ============================================================
-- FASE 2 — ESQUEMA: inventory_transfers (si no existe ya)
-- ============================================================

CREATE TABLE IF NOT EXISTS inventory_transfers (
    transfer_id     SERIAL PRIMARY KEY,
    lot_id          INT         NOT NULL REFERENCES vaccine_lots(lot_id),
    vaccine_id      INT         NOT NULL REFERENCES vaccines(vaccine_id),
    from_clinic_id  INT         NOT NULL REFERENCES clinics(clinic_id),
    to_clinic_id    INT         NOT NULL REFERENCES clinics(clinic_id),
    quantity        INT         NOT NULL CHECK (quantity > 0),
    transfer_status VARCHAR(20) NOT NULL DEFAULT 'Pendiente'
                    CHECK (transfer_status IN (
                        'Pendiente', 'En_Transito', 'Recibido', 'Cancelado', 'Rechazado'
                    )),
    requested_by    INT         NOT NULL REFERENCES workers(worker_id),
    approved_by     INT                  REFERENCES workers(worker_id),
    reason          TEXT,
    notes           TEXT,
    requested_at    TIMESTAMP   NOT NULL DEFAULT NOW(),
    resolved_at     TIMESTAMP,
    CONSTRAINT chk_transfer_different_clinics CHECK (from_clinic_id <> to_clinic_id)
);

CREATE INDEX IF NOT EXISTS idx_transfers_lot       ON inventory_transfers(lot_id);
CREATE INDEX IF NOT EXISTS idx_transfers_from      ON inventory_transfers(from_clinic_id);
CREATE INDEX IF NOT EXISTS idx_transfers_to        ON inventory_transfers(to_clinic_id);
CREATE INDEX IF NOT EXISTS idx_transfers_status    ON inventory_transfers(transfer_status);
CREATE INDEX IF NOT EXISTS idx_transfers_requested ON inventory_transfers(requested_at DESC);
CREATE INDEX IF NOT EXISTS idx_transfers_requester ON inventory_transfers(requested_by);

-- Eliminar constraint UNIQUE de appointment_id en vaccination_records
-- (permite múltiples vacunas por cita)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conrelid = 'vaccination_records'::regclass
          AND contype = 'u'
          AND conname ILIKE '%appointment%'
    ) THEN
        EXECUTE (
            SELECT 'ALTER TABLE vaccination_records DROP CONSTRAINT ' || conname
            FROM pg_constraint
            WHERE conrelid = 'vaccination_records'::regclass
              AND contype = 'u'
              AND conname ILIKE '%appointment%'
            LIMIT 1
        );
    END IF;
END;
$$;

-- ============================================================
-- TRIGGERS
-- ============================================================

-- Trigger 4 mejorado: decrementa stock Y registra movimiento
CREATE OR REPLACE FUNCTION fn_decrement_vaccine_lot_stock()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

-- Nuevo trigger: auto-gestión de lot_status
CREATE OR REPLACE FUNCTION fn_auto_lot_status()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_auto_lot_status ON vaccine_lots;
CREATE TRIGGER trg_auto_lot_status
BEFORE UPDATE ON vaccine_lots
FOR EACH ROW EXECUTE FUNCTION fn_auto_lot_status();

-- ============================================================
-- STORED PROCEDURES — Fase 1
-- ============================================================

-- sp_almacen_dashboard
CREATE OR REPLACE PROCEDURE sp_almacen_dashboard(
    IN    p_clinic_id       INT,
    INOUT p_kpis            REFCURSOR,
    INOUT p_alertas         REFCURSOR,
    INOUT p_movimientos     REFCURSOR,
    INOUT p_lotes_criticos  REFCURSOR
)
LANGUAGE plpgsql AS $$
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

    -- Alertas (crítico primero)
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
                    THEN 'Vence en ' || (vl.expiration_date - CURRENT_DATE) || ' día(s)'
                WHEN vl.quantity_available <= 5
                    THEN 'Stock crítico: ' || vl.quantity_available || ' dosis'
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

    -- Movimientos recientes (últimos 20)
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

    -- Lotes críticos para gráfica
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

-- sp_get_movements_full
CREATE OR REPLACE PROCEDURE sp_get_movements_full(
    IN    p_clinic_id    INT,
    IN    p_lot_id       INT,
    IN    p_date_from    DATE,
    IN    p_date_to      DATE,
    IN    p_type_filter  VARCHAR,
    INOUT p_results      REFCURSOR
)
LANGUAGE plpgsql AS $$
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

-- sp_register_manual_movement
CREATE OR REPLACE PROCEDURE sp_register_manual_movement(
    IN    p_lot_id        INT,
    IN    p_worker_id     INT,
    IN    p_movement_type VARCHAR,
    IN    p_quantity      INT,
    IN    p_reason        TEXT,
    INOUT p_results       REFCURSOR
)
LANGUAGE plpgsql AS $$
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

-- sp_update_lot_status
CREATE OR REPLACE PROCEDURE sp_update_lot_status(
    IN    p_lot_id      INT,
    IN    p_new_status  VARCHAR,
    IN    p_worker_id   INT,
    IN    p_reason      TEXT,
    INOUT p_results     REFCURSOR
)
LANGUAGE plpgsql AS $$
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

-- sp_get_almacen_alerts
CREATE OR REPLACE PROCEDURE sp_get_almacen_alerts(
    IN    p_clinic_id INT,
    INOUT p_results   REFCURSOR
)
LANGUAGE plpgsql AS $$
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
                    THEN 'Vence en ' || (vl.expiration_date - CURRENT_DATE) || ' día(s)'
                WHEN vl.quantity_available <= 5
                    THEN 'Stock crítico: ' || vl.quantity_available || ' dosis'
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

-- sp_get_lot_detail
CREATE OR REPLACE PROCEDURE sp_get_lot_detail(
    IN    p_lot_id  INT,
    INOUT p_lot     REFCURSOR,
    INOUT p_movs    REFCURSOR
)
LANGUAGE plpgsql AS $$
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

-- ============================================================
-- STORED PROCEDURES — Fase 2 (Transferencias)
-- ============================================================

-- sp_get_transfers
CREATE OR REPLACE PROCEDURE sp_get_transfers(
    IN    p_clinic_id      INT,
    IN    p_status_filter  VARCHAR,
    INOUT p_results        REFCURSOR
)
LANGUAGE plpgsql AS $$
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

-- sp_create_transfer
CREATE OR REPLACE PROCEDURE sp_create_transfer(
    IN    p_lot_id        INT,
    IN    p_to_clinic_id  INT,
    IN    p_quantity      INT,
    IN    p_worker_id     INT,
    IN    p_reason        TEXT,
    INOUT p_results       REFCURSOR
)
LANGUAGE plpgsql AS $$
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
            'El lote está en estado ' || v_lot.lot_status || ' y no puede transferirse.' AS message,
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
            'La clínica destino debe ser diferente a la clínica origen.' AS message,
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

-- sp_accept_transfer
CREATE OR REPLACE PROCEDURE sp_accept_transfer(
    IN    p_transfer_id  INT,
    IN    p_worker_id    INT,
    IN    p_notes        TEXT,
    INOUT p_results      REFCURSOR
)
LANGUAGE plpgsql AS $$
DECLARE
    v_t          RECORD;
    v_qty_before INT;
    v_qty_after  INT;
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
            'Solo se pueden aceptar transferencias Pendientes o En_Tránsito. Estado actual: ' || v_t.transfer_status AS message;
        RETURN;
    END IF;

    SELECT quantity_available INTO v_qty_before
    FROM vaccine_lots WHERE lot_id = v_t.lot_id FOR UPDATE;

    IF v_qty_before < v_t.quantity THEN
        OPEN p_results FOR SELECT FALSE AS success,
            'Stock insuficiente en lote origen. Disponible: ' || v_qty_before AS message;
        RETURN;
    END IF;

    v_qty_after := v_qty_before - v_t.quantity;

    UPDATE vaccine_lots
    SET quantity_available = v_qty_after,
        lot_status = CASE WHEN v_qty_after = 0 THEN 'Agotado' ELSE lot_status END
    WHERE lot_id = v_t.lot_id;

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

    INSERT INTO inventory_movements (
        lot_id, vaccine_id, clinic_id, worker_id,
        movement_type, quantity, quantity_before, quantity_after,
        reference_id, reference_type, reason
    ) VALUES (
        v_t.lot_id, v_t.vaccine_id, v_t.to_clinic_id, p_worker_id,
        'Transferencia_Entrada', v_t.quantity, 0, v_t.quantity,
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

-- sp_reject_transfer
CREATE OR REPLACE PROCEDURE sp_reject_transfer(
    IN    p_transfer_id  INT,
    IN    p_worker_id    INT,
    IN    p_reason       TEXT,
    INOUT p_results      REFCURSOR
)
LANGUAGE plpgsql AS $$
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

-- sp_cancel_transfer
CREATE OR REPLACE PROCEDURE sp_cancel_transfer(
    IN    p_transfer_id  INT,
    IN    p_worker_id    INT,
    IN    p_reason       TEXT,
    INOUT p_results      REFCURSOR
)
LANGUAGE plpgsql AS $$
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
