CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- COUNTRIES
INSERT INTO countries (name, iso_code) VALUES
('México','MX'),
('Rusia','RU'),
('Japón','JP'),
('Alemania', 'DE'),
('Reino Unido', 'GB'),
('Francia', 'FR'),
('Italia', 'IT'),
('China', 'CN');

-- STATES
INSERT INTO states (country_id, name, code) VALUES
(1,'Nuevo León','NL'),
(1,'Jalisco','JA'),
(1,'Ciudad de México','CDMX'),
(1,'Coahuila','COA'),
(1,'Tamaulipas','TAM'),
(1,'Sonora','SON'),
(1,'Chihuahua','CHI'),
(1,'Yucatán','YUC'),
(1,'Puebla','PUE'),
(1,'Querétaro','QRO'),
(1,'Guanajuato','GTO'),
(1,'Sinaloa','SIN'),
(1,'Durango','DGO'),
(1,'Veracruz','VER'),
(1,'Oaxaca','OAX');

-- MUNICIPALITIES
INSERT INTO municipalities (state_id, name) VALUES
(1,'Monterrey'),
(2,'Guadalajara'),
(3,'Benito Juárez'),
(4,'Saltillo'),
(5,'Reynosa'),
(6,'Hermosillo'),
(7,'Chihuahua'),
(8,'Mérida'),
(9,'Puebla'),
(10,'Querétaro');

-- NEIGHBORHOODS
INSERT INTO neighborhoods (neighborhood_id, municipality_id, name, zip_code) VALUES
(1,1,'Centro','64000'),
(2,1,'Monterrey','64010'),
(3,1,'Apodaca', '66600'),
(4,1,'San Nicolás de los Garza','64020'),
(5,1,'Guadalupe','64030'),
(6,1,'San Pedro Garza García','64040'),
(7,1,'Escobedo','64050'),
(8,1,'Santa Catarina','64060'),
(9,1,'Cuauhtémoc','64070'),
(10,1,'García','64080'),
(11,1,'Cadereyta Jiménez','64090'),
(12,1,'Santiago','64100'),
(13,1,'Allende','64120'),
(14,1,'Anáhuac','64130'),
(15,2,'Americana','44160'),
(16,3,'Del Valle','03100'),
(17,4,'República','25280'),
(18,5,'Vista Hermosa','88710'),
(19,6,'Centro','83000'),
(20,7,'Panamericana','31210'),
(21,8,'Montecristo','97133'),
(22,9,'La Paz','72160'),
(23,10,'Juriquilla','76230');

-- ADDRESSES
INSERT INTO addresses (address_id, neighborhood_id, street, ext_number, cross_street_1, latitude, longitude) VALUES
(1, 1,  'Av. Constitución', '100',  'Av. Pino Suárez',       25.6686, -100.3092),
(2, 2,  'Calle Ruiz Cortines', '320',  'Blvd. Las Torres',      25.7804, -100.1880),
(3, 3, 'Blvd. Díaz Ordaz',   '890',  'Av. Universidad',       25.7319, -100.2988),
(4, 4,  'Av. Miguel Alemán',  '450',  'Calle Nogal',           25.6826, -100.2197),
(5, 5,  'Av. Vasconcelos',  '230',  'Av. Morones Prieto',    25.6506, -100.3951),
(6, 6,  'Blvd. Escobedo', '1100', 'Av. Las Torres',        25.7990, -100.3210),
(7, 7,  'Av. Santa Catarina', '500',  'Calle Los Pinos',       25.6729, -100.4591),
(8, 8,  'Calle Benito Juárez', '75',   'Av. Juárez',            25.6427, -100.0869),
(9, 9,  'Av. Ignacio Morones', '210',  'Calle Tamaulipas',      25.6692, -100.3325),
(10, 10, 'Calle Las Flores', '88',   'Blvd. Solidaridad',     25.7890, -100.1760),
(11, 11,  'Calle Moctezuma', '55',   'Av. Zaragoza',          25.6720, -100.3100),
(12, 12,  'Av. Churubusco', '430',  'Calle Independencia',   25.7300, -100.3010),
(13, 13, 'Av. Vallarta','202','Chapultepec',20.6736,-103.3440),
(14, 14,'Insurgentes Sur','303','Félix Cuevas',19.3889,-99.1680),
(15, 15,'Venustiano Carranza','404','Allende',25.4267,-100.9950),
(16, 16,'Hidalgo','505','Juárez',26.0806,-98.2883),
(17, 17,'Morelos','606','Rosales',29.0729,-110.9559),
(18, 18,'Tecnológico','707','Homero',28.6353,-106.0889),
(19, 19,'Paseo Montejo','808','Colón',20.9674,-89.5926),
(20, 20,'Juárez','909','5 de Mayo',19.0414,-98.2063),
(21, 21,'Antea','111','Universidad',20.5888,-100.3899);

-- CLINICS
INSERT INTO clinics (clinic_id, name, address_id, phone, institution_type, is_active) VALUES
(1, 'Clínica Immunicare Centro',          1,  '81-2000-0101', 'SSA', TRUE),
(2, 'Clínica Immunicare Monterrey',       2,  '81-2000-0102', 'SSA', TRUE),
(3, 'Clínica Immunicare Apodaca',         3,  '81-2000-0103', 'SSA', TRUE),
(4, 'Clínica Immunicare San Nicolás',     4,  '81-2000-0104', 'SSA', TRUE),
(5, 'Clínica Immunicare Guadalupe',       5,  '81-2000-0105', 'SSA', TRUE),
(6, 'Clínica Immunicare San Pedro',       6,  '81-2000-0106', 'SSA', TRUE),
(7, 'Clínica Immunicare Escobedo',        7,  '81-2000-0107', 'SSA', TRUE),
(8, 'Clínica Immunicare Santa Catarina',  8,  '81-2000-0108', 'SSA', TRUE),
(9, 'Clínica Immunicare Juárez',          9,  '81-2000-0109', 'SSA', TRUE),
(10, 'Clínica Immunicare Obispado',        10, '81-2000-0110', 'SSA', TRUE);

-- CLINIC AREA TYPES
INSERT INTO clinic_area_types (code, name) VALUES
('WAIT', 'Sala de Espera'),
('VACC', 'Área de Vacunación'),
('CONS', 'Consultorio'),
('NURS', 'Enfermería'),
('RECP', 'Recepción'),
('STOR', 'Almacén');

INSERT INTO clinic_areas (clinic_id, name, area_type_id, code, floor, capacity) VALUES
(1, 'Sala de Espera Principal',       1, 'WAIT-01', 1, 30),
(1, 'Consultorio 1 — Pediatría',      2, 'CONS-01', 1, 4),
(1, 'Área de Vacunación',             6, 'VACC-01', 1, 6),
(1, 'Almacén de Biológicos',          4, 'STOR-01', 1, 2),
(1, 'Recepción',                      5, 'RECP-01', 1, 3),
(2, 'Sala de Espera A',               1, 'WAIT-02', 1, 25),
(2, 'Consultorio 1 — Vacunación',     2, 'CONS-02', 1, 4),
(2, 'Área de Vacunación',             6, 'VACC-02', 1, 6),
(2, 'Almacén de Biológicos',          4, 'STOR-02', 1, 2),
(3, 'Sala de Espera B',               1, 'WAIT-03', 1, 20),
(3, 'Consultorio Pediátrico',         2, 'CONS-03', 1, 4),
(3, 'Área de Vacunación',             6, 'VACC-03', 1, 5),
(3, 'Sala de Espera C',               1, 'WAIT-04', 1, 20),
(4, 'Área de Vacunación',             6, 'VACC-04', 1, 5),
(4, 'Sala de Espera D',               1, 'WAIT-05', 1, 20),
(4, 'Consultorio Pediátrico',         2, 'CONS-04', 1, 4);

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

-- BLOOD TYPES
INSERT INTO blood_types (blood_type) VALUES
('A+'),('A-'),('B+'),('B-'),('AB+'),('AB-'),('O+'),('O-');

-- ALLERGIES
INSERT INTO allergies (name, allergy_type) VALUES
('Penicilina','Medicamento'),
('Polen','Ambiental'),
('Lácteos','Alimento'),
('Maní','Alimento'),
('Mariscos','Alimento'),
('Polvo','Ambiental'),
('Latex','Contacto'),
('Huevos','Alimento'),
('Picadura de abeja','Insecto'),
('Ibuprofeno','Medicamento'),
('Gluten','Alimento'),
('Perfume','Químico'),
('Soya','Alimento'),
('Pelo de gato','Animal'),
('Amoxicilina','Medicamento');

