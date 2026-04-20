from datetime import date, datetime, timedelta
from calendar import month_abbr
from flask import Flask, flash, jsonify, redirect, render_template, request, session, url_for

app = Flask(__name__)
app.secret_key = "segunda-entrega-demo"


# DATOS HARDCODEADOS  (simulan lo que devolvería PostgreSQL)

# --- ADDRESSES -----------------------------------------------------------
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
    {"neighborhood_id": 1, "municipality_id": 1, "name": "Centro",     "zip_code": "64000"},
    {"neighborhood_id": 2, "municipality_id": 1, "name": "Obispado",   "zip_code": "64010"},
    {"neighborhood_id": 3, "municipality_id": 2, "name": "Topo Chico", "zip_code": "64260"},
]

# cross_street_2 fue eliminada del schema
ADDRESSES = [
    {"address_id": 1, "neighborhood_id": 1, "street": "Av. Constitución", "ext_number": "100", "cross_street_1": "Juárez",  "latitude": 25.6700, "longitude": -100.3099},
    {"address_id": 2, "neighborhood_id": 2, "street": "Calle Obispado",   "ext_number": "45",  "cross_street_1": "Hidalgo", "latitude": 25.6780, "longitude": -100.3200},
    {"address_id": 3, "neighborhood_id": 3, "street": "Blvd. Díaz Ordaz", "ext_number": "500", "cross_street_1": "Morones", "latitude": 25.7050, "longitude": -100.3500},
]

# --- CLINICS -------------------------------------------------------------
# clues fue eliminada del schema
CLINICS = [
    {"clinic_id": 1, "name": "Centro de Salud Centro",  "address_id": 1, "phone": "8112223344", "institution_type": "SSA",  "is_active": True},
    {"clinic_id": 2, "name": "Unidad Médica Obispado",  "address_id": 2, "phone": "8118887766", "institution_type": "IMSS", "is_active": True},
    {"clinic_id": 3, "name": "Clínica DIF Guadalupe",   "address_id": 3, "phone": "8191234567", "institution_type": "DIF",  "is_active": True},
]

# area_type ahora es FK a area_types
AREA_TYPES = [
    {"area_type_id": 1, "area_type": "Recepcion"},
    {"area_type_id": 2, "area_type": "Sala_Espera"},
    {"area_type_id": 3, "area_type": "Consultorio"},
    {"area_type_id": 4, "area_type": "Enfermeria"},
    {"area_type_id": 5, "area_type": "Almacen"},
]

CLINIC_AREAS = [
    {"area_id": 1, "clinic_id": 1, "name": "Recepción",      "area_type_id": 1, "floor": 1, "capacity": 20},
    {"area_id": 2, "clinic_id": 1, "name": "Sala de Espera", "area_type_id": 2, "floor": 1, "capacity": 40},
    {"area_id": 3, "clinic_id": 1, "name": "Consultorio 1",  "area_type_id": 3, "floor": 1, "capacity": 5},
    {"area_id": 4, "clinic_id": 2, "name": "Enfermería A",   "area_type_id": 4, "floor": 1, "capacity": 10},
    {"area_id": 5, "clinic_id": 3, "name": "Almacén Central","area_type_id": 5, "floor": 1, "capacity": None},
]

EQUIPMENT_CATALOG = [
    {"equipment_id": 1, "name": "Refrigerador de vacunas", "category": "Refrigeración", "requires_calibration": True},
    {"equipment_id": 2, "name": "Termómetro digital",      "category": "Medición",      "requires_calibration": True},
]

AREA_EQUIPMENT = [
    {"area_equipment_id": 1, "area_id": 3, "equipment_id": 1, "quantity": 1, "serial_number": "SER-001", "condition": "Bueno"},
    {"area_equipment_id": 2, "area_id": 4, "equipment_id": 2, "quantity": 2, "serial_number": None,      "condition": "Regular"},
]

# --- PATIENTS ------------------------------------------------------------
# Normalizado: second_last, address_id, risk_level, is_active, registered_at eliminados
# blood_type_id ahora es FK; agregados weight_kg y premature
BLOOD_TYPES = [
    {"blood_type_id": 1, "blood_type": "O+"},
    {"blood_type_id": 2, "blood_type": "A+"},
    {"blood_type_id": 3, "blood_type": "B+"},
    {"blood_type_id": 4, "blood_type": "AB+"},
    {"blood_type_id": 5, "blood_type": "O-"},
    {"blood_type_id": 6, "blood_type": "A-"},
    {"blood_type_id": 7, "blood_type": "B-"},
    {"blood_type_id": 8, "blood_type": "AB-"},
]

PATIENTS = [
    {"patient_id": 1, "first_name": "Ana",     "last_name": "Martínez", "curp": "MASA200515MNLRTN09", "birth_date": "2020-05-15", "gender": "F", "blood_type_id": 1, "nfc_token": "NFC001", "weight_kg": 12.5, "premature": False},
    {"patient_id": 2, "first_name": "Carlos",  "last_name": "Sánchez",  "curp": "SARC190308HNLNRL05", "birth_date": "2019-03-08", "gender": "M", "blood_type_id": 2, "nfc_token": "NFC002", "weight_kg": 15.0, "premature": False},
    {"patient_id": 3, "first_name": "Daniela", "last_name": "López",    "curp": "LOJD221003MNLPJN07", "birth_date": "2022-10-03", "gender": "F", "blood_type_id": 3, "nfc_token": "NFC003", "weight_kg": 10.2, "premature": True},
    {"patient_id": 4, "first_name": "Miguel",  "last_name": "Flores",   "curp": "FOCM210720HNLLRG04", "birth_date": "2021-07-20", "gender": "M", "blood_type_id": 4, "nfc_token": "NFC004", "weight_kg": 13.8, "premature": False},
]

# allergies ahora es catálogo normalizado
ALLERGIES = [
    {"allergy_id": 1, "name": "Polen",      "allergy_type": "Ambiental"},
    {"allergy_id": 2, "name": "Penicilina", "allergy_type": "Medicamento"},
    {"allergy_id": 3, "name": "Látex",      "allergy_type": "Contacto"},
]

# patient_allergies ahora referencia allergy_id en vez de guardar allergen/reaction directo
PATIENT_ALLERGIES = [
    {"patient_allergy_id": 1, "patient_id": 2, "allergy_id": 1, "severity": "Leve",     "reaction_desc": "Rinitis"},
    {"patient_allergy_id": 2, "patient_id": 3, "allergy_id": 2, "severity": "Moderada", "reaction_desc": "Urticaria – evitar derivados"},
    {"patient_allergy_id": 3, "patient_id": 3, "allergy_id": 3, "severity": "Leve",     "reaction_desc": "Erupción"},
]

# --- GUARDIANS ----------------------------------------------------------
# marital_status y occupation ahora son tablas normalizadas
MARITAL_STATUS = [
    {"marital_status_id": 1, "marital_status": "Casado"},
    {"marital_status_id": 2, "marital_status": "Soltero"},
    {"marital_status_id": 3, "marital_status": "Union_Libre"},
    {"marital_status_id": 4, "marital_status": "Divorciado"},
    {"marital_status_id": 5, "marital_status": "Viudo"},
]

OCCUPATIONS = [
    {"occupation_id": 1, "occupation_name": "Profesora"},
    {"occupation_id": 2, "occupation_name": "Contador"},
    {"occupation_id": 3, "occupation_name": "Enfermera"},
]

