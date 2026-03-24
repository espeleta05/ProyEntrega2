from datetime import date, datetime
from flask import Flask, flash, jsonify, redirect, render_template, request, session, url_for

app = Flask(__name__)
app.secret_key = "segunda-entrega-demo"


# DATOS HARDCODEADOS  (simulan lo que devolvería PostgreSQL)

# --- COUNTRIES / STATES / MUNICIPALITIES / NEIGHBORHOODS / ADDRESSES 
COUNTRIES = [
    {"country_id": 1, "name": "México", "iso_code": "MX"},
]

STATES = [
    {"state_id": 1, "country_id": 1, "name": "Nuevo León", "code": "NL"},
]

MUNICIPALITIES = [
    {"municipality_id": 1, "state_id": 1, "name": "Monterrey"},
    {"municipality_id": 2, "state_id": 1, "name": "Guadalupe"},
]

NEIGHBORHOODS = [
    {"neighborhood_id": 1, "municipality_id": 1, "name": "Centro",       "zip_code": "64000"},
    {"neighborhood_id": 2, "municipality_id": 1, "name": "Obispado",     "zip_code": "64010"},
    {"neighborhood_id": 3, "municipality_id": 2, "name": "Topo Chico",   "zip_code": "64260"},
]

ADDRESSES = [
    {"address_id": 1, "neighborhood_id": 1, "street": "Av. Constitución",  "ext_number": "100", "cross_street_1": "Juárez",   "cross_street_2": "Zaragoza", "latitude": 25.6700, "longitude": -100.3099},
    {"address_id": 2, "neighborhood_id": 2, "street": "Calle Obispado",    "ext_number": "45",  "cross_street_1": "Hidalgo",  "cross_street_2": None,       "latitude": 25.6780, "longitude": -100.3200},
    {"address_id": 3, "neighborhood_id": 3, "street": "Blvd. Díaz Ordaz",  "ext_number": "500", "cross_street_1": "Morones",  "cross_street_2": None,       "latitude": 25.7050, "longitude": -100.3500},
]

# --- CLINICS
CLINICS = [
    {"clinic_id": 1, "name": "Centro de Salud Centro",    "clues": "NLSSA001", "address_id": 1, "phone": "8112223344", "institution_type": "SSA",     "is_active": True},
    {"clinic_id": 2, "name": "Unidad Médica Obispado",    "clues": "NLIMSS02", "address_id": 2, "phone": "8118887766", "institution_type": "IMSS",    "is_active": True},
    {"clinic_id": 3, "name": "Clínica DIF Guadalupe",     "clues": "NLDIF003", "address_id": 3, "phone": "8191234567", "institution_type": "DIF",     "is_active": True},
]

CLINIC_AREAS = [
    {"area_id": 1, "clinic_id": 1, "name": "Recepción",       "area_type": "Recepcion",   "floor": 1, "capacity": 20},
    {"area_id": 2, "clinic_id": 1, "name": "Sala de Espera",  "area_type": "Sala_Espera", "floor": 1, "capacity": 40},
    {"area_id": 3, "clinic_id": 1, "name": "Consultorio 1",   "area_type": "Consultorio", "floor": 1, "capacity": 5},
    {"area_id": 4, "clinic_id": 2, "name": "Enfermería A",    "area_type": "Enfermeria",  "floor": 1, "capacity": 10},
    {"area_id": 5, "clinic_id": 3, "name": "Almacén Central", "area_type": "Almacen",     "floor": 1, "capacity": None},
]

# --- ROLES / WORKERS 
ROLES = [
    {"role_id": 1, "name": "Administrador", "description": "Acceso total al sistema"},
    {"role_id": 2, "name": "Médico",        "description": "Consulta y vacunación"},
    {"role_id": 3, "name": "Enfermero",     "description": "Aplicación de vacunas"},
    {"role_id": 4, "name": "Almacen",       "description": "Control de inventario"},
    {"role_id": 5, "name": "Recepcionista", "description": "Registro de llegadas"},
]

WORKERS = [
    {"worker_id": 1, "role_id": 1, "first_name": "Admin",  "last_name": "Demo",   "second_last": None,    "curp": "ADMD800101HNLMMS09", "email": "admin",             "phone": None,         "address_id": None, "birth_date": "1980-01-01", "hire_date": "2020-01-01", "is_active": True},
    {"worker_id": 2, "role_id": 3, "first_name": "Elena",  "last_name": "Garza",  "second_last": "Leal",  "curp": "GALE900215MNLRZL05", "email": "elena@demo.local",  "phone": "8111122334", "address_id": 1,    "birth_date": "1990-02-15", "hire_date": "2021-03-10", "is_active": True},
    {"worker_id": 3, "role_id": 4, "first_name": "Mario",  "last_name": "Ruiz",   "second_last": "Peña",  "curp": "RUPM850730HNLZÑR08", "email": "mario@demo.local",  "phone": "8199988776", "address_id": 2,    "birth_date": "1985-07-30", "hire_date": "2022-06-01", "is_active": True},
    {"worker_id": 4, "role_id": 2, "first_name": "Sofía",  "last_name": "Torres", "second_last": "Vega",  "curp": "TOVS920410MNLRRG06", "email": "sofia@demo.local",  "phone": "8115566778", "address_id": 3,    "birth_date": "1992-04-10", "hire_date": "2023-01-15", "is_active": True},
    {"worker_id": 5, "role_id": 5, "first_name": "Pedro",  "last_name": "Luna",   "second_last": None,    "curp": "LUMP781120HNLNND03", "email": "pedro@demo.local",  "phone": "8182233445", "address_id": 1,    "birth_date": "1978-11-20", "hire_date": "2020-09-05", "is_active": False},
]

WORKER_PROFESSIONAL = [
    {"worker_id": 4, "cedula_profesional": "CED-1234567", "specialty": "Pediatría",        "institution_title": "UANL",          "specialty_code": "PED"},
    {"worker_id": 2, "cedula_profesional": "CED-9876543", "specialty": "Enfermería General","institution_title": "TecSalud NL",   "specialty_code": "ENF"},
]

WORKER_CLINIC_ASSIGNMENTS = [
    {"assignment_id": 1, "worker_id": 1, "clinic_id": 1, "area_id": None, "start_date": "2020-01-01", "end_date": None,         "is_active": True},
    {"assignment_id": 2, "worker_id": 2, "clinic_id": 1, "area_id": 3,    "start_date": "2021-03-10", "end_date": None,         "is_active": True},
    {"assignment_id": 3, "worker_id": 3, "clinic_id": 1, "area_id": 5,    "start_date": "2022-06-01", "end_date": None,         "is_active": True},
    {"assignment_id": 4, "worker_id": 4, "clinic_id": 2, "area_id": 4,    "start_date": "2023-01-15", "end_date": None,         "is_active": True},
    {"assignment_id": 5, "worker_id": 5, "clinic_id": 3, "area_id": 1,    "start_date": "2020-09-05", "end_date": "2024-12-31", "is_active": False},
]

WORKER_SCHEDULES = [
    {"schedule_id": 1, "worker_id": 2, "clinic_id": 1, "day_of_week": 1, "entry_time": "08:00", "exit_time": "14:00", "shift_type": "Matutino"},
    {"schedule_id": 2, "worker_id": 2, "clinic_id": 1, "day_of_week": 3, "entry_time": "08:00", "exit_time": "14:00", "shift_type": "Matutino"},
    {"schedule_id": 3, "worker_id": 4, "clinic_id": 2, "day_of_week": 2, "entry_time": "14:00", "exit_time": "20:00", "shift_type": "Vespertino"},
]

