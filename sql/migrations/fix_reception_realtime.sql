-- Corrige sp_reception_realtime: nombre de paciente con COALESCE para evitar NULL
CREATE OR REPLACE PROCEDURE sp_reception_realtime(
    IN    p_clinic_id  INT,
    INOUT p_result     REFCURSOR
)
LANGUAGE plpgsql AS $$
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
            NULLIF(TRIM(COALESCE(p.first_name,'') || ' ' || COALESCE(p.last_name,'')), '') AS full_name,
            DATE_PART('year', AGE(CURRENT_DATE, p.birth_date))::INT         AS age,
            p.photo,
            COALESCE(ca.name, 'Sin área')                                   AS current_area,
            COALESCE(NULLIF(TRIM(COALESCE(w.first_name,'') || ' ' || COALESCE(w.last_name,'')), ''), 'Sin asignar') AS assigned_worker,
            pcv.appointment_id,
            a.scheduled_at,
            a.appointment_status,
            (SELECT COUNT(*) FROM patient_vaccine_schedule pvs
             WHERE pvs.patient_id = p.patient_id AND pvs.status = 'Atrasada') > 0 AS has_overdue_vaccines,
            EXISTS(SELECT 1 FROM patient_allergies WHERE patient_id = p.patient_id) AS has_allergies,
            CASE pcv.visit_status
                WHEN 'En recepcion'  THEN '#3B82F6'
                WHEN 'En espera'     THEN '#F59E0B'
                WHEN 'En consulta'   THEN '#8B5CF6'
                WHEN 'En vacunacion' THEN '#10B981'
                ELSE                      '#6B7280'
            END                                                              AS status_color,
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
$$
