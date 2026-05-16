-- ============================================================
-- MIGRACIÓN: Tabla nfc_relations + fixes de SP NFC
-- Ejecutar UNA sola vez sobre la BD existente.
-- ============================================================

SET client_encoding = 'UTF8';
SET search_path = public;

BEGIN;

-- ============================================================
-- PASO 1: Vista nfc_relations
-- Enlace directo nfc_id (uid del lector) → patient_id
-- Equivale a las tarjetas activas en nfc_cards.
-- ============================================================
CREATE OR REPLACE VIEW nfc_relations AS
SELECT
    uid        AS nfc_id,
    patient_id,
    issued_date,
    last_scanned_at,
    status
FROM nfc_cards;


-- ============================================================
-- PASO 2: Fix sp_assign_nfc_card
-- Solo bloquea si ya existe una tarjeta ACTIVA con ese UID.
-- Antes bloqueaba incluso tarjetas inactivas/eliminadas (históricas).
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_assign_nfc_card(
    IN    p_patient_id  INT,
    IN    p_uid         VARCHAR,
    IN    p_card_type   VARCHAR,
    IN    p_issued_by   INT,
    IN    p_notes       TEXT,
    INOUT p_results     REFCURSOR
)
LANGUAGE plpgsql AS $$
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


-- ============================================================
-- PASO 3: Actualizar sp_get_nfc_cards_full
-- Agrega el estado clínico actual del paciente (visita activa).
-- ============================================================
CREATE OR REPLACE PROCEDURE sp_get_nfc_cards_full(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
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

COMMIT;
