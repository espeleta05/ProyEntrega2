-- COUNTRIES
INSERT INTO countries (name, iso_code) VALUES
('México','MX');

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
(10,'Querétaro'),
(11,'León'),
(12,'Culiacán'),
(13,'Durango'),
(14,'Veracruz'),
(15,'Oaxaca de Juárez');

-- NEIGHBORHOODS
INSERT INTO neighborhoods (municipality_id, name, zip_code) VALUES
(1,'Centro','64000'),
(2,'Americana','44160'),
(3,'Del Valle','03100'),
(4,'República','25280'),
(5,'Vista Hermosa','88710'),
(6,'Centro','83000'),
(7,'Panamericana','31210'),
(8,'Montecristo','97133'),
(9,'La Paz','72160'),
(10,'Juriquilla','76230'),
(11,'Obregón','37320'),
(12,'Tres Ríos','80020'),
(13,'Zona Centro','34000'),
(14,'Costa Verde','94294'),
(15,'Reforma','68050');

-- ADDRESSES
INSERT INTO addresses (neighborhood_id, street, ext_number, cross_street_1, latitude, longitude) VALUES
(1,'Av. Juárez','101','Padre Mier',25.6866,-100.3161),
(2,'Av. Vallarta','202','Chapultepec',20.6736,-103.3440),
(3,'Insurgentes Sur','303','Félix Cuevas',19.3889,-99.1680),
(4,'Venustiano Carranza','404','Allende',25.4267,-100.9950),
(5,'Hidalgo','505','Juárez',26.0806,-98.2883),
(6,'Morelos','606','Rosales',29.0729,-110.9559),
(7,'Tecnológico','707','Homero',28.6353,-106.0889),
(8,'Paseo Montejo','808','Colón',20.9674,-89.5926),
(9,'Juárez','909','5 de Mayo',19.0414,-98.2063),
(10,'Antea','111','Universidad',20.5888,-100.3899),
(11,'Madero','222','Hidalgo',21.1220,-101.6823),
(12,'Álvaro Obregón','333','Universitarios',24.8091,-107.3940),
(13,'20 de Noviembre','444','Victoria',24.0277,-104.6532),
(14,'Ruiz Cortines','555','Martí',19.1738,-96.1342),
(15,'Calzada Porfirio Díaz','666','Escuela Naval',17.0732,-96.7266);

-- CLINICS
INSERT INTO clinics (name, address_id, phone, institution_type, is_active) VALUES
('Clínica Monterrey Norte',1,'8111111111','IMSS',TRUE),
('Clínica Guadalajara Centro',2,'3311111111','ISSSTE',TRUE),
('Clínica Del Valle',3,'5511111111','SSA',TRUE),
('Clínica Saltillo',4,'8441111111','IMSS',TRUE),
('Clínica Reynosa',5,'8991111111','SSA',TRUE),
('Clínica Hermosillo',6,'6621111111','ISSSTE',TRUE),
('Clínica Chihuahua',7,'6141111111','IMSS',TRUE),
('Clínica Mérida',8,'9991111111','SSA',TRUE),
('Clínica Puebla',9,'2221111111','ISSSTE',TRUE),
('Clínica Querétaro',10,'4421111111','IMSS',TRUE),
('Clínica León',11,'4771111111','SSA',TRUE),
('Clínica Culiacán',12,'6671111111','ISSSTE',TRUE),
('Clínica Durango',13,'6181111111','IMSS',TRUE),
('Clínica Veracruz',14,'2291111111','SSA',TRUE),
('Clínica Oaxaca',15,'9511111111','ISSSTE',TRUE);

