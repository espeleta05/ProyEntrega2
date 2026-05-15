"""
seed.py — Genera datos de prueba en MongoDB usando los catálogos reales del proyecto.

Uso:
  python -m mongo.seed            # inserta datos (limpia primero)
  python -m mongo.seed --export   # inserta y exporta a mongo/collections/
"""

import json
import random
import sys
from datetime import datetime, timedelta
from pathlib import Path

random.seed(7)

# ── Catálogos reales tomados de sql/datos.sql ─────────────────────────

CLINICAS = [
    (1,  'Clínica Immunicare Centro'),
    (2,  'Clínica Immunicare Monterrey'),
    (3,  'Clínica Immunicare Apodaca'),
    (4,  'Clínica Immunicare San Nicolás'),
    (5,  'Clínica Immunicare Guadalupe'),
    (6,  'Clínica Immunicare San Pedro'),
    (7,  'Clínica Immunicare Escobedo'),
    (8,  'Clínica Immunicare Santa Catarina'),
    (9,  'Clínica Immunicare Juárez'),
    (10, 'Clínica Immunicare Obispado'),
]

VACUNAS = [
    (1,  'BCG'),
    (2,  'Hepatitis B'),
    (3,  'Pentavalente acelular'),
    (4,  'Hepatitis B (serie)'),
    (5,  'Rotavirus'),
    (6,  'Neumococo conjugada'),
    (7,  'Influenza'),
    (8,  'SRP'),
    (9,  'Pentavalente refuerzo'),
    (10, 'DPT (refuerzo)'),
    (11, 'OPV'),
    (12, 'VPH'),
]

TRABAJADORES = [
    (1,  'José Pérez'),
    (2,  'Lucía Santos'),
    (3,  'Mario Luna'),
    (4,  'Elisa Campos'),
    (5,  'Raúl Mora'),
    (6,  'Paty Ríos'),
    (7,  'Andrés León'),
    (8,  'Diana Paz'),
    (9,  'Iván Silva'),
    (10, 'Karen Vega'),
]

PACIENTES = [
    (1,  'Mateo García'),
    (2,  'Sofía Martínez'),
    (3,  'Diego López'),
    (4,  'Valentina Hernández'),
    (5,  'Lucas Ramírez'),
    (6,  'Emma Torres'),
    (7,  'Sebastián Flores'),
    (8,  'Camila Rivera'),
    (9,  'Leonardo Gómez'),
    (10, 'Renata Díaz'),
    (11, 'Emiliano Castro'),
    (12, 'Regina Ortiz'),
    (13, 'Daniel Morales'),
    (14, 'Victoria Ruiz'),
    (15, 'Ángel Navarro'),
]

TIPOS_EVENTO = [
    'login',
    'logout',
    'nfc_scan',
    'vacuna_aplicada',
    'cita_creada',
    'cita_cancelada',
    'alerta_generada',
]

TABLAS_AUDITORIA = [
    'vaccination_records',
    'appointments',
    'patients',
    'vaccine_lots',
    'workers',
    'nfc_cards',
    'guardians',
    'clinic_inventory',
]


# ── Helpers ───────────────────────────────────────────────────────────

def _rand_fecha(dias_atras):
    inicio = datetime.utcnow() - timedelta(days=dias_atras)
    return inicio + timedelta(seconds=random.randint(0, dias_atras * 86400))


# ── Generadores ───────────────────────────────────────────────────────

def generar_eventos(n=500):
    docs = []
    for _ in range(n):
        tipo = random.choice(TIPOS_EVENTO)
        cid, _ = random.choice(CLINICAS)
        tid, _ = random.choice(TRABAJADORES)
        ts = _rand_fecha(60).replace(hour=random.randint(8, 18), minute=random.randint(0, 59))

        paciente_id = None
        if tipo in ('nfc_scan', 'vacuna_aplicada', 'cita_creada', 'cita_cancelada', 'alerta_generada'):
            paciente_id = random.choice(PACIENTES)[0]

        payload = {}
        if tipo == 'nfc_scan':
            payload = {'accion': random.choice(['Registrar_Llegada', 'Abrir_Expediente'])}
        elif tipo == 'vacuna_aplicada':
            vid, vnombre = random.choice(VACUNAS)
            payload = {'vacuna_id': vid, 'vacuna': vnombre}
        elif tipo in ('cita_creada', 'cita_cancelada'):
            payload = {'cita_id': random.randint(1, 100)}
        elif tipo == 'alerta_generada':
            payload = {'tipo_alerta': random.choice(['Proximidad', 'Atraso', 'Critico'])}

        docs.append({
            'tipo':          tipo,
            'timestamp':     ts,
            'paciente_id':   paciente_id,
            'trabajador_id': tid,
            'clinica_id':    cid,
            'payload':       payload,
            'ip':            f'192.168.1.{random.randint(10, 250)}',
            'resultado':     'ok' if random.random() > 0.07 else 'error',
        })
    return docs