# second_last eliminado; marital_status_id y occupation son FK int
GUARDIANS = [
    {"guardian_id": 1, "first_name": "María", "last_name": "Martínez", "curp": "MASM800501MNLRTRO8", "address_id": 1, "marital_status_id": 1, "occupation": 1},
    {"guardian_id": 2, "first_name": "Jorge", "last_name": "Sánchez",  "curp": "SARJ790320HNLNYR02", "address_id": 2, "marital_status_id": 2, "occupation": 2},
    {"guardian_id": 3, "first_name": "Laura", "last_name": "López",    "curp": "LOJL850715MNLPJR05", "address_id": 3, "marital_status_id": 3, "occupation": 3},
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

# Tabla nueva: relación paciente-tutor normalizada (antes era guardian_id directo en patients)
PATIENT_GUARDIAN_RELATIONS = [
    {"relation_id": 1, "patient_id": 1, "guardian_id": 1, "relation_type": "Madre",  "is_primary": True,  "has_custody": True},
    {"relation_id": 2, "patient_id": 2, "guardian_id": 2, "relation_type": "Padre",  "is_primary": True,  "has_custody": True},
    {"relation_id": 3, "patient_id": 3, "guardian_id": 3, "relation_type": "Madre",  "is_primary": True,  "has_custody": True},
    {"relation_id": 4, "patient_id": 4, "guardian_id": 1, "relation_type": "Madre",  "is_primary": True,  "has_custody": True},
]

# --- WORKERS ------------------------------------------------------------
# second_last, email, phone, is_active eliminados del workers principal
# email y teléfono ahora en worker_emails / worker_phones
# specialty normalizada en specialties / institutions
ROLES = [
    {"role_id": 1, "name": "Administrador", "description": "Acceso total al sistema"},
    {"role_id": 2, "name": "Médico",        "description": "Consulta y vacunación"},
    {"role_id": 3, "name": "Enfermero",     "description": "Aplicación de vacunas"},
    {"role_id": 4, "name": "Almacen",       "description": "Control de inventario"},
    {"role_id": 5, "name": "Recepcionista", "description": "Registro de llegadas"},
]

SPECIALTIES = [
    {"specialty_id": 1, "name": "Pediatría"},
    {"specialty_id": 2, "name": "Enfermería General"},
]

INSTITUTIONS = [
    {"institution_id": 1, "institution_name": "UANL",        "address_id": None},
    {"institution_id": 2, "institution_name": "TecSalud NL", "address_id": None},
]

WORKERS = [
    {"worker_id": 1, "role_id": 1, "first_name": "Admin",  "last_name": "Demo",   "curp": "ADMD800101HNLMMS09", "address_id": None, "birth_date": "1980-01-01", "hire_date": "2020-01-01", "password_hash": "hash:123"},
    {"worker_id": 2, "role_id": 3, "first_name": "Elena",  "last_name": "Garza",  "curp": "GALE900215MNLRZL05", "address_id": 1,    "birth_date": "1990-02-15", "hire_date": "2021-03-10", "password_hash": "hash:elena"},
    {"worker_id": 3, "role_id": 4, "first_name": "Mario",  "last_name": "Ruiz",   "curp": "RUPM850730HNLZXR08", "address_id": 2,    "birth_date": "1985-07-30", "hire_date": "2022-06-01", "password_hash": "hash:mario"},
    {"worker_id": 4, "role_id": 2, "first_name": "Sofía",  "last_name": "Torres", "curp": "TOVS920410MNLRRG06", "address_id": 3,    "birth_date": "1992-04-10", "hire_date": "2023-01-15", "password_hash": "hash:sofia"},
    {"worker_id": 5, "role_id": 5, "first_name": "Pedro",  "last_name": "Luna",   "curp": "LUMP781120HNLNND03", "address_id": 1,    "birth_date": "1978-11-20", "hire_date": "2020-09-05", "password_hash": "hash:pedro"},
]

WORKER_PHONES = [
    {"phone_id": 1, "worker_id": 2, "phone": "8111122334", "phone_type": "Celular", "is_primary": True},
    {"phone_id": 2, "worker_id": 3, "phone": "8199988776", "phone_type": "Celular", "is_primary": True},
    {"phone_id": 3, "worker_id": 4, "phone": "8115566778", "phone_type": "Celular", "is_primary": True},
    {"phone_id": 4, "worker_id": 5, "phone": "8182233445", "phone_type": "Celular", "is_primary": True},
]

WORKER_EMAILS = [
    {"email_id": 1, "worker_id": 1, "email": "admin",             "is_primary": True},
    {"email_id": 2, "worker_id": 2, "email": "elena@demo.local",  "is_primary": True},
    {"email_id": 3, "worker_id": 3, "email": "mario@demo.local",  "is_primary": True},
    {"email_id": 4, "worker_id": 4, "email": "sofia@demo.local",  "is_primary": True},
    {"email_id": 5, "worker_id": 5, "email": "pedro@demo.local",  "is_primary": True},
]

# specialty ahora referencia specialty_id e institution_id (FKs)
WORKER_PROFESSIONAL = [
    {"worker_id": 4, "cedula_profesional": "CED-1234567", "specialty_id": 1, "institution_id": 1},
    {"worker_id": 2, "cedula_profesional": "CED-9876543", "specialty_id": 2, "institution_id": 2},
]

# Renombrada: worker_clinic_assignments → worker_clinic_assignment (sin 's' final)
WORKER_CLINIC_ASSIGNMENT = [
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

# --- VACCINES -----------------------------------------------------------
# manufacturer, disease_target, route etc. normalizados a tablas propias
MANUFACTURERS = [
    {"manufacturer_id": 1, "name": "Biofabrica MX", "country_id": 1, "contact_email": None},
    {"manufacturer_id": 2, "name": "SaludVac",      "country_id": 1, "contact_email": None},
    {"manufacturer_id": 3, "name": "GSK",           "country_id": None, "contact_email": None},
    {"manufacturer_id": 4, "name": "MSD",           "country_id": None, "contact_email": None},
    {"manufacturer_id": 5, "name": "Sanofi",        "country_id": None, "contact_email": None},
]

VACCINE_VIAS = [
    {"via_id": 1, "via": "Intradérmica"},
    {"via_id": 2, "via": "Intramuscular"},
    {"via_id": 3, "via": "Oral"},
    {"via_id": 4, "via": "Subcutánea"},
]

# Campos eliminados: disease_target, recommended_age_months, doses_required, interval_days, route, is_active
VACCINES = [
    {"vaccine_id": 1, "name": "BCG",          "commercial_name": None,             "manufacturer_id": 1, "via_id": 1, "ideal_age_months": 0,  "disease_prevented": "Tuberculosis"},
    {"vaccine_id": 2, "name": "Hepatitis B",  "commercial_name": "Engerix-B",      "manufacturer_id": 2, "via_id": 2, "ideal_age_months": 0,  "disease_prevented": "Hepatitis B"},
    {"vaccine_id": 3, "name": "Pentavalente", "commercial_name": None,             "manufacturer_id": 3, "via_id": 2, "ideal_age_months": 2,  "disease_prevented": "Difteria/Tos/Tétanos"},
    {"vaccine_id": 4, "name": "Rotavirus",    "commercial_name": "RotaTeq",        "manufacturer_id": 4, "via_id": 3, "ideal_age_months": 2,  "disease_prevented": "Gastroenteritis"},
    {"vaccine_id": 5, "name": "Influenza",    "commercial_name": "Vaxigrip Tetra", "manufacturer_id": 5, "via_id": 2, "ideal_age_months": 6,  "disease_prevented": "Influenza estacional"},
]

# quantity_remaining → quantity_available; reception_date → received_date; is_active y received_by eliminados
VACCINE_LOTS = [
    {"lot_id": 1, "vaccine_id": 1, "clinic_id": 1, "lot_number": "LOT-BCG-2025-01", "quantity_received": 200, "quantity_available": 120, "expiration_date": "2026-06-30", "received_date": "2025-01-05"},
    {"lot_id": 2, "vaccine_id": 2, "clinic_id": 1, "lot_number": "LOT-HEB-2025-02", "quantity_received": 150, "quantity_available": 95,  "expiration_date": "2025-12-31", "received_date": "2025-01-10"},
    {"lot_id": 3, "vaccine_id": 3, "clinic_id": 1, "lot_number": "LOT-PEN-2025-03", "quantity_received": 100, "quantity_available": 80,  "expiration_date": "2026-03-15", "received_date": "2025-02-01"},
    {"lot_id": 4, "vaccine_id": 4, "clinic_id": 2, "lot_number": "LOT-ROT-2025-04", "quantity_received": 60,  "quantity_available": 30,  "expiration_date": "2025-08-01", "received_date": "2025-02-15"},
    {"lot_id": 5, "vaccine_id": 5, "clinic_id": 3, "lot_number": "LOT-INF-2024-09", "quantity_received": 300, "quantity_available": 0,   "expiration_date": "2025-06-30", "received_date": "2024-09-01"},
]

# --- OFFICIAL SCHEME ----------------------------------------------------
VACCINATION_SCHEME = [
    {"scheme_id": 1, "name": "Esquema Nacional de Vacunación", "issuing_body": "SS México", "year": 2024, "is_current": True},
]

SCHEME_DOSES = [
    {"dose_id": 1, "scheme_id": 1, "vaccine_id": 1, "dose_number": 1, "dose_label": "Dosis 1", "ideal_age_months": 0,  "min_interval_days": None},
    {"dose_id": 2, "scheme_id": 1, "vaccine_id": 2, "dose_number": 1, "dose_label": "Dosis 1", "ideal_age_months": 0,  "min_interval_days": None},
    {"dose_id": 3, "scheme_id": 1, "vaccine_id": 2, "dose_number": 2, "dose_label": "Dosis 3", "ideal_age_months": 6,  "min_interval_days": 30},
    {"dose_id": 4, "scheme_id": 1, "vaccine_id": 3, "dose_number": 1, "dose_label": "Dosis 1", "ideal_age_months": 2,  "min_interval_days": None},
    {"dose_id": 5, "scheme_id": 1, "vaccine_id": 3, "dose_number": 2, "dose_label": "Dosis 2", "ideal_age_months": 4,  "min_interval_days": 60},
    {"dose_id": 6, "scheme_id": 1, "vaccine_id": 4, "dose_number": 1, "dose_label": "Dosis 1", "ideal_age_months": 2,  "min_interval_days": None},
    {"dose_id": 7, "scheme_id": 1, "vaccine_id": 5, "dose_number": 1, "dose_label": "Dosis 1", "ideal_age_months": 6,  "min_interval_days": None},
]

# --- APPOINTMENTS -------------------------------------------------------
# vaccine_id eliminado; agregados area_id, duration_min, reason
# status → appointment_status; notes → appointment_notes
APPOINTMENTS = [
    {"appointment_id": 1, "patient_id": 1, "clinic_id": 1, "area_id": 3, "worker_id": 2, "scheduled_at": "2025-06-10 09:00", "duration_min": 15, "reason": "Segunda dosis Hep B",      "appointment_status": "Programada", "appointment_notes": None},
    {"appointment_id": 2, "patient_id": 2, "clinic_id": 1, "area_id": 3, "worker_id": 2, "scheduled_at": "2025-04-15 10:30", "duration_min": 15, "reason": "Pentavalente refuerzo",    "appointment_status": "Programada", "appointment_notes": None},
    {"appointment_id": 3, "patient_id": 3, "clinic_id": 2, "area_id": 4, "worker_id": 4, "scheduled_at": "2025-05-20 08:00", "duration_min": 20, "reason": "Influenza",                "appointment_status": "Cancelada",  "appointment_notes": "Paciente no asistió"},
    {"appointment_id": 4, "patient_id": 4, "clinic_id": 1, "area_id": 3, "worker_id": 2, "scheduled_at": "2025-03-22 11:00", "duration_min": 15, "reason": "BCG",                      "appointment_status": "Completada", "appointment_notes": "Aplicada sin incidentes"},
]

# --- VACCINATION RECORDS ------------------------------------------------
# Antes llamada APPLICATIONS; campos eliminados: dose_applied, next_dose_date, clinic_location, notes
# Nuevos campos: scheme_dose_id, application_site_id, patient_temp_c, had_reaction
APPLICATION_SITES = [
    {"application_site_id": 1, "application_site": "Deltoides_Izquierdo"},
    {"application_site_id": 2, "application_site": "Deltoides_Derecho"},
    {"application_site_id": 3, "application_site": "Muslo_Izquierdo"},
    {"application_site_id": 4, "application_site": "Muslo_Derecho"},
    {"application_site_id": 5, "application_site": "Oral"},
]

VACCINATION_RECORDS = [
    {"record_id": 1, "patient_id": 1, "vaccine_id": 1, "worker_id": 2, "clinic_id": 1, "lot_id": 1, "scheme_dose_id": 1, "applied_date": "2025-01-10", "application_site_id": 3, "patient_temp_c": 36.5, "had_reaction": False},
    {"record_id": 2, "patient_id": 2, "vaccine_id": 2, "worker_id": 2, "clinic_id": 1, "lot_id": 2, "scheme_dose_id": 2, "applied_date": "2025-02-15", "application_site_id": 1, "patient_temp_c": 36.8, "had_reaction": False},
    {"record_id": 3, "patient_id": 1, "vaccine_id": 3, "worker_id": 1, "clinic_id": 1, "lot_id": 3, "scheme_dose_id": 3, "applied_date": "2025-03-20", "application_site_id": 4, "patient_temp_c": 37.0, "had_reaction": False},
    {"record_id": 4, "patient_id": 3, "vaccine_id": 2, "worker_id": 4, "clinic_id": 2, "lot_id": 2, "scheme_dose_id": 2, "applied_date": "2025-03-01", "application_site_id": 2, "patient_temp_c": 36.6, "had_reaction": False},
    {"record_id": 5, "patient_id": 4, "vaccine_id": 4, "worker_id": 2, "clinic_id": 2, "lot_id": 4, "scheme_dose_id": 4, "applied_date": "2025-03-22", "application_site_id": 5, "patient_temp_c": 36.9, "had_reaction": False},
]

POST_VACCINE_REACTIONS = []  # vacío en demo

# --- SCHEME COMPLETION ALERTS -------------------------------------------
# vaccine_id → scheme_dose_id; resolved_at, resolved_by, notes, generated_at eliminados
# expected_date → due_date; agregado notified_at
SCHEME_COMPLETION_ALERTS = [
    {"alert_id": 1, "patient_id": 3, "scheme_dose_id": 3, "due_date": "2023-12-03", "status": "Pendiente", "notified_at": None},
    {"alert_id": 2, "patient_id": 2, "scheme_dose_id": 6, "due_date": "2025-03-08", "status": "Enviada",   "notified_at": "2025-03-09 08:00"},
    {"alert_id": 3, "patient_id": 1, "scheme_dose_id": 2, "due_date": "2025-04-15", "status": "Resuelta",  "notified_at": "2025-03-10 09:00"},
]

# --- NFC ----------------------------------------------------------------
# notes → nfc_card_notes
NFC_CARDS = [
    {"nfc_card_id": 1, "patient_id": 1, "uid": "NFC001AA", "card_type": "Tarjeta", "issued_date": "2024-01-10", "issued_by": 1, "status": "Activa",      "last_scanned_at": "2025-03-20 09:15", "nfc_card_notes": None},
    {"nfc_card_id": 2, "patient_id": 2, "uid": "NFC002BB", "card_type": "Pulsera", "issued_date": "2024-02-14", "issued_by": 1, "status": "Activa",      "last_scanned_at": "2025-02-15 10:05", "nfc_card_notes": None},
    {"nfc_card_id": 3, "patient_id": 3, "uid": "NFC003CC", "card_type": "Llavero", "issued_date": "2024-03-20", "issued_by": 1, "status": "Desactivada", "last_scanned_at": None,               "nfc_card_notes": "Reportado extraviado"},
    {"nfc_card_id": 4, "patient_id": 4, "uid": "NFC004DD", "card_type": "Tarjeta", "issued_date": "2024-04-05", "issued_by": 1, "status": "Activa",      "last_scanned_at": "2025-03-22 11:00", "nfc_card_notes": None},
]

NFC_DEVICES = [
    {"device_id": "DEV-001", "clinic_id": 1, "area_id": 3, "device_name": "Lector Consultorio 1", "model": "ACR122U", "serial_number": "SN-ACR-001", "nfc_device_status": "Activo", "registered_at": "2024-01-01"},
]

# result → nfc_scan_result; agregado device_id
NFC_SCAN_EVENTS = [
    {"scan_event_id": 1, "nfc_card_id": 1, "scanned_by": 2, "clinic_id": 1, "area_id": 3, "scanned_at": "2025-03-20 09:15", "action_triggered": "Abrir_Expediente",    "device_id": "DEV-001", "nfc_scan_result": "Expediente abierto correctamente"},
    {"scan_event_id": 2, "nfc_card_id": 2, "scanned_by": 2, "clinic_id": 1, "area_id": 3, "scanned_at": "2025-02-15 10:05", "action_triggered": "Confirmar_Vacunacion", "device_id": "DEV-001", "nfc_scan_result": "Vacunación registrada"},
    {"scan_event_id": 3, "nfc_card_id": 4, "scanned_by": 2, "clinic_id": 1, "area_id": 1, "scanned_at": "2025-03-22 11:00", "action_triggered": "Registrar_Llegada",    "device_id": None,      "nfc_scan_result": "Llegada registrada"},
]

# --- SUPPLY / INVENTORY -------------------------------------------------
# supply_catalog: eliminado description; clinic_inventory: eliminado updated_by; last_updated solo DATE
SUPPLY_CATALOG = [
    {"supply_id": 1, "name": "Jeringa 1mL",       "unit": "pieza",   "category": "Jeringa"},
    {"supply_id": 2, "name": "Jeringa 5mL",       "unit": "pieza",   "category": "Jeringa"},
    {"supply_id": 3, "name": "Algodón estéril",   "unit": "paquete", "category": "Desechable"},
    {"supply_id": 4, "name": "Guantes nitrilo M", "unit": "caja",    "category": "Desechable"},
    {"supply_id": 5, "name": "Paracetamol 500mg", "unit": "tableta", "category": "Medicamento"},
]

CLINIC_INVENTORY = [
    {"inventory_id": 1, "clinic_id": 1, "supply_id": 1, "quantity": 500,  "min_stock": 50,  "last_updated": "2025-03-01"},
    {"inventory_id": 2, "clinic_id": 1, "supply_id": 3, "quantity": 30,   "min_stock": 20,  "last_updated": "2025-03-01"},
    {"inventory_id": 3, "clinic_id": 1, "supply_id": 4, "quantity": 8,    "min_stock": 10,  "last_updated": "2025-03-10"},  # bajo stock
    {"inventory_id": 4, "clinic_id": 2, "supply_id": 2, "quantity": 200,  "min_stock": 30,  "last_updated": "2025-02-20"},
    {"inventory_id": 5, "clinic_id": 3, "supply_id": 5, "quantity": 1000, "min_stock": 100, "last_updated": "2025-01-15"},
]

# Tablas nuevas del schema
BEACONS = []
SCAN_LOGS = []
AUDIT_LOG = []


# --- USERS (login) -------------------------------------------------------
USERS = {
    "admin": {"password": "123", "worker_id": 1, "name": "Admin", "lastname": "Demo", "role": "Administrador"},
}


# =============================================================================
# HELPERS — simulan el cursor de psycopg2
# =============================================================================

def _cur_fetchall(table):
    tables = {
        "countries":                  COUNTRIES,
        "states":                     STATES,
        "municipalities":             MUNICIPALITIES,
        "neighborhoods":              NEIGHBORHOODS,
        "addresses":                  ADDRESSES,
        "clinics":                    CLINICS,
        "area_types":                 AREA_TYPES,
        "clinic_areas":               CLINIC_AREAS,
        "equipment_catalog":          EQUIPMENT_CATALOG,
        "area_equipment":             AREA_EQUIPMENT,
        "blood_types":                BLOOD_TYPES,
        "patients":                   PATIENTS,
        "allergies":                  ALLERGIES,
        "patient_allergies":          PATIENT_ALLERGIES,
        "marital_status":             MARITAL_STATUS,
        "occupations":                OCCUPATIONS,
        "guardians":                  GUARDIANS,
        "guardian_phones":            GUARDIAN_PHONES,
        "guardian_emails":            GUARDIAN_EMAILS,
        "patient_guardian_relations": PATIENT_GUARDIAN_RELATIONS,
        "roles":                      ROLES,
        "specialties":                SPECIALTIES,
        "institutions":               INSTITUTIONS,
        "workers":                    WORKERS,
        "worker_phones":              WORKER_PHONES,
        "worker_emails":              WORKER_EMAILS,
        "worker_professional":        WORKER_PROFESSIONAL,
        "worker_clinic_assignment":   WORKER_CLINIC_ASSIGNMENT,
        "worker_schedules":           WORKER_SCHEDULES,
        "manufacturers":              MANUFACTURERS,
        "vaccine_vias":               VACCINE_VIAS,
        "vaccines":                   VACCINES,
        "vaccine_lots":               VACCINE_LOTS,
        "vaccination_scheme":         VACCINATION_SCHEME,
        "scheme_doses":               SCHEME_DOSES,
        "appointments":               APPOINTMENTS,
        "application_sites":          APPLICATION_SITES,
        "vaccination_records":        VACCINATION_RECORDS,
        "post_vaccine_reactions":     POST_VACCINE_REACTIONS,
        "scheme_completion_alerts":   SCHEME_COMPLETION_ALERTS,
        "nfc_cards":                  NFC_CARDS,
        "nfc_devices":                NFC_DEVICES,
        "nfc_scan_events":            NFC_SCAN_EVENTS,
        "supply_catalog":             SUPPLY_CATALOG,
        "clinic_inventory":           CLINIC_INVENTORY,
        "beacons":                    BEACONS,
        "scan_logs":                  SCAN_LOGS,
        "audit_log":                  AUDIT_LOG,
    }
    return list(tables.get(table, []))


def _cur_fetchone(table, pk_field, pk_value):
    return next((row for row in _cur_fetchall(table) if row.get(pk_field) == pk_value), None)


def _cur_fetchall_where(table, field, value):
    return [row for row in _cur_fetchall(table) if row.get(field) == value]


# =============================================================================
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
        "name":      first,
        "lastname":  last,
        "role":      session.get("role", "Administrador"),
        "worker_id": session.get("worker_id"),
        "initials":  initials,
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
    parts = [patient.get("first_name", ""), patient.get("last_name", "")]
    return " ".join(p for p in parts if p).strip()


def _worker_full_name(worker_id):
    w = _cur_fetchone("workers", "worker_id", worker_id)
    if not w:
        return "Personal demo"
    return f"{w['first_name']} {w['last_name']}".strip()


def _worker_email(worker_id):
    """Devuelve el email primario del trabajador desde worker_emails."""
    emails = _cur_fetchall_where("worker_emails", "worker_id", worker_id)
    primary = next((e for e in emails if e.get("is_primary")), None)
    return (primary or emails[0])["email"] if emails else "—"


def _guardian_primary_phone(guardian_id):
    phones = _cur_fetchall_where("guardian_phones", "guardian_id", guardian_id)
    primary = next((p for p in phones if p.get("is_primary")), None)
    return (primary or phones[0])["phone"] if phones else "—"


def _patient_primary_guardian(patient_id):
    """Devuelve el guardian_id del tutor primario via patient_guardian_relations."""
    rels = _cur_fetchall_where("patient_guardian_relations", "patient_id", patient_id)
    primary_rel = next((r for r in rels if r.get("is_primary")), None)
    if not primary_rel and rels:
        primary_rel = rels[0]
    return primary_rel["guardian_id"] if primary_rel else None


def _guardian_full_name(guardian_id):
    g = _cur_fetchone("guardians", "guardian_id", guardian_id)
    if not g:
        return "Tutor no registrado"
    return f"{g['first_name']} {g['last_name']}".strip()


def _vaccine_name(vaccine_id):
    v = _cur_fetchone("vaccines", "vaccine_id", vaccine_id)
    return v["name"] if v else "Vacuna desconocida"


def _blood_type_str(blood_type_id):
    bt = _cur_fetchone("blood_types", "blood_type_id", blood_type_id)
    return bt["blood_type"] if bt else "—"

def _enrich_patient(p):
    """Agrega campos calculados y relacionados a un paciente."""
    item = dict(p)
    item["full_name"]   = _patient_full_name(p)
    item["age"]         = _age_years(p["birth_date"])
    item["blood_type"]  = _blood_type_str(p.get("blood_type_id"))

    # Guardian via patient_guardian_relations (normalizado)
    g_id = _patient_primary_guardian(p["patient_id"])
    item["guardian"]    = _guardian_full_name(g_id) if g_id else "Sin tutor"
    item["contact"]     = _guardian_primary_phone(g_id) if g_id else "—"

    # Alergias via tabla allergies normalizada
    pa_rows = _cur_fetchall_where("patient_allergies", "patient_id", p["patient_id"])
    allergy_names = []
    for pa in pa_rows:
        allergy = _cur_fetchone("allergies", "allergy_id", pa["allergy_id"])
        if allergy:
            allergy_names.append(allergy["name"])
    item["allergies"] = ", ".join(allergy_names) or "Ninguna"

    # risk_level ya no existe en patients; se calcula o se omite
    item["risk"] = "N/A"
    return item


def _enrich_record(r):
    """Agrega nombres legibles a un registro de vacunación (vaccination_records)."""
    item = dict(r)
    patient = _cur_fetchone("patients", "patient_id", r["patient_id"])
    item["patient_name"] = _patient_full_name(patient) if patient else "—"
    item["name"]         = _vaccine_name(r["vaccine_id"])
    item["doctor"]       = _worker_full_name(r["worker_id"])
    item["date"]         = r["applied_date"]
    item["id"]           = r["record_id"]

    # Dosis desde scheme_doses
    dose = _cur_fetchone("scheme_doses", "dose_id", r.get("scheme_dose_id"))
    item["dose"]      = dose["dose_label"] if dose else "—"
    item["next_date"] = None  # ya no existe next_dose_date; se calcula por esquema si se requiere

    # Sitio de aplicación
    site = _cur_fetchone("application_sites", "application_site_id", r.get("application_site_id"))
    item["application_site"] = site["application_site"] if site else "—"

    item["had_reaction"]   = r.get("had_reaction", False)
    item["patient_temp_c"] = r.get("patient_temp_c")
    item["notes"]          = "Con reacción" if r.get("had_reaction") else "Sin reacciones"
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
from datetime import date, timedelta
from calendar import month_abbr

@app.route("/dashboard")
def dashboard():
    locked = _require_login()
    if locked:
        return locked

    today_dt      = date.today()
    patients_raw  = _cur_fetchall("patients")
    vaccines_raw  = _cur_fetchall("vaccines")
    records_raw   = _cur_fetchall("vaccination_records")
    alerts_raw    = _cur_fetchall("gps_risk_alerts")
    inventory_raw = _cur_fetchall("clinic_inventory")
    lots_raw      = _cur_fetchall("vaccine_lots")
    scheme_raw    = _cur_fetchall("scheme_doses")   # tabla con las dosis del esquema oficial

    # ── Pacientes enriquecidos ──────────────────────────────────────────────
    top_patients = [_enrich_patient(p) for p in patients_raw[:5]]

    # ── KPI: cobertura — pacientes con todas las dosis del esquema ──────────
    total_doses_in_scheme = len(scheme_raw)   # cuántas dosis tiene el esquema completo

    def patient_completed_scheme(pid):
        applied = [r for r in records_raw if r["patient_id"] == pid]
        return len(applied) >= total_doses_in_scheme

    patients_complete  = sum(1 for p in patients_raw if patient_completed_scheme(p["patient_id"]))
    coverage_pct       = round(patients_complete / len(patients_raw) * 100) if patients_raw else 0

    # Tendencia: comparar con mes anterior (simulado como -2 si no hay datos previos)
    # Ajusta esta lógica según tu BD real
    coverage_trend = 0   # reemplaza con cálculo real si guardas histórico

    # ── KPI: pacientes con dosis atrasadas ──────────────────────────────────
    # Un paciente está atrasado si tiene al menos 1 dosis del esquema pendiente
    # y su edad ya superó la edad recomendada de esa dosis
    def patient_is_delayed(patient):
        age_months = (patient.get("age") or 0) * 12
        applied_vaccine_ids = {r["vaccine_id"] for r in records_raw if r["patient_id"] == patient["patient_id"]}
        for dose in scheme_raw:
            if dose["vaccine_id"] not in applied_vaccine_ids:
                if age_months > (dose.get("ideal_age_months") or 0) + 1:
                    return True
        return False

    delayed_patients   = sum(1 for p in patients_raw if patient_is_delayed(p))

    # Pacientes críticos: 2+ vacunas atrasadas
    def count_delayed_doses(patient):
        age_months = (patient.get("age") or 0) * 12
        applied_vaccine_ids = {r["vaccine_id"] for r in records_raw if r["patient_id"] == patient["patient_id"]}
        return sum(
            1 for dose in scheme_raw
            if dose["vaccine_id"] not in applied_vaccine_ids
            and age_months > (dose.get("ideal_age_months") or 0) + 1
        )

    patients_critical = sum(1 for p in patients_raw if count_delayed_doses(p) >= 2)

    # ── KPI: dosis aplicadas ────────────────────────────────────────────────
    week_start         = today_dt - timedelta(days=today_dt.weekday())
    month_start        = today_dt.replace(day=1)

    applications_today = sum(1 for r in records_raw if r.get("applied_date") == today_dt.isoformat())
    doses_this_week    = sum(1 for r in records_raw if r.get("applied_date", "") >= week_start.isoformat())
    doses_this_month   = sum(1 for r in records_raw if r.get("applied_date", "") >= month_start.isoformat())

    # ── KPI: pacientes con dosis vencidas (lotes vencidos usados) ───────────
    expired_lots       = {l["lot_id"] for l in lots_raw if l.get("expiration_date") and str(l["expiration_date"]) < today_dt.isoformat()}
    expired_doses      = sum(1 for r in records_raw if r.get("lot_id") in expired_lots)

    # ── KPI: nuevos pacientes este mes ──────────────────────────────────────
    new_patients_month = sum(
        1 for p in patients_raw
        if str(p.get("created_at", ""))[:7] == today_dt.strftime("%Y-%m")
    )

    # ── KPI: lotes por vencer esta semana ──────────────────────────────────
    week_end           = today_dt + timedelta(days=7)
    expiring_lots_week = sum(
        1 for l in lots_raw
        if l.get("expiration_date")
        and today_dt.isoformat() <= str(l["expiration_date"]) <= week_end.isoformat()
    )

    # ── Stock bajo ─────────────────────────────────────────────────────────
    low_stock_count    = len([i for i in inventory_raw if i["quantity"] < i["min_stock"]])

    # ── Alertas pendientes ─────────────────────────────────────────────────
    pending_alerts     = len([al for al in alerts_raw if al["resolved_at"] is None])

    # ── Cobertura por grupo de edad ─────────────────────────────────────────
    age_groups = [
        ("0–1 año",   0,   1),
        ("1–5 años",  1,   5),
        ("5–10 años", 5,   10),
        ("10–15 años",10,  15),
        ("15+ años",  15,  99999),
    ]
    coverage_by_age = []
    for label, lo, hi in age_groups:
        group = [p for p in patients_raw if lo <= (p.get("age") or 0) < hi]
        if group:
            complete = sum(1 for p in group if patient_completed_scheme(p["patient_id"]))
            pct = round(complete / len(group) * 100)
        else:
            pct = 0
        coverage_by_age.append({"label": label, "pct": pct})

    # ── Dosis por mes (últimos 6 meses) ────────────────────────────────────
    doses_by_month = []
    for i in range(5, -1, -1):
        target = (today_dt.replace(day=1) - timedelta(days=i * 28))
        ym     = target.strftime("%Y-%m")
        count  = sum(1 for r in records_raw if str(r.get("applied_date", ""))[:7] == ym)
        doses_by_month.append({"label": month_abbr[target.month], "count": count})

    # Tendencia mensual: comparar último mes vs penúltimo
    if len(doses_by_month) >= 2 and doses_by_month[-2]["count"] > 0:
        monthly_trend = round(
            (doses_by_month[-1]["count"] - doses_by_month[-2]["count"])
            / doses_by_month[-2]["count"] * 100
        )
    else:
        monthly_trend = 0

    # ── % retraso por vacuna ───────────────────────────────────────────────
    delay_by_vaccine = []
    for vac in vaccines_raw[:8]:   # top 8 para no saturar la gráfica
        vid       = vac["vaccine_id"]
        eligible  = [
            p for p in patients_raw
            if any(
                d["vaccine_id"] == vid and (p.get("age") or 0) * 12 > (d.get("ideal_age_months") or 0) + 1
                for d in scheme_raw
            )
        ]
        if not eligible:
            continue
        applied   = {r["patient_id"] for r in records_raw if r["vaccine_id"] == vid}
        delayed   = sum(1 for p in eligible if p["patient_id"] not in applied)
        pct       = round(delayed / len(eligible) * 100)
        delay_by_vaccine.append({"vaccine": vac["name"], "pct": pct})

    delay_by_vaccine.sort(key=lambda x: x["pct"], reverse=True)

    session["last_visit"] = today_dt.isoformat()

    return render_template(
        "index_2daE.html",
        **_session_vars(),
        today               = today_dt.strftime("%d/%m/%Y"),
        total_patients      = len(patients_raw),
        total_vaccines      = len(vaccines_raw),
        applications_today  = applications_today,
        doses_this_week     = doses_this_week,
        doses_this_month    = doses_this_month,
        coverage_pct        = coverage_pct,
        coverage_trend      = coverage_trend,
        delayed_patients    = delayed_patients,
        patients_critical   = patients_critical,
        expired_doses       = expired_doses,
        new_patients_month  = new_patients_month,
        expiring_lots_week  = expiring_lots_week,
        low_stock_count     = low_stock_count,
        pending_alerts      = pending_alerts,
        monthly_trend       = monthly_trend,
        coverage_by_age     = coverage_by_age,
        doses_by_month      = doses_by_month,
        delay_by_vaccine    = delay_by_vaccine,
        top_patients        = top_patients,
    )

# ── PACIENTES ─────────────────────────────────────────────────────────────────
@app.route("/pacientes")
def pacientes():
    locked = _require_login()
    if locked:
        return locked

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

    # Simular INSERT en guardians (sin second_last, marital_status/occupation como FK int)
    new_guardian_id = _next_id(GUARDIANS, "guardian_id")
    GUARDIANS.append({
        "guardian_id":       new_guardian_id,
        "first_name":        (tutor.get("name")    or "Tutor").strip(),
        "last_name":         (tutor.get("lastname") or "Demo").strip(),
        "curp":              None,
        "address_id":        None,
        "marital_status_id": None,
        "occupation":        None,
    })
    if tutor.get("number"):
        GUARDIAN_PHONES.append({
            "phone_id":   _next_id(GUARDIAN_PHONES, "phone_id"),
            "guardian_id": new_guardian_id,
            "phone":       tutor["number"],
            "phone_type":  "Celular",
            "is_primary":  True,
        })

    # Simular INSERT en patients (sin second_last, address_id, risk_level, is_active, registered_at)
    new_pid = _next_id(PATIENTS, "patient_id")
    PATIENTS.append({
        "patient_id":   new_pid,
        "first_name":   first_name,
        "last_name":    last_name,
        "curp":         payload.get("curp"),
        "birth_date":   payload.get("birth_date") or "2021-01-01",
        "gender":       payload.get("gender") or "M",
        "blood_type_id": 1,  # O+ por default
        "nfc_token":    f"NFC{new_pid:03d}",
        "weight_kg":    payload.get("weight_kg"),
        "premature":    bool(payload.get("premature", False)),
    })

    # Simular INSERT en patient_guardian_relations
    PATIENT_GUARDIAN_RELATIONS.append({
        "relation_id":   _next_id(PATIENT_GUARDIAN_RELATIONS, "relation_id"),
        "patient_id":    new_pid,
        "guardian_id":   new_guardian_id,
        "relation_type": "Tutor",
        "is_primary":    True,
        "has_custody":   True,
    })

    flash(f"Paciente {first_name} {last_name} registrado correctamente.", "success")
    return jsonify({"message": "Paciente registrado (demo)", "patient_id": new_pid})


@app.route("/delete_patient/<int:id>", methods=["POST"])
def delete_patient(id):
    locked = _require_login()
    if locked:
        return jsonify({"error": "No autenticado"}), 401

    patient = _cur_fetchone("patients", "patient_id", id)
    if not patient:
        return jsonify({"error": "Paciente no encontrado"}), 404

    PATIENTS.remove(patient)
    nombre = _patient_full_name(patient)

    for r in _cur_fetchall_where("vaccination_records", "patient_id", id):
        VACCINATION_RECORDS.remove(r)

    for rel in _cur_fetchall_where("patient_guardian_relations", "patient_id", id):
        PATIENT_GUARDIAN_RELATIONS.remove(rel)

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
    records_raw  = _cur_fetchall_where("vaccination_records", "patient_id", patient["patient_id"]) if patient else []
    records      = [_enrich_record(r) for r in records_raw]

    next_vaccines = _build_next_vaccines(patient["patient_id"]) if patient else []

    return render_template(
        "historial_2daE.html",
        **_session_vars(),
        patients=[_enrich_patient(p) for p in patients_raw],
        patient=patient,
        applications=records,
        next_vaccines=next_vaccines,
    )


@app.route("/historial/<int:id>")
def historial_paciente(id):
    locked = _require_login()
    if locked:
        return locked

    patient_raw = _cur_fetchone("patients", "patient_id", id)
    if not patient_raw:
        flash("Paciente no encontrado.", "danger")
        return redirect(url_for("historial"))

    patient     = _enrich_patient(patient_raw)
    records_raw = _cur_fetchall_where("vaccination_records", "patient_id", id)
    records     = [_enrich_record(r) for r in records_raw]

    session["last_patient_viewed"] = id

    return render_template(
        "historial_2daE.html",
        **_session_vars(),
        patients=[_enrich_patient(p) for p in _cur_fetchall("patients")],
        patient=patient,
        applications=records,
        next_vaccines=_build_next_vaccines(id),
    )


def _build_next_vaccines(patient_id):
    """Construye las próximas vacunas pendientes desde scheme_doses vs vaccination_records."""
    applied_dose_ids = {
        r["scheme_dose_id"]
        for r in _cur_fetchall_where("vaccination_records", "patient_id", patient_id)
        if r.get("scheme_dose_id")
    }
    pending = []
    for dose in _cur_fetchall("scheme_doses"):
        if dose["dose_id"] not in applied_dose_ids:
            vaccine = _cur_fetchone("vaccines", "vaccine_id", dose["vaccine_id"])
            pending.append({
                "name": vaccine["name"] if vaccine else "—",
                "dose": dose["dose_label"],
                "date": f"A los {dose['ideal_age_months']} meses" if dose.get("ideal_age_months") is not None else "—",
            })
    return pending[:3]


# ── FUNCIONES DE ENRIQUECIMIENTO (Helpers de datos relacionales) ────────────
def _enrich_appointment(ap):
    """Enriquece cita con nombres y datos relacionales."""
    item = dict(ap)
    patient = _cur_fetchone("patients", "patient_id", ap["patient_id"])
    worker = _cur_fetchone("workers", "worker_id", ap["worker_id"])
    clinic = _cur_fetchone("clinics", "clinic_id", ap["clinic_id"])
    area = _cur_fetchone("clinic_areas", "area_id", ap.get("area_id")) if ap.get("area_id") else None

    item["patient_name"] = _patient_full_name(patient) if patient else "—"
    item["worker_name"] = f"{worker['first_name']} {worker['last_name']}" if worker else "—"
    item["clinic_name"] = clinic["name"] if clinic else "—"
    item["area_name"] = area["name"] if area else "—"
    item["vaccine_name"] = ap.get("reason") or "—"
    item["status"] = ap.get("appointment_status", "—")
    item["notes"] = ap.get("appointment_notes", "")
    return item


def _enrich_inventory_item(inv):
    """Enriquece insumo con nombres y datos relacionales."""
    item = dict(inv)
    supply = _cur_fetchone("supply_catalog", "supply_id", inv["supply_id"])
    clinic = _cur_fetchone("clinics", "clinic_id", inv["clinic_id"])

    item["supply_name"] = supply["name"] if supply else "—"
    item["supply_unit"] = supply["unit"] if supply else "—"
    item["supply_category"] = supply["category"] if supply else "—"
    item["clinic_name"] = clinic["name"] if clinic else "—"
    item["low_stock"] = inv["quantity"] < inv["min_stock"]
    return item


def _enrich_nfc_card(c):
    """Enriquece tarjeta NFC con datos del paciente."""
    item = dict(c)
    patient = _cur_fetchone("patients", "patient_id", c["patient_id"])
    item["patient_name"] = _patient_full_name(patient) if patient else "—"
    item["notes"] = c.get("nfc_card_notes")
    return item


def _enrich_nfc_scan(s):
    """Enriquece evento de escaneo NFC con datos relacionales."""
    item = dict(s)
    item["worker_name"] = _worker_full_name(s["scanned_by"]) if s.get("scanned_by") else "—"
    card = _cur_fetchone("nfc_cards", "nfc_card_id", s["nfc_card_id"])
    patient = _cur_fetchone("patients", "patient_id", card["patient_id"]) if card else None
    item["patient_name"] = _patient_full_name(patient) if patient else "—"
    item["result"] = s.get("nfc_scan_result")
    return item


def _enrich_area(a):
    """Enriquece área con nombre del tipo."""
    item = dict(a)
    atype = _cur_fetchone("area_types", "area_type_id", a["area_type_id"])
    item["area_type"] = atype["area_type"] if atype else "—"
    return item


def _enrich_clinic(c):
    """Enriquece clínica con dirección completa y áreas."""
    item = dict(c)
    address = _cur_fetchone("addresses", "address_id", c["address_id"])
    if address:
        nbhd = _cur_fetchone("neighborhoods", "neighborhood_id", address["neighborhood_id"])
        item["address_str"] = f"{address['street']} {address['ext_number'] or ''}, {nbhd['name'] if nbhd else ''}".strip(", ")
    else:
        item["address_str"] = "—"

    areas_raw = _cur_fetchall_where("clinic_areas", "clinic_id", c["clinic_id"])
    item["areas"] = [_enrich_area(a) for a in areas_raw]
    return item


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

    patient     = _enrich_patient(patient_raw)
    records_raw = _cur_fetchall_where("vaccination_records", "patient_id", id)
    records     = [_enrich_record(r) for r in records_raw]

    return render_template(
        "esquemaPaciente_2daE.html",
        **_session_vars(),
        patient=patient,
        patient_name=patient["full_name"],
        applications=records,
        next_vaccines=_build_next_vaccines(id),
    )


# ── ESQUEMA VACUNACIÓN ────────────────────────────────────────────────────────
@app.route("/esquema")
def esquema_vacunacion():
    locked = _require_login()
    if locked:
        return locked

    # Construir datos del esquema para la plantilla
    scheme_data = []
    for dose in _cur_fetchall("scheme_doses"):
        vaccine = _cur_fetchone("vaccines", "vaccine_id", dose["vaccine_id"])
        scheme_data.append((dose, vaccine or {}))

    return render_template(
        "esquemaVacunacion_2daE.html",
        **_session_vars(),
        esquema=scheme_data,
    )


# ── VACUNAS ───────────────────────────────────────────────────────────────────
@app.route("/vacunas")
def vacunas_page():
    locked = _require_login()
    if locked:
        return locked

    vaccines = _cur_fetchall("vaccines")
    lots     = _cur_fetchall("vaccine_lots")

    # Enriquecer vacunas con fabricante, vía y stock (quantity_available)
    for v in vaccines:
        mfr = _cur_fetchone("manufacturers", "manufacturer_id", v.get("manufacturer_id"))
        via = _cur_fetchone("vaccine_vias",  "via_id",          v.get("via_id"))
        v["manufacturer"] = mfr["name"] if mfr else "—"
        v["route"]        = via["via"]  if via  else "—"
        v["inventory"]    = sum(
            l["quantity_available"]
            for l in lots
            if l["vaccine_id"] == v["vaccine_id"]
        )

    return render_template(
        "vacunas_2daE.html",
        **_session_vars(),
        total_vaccines=len(vaccines),
        vaccines=vaccines,
        lots=lots,
        today=date.today().isoformat(),
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
        "vaccine_id":       new_vid,
        "name":             name,
        "commercial_name":  payload.get("commercial_name"),
        "manufacturer_id":  payload.get("manufacturer_id"),
        "via_id":           payload.get("via_id"),
        "ideal_age_months": payload.get("ideal_age_months"),
        "descripcion":      payload.get("descripcion") or "No especificado",
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


# ── APLICACIONES (VACCINATION RECORDS) ───────────────────────────────────────
@app.route("/aplicaciones")
def aplicaciones():
    locked = _require_login()
    if locked:
        return locked

    records_raw       = _cur_fetchall("vaccination_records")
    records           = [_enrich_record(r) for r in records_raw]
    unique_patients   = len(set(r["patient_id"] for r in records_raw))
    unique_vaccines   = len(set(r["vaccine_id"] for r in records_raw))
    applications_today = sum(
        1 for r in records_raw if r["applied_date"] == date.today().isoformat()
    )

    return render_template(
        "aplicaciones_2daE.html",
        **_session_vars(),
        total_applications=len(records),
        total_patients_attended=unique_patients,
        total_unique_vaccines=unique_vaccines,
        applications_today=applications_today,
        applications=records,
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
            patient_id     = int(request.form.get("patient_id", "0"))
            vaccine_id     = int(request.form.get("vaccine_id", "0"))
            worker_id      = int(request.form.get("worker_id",  "0"))
            scheme_dose_id = request.form.get("scheme_dose_id")
            scheme_dose_id = int(scheme_dose_id) if scheme_dose_id else None
            app_site_id    = request.form.get("application_site_id")
            app_site_id    = int(app_site_id) if app_site_id else None
        except ValueError:
            error = "IDs inválidos"
        else:
            patient = _cur_fetchone("patients", "patient_id", patient_id)
            vaccine = _cur_fetchone("vaccines",  "vaccine_id", vaccine_id)
            if not patient or not vaccine:
                error = "Paciente o vacuna no encontrados"
            else:
                new_record = {
                    "record_id":           _next_id(VACCINATION_RECORDS, "record_id"),
                    "patient_id":          patient_id,
                    "vaccine_id":          vaccine_id,
                    "worker_id":           worker_id or session.get("worker_id", 1),
                    "clinic_id":           1,
                    "lot_id":              None,
                    "scheme_dose_id":      scheme_dose_id,
                    "applied_date":        request.form.get("applied_date") or date.today().isoformat(),
                    "application_site_id": app_site_id,
                    "patient_temp_c":      request.form.get("patient_temp_c") or None,
                    "had_reaction":        request.form.get("had_reaction") == "true",
                }
                VACCINATION_RECORDS.insert(0, new_record)
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
        scheme_doses=_cur_fetchall("scheme_doses"),
        application_sites=_cur_fetchall("application_sites"),
        form=form,
        error=error,
    )


# ── PERSONAL ──────────────────────────────────────────────────────────────────
@app.route("/personal")
def personal():
    locked = _require_login()
    if locked:
        return locked

    workers_raw = _cur_fetchall("workers")
    workers = []
    for w in workers_raw:
        row  = dict(w)
        role = _cur_fetchone("roles", "role_id", w["role_id"])
        row["role"]     = role["name"] if role else "Sin rol"
        row["name"]     = w["first_name"]
        row["lastname"] = w["last_name"]
        # email desde worker_emails
        row["mail"]     = _worker_email(w["worker_id"])
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

        # Verificar email en worker_emails
        email_exists = any(
            (e.get("email") or "").lower() == mail.lower()
            for e in _cur_fetchall("worker_emails")
        )

        if password != confirm:
            error = "Las contraseñas no coinciden"
            flash(error, "danger")
        elif email_exists:
            error = "El email ya existe en el sistema"
            flash(error, "danger")
        else:
            role_id = int(request.form.get("role_id") or 3)
            new_wid = _next_id(WORKERS, "worker_id")
            WORKERS.append({
                "worker_id":     new_wid,
                "role_id":       role_id,
                "first_name":    request.form.get("first_name", ""),
                "last_name":     request.form.get("last_name", ""),
                "curp":          None,
                "address_id":    None,
                "birth_date":    None,
                "hire_date":     date.today().isoformat(),
                "password_hash": f"hash:{password}",
            })
            # Insertar email en worker_emails
            WORKER_EMAILS.append({
                "email_id":  _next_id(WORKER_EMAILS, "email_id"),
                "worker_id": new_wid,
                "email":     mail,
                "is_primary": True,
            })
            # Insertar teléfono si viene
            phone = request.form.get("phone")
            if phone:
                WORKER_PHONES.append({
                    "phone_id":  _next_id(WORKER_PHONES, "phone_id"),
                    "worker_id": new_wid,
                    "phone":     phone,
                    "phone_type": "Celular",
                    "is_primary": True,
                })
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

@app.route("/personal/editar/<int:worker_id>", methods=["GET", "POST"])
def edit_user(worker_id):
    worker = next((w for w in WORKERS if w["worker_id"] == worker_id), None)

    if not worker:
        flash("Usuario no encontrado", "danger")
        return redirect(url_for("personal"))

    if request.method == "POST":
        worker["first_name"] = request.form.get("name")
        worker["last_name"]  = request.form.get("lastname")
        worker["role"]       = request.form.get("role")
        worker["mail"]       = request.form.get("mail")

        flash("Usuario actualizado correctamente", "success")
        return redirect(url_for("personal"))

    return render_template(
        "edit_user_2daE.html",
        worker=worker,
        **_session_vars()
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
    inventory = [_enrich_inventory_item(item) for item in inventory_raw]

    if any(i["low_stock"] for i in inventory):
        flash("⚠ Hay insumos con stock por debajo del mínimo.", "warning")

    session["last_section"] = "inventario"

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
    appointments = [_enrich_appointment(ap) for ap in appointments_raw]

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
    cards = [_enrich_nfc_card(c) for c in cards_raw]

    scan_events_raw = _cur_fetchall("nfc_scan_events")
    scans = [_enrich_nfc_scan(s) for s in scan_events_raw]

    session["last_section"] = "nfc"

    return render_template(
        "nfc_2daE.html",
        **_session_vars(),
        cards=cards,
        scans=scans,
        total_cards=len(cards),
        active_cards=sum(1 for c in cards_raw if c["status"] == "Activa"),
    )


# ── CLÍNICAS ──────────────────────────────────────────────────────────────────
@app.route("/clinicas")
def clinicas():
    locked = _require_login()
    if locked:
        return locked

    clinics_raw = _cur_fetchall("clinics")
    clinics = [_enrich_clinic(c) for c in clinics_raw]

    session["last_section"] = "clinicas"

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
                l["quantity_available"]  # actualizado desde quantity_remaining
                for l in _cur_fetchall_where("vaccine_lots", "vaccine_id", v["vaccine_id"])
            )
            results.append({
                "type":     "vacuna",
                "title":    v["name"],
                "subtitle": f"Stock: {lot_stock}",
                "url":      url_for("vacunas_page") + f"?q={v['name']}",
            })

    for w in _cur_fetchall("workers"):
        name  = f"{w['first_name']} {w['last_name']}".strip()
        email = _worker_email(w["worker_id"])
        if q in name.lower() or q in email.lower():
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

    records_raw  = _cur_fetchall("vaccination_records")
    patients_raw = _cur_fetchall("patients")
    total_doses  = len(records_raw)
    reached_pop  = len(set(r["patient_id"] for r in records_raw))
    target_pop   = max(len(patients_raw), 1)
    coverage     = (reached_pop / target_pop) * 100

    monthly = [
        {"period_label": "2026-01", "doses_applied": 1, "unique_patients": 1},
        {"period_label": "2026-02", "doses_applied": 1, "unique_patients": 1},
        {"period_label": "2026-03", "doses_applied": 3, "unique_patients": 3},
    ]

    vax_count  = {}
    vax_people = {}
    for r in records_raw:
        vname = _vaccine_name(r["vaccine_id"])
        vax_count[vname]  = vax_count.get(vname, 0) + 1
        vax_people.setdefault(vname, set()).add(r["patient_id"])

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
            "zone_name":       z["name"],
            "doses_applied":   z["cases"],
            "unique_patients": z["cases"],
            "risk_level":      z["risk"],
            "risk_label":      {"high": "Alto", "medium": "Medio", "low": "Bajo"}.get(z["risk"], "—"),
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


@app.route("/api/alertas-esquema")
def api_alertas_esquema():
    locked = _require_login()
    if locked:
        return jsonify({"error": "No autenticado"}), 401

    alerts_raw = _cur_fetchall("scheme_completion_alerts")
    result = []
    for al in alerts_raw:
        patient = _cur_fetchone("patients", "patient_id", al["patient_id"])
        dose    = _cur_fetchone("scheme_doses", "dose_id", al["scheme_dose_id"])
        vaccine_name = "—"
        if dose:
            v = _cur_fetchone("vaccines", "vaccine_id", dose["vaccine_id"])
            vaccine_name = v["name"] if v else "—"
        result.append({
            **al,
            "patient_name": _patient_full_name(patient) if patient else "—",
            "vaccine_name": vaccine_name,
            "dose_label":   dose["dose_label"] if dose else "—",
        })
    return jsonify(result)


if __name__ == "__main__":
    app.run(debug=True)