# --- GUARDIANS 
GUARDIANS = [
    {"guardian_id": 1, "first_name": "María",  "last_name": "Martínez", "second_last": "Soto",   "curp": "MASM800501MNLRTRO8", "address_id": 1, "marital_status": "Casado",      "occupation": "Profesora",   "created_at": "2024-01-10"},
    {"guardian_id": 2, "first_name": "Jorge",  "last_name": "Sánchez",  "second_last": "Reyes",  "curp": "SARJ790320HNLNYR02", "address_id": 2, "marital_status": "Soltero",     "occupation": "Contador",    "created_at": "2024-02-14"},
    {"guardian_id": 3, "first_name": "Laura",  "last_name": "López",    "second_last": "Juárez", "curp": "LOJL850715MNLPJR05", "address_id": 3, "marital_status": "Union_Libre", "occupation": "Enfermera",   "created_at": "2024-03-20"},
]

GUARDIAN_PHONES = [
    {"phone_id": 1, "guardian_id": 1, "phone": "8112345678", "phone_type": "Celular",    "is_primary": True},
    {"phone_id": 2, "guardian_id": 1, "phone": "8118889900", "phone_type": "Casa",       "is_primary": False},
    {"phone_id": 3, "guardian_id": 2, "phone": "8187654321", "phone_type": "Celular",    "is_primary": True},
    {"phone_id": 4, "guardian_id": 3, "phone": "8199911122", "phone_type": "Celular",    "is_primary": True},
    {"phone_id": 5, "guardian_id": 3, "phone": "8005551234", "phone_type": "Emergencia", "is_primary": False},
]

GUARDIAN_EMAILS = [
    {"email_id": 1, "guardian_id": 1, "email": "maria.martinez@mail.com", "is_primary": True},
    {"email_id": 2, "guardian_id": 2, "email": "jorge.sanchez@mail.com",  "is_primary": True},
    {"email_id": 3, "guardian_id": 3, "email": "laura.lopez@mail.com",    "is_primary": True},
]

# --- PATIENTS 
PATIENTS = [
    {"patient_id": 1, "first_name": "Ana",     "last_name": "Martínez", "second_last": "Soto",   "curp": "MASA200515MNLRTN09", "birth_date": "2020-05-15", "gender": "F", "blood_type": "O+",  "nfc_token": "NFC001", "guardian_id": 1, "address_id": 1, "risk_level": "bajo",  "is_active": True, "registered_at": "2024-01-10"},
    {"patient_id": 2, "first_name": "Carlos",  "last_name": "Sánchez",  "second_last": "Reyes",  "curp": "SARC190308HNLNRL05", "birth_date": "2019-03-08", "gender": "M", "blood_type": "A+",  "nfc_token": "NFC002", "guardian_id": 2, "address_id": 2, "risk_level": "medio", "is_active": True, "registered_at": "2024-02-14"},
    {"patient_id": 3, "first_name": "Daniela", "last_name": "López",    "second_last": "Juárez", "curp": "LOJD221003MNLPJN07", "birth_date": "2022-10-03", "gender": "F", "blood_type": "B+",  "nfc_token": "NFC003", "guardian_id": 3, "address_id": 3, "risk_level": "alto",  "is_active": True, "registered_at": "2024-03-20"},
    {"patient_id": 4, "first_name": "Miguel",  "last_name": "Flores",   "second_last": "Cruz",   "curp": "FOCM210720HNLLRG04", "birth_date": "2021-07-20", "gender": "M", "blood_type": "AB+", "nfc_token": "NFC004", "guardian_id": 1, "address_id": 1, "risk_level": "bajo",  "is_active": True, "registered_at": "2024-04-05"},
]

PATIENT_ALLERGIES = [
    {"allergy_id": 1, "patient_id": 2, "allergen": "Polen",      "reaction": "Rinitis",    "severity": "Leve",     "notes": None},
    {"allergy_id": 2, "patient_id": 3, "allergen": "Penicilina", "reaction": "Urticaria",  "severity": "Moderada", "notes": "Evitar derivados"},
    {"allergy_id": 3, "patient_id": 3, "allergen": "Látex",      "reaction": "Erupción",   "severity": "Leve",     "notes": None},
]

# --- VACCINES / LOTS 
VACCINES = [
    {"vaccine_id": 1, "name": "BCG",           "disease_target": "Tuberculosis",           "manufacturer": "Biofabrica MX", "recommended_age_months": "0-12",   "doses_required": 1, "interval_days": None, "route": "Intradérmica",    "is_active": True},
    {"vaccine_id": 2, "name": "Hepatitis B",   "disease_target": "Hepatitis B",             "manufacturer": "SaludVac",     "recommended_age_months": "0+",     "doses_required": 3, "interval_days": 30,   "route": "Intramuscular",   "is_active": True},
    {"vaccine_id": 3, "name": "Pentavalente",  "disease_target": "Difteria/Tos/Tétanos",   "manufacturer": "GSK",          "recommended_age_months": "2-72",   "doses_required": 5, "interval_days": 60,   "route": "Intramuscular",   "is_active": True},
    {"vaccine_id": 4, "name": "Rotavirus",     "disease_target": "Gastroenteritis",         "manufacturer": "MSD",          "recommended_age_months": "2-8",    "doses_required": 3, "interval_days": 60,   "route": "Oral",            "is_active": True},
    {"vaccine_id": 5, "name": "Influenza",     "disease_target": "Influenza estacional",    "manufacturer": "Sanofi",       "recommended_age_months": "6+",     "doses_required": 1, "interval_days": 365,  "route": "Intramuscular",   "is_active": True},
]

VACCINE_LOTS = [
    {"lot_id": 1, "vaccine_id": 1, "clinic_id": 1, "lot_number": "LOT-BCG-2025-01",  "quantity_received": 200, "quantity_remaining": 120, "reception_date": "2025-01-05", "expiration_date": "2026-06-30", "is_active": True,  "received_by": 3},
    {"lot_id": 2, "vaccine_id": 2, "clinic_id": 1, "lot_number": "LOT-HEB-2025-02",  "quantity_received": 150, "quantity_remaining": 95,  "reception_date": "2025-01-10", "expiration_date": "2025-12-31", "is_active": True,  "received_by": 3},
    {"lot_id": 3, "vaccine_id": 3, "clinic_id": 1, "lot_number": "LOT-PEN-2025-03",  "quantity_received": 100, "quantity_remaining": 80,  "reception_date": "2025-02-01", "expiration_date": "2026-03-15", "is_active": True,  "received_by": 3},
    {"lot_id": 4, "vaccine_id": 4, "clinic_id": 2, "lot_number": "LOT-ROT-2025-04",  "quantity_received": 60,  "quantity_remaining": 30,  "reception_date": "2025-02-15", "expiration_date": "2025-08-01", "is_active": True,  "received_by": 3},
    {"lot_id": 5, "vaccine_id": 5, "clinic_id": 3, "lot_number": "LOT-INF-2024-09",  "quantity_received": 300, "quantity_remaining": 0,   "reception_date": "2024-09-01", "expiration_date": "2025-06-30", "is_active": False, "received_by": 3},
]