-- CLINIC AREA TYPES
INSERT INTO clinic_area_types (area_type) VALUES
('Administración'),
('Enfermería'),
('Médico'),
('Recepción'),
('Almacén');

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
INSERT INTO patients (first_name, last_name, birth_date, blood_type_id, gender, nfc_token, curp, weight_kg, premature) VALUES
('Mateo','García','2018-03-15',1,'M','NFC001','GAMM180315HNLRTRA1',25.50,FALSE),
('Sofía','Martínez','2019-07-20',2,'F','NFC002','MASS190720MNLRFBA2',22.10,FALSE),
('Diego','López','2020-01-10',3,'M','NFC003','LODD200110HNLRPCA3',18.00,TRUE),
('Valentina','Hernández','2017-11-05',4,'F','NFC004','HEVV171105MNLRLDA4',28.40,FALSE),
('Lucas','Ramírez','2021-06-12',5,'M','NFC005','RALL210612HNLRMNA5',16.20,FALSE),
('Emma','Torres','2018-08-18',6,'F','NFC006','TOEE180818MNLRRSA6',24.30,FALSE),
('Sebastián','Flores','2019-04-09',7,'M','NFC007','FOSS190409HNLRBTA7',20.00,FALSE),
('Camila','Rivera','2020-09-14',8,'F','NFC008','RICC200914MNLRVCA8',19.40,TRUE),
('Leonardo','Gómez','2017-12-30',1,'M','NFC009','GOAL171230HNLRMDA9',29.10,FALSE),
('Renata','Díaz','2021-02-25',2,'F','NFC010','DIRR210225MNLRZEA1',15.70,FALSE),
('Emiliano','Castro','2018-05-03',3,'M','NFC011','CAEE180503HNLRMSA2',23.60,FALSE),
('Regina','Ortiz','2019-10-16',4,'F','NFC012','OARR191016MNLRRGA3',21.80,FALSE),
('Daniel','Morales','2020-07-01',5,'M','NFC013','MODD200701HNLRNTA4',17.90,TRUE),
('Victoria','Ruiz','2017-09-27',6,'F','NFC014','RUVV170927MNLRKLA5',30.20,FALSE),
('Ángel','Navarro','2021-04-11',7,'M','NFC015','NAAA210411HNLRVSA6',14.50,FALSE);

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

-- ROLES
INSERT INTO roles (name, description) VALUES
('Administrador','Gestiona el sistema'),
('Enfermero','Aplica vacunas'),
('Médico','Supervisa pacientes'),
('Recepcionista','Agenda citas'),
('Almacén','Controla inventario');

-- SPECIALTIES
INSERT INTO specialties (name) VALUES
('Pediatría'),('Medicina General'),('Inmunología'),('Enfermería Pediátrica'),('Urgencias'),
('Cardiología'),('Neurología'),('Dermatología'),('Nutrición'),('Traumatología'),
('Ginecología'),('Radiología'),('Oncología'),('Psiquiatría'),('Oftalmología');

-- CLINIC AREAS
INSERT INTO clinic_areas (clinic_id, name, area_type_id, floor, capacity) VALUES
(1,'Área Norte',1,1,20),(2,'Área Centro',2,1,15),(3,'Área Pediátrica',3,2,10),
(4,'Recepción A',4,1,25),(5,'Almacén Principal',5,0,30),(6,'Consultorio 1',3,2,10),
(7,'Enfermería A',2,1,12),(8,'Administración',1,2,8),(9,'Vacunación',2,1,20),
(10,'Urgencias',3,1,15),(11,'Recepción B',4,1,25),(12,'Farmacia',5,0,18),
(13,'Consultorio 2',3,2,10),(14,'Área Sur',1,1,20),(15,'Enfermería B',2,1,15);

-- EQUIPMENT CATALOG
INSERT INTO equipment_catalog (name, category, requires_calibration) VALUES
('Refrigerador Médico','Frío',TRUE),('Termómetro Digital','Medición',FALSE),
('Báscula Pediátrica','Peso',TRUE),('Camilla','Mobiliario',FALSE),('Computadora','Tecnología',FALSE),
('Monitor Signos','Monitoreo',TRUE),('Oxímetro','Monitoreo',FALSE),('Jeringa Automática','Vacunación',TRUE),
('Lector NFC','Tecnología',FALSE),('Impresora','Tecnología',FALSE),('Mesa Clínica','Mobiliario',FALSE),
('Silla de Espera','Mobiliario',FALSE),('Estante','Almacén',FALSE),('Laptop','Tecnología',FALSE),('Ultracongelador','Frío',TRUE);