-- PATIENTS
INSERT INTO patients (first_name, last_name, birth_date, blood_type_id, gender, curp, weight_kg, premature) VALUES
('Mateo','García','2018-03-15',1,'M','GAMM180315HNLRTRA1',25.50,FALSE),
('Sofía','Martínez','2019-07-20',2,'F','MASS190720MNLRFBA2',22.10,FALSE),
('Diego','López','2020-01-10',3,'M','LODD200110HNLRPCA3',18.00,TRUE),
('Valentina','Hernández','2017-11-05',4,'F','HEVV171105MNLRLDA4',28.40,FALSE),
('Lucas','Ramírez','2021-06-12',5,'M','RALL210612HNLRMNA5',16.20,FALSE),
('Emma','Torres','2018-08-18',6,'F','TOEE180818MNLRRSA6',24.30,FALSE),
('Sebastián','Flores','2019-04-09',7,'M','FOSS190409HNLRBTA7',20.00,FALSE),
('Camila','Rivera','2020-09-14',8,'F','RICC200914MNLRVCA8',19.40,TRUE),
('Leonardo','Gómez','2017-12-30',1,'M','GOAL171230HNLRMDA9',29.10,FALSE),
('Renata','Díaz','2021-02-25',2,'F','DIRR210225MNLRZEA1',15.70,FALSE),
('Emiliano','Castro','2018-05-03',3,'M','CAEE180503HNLRMSA2',23.60,FALSE),
('Regina','Ortiz','2019-10-16',4,'F','OARR191016MNLRRGA3',21.80,FALSE),
('Daniel','Morales','2020-07-01',5,'M','MODD200701HNLRNTA4',17.90,TRUE),
('Victoria','Ruiz','2017-09-27',6,'F','RUVV170927MNLRKLA5',30.20,FALSE),
('Ángel','Navarro','2021-04-11',7,'M','NAAA210411HNLRVSA6',14.50,FALSE);

INSERT INTO patient_allergies (patient_allergy_id, patient_id, allergy_id, severity, reaction_desc) VALUES
(1,  3,  2, 'Moderada', 'Eritema cutáneo en zona de aplicación'),
(2,  5,  4, 'Leve',     'Urticaria leve post-ingesta'),
(3,  7,  3, 'Severa',   'Anafilaxia documentada en 2020'),
(4,  9,  1, 'Moderada', 'Erupción cutánea y prurito generalizado'),
(5,  11, 5, 'Leve',     'Náuseas leves'),
(6,  13, 6, 'Leve',     'Estornudos y lagrimeo'),
(7,  14, 8, 'Moderada', 'Dolor abdominal e inflamación'), 
(10, 8, 10, 'Leve',     'Eritema leve'),
(11, 10, 11, 'Moderada', 'Diarrea y dolor abdominal'),
(12, 12, 12, 'Leve',     'Irritación cutánea leve'),
(13, 1,  13, 'Moderada', 'Inflamación local y fiebre'),
(14, 4,  14, 'Leve',     'Estornudos y congestión nasal'),
(15, 15, 15, 'Severa',   'Anafilaxia documentada en 2021');

-- MARITAL STATUS
INSERT INTO marital_status (marital_status) VALUES
('Soltero'),('Casado'),('Divorciado'),('Viudo');

-- OCCUPATIONS
INSERT INTO occupations (occupation_name) VALUES
('Ingeniero'),('Doctor'),('Maestro'),('Abogado'),('Contador'),
('Arquitecto'),('Enfermero'),('Chofer'),('Chef'),('Programador'),
('Diseñador'),('Comerciante'),('Mecánico'),('Psicólogo'),('Administrador');

-- GUARDIANS
INSERT INTO guardians (first_name, last_name, curp, address_id, marital_status_id, occupation) VALUES
('Carlos','García','GACC850101HNLRRL01',1,2,1),
('María','Martínez','MARM860202MNLRRS02',2,2,2),
('Luis','López','LOLU870303HNLRPS03',3,1,3),
('Ana','Hernández','HEAA880404MNLRRN04',4,2,4),
('Jorge','Ramírez','RAJO890505HNLRMR05',5,2,5),
('Laura','Torres','TOLA900606MNLRRR06',6,1,6),
('Pedro','Flores','FOPP910707HNLRLD07',7,2,7),
('Elena','Rivera','RIEE920808MNLRVL08',8,2,8),
('Miguel','Gómez','GOMM930909HNLRMR09',9,1,9),
('Patricia','Díaz','DIPP941010MNLRZT10',10,2,10),
('Fernando','Castro','CAFF951111HNLRRS11',11,2,11),
('Gabriela','Ortiz','ORGG961212MNLRRB12',12,1,12),
('Ricardo','Morales','MORR970101HNLRRC13',13,2,13),
('Daniela','Ruiz','RUDD980202MNLRZN14',14,2,14),
('Hugo','Navarro','NAHH990303HNLRVG15',15,1,15);

-- GUARDIAN PHONES
INSERT INTO guardian_phones (guardian_id, phone, phone_type, is_primary) VALUES
(1,'8110000001','Móvil',TRUE),(2,'8110000002','Móvil',TRUE),(3,'8110000003','Casa',TRUE),
(4,'8110000004','Móvil',TRUE),(5,'8110000005','Trabajo',TRUE),(6,'8110000006','Casa',TRUE),
(7,'8110000007','Móvil',TRUE),(8,'8110000008','Trabajo',TRUE),(9,'8110000009','Casa',TRUE),
(10,'8110000010','Móvil',TRUE),(11,'8110000011','Trabajo',TRUE),(12,'8110000012','Casa',TRUE),
(13,'8110000013','Móvil',TRUE),(14,'8110000014','Trabajo',TRUE),(15,'8110000015','Casa',TRUE);

-- GUARDIAN EMAILS
INSERT INTO guardian_emails (email_id, guardian_id, email, is_primary) VALUES
(1, 1, 'carlos.garcia@gmail.com', TRUE),
(2, 2, 'maria.martinez@gmail.com', TRUE),
(3, 3, 'luis.lopez@gmail.com', TRUE),
(4, 4, 'ana.hernandez@gmail.com', TRUE),
(5, 5, 'jorge.ramirez@gmail.com', TRUE),
(6, 6, 'laura.torres@gmail.com', TRUE),
(7, 7, 'pedro.flores@gmail.com', TRUE),
(8, 8, 'elena.rivera@gmail.com', TRUE),
(9, 9, 'miguel.gomez@gmail.com', TRUE),
(10, 10, 'patricia.diaz@gmail.com', TRUE),
(11, 11, 'fernando.castro@gmail.com', TRUE),
(12, 12, 'gabriela.ortiz@gmail.com', TRUE),
(13, 13, 'ricardo.morales@gmail.com', TRUE),
(14, 14, 'daniela.ruiz@gmail.com', TRUE),
(15, 15, 'hugo.navarro@gmail.com', TRUE);

-- PATIENT GUARDIAN RELATIONS
INSERT INTO patient_guardian_relations (patient_id, guardian_id, relation_type, is_primary, has_custody) VALUES
(1,1,'Padre',TRUE,TRUE),
(2,2,'Madre',TRUE,TRUE),
(3,3,'Padre',TRUE,TRUE),
(4,4,'Madre',TRUE,TRUE),
(5,5,'Padre',TRUE,TRUE),
(6,6,'Madre',TRUE,TRUE),
(7,7,'Padre',TRUE,TRUE),
(8,8,'Madre',TRUE,TRUE),
(9,9,'Padre',TRUE,TRUE),
(10,10,'Madre',TRUE,TRUE),
(11,11,'Padre',TRUE,TRUE),
(12,12,'Madre',TRUE,TRUE),
(13,13,'Padre',TRUE,TRUE),
(14,14,'Madre',TRUE,TRUE),
(15,15,'Padre',TRUE,TRUE);

-- ══════════════════════════════════════════════════════════════
-- LIMPIEZA: roles + todo lo que depende via CASCADE
-- (workers, users, appointments, vaccination_records, etc.)
-- Permite re-ejecutar el archivo sin errores de duplicados
-- ══════════════════════════════════════════════════════════════
TRUNCATE TABLE roles RESTART IDENTITY CASCADE;

-- ROLES
INSERT INTO roles (name, description) VALUES
('Administrador','Gestiona el sistema'),
('Enfermero','Aplica vacunas'),
('Medico','Supervisa pacientes'),
('Recepcionista','Agenda citas'),
('Almacen','Controla inventario'),
('Tutor','Cuida pacientes');

-- SPECIALTIES
INSERT INTO specialties (name) VALUES
('Pediatría'),('Medicina General'),('Inmunología'),('Enfermería Pediátrica'), ('Vacunología'),('Atención Primaria'),('Salud Pública'), ('Infectología'),('Epidemiología'),('Medicina Familiar'),('Cuidados Intensivos'),('Medicina Preventiva');

-- INSTITUTIONS
INSERT INTO institutions (institution_name, address_id) VALUES
('UANL',1),('UNAM',2),('IPN',3),('TEC',4),('UDEM',5),('BUAP',6),('UDG',7);

-- WORKERS
INSERT INTO workers (role_id, first_name, last_name, curp, address_id, birth_date, hire_date) VALUES
(1,'José','Pérez','PEPJ850101HNLRRS01',1,'1985-01-01','2020-01-01'),
(2,'Lucía','Santos','SALU860202MNLRNC02',2,'1986-02-02','2020-02-01'),
(3,'Mario','Luna','LUMM870303HNLRNR03',3,'1987-03-03','2020-03-01'),
(4,'Elisa','Campos','CAEE880404MNLRML04',4,'1988-04-04','2020-04-01'),
(5,'Raúl','Mora','MORR890505HNLRRA05',5,'1989-05-05','2020-05-01'),
(1,'Paty','Ríos','RIPP900606MNLRRT06',6,'1990-06-06','2020-06-01'),
(2,'Andrés','León','LEAA910707HNLRNN07',7,'1991-07-07','2020-07-01'),
(3,'Diana','Paz','PADD920808MNLRDZ08',8,'1992-08-08','2020-08-01'),
(4,'Iván','Silva','SIII930909HNLRLV09',9,'1993-09-09','2020-09-01'),
(5,'Karen','Vega','VEKK941010MNLRGR10',10,'1994-10-10','2020-10-01'),
(1,'Tomás','Gil','GITT951111HNLRLM11',11,'1995-11-11','2020-11-01'),
(2,'Nora','Reyes','RENN961212MNLRYR12',12,'1996-12-12','2020-12-01'),
(3,'Alan','Cruz','CUAA970101HNLRRL13',13,'1997-01-01','2021-01-01'),
(4,'Mónica','Peña','PEMM980202MNLRXN14',14,'1998-02-02','2021-02-01'),
(5,'Víctor','Soto','SOVV990303HNLRCT15',15,'1999-03-03','2021-03-01');