# --- VACCINATION RECORDS (APPLICATIONS) 
APPLICATIONS = [
    {"record_id": 1, "patient_id": 1, "vaccine_id": 1, "lot_id": 1, "clinic_id": 1, "applied_by": 2, "applied_date": "2025-01-10", "dose_applied": "1", "next_dose_date": "2025-03-10", "clinic_location": "Consultorio 1", "notes": "Sin reacciones"},
    {"record_id": 2, "patient_id": 2, "vaccine_id": 2, "lot_id": 2, "clinic_id": 1, "applied_by": 2, "applied_date": "2025-02-15", "dose_applied": "1", "next_dose_date": "2025-04-15", "clinic_location": "Consultorio 1", "notes": "Control en 2 meses"},
    {"record_id": 3, "patient_id": 1, "vaccine_id": 3, "lot_id": 3, "clinic_id": 1, "applied_by": 1, "applied_date": "2025-03-20", "dose_applied": "2", "next_dose_date": "2025-05-20", "clinic_location": "Enfermería A",  "notes": "Reforzar hidratación"},
    {"record_id": 4, "patient_id": 3, "vaccine_id": 2, "lot_id": 2, "clinic_id": 2, "applied_by": 4, "applied_date": "2025-03-01", "dose_applied": "1", "next_dose_date": "2025-05-01", "clinic_location": "Enfermería A",  "notes": "Primera dosis"},
    {"record_id": 5, "patient_id": 4, "vaccine_id": 4, "lot_id": 4, "clinic_id": 2, "applied_by": 2, "applied_date": "2025-03-22", "dose_applied": "1", "next_dose_date": None,          "clinic_location": "Consultorio 1", "notes": "Sin incidencias"},
]

# --- SCHEME (vaccination schedule) 
SCHEME = [
    ({"ideal_age_months": 0,  "dose_number": "Dosis 1"}, {"name": "BCG"}),
    ({"ideal_age_months": 0,  "dose_number": "Dosis 1"}, {"name": "Hepatitis B"}),
    ({"ideal_age_months": 2,  "dose_number": "Dosis 1"}, {"name": "Pentavalente"}),
    ({"ideal_age_months": 2,  "dose_number": "Dosis 1"}, {"name": "Rotavirus"}),
    ({"ideal_age_months": 4,  "dose_number": "Dosis 2"}, {"name": "Pentavalente"}),
    ({"ideal_age_months": 6,  "dose_number": "Dosis 1"}, {"name": "Influenza"}),
    ({"ideal_age_months": 6,  "dose_number": "Dosis 3"}, {"name": "Hepatitis B"}),
    ({"ideal_age_months": 12, "dose_number": "Dosis 1"}, {"name": "SRP"}),
]

SCHEME_COMPLETION_ALERTS = [
    {"alert_id": 1, "patient_id": 3, "vaccine_id": 3, "expected_date": "2023-12-03", "status": "Pendiente",  "generated_at": "2024-01-01", "resolved_at": None,         "resolved_by": None, "notes": "Esquema incompleto – Pentavalente"},
    {"alert_id": 2, "patient_id": 2, "vaccine_id": 5, "expected_date": "2025-03-08", "status": "Enviada",    "generated_at": "2025-03-09", "resolved_at": None,         "resolved_by": None, "notes": "Influenza pendiente"},
    {"alert_id": 3, "patient_id": 1, "vaccine_id": 2, "expected_date": "2025-04-15", "status": "Resuelta",   "generated_at": "2025-03-10", "resolved_at": "2025-04-16", "resolved_by": 2,    "notes": "Hepatitis B dosis 2 aplicada"},
]

# --- APPOINTMENTS 
APPOINTMENTS = [
    {"appointment_id": 1, "patient_id": 1, "clinic_id": 1, "worker_id": 2, "vaccine_id": 2, "scheduled_at": "2025-06-10 09:00", "status": "Programada",  "notes": "Segunda dosis Hep B"},
    {"appointment_id": 2, "patient_id": 2, "clinic_id": 1, "worker_id": 2, "vaccine_id": 3, "scheduled_at": "2025-04-15 10:30", "status": "Programada",  "notes": "Pentavalente refuerzo"},
    {"appointment_id": 3, "patient_id": 3, "clinic_id": 2, "worker_id": 4, "vaccine_id": 5, "scheduled_at": "2025-05-20 08:00", "status": "Cancelada",   "notes": "Paciente no asistió"},
    {"appointment_id": 4, "patient_id": 4, "clinic_id": 1, "worker_id": 2, "vaccine_id": 1, "scheduled_at": "2025-03-22 11:00", "status": "Completada",  "notes": "BCG aplicada sin incidentes"},
]

# --- NFC CARDS & SCAN EVENTS 
NFC_CARDS = [
    {"nfc_card_id": 1, "patient_id": 1, "uid": "NFC001AA", "card_type": "Tarjeta",  "issued_date": "2024-01-10", "issued_by": 1, "status": "Activa",       "last_scanned_at": "2025-03-20 09:15", "notes": None},
    {"nfc_card_id": 2, "patient_id": 2, "uid": "NFC002BB", "card_type": "Pulsera",  "issued_date": "2024-02-14", "issued_by": 1, "status": "Activa",       "last_scanned_at": "2025-02-15 10:05", "notes": None},
    {"nfc_card_id": 3, "patient_id": 3, "uid": "NFC003CC", "card_type": "Llavero",  "issued_date": "2024-03-20", "issued_by": 1, "status": "Desactivada",  "last_scanned_at": None,               "notes": "Reportado extraviado"},
    {"nfc_card_id": 4, "patient_id": 4, "uid": "NFC004DD", "card_type": "Tarjeta",  "issued_date": "2024-04-05", "issued_by": 1, "status": "Activa",       "last_scanned_at": "2025-03-22 11:00", "notes": None},
]

NFC_SCAN_EVENTS = [
    {"scan_event_id": 1, "nfc_card_id": 1, "scanned_by": 2, "clinic_id": 1, "area_id": 3, "scanned_at": "2025-03-20 09:15", "action_triggered": "Abrir_Expediente",    "result": "Expediente abierto correctamente"},
    {"scan_event_id": 2, "nfc_card_id": 2, "scanned_by": 2, "clinic_id": 1, "area_id": 3, "scanned_at": "2025-02-15 10:05", "action_triggered": "Confirmar_Vacunacion", "result": "Vacunación registrada"},
    {"scan_event_id": 3, "nfc_card_id": 4, "scanned_by": 2, "clinic_id": 1, "area_id": 1, "scanned_at": "2025-03-22 11:00", "action_triggered": "Registrar_Llegada",    "result": "Llegada registrada"},
]

# --- GPS DEVICES & LOCATIONS 
GPS_DEVICES = [
    {"gps_device_id": 1, "patient_id": 3, "device_type": "Pulsera_GPS", "model": "GarminKid3", "imei": "352099001761481", "assigned_date": "2024-03-20", "assigned_by": 1, "battery_pct": 72, "status": "Activo"},
    {"gps_device_id": 2, "patient_id": 2, "device_type": "App_Tutor",   "model": "AppSalud v2", "imei": None,             "assigned_date": "2024-02-14", "assigned_by": 1, "battery_pct": 95, "status": "Activo"},
]

GPS_RISK_ALERTS = [
    {"alert_id": 1, "patient_id": 3, "gps_device_id": 1, "alert_type": "Salida_Zona_Segura", "triggered_at": "2025-03-10 14:35", "location_lat": 25.6850, "location_lng": -100.3150, "resolved_at": "2025-03-10 14:50", "resolved_by": 2,    "notes": "Tutor confirmó ubicación"},
    {"alert_id": 2, "patient_id": 2, "gps_device_id": 2, "alert_type": "Bateria_Baja",       "triggered_at": "2025-03-20 07:00", "location_lat": None,    "location_lng": None,       "resolved_at": None,               "resolved_by": None, "notes": "Pendiente de respuesta"},
]