-- AREA EQUIPMENT
INSERT INTO area_equipment (area_id, equipment_id, quantity, serial_number, condition) VALUES
(1,1,1,'SN001','Bueno'),(2,2,2,'SN002','Bueno'),(3,3,1,'SN003','Excelente'),
(4,4,3,'SN004','Bueno'),(5,5,2,'SN005','Excelente'),(6,6,1,'SN006','Bueno'),
(7,7,2,'SN007','Bueno'),(8,8,1,'SN008','Excelente'),(9,9,1,'SN009','Bueno'),
(10,10,2,'SN010','Excelente'),(11,11,1,'SN011','Bueno'),(12,12,6,'SN012','Bueno'),
(13,13,2,'SN013','Excelente'),(14,14,1,'SN014','Bueno'),(15,15,1,'SN015','Excelente');

-- PATIENT ALLERGIES
INSERT INTO patient_allergies (patient_id, allergy_id, severity, reaction_desc) VALUES
(1,1,'Moderada','Erupción'),(2,2,'Leve','Estornudos'),(3,3,'Moderada','Dolor estomacal'),
(4,4,'Alta','Inflamación'),(5,5,'Alta','Ronchas'),(6,6,'Leve','Tos'),
(7,7,'Moderada','Irritación'),(8,8,'Leve','Náuseas'),(9,9,'Alta','Fiebre'),
(10,10,'Moderada','Mareo'),(11,11,'Leve','Dolor abdominal'),(12,12,'Leve','Dolor cabeza'),
(13,13,'Moderada','Inflamación'),(14,14,'Leve','Estornudos'),(15,15,'Moderada','Fiebre');

-- GUARDIAN PHONES
INSERT INTO guardian_phones (guardian_id, phone, phone_type, is_primary) VALUES
(1,'8110000001','Móvil',TRUE),(2,'8110000002','Móvil',TRUE),(3,'8110000003','Casa',TRUE),
(4,'8110000004','Móvil',TRUE),(5,'8110000005','Trabajo',TRUE),(6,'8110000006','Casa',TRUE),
(7,'8110000007','Móvil',TRUE),(8,'8110000008','Trabajo',TRUE),(9,'8110000009','Casa',TRUE),
(10,'8110000010','Móvil',TRUE),(11,'8110000011','Trabajo',TRUE),(12,'8110000012','Casa',TRUE),
(13,'8110000013','Móvil',TRUE),(14,'8110000014','Trabajo',TRUE),(15,'8110000015','Casa',TRUE);

-- GUARDIAN EMAILS
INSERT INTO guardian_emails (guardian_id, email, is_primary) VALUES
(1,'guardian1@mail.com',TRUE),(2,'guardian2@mail.com',TRUE),(3,'guardian3@mail.com',TRUE),
(4,'guardian4@mail.com',TRUE),(5,'guardian5@mail.com',TRUE),(6,'guardian6@mail.com',TRUE),
(7,'guardian7@mail.com',TRUE),(8,'guardian8@mail.com',TRUE),(9,'guardian9@mail.com',TRUE),
(10,'guardian10@mail.com',TRUE),(11,'guardian11@mail.com',TRUE),(12,'guardian12@mail.com',TRUE),
(13,'guardian13@mail.com',TRUE),(14,'guardian14@mail.com',TRUE),(15,'guardian15@mail.com',TRUE);

-- INSTITUTIONS
INSERT INTO institutions (institution_name, address_id) VALUES
('UANL',1),('UNAM',2),('IPN',3),('TEC',4),('UDEM',5),('BUAP',6),('UDG',7),('UAQ',8),('UV',9),('UAS',10),('UACH',11),('UAN',12),('UABC',13),('UAEM',14),('UOAX',15);

