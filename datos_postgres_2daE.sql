-- Datos semilla para segunda entrega (2-3 registros por modulo)

INSERT INTO cat_role (role_name) VALUES
('Administrador'),
('Enfermero'),
('Almacen');

INSERT INTO cat_blood_type (blood_type_code) VALUES
('O+'),
('A+'),
('B+');

INSERT INTO cat_gender (gender_name) VALUES
('Masculino'),
('Femenino');

INSERT INTO cat_risk_level (risk_code, risk_label) VALUES
('low', 'Bajo'),
('medium', 'Medio'),
('high', 'Alto');

INSERT INTO clinics (clinic_name, zone_name, address_line) VALUES
('Clinica Centro', 'Zona Centro', 'Calle Juarez 101'),
('Clinica Norte', 'Zona Norte', 'Av. Universidad 220'),
('Clinica Sur', 'Zona Sur', 'Av. Reforma 330');

INSERT INTO risk_zone (zone_name, risk_level_id, notes) VALUES
('Zona Centro', 3, 'Mas casos respiratorios'),
('Zona Norte', 2, 'Vigilancia semanal'),
('Zona Sur', 1, 'Estable');

INSERT INTO guardians (first_name, last_name, curp, phone, mail, address_line) VALUES
('Maria', 'Martinez', 'MAMM900101HNLRRA01', '8112345678', 'maria@correo.com', 'Col. Centro'),
('Jorge', 'Sanchez', 'JOSA910202HNLNRA02', '8187654321', 'jorge@correo.com', 'Col. Norte'),
('Laura', 'Lopez', 'LALP920303MNLNRA03', '8199911122', 'laura@correo.com', 'Col. Sur');

INSERT INTO patients (first_name, last_name, birth_date, blood_type_id, gender_id, allergies, risk_zone_id) VALUES
('Ana', 'Martinez', '2020-05-15', 1, 2, 'Ninguna', 1),
('Carlos', 'Sanchez', '2019-03-08', 2, 1, 'Polen', 2),
('Daniela', 'Lopez', '2022-10-03', 3, 2, 'Penicilina', 3);

INSERT INTO patient_guardian (patient_id, guardian_id, relationship_type, is_primary) VALUES
(1, 1, 'Madre', TRUE),
(2, 2, 'Padre', TRUE),
(3, 3, 'Madre', TRUE);

INSERT INTO workers (first_name, last_name, role_id, mail, password_hash) VALUES
('Admin', 'Demo', 1, 'admin', 'hash_demo_admin_123'),
('Elena', 'Garza', 2, 'elena@demo.local', 'hash_demo_1'),
('Mario', 'Ruiz', 3, 'mario@demo.local', 'hash_demo_2');

INSERT INTO vaccines (vaccine_name, manufacturer, description, min_age_months, max_age_months) VALUES
('BCG', 'Biofabrica MX', 'Previene tuberculosis infantil', 0, 12),
('Hepatitis B', 'SaludVac', 'Protege contra hepatitis B', 0, NULL),
('Pentavalente', 'GSK', 'Proteccion combinada infantil', 2, 72);

INSERT INTO vaccine_schedule (vaccine_id, dose_order, dose_label, ideal_age_months, min_interval_days) VALUES
(1, 1, 'Dosis 1', 0, 0),
(2, 1, 'Dosis 1', 0, 0),
(3, 1, 'Dosis 1', 2, 0);

INSERT INTO vaccine_batch (vaccine_id, lot_number, expiration_date, stock_qty) VALUES
(1, 'BCG-LOTE-001', '2027-12-31', 120),
(2, 'HEPB-LOTE-001', '2027-12-31', 95),
(3, 'PENTA-LOTE-001', '2027-12-31', 80);

INSERT INTO vaccination_event (patient_id, vaccine_id, batch_id, worker_id, clinic_id, dose_order, applied_date, notes) VALUES
(1, 1, 1, 2, 1, 1, '2025-01-10', 'Sin reacciones'),
(2, 2, 2, 2, 2, 1, '2025-02-15', 'Control en 2 meses'),
(1, 3, 3, 1, 1, 2, '2025-03-20', 'Reforzar hidratacion');

-- Ejemplos de uso de SP simples
-- SELECT sp_registrar_paciente_simple('Luis', 'Perez', '2021-01-01', 'O+', 'Masculino', 'Ninguna');
-- SELECT sp_registrar_vacuna_simple('Influenza', 'DemoLab', 'Dosis anual', 6, NULL);
-- SELECT sp_registrar_aplicacion_simple(1, 1, 2, 1, 1, 1, CURRENT_DATE, 'Aplicacion demo');
-- SELECT * FROM sp_reporte_resumen_simple();