INSERT INTO worker_professional (worker_id, cedula_profesional, specialty_id, institution_id) VALUES
(1, '5432109', 1,  1),
(1,  '5432109', 5,  2),
(2,  '5432876', 1,  1),
(2,  '5432876', 3,  3),
(3,  '6789012', 2,  6),
(4,  '4321098', 4,  4),
(5,  '4123456', 1,  2),
(5,  '4123456', 4,  5),
(6,  '7654321', 5,  5),
(7,  '8765432', 8,  7),
(8,  '3456789', 1,  3),
(8,  '3456789', 6,  3),
(9,  '6543210', 2,  3),
(10, '7890123', 4,  5),
(11, '9012345', 2,  6),
(12, '2345678', 1,  1),
(13, '2345678', 7,  4),
(14, '5678901', 3,  4),
(15, '6789012', 5,  2);

INSERT INTO worker_phones (worker_id, phone, phone_type, is_primary) VALUES
(1,  '81-3001-1111', 'Celular', TRUE),
(2,  '81-3001-2222', 'Celular', TRUE),
(3,  '81-3001-3333', 'Celular', TRUE),
(4,  '81-3001-4444', 'Celular', TRUE),
(5,  '81-3001-5555', 'Celular', TRUE),
(6,  '81-3001-6666', 'Celular', TRUE),
(7,  '81-3001-7777', 'Celular', TRUE),
(8,  '81-3001-8888', 'Celular', TRUE),
(9,  '81-3001-9999', 'Celular', TRUE),
(10, '81-3002-0000', 'Celular', TRUE),
(11, '81-3002-1111', 'Celular', TRUE),
(12, '81-3002-2222', 'Celular', TRUE),
(13, '81-3002-3333', 'Celular', TRUE),
(14, '81-3002-4444', 'Celular', TRUE),
(15, '81-3002-5555', 'Celular', TRUE);

INSERT INTO worker_emails (worker_id, email, is_primary) VALUES
(1,  'jose.perez@gmail.com',    TRUE),
(2,  'lucia.santos@gmail.com',  TRUE),
(3,  'mario.luna@gmail.com',    TRUE),
(4,  'elisa.campos@gmail.com',  TRUE),
(5,  'raul.mora@gmail.com',     TRUE),
(6,  'paty.rios@gmail.com',     TRUE),
(7,  'andres.leon@gmail.com',   TRUE),
(8,  'diana.paz@gmail.com',     TRUE),
(9,  'ivan.silva@gmail.com',    TRUE),
(10, 'karen.vega@gmail.com',    TRUE),
(11, 'tomas.gil@gmail.com',     TRUE),
(12, 'nora.reyes@gmail.com',    TRUE),
(13, 'alan.cruz@gmail.com',     TRUE),
(14, 'monica.pena@gmail.com',   TRUE),
(15, 'victor.soto@gmail.com',   TRUE);

INSERT INTO worker_clinic_assignment (worker_id, clinic_id, area_id, start_date, end_date, is_active) VALUES
(1,  1, 5,  '2015-03-01', NULL, TRUE),
(2,  1, 2,  '2010-07-20', NULL, TRUE),
(3,  1, 3,  '2018-01-10', NULL, TRUE),
(4,  1, 4,  '2020-06-15', NULL, TRUE),
(5,  2, 7,  '2012-09-01', NULL, TRUE),
(6,  2, 8,  '2019-04-01', NULL, TRUE),
(7,  3, 12, '2017-11-15', NULL, TRUE),
(8,  3, 11, '2008-03-20', NULL, TRUE),
(9,  2, 9,  '2022-01-05', NULL, TRUE),
(10, 4, 13, '2016-08-01', NULL, TRUE),
(11, 4, 14, '2021-03-10', NULL, TRUE),
(12, 5, 15, '2009-11-01', NULL, TRUE),
(13, 5, 14, '2014-05-20', NULL, TRUE),
(14, 1, 3,  '2013-02-01', NULL, TRUE),
(15, 1, 2,  '2011-10-10', NULL, TRUE);

INSERT INTO worker_schedules (worker_id, clinic_id, day_of_week, entry_time, exit_time, shift_type) VALUES
(1,  1, 1, '08:00', '14:00', 'Matutino'),
(1,  1, 2, '08:00', '14:00', 'Matutino'),
(1,  1, 3, '08:00', '14:00', 'Matutino'),
(2,  1, 1, '08:00', '15:00', 'Matutino'),
(2,  1, 2, '08:00', '15:00', 'Matutino'),
(3,  1, 1, '08:00', '14:00', 'Matutino'),
(3,  1, 2, '08:00', '14:00', 'Matutino'),
(4,  1, 1, '08:00', '14:00', 'Matutino'),
(5,  2, 1, '14:00', '20:00', 'Vespertino'),
(5,  2, 2, '14:00', '20:00', 'Vespertino'),
(6,  2, 1, '14:00', '20:00', 'Vespertino'),
(7,  3, 1, '08:00', '14:00', 'Matutino'),
(7,  3, 2, '08:00', '14:00', 'Matutino'),
(8,  3, 1, '08:00', '14:00', 'Matutino'),
(9,  2, 1, '14:00', '20:00', 'Vespertino'),
(10, 4, 1, '08:00', '14:00', 'Matutino'),
(11, 4, 2, '08:00', '14:00', 'Matutino'),
(12, 5, 1, '14:00', '20:00', 'Vespertino'),
(13, 5, 2, '14:00', '20:00', 'Vespertino'),
(14, 1, 1, '08:00', '14:00', 'Matutino'),
(15, 1, 2, '08:00', '14:00', 'Matutino');

-- Ampliar horarios: lunes(1) a viernes(5) para todos los trabajadores
INSERT INTO worker_schedules (worker_id, clinic_id, day_of_week, entry_time, exit_time, shift_type)
VALUES
-- Worker 1 — Clínica 1, Matutino (ya tiene 1,2,3 → agregar 4,5)
(1,  1, 4, '08:00', '14:00', 'Matutino'),
(1,  1, 5, '08:00', '14:00', 'Matutino'),
-- Worker 2 — Clínica 1, Matutino (ya tiene 1,2 → agregar 3,4,5)
(2,  1, 3, '08:00', '15:00', 'Matutino'),
(2,  1, 4, '08:00', '15:00', 'Matutino'),
(2,  1, 5, '08:00', '15:00', 'Matutino'),
-- Worker 3 — Clínica 1, Matutino (ya tiene 1,2 → agregar 3,4,5)
(3,  1, 3, '08:00', '14:00', 'Matutino'),
(3,  1, 4, '08:00', '14:00', 'Matutino'),
(3,  1, 5, '08:00', '14:00', 'Matutino'),
-- Worker 4 — Clínica 1, Matutino (ya tiene 1 → agregar 2,3,4,5)
(4,  1, 2, '08:00', '14:00', 'Matutino'),
(4,  1, 3, '08:00', '14:00', 'Matutino'),
(4,  1, 4, '08:00', '14:00', 'Matutino'),
(4,  1, 5, '08:00', '14:00', 'Matutino'),
-- Worker 5 — Clínica 2, Vespertino (ya tiene 1,2 → agregar 3,4,5)
(5,  2, 3, '14:00', '20:00', 'Vespertino'),
(5,  2, 4, '14:00', '20:00', 'Vespertino'),
(5,  2, 5, '14:00', '20:00', 'Vespertino'),
-- Worker 6 — Clínica 2, Vespertino (ya tiene 1 → agregar 2,3,4,5)
(6,  2, 2, '14:00', '20:00', 'Vespertino'),
(6,  2, 3, '14:00', '20:00', 'Vespertino'),
(6,  2, 4, '14:00', '20:00', 'Vespertino'),
(6,  2, 5, '14:00', '20:00', 'Vespertino'),
-- Worker 7 — Clínica 3, Matutino (ya tiene 1,2 → agregar 3,4,5)
(7,  3, 3, '08:00', '14:00', 'Matutino'),
(7,  3, 4, '08:00', '14:00', 'Matutino'),
(7,  3, 5, '08:00', '14:00', 'Matutino'),
-- Worker 8 — Clínica 3, Matutino (ya tiene 1 → agregar 2,3,4,5)
(8,  3, 2, '08:00', '14:00', 'Matutino'),
(8,  3, 3, '08:00', '14:00', 'Matutino'),
(8,  3, 4, '08:00', '14:00', 'Matutino'),
(8,  3, 5, '08:00', '14:00', 'Matutino'),
-- Worker 9 — Clínica 2, Vespertino (ya tiene 1 → agregar 2,3,4,5)
(9,  2, 2, '14:00', '20:00', 'Vespertino'),
(9,  2, 3, '14:00', '20:00', 'Vespertino'),
(9,  2, 4, '14:00', '20:00', 'Vespertino'),
(9,  2, 5, '14:00', '20:00', 'Vespertino'),
-- Worker 10 — Clínica 4, Matutino (ya tiene 1 → agregar 2,3,4,5)
(10, 4, 2, '08:00', '14:00', 'Matutino'),
(10, 4, 3, '08:00', '14:00', 'Matutino'),
(10, 4, 4, '08:00', '14:00', 'Matutino'),
(10, 4, 5, '08:00', '14:00', 'Matutino'),
-- Worker 11 — Clínica 4, Matutino (ya tiene 2 → agregar 1,3,4,5)
(11, 4, 1, '08:00', '14:00', 'Matutino'),
(11, 4, 3, '08:00', '14:00', 'Matutino'),
(11, 4, 4, '08:00', '14:00', 'Matutino'),
(11, 4, 5, '08:00', '14:00', 'Matutino'),
-- Worker 12 — Clínica 5, Vespertino (ya tiene 1 → agregar 2,3,4,5)
(12, 5, 2, '14:00', '20:00', 'Vespertino'),
(12, 5, 3, '14:00', '20:00', 'Vespertino'),
(12, 5, 4, '14:00', '20:00', 'Vespertino'),
(12, 5, 5, '14:00', '20:00', 'Vespertino'),
-- Worker 13 — Clínica 5, Vespertino (ya tiene 2 → agregar 1,3,4,5)
(13, 5, 1, '14:00', '20:00', 'Vespertino'),
(13, 5, 3, '14:00', '20:00', 'Vespertino'),
(13, 5, 4, '14:00', '20:00', 'Vespertino'),
(13, 5, 5, '14:00', '20:00', 'Vespertino'),
-- Worker 14 — Clínica 1, Matutino (ya tiene 1 → agregar 2,3,4,5)
(14, 1, 2, '08:00', '14:00', 'Matutino'),
(14, 1, 3, '08:00', '14:00', 'Matutino'),
(14, 1, 4, '08:00', '14:00', 'Matutino'),
(14, 1, 5, '08:00', '14:00', 'Matutino'),
-- Worker 15 — Clínica 1, Matutino (ya tiene 2 → agregar 1,3,4,5)
(15, 1, 1, '08:00', '14:00', 'Matutino'),
(15, 1, 3, '08:00', '14:00', 'Matutino'),
(15, 1, 4, '08:00', '14:00', 'Matutino'),
(15, 1, 5, '08:00', '14:00', 'Matutino')
ON CONFLICT DO NOTHING;