-- WORKERS
INSERT INTO workers (role_id, first_name, last_name, curp, address_id, birth_date, hire_date, password_hash) VALUES
(1,'José','Pérez','PEPJ850101HNLRRS01',1,'1985-01-01','2020-01-01','hash1'),
(2,'Lucía','Santos','SALU860202MNLRNC02',2,'1986-02-02','2020-02-01','hash2'),
(3,'Mario','Luna','LUMM870303HNLRNR03',3,'1987-03-03','2020-03-01','hash3'),
(4,'Elisa','Campos','CAEE880404MNLRML04',4,'1988-04-04','2020-04-01','hash4'),
(5,'Raúl','Mora','MORR890505HNLRRA05',5,'1989-05-05','2020-05-01','hash5'),
(1,'Paty','Ríos','RIPP900606MNLRRT06',6,'1990-06-06','2020-06-01','hash6'),
(2,'Andrés','León','LEAA910707HNLRNN07',7,'1991-07-07','2020-07-01','hash7'),
(3,'Diana','Paz','PADD920808MNLRDZ08',8,'1992-08-08','2020-08-01','hash8'),
(4,'Iván','Silva','SIII930909HNLRLV09',9,'1993-09-09','2020-09-01','hash9'),
(5,'Karen','Vega','VEKK941010MNLRGR10',10,'1994-10-10','2020-10-01','hash10'),
(1,'Tomás','Gil','GITT951111HNLRLM11',11,'1995-11-11','2020-11-01','hash11'),
(2,'Nora','Reyes','RENN961212MNLRYR12',12,'1996-12-12','2020-12-01','hash12'),
(3,'Alan','Cruz','CUAA970101HNLRRL13',13,'1997-01-01','2021-01-01','hash13'),
(4,'Mónica','Peña','PEMM980202MNLRXN14',14,'1998-02-02','2021-02-01','hash14'),
(5,'Víctor','Soto','SOVV990303HNLRCT15',15,'1999-03-03','2021-03-01','hash15');

-- USERS
INSERT INTO users (worker_id, username, password_hash, is_active) VALUES
(1,'admin1','hash1',TRUE),(2,'enfermero1','hash2',TRUE),(3,'medico1','hash3',TRUE),
(4,'recepcion1','hash4',TRUE),(5,'almacen1','hash5',TRUE),(6,'admin2','hash6',TRUE),
(7,'enfermero2','hash7',TRUE),(8,'medico2','hash8',TRUE),(9,'recepcion2','hash9',TRUE),
(10,'almacen2','hash10',TRUE),(11,'admin3','hash11',TRUE),(12,'enfermero3','hash12',TRUE),
(13,'medico3','hash13',TRUE),(14,'recepcion3','hash14',TRUE),(15,'almacen3','hash15',TRUE);

-- MANUFACTURERS
INSERT INTO manufacturers (name, country_id, contact_email) VALUES
('Pfizer',1,'pfizer@mail.com'),('Moderna',2,'moderna@mail.com'),('AstraZeneca',3,'astra@mail.com'),
('Sanofi',4,'sanofi@mail.com'),('GSK',5,'gsk@mail.com'),('Bayer',6,'bayer@mail.com'),
('BioNTech',7,'bio@mail.com'),('Novavax',8,'nova@mail.com'),('Sinovac',9,'sino@mail.com'),
('Sputnik',10,'sputnik@mail.com'),('Janssen',11,'janssen@mail.com'),('Merck',12,'merck@mail.com'),
('Abbott',13,'abbott@mail.com'),('Takeda',14,'takeda@mail.com'),('Roche',15,'roche@mail.com');

-- VACCINE VIAS
INSERT INTO vaccine_vias (via) VALUES
('Intramuscular'),('Subcutánea'),('Oral'),('Intravenosa'),('Intradérmica');

-- VACCINES
INSERT INTO vaccines (name, commercial_name, manufacturer_id, via_id, ideal_age_months, disease_prevented) VALUES
('BCG','BCG Plus',1,1,0,'Tuberculosis'),('Hepatitis B','HepaSafe',2,1,1,'Hepatitis B'),
('Pentavalente','PentaKids',3,1,2,'Difteria'),('Rotavirus','RotaFree',4,3,2,'Rotavirus'),
('Neumococo','NeumoCare',5,1,2,'Neumonía'),('Influenza','FluKids',6,1,6,'Influenza'),
('SRP','TripleViral',7,2,12,'Sarampión'),('Varicela','VariSafe',8,2,12,'Varicela'),
('COVID-19','CovidShield',9,1,60,'COVID-19'),('Polio','PolioVac',10,3,4,'Polio'),
('Tétanos','TetaSafe',11,1,6,'Tétanos'),('Rabia','RabVac',12,1,24,'Rabia'),
('Hepatitis A','HepaA',13,1,12,'Hepatitis A'),('VPH','VPHCare',14,1,96,'VPH'),('Meningococo','Meningo',15,1,6,'Meningitis');

```