GPS_SAFE_ZONES = [
    {"zone_id": 1, "patient_id": 3, "guardian_id": 3, "zone_name": "Casa",       "center_lat": 25.7050, "center_lng": -100.3500, "radius_m": 150, "is_active": True},
    {"zone_id": 2, "patient_id": 3, "guardian_id": 3, "zone_name": "Clínica",    "center_lat": 25.6700, "center_lng": -100.3099, "radius_m": 200, "is_active": True},
    {"zone_id": 3, "patient_id": 2, "guardian_id": 2, "zone_name": "Escuela",    "center_lat": 25.6780, "center_lng": -100.3200, "radius_m": 100, "is_active": True},
]

# --- SUPPLY / INVENTORY 
SUPPLY_CATALOG = [
    {"supply_id": 1, "name": "Jeringa 1mL",         "unit": "pieza",   "category": "Jeringa",      "description": "Jeringa desechable 1mL"},
    {"supply_id": 2, "name": "Jeringa 5mL",         "unit": "pieza",   "category": "Jeringa",      "description": "Jeringa desechable 5mL"},
    {"supply_id": 3, "name": "Algodón estéril",     "unit": "paquete", "category": "Desechable",   "description": "Paquete 100 piezas"},
    {"supply_id": 4, "name": "Guantes nitrilo M",   "unit": "caja",    "category": "Desechable",   "description": "Caja 100 guantes talla M"},
    {"supply_id": 5, "name": "Paracetamol 500mg",   "unit": "tableta", "category": "Medicamento",  "description": "Analgésico/antipirético"},
]

CLINIC_INVENTORY = [
    {"inventory_id": 1, "clinic_id": 1, "supply_id": 1, "quantity": 500,  "min_stock": 50,  "last_updated": "2025-03-01", "updated_by": 3},
    {"inventory_id": 2, "clinic_id": 1, "supply_id": 3, "quantity": 30,   "min_stock": 20,  "last_updated": "2025-03-01", "updated_by": 3},
    {"inventory_id": 3, "clinic_id": 1, "supply_id": 4, "quantity": 8,    "min_stock": 10,  "last_updated": "2025-03-10", "updated_by": 3},  # bajo stock
    {"inventory_id": 4, "clinic_id": 2, "supply_id": 2, "quantity": 200,  "min_stock": 30,  "last_updated": "2025-02-20", "updated_by": 3},
    {"inventory_id": 5, "clinic_id": 3, "supply_id": 5, "quantity": 1000, "min_stock": 100, "last_updated": "2025-01-15", "updated_by": 3},
]

# --- RISK ZONES (mapa) 
ZONES = [
    {"name": "Zona Centro",   "cases": 4, "risk": "high"},
    {"name": "Zona Norte",    "cases": 2, "risk": "medium"},
    {"name": "Zona Sur",      "cases": 1, "risk": "low"},
    {"name": "Zona Oriente",  "cases": 3, "risk": "high"},
    {"name": "Zona Poniente", "cases": 1, "risk": "low"},
]

# --- USERS (login) 
USERS = {
    "admin": {"password": "123", "worker_id": 1, "name": "Admin", "lastname": "Demo", "role": "Administrador"},
}


# 
# HELPERS — simulan el cursor de psycopg2
# =============================================================================

def _cur_fetchall(table):
    """Devuelve todos los registros de una tabla (simula cur.fetchall())."""
    tables = {
        "countries":               COUNTRIES,
        "states":                  STATES,
        "municipalities":          MUNICIPALITIES,
        "neighborhoods":           NEIGHBORHOODS,
        "addresses":               ADDRESSES,
        "clinics":                 CLINICS,
        "clinic_areas":            CLINIC_AREAS,
        "roles":                   ROLES,
        "workers":                 WORKERS,
        "worker_professional":     WORKER_PROFESSIONAL,
        "worker_clinic_assignments": WORKER_CLINIC_ASSIGNMENTS,
        "worker_schedules":        WORKER_SCHEDULES,
        "guardians":               GUARDIANS,
        "guardian_phones":         GUARDIAN_PHONES,
        "guardian_emails":         GUARDIAN_EMAILS,
        "patients":                PATIENTS,
        "patient_allergies":       PATIENT_ALLERGIES,
        "vaccines":                VACCINES,
        "vaccine_lots":            VACCINE_LOTS,
        "applications":            APPLICATIONS,
        "scheme":                  SCHEME,
        "scheme_completion_alerts": SCHEME_COMPLETION_ALERTS,
        "appointments":            APPOINTMENTS,
        "nfc_cards":               NFC_CARDS,
        "nfc_scan_events":         NFC_SCAN_EVENTS,
        "gps_devices":             GPS_DEVICES,
        "gps_risk_alerts":         GPS_RISK_ALERTS,
        "gps_safe_zones":          GPS_SAFE_ZONES,
        "supply_catalog":          SUPPLY_CATALOG,
        "clinic_inventory":        CLINIC_INVENTORY,
        "zones":                   ZONES,
    }
    return list(tables.get(table, []))


def _cur_fetchone(table, pk_field, pk_value):
    """Devuelve el primer registro que coincida con la PK (simula cur.fetchone())."""
    return next((row for row in _cur_fetchall(table) if row.get(pk_field) == pk_value), None)


def _cur_fetchall_where(table, field, value):
    """Devuelve todos los registros filtrados por un campo (simula WHERE simple)."""
    return [row for row in _cur_fetchall(table) if row.get(field) == value]


# 
# HELPERS — sesión, formateo, ids
# =============================================================================

def _require_login():
    if "user_name" not in session:
        flash("Debes iniciar sesión para continuar.", "warning")
        return redirect(url_for("login"))
    return None


def _session_vars():
    first = session.get("user_name", "")
    last  = session.get("user_lastname", "")
    initials = ((first[:1] + last[:1]).upper()) or "AD"
    return {
        "name":     first,
        "lastname": last,
        "role":     session.get("role", "Administrador"),
        "worker_id": session.get("worker_id"),
        "initials": initials,
    }


def _age_years(birth_date_str):
    try:
        b = datetime.strptime(birth_date_str, "%Y-%m-%d").date()
    except (ValueError, TypeError):
        return 0
    today = date.today()
    years = today.year - b.year
    if (today.month, today.day) < (b.month, b.day):
        years -= 1
    return max(years, 0)


def _next_id(items, key):
    if not items:
        return 1
    return max(item[key] for item in items) + 1


def _patient_full_name(patient):
    parts = [patient.get("first_name", ""), patient.get("last_name", ""), patient.get("second_last") or ""]
    return " ".join(p for p in parts if p).strip()


def _worker_full_name(worker_id):
    w = _cur_fetchone("workers", "worker_id", worker_id)
    if not w:
        return "Personal demo"
    return f"{w['first_name']} {w['last_name']}".strip()


def _guardian_full_name(guardian_id):
    g = _cur_fetchone("guardians", "guardian_id", guardian_id)
    if not g:
        return "Tutor no registrado"
    return f"{g['first_name']} {g['last_name']}".strip()


def _guardian_primary_phone(guardian_id):
    phones = _cur_fetchall_where("guardian_phones", "guardian_id", guardian_id)
    primary = next((p for p in phones if p.get("is_primary")), None)
    return (primary or phones[0])["phone"] if phones else "—"