-- USERS
INSERT INTO users (worker_id, username, password_hash, is_active) VALUES
(1,'jose.perez',crypt('admin123', gen_salt('bf')),TRUE),
(2,'lucia.santos',crypt('enfermero123', gen_salt('bf')),TRUE),
(3,'mario.luna',crypt('medico123', gen_salt('bf')),TRUE),
(4,'elisa.campos',crypt('recepcion123', gen_salt('bf')),TRUE),
(5,'raul.mora',crypt('almacen123', gen_salt('bf')),TRUE);

INSERT INTO guardian_accounts (guardian_id, email, password_hash, is_active, email_verified) VALUES
(1,  'carlos.garcia@gmail.com',    crypt('tutor1',  gen_salt('bf')), TRUE, TRUE),
(2,  'maria.martinez@gmail.com',   crypt('tutor2',  gen_salt('bf')), TRUE, TRUE),
(3,  'luis.lopez@gmail.com',       crypt('tutor3',  gen_salt('bf')), TRUE, TRUE);



-- MANUFACTURERS
INSERT INTO manufacturers (manufacturer_id,name, country_id, contact_email) VALUES
(1, 'Pfizer',1,'pfizer@gmail.com'),
(2, 'AstraZeneca',5,'astra@mail.com'),
(3, 'Sanofi',6,'sanofi@gmail.com'),
(4, 'GSK',5,'gsk@mail.com'),
(5, 'Bayer',4,'bayer@mail.com'),
(6, 'BioNTech',4,'bio@gmail.com'),
(7, 'Sinovac',8,'sino@mail.com'),
(8, 'Sputnik',2,'sputnik@gmail.com'),
(9, 'Abbott',2,'abbott@gmail.com'),
(10, 'Takeda',3,'takeda@mail.com');

-- VACCINE VIAS
INSERT INTO vaccine_vias (via) VALUES
('Intramuscular'),('Subcutánea'),('Oral'),('Intravenosa'),('Intradérmica');

-- VACCINES
INSERT INTO vaccines (vaccine_id, name, commercial_name, manufacturer_id, via_id, ideal_age_months, disease_prevented) VALUES
(1,  'BCG', 'BCG Birmex', 1, 1,  0,  'Tuberculosis — dosis única al nacimiento'),
(2,  'Hepatitis B', 'Engerix-B',  5, 2,  0,  'Hepatitis B — primera dosis al nacimiento'),
(3,  'Pentavalente acelular','Pentaxim', 2, 2,  2,  'DPT + Hib + Polio inactivado — 3 dosis'),
(4,  'Hepatitis B (serie)',  'Engerix-B pediátrica',5,2,  2,  'Hepatitis B — dosis 2 y 3 de la serie'),
(5,  'Rotavirus', 'RotaTeq', 3, 4,  2,  'Diarrea por Rotavirus — 3 dosis orales'),
(6,  'Neumococo conjugada',  'Prevenar 13', 4, 2,  2,  'Neumococo 13V — 3 dosis + refuerzo'),
(7,  'Influenza', 'Fluvax Pediátrica', 10,2,  6,  'Influenza estacional — anual desde 6 meses'),
(8,  'SRP', 'M-M-R II', 3, 3,  12, 'Sarampión, Rubeola, Parotiditis — 2 dosis'),
(9,  'Pentavalente refuerzo','Pentaxim refuerzo', 2, 2,  18, 'DPT + Hib + Polio — refuerzo 18 meses'),
(10, 'DPT (refuerzo)', 'Tripacel',  2, 2,  48, 'Difteria, Pertussis, Tétanos — refuerzo 4 años'),
(11, 'OPV','Polio oral',    1, 4,  60, 'Polio oral — Semanas Nacionales de Salud'),
(12, 'VPH',  'Gardasil 9', 3, 2,  132,'Virus del Papiloma Humano — 5to grado primaria');

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

INSERT INTO vaccination_scheme (scheme_id, name, issuing_body, year, is_current) VALUES
    (1, 'Cartilla Nacional de Vacunación 2024', 'SSA México', 2024, TRUE),
    (2, 'Cartilla Nacional de Vacunación 2023', 'SSA México', 2023, FALSE);

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
    --  APPOINTMENTS  (schema correcto: sin vaccine_id/scheme_dose_id)
    --  15 citas — una por paciente, vinculadas al primer registro de cada uno.
    --  Worker 3 (Médico Mario, clinic 1, area 3) y Worker 2 (Enfermera Lucía, clinic 1, area 2).
    --  Fechas distintas → no viola UNIQUE(worker_id, scheduled_at) ni UNIQUE(clinic_id, area_id, scheduled_at).
    -- ─────────────────────────────────────────────
INSERT INTO appointments
(appointment_id, patient_id, clinic_id, area_id, worker_id,
 patient_schedule_id, scheduled_at, duration_min, reason,
 appointment_status, created_by_role, created_by_worker_id)
VALUES
-- Médico Mario (worker 3) → area 3
(1,  1,  1, 3, 3, NULL, '2018-03-15 09:00', 20, 'BCG + Hep B nacimiento',       'Completada', 'Medico',    3),
(2,  2,  1, 3, 3, NULL, '2019-07-20 09:00', 20, 'BCG + Hep B nacimiento',       'Completada', 'Medico',    3),
(4,  4,  1, 3, 3, NULL, '2017-11-05 09:00', 20, 'Hep B 1ra dosis nacimiento',   'Completada', 'Medico',    3),
(6,  6,  1, 3, 3, NULL, '2018-08-18 09:00', 20, 'BCG nacimiento',               'Completada', 'Medico',    3),
(8,  8,  1, 3, 3, NULL, '2020-09-14 09:00', 20, 'BCG nacimiento',               'Completada', 'Medico',    3),
(9,  9,  1, 3, 3, NULL, '2017-12-30 09:00', 20, 'BCG + Hep B nacimiento',       'Completada', 'Medico',    3),
(11,11,  1, 3, 3, NULL, '2018-05-03 09:00', 20, 'BCG nacimiento',               'Completada', 'Medico',    3),
(13,13,  1, 3, 3, NULL, '2020-09-01 09:00', 20, 'Pentavalente 1ra dosis — 2m',  'Completada', 'Medico',    3),
(14,14,  1, 3, 3, NULL, '2017-09-27 09:00', 20, 'BCG nacimiento',               'Completada', 'Medico',    3),
-- Enfermera Lucía (worker 2) → area 2
(3,  3,  1, 2, 2, NULL, '2020-01-10 09:00', 20, 'BCG nacimiento',               'Completada', 'Enfermero', 2),
(5,  5,  1, 2, 2, NULL, '2021-06-12 09:00', 20, 'BCG nacimiento',               'Completada', 'Enfermero', 2),
(7,  7,  1, 2, 2, NULL, '2019-04-09 09:00', 20, 'Hep B 1ra dosis nacimiento',   'Completada', 'Enfermero', 2),
(10,10,  1, 2, 2, NULL, '2021-02-25 09:00', 20, 'Hep B 1ra dosis nacimiento',   'Completada', 'Enfermero', 2),
(12,12,  1, 2, 2, NULL, '2019-10-16 09:00', 20, 'BCG nacimiento',               'Completada', 'Enfermero', 2),
(15,15,  1, 2, 2, NULL, '2021-04-11 09:00', 20, 'BCG nacimiento',               'Completada', 'Enfermero', 2);

    -- ─────────────────────────────────────────────
    --  VACCINATION RECORDS (96 registros)
    --  15 registros vinculados a su appointment (first visit).
    --  El resto: appointment_id = NULL (dosis extra, sin cita previa).
    --  Paciente 9 = ESQUEMA COMPLETO hasta 24 meses.
    -- ─────────────────────────────────────────────

