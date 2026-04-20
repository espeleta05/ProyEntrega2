-- ============================================================
--  SEED DATA — Sistema de Vacunación
--  Basado en Esquema Nacional de Vacunación México
-- ============================================================

-- ─────────────────────────────────────────────
--  ADDRESSES
-- ─────────────────────────────────────────────

INSERT INTO countries (country_id, name, iso_code) VALUES
(1, 'México', 'MX');

INSERT INTO states (state_id, country_id, name, code) VALUES
(1, 1, 'Nuevo León', 'NL');

INSERT INTO municipalities (municipality_id, state_id, name) VALUES
(1,  1, 'Monterrey'),
(2,  1, 'Apodaca'),
(3,  1, 'San Nicolás de los Garza'),
(4,  1, 'Guadalupe'),
(5,  1, 'San Pedro Garza García'),
(6,  1, 'Escobedo'),
(7,  1, 'Santa Catarina'),
(8,  1, 'Juárez'),
(9,  1, 'Guadalajara'),
(10, 1, 'Cuauhtémoc');

INSERT INTO neighborhoods (neighborhood_id, municipality_id, name, zip_code) VALUES
(1,  1, 'Centro',                   '64000'),
(2,  2, 'Real de Palmas',           '66630'),
(3,  3, 'Colinas Valle Verde',      '66450'),
(4,  4, 'Las Puentes',              '67116'),
(5,  5, 'Del Valle',                '66220'),
(6,  6, 'Las Cumbres',              '66057'),
(7,  7, 'Cumbres Mediterráneo',     '66378'),
(8,  8, 'Los Encinos',              '67250'),
(9,  1, 'Obispado',                 '64060'),
(10, 2, 'Villas de Apodaca',        '66600');

INSERT INTO addresses (address_id, neighborhood_id, street, ext_number, cross_street_1, latitude, longitude) VALUES
(1,  1,  'Av. Constitución',       '100',  'Av. Pino Suárez',       25.6686, -100.3092),
(2,  2,  'Calle Ruiz Cortines',    '320',  'Blvd. Las Torres',      25.7804, -100.1880),
(3,  3,  'Blvd. Díaz Ordaz',       '890',  'Av. Universidad',       25.7319, -100.2988),
(4,  4,  'Av. Miguel Alemán',      '450',  'Calle Nogal',           25.6826, -100.2197),
(5,  5,  'Av. Vasconcelos',        '230',  'Av. Morones Prieto',    25.6506, -100.3951),
(6,  6,  'Blvd. Escobedo',         '1100', 'Av. Las Torres',        25.7990, -100.3210),
(7,  7,  'Av. Santa Catarina',     '500',  'Calle Los Pinos',       25.6729, -100.4591),
(8,  8,  'Calle Benito Juárez',    '75',   'Av. Juárez',            25.6427, -100.0869),
(9,  9,  'Av. Ignacio Morones',    '210',  'Calle Tamaulipas',      25.6692, -100.3325),
(10, 10, 'Calle Las Flores',       '88',   'Blvd. Solidaridad',     25.7890, -100.1760),
(11, 1,  'Calle Moctezuma',        '55',   'Av. Zaragoza',          25.6720, -100.3100),
(12, 3,  'Av. Churubusco',         '430',  'Calle Independencia',   25.7300, -100.3010);

-- ─────────────────────────────────────────────
--  CLINICS
-- ─────────────────────────────────────────────

-- Una sola clínica con varias sedes (diferentes address_id)
INSERT INTO clinics (clinic_id, name, address_id, phone, institution_type, is_active) VALUES
(1, 'Centro de Salud Nuevo León — Sede Centro',          1,  '81-2000-0101', 'SSA', TRUE),
(2, 'Centro de Salud Nuevo León — Sede Apodaca',         2,  '81-2000-0102', 'SSA', TRUE),
(3, 'Centro de Salud Nuevo León — Sede San Nicolás',     3,  '81-2000-0103', 'SSA', TRUE),
(4, 'Centro de Salud Nuevo León — Sede Guadalupe',       4,  '81-2000-0104', 'SSA', TRUE),
(5, 'Centro de Salud Nuevo León — Sede San Pedro',       5,  '81-2000-0105', 'SSA', TRUE),
(6, 'Centro de Salud Nuevo León — Sede Escobedo',        6,  '81-2000-0106', 'SSA', TRUE),
(7, 'Centro de Salud Nuevo León — Sede Santa Catarina',  7,  '81-2000-0107', 'SSA', TRUE),
(8, 'Centro de Salud Nuevo León — Sede Juárez',          8,  '81-2000-0108', 'SSA', TRUE),
(9, 'Centro de Salud Nuevo León — Sede Obispado',        9,  '81-2000-0109', 'SSA', TRUE),
(10,'Centro de Salud Nuevo León — Sede Villas Apodaca',  10, '81-2000-0110', 'SSA', TRUE);

-- ─────────────────────────────────────────────
--  CLINIC AREAS
-- ─────────────────────────────────────────────

INSERT INTO area_types (area_type_id, area_type) VALUES
(1, 'Sala_Espera'),
(2, 'Consultorio'),
(3, 'Enfermeria'),
(4, 'Almacen'),
(5, 'Recepcion'),
(6, 'Vacunacion');

INSERT INTO clinic_areas (area_id, clinic_id, name, area_type_id, floor, capacity) VALUES
(1,  1, 'Sala de Espera Principal',       1, 1, 30),
(2,  1, 'Consultorio 1 — Pediatría',      2, 1,  4),
(3,  1, 'Área de Vacunación',             6, 1,  6),
(4,  1, 'Almacén de Biológicos',          4, 1,  2),
(5,  1, 'Recepción',                      5, 1,  3),
(6,  2, 'Sala de Espera A',               1, 1, 25),
(7,  2, 'Consultorio 1 — Vacunación',     2, 1,  4),
(8,  2, 'Área de Vacunación',             6, 1,  6),
(9,  2, 'Almacén de Biológicos',          4, 1,  2),
(10, 3, 'Sala de Espera B',               1, 1, 20),
(11, 3, 'Consultorio Pediátrico',         2, 1,  4),
(12, 3, 'Área de Vacunación',             6, 1,  5),
(13, 4, 'Sala de Espera C',               1, 1, 20),
(14, 4, 'Área de Vacunación',             6, 1,  5),
(15, 5, 'Sala de Espera D',               1, 1, 20),
(16, 5, 'Consultorio Pediátrico',         2, 1,  4);

-- ─────────────────────────────────────────────
--  EQUIPMENT
-- ─────────────────────────────────────────────

INSERT INTO equipment_catalog (equipment_id, name, category, requires_calibration) VALUES
(1,  'Refrigerador Haier 2-8°C',            'Refrigeración', TRUE),
(2,  'Silla de Exploración Pediátrica',     'Mobiliario',    FALSE),
(3,  'Termómetro Digital Infrarrojo',       'Diagnóstico',   TRUE),
(4,  'Báscula Pediátrica Digital',          'Diagnóstico',   TRUE),
(5,  'Carro de Vacunación',                 'Mobiliario',    FALSE),
(6,  'Congelador de Vacunas -20°C',         'Refrigeración', TRUE),
(7,  'Tensiómetro Pediátrico',              'Diagnóstico',   TRUE),
(8,  'Esterilizador UV portátil',           'Esterilización',TRUE),
(9,  'Negatoscopio',                        'Diagnóstico',   FALSE),
(10, 'Escritorio Clínico',                  'Mobiliario',    FALSE);