def _vaccine_name(vaccine_id):
    v = _cur_fetchone("vaccines", "vaccine_id", vaccine_id)
    return v["name"] if v else "Vacuna desconocida"


def _enrich_patient(p):
    """Agrega campos calculados y relacionados a un paciente."""
    item = dict(p)
    item["full_name"]  = _patient_full_name(p)
    item["age"]        = _age_years(p["birth_date"])
    item["guardian"]   = _guardian_full_name(p["guardian_id"])
    item["contact"]    = _guardian_primary_phone(p["guardian_id"])
    item["allergies"]  = ", ".join(
        a["allergen"] for a in _cur_fetchall_where("patient_allergies", "patient_id", p["patient_id"])
    ) or "Ninguna"
    item["risk"]       = p.get("risk_level", "bajo")
    return item


def _enrich_application(a):
    """Agrega nombres legibles a un registro de vacunación."""
    item = dict(a)
    item["patient_name"] = _patient_full_name(
        _cur_fetchone("patients", "patient_id", a["patient_id"]) or {}
    )
    item["name"]   = _vaccine_name(a["vaccine_id"])
    item["doctor"] = _worker_full_name(a["applied_by"])
    item["date"]   = a["applied_date"]
    item["next_date"] = a.get("next_dose_date")
    item["dose"]   = a["dose_applied"]
    item["notes"]  = a.get("notes", "")
    item["id"]     = a["record_id"]
    return item


# =============================================================================
# RUTAS
# =============================================================================

@app.route("/")
def home():
    return redirect(url_for("login"))


# ── LOGIN / LOGOUT ────────────────────────────────────────────────────────────
@app.route("/login", methods=["GET", "POST"])
def login():
    if "user_name" in session:
        return redirect(url_for("dashboard"))

    if request.method == "POST":
        mail     = (request.form.get("mail") or "").strip()
        password = request.form.get("password") or ""
        user     = USERS.get(mail)

        if user and user["password"] == password:
            session["user_name"]     = user["name"]
            session["user_lastname"] = user["lastname"]
            session["role"]          = user["role"]
            session["worker_id"]     = user["worker_id"]
            flash(f"Bienvenido, {user['name']}.", "success")
            return redirect(url_for("dashboard"))

        flash("Credenciales inválidas. Usa admin / 123", "danger")

    return render_template("login_2daE.html")


@app.route("/logout")
def logout():
    nombre = session.get("user_name", "")
    session.clear()
    flash(f"Sesión de {nombre} cerrada correctamente.", "info")
    return redirect(url_for("login"))


# ── DASHBOARD ─────────────────────────────────────────────────────────────────
@app.route("/dashboard")
def dashboard():
    locked = _require_login()
    if locked:
        return locked

    # cur.fetchall() simulado
    patients_raw  = _cur_fetchall("patients")
    vaccines_raw  = _cur_fetchall("vaccines")
    apps_raw      = _cur_fetchall("applications")
    alerts_raw    = _cur_fetchall("gps_risk_alerts")
    inventory_raw = _cur_fetchall("clinic_inventory")

    # Estadísticas de inventario bajo
    low_stock = [i for i in inventory_raw if i["quantity"] < i["min_stock"]]

    top_patients = [_enrich_patient(p) for p in patients_raw[:3]]

    # KPIs de sesión
    session["last_visit"] = date.today().isoformat()

    ctx = {
        **_session_vars(),
        "today":              date.today().strftime("%d/%m/%Y"),
        "total_patients":     len(patients_raw),
        "total_vaccines":     len(vaccines_raw),
        "applications_today": sum(
            1 for a in apps_raw if a["applied_date"] == date.today().isoformat()
        ),
        "pending_alerts":     len([al for al in alerts_raw if al["resolved_at"] is None]),
        "low_stock_count":    len(low_stock),
        "top_patients":       top_patients,
        "dashboard_vaccines": vaccines_raw[:3],
    }
    return render_template("index_2daE.html", **ctx)


# ── PACIENTES ─────────────────────────────────────────────────────────────────
@app.route("/pacientes")
def pacientes():
    locked = _require_login()
    if locked:
        return locked

    # cur.fetchall() simulado
    patients_raw = _cur_fetchall("patients")
    patients     = [_enrich_patient(p) for p in patients_raw]

    return render_template(
        "pacientes_2daE.html",
        **_session_vars(),
        total_patients=len(patients),
        patients=patients,
    )


@app.route("/register_patient", methods=["POST"])
def register_patient():
    locked = _require_login()
    if locked:
        return jsonify({"error": "No autenticado"}), 401

    payload = request.get_json(silent=True) or {}
    tutor   = payload.get("tutor") or {}

    first_name = (payload.get("first_name") or "").strip()
    last_name  = (payload.get("last_name")  or "").strip()
    if not first_name or not last_name:
        return jsonify({"error": "Nombre y apellido son requeridos"}), 400

    # Simular INSERT en guardians
    new_guardian_id = _next_id(GUARDIANS, "guardian_id")
    GUARDIANS.append({
        "guardian_id":   new_guardian_id,
        "first_name":    (tutor.get("name")     or "Tutor").strip(),
        "last_name":     (tutor.get("lastname")  or "Demo").strip(),
        "second_last":   None,
        "curp":          None,
        "address_id":    None,
        "marital_status": None,
        "occupation":    None,
        "created_at":    date.today().isoformat(),
    })
    if tutor.get("number"):
        GUARDIAN_PHONES.append({
            "phone_id":   _next_id(GUARDIAN_PHONES, "phone_id"),
            "guardian_id": new_guardian_id,
            "phone":       tutor["number"],
            "phone_type":  "Celular",
            "is_primary":  True,
        })

    # Simular INSERT en patients
    new_pid = _next_id(PATIENTS, "patient_id")
    PATIENTS.append({
        "patient_id":   new_pid,
        "first_name":   first_name,
        "last_name":    last_name,
        "second_last":  None,
        "curp":         payload.get("curp"),
        "birth_date":   payload.get("birth_date") or "2021-01-01",
        "gender":       payload.get("gender") or "M",
        "blood_type":   payload.get("blood_type") or "O+",
        "nfc_token":    f"NFC{new_pid:03d}",
        "guardian_id":  new_guardian_id,
        "address_id":   None,
        "risk_level":   "bajo",
        "is_active":    True,
        "registered_at": date.today().isoformat(),
    })

    flash(f"Paciente {first_name} {last_name} registrado correctamente.", "success")
    return jsonify({"message": "Paciente registrado (demo)", "patient_id": new_pid})


@app.route("/delete_patient/<int:id>", methods=["POST"])
def delete_patient(id):
    locked = _require_login()
    if locked:
        return jsonify({"error": "No autenticado"}), 401

    # cur.fetchone() simulado
    patient = _cur_fetchone("patients", "patient_id", id)
    if not patient:
        return jsonify({"error": "Paciente no encontrado"}), 404

    PATIENTS.remove(patient)
    nombre = _patient_full_name(patient)

    for a in _cur_fetchall_where("applications", "patient_id", id):
        APPLICATIONS.remove(a)

    flash(f"Paciente {nombre} eliminado.", "warning")
    return jsonify({"message": "Paciente eliminado (demo)"})