INSERT INTO vaccination_records
(record_id, patient_id, vaccine_id, worker_id, clinic_id, lot_id,
 scheme_dose_id, applied_date, application_site_id, appointment_id,
 patient_temp_c, had_reaction)
VALUES

-- ── Paciente 9 — Leonardo Gómez (2017-12-30) — ESQUEMA COMPLETO ──
(1,  9,1,3,1,1,  1,'2017-12-30',6, 9,  36.5,FALSE), -- BCG             ← appointment 9
(2,  9,2,3,1,2,  2,'2017-12-30',1,NULL,36.5,FALSE), -- Hep B 1ra
(3,  9,3,3,1,3,  3,'2018-02-28',1,NULL,36.5,FALSE), -- Penta 1ra
(4,  9,4,3,1,4,  4,'2018-02-28',2,NULL,36.5,FALSE), -- Hep B 2da
(5,  9,5,3,1,5,  5,'2018-02-28',5,NULL,36.6,FALSE), -- Rotavirus 1ra
(6,  9,6,3,1,6,  6,'2018-02-28',4,NULL,36.6,FALSE), -- Neumococo 1ra
(7,  9,3,3,1,3,  7,'2018-04-30',1,NULL,36.6,FALSE), -- Penta 2da
(8,  9,5,3,1,5,  8,'2018-04-30',2,NULL,36.6,FALSE), -- Rotavirus 2da
(9,  9,6,3,1,6,  9,'2018-04-30',4,NULL,36.5,FALSE), -- Neumococo 2da
(10, 9,3,2,1,3, 10,'2018-06-30',1,NULL,36.7,FALSE), -- Penta 3ra
(11, 9,4,2,1,4, 11,'2018-06-30',2,NULL,36.7,FALSE), -- Hep B 3ra
(12, 9,5,2,1,5, 12,'2018-06-30',5,NULL,36.7,FALSE), -- Rotavirus 3ra
(13, 9,7,2,1,7, 13,'2018-06-30',3,NULL,36.5,FALSE), -- Influenza 1ra
(14, 9,7,2,1,7, 14,'2018-07-30',3,NULL,36.5,FALSE), -- Influenza 2da
(15, 9,8,3,1,8, 15,'2018-12-30',3,NULL,36.8,FALSE), -- SRP 1ra
(16, 9,6,3,1,6, 16,'2018-12-30',1,NULL,36.8,FALSE), -- Neumococo 3ra
(17, 9,9,3,2,9, 17,'2019-06-30',1,NULL,36.6,FALSE), -- Penta refuerzo
(18, 9,7,3,1,7, 18,'2019-12-30',3,NULL,36.5,FALSE), -- Influenza anual ← ESQUEMA COMPLETO a 24m

-- ── Paciente 1 — Mateo García (2018-03-15, ~8 años) ──
(19, 1,1,3,1,1,  1,'2018-03-15',6, 1, 36.5,FALSE), -- BCG             ← appointment 1
(20, 1,2,3,1,2,  2,'2018-03-15',1,NULL,36.5,FALSE), -- Hep B 1ra
(21, 1,6,3,1,6,  6,'2018-05-15',4,NULL,36.6,FALSE), -- Neumococo 1ra (2m)
(22, 1,8,3,1,8, 15,'2019-03-15',3,NULL,36.7,FALSE), -- SRP 1ra (12m)
(23, 1,9,3,2,9, 17,'2019-09-15',1,NULL,36.5,FALSE), -- Penta refuerzo (18m)
(24, 1,10,3,2,10,20,'2022-03-15',2,NULL,36.6,FALSE), -- DPT refuerzo (48m)
(25, 1,8,3,1,8, 24,'2024-03-15',3,NULL,36.6,FALSE), -- SRP refuerzo (72m)

-- ── Paciente 2 — Sofía Martínez (2019-07-20, ~6 años 10m) ──
(26, 2,1,3,1,1,  1,'2019-07-20',6, 2, 36.5,FALSE), -- BCG             ← appointment 2
(27, 2,2,3,1,2,  2,'2019-07-20',1,NULL,36.5,FALSE), -- Hep B 1ra
(28, 2,6,3,1,6,  6,'2019-09-20',4,NULL,36.6,FALSE), -- Neumococo 1ra (2m)
(29, 2,8,3,1,8, 15,'2020-07-20',3,NULL,36.7,FALSE), -- SRP 1ra (12m)
(30, 2,9,3,2,9, 17,'2021-01-20',1,NULL,36.5,FALSE), -- Penta refuerzo (18m)
(31, 2,8,3,1,8, 24,'2025-07-20',3,NULL,36.6,FALSE), -- SRP refuerzo (72m)

-- ── Paciente 3 — Diego López (2020-01-10, prematuro) ──
(32, 3,1,2,1,1,  1,'2020-01-10',6, 3, 36.5,FALSE), -- BCG             ← appointment 3
(33, 3,3,2,1,3,  3,'2020-03-10',1,NULL,36.6,FALSE), -- Penta 1ra (2m)
(34, 3,6,2,1,6,  6,'2020-03-10',4,NULL,36.6,FALSE), -- Neumococo 1ra (2m)
(35, 3,8,2,1,8, 15,'2021-01-10',3,NULL,36.7,FALSE), -- SRP 1ra (12m)
(36, 3,10,2,2,10,20,'2024-01-10',1,NULL,36.5,FALSE), -- DPT refuerzo (48m)

-- ── Paciente 4 — Valentina Hernández (2017-11-05, ~8 años 6m) ──
(37, 4,2,3,1,2,  2,'2017-11-05',1, 4, 36.5,FALSE), -- Hep B 1ra      ← appointment 4
(38, 4,4,3,1,4,  4,'2018-01-05',2,NULL,36.6,FALSE), -- Hep B 2da (2m)
(39, 4,8,3,1,8, 15,'2018-11-05',3,NULL,36.7,FALSE), -- SRP 1ra (12m)
(40, 4,9,3,2,9, 17,'2019-05-05',1,NULL,36.5,FALSE), -- Penta refuerzo (18m)
(41, 4,8,3,1,8, 24,'2023-11-05',3,NULL,36.6,FALSE), -- SRP refuerzo (72m)

-- ── Paciente 5 — Lucas Ramírez (2021-06-12, ~4 años 11m) ──
(42, 5,1,2,1,1,  1,'2021-06-12',6, 5, 36.5,FALSE), -- BCG             ← appointment 5
(43, 5,3,2,1,3,  3,'2021-08-12',1,NULL,36.6,FALSE), -- Penta 1ra (2m)
(44, 5,5,2,1,5,  5,'2021-08-12',5,NULL,36.6,FALSE), -- Rotavirus 1ra (2m)
(45, 5,3,2,1,3,  7,'2021-10-12',1,NULL,36.5,FALSE), -- Penta 2da (4m)
(46, 5,8,2,1,8, 15,'2022-06-12',3,NULL,36.7,FALSE), -- SRP 1ra (12m)
(47, 5,9,2,2,9, 17,'2022-12-12',1,NULL,36.5,FALSE), -- Penta refuerzo (18m)
(48, 5,10,2,2,10,20,'2025-06-12',2,NULL,36.6,FALSE), -- DPT refuerzo (48m)

-- ── Paciente 6 — Emma Torres (2018-08-18, ~7 años 9m) ──
(49, 6,1,3,1,1,  1,'2018-08-18',6, 6, 36.5,FALSE), -- BCG             ← appointment 6
(50, 6,6,3,1,6,  6,'2018-10-18',4,NULL,36.6,FALSE), -- Neumococo 1ra (2m)
(51, 6,8,3,1,8, 15,'2019-08-18',3,NULL,36.7,FALSE), -- SRP 1ra (12m)
(52, 6,6,3,1,6, 16,'2019-08-18',1,NULL,36.7,FALSE), -- Neumococo 3ra (12m)
(53, 6,10,3,2,10,20,'2022-08-18',2,NULL,36.5,FALSE), -- DPT refuerzo (48m)
(54, 6,8,3,1,8, 24,'2024-08-18',3,NULL,36.6,FALSE), -- SRP refuerzo (72m)

-- ── Paciente 7 — Sebastián Flores (2019-04-09, ~7 años) ──
(55, 7,2,2,1,2,  2,'2019-04-09',1, 7, 36.5,FALSE), -- Hep B 1ra      ← appointment 7
(56, 7,3,2,1,3,  3,'2019-06-09',2,NULL,36.6,FALSE), -- Penta 1ra (2m)
(57, 7,8,2,1,8, 15,'2020-04-09',3,NULL,36.7,FALSE), -- SRP 1ra (12m)
(58, 7,9,2,2,9, 17,'2020-10-09',1,NULL,36.5,FALSE), -- Penta refuerzo (18m)
(59, 7,8,2,1,8, 24,'2025-04-09',4,NULL,36.6,FALSE), -- SRP refuerzo (72m)