INSERT INTO area_equipment (area_equipment_id, area_id, equipment_id, quantity, serial_number, condition) VALUES
(1,  4,  1, 2, 'REF-2024-001', 'Bueno'),
(2,  4,  6, 1, 'CON-2023-002', 'Bueno'),
(3,  3,  2, 2, 'SIL-2022-003', 'Bueno'),
(4,  3,  3, 2, 'TER-2023-004', 'Bueno'),
(5,  3,  4, 1, 'BAS-2022-005', 'Regular'),
(6,  3,  5, 1, 'CAR-2024-006', 'Bueno'),
(7,  2,  2, 1, 'SIL-2021-007', 'Bueno'),
(8,  2,  7, 1, 'TEN-2023-008', 'Bueno'),
(9,  2, 10, 1, 'ESC-2020-009', 'Regular'),
(10, 9,  1, 1, 'REF-2024-010', 'Bueno');

    -- ─────────────────────────────────────────────
    --  PATIENTS
    -- ─────────────────────────────────────────────

    INSERT INTO blood_types (blood_type_id, blood_type) VALUES
    (1, 'O+'),
    (2, 'O-'),
    (3, 'A+'),
    (4, 'A-'),
    (5, 'B+'),
    (6, 'B-'),
    (7, 'AB+'),
    (8, 'AB-');

    -- Todos menores de 10 años (nacidos después de 2016-03-24)
    INSERT INTO patients (patient_id, first_name, last_name, birth_date, blood_type_id, gender, nfc_token, curp, weight_kg, premature) VALUES
    (1,  'Sofia',      'Ramirez Torres',     '2024-01-15', 1, 'F', 'NFC001', 'RATS240115MNLMRS01', 4.2,  FALSE)
    (2,  'Mateo',      'González Vega',      '2023-06-10', 3, 'M', 'NFC002', 'GOVM230610HNLNNG02', 9.5,  FALSE)
    (3,  'Valentina',  'Hernández Cruz',     '2022-11-20', 2, 'F', 'NFC003', 'HECV221120MNLRRL03', 11.8, FALSE)
    (4,  'Santiago',   'López Morales',      '2021-04-05', 5, 'M', 'NFC004', 'LOMS210405HNLPRG04', 14.3, FALSE)
    (5,  'Isabella',   'Martínez Sánchez',   '2020-09-18', 7, 'F', 'NFC005', 'MASI200918MNLRRN05', 17.6, FALSE)
    (6,  'Emiliano',   'Flores Reyes',       '2019-03-22', 4, 'M', 'NFC006', 'FOREM190322HNLLL06',20.4, FALSE)
    (7,  'Camila',     'Díaz Ortega',        '2018-07-30', 6, 'F', 'NFC007', 'DIOC180730MNLXZM07', 22.1, TRUE),
    (8,  'Sebastián',  'Pérez Gutiérrez',    '2017-12-12', 8, 'M', 'NFC008', 'PEGS171212HNLRRB08', 24.8, FALSE),
    (9,  'Luciana',    'Vargas Jiménez',     '2016-08-03', 1, 'F', 'NFC009', 'VAJI160803MNLRGN09', 27.0, FALSE),
    (10, 'Nicolás',    'Castro Mendoza',     '2024-07-20', 3, 'M', 'NFC010', 'CAMN240720HNLSRC10', 3.8,  TRUE),
    (11, 'Regina',     'Aguirre Luna',       '2023-02-14', 5, 'F', 'NFC011', 'AULR230214MNLGRN11', 7.2,  FALSE),
    (12, 'Rodrigo',    'Torres Blanco',      '2022-05-25', 2, 'M', 'NFC012', 'TOBR220525HNLRRD12', 12.5, FALSE),
    (13, 'Mariana',    'Sánchez Ríos',       '2021-10-10', 6, 'F', 'NFC013', 'SARM211010MNLNNN13', 15.1, FALSE),
    (14, 'Diego',      'Reyes Ibarra',       '2020-01-28', 4, 'M', 'NFC014', 'REID200128HNLLBY14', 18.9, FALSE),
    (15, 'Ximena',     'Morales Escamilla',  '2019-11-05', 7, 'F', 'NFC015', 'MOEX191105MNLRLS15', 21.3, FALSE);

    -- ─────────────────────────────────────────────
    --  ALLERGIES
    -- ─────────────────────────────────────────────

    INSERT INTO allergies (allergy_id, name, allergy_type) VALUES
    (1,  'Penicilina',          'Medicamento'),
    (2,  'Neomicina',           'Medicamento'),
    (3,  'Látex',               'Latex'),
    (4,  'Huevo',               'Alimento'),
    (5,  'Gelatina',            'Alimento'),
    (6,  'Polen',               'Ambiental'),
    (7,  'Polvo',               'Ambiental'),
    (8,  'Levadura',            'Alimento'),
    (9,  'Sulfas',              'Medicamento'),
    (10, 'Estreptomicina',      'Medicamento');

    INSERT INTO patient_allergies (patient_allergy_id, patient_id, allergy_id, severity, reaction_desc) VALUES
    (1,  3,  2, 'Moderada', 'Eritema cutáneo en zona de aplicación'),
    (2,  5,  4, 'Leve',     'Urticaria leve post-ingesta'),
    (3,  7,  3, 'Severa',   'Anafilaxia documentada en 2020'),
    (4,  9,  1, 'Moderada', 'Erupción cutánea y prurito generalizado'),
    (5,  11, 5, 'Leve',     'Náuseas leves'),
    (6,  13, 6, 'Leve',     'Estornudos y lagrimeo'),
    (7,  14, 8, 'Moderada', 'Dolor abdominal e inflamación'),
    (8,  2,  7, 'Leve',     'Rinitis alérgica'),
    (9,  6,  9, 'Severa',   'Reacción anafiláctica previa'),
    (10, 8, 10, 'Leve',     'Eritema leve');

    -- ─────────────────────────────────────────────
    --  GUARDIANS
    -- ─────────────────────────────────────────────

    INSERT INTO marital_status (marital_status_id, marital_status) VALUES
    (1, 'Casado'),
    (2, 'Soltero');

    INSERT INTO occupations (occupation_id, occupation_name) VALUES
    (1,  'Contador'),
    (2,  'Maestro'),
    (3,  'Enfermero'),
    (4,  'Ingeniero'),
    (5,  'Médico'),
    (6,  'Comerciante'),
    (7,  'Abogado'),
    (8,  'Ama de casa'),
    (9,  'Empleado'),
    (10, 'Arquitecto');

    INSERT INTO guardians (guardian_id, first_name, last_name, curp, address_id, marital_status_id, occupation) VALUES
    (1,  'José Luis',  'Ramírez Garza',    'RAGJ780312HNLMRS01', 1,  1, 4),
    (2,  'Laura',      'Torres Vega',      'TOVL850620MNLRRR02', 2,  1, 2),
    (3,  'Carlos',     'González Pérez',   'GOPC750918HNLNNR03', 3,  2, 1),
    (4,  'Ana María',  'Vega Soto',        'VESA820414MNLGGN04', 4,  1, 8),
    (5,  'Roberto',    'Hernández Luna',   'HELR900101HNLRNB05', 5,  2, 9),
    (6,  'Patricia',   'Cruz Morales',     'CRMP880730MNLRRT06', 6,  2, 2),
    (7,  'Fernando',   'López Ibarra',     'LOIF770505HNLPBR07', 7,  1, 7),
    (8,  'Claudia',    'Morales Fuentes',  'MOFC920215MNLRLN08', 8,  2, 6),
    (9,  'Armando',    'Flores Castro',    'FOCA850909HNLLLR09', 9,  1, 4),
    (10, 'Verónica',   'Reyes Acosta',     'REAV900322MNLLYV10', 10, 2, 3),
    (11, 'Héctor',     'Martínez Rojas',   'MARH800117HNLRRH11', 11, 1, 5),
    (12, 'Sandra',     'Díaz Gutiérrez',   'DIGS870628MNLXZN12', 1,  1, 8);

    INSERT INTO guardian_phones (phone_id, guardian_id, phone, phone_type, is_primary) VALUES
    (1,  1,  '81-1111-2222', 'Celular',  TRUE),
    (2,  1,  '81-1111-3333', 'Trabajo',  FALSE),
    (3,  2,  '81-2222-4444', 'Celular',  TRUE),
    (4,  3,  '81-3333-5555', 'Celular',  TRUE),
    (5,  4,  '81-4444-6666', 'Celular',  TRUE),
    (6,  5,  '81-5555-7777', 'Celular',  TRUE),
    (7,  6,  '81-6666-8888', 'Celular',  TRUE),
    (8,  7,  '81-7777-9999', 'Celular',  TRUE),
    (9,  8,  '81-8888-0000', 'Celular',  TRUE),
    (10, 9,  '81-9999-1111', 'Celular',  TRUE),
    (11, 10, '81-0000-2222', 'Celular',  TRUE),
    (12, 11, '81-1234-5678', 'Celular',  TRUE);

    INSERT INTO guardian_emails (email_id, guardian_id, email, is_primary) VALUES
    (1,  1,  'jose.ramirez@gmail.com',    TRUE),
    (2,  2,  'laura.torres@hotmail.com',  TRUE),
    (3,  3,  'carlos.gonzalez@gmail.com', TRUE),
    (4,  4,  'ana.vega@outlook.com',      TRUE),
    (5,  5,  'roberto.hdz@gmail.com',     TRUE),
    (6,  6,  'patricia.cruz@yahoo.com',   TRUE),
    (7,  7,  'fernando.lopez@gmail.com',  TRUE),
    (8,  8,  'claudia.morales@gmail.com', TRUE),
    (9,  9,  'armando.flores@gmail.com',  TRUE),
    (10, 10, 'veronica.reyes@hotmail.com',TRUE),
    (11, 11, 'hector.mtz@gmail.com',      TRUE),
    (12, 12, 'sandra.diaz@outlook.com',   TRUE);

    INSERT INTO patient_guardian_relations (relation_id, patient_id, guardian_id, relation_type, is_primary, has_custody) VALUES
    (1,  1,  1,  'Padre',  TRUE,  TRUE),
    (2,  1,  2,  'Madre',  FALSE, TRUE),
    (3,  2,  3,  'Padre',  TRUE,  TRUE),
    (4,  3,  4,  'Madre',  TRUE,  TRUE),
    (5,  4,  5,  'Padre',  TRUE,  TRUE),
    (6,  5,  6,  'Madre',  TRUE,  TRUE),
    (7,  6,  7,  'Padre',  TRUE,  TRUE),
    (8,  7,  8,  'Madre',  TRUE,  TRUE),
    (9,  8,  9,  'Padre',  TRUE,  TRUE),
    (10, 9,  10, 'Madre',  TRUE,  TRUE),
    (11, 10, 1,  'Padre',  TRUE,  TRUE),
    (12, 11, 11, 'Padre',  TRUE,  TRUE),
    (13, 12, 12, 'Madre',  TRUE,  TRUE),
    (14, 13, 6,  'Madre',  FALSE, TRUE),
    (15, 14, 7,  'Padre',  FALSE, TRUE);

    -- ─────────────────────────────────────────────
    --  WORKERS
    -- ─────────────────────────────────────────────

    INSERT INTO roles (role_id, name, description) VALUES
    (1, 'Administrador', 'Gestión del sistema y usuarios'),
    (2, 'Doctor',        'Consulta médica y supervisión clínica'),
    (3, 'Enfermero',     'Aplicación de vacunas y cuidados de enfermería'),
    (4, 'Almacen',       'Control de inventario de biológicos e insumos');

    INSERT INTO specialties (specialty_id, name) VALUES
    (1,  'Pediatría'),
    (2,  'Enfermería Pediátrica'),
    (3,  'Medicina Familiar'),
    (4,  'Epidemiología'),
    (5,  'Vacunología'),
    (6,  'Inmunología'),
    (7,  'Salud Pública'),
    (8,  'Enfermería General'),
    (9,  'Administración en Salud'),
    (10, 'Logística Médica');

    INSERT INTO institutions (institution_id, institution_name, address_id) VALUES
    (1,  'UANL — Facultad de Medicina',       1),
    (2,  'UDEM',                              5),
    (3,  'TEC de Monterrey — Medicina',       9),
    (4,  'IPN — ENMH',                        11),
    (5,  'UAM Xochimilco',                    12),
    (6,  'UANL — Facultad de Enfermería',     1),
    (7,  'Cruz Roja Mexicana',                2),
    (8,  'IMSS — Centro de Capacitación',     3),
    (9,  'SSA — Dirección General',           4),
    (10, 'Hospital Universitario UANL',       1);

    -- Contraseña hasheada bcrypt de "Salud2024!"
    INSERT INTO workers (worker_id, role_id, first_name, last_name, curp, address_id, birth_date, hire_date, password_hash) VALUES
    (1,  1, 'María Elena',  'González Soto',   'GOSM880512MNLNTR01', 1,  '1988-05-12', '2015-03-01', '$2b$12$KIx4O5EYVxmNQe9oFuLwCO1UZ2XVDL.bJt7pFm3kNwHcAe5G0DVGS'),
    (2,  2, 'Carlos Alberto','Herrera Vega',   'HEVC750419HNLRRL02', 2,  '1975-04-19', '2010-07-20', '$2b$12$KIx4O5EYVxmNQe9oFuLwCO1UZ2XVDL.bJt7pFm3kNwHcAe5G0DVGS'),
    (3,  3, 'Ana Lucía',    'Martínez Ruiz',   'MARA821011MNLRRN03', 3,  '1982-10-11', '2018-01-10', '$2b$12$KIx4O5EYVxmNQe9oFuLwCO1UZ2XVDL.bJt7pFm3kNwHcAe5G0DVGS'),
    (4,  4, 'Luis Ángel',   'Vega Treviño',    'VETL920203HNLGRN04', 4,  '1992-02-03', '2020-06-15', '$2b$12$KIx4O5EYVxmNQe9oFuLwCO1UZ2XVDL.bJt7pFm3kNwHcAe5G0DVGS'),
    (5,  2, 'Rosa Isabel',  'Garza Cantú',     'GACR850714MNLRNR05', 5,  '1985-07-14', '2012-09-01', '$2b$12$KIx4O5EYVxmNQe9oFuLwCO1UZ2XVDL.bJt7pFm3kNwHcAe5G0DVGS'),
    (6,  3, 'Jorge Iván',   'Sánchez Medina',  'SAMJ900328HNLNDR06', 6,  '1990-03-28', '2019-04-01', '$2b$12$KIx4O5EYVxmNQe9oFuLwCO1UZ2XVDL.bJt7pFm3kNwHcAe5G0DVGS'),
    (7,  3, 'Claudia Irene','Moreno Leal',     'MOLC880605MNLRLN07', 7,  '1988-06-05', '2017-11-15', '$2b$12$KIx4O5EYVxmNQe9oFuLwCO1UZ2XVDL.bJt7pFm3kNwHcAe5G0DVGS'),
    (8,  2, 'Ernesto',      'Ramírez Peña',    'RAPE770830HNLMNR08', 8,  '1977-08-30', '2008-03-20', '$2b$12$KIx4O5EYVxmNQe9oFuLwCO1UZ2XVDL.bJt7pFm3kNwHcAe5G0DVGS'),
    (9,  4, 'Daniela',      'Fuentes Ibarra',  'FUID950112MNLNBD09', 9,  '1995-01-12', '2022-01-05', '$2b$12$KIx4O5EYVxmNQe9oFuLwCO1UZ2XVDL.bJt7pFm3kNwHcAe5G0DVGS'),
    (10, 1, 'Miguel Ángel', 'Torres Castillo', 'TOCM830917HNLRSG10', 10, '1983-09-17', '2016-08-01', '$2b$12$KIx4O5EYVxmNQe9oFuLwCO1UZ2XVDL.bJt7pFm3kNwHcAe5G0DVGS'),
    (11, 3, 'Paola',        'Reyes Guzmán',    'REGP930425MNLLYN11', 11, '1993-04-25', '2021-03-10', '$2b$12$KIx4O5EYVxmNQe9oFuLwCO1UZ2XVDL.bJt7pFm3kNwHcAe5G0DVGS'),
    (12, 2, 'Héctor Manuel','Luna Salinas',    'LUSH800614HNLNNC12', 12, '1980-06-14', '2009-11-01', '$2b$12$KIx4O5EYVxmNQe9oFuLwCO1UZ2XVDL.bJt7pFm3kNwHcAe5G0DVGS');

    INSERT INTO worker_professional (worker_id, cedula_profesional, specialty_id, institution_id) VALUES
    (2,  '5432876', 1,  1),
    (2,  '5432876', 3,  10),
    (3,  '6789012', 2,  6),
    (5,  '4123456', 1,  2),
    (5,  '4123456', 4,  9),
    (6,  '7654321', 5,  8),
    (7,  '8765432', 8,  7),
    (8,  '3456789', 1,  3),
    (8,  '3456789', 6,  10),
    (11, '9012345', 2,  6),
    (12, '2345678', 1,  1),
    (12, '2345678', 7,  9);

    INSERT INTO worker_phones (phone_id, worker_id, phone, phone_type, is_primary) VALUES
    (1,  1,  '81-3001-1111', 'Celular', TRUE),
    (2,  2,  '81-3001-2222', 'Celular', TRUE),
    (3,  3,  '81-3001-3333', 'Celular', TRUE),
    (4,  4,  '81-3001-4444', 'Celular', TRUE),
    (5,  5,  '81-3001-5555', 'Celular', TRUE),
    (6,  6,  '81-3001-6666', 'Celular', TRUE),
    (7,  7,  '81-3001-7777', 'Celular', TRUE),
    (8,  8,  '81-3001-8888', 'Celular', TRUE),
    (9,  9,  '81-3001-9999', 'Celular', TRUE),
    (10, 10, '81-3002-0000', 'Celular', TRUE),
    (11, 11, '81-3002-1111', 'Celular', TRUE),
    (12, 12, '81-3002-2222', 'Celular', TRUE);

    INSERT INTO worker_emails (email_id, worker_id, email, is_primary) VALUES
    (1,  1,  'mgonzalez@saludnl.gob.mx',  TRUE),
    (2,  2,  'cherrera@saludnl.gob.mx',   TRUE),
    (3,  3,  'amartinez@saludnl.gob.mx',  TRUE),
    (4,  4,  'lvega@saludnl.gob.mx',      TRUE),
    (5,  5,  'rgarza@saludnl.gob.mx',     TRUE),
    (6,  6,  'jsanchez@saludnl.gob.mx',   TRUE),
    (7,  7,  'cmoreno@saludnl.gob.mx',    TRUE),
    (8,  8,  'eramirez@saludnl.gob.mx',   TRUE),
    (9,  9,  'dfuentes@saludnl.gob.mx',   TRUE),
    (10, 10, 'mtorres@saludnl.gob.mx',    TRUE),
    (11, 11, 'preyes@saludnl.gob.mx',     TRUE),
    (12, 12, 'hluna@saludnl.gob.mx',      TRUE);

    INSERT INTO worker_clinic_assignment (assignment_id, worker_id, clinic_id, area_id, start_date, end_date, is_active) VALUES
    (1,  1,  1, 5,  '2015-03-01', NULL, TRUE),
    (2,  2,  1, 2,  '2010-07-20', NULL, TRUE),
    (3,  3,  1, 3,  '2018-01-10', NULL, TRUE),
    (4,  4,  1, 4,  '2020-06-15', NULL, TRUE),
    (5,  5,  2, 7,  '2012-09-01', NULL, TRUE),
    (6,  6,  2, 8,  '2019-04-01', NULL, TRUE),
    (7,  7,  3, 12, '2017-11-15', NULL, TRUE),
    (8,  8,  3, 11, '2008-03-20', NULL, TRUE),
    (9,  9,  2, 9,  '2022-01-05', NULL, TRUE),
    (10, 10, 4, 13, '2016-08-01', NULL, TRUE),
    (11, 11, 4, 14, '2021-03-10', NULL, TRUE),
    (12, 12, 5, 15, '2009-11-01', NULL, TRUE);

    INSERT INTO worker_schedules (schedule_id, worker_id, clinic_id, day_of_week, entry_time, exit_time, shift_type) VALUES
    (1,  1,  1, 1, '08:00', '14:00', 'Matutino'),
    (2,  1,  1, 2, '08:00', '14:00', 'Matutino'),
    (3,  1,  1, 3, '08:00', '14:00', 'Matutino'),
    (4,  2,  1, 1, '08:00', '15:00', 'Matutino'),
    (5,  2,  1, 2, '08:00', '15:00', 'Matutino'),
    (6,  3,  1, 1, '08:00', '14:00', 'Matutino'),
    (7,  3,  1, 2, '08:00', '14:00', 'Matutino'),
    (8,  4,  1, 1, '08:00', '14:00', 'Matutino'),
    (9,  5,  2, 1, '14:00', '20:00', 'Vespertino'),
    (10, 5,  2, 2, '14:00', '20:00', 'Vespertino'),
    (11, 6,  2, 1, '14:00', '20:00', 'Vespertino'),
    (12, 7,  3, 1, '08:00', '14:00', 'Matutino');

    -- ─────────────────────────────────────────────
    --  VACCINES — Basado en Esquema Nacional
    -- ─────────────────────────────────────────────

    INSERT INTO manufacturers (manufacturer_id, name, country_id, contact_email) VALUES
    (1,  'Birmex',                    1, 'contacto@birmex.gob.mx'),
    (2,  'Sanofi Pasteur',            1, 'contacto@sanofi.mx'),
    (3,  'Merck Sharp & Dohme',       1, 'info@msd.com'),
    (4,  'Pfizer',                    1, 'info@pfizer.com'),
    (5,  'GlaxoSmithKline (GSK)',     1, 'info@gsk.com'),
    (6,  'Serum Institute of India',  1, 'info@seruminstitute.com'),
    (7,  'Janssen',                   1, 'info@janssen.com'),
    (8,  'AstraZeneca',               1, 'info@astrazeneca.com'),
    (9,  'Abbott',                    1, 'info@abbott.com'),
    (10, 'Laboratorio Avi-Mex',       1, 'contacto@avimex.com');

    INSERT INTO vaccine_vias (via_id, via) VALUES
    (1, 'Intradérmica'),
    (2, 'Intramuscular'),
    (3, 'Subcutánea'),
    (4, 'Oral');

    -- Vacunas del Esquema Nacional de Vacunación México
    INSERT INTO vaccines (vaccine_id, name, commercial_name, manufacturer_id, via_id, ideal_age_months, descripcion) VALUES
    (1,  'BCG',                  'BCG Birmex',        1, 1,  0,  'Tuberculosis — dosis única al nacimiento'),
    (2,  'Hepatitis B',          'Engerix-B',         5, 2,  0,  'Hepatitis B — primera dosis al nacimiento'),
    (3,  'Pentavalente acelular','Pentaxim',          2, 2,  2,  'DPT + Hib + Polio inactivado — 3 dosis'),
    (4,  'Hepatitis B (serie)',  'Engerix-B pediátrica',5,2,  2,  'Hepatitis B — dosis 2 y 3 de la serie'),
    (5,  'Rotavirus',            'RotaTeq',           3, 4,  2,  'Diarrea por Rotavirus — 3 dosis orales'),
    (6,  'Neumococo conjugada',  'Prevenar 13',       4, 2,  2,  'Neumococo 13V — 3 dosis + refuerzo'),
    (7,  'Influenza',            'Fluvax Pediátrica', 10,2,  6,  'Influenza estacional — anual desde 6 meses'),
    (8,  'SRP',                  'M-M-R II',          3, 3,  12, 'Sarampión, Rubeola, Parotiditis — 2 dosis'),
    (9,  'Pentavalente refuerzo','Pentaxim refuerzo', 2, 2,  18, 'DPT + Hib + Polio — refuerzo 18 meses'),
    (10, 'DPT (refuerzo)',       'Tripacel',          2, 2,  48, 'Difteria, Pertussis, Tétanos — refuerzo 4 años'),
    (11, 'OPV',                  'Polio oral',        1, 4,  60, 'Polio oral — Semanas Nacionales de Salud'),
    (12, 'VPH',                  'Gardasil 9',        3, 2,  132,'Virus del Papiloma Humano — 5to grado primaria');

    -- ─────────────────────────────────────────────
    --  VACCINE LOTS
    -- ─────────────────────────────────────────────

    INSERT INTO vaccine_lots (lot_id, vaccine_id, clinic_id, lot_number, quantity_received, quantity_available, expiration_date, received_date) VALUES
    (1,  1,  1, 'BCG-2025-A001',   200, 182, '2026-03-31', '2025-01-05'),
    (2,  2,  1, 'HEPB-2025-B001',  150, 121, '2026-10-15', '2025-01-05'),
    (3,  3,  1, 'PENT-2025-C001',  100,  87, '2026-08-31', '2025-01-15'),
    (4,  4,  1, 'HEPBS-2025-D001', 100,  93, '2026-10-15', '2025-01-15'),
    (5,  5,  1, 'ROTA-2025-E001',   80,  61, '2025-12-15', '2025-01-10'),
    (6,  6,  1, 'NEUM-2025-F001',  120,  98, '2026-12-31', '2025-01-20'),
    (7,  7,  1, 'INFL-2025-G001',  200, 155, '2025-06-30', '2025-01-03'),
    (8,  8,  1, 'SRP-2025-H001',    60,  47, '2026-06-30', '2025-02-01'),
    (9,  9,  2, 'PENTR-2025-I001',  80,  72, '2026-08-31', '2025-01-15'),
    (10, 10, 2, 'DPT-2025-J001',    70,  63, '2026-09-30', '2025-02-10'),
    (11, 11, 3, 'OPV-2025-K001',   100,  88, '2025-09-30', '2025-01-10'),
    (12, 12, 4, 'VPH-2025-L001',    50,  48, '2027-06-30', '2025-03-01');

    -- ─────────────────────────────────────────────
    --  OFFICIAL SCHEME — Cartilla Nacional 2024
    -- ─────────────────────────────────────────────

    INSERT INTO vaccination_scheme (scheme_id, name, issuing_body, year, is_current) VALUES
    (1, 'Cartilla Nacional de Vacunación 2024', 'SSA México', 2024, TRUE),
    (2, 'Cartilla Nacional de Vacunación 2023', 'SSA México', 2023, FALSE);

    -- scheme_doses basado en la imagen del Esquema Nacional
    INSERT INTO scheme_doses (dose_id, scheme_id, vaccine_id, dose_number, dose_label, ideal_age_months, min_interval_days) VALUES
    -- Nacimiento
    (1,  1, 1,  1, 'BCG — Dosis única',              0,   NULL),
    (2,  1, 2,  1, 'Hepatitis B — 1ra dosis',         0,   NULL),
    -- 2 meses
    (3,  1, 3,  1, 'Pentavalente — 1ra dosis',        2,   NULL),
    (4,  1, 4,  2, 'Hepatitis B — 2da dosis',         2,   56),
    (5,  1, 5,  1, 'Rotavirus — 1ra dosis',           2,   NULL),
    (6,  1, 6,  1, 'Neumococo — 1ra dosis',           2,   NULL),
    -- 4 meses
    (7,  1, 3,  2, 'Pentavalente — 2da dosis',        4,   56),
    (8,  1, 5,  2, 'Rotavirus — 2da dosis',           4,   28),
    (9,  1, 6,  2, 'Neumococo — 2da dosis',           4,   56),
    -- 6 meses
    (10, 1, 3,  3, 'Pentavalente — 3ra dosis',        6,   56),
    (11, 1, 4,  3, 'Hepatitis B — 3ra dosis',         6,   56),
    (12, 1, 5,  3, 'Rotavirus — 3ra dosis',           6,   28),
    (13, 1, 7,  1, 'Influenza — 1ra dosis',           6,   NULL),
    -- 7 meses
    (14, 1, 7,  2, 'Influenza — 2da dosis',           7,   28),
    -- 12 meses
    (15, 1, 8,  1, 'SRP — 1ra dosis',                12,  NULL),
    (16, 1, 6,  3, 'Neumococo — 3ra dosis',           12,  56),
    -- 18 meses
    (17, 1, 9,  1, 'Pentavalente — Refuerzo',         18,  NULL),
    -- 24 meses (2 años)
    (18, 1, 7,  3, 'Influenza refuerzo anual',        24,  365),
    -- 36 meses (3 años)
    (19, 1, 7,  4, 'Influenza refuerzo anual',        36,  365),
    -- 48 meses (4 años)
    (20, 1, 10, 1, 'DPT — Refuerzo',                 48,  NULL),
    (21, 1, 7,  5, 'Influenza refuerzo anual',        48,  365),
    -- 59 meses (5 años)
    (22, 1, 7,  6, 'Influenza refuerzo anual oct-ene',59,  365),
    (23, 1, 11, 1, 'OPV — Semanas Nacionales Salud',  60,  NULL),
    -- 72 meses (6 años)
    (24, 1, 8,  2, 'SRP — Refuerzo',                 72,  NULL),
    -- 11 años / 5to primaria
    (25, 1, 12, 1, 'VPH — 1ra dosis',               132,  NULL),
    (26, 1, 12, 2, 'VPH — 2da dosis',               138,  180);

    -- ─────────────────────────────────────────────
    --  APPLICATION SITES
    -- ─────────────────────────────────────────────

    INSERT INTO application_sites (application_site_id, application_site) VALUES
    (1, 'Muslo_Izq'),
    (2, 'Muslo_Der'),
    (3, 'Brazo_Izq'),
    (4, 'Brazo_Der'),
    (5, 'Oral'),
    (6, 'Intradermica_Hombro_Der'),
    (7, 'Glúteo_Izq'),
    (8, 'Glúteo_Der');

    -- ─────────────────────────────────────────────
    --  APPOINTMENTS
    -- ─────────────────────────────────────────────

    INSERT INTO appointments (appointment_id, patient_id, clinic_id, area_id, worker_id, scheduled_at, duration_min, reason, appointment_status, appointment_notes) VALUES
    (1,  1,  1, 3, 3, '2024-02-10 09:00', 20, 'Vacuna BCG y Hepatitis B — nacimiento',      'Completada', 'Sin incidencias'),
    (2,  2,  1, 3, 3, '2023-08-15 10:00', 20, 'Pentavalente 1ra dosis — 2 meses',           'Completada', 'Sin incidencias'),
    (3,  3,  2, 8, 6, '2023-01-25 09:30', 20, 'Pentavalente 1ra dosis',                     'Completada', NULL),
    (4,  4,  1, 3, 3, '2021-06-10 11:00', 20, 'SRP 1ra dosis — 12 meses',                   'Completada', NULL),
    (5,  5,  2, 8, 6, '2021-09-20 09:00', 20, 'Influenza refuerzo anual',                   'Completada', NULL),
    (6,  6,  3,12, 7, '2020-03-22 10:30', 20, 'SRP 1ra dosis',                              'Completada', NULL),
    (7,  7,  1, 3, 3, '2019-07-30 09:00', 20, 'BCG nacimiento',                             'Completada', 'Paciente prematura'),
    (8,  8,  2, 8, 6, '2019-12-12 11:00', 20, 'DPT refuerzo — 4 años',                      'Completada', NULL),
    (9,  9,  1, 3, 3, '2018-08-03 09:00', 20, 'BCG nacimiento',                             'Completada', NULL),
    (10, 10, 1, 3, 3, '2024-08-10 10:00', 20, 'BCG y Hepatitis B — nacimiento',             'Completada', 'Paciente prematuro'),
    (11, 1,  1, 3, 3, '2024-04-15 09:30', 20, 'Pentavalente 1ra dosis — 2 meses',           'Completada', NULL),
    (12, 2,  1, 3, 3, '2024-02-20 10:00', 20, 'SRP 2da dosis — refuerzo',                  'Pendiente',  'Próxima cita programada'),
    (13, 11, 1, 3, 3, '2023-04-20 09:00', 20, 'Pentavalente 1ra dosis',                    'Completada', NULL),
    (14, 12, 2, 8, 6, '2022-07-30 10:00', 20, 'Pentavalente 2da dosis',                    'Completada', NULL),
    (15, 13, 3,12, 7, '2022-10-15 11:00', 20, 'SRP 1ra dosis',                             'Completada', NULL);

    -- ─────────────────────────────────────────────
    --  VACCINATION RECORDS
    -- ─────────────────────────────────────────────

    INSERT INTO vaccination_records (record_id, patient_id, vaccine_id, worker_id, clinic_id, lot_id, scheme_dose_id, applied_date, application_site_id, patient_temp_c, had_reaction) VALUES
    (1,  1,  1,  3, 1, 1,  1,  '2024-01-15', 6,    36.5, FALSE),  -- Sofía: BCG nacimiento
    (2,  1,  2,  3, 1, 2,  2,  '2024-01-15', 1,    36.5, FALSE),  -- Sofía: HepB 1ra
    (3,  1,  3,  3, 1, 3,  3,  '2024-03-15', 1,    36.7, FALSE),  -- Sofía: Penta 1ra
    (4,  1,  4,  3, 1, 4,  4,  '2024-03-15', 2,    36.7, FALSE),  -- Sofía: HepB 2da
    (5,  1,  5,  3, 1, 5,  5,  '2024-03-15', 5,    36.7, FALSE),  -- Sofía: Rota 1ra
    (6,  2,  1,  3, 1, 1,  1,  '2023-06-10', 6,    36.8, FALSE),  -- Mateo: BCG
    (7,  2,  2,  3, 1, 2,  2,  '2023-06-10', 1,    36.8, FALSE),  -- Mateo: HepB 1ra
    (8,  2,  3,  3, 1, 3,  3,  '2023-08-10', 1,    36.9, FALSE),  -- Mateo: Penta 1ra
    (9,  3,  1,  6, 2, 1,  1,  '2022-11-20', 6,    36.6, FALSE),  -- Valentina: BCG
    (10, 3,  2,  6, 2, 2,  2,  '2022-11-20', 2,    36.6, FALSE),  -- Valentina: HepB 1ra
    (11, 3,  3,  6, 2, 3,  3,  '2023-01-20', 1,    36.8, TRUE),   -- Valentina: Penta 1ra (reacción)
    (12, 4,  8,  3, 1, 8,  15, '2022-04-05', 3,    36.5, FALSE),  -- Santiago: SRP 1ra
    (13, 4,  9,  3, 1, 9,  17, '2022-10-05', 1,    36.8, FALSE),  -- Santiago: Penta refuerzo
    (14, 5,  8,  6, 2, 8,  15, '2021-09-18', 3,    36.7, FALSE),  -- Isabella: SRP 1ra
    (15, 5,  7,  6, 2, 7,  18, '2022-09-20', 2,    36.6, FALSE),  -- Isabella: Influenza refuerzo
    (16, 6,  8,  7, 3, 8,  15, '2020-03-22', 3,    36.5, FALSE),  -- Emiliano: SRP 1ra
    (17, 6,  10, 7, 3, 10, 20, '2023-03-22', 2,    36.9, FALSE),  -- Emiliano: DPT refuerzo
    (18, 7,  1,  3, 1, 1,  1,  '2018-07-30', 6,    36.4, FALSE),  -- Camila: BCG
    (19, 8,  10, 6, 2, 10, 20, '2021-12-12', 4,    37.0, FALSE),  -- Sebastián: DPT refuerzo
    (20, 9,  8,  3, 1, 8,  24, '2022-08-03', 3,    36.6, FALSE);  -- Luciana: SRP refuerzo

    -- ─────────────────────────────────────────────
    --  POST VACCINE REACTIONS
    -- ─────────────────────────────────────────────

    INSERT INTO post_vaccine_reactions (reaction_id, record_id, reported_by, symptom, severity, onset_hours, treatment, notified_authority) VALUES
    (1,  11, 6, 'Eritema leve en sitio de aplicación',    'Leve',     4,  'Compresas frías',              FALSE),
    (2,  11, 6, 'Llanto persistente 2h',                  'Leve',     2,  'Observación — cedió solo',     FALSE),
    (3,  3,  3, 'Fiebre 37.8°C transitoria',              'Leve',     12, 'Paracetamol 60mg/kg oral',     FALSE),
    (4,  8,  3, 'Endurecimiento en zona de punción',      'Leve',     6,  'Compresas tibias',             FALSE),
    (5,  19, 6, 'Fiebre 38.0°C',                          'Leve',     12, 'Paracetamol 150mg oral',       FALSE),
    (6,  12, 3, 'Eritema leve post-SRP',                  'Leve',     24, 'Observación',                  FALSE),
    (7,  17, 7, 'Dolor local en sitio de inyección',      'Leve',     2,  'Compresas frías',              FALSE),
    (8,  15, 6, 'Rinorrea leve post-influenza',           'Leve',     48, 'Observación',                  FALSE),
    (9,  20, 3, 'Fiebre 38.2°C post-SRP refuerzo',       'Moderada', 24, 'Paracetamol + hidratación',    FALSE),
    (10, 5,  3, 'Malestar gástrico leve post-rotavirus',  'Leve',     6,  'Hidratación oral',             FALSE);

    -- ─────────────────────────────────────────────
    --  NFC
    -- ─────────────────────────────────────────────

    INSERT INTO nfc_cards (nfc_card_id, patient_id, uid, card_type, issued_date, issued_by, status, last_scanned_at, nfc_card_notes) VALUES
    (1,  1,  '04:A1:2B:11:5C:22:80', 'Pulsera', '2024-01-15', 3, 'Activa',      '2025-03-10 09:00', NULL),
    (2,  2,  '04:B2:3C:22:6D:33:91', 'Pulsera', '2023-06-10', 3, 'Activa',      '2025-03-15 10:30', NULL),
    (3,  3,  '04:C3:4D:33:7E:44:A2', 'Pulsera', '2022-11-20', 6, 'Activa',      '2025-02-28 09:15', NULL),
    (4,  4,  '04:D4:5E:44:8F:55:B3', 'Tarjeta', '2021-04-05', 3, 'Activa',      '2025-01-20 11:00', NULL),
    (5,  5,  '04:E5:6F:55:90:66:C4', 'Pulsera', '2020-09-18', 6, 'Activa',      '2025-03-01 09:45', NULL),
    (6,  6,  '04:F6:70:66:A1:77:D5', 'Pulsera', '2019-03-22', 7, 'Activa',      '2025-02-14 10:00', NULL),
    (7,  7,  '04:07:81:77:B2:88:E6', 'Pulsera', '2018-07-30', 3, 'Activa',      '2025-03-05 08:50', 'Paciente prematura'),
    (8,  8,  '04:18:92:88:C3:99:F7', 'Tarjeta', '2017-12-12', 6, 'Activa',      '2025-02-20 09:30', NULL),
    (9,  9,  '04:29:A3:99:D4:AA:08', 'Pulsera', '2016-08-03', 3, 'Activa',      '2025-01-15 10:10', NULL),
    (10, 10, '04:3A:B4:AA:E5:BB:19', 'Pulsera', '2024-07-20', 3, 'Activa',      NULL,               'Paciente prematuro'),
    (11, 11, '04:4B:C5:BB:F6:CC:2A', 'Pulsera', '2023-02-14', 6, 'Activa',      '2025-03-12 09:00', NULL),
    (12, 12, '04:5C:D6:CC:07:DD:3B', 'Pulsera', '2022-05-25', 6, 'Activa',      '2025-03-08 10:20', NULL);

    INSERT INTO nfc_devices (device_id, clinic_id, area_id, device_name, model, serial_number, nfc_device_status, registered_at) VALUES
    ('TABLET-REC-01',  1, 5,  'Recepción Principal Sede Centro',  'ACR122U',   'SN-001', 'Activo', '2023-01-10'),
    ('TABLET-VAC-01',  1, 3,  'Área Vacunación Sede Centro',      'ACR1252U',  'SN-002', 'Activo', '2023-01-10'),
    ('TABLET-REC-02',  2, 6,  'Recepción Sede Apodaca',           'ACR122U',   'SN-003', 'Activo', '2023-06-15'),
    ('TABLET-VAC-02',  2, 8,  'Área Vacunación Sede Apodaca',     'ACR1252U',  'SN-004', 'Activo', '2023-06-15'),
    ('TABLET-REC-03',  3, 10, 'Recepción Sede San Nicolás',       'ACR122U',   'SN-005', 'Activo', '2023-09-01'),
    ('TABLET-VAC-03',  3, 12, 'Área Vacunación Sede San Nicolás', 'ACR1252U',  'SN-006', 'Activo', '2023-09-01'),
    ('TABLET-REC-04',  4, 13, 'Recepción Sede Guadalupe',         'ACR122U',   'SN-007', 'Activo', '2024-01-15'),
    ('TABLET-VAC-04',  4, 14, 'Área Vacunación Sede Guadalupe',   'ACR1252U',  'SN-008', 'Activo', '2024-01-15'),
    ('TABLET-REC-05',  5, 15, 'Recepción Sede San Pedro',         'ACR122U',   'SN-009', 'Activo', '2024-03-01'),
    ('TABLET-CONS-01', 1, 2,  'Consultorio 1 Sede Centro',        'ACR1252U',  'SN-010', 'Activo', '2023-01-10');

    INSERT INTO nfc_scan_events (scan_event_id, nfc_card_id, scanned_by, clinic_id, area_id, scanned_at, action_triggered, device_id, nfc_scan_result) VALUES
    (1,  1, 3, 1, 5, '2025-03-10 08:55', 'Registrar_Llegada', 'TABLET-REC-01',  'OK'),
    (2,  1, 3, 1, 3, '2025-03-10 09:02', 'Abrir_Expediente',  'TABLET-VAC-01',  'OK'),
    (3,  2, 3, 1, 5, '2025-03-15 10:25', 'Registrar_Llegada', 'TABLET-REC-01',  'OK'),
    (4,  2, 3, 1, 3, '2025-03-15 10:32', 'Abrir_Expediente',  'TABLET-VAC-01',  'OK'),
    (5,  3, 6, 2, 6, '2025-02-28 09:10', 'Registrar_Llegada', 'TABLET-REC-02',  'OK'),
    (6,  3, 6, 2, 8, '2025-02-28 09:18', 'Abrir_Expediente',  'TABLET-VAC-02',  'OK'),
    (7,  5, 6, 2, 6, '2025-03-01 09:40', 'Registrar_Llegada', 'TABLET-REC-02',  'OK'),
    (8,  6, 7, 3,10, '2025-02-14 09:55', 'Registrar_Llegada', 'TABLET-REC-03',  'OK'),
    (9,  7, 3, 1, 5, '2025-03-05 08:45', 'Registrar_Llegada', 'TABLET-REC-01',  'OK'),
    (10, 9, 3, 1, 5, '2025-01-15 10:05', 'Registrar_Llegada', 'TABLET-REC-01',  'OK'),
    (11,11, 6, 2, 6, '2025-03-12 08:58', 'Registrar_Llegada', 'TABLET-REC-02',  'OK'),
    (12,12, 6, 2, 6, '2025-03-08 10:15', 'Registrar_Llegada', 'TABLET-REC-02',  'OK');

    -- ─────────────────────────────────────────────
    --  GPS
    -- ─────────────────────────────────────────────

    INSERT INTO gps_devices (gps_device_id, patient_id, device_type, model, imei, assigned_date, assigned_by, battery_pct, gps_device_status) VALUES
    (1,  1,  'Pulsera GPS', 'LK209A',     '123456789012345', '2024-02-01', 3, 92, 'Activo'),
    (2,  2,  'Pulsera GPS', 'LK209A',     '234567890123456', '2023-07-01', 3, 85, 'Activo'),
    (3,  3,  'Pulsera GPS', 'LK209B',     '345678901234567', '2023-01-15', 6, 78, 'Activo'),
    (4,  4,  'App Tutor',   'iPhone15',   NULL,              '2021-05-01', 3, NULL,'Activo'),
    (5,  5,  'Pulsera GPS', 'LK209A',     '456789012345678', '2020-10-01', 6, 65, 'Activo'),
    (6,  6,  'App Tutor',   'Samsung-S23',NULL,              '2019-04-01', 7, NULL,'Activo'),
    (7,  7,  'Pulsera GPS', 'LK209B',     '567890123456789', '2018-08-01', 3, 88, 'Activo'),
    (8,  8,  'Pulsera GPS', 'LK209A',     '678901234567890', '2018-01-01', 6, 71, 'Activo'),
    (9,  9,  'App Tutor',   'Xiaomi-13',  NULL,              '2016-09-01', 3, NULL,'Activo'),
    (10, 10, 'Pulsera GPS', 'LK209B',     '789012345678901', '2024-08-01', 3, 95, 'Activo');

    INSERT INTO gps_locations (location_id, gps_device_id, patient_id, latitude, longitude, accuracy_m, recorded_at, speed_kmh, altitude_m) VALUES
    (1,  1,  1,  25.668600, -100.309200,  4, '2025-03-10 08:40:00', 0.0,   540),
    (2,  1,  1,  25.668700, -100.309100,  3, '2025-03-10 08:52:00', 2.1,   539),
    (3,  1,  1,  25.668600, -100.309200,  2, '2025-03-10 09:00:00', 0.0,   540),
    (4,  2,  2,  25.780400, -100.188000,  5, '2025-03-15 10:10:00', 0.0,   350),
    (5,  2,  2,  25.780500, -100.188100,  4, '2025-03-15 10:28:00', 1.5,   351),
    (6,  3,  3,  25.731900, -100.298800,  6, '2025-02-28 09:05:00', 3.0,   520),
    (7,  5,  5,  25.650600, -100.395100,  5, '2025-03-01 09:35:00', 0.0,   535),
    (8,  7,  7,  25.672900, -100.459100,  7, '2025-03-05 08:43:00', 1.8,   545),
    (9,  10, 10, 25.668600, -100.309200,  4, '2025-03-10 09:00:00', 0.0,   540),
    (10, 4,  4,  25.682600, -100.219700,  8, '2025-01-20 10:55:00', 0.0,   530),
    (11, 6,  6,  25.799000, -100.321000,  6, '2025-02-14 09:50:00', 2.5,   348),
    (12, 8,  8,  25.642700, -100.086900, 10, '2025-02-20 09:25:00', 0.0,   490);

    INSERT INTO gps_safe_zones (zone_id, patient_id, guardian_id, zone_name, center_lat, center_lng, radius_m, is_active) VALUES
    (1,  1,  1,  'Casa',                   25.669500, -100.310000, 150, TRUE),
    (2,  1,  1,  'Clínica Centro',         25.668600, -100.309200, 100, TRUE),
    (3,  2,  3,  'Casa',                   25.780400, -100.188000, 150, TRUE),
    (4,  2,  3,  'Escuela Primaria',       25.781000, -100.187000, 120, TRUE),
    (5,  3,  4,  'Casa',                   25.731900, -100.298800, 150, TRUE),
    (6,  4,  5,  'Casa',                   25.682600, -100.219700, 150, TRUE),
    (7,  5,  6,  'Casa',                   25.650600, -100.395100, 150, TRUE),
    (8,  6,  7,  'Casa',                   25.799000, -100.321000, 150, TRUE),
    (9,  7,  8,  'Casa',                   25.672900, -100.459100, 150, TRUE),
    (10, 8,  9,  'Casa',                   25.642700, -100.086900, 150, TRUE),
    (11, 9,  10, 'Casa',                   25.669200, -100.309500, 150, TRUE),
    (12, 10, 1,  'Casa',                   25.669500, -100.310000, 100, TRUE);

    INSERT INTO gps_risk_alerts (alert_id, patient_id, gps_device_id, alert_type, triggered_at, location_lat, location_lng, resolved_at, resolved_by, risk_notes) VALUES
    (1,  1,  1, 'Salida_Zona_Segura',   '2025-02-01 16:30', 25.671000, -100.312000, '2025-02-01 16:45', 3, 'Tutor confirmó salida al parque'),
    (2,  3,  3, 'Sin_Señal',            '2025-01-15 11:00', NULL,       NULL,        '2025-01-15 11:30', 6, 'Batería agotada — recargó'),
    (3,  5,  5, 'Batería_Baja',         '2025-02-10 14:00', 25.650600, -100.395100, '2025-02-10 18:00', 6, 'Tutor recargó el dispositivo'),
    (4,  2,  2, 'Salida_Zona_Segura',   '2025-03-05 17:15', 25.783000, -100.186000, '2025-03-05 17:35', 3, 'Fue con familiar autorizado'),
    (5,  7,  7, 'Salida_Zona_Segura',   '2025-01-20 15:00', 25.675000, -100.462000, '2025-01-20 15:20', 7, 'Paciente en patio de vecino'),
    (6,  8,  8, 'Sin_Señal',            '2025-02-05 09:30', NULL,       NULL,        '2025-02-05 10:00', 6, 'Dispositivo reiniciado'),
    (7,  9,  9, 'Inasistencia_Cita',    '2025-03-01 09:30', 25.669200, -100.309500, NULL,               NULL, 'Cita pendiente de reprogramar'),
    (8,  4,  4, 'Batería_Baja',         '2025-01-10 17:00', 25.682600, -100.219700, '2025-01-10 20:00', 3, 'App tutor actualizada y recargada'),
    (9,  6,  6, 'Salida_Zona_Segura',   '2025-02-20 16:45', 25.802000, -100.318000, '2025-02-20 17:10', 7, 'Salida autorizada por tutor'),
    (10, 10, 10,'Sin_Señal',            '2025-02-25 13:00', NULL,       NULL,        '2025-02-25 13:20', 3, 'Señal débil en interior — resuelto');

    -- ─────────────────────────────────────────────
    --  ALERTS AND AUDITS
    -- ─────────────────────────────────────────────

    INSERT INTO scheme_completion_alerts (alert_id, patient_id, scheme_dose_id, due_date, status, notified_at) VALUES
    (1,  1,  6,  '2024-03-15', 'Aplicada',  '2024-03-01 09:00'),  -- Sofía: Neumococo 1ra
    (2,  1,  7,  '2024-05-15', 'Pendiente', NULL),                 -- Sofía: Penta 2da
    (3,  2,  7,  '2023-10-10', 'Aplicada',  '2023-09-25 09:00'),  -- Mateo: Penta 2da (aprox)
    (4,  2,  15, '2024-06-10', 'Pendiente', NULL),                 -- Mateo: SRP 1ra
    (5,  3,  7,  '2023-03-20', 'Aplicada',  '2023-03-05 09:00'),  -- Valentina: Penta 2da
    (6,  4,  17, '2022-10-05', 'Aplicada',  '2022-09-20 09:00'),  -- Santiago: Penta refuerzo
    (7,  5,  19, '2023-09-18', 'Pendiente', NULL),                 -- Isabella: Influenza 3 años
    (8,  6,  20, '2023-03-22', 'Aplicada',  '2023-03-08 09:00'),  -- Emiliano: DPT refuerzo
    (9,  10, 2,  '2024-07-20', 'Pendiente', NULL),                 -- Nicolás: HepB 1ra
    (10, 11, 3,  '2023-04-14', 'Aplicada',  '2023-04-01 09:00'),  -- Regina: Penta 1ra
    (11, 12, 7,  '2022-07-25', 'Aplicada',  '2022-07-10 09:00'),  -- Rodrigo: Penta 2da
    (12, 13, 15, '2022-10-10', 'Aplicada',  '2022-09-25 09:00');  -- Mariana: SRP 1ra

    INSERT INTO supply_catalog (supply_id, name, unit, category) VALUES
    (1,  'Jeringa 0.5ml 25Gx1"',               'Pieza',  'Jeringa'),
    (2,  'Jeringa 1ml 23Gx1"',                 'Pieza',  'Jeringa'),
    (3,  'Torunda de algodón con alcohol',     'Pieza',  'Desechable'),
    (4,  'Guante de látex talla S',            'Par',    'Desechable'),
    (5,  'Guante de látex talla M',            'Par',    'Desechable'),
    (6,  'Guante de látex talla L',            'Par',    'Desechable'),
    (7,  'Bandita adhesiva pediátrica',        'Pieza',  'Desechable'),
    (8,  'Cubre bocas tricapa',                'Pieza',  'Desechable'),
    (9,  'Contenedor de punzocortantes 1L',    'Pieza',  'Residuos'),
    (10, 'Solución salina 10ml',               'Ampolleta','Solución'),
    (11, 'Paracetamol 120mg/5ml gotas',        'Frasco', 'Medicamento'),
    (12, 'Adrenalina 1mg/ml jeringa prellenada','Pieza', 'Emergencia');

    INSERT INTO clinic_inventory (inventory_id, clinic_id, supply_id, quantity, min_stock, last_updated) VALUES
    (1,  1,  1, 500, 100, '2025-03-20'),
    (2,  1,  2, 300,  80, '2025-03-20'),
    (3,  1,  3, 800, 200, '2025-03-20'),
    (4,  1,  5, 150,  50, '2025-03-20'),
    (5,  1,  7, 400, 100, '2025-03-20'),
    (6,  1,  9,  20,   5, '2025-03-20'),
    (7,  2,  1, 350,  80, '2025-03-22'),
    (8,  2,  3, 600, 150, '2025-03-22'),
    (9,  2,  5, 120,  40, '2025-03-22'),
    (10, 3,  1, 250,  80, '2025-03-18'),
    (11, 3,  3, 400, 100, '2025-03-18'),
    (12, 4,  1, 200,  80, '2025-03-15');

    INSERT INTO beacons (beacon_id, uuid, major, minor, area_id, clinic_id, beacon_status, last_ping) VALUES
    (1,  '550e8400-e29b-41d4-a001', 1, 1, 5,  1, 'Online',  '2025-03-24 07:55'),
    (2,  '550e8400-e29b-41d4-a002', 1, 2, 3,  1, 'Online',  '2025-03-24 07:57'),
    (3,  '550e8400-e29b-41d4-a003', 1, 3, 2,  1, 'Online',  '2025-03-24 07:58'),
    (4,  '550e8400-e29b-41d4-a004', 2, 1, 6,  2, 'Online',  '2025-03-24 08:00'),
    (5,  '550e8400-e29b-41d4-a005', 2, 2, 8,  2, 'Online',  '2025-03-24 08:01'),
    (6,  '550e8400-e29b-41d4-a006', 3, 1, 10, 3, 'Online',  '2025-03-24 07:59'),
    (7,  '550e8400-e29b-41d4-a007', 3, 2, 12, 3, 'Offline', '2025-03-22 18:00'),
    (8,  '550e8400-e29b-41d4-a008', 4, 1, 13, 4, 'Online',  '2025-03-24 08:02'),
    (9,  '550e8400-e29b-41d4-a009', 4, 2, 14, 4, 'Online',  '2025-03-24 08:03'),
    (10, '550e8400-e29b-41d4-a010', 5, 1, 15, 5, 'Online',  '2025-03-24 08:05');

    INSERT INTO scan_logs (log_id, patient_id, beacon_id, rssi, scanned_at, scan_type) VALUES
    (1,  1,  2, -65, '2025-03-10 09:00', 'NFC'),
    (2,  2,  2, -70, '2025-03-15 10:30', 'NFC'),
    (3,  3,  4, -72, '2025-02-28 09:15', 'BLE'),
    (4,  5,  5, -68, '2025-03-01 09:42', 'NFC'),
    (5,  6,  6, -75, '2025-02-14 09:58', 'BLE'),
    (6,  7,  1, -62, '2025-03-05 08:47', 'NFC'),
    (7,  9,  1, -66, '2025-01-15 10:08', 'NFC'),
    (8,  11, 4, -71, '2025-03-12 09:02', 'NFC'),
    (9,  12, 5, -69, '2025-03-08 10:18', 'BLE'),
    (10, 4,  8, -74, '2025-01-20 10:58', 'NFC'),
    (11, 8,  4, -73, '2025-02-20 09:28', 'NFC'),
    (12, 1,  3, -64, '2025-03-10 09:05', 'BLE');

    INSERT INTO audit_log (audit_id, table_name, record_id, action, worker_id, changed_at, ip_address) VALUES
    (1,  'vaccination_records', 1,  'INSERT', 3,  '2024-01-15 09:10', '192.168.1.45'),
    (2,  'vaccination_records', 2,  'INSERT', 3,  '2024-01-15 09:11', '192.168.1.45'),
    (3,  'patients',            1,  'UPDATE', 1,  '2024-03-15 10:20', '192.168.1.12'),
    (4,  'vaccination_records', 3,  'INSERT', 3,  '2024-03-15 09:05', '192.168.1.45'),
    (5,  'vaccine_lots',        1,  'UPDATE', 4,  '2024-03-15 09:06', '192.168.1.50'),
    (6,  'appointments',        1,  'INSERT', 1,  '2024-01-10 08:00', '192.168.1.12'),
    (7,  'nfc_cards',           1,  'INSERT', 3,  '2024-01-15 09:15', '192.168.1.45'),
    (8,  'gps_devices',         1,  'INSERT', 3,  '2024-02-01 10:00', '192.168.1.45'),
    (9,  'guardians',           1,  'UPDATE', 1,  '2024-05-20 11:30', '192.168.1.12'),
    (10, 'vaccination_records', 11, 'INSERT', 6,  '2023-01-20 09:30', '192.168.2.10'),
    (11, 'post_vaccine_reactions',1,'INSERT', 6,  '2023-01-20 09:45', '192.168.2.10'),
    (12, 'vaccine_lots',        5,  'UPDATE', 9,  '2024-01-20 08:00', '192.168.1.55');