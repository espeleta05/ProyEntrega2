CREATE OR REPLACE PROCEDURE public.sp_assign_nfc_card(IN p_patient_id integer, IN p_uid character varying, IN p_card_type character varying, IN p_issued_by integer, IN p_notes text, INOUT p_results refcursor)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_nfc_card_id INT;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM patients WHERE patient_id = p_patient_id) THEN
        RAISE EXCEPTION 'El paciente % no existe', p_patient_id;
    END IF;

    IF TRIM(COALESCE(p_uid, '')) = '' THEN
        RAISE EXCEPTION 'El UID de la tarjeta es obligatorio';
    END IF;

    IF EXISTS (SELECT 1 FROM nfc_cards WHERE uid = TRIM(p_uid) AND status = 'Activa') THEN
        RAISE EXCEPTION 'Ya existe una tarjeta activa con el UID %', p_uid;
    END IF;

    IF EXISTS (
        SELECT 1 FROM nfc_cards
        WHERE patient_id = p_patient_id AND status = 'Activa'
    ) THEN
        RAISE EXCEPTION 'El paciente ya tiene una tarjeta NFC activa. Desactivala antes de asignar una nueva.';
    END IF;

    IF p_issued_by IS NOT NULL AND NOT EXISTS (
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
    RETURNING nfc_card_id INTO v_nfc_card_id;

    OPEN p_results FOR
        SELECT TRUE          AS success,
               'Tarjeta NFC asignada correctamente' AS message,
               v_nfc_card_id AS nfc_card_id,
               TRIM(p_uid)   AS uid;

EXCEPTION WHEN OTHERS THEN
    OPEN p_results FOR
        SELECT FALSE AS success, SQLERRM AS message,
               NULL::INT AS nfc_card_id, NULL::VARCHAR AS uid;
END;
$procedure$