-- ── Paciente 8 — Camila Rivera (2020-09-14, prematura) ──
(60, 8,1,3,1,1,  1,'2020-09-14',6, 8, 36.5,FALSE), -- BCG             ← appointment 8
(61, 8,6,3,1,6,  6,'2020-11-14',4,NULL,36.6,FALSE), -- Neumococo 1ra (2m)
(62, 8,8,3,1,8, 15,'2021-09-14',3,NULL,36.7,FALSE), -- SRP 1ra (12m)
(63, 8,9,3,2,9, 17,'2022-03-14',1,NULL,36.5,FALSE), -- Penta refuerzo (18m)
(64, 8,10,3,2,10,20,'2024-09-14',2,NULL,36.6,FALSE), -- DPT refuerzo (48m)

-- ── Paciente 10 — Renata Díaz (2021-02-25, ~5 años 2m) ──
(65,10,2,2,1,2,  2,'2021-02-25',1,10, 36.5,FALSE), -- Hep B 1ra      ← appointment 10
(66,10,5,2,1,5,  5,'2021-04-25',5,NULL,36.6,FALSE), -- Rotavirus 1ra (2m)
(67,10,8,2,1,8, 15,'2022-02-25',3,NULL,36.7,FALSE), -- SRP 1ra (12m)
(68,10,9,2,2,9, 17,'2022-08-25',1,NULL,36.5,FALSE), -- Penta refuerzo (18m)
(69,10,10,2,2,10,20,'2025-02-25',2,NULL,36.6,FALSE), -- DPT refuerzo (48m)

-- ── Paciente 11 — Emiliano Castro (2018-05-03, ~8 años) ──
(70,11,1,3,1,1,  1,'2018-05-03',6,11, 36.5,FALSE), -- BCG             ← appointment 11
(71,11,3,3,1,3,  3,'2018-07-03',1,NULL,36.6,FALSE), -- Penta 1ra (2m)
(72,11,7,3,1,7, 13,'2018-11-03',3,NULL,36.5,FALSE), -- Influenza 1ra (6m)
(73,11,8,3,1,8, 15,'2019-05-03',3,NULL,36.7,FALSE), -- SRP 1ra (12m)
(74,11,10,3,2,10,20,'2022-05-03',2,NULL,36.6,FALSE), -- DPT refuerzo (48m)
(75,11,8,3,1,8, 24,'2024-05-03',3,NULL,36.6,FALSE), -- SRP refuerzo (72m)

-- ── Paciente 12 — Regina Ortiz (2019-10-16, ~6 años 7m) ──
(76,12,1,2,1,1,  1,'2019-10-16',6,12, 36.5,FALSE), -- BCG             ← appointment 12
(77,12,6,2,1,6,  6,'2019-12-16',4,NULL,36.6,FALSE), -- Neumococo 1ra (2m)
(78,12,8,2,1,8, 15,'2020-10-16',3,NULL,36.7,FALSE), -- SRP 1ra (12m)
(79,12,6,2,1,6, 16,'2020-10-16',1,NULL,36.7,FALSE), -- Neumococo 3ra (12m)
(80,12,8,2,1,8, 24,'2025-10-16',3,NULL,36.6,FALSE), -- SRP refuerzo (72m)

-- ── Paciente 13 — Daniel Morales (2020-07-01, prematuro) ──
(81,13,3,3,1,3,  3,'2020-09-01',1,13, 36.6,FALSE), -- Penta 1ra (2m) ← appointment 13
(82,13,6,3,1,6,  6,'2020-09-01',4,NULL,36.6,FALSE), -- Neumococo 1ra (2m)
(83,13,8,3,1,8, 15,'2021-07-01',3,NULL,36.7,FALSE), -- SRP 1ra (12m)
(84,13,9,3,2,9, 17,'2022-01-01',1,NULL,36.5,FALSE), -- Penta refuerzo (18m)
(85,13,10,3,2,10,20,'2024-07-01',2,NULL,36.6,FALSE), -- DPT refuerzo (48m)

-- ── Paciente 14 — Victoria Ruiz (2017-09-27, ~8 años 7m) ──
(86,14,1,3,1,1,  1,'2017-09-27',6,14, 36.5,FALSE), -- BCG             ← appointment 14
(87,14,8,3,1,8, 15,'2018-09-27',3,NULL,36.7,FALSE), -- SRP 1ra (12m)
(88,14,9,3,2,9, 17,'2019-03-27',1,NULL,36.5,FALSE), -- Penta refuerzo (18m)
(89,14,10,3,2,10,20,'2021-09-27',2,NULL,36.6,FALSE), -- DPT refuerzo (48m)
(90,14,8,3,1,8, 24,'2023-09-27',3,NULL,36.6,FALSE), -- SRP refuerzo (72m)

-- ── Paciente 15 — Ángel Navarro (2021-04-11, ~5 años 1m) ──
(91,15,1,2,1,1,  1,'2021-04-11',6,15, 36.5,FALSE), -- BCG             ← appointment 15
(92,15,5,2,1,5,  5,'2021-06-11',5,NULL,36.6,FALSE), -- Rotavirus 1ra (2m)
(93,15,6,2,1,6,  6,'2021-06-11',4,NULL,36.6,FALSE), -- Neumococo 1ra (2m)
(94,15,8,2,1,8, 15,'2022-04-11',3,NULL,36.7,FALSE), -- SRP 1ra (12m)
(95,15,9,2,2,9, 17,'2022-10-11',1,NULL,36.5,FALSE), -- Penta refuerzo (18m)
(96,15,10,2,2,10,20,'2025-04-11',2,NULL,36.6,FALSE); -- DPT refuerzo (48m)

-- Reacciones vinculadas a registros reales del paciente 9 (esquema completo)
-- y a registros de otros pacientes. Todos los reported_by son médicos/enfermeros válidos.
INSERT INTO post_vaccine_reactions (reaction_id, record_id, reported_by, symptom, severity, onset_hours, treatment, notified_authority) VALUES
    (1,  13, 3, 'Eritema leve en sitio de aplicación',   'Leve',     4,  'Compresas frías',           FALSE), -- P9 Influenza 1ra
    (2,  13, 3, 'Llanto persistente 2h post-influenza',  'Leve',     2,  'Observación — cedió solo',  FALSE), -- P9 Influenza 1ra
    (3,  3,  3, 'Fiebre 37.8°C transitoria',             'Leve',     12, 'Paracetamol 60mg/kg oral',  FALSE), -- P9 Penta 1ra
    (4,  8,  3, 'Endurecimiento en zona de punción',     'Leve',     6,  'Compresas tibias',          FALSE), -- P9 Rotavirus 2da
    (5,  15, 3, 'Fiebre 38.0°C post-SRP',                'Leve',     12, 'Paracetamol 150mg oral',    FALSE), -- P9 SRP 1ra
    (6,  12, 3, 'Eritema leve post-rotavirus',           'Leve',     24, 'Observación',               FALSE), -- P9 Rotavirus 3ra
    (7,  14, 3, 'Dolor local en sitio de inyección',     'Leve',     2,  'Compresas frías',           FALSE), -- P9 Influenza 2da
    (8,  22, 3, 'Fiebre 38.1°C post-SRP',                'Leve',     12, 'Paracetamol + hidratación', FALSE), -- P1 SRP 1ra
    (9,  4,  3, 'Fiebre 38.2°C post-HepB',              'Moderada', 24, 'Paracetamol + hidratación', FALSE), -- P9 Hep B 2da
    (10, 5,  3, 'Malestar gástrico leve post-rotavirus', 'Leve',     6,  'Hidratación oral',          FALSE); -- P9 Rotavirus 1ra

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

-- PATIENT VACCINE SCHEDULE
-- Genera una fila por cada paciente×dosis; el status se deriva de vaccination_records
INSERT INTO patient_vaccine_schedule (patient_id, scheme_dose_id, due_date, status)
SELECT
    p.patient_id,
    sd.dose_id,
    (p.birth_date + (sd.ideal_age_months || ' months')::INTERVAL)::DATE AS due_date,
    CASE
        WHEN EXISTS (
            SELECT 1 FROM vaccination_records vr
            WHERE vr.patient_id = p.patient_id AND vr.scheme_dose_id = sd.dose_id
        ) THEN 'Aplicada'
        WHEN (p.birth_date + (sd.ideal_age_months || ' months')::INTERVAL)::DATE < CURRENT_DATE
        THEN 'Atrasada'
        ELSE 'Pendiente'
    END
FROM patients p
CROSS JOIN scheme_doses sd
WHERE p.is_active != FALSE
ON CONFLICT DO NOTHING;

-- CITAS PROGRAMADAS (hoy y próximos días para demostración del dashboard)
-- Worker 3 (Mario, área 3) y Worker 2 (Lucía, área 2) — timestamps distintos para no violar UNIQUE
INSERT INTO appointments
(appointment_id, patient_id, clinic_id, area_id, worker_id,
 patient_schedule_id, scheduled_at, duration_min, reason,
 appointment_status, created_by_role, created_by_worker_id)
VALUES
(16, 1,  1, 3, 3, NULL, CURRENT_DATE + INTERVAL '10 hours',          20, 'Influenza anual',          'Programada', 'Administrador', 1),
(17, 5,  1, 2, 2, NULL, CURRENT_DATE + INTERVAL '10 hours 30 minutes',20, 'Pentavalente 2da dosis',  'Programada', 'Administrador', 1),
(18, 10, 1, 3, 3, NULL, CURRENT_DATE + INTERVAL '11 hours',          20, 'Neumococo 1ra dosis',      'Confirmada', 'Administrador', 1),
(19, 3,  1, 2, 2, NULL, CURRENT_DATE + INTERVAL '11 hours 30 minutes',20, 'Rotavirus 3ra dosis',     'Programada', 'Administrador', 1),
(20, 6,  1, 3, 3, NULL, CURRENT_DATE + INTERVAL '12 hours',          20, 'SRP 1ra dosis',            'Programada', 'Administrador', 1),
(21, 11, 1, 3, 3, NULL, CURRENT_DATE + INTERVAL '1 day 9 hours',     20, 'Pentavalente 3ra dosis',   'Programada', 'Administrador', 1),
(22, 7,  1, 2, 2, NULL, CURRENT_DATE + INTERVAL '1 day 10 hours',    20, 'Hep B 2da dosis',          'Confirmada', 'Administrador', 1),
(23, 14, 1, 3, 3, NULL, CURRENT_DATE + INTERVAL '2 days 9 hours',    20, 'SRP refuerzo 6 años',      'Programada', 'Administrador', 1);