# ── HISTORIAL ─────────────────────────────────────────────────────────────────
@app.route("/historial")
def historial():
    locked = _require_login()
    if locked:
        return locked

    patients_raw = _cur_fetchall("patients")
    patient      = _enrich_patient(patients_raw[0]) if patients_raw else None
    apps_raw     = _cur_fetchall_where("applications", "patient_id", patient["patient_id"]) if patient else []
    apps         = [_enrich_application(a) for a in apps_raw]

    next_vaccines = [
        {"name": "Hepatitis B", "dose": "2", "date": "2025-06-10"},
        {"name": "Pentavalente", "dose": "3", "date": "2025-07-20"},
    ]
    return render_template(
        "historial_2daE.html",
        **_session_vars(),
        patients=[_enrich_patient(p) for p in patients_raw],
        patient=patient,
        applications=apps,
        next_vaccines=next_vaccines,
    )


@app.route("/historial/<int:id>")
def historial_paciente(id):
    locked = _require_login()
    if locked:
        return locked

    # cur.fetchone() + cur.fetchall() simulados
    patient_raw = _cur_fetchone("patients", "patient_id", id)
    if not patient_raw:
        flash("Paciente no encontrado.", "danger")
        return redirect(url_for("historial"))

    patient  = _enrich_patient(patient_raw)
    apps_raw = _cur_fetchall_where("applications", "patient_id", id)
    apps     = [_enrich_application(a) for a in apps_raw]

    next_vaccines = [
        {"name": "Refuerzo Pentavalente", "dose": "3", "date": "2025-08-15"},
        {"name": "Influenza",             "dose": "1", "date": "2025-09-01"},
    ]
    session["last_patient_viewed"] = id

    return render_template(
        "historial_2daE.html",
        **_session_vars(),
        patients=[_enrich_patient(p) for p in _cur_fetchall("patients")],
        patient=patient,
        applications=apps,
        next_vaccines=next_vaccines,
    )


# ── ESQUEMA PACIENTE ──────────────────────────────────────────────────────────
@app.route("/esquema_paciente/<int:id>")
def esquema_paciente(id):
    locked = _require_login()
    if locked:
        return locked

    patient_raw = _cur_fetchone("patients", "patient_id", id)
    if not patient_raw:
        flash("Paciente no encontrado.", "danger")
        return redirect(url_for("historial"))

    patient  = _enrich_patient(patient_raw)
    apps_raw = _cur_fetchall_where("applications", "patient_id", id)
    apps     = [_enrich_application(a) for a in apps_raw]
    next_vaccines = [
        {"name": "Hepatitis B",  "dose": "Dosis 2", "date": "2025-06-10"},
        {"name": "Pentavalente", "dose": "Dosis 3",  "date": "2025-07-20"},
    ]

    return render_template(
        "esquemaPaciente_2daE.html",
        **_session_vars(),
        patient=patient,
        patient_name=patient["full_name"],
        applications=apps,
        next_vaccines=next_vaccines,
    )


# ── ESQUEMA VACUNACIÓN ────────────────────────────────────────────────────────
@app.route("/esquema")
def esquema_vacunacion():
    locked = _require_login()
    if locked:
        return locked

    return render_template(
        "esquemaVacunacion_2daE.html",
        **_session_vars(),
        esquema=_cur_fetchall("scheme"),
    )


# ── VACUNAS ───────────────────────────────────────────────────────────────────
@app.route("/vacunas")
def vacunas_page():
    locked = _require_login()
    if locked:
        return locked

    vaccines = _cur_fetchall("vaccines")
    lots     = _cur_fetchall("vaccine_lots")

    # Agregar stock total por vacuna desde lotes activos
    for v in vaccines:
        v["inventory"] = sum(
            l["quantity_remaining"]
            for l in lots
            if l["vaccine_id"] == v["vaccine_id"] and l["is_active"]
        )

    return render_template(
        "vacunas_2daE.html",
        **_session_vars(),
        total_vaccines=len(vaccines),
        vaccines=vaccines,
        lots=lots,
    )


@app.route("/register_vaccine", methods=["POST"])
def register_vaccine():
    locked = _require_login()
    if locked:
        return jsonify({"error": "No autenticado"}), 401

    payload = request.get_json(silent=True) or {}
    name    = (payload.get("name") or "").strip()
    if not name:
        return jsonify({"error": "El nombre de vacuna es requerido"}), 400

    new_vid = _next_id(VACCINES, "vaccine_id")
    VACCINES.append({
        "vaccine_id":             new_vid,
        "name":                   name,
        "disease_target":         payload.get("disease_target") or "No especificado",
        "manufacturer":           payload.get("manufacturer") or "Sin fabricante",
        "recommended_age_months": payload.get("recommended_age_months"),
        "doses_required":         int(payload.get("doses_required") or 1),
        "interval_days":          payload.get("interval_days"),
        "route":                  payload.get("route") or "Intramuscular",
        "is_active":              True,
    })
    flash(f"Vacuna '{name}' registrada.", "success")
    return jsonify({"message": "Vacuna registrada (demo)", "vaccine_id": new_vid})


@app.route("/delete_vaccine/<int:id>", methods=["POST"])
def delete_vaccine(id):
    locked = _require_login()
    if locked:
        return jsonify({"error": "No autenticado"}), 401

    vaccine = _cur_fetchone("vaccines", "vaccine_id", id)
    if not vaccine:
        return jsonify({"error": "Vacuna no encontrada"}), 404

    VACCINES.remove(vaccine)
    flash(f"Vacuna '{vaccine['name']}' eliminada.", "warning")
    return jsonify({"message": "Vacuna eliminada (demo)"})


# ── APLICACIONES ──────────────────────────────────────────────────────────────
@app.route("/aplicaciones")
def aplicaciones():
    locked = _require_login()
    if locked:
        return locked

    apps_raw          = _cur_fetchall("applications")
    apps              = [_enrich_application(a) for a in apps_raw]
    unique_patients   = len(set(a["patient_id"] for a in apps_raw))
    unique_vaccines   = len(set(a["vaccine_id"] for a in apps_raw))
    applications_today = sum(
        1 for a in apps_raw if a["applied_date"] == date.today().isoformat()
    )

    return render_template(
        "aplicaciones_2daE.html",
        **_session_vars(),
        total_applications=len(apps),
        total_patients_attended=unique_patients,
        total_unique_vaccines=unique_vaccines,
        applications_today=applications_today,
        applications=apps,
    )


@app.route("/agregar_aplicacion", methods=["GET", "POST"])
def agregar_aplicacion():
    locked = _require_login()
    if locked:
        return locked

    form  = {}
    error = None

    if request.method == "POST":
        form = dict(request.form)
        try:
            patient_id = int(request.form.get("patient_id", "0"))
            vaccine_id = int(request.form.get("vaccine_id", "0"))
            worker_id  = int(request.form.get("worker_id",  "0"))
        except ValueError:
            error = "IDs inválidos"
        else:
            # cur.fetchone() simulado
            patient = _cur_fetchone("patients", "patient_id", patient_id)
            vaccine = _cur_fetchone("vaccines",  "vaccine_id", vaccine_id)
            if not patient or not vaccine:
                error = "Paciente o vacuna no encontrados"
            else:
                new_record = {
                    "record_id":      _next_id(APPLICATIONS, "record_id"),
                    "patient_id":     patient_id,
                    "vaccine_id":     vaccine_id,
                    "lot_id":         None,
                    "clinic_id":      1,
                    "applied_by":     worker_id or session.get("worker_id", 1),
                    "applied_date":   request.form.get("applied_date") or date.today().isoformat(),
                    "dose_applied":   request.form.get("dose_applied") or "1",
                    "next_dose_date": None,
                    "clinic_location": request.form.get("clinic_location") or "Consultorio",
                    "notes":          request.form.get("notes") or "",
                }
                APPLICATIONS.insert(0, new_record)
                flash(
                    f"Aplicación de {vaccine['name']} registrada para "
                    f"{_patient_full_name(patient)}.",
                    "success",
                )
                return redirect(url_for("aplicaciones"))

    return render_template(
        "agregarAplicacion_2daE.html",
        **_session_vars(),
        patients=_cur_fetchall("patients"),
        vaccines=_cur_fetchall("vaccines"),
        workers=_cur_fetchall("workers"),
        form=form,
        error=error,
    )