def generar_historial(n=400):
    docs = []
    for i in range(n):
        cid, cnombre = random.choice(CLINICAS)
        vid, vnombre = random.choice(VACUNAS)
        tid, tnombre = random.choice(TRABAJADORES)
        pid, pnombre = random.choice(PACIENTES)
        fecha = _rand_fecha(365)
        reaccion = random.random() < 0.06

        docs.append({
            'pg_record_id':      10000 + i,
            'fecha_aplicacion':  fecha,
            'anio_mes':          fecha.strftime('%Y-%m'),
            'paciente_id':       pid,
            'paciente_nombre':   pnombre,
            'vacuna_id':         vid,
            'vacuna_nombre':     vnombre,
            'clinica_id':        cid,
            'clinica_nombre':    cnombre,
            'trabajador_id':     tid,
            'trabajador_nombre': tnombre,
            'tuvo_reaccion':     reaccion,
            'temperatura_c':     round(random.uniform(36.2, 38.5 if reaccion else 37.2), 1),
        })
    return docs


def generar_auditoria(n=300):
    acciones = ['INSERT', 'UPDATE', 'DELETE']
    pesos    = [0.35, 0.55, 0.10]
    docs = []
    for _ in range(n):
        accion = random.choices(acciones, weights=pesos)[0]
        tabla  = random.choice(TABLAS_AUDITORIA)
        tid, tnombre = random.choice(TRABAJADORES)
        fecha = _rand_fecha(30).replace(hour=random.randint(8, 19), minute=random.randint(0, 59))

        cambios = {}
        if accion == 'UPDATE':
            campo = random.choice(['status', 'phone', 'quantity', 'is_active'])
            cambios = {campo: {'antes': 'valor_anterior', 'despues': 'valor_nuevo'}}
        elif accion == 'INSERT':
            cambios = {'creado': True}
        else:
            cambios = {'motivo': 'solicitud del usuario'}

        docs.append({
            'tabla':             tabla,
            'record_id':         random.randint(1, 500),
            'accion':            accion,
            'cambios':           cambios,
            'trabajador_id':     tid,
            'trabajador_nombre': tnombre,
            'fecha':             fecha,
            'ip':                f'192.168.1.{random.randint(10, 250)}',
        })
    return docs


# ── Carga ─────────────────────────────────────────────────────────────

def cargar(limpiar=True):
    from mongo.conexion import get_db
    db = get_db()
    if db is None:
        print('[ERROR] MongoDB no disponible')
        return

    if limpiar:
        db.eventos.delete_many({})
        db.historial_vacunacion.delete_many({})
        db.auditoria.delete_many({})
        print('[OK] Colecciones limpiadas')

    ev = generar_eventos(500)
    hi = generar_historial(400)
    au = generar_auditoria(300)

    db.eventos.insert_many(ev)
    db.historial_vacunacion.insert_many(hi)
    db.auditoria.insert_many(au)

    print(f'[OK] eventos:              {db.eventos.count_documents({})}')
    print(f'[OK] historial_vacunacion: {db.historial_vacunacion.count_documents({})}')
    print(f'[OK] auditoria:            {db.auditoria.count_documents({})}')


# ── Exportar a JSON ───────────────────────────────────────────────────

def exportar():
    from mongo.conexion import get_db
    db = get_db()
    if db is None:
        print('[ERROR] MongoDB no disponible para exportar')
        return

    out = Path(__file__).resolve().parent / 'collections'
    out.mkdir(exist_ok=True)

    def serial(o):
        if isinstance(o, datetime):
            return o.isoformat()
        try:
            from bson import ObjectId
            if isinstance(o, ObjectId):
                return str(o)
        except ImportError:
            pass
        return str(o)

    for nombre in ('eventos', 'historial_vacunacion', 'auditoria'):
        docs = list(db[nombre].find())
        for d in docs:
            d.pop('_id', None)
        ruta = out / f'{nombre}.json'
        with open(ruta, 'w', encoding='utf-8') as f:
            json.dump(docs, f, ensure_ascii=False, indent=2, default=serial)
        print(f'  → {ruta} ({len(docs)} docs)')


# ── CLI ───────────────────────────────────────────────────────────────

if __name__ == '__main__':
    exportar_flag = '--export' in sys.argv
    cargar()
    if exportar_flag:
        print('\nExportando colecciones...')
        exportar()