-- Corregir secuencias tras inserts con IDs explícitos
SELECT SETVAL('appointments_appointment_id_seq',
              (SELECT MAX(appointment_id) FROM appointments));
SELECT SETVAL('vaccination_records_record_id_seq',
              (SELECT MAX(record_id) FROM vaccination_records));

-- ALERTAS: generar alertas de dosis atrasadas y próximas (requiere patient_vaccine_schedule)
BEGIN;
CALL sp_generate_alerts('cur_seed_alerts');
COMMIT;

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

    INSERT INTO audit_log (audit_id, table_name, record_id, action, worker_id, changed_at, ip_address) VALUES
    (1,  'vaccination_records',  1,  'INSERT', 3, '2017-12-30 09:05', '192.168.1.45'),
    (2,  'vaccination_records',  2,  'INSERT', 3, '2017-12-30 09:06', '192.168.1.45'),
    (3,  'patients',             1,  'UPDATE', 1, '2024-03-15 10:20', '192.168.1.12'),
    (4,  'vaccination_records',  19, 'INSERT', 3, '2018-03-15 09:05', '192.168.1.45'),
    (5,  'vaccine_lots',         1,  'UPDATE', 4, '2025-01-05 09:06', '192.168.1.50'),
    (6,  'appointments',         1,  'INSERT', 1, '2018-03-14 08:00', '192.168.1.12'),
    (7,  'nfc_cards',            1,  'INSERT', 3, '2024-01-15 09:15', '192.168.1.45'),
    (8,  'nfc_cards',            2,  'INSERT', 3, '2024-01-15 09:20', '192.168.1.45'),
    (9,  'guardians',            1,  'UPDATE', 1, '2024-05-20 11:30', '192.168.1.12'),
    (10, 'vaccination_records',  70, 'INSERT', 3, '2018-05-03 09:30', '192.168.2.10'),
    (11, 'post_vaccine_reactions',1, 'INSERT', 3, '2018-06-30 09:45', '192.168.1.45'),
    (12, 'vaccine_lots',         5,  'UPDATE', 4, '2025-01-10 08:00', '192.168.1.55');


-- (requiere que existan vacunas y clínicas)

INSERT INTO vaccine_lots
    (vaccine_id, clinic_id, lot_number, quantity_received, quantity_available,
     expiration_date, received_date, lot_status)
SELECT
    (SELECT vaccine_id FROM vaccines ORDER BY vaccine_id LIMIT 1 OFFSET 0),
    (SELECT clinic_id  FROM clinics  WHERE is_active = TRUE ORDER BY clinic_id LIMIT 1 OFFSET 0),
    'LOTE-HB-2024-001', 100, 72,
    CURRENT_DATE + INTERVAL '180 days', CURRENT_DATE - INTERVAL '30 days',
    'Disponible'
WHERE NOT EXISTS (SELECT 1 FROM vaccine_lots WHERE lot_number = 'LOTE-HB-2024-001');

INSERT INTO vaccine_lots
    (vaccine_id, clinic_id, lot_number, quantity_received, quantity_available,
     expiration_date, received_date, lot_status)
SELECT
    (SELECT vaccine_id FROM vaccines ORDER BY vaccine_id LIMIT 1 OFFSET 1),
    (SELECT clinic_id  FROM clinics  WHERE is_active = TRUE ORDER BY clinic_id LIMIT 1 OFFSET 0),
    'LOTE-BCG-2024-002', 50, 8,
    CURRENT_DATE + INTERVAL '25 days', CURRENT_DATE - INTERVAL '60 days',
    'Disponible'
WHERE NOT EXISTS (SELECT 1 FROM vaccine_lots WHERE lot_number = 'LOTE-BCG-2024-002');

INSERT INTO vaccine_lots
    (vaccine_id, clinic_id, lot_number, quantity_received, quantity_available,
     expiration_date, received_date, lot_status)
SELECT
    (SELECT vaccine_id FROM vaccines ORDER BY vaccine_id LIMIT 1 OFFSET 2),
    (SELECT clinic_id  FROM clinics  WHERE is_active = TRUE ORDER BY clinic_id LIMIT 1 OFFSET 1),
    'LOTE-NEU-2024-003', 80, 5,
    CURRENT_DATE + INTERVAL '90 days', CURRENT_DATE - INTERVAL '45 days',
    'Disponible'
WHERE NOT EXISTS (SELECT 1 FROM vaccine_lots WHERE lot_number = 'LOTE-NEU-2024-003');

INSERT INTO vaccine_lots
    (vaccine_id, clinic_id, lot_number, quantity_received, quantity_available,
     expiration_date, received_date, lot_status)
SELECT
    (SELECT vaccine_id FROM vaccines ORDER BY vaccine_id LIMIT 1 OFFSET 0),
    (SELECT clinic_id  FROM clinics  WHERE is_active = TRUE ORDER BY clinic_id LIMIT 1 OFFSET 1),
    'LOTE-HB-2024-004', 60, 0,
    CURRENT_DATE + INTERVAL '200 days', CURRENT_DATE - INTERVAL '20 days',
    'Agotado'
WHERE NOT EXISTS (SELECT 1 FROM vaccine_lots WHERE lot_number = 'LOTE-HB-2024-004');

INSERT INTO vaccine_lots
    (vaccine_id, clinic_id, lot_number, quantity_received, quantity_available,
     expiration_date, received_date, lot_status)
SELECT
    (SELECT vaccine_id FROM vaccines ORDER BY vaccine_id LIMIT 1 OFFSET 3),
    (SELECT clinic_id  FROM clinics  WHERE is_active = TRUE ORDER BY clinic_id LIMIT 1 OFFSET 0),
    'LOTE-VPH-2023-005', 40, 40,
    CURRENT_DATE - INTERVAL '10 days', CURRENT_DATE - INTERVAL '120 days',
    'Caducado'
WHERE NOT EXISTS (SELECT 1 FROM vaccine_lots WHERE lot_number = 'LOTE-VPH-2023-005');

-- ── 2. MOVIMIENTOS DE INVENTARIO ─────────────────────────────
-- (requiere que inventory_movements exista — creada en Fase 1)

INSERT INTO inventory_movements
    (lot_id, vaccine_id, clinic_id, worker_id,
     movement_type, quantity, quantity_before, quantity_after,
     reference_type, reason)
SELECT
    vl.lot_id, vl.vaccine_id, vl.clinic_id,
    (SELECT worker_id FROM workers WHERE is_active = TRUE ORDER BY worker_id LIMIT 1),
    'Entrada', 100, 0, 100,
    'manual', 'Recepción inicial de lote'
FROM vaccine_lots vl WHERE vl.lot_number = 'LOTE-HB-2024-001';

INSERT INTO inventory_movements
    (lot_id, vaccine_id, clinic_id, worker_id,
     movement_type, quantity, quantity_before, quantity_after,
     reference_type, reason, created_at)
SELECT
    vl.lot_id, vl.vaccine_id, vl.clinic_id,
    (SELECT worker_id FROM workers WHERE is_active = TRUE ORDER BY worker_id LIMIT 1),
    'Salida_Aplicacion', 10, 100, 90,
    'manual', 'Aplicaciones jornada vacunación',
    NOW() - INTERVAL '20 days'
FROM vaccine_lots vl WHERE vl.lot_number = 'LOTE-HB-2024-001';

INSERT INTO inventory_movements
    (lot_id, vaccine_id, clinic_id, worker_id,
     movement_type, quantity, quantity_before, quantity_after,
     reference_type, reason, created_at)
SELECT
    vl.lot_id, vl.vaccine_id, vl.clinic_id,
    (SELECT worker_id FROM workers WHERE is_active = TRUE ORDER BY worker_id LIMIT 1),
    'Salida_Aplicacion', 12, 90, 78,
    'manual', 'Aplicaciones semana 2',
    NOW() - INTERVAL '13 days'
FROM vaccine_lots vl WHERE vl.lot_number = 'LOTE-HB-2024-001';

INSERT INTO inventory_movements
    (lot_id, vaccine_id, clinic_id, worker_id,
     movement_type, quantity, quantity_before, quantity_after,
     reference_type, reason, created_at)
SELECT
    vl.lot_id, vl.vaccine_id, vl.clinic_id,
    (SELECT worker_id FROM workers WHERE is_active = TRUE ORDER BY worker_id LIMIT 1),
    'Salida_Merma', 3, 78, 75,
    'manual', 'Frascos dañados en refrigeración',
    NOW() - INTERVAL '7 days'
FROM vaccine_lots vl WHERE vl.lot_number = 'LOTE-HB-2024-001';

INSERT INTO inventory_movements
    (lot_id, vaccine_id, clinic_id, worker_id,
     movement_type, quantity, quantity_before, quantity_after,
     reference_type, reason, created_at)