# ── PERSONAL ──────────────────────────────────────────────────────────────────
@app.route("/personal")
def personal():
    locked = _require_login()
    if locked:
        return locked

    # cur.fetchall() simulado con join roles
    workers_raw = _cur_fetchall("workers")
    workers = []
    for w in workers_raw:
        row = dict(w)
        role = _cur_fetchone("roles", "role_id", w["role_id"])
        row["role"]     = role["name"] if role else "Sin rol"
        row["name"]     = w["first_name"]
        row["lastname"] = w["last_name"]
        row["mail"]     = w["email"]
        workers.append(row)

    return render_template(
        "personal_2daE.html",
        **_session_vars(),
        workers=workers,
        total_workers=len(workers),
        roles=_cur_fetchall("roles"),
    )


@app.route("/personal/agregar", methods=["GET", "POST"])
def add_user():
    locked = _require_login()
    if locked:
        return locked

    form  = {}
    error = None

    if request.method == "POST":
        form     = dict(request.form)
        password = request.form.get("password") or ""
        confirm  = request.form.get("password_confirm") or ""
        mail     = (request.form.get("mail") or "").strip()

        if password != confirm:
            error = "Las contraseñas no coinciden"
            flash(error, "danger")
        elif any((w.get("email") or "").lower() == mail.lower() for w in WORKERS):
            error = "El email ya existe en el sistema"
            flash(error, "danger")
        else:
            role_id = int(request.form.get("role_id") or 3)
            new_wid = _next_id(WORKERS, "worker_id")
            WORKERS.append({
                "worker_id":   new_wid,
                "role_id":     role_id,
                "first_name":  request.form.get("name", ""),
                "last_name":   request.form.get("lastname", ""),
                "second_last": None,
                "curp":        None,
                "email":       mail,
                "phone":       request.form.get("phone"),
                "address_id":  None,
                "birth_date":  None,
                "hire_date":   date.today().isoformat(),
                "is_active":   True,
                "password_hash": f"hash:{password}",
                "created_at":  datetime.now().isoformat(),
                "updated_at":  datetime.now().isoformat(),
            })
            # Guardar en sesión el último trabajador registrado
            session["last_registered_worker"] = new_wid
            flash(
                f"Usuario {request.form.get('name', '')} registrado correctamente.",
                "success",
            )
            return redirect(url_for("personal"))

    return render_template(
        "add_user_2daE.html",
        **_session_vars(),
        form=form,
        error=error,
        roles=_cur_fetchall("roles"),
    )


# ── MAPA DE RIESGO ────────────────────────────────────────────────────────────
@app.route("/mapa-riesgo")
def mapa_riesgo():
    locked = _require_login()
    if locked:
        return locked

    zones  = _cur_fetchall("zones")
    alerts = _cur_fetchall("gps_risk_alerts")

    high   = sum(1 for z in zones if z["risk"] == "high")
    medium = sum(1 for z in zones if z["risk"] == "medium")
    low    = sum(1 for z in zones if z["risk"] == "low")

    # Alertas GPS activas (sin resolver)
    active_gps_alerts = [a for a in alerts if a["resolved_at"] is None]

    return render_template(
        "mapaRiesgo_2daE.html",
        **_session_vars(),
        high_risk_count=high,
        medium_risk_count=medium,
        low_risk_count=low,
        zones=zones,
        gps_alerts=active_gps_alerts,
        safe_zones=_cur_fetchall("gps_safe_zones"),
    )


# ── REPORTES PÚBLICOS ─────────────────────────────────────────────────────────
@app.route("/reportes-publicos")
def reportes_publicos():
    locked = _require_login()
    if locked:
        return locked
    return render_template("reportesPublicos_2daE.html", **_session_vars())


# ── INVENTARIO ────────────────────────────────────────────────────────────────
@app.route("/inventario")
def inventario():
    locked = _require_login()
    if locked:
        return locked

    inventory_raw = _cur_fetchall("clinic_inventory")
    inventory = []
    for row in inventory_raw:
        item    = dict(row)
        supply  = _cur_fetchone("supply_catalog", "supply_id", row["supply_id"])
        clinic  = _cur_fetchone("clinics",        "clinic_id", row["clinic_id"])
        item["supply_name"]    = supply["name"]    if supply else "—"
        item["supply_unit"]    = supply["unit"]    if supply else "—"
        item["supply_category"] = supply["category"] if supply else "—"
        item["clinic_name"]    = clinic["name"]    if clinic else "—"
        item["low_stock"]      = row["quantity"] < row["min_stock"]
        inventory.append(item)

    if any(i["low_stock"] for i in inventory):
        flash("⚠ Hay insumos con stock por debajo del mínimo.", "warning")

    return render_template(
        "inventario_2daE.html",
        **_session_vars(),
        inventory=inventory,
        supply_catalog=_cur_fetchall("supply_catalog"),
        clinics=_cur_fetchall("clinics"),
    )


# ── CITAS ─────────────────────────────────────────────────────────────────────
@app.route("/citas")
def citas():
    locked = _require_login()
    if locked:
        return locked

    appointments_raw = _cur_fetchall("appointments")
    appointments = []
    for ap in appointments_raw:
        item = dict(ap)
        patient = _cur_fetchone("patients", "patient_id", ap["patient_id"])
        worker  = _cur_fetchone("workers",  "worker_id",  ap["worker_id"])
        vaccine = _cur_fetchone("vaccines", "vaccine_id", ap["vaccine_id"])
        clinic  = _cur_fetchone("clinics",  "clinic_id",  ap["clinic_id"])
        item["patient_name"] = _patient_full_name(patient) if patient else "—"
        item["worker_name"]  = f"{worker['first_name']} {worker['last_name']}" if worker else "—"
        item["vaccine_name"] = vaccine["name"] if vaccine else "—"
        item["clinic_name"]  = clinic["name"]  if clinic  else "—"
        appointments.append(item)

    # Guardar en sesión la última vista
    session["last_section"] = "citas"

    return render_template(
        "citas_2daE.html",
        **_session_vars(),
        appointments=appointments,
        total_appointments=len(appointments),
        patients=_cur_fetchall("patients"),
        vaccines=_cur_fetchall("vaccines"),
        workers=_cur_fetchall("workers"),
        clinics=_cur_fetchall("clinics"),
    )


