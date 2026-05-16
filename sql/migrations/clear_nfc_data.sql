-- ============================================================
-- LIMPIEZA: borrar todos los registros de tarjetas NFC,
--           escaneos y visitas clínicas.
--           NO toca patients.nfc_id.
--           Usa IF EXISTS para tolerar tablas que aún no existan.
-- ============================================================

SET client_encoding = 'UTF8';
SET search_path = public;

BEGIN;

-- 1. Movimientos de visita (puede no existir si la migración no corrió)
DO $$ BEGIN
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'visit_area_movements') THEN
        DELETE FROM visit_area_movements;
    END IF;
END $$;

-- 2. Romper referencias circulares en patient_clinic_visits (si existe)
DO $$ BEGIN
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'patient_clinic_visits') THEN
        UPDATE patient_clinic_visits
        SET checkin_nfc_scan_id  = NULL,
            checkout_nfc_scan_id = NULL;
        DELETE FROM patient_clinic_visits;
    END IF;
END $$;

-- 3. Romper visit_id en nfc_scan_events (si existe la columna)
DO $$ BEGIN
    IF EXISTS (
        SELECT FROM information_schema.columns
        WHERE table_name = 'nfc_scan_events' AND column_name = 'visit_id'
    ) THEN
        UPDATE nfc_scan_events SET visit_id = NULL;
    END IF;
END $$;

-- 4. Vaciar eventos de escaneo
DELETE FROM nfc_scan_events;

-- 5. Vaciar tarjetas NFC
DELETE FROM nfc_cards;

-- 6. Reiniciar secuencias
ALTER SEQUENCE IF EXISTS nfc_cards_nfc_card_id_seq          RESTART WITH 1;
ALTER SEQUENCE IF EXISTS nfc_scan_events_scan_event_id_seq  RESTART WITH 1;
ALTER SEQUENCE IF EXISTS patient_clinic_visits_visit_id_seq RESTART WITH 1;
ALTER SEQUENCE IF EXISTS visit_area_movements_movement_id_seq RESTART WITH 1;

COMMIT;