SELECT
    vl.lot_id, vl.vaccine_id, vl.clinic_id,
    (SELECT worker_id FROM workers WHERE is_active = TRUE ORDER BY worker_id LIMIT 1),
    'Ajuste_Positivo', 3, 69, 72,
    'manual', 'Corrección de conteo físico',
    NOW() - INTERVAL '3 days'
FROM vaccine_lots vl WHERE vl.lot_number = 'LOTE-HB-2024-001';

INSERT INTO inventory_movements
    (lot_id, vaccine_id, clinic_id, worker_id,
     movement_type, quantity, quantity_before, quantity_after,
     reference_type, reason, created_at)
SELECT
    vl.lot_id, vl.vaccine_id, vl.clinic_id,
    (SELECT worker_id FROM workers WHERE is_active = TRUE ORDER BY worker_id LIMIT 1),
    'Entrada', 50, 0, 50,
    'manual', 'Recepción inicial de lote BCG',
    NOW() - INTERVAL '60 days'
FROM vaccine_lots vl WHERE vl.lot_number = 'LOTE-BCG-2024-002';

INSERT INTO inventory_movements
    (lot_id, vaccine_id, clinic_id, worker_id,
     movement_type, quantity, quantity_before, quantity_after,
     reference_type, reason, created_at)
SELECT
    vl.lot_id, vl.vaccine_id, vl.clinic_id,
    (SELECT worker_id FROM workers WHERE is_active = TRUE ORDER BY worker_id LIMIT 1),
    'Salida_Aplicacion', 42, 50, 8,
    'manual', 'Aplicaciones acumuladas',
    NOW() - INTERVAL '5 days'
FROM vaccine_lots vl WHERE vl.lot_number = 'LOTE-BCG-2024-002';

INSERT INTO inventory_movements
    (lot_id, vaccine_id, clinic_id, worker_id,
     movement_type, quantity, quantity_before, quantity_after,
     reference_type, reason, created_at)
SELECT
    vl.lot_id, vl.vaccine_id, vl.clinic_id,
    (SELECT worker_id FROM workers WHERE is_active = TRUE ORDER BY worker_id LIMIT 1),
    'Salida_Caducidad', 40, 40, 0,
    'manual', 'Retiro de lote vencido por control de calidad',
    NOW() - INTERVAL '9 days'
FROM vaccine_lots vl WHERE vl.lot_number = 'LOTE-VPH-2023-005';

-- ── 3. TRANSFERENCIAS ────────────────────────────────────────
-- (requiere ≥ 2 clínicas activas)

INSERT INTO inventory_transfers
    (lot_id, vaccine_id, from_clinic_id, to_clinic_id,
     quantity, transfer_status, requested_by, reason, requested_at)
SELECT
    vl.lot_id, vl.vaccine_id,
    (SELECT clinic_id FROM clinics WHERE is_active = TRUE ORDER BY clinic_id LIMIT 1 OFFSET 0),
    (SELECT clinic_id FROM clinics WHERE is_active = TRUE ORDER BY clinic_id LIMIT 1 OFFSET 1),
    20, 'Pendiente',
    (SELECT worker_id FROM workers WHERE is_active = TRUE ORDER BY worker_id LIMIT 1),
    'Redistribución por exceso de stock en clínica Norte',
    NOW() - INTERVAL '2 days'
FROM vaccine_lots vl WHERE vl.lot_number = 'LOTE-HB-2024-001';

INSERT INTO inventory_transfers
    (lot_id, vaccine_id, from_clinic_id, to_clinic_id,
     quantity, transfer_status, requested_by, approved_by,
     reason, notes, requested_at, resolved_at)
SELECT
    vl.lot_id, vl.vaccine_id,
    (SELECT clinic_id FROM clinics WHERE is_active = TRUE ORDER BY clinic_id LIMIT 1 OFFSET 0),
    (SELECT clinic_id FROM clinics WHERE is_active = TRUE ORDER BY clinic_id LIMIT 1 OFFSET 1),
    15, 'Recibido',
    (SELECT worker_id FROM workers WHERE is_active = TRUE ORDER BY worker_id LIMIT 1),
    (SELECT worker_id FROM workers WHERE is_active = TRUE ORDER BY worker_id LIMIT 1),
    'Cobertura campaña vacunación clínica Sur',
    'Recibido en buen estado, cadena de frío conservada',
    NOW() - INTERVAL '15 days',
    NOW() - INTERVAL '13 days'
FROM vaccine_lots vl WHERE vl.lot_number = 'LOTE-NEU-2024-003';

INSERT INTO inventory_transfers
    (lot_id, vaccine_id, from_clinic_id, to_clinic_id,
     quantity, transfer_status, requested_by, approved_by,
     reason, notes, requested_at, resolved_at)
SELECT
    vl.lot_id, vl.vaccine_id,
    (SELECT clinic_id FROM clinics WHERE is_active = TRUE ORDER BY clinic_id LIMIT 1 OFFSET 1),
    (SELECT clinic_id FROM clinics WHERE is_active = TRUE ORDER BY clinic_id LIMIT 1 OFFSET 0),
    10, 'Rechazado',
    (SELECT worker_id FROM workers WHERE is_active = TRUE ORDER BY worker_id LIMIT 1),
    (SELECT worker_id FROM workers WHERE is_active = TRUE ORDER BY worker_id LIMIT 1),
    'Préstamo temporal por campaña',
    'Stock insuficiente en clínica origen para cubrir la solicitud',
    NOW() - INTERVAL '8 days',
    NOW() - INTERVAL '7 days'
FROM vaccine_lots vl WHERE vl.lot_number = 'LOTE-BCG-2024-002';

INSERT INTO inventory_transfers
    (lot_id, vaccine_id, from_clinic_id, to_clinic_id,
     quantity, transfer_status, requested_by,
     reason, requested_at, resolved_at)
SELECT
    vl.lot_id, vl.vaccine_id,
    (SELECT clinic_id FROM clinics WHERE is_active = TRUE ORDER BY clinic_id LIMIT 1 OFFSET 0),
    (SELECT clinic_id FROM clinics WHERE is_active = TRUE ORDER BY clinic_id LIMIT 1 OFFSET 1),
    5, 'Cancelado',
    (SELECT worker_id FROM workers WHERE is_active = TRUE ORDER BY worker_id LIMIT 1),
    'Solicitud por error de sistema',
    NOW() - INTERVAL '20 days',
    NOW() - INTERVAL '19 days'
FROM vaccine_lots vl WHERE vl.lot_number = 'LOTE-HB-2024-001';

-- Sincronizar secuencias SERIAL después de inserts con IDs explícitos
SELECT setval(pg_get_serial_sequence('neighborhoods',   'neighborhood_id'),   MAX(neighborhood_id))   FROM neighborhoods;
SELECT setval(pg_get_serial_sequence('addresses',       'address_id'),        MAX(address_id))        FROM addresses;
SELECT setval(pg_get_serial_sequence('clinics',         'clinic_id'),         MAX(clinic_id))         FROM clinics;
SELECT setval(pg_get_serial_sequence('equipment_catalog','equipment_id'),     MAX(equipment_id))      FROM equipment_catalog;
SELECT setval(pg_get_serial_sequence('area_equipment',  'area_equipment_id'), MAX(area_equipment_id)) FROM area_equipment;
SELECT setval(pg_get_serial_sequence('patient_allergies','patient_allergy_id'),MAX(patient_allergy_id))FROM patient_allergies;
SELECT setval(pg_get_serial_sequence('guardian_emails', 'email_id'),          MAX(email_id))          FROM guardian_emails;
SELECT setval(pg_get_serial_sequence('manufacturers',   'manufacturer_id'),   MAX(manufacturer_id))   FROM manufacturers;
SELECT setval(pg_get_serial_sequence('vaccines',        'vaccine_id'),        MAX(vaccine_id))        FROM vaccines;
SELECT setval(pg_get_serial_sequence('vaccine_lots',    'lot_id'),            MAX(lot_id))            FROM vaccine_lots;
SELECT setval(pg_get_serial_sequence('vaccination_scheme','scheme_id'),       MAX(scheme_id))         FROM vaccination_scheme;
SELECT setval(pg_get_serial_sequence('scheme_doses',    'dose_id'),           MAX(dose_id))           FROM scheme_doses;
SELECT setval(pg_get_serial_sequence('application_sites','application_site_id'),MAX(application_site_id)) FROM application_sites;
SELECT setval(pg_get_serial_sequence('appointments',    'appointment_id'),    MAX(appointment_id))    FROM appointments;
SELECT setval(pg_get_serial_sequence('vaccination_records','record_id'),      MAX(record_id))         FROM vaccination_records;
SELECT setval(pg_get_serial_sequence('post_vaccine_reactions','reaction_id'), MAX(reaction_id))       FROM post_vaccine_reactions;
SELECT setval(pg_get_serial_sequence('nfc_cards',       'nfc_card_id'),       MAX(nfc_card_id))       FROM nfc_cards;
SELECT setval(pg_get_serial_sequence('nfc_scan_events', 'scan_event_id'),     MAX(scan_event_id))     FROM nfc_scan_events;
SELECT setval(pg_get_serial_sequence('supply_catalog',  'supply_id'),         MAX(supply_id))         FROM supply_catalog;
SELECT setval(pg_get_serial_sequence('clinic_inventory','inventory_id'),      MAX(inventory_id))      FROM clinic_inventory;
SELECT setval(pg_get_serial_sequence('audit_log', 'audit_id'), COALESCE(MAX(audit_id), 1)) FROM audit_log;