# ── NFC ───────────────────────────────────────────────────────────────────────
@app.route("/nfc")
def nfc():
    locked = _require_login()
    if locked:
        return locked

    cards_raw = _cur_fetchall("nfc_cards")
    cards = []
    for c in cards_raw:
        item    = dict(c)
        patient = _cur_fetchone("patients", "patient_id", c["patient_id"])
        item["patient_name"] = _patient_full_name(patient) if patient else "—"
        cards.append(item)

    scan_events_raw = _cur_fetchall("nfc_scan_events")
    scans = []
    for s in scan_events_raw:
        item = dict(s)
        item["worker_name"] = _worker_full_name(s["scanned_by"])
        card    = _cur_fetchone("nfc_cards", "nfc_card_id", s["nfc_card_id"])
        patient = _cur_fetchone("patients", "patient_id", card["patient_id"]) if card else None
        item["patient_name"] = _patient_full_name(patient) if patient else "—"
        scans.append(item)

    return render_template(
        "nfc_2daE.html",
        **_session_vars(),
        cards=cards,
        scans=scans,
        total_cards=len(cards),
        active_cards=sum(1 for c in cards_raw if c["status"] == "Activa"),
    )


# ── GPS / ALERTAS ─────────────────────────────────────────────────────────────
@app.route("/gps")
def gps():
    locked = _require_login()
    if locked:
        return locked

    devices_raw = _cur_fetchall("gps_devices")
    devices = []
    for d in devices_raw:
        item    = dict(d)
        patient = _cur_fetchone("patients", "patient_id", d["patient_id"])
        item["patient_name"] = _patient_full_name(patient) if patient else "—"
        devices.append(item)

    alerts_raw = _cur_fetchall("gps_risk_alerts")
    alerts = []
    for a in alerts_raw:
        item    = dict(a)
        patient = _cur_fetchone("patients", "patient_id", a["patient_id"])
        item["patient_name"]  = _patient_full_name(patient) if patient else "—"
        item["resolved_name"] = _worker_full_name(a["resolved_by"]) if a["resolved_by"] else "Pendiente"
        alerts.append(item)

    active_alerts = [a for a in alerts if a["resolved_at"] is None]
    if active_alerts:
        flash(f"Tienes {len(active_alerts)} alerta(s) GPS sin resolver.", "danger")

    return render_template(
        "gps_2daE.html",
        **_session_vars(),
        devices=devices,
        alerts=alerts,
        active_alerts_count=len(active_alerts),
        safe_zones=_cur_fetchall("gps_safe_zones"),
    )


# ── CLÍNICAS ──────────────────────────────────────────────────────────────────
@app.route("/clinicas")
def clinicas():
    locked = _require_login()
    if locked:
        return locked

    clinics_raw = _cur_fetchall("clinics")
    clinics = []
    for c in clinics_raw:
        item    = dict(c)
        address = _cur_fetchone("addresses", "address_id", c["address_id"])
        if address:
            nbhd   = _cur_fetchone("neighborhoods", "neighborhood_id", address["neighborhood_id"])
            item["address_str"] = f"{address['street']} {address['ext_number'] or ''}, {nbhd['name'] if nbhd else ''}".strip(", ")
        else:
            item["address_str"] = "—"
        item["areas"] = _cur_fetchall_where("clinic_areas", "clinic_id", c["clinic_id"])
        clinics.append(item)

    return render_template(
        "clinicas_2daE.html",
        **_session_vars(),
        clinics=clinics,
        total_clinics=len(clinics),
    )


# =============================================================================
# APIs JSON
# =============================================================================

@app.route("/api/global-search")
def api_global_search():
    locked = _require_login()
    if locked:
        return jsonify({"results": []})

    q = (request.args.get("q") or "").strip().lower()
    if not q:
        return jsonify({"results": []})

    results = []

    for p in _cur_fetchall("patients"):
        full = _patient_full_name(p)
        if q in full.lower() or q in str(p["patient_id"]):
            results.append({
                "type":     "paciente",
                "title":    full,
                "subtitle": f"ID: P{p['patient_id']}",
                "url":      url_for("historial_paciente", id=p["patient_id"]),
            })

    for v in _cur_fetchall("vaccines"):
        if q in v["name"].lower() or q in str(v["vaccine_id"]):
            lot_stock = sum(
                l["quantity_remaining"]
                for l in _cur_fetchall_where("vaccine_lots", "vaccine_id", v["vaccine_id"])
                if l["is_active"]
            )
            results.append({
                "type":     "vacuna",
                "title":    v["name"],
                "subtitle": f"Stock: {lot_stock}",
                "url":      url_for("vacunas_page") + f"?q={v['name']}",
            })

    for w in _cur_fetchall("workers"):
        name = f"{w['first_name']} {w['last_name']}".strip()
        if q in name.lower() or q in (w.get("email") or "").lower():
            role = _cur_fetchone("roles", "role_id", w["role_id"])
            results.append({
                "type":     "personal",
                "title":    name,
                "subtitle": role["name"] if role else "",
                "url":      url_for("personal") + f"?q={name}",
            })

    return jsonify({"results": results[:10]})


@app.route("/api/reportes-publicos/resumen")
def api_reportes_publicos_resumen():
    locked = _require_login()
    if locked:
        return jsonify({"error": "No autenticado"}), 401

    apps_raw        = _cur_fetchall("applications")
    patients_raw    = _cur_fetchall("patients")
    total_doses     = len(apps_raw)
    reached_pop     = len(set(a["patient_id"] for a in apps_raw))
    target_pop      = max(len(patients_raw), 1)
    coverage        = (reached_pop / target_pop) * 100

    monthly = [
        {"period_label": "2026-01", "doses_applied": 1, "unique_patients": 1},
        {"period_label": "2026-02", "doses_applied": 1, "unique_patients": 1},
        {"period_label": "2026-03", "doses_applied": 3, "unique_patients": 3},
    ]

    vax_count  = {}
    vax_people = {}
    for a in apps_raw:
        vname = _vaccine_name(a["vaccine_id"])
        vax_count[vname]  = vax_count.get(vname, 0) + 1
        vax_people.setdefault(vname, set()).add(a["patient_id"])

    vaccines_summary = [
        {
            "vaccine_name":    name,
            "doses_applied":   doses,
            "unique_patients": len(vax_people[name]),
            "share_percent":   round(doses / total_doses * 100, 1) if total_doses else 0,
        }
        for name, doses in vax_count.items()
    ]

    zones_raw = _cur_fetchall("zones")
    zones_summary = [
        {
            "zone_name":      z["name"],
            "doses_applied":  z["cases"],
            "unique_patients": z["cases"],
            "risk_level":     z["risk"],
            "risk_label":     {"high": "Alto", "medium": "Medio", "low": "Bajo"}.get(z["risk"], "—"),
        }
        for z in zones_raw
    ]

    payload = {
        "kpis": {
            "total_doses_applied": total_doses,
            "target_population":   target_pop,
            "reached_population":  reached_pop,
            "coverage_percent":    round(coverage, 1),
            "avg_delay_days":      5.0,
            "active_zones":        len(zones_raw),
        },
        "monthly":  monthly,
        "vaccines": vaccines_summary,
        "zones":    zones_summary,
    }
    return jsonify(payload)


# ── Alertas de esquema incompleto (API) ───────────────────────────────────────
@app.route("/api/alertas-esquema")
def api_alertas_esquema():
    locked = _require_login()
    if locked:
        return jsonify({"error": "No autenticado"}), 401

    alerts_raw = _cur_fetchall("scheme_completion_alerts")
    result = []
    for al in alerts_raw:
        patient = _cur_fetchone("patients", "patient_id", al["patient_id"])
        result.append({
            **al,
            "patient_name":  _patient_full_name(patient) if patient else "—",
            "vaccine_name":  _vaccine_name(al["vaccine_id"]),
        })
    return jsonify(result)


if __name__ == "__main__":
    app.run(debug=True)