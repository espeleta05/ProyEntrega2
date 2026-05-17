-- ============================================================
-- MIGRACIÓN: SPs del dashboard de recepcionista
-- Ejecutar una vez. Es idempotente (OR REPLACE).
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1. sp_recepcionista_kpis
--    Devuelve una sola fila con conteos del día actual y de
--    pacientes registrados hoy / esta semana.
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE sp_recepcionista_kpis(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
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


-- ────────────────────────────────────────────────────────────
-- 2. sp_recepcionista_citas_hoy
--    Devuelve las citas de hoy con datos de paciente, área,
--    médico y una bandera alerta_tardia (hora ya pasó y
--    la cita sigue Programada/Confirmada).
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE sp_recepcionista_citas_hoy(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT
            a.appointment_id,
            a.scheduled_at,
            a.appointment_status,
            a.patient_id,
            (p.first_name || ' ' || p.last_name)          AS patient_name,
            COALESCE(cat.name, '—')                        AS area_name,
            COALESCE(w.first_name || ' ' || w.last_name,
                     '—')                                  AS worker_name,
            -- ¿Tiene vacuna programada en el esquema?
            EXISTS (
                SELECT 1 FROM patient_vaccine_schedule pvs
                WHERE pvs.patient_id = a.patient_id
                  AND pvs.status = 'Pendiente'
                  AND pvs.due_date <= CURRENT_DATE
            )                                              AS vacuna_programada,
            -- Alerta: hora ya pasó y aún no se registró asistencia
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


-- ────────────────────────────────────────────────────────────
-- 3. sp_recepcionista_actividad_reciente
--    Devuelve las últimas N acciones en las últimas 24 h:
--    citas agendadas y pacientes registrados.
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE sp_recepcionista_actividad_reciente(
    IN    p_limit   INT,
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
BEGIN
    OPEN p_results FOR
        SELECT tipo, descripcion, ts
        FROM (
            -- Citas agendadas en las últimas 24 h
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

            -- Pacientes registrados en las últimas 24 h
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


-- ────────────────────────────────────────────────────────────
-- 4. sp_recepcionista_pacientes_semana
--    Pacientes registrados por día en la semana actual
--    (lunes a hoy), para la gráfica de Highcharts.
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE PROCEDURE sp_recepcionista_pacientes_semana(
    INOUT p_results REFCURSOR
)
LANGUAGE plpgsql AS $$
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
