# Sistema de Vacunación Infantil

Sistema web de gestión clínica de vacunación infantil desarrollado con Flask, PostgreSQL y MongoDB, con una arquitectura de tres capas (presentación, lógica de negocio y datos).

---

## Tabla de Contenidos

1. [Descripción del Proyecto](#1-descripción-del-proyecto)
2. [Requisitos Previos](#2-requisitos-previos)
3. [Instalación de Dependencias del Sistema](#3-instalación-de-dependencias-del-sistema)
4. [Configuración de PostgreSQL](#4-configuración-de-postgresql)
5. [Configuración de MongoDB](#5-configuración-de-mongodb)
6. [Restauración de la Base de Datos](#6-restauración-de-la-base-de-datos)
7. [Configuración del Entorno Virtual Python](#7-configuración-del-entorno-virtual-python)
8. [Instalación de Dependencias Python](#8-instalación-de-dependencias-python)
9. [Configuración de Conexión a Base de Datos](#9-configuración-de-conexión-a-base-de-datos)
10. [Ejecución del Sistema](#10-ejecución-del-sistema)
11. [Configuración de Firewall](#11-configuración-de-firewall)
12. [Estructura del Proyecto](#12-estructura-del-proyecto)
13. [Recomendaciones](#13-recomendaciones)

---

## 1. Descripción del Proyecto

El **Sistema de Vacunación Infantil** es una aplicación web de gestión clínica diseñada para digitalizar y centralizar el proceso de vacunación pediátrica en centros de salud. Permite administrar el ciclo completo de atención desde la recepción del paciente hasta la generación de reportes, garantizando trazabilidad y seguridad en el registro de cada dosis aplicada.

El sistema utiliza **PostgreSQL** para la gestión de datos relacionales (pacientes, tutores, vacunas, citas) y **MongoDB** para el almacenamiento de datos no relacionales o documentales (como registros de auditoría, logs de actividad o reportes).

### Funcionalidades principales

| Módulo | Descripción |
|---|---|
| **Recepción** | Registro de llegada de pacientes y gestión de citas |
| **Pacientes** | Alta, consulta y edición de datos de niños |
| **Tutores** | Gestión de responsables legales asociados a cada paciente |
| **Vacunación** | Registro de vacunas aplicadas, lotes y fechas |
| **Reportes** | Generación de informes por paciente, vacuna o período |
| **NFC** | Identificación rápida de pacientes mediante tarjetas NFC |
| **Control de roles** | Vistas diferenciadas para recepcionista, enfermero y administrador |

### Stack tecnológico

- **Backend:** Python 3 + Flask
- **Base de datos relacional:** PostgreSQL (con stored procedures, triggers y vistas)
- **Base de datos documental:** MongoDB
- **Frontend:** HTML + CSS + JavaScript (plantillas Jinja2)
- **Arquitectura:** Three-tier (presentación · lógica de negocio · datos)

---

## 2. Requisitos Previos

Antes de comenzar, asegúrate de contar con lo siguiente en tu instancia Linux (Google Cloud VM):

- Sistema operativo Linux (RHEL / CentOS / Fedora recomendado)
- Acceso a internet desde la instancia
- Usuario con privilegios `sudo`
- Python 3.8 o superior
- PostgreSQL 13 o superior
- MongoDB 6.0 o superior
- `pip` (gestor de paquetes de Python)
- `git` (opcional, si se clona el repositorio)

---

## 3. Instalación de Dependencias del Sistema

Actualiza los paquetes del sistema e instala todas las dependencias necesarias:

```bash
sudo dnf update -y
sudo dnf install -y python3 python3-pip postgresql postgresql-server postgresql-contrib git
```

Para instalar MongoDB en RHEL/Fedora, agrega el repositorio oficial y luego instala:

```bash
cat <<'EOF' | sudo tee /etc/yum.repos.d/mongodb-org-6.0.repo
[mongodb-org-6.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/8/mongodb-org/6.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-6.0.asc
EOF

sudo dnf install -y mongodb-org
```

Verifica que las instalaciones fueron exitosas:

```bash
python3 --version
psql --version
mongod --version
```

---

## 4. Configuración de PostgreSQL

### 4.1 Inicializar la base de datos

Si es la primera vez que se configura PostgreSQL en la máquina, inicializa el clúster:

```bash
sudo postgresql-setup --initdb
```

### 4.2 Iniciar y habilitar el servicio

```bash
sudo systemctl start postgresql
sudo systemctl enable postgresql
```

Verifica que el servicio esté activo:

```bash
sudo systemctl status postgresql
```

### 4.3 Establecer contraseña para el usuario `postgres`

Accede al shell de PostgreSQL como superusuario:

```bash
sudo -u postgres psql
```

Dentro de `psql`, ejecuta:

```sql
ALTER USER postgres WITH PASSWORD 'tu_contraseña_segura';
\q
```

> Reemplaza `tu_contraseña_segura` por una contraseña de tu elección. Guárdala, la necesitarás en el paso 9.

### 4.4 Crear la base de datos

```bash
sudo -u postgres createdb sistemavacunacion
```

---

## 5. Configuración de MongoDB

### 5.1 Iniciar y habilitar el servicio

```bash
sudo systemctl start mongod
sudo systemctl enable mongod
```

Verifica que el servicio esté activo:

```bash
sudo systemctl status mongod
```

### 5.2 Acceder al shell de MongoDB

```bash
mongosh
```

### 5.3 Crear la base de datos y usuario de la aplicación

Dentro del shell de MongoDB, ejecuta:

```javascript
use sistemavacunacion_mongo

db.createUser({
  user: "mongouser",
  pwd: "tu_contraseña_mongo",
  roles: [{ role: "readWrite", db: "sistemavacunacion_mongo" }]
})

exit
```

> Reemplaza `tu_contraseña_mongo` por una contraseña de tu elección. Guárdala, la necesitarás en el paso 9.

### 5.4 (Opcional) Habilitar autenticación

Si deseas requerir autenticación para conectarse, edita el archivo de configuración de MongoDB:

```bash
sudo nano /etc/mongod.conf
```

Busca la sección `security` y activa la autenticación:

```yaml
security:
  authorization: enabled
```

Luego reinicia el servicio:

```bash
sudo systemctl restart mongod
```

---

## 6. Restauración de la Base de Datos

### 6.1 Restaurar PostgreSQL

El archivo de respaldo `sistemavacunacionBACKUP3.sql` **debe estar incluido en el proyecto** (en la raíz del directorio descomprimido).

Para restaurar el esquema completo, datos de prueba, stored procedures, triggers y vistas, ejecuta:

```bash
sudo -u postgres psql -d sistemavacunacion -f sistemavacunacionBACKUP3.sql
```

Si el archivo se encuentra en otro directorio, proporciona la ruta absoluta:

```bash
sudo -u postgres psql -d sistemavacunacion -f /ruta/completa/sistemavacunacionBACKUP3.sql
```

> Espera a que el proceso finalice sin errores antes de continuar. Cualquier error en esta etapa afectará el funcionamiento del sistema.

### 6.2 Restaurar MongoDB

Si el proyecto incluye un respaldo de MongoDB (exportado con `mongodump`), restáuralo con:

```bash
mongorestore --db sistemavacunacion_mongo /ruta/al/respaldo/mongo/
```

Si el respaldo fue exportado en formato JSON con `mongoexport`, impórtalo colección por colección:

```bash
mongoimport --db sistemavacunacion_mongo --collection nombre_coleccion --file nombre_coleccion.json
```

---

## 7. Configuración del Entorno Virtual Python

Desde la raíz del proyecto descomprimido, crea y activa un entorno virtual para aislar las dependencias:

```bash
python3 -m venv venv
source venv/bin/activate
```

Tu prompt de terminal debería mostrar `(venv)` al inicio, indicando que el entorno está activo.

> Para desactivar el entorno virtual en cualquier momento, ejecuta `deactivate`.

---

## 8. Instalación de Dependencias Python

Con el entorno virtual activo, instala todas las librerías necesarias:

```bash
pip install --upgrade pip
pip install -r requirements.txt
```

Si se presentan errores de compilación, instala las dependencias de desarrollo del sistema:

```bash
sudo dnf install -y python3-devel libpq-devel gcc
```

Luego vuelve a ejecutar `pip install -r requirements.txt`.

---

## 9. Configuración de Conexión a Base de Datos

El sistema requiere configurar la conexión a **dos bases de datos**: PostgreSQL y MongoDB. Busca en el proyecto el archivo de configuración (puede llamarse `config.py`, `db.py`, `database.py` o estar directamente en `app_2daE.py`) y ajusta los siguientes valores:

### 9.1 PostgreSQL

| Parámetro | Valor |
|---|---|
| `host` | `localhost` |
| `user` | `postgres` |
| `password` | la contraseña definida en el paso 4.3 |
| `port` | `5432` |
| `database` | `sistemavacunacion` |

#### Ejemplo de configuración

```python
PG_CONFIG = {
    "host": "localhost",
    "user": "postgres",
    "password": "tu_contraseña_segura",
    "port": 5432,
    "database": "sistemavacunacion"
}
```

O en formato de cadena de conexión (SQLAlchemy / psycopg2):

```python
POSTGRES_URL = "postgresql://postgres:tu_contraseña_segura@localhost:5432/sistemavacunacion"
```

### 9.2 MongoDB

| Parámetro | Valor |
|---|---|
| `host` | `localhost` |
| `user` | `mongouser` |
| `password` | la contraseña definida en el paso 5.3 |
| `port` | `27017` |
| `database` | `sistemavacunacion_mongo` |

#### Ejemplo de configuración

```python
MONGO_CONFIG = {
    "host": "localhost",
    "port": 27017,
    "user": "mongouser",
    "password": "tu_contraseña_mongo",
    "database": "sistemavacunacion_mongo"
}
```

O en formato de cadena de conexión (PyMongo):

```python
MONGO_URL = "mongodb://mongouser:tu_contraseña_mongo@localhost:27017/sistemavacunacion_mongo"
```

> Asegúrate de que los valores de ambas bases de datos coincidan exactamente con los configurados en los pasos 4 y 5.

---

## 10. Ejecución del Sistema

### 10.1 Definir el punto de entrada de Flask

```bash
export FLASK_APP=app_2daE.py
```

### 10.2 (Opcional) Activar el modo de desarrollo

```bash
export FLASK_ENV=development
```

### 10.3 Iniciar el servidor

```bash
flask run --host=0.0.0.0
```

El sistema quedará disponible en el puerto `5000`. Abre un navegador y accede usando la IP pública de tu instancia:

```
http://IP_DE_LA_INSTANCIA:5000
```

> Puedes obtener la IP pública de tu VM desde la consola de Google Cloud, en la sección **Compute Engine > Instancias de VM**.

---

## 11. Configuración de Firewall

Para que el puerto `5000` sea accesible desde el exterior, configura el firewall del sistema operativo:

```bash
sudo firewall-cmd --permanent --add-port=5000/tcp
sudo firewall-cmd --reload
```

Verifica que la regla quedó activa:

```bash
sudo firewall-cmd --list-ports
```

> Adicionalmente, asegúrate de que en la consola de Google Cloud el firewall de VPC permita el tráfico entrante en el puerto `5000` (regla de red en **Red de VPC > Firewall**).

---

## 12. Estructura del Proyecto

Al descomprimir el archivo `.zip`, deberías encontrar la siguiente estructura:

```
ProyEntrega2/
├── app_2daE.py                     # Punto de entrada principal de Flask
├── requirements.txt                # Dependencias Python del proyecto
├── sistemavacunacionBACKUP3.sql    # Respaldo completo de PostgreSQL
├── templates/                      # Plantillas HTML (Jinja2) por módulo
│   ├── recepcion/
│   ├── pacientes/
│   ├── vacunacion/
│   └── ...
├── static/                         # Archivos estáticos (CSS, JS, imágenes)
│   ├── css/
│   ├── js/
│   └── img/
├── sql/                            # Scripts SQL auxiliares (opcional)
├── controllers/                    # Lógica de negocio por módulo
├── models/                         # Acceso y consulta a las bases de datos
└── ...
```

---

## 13. Recomendaciones

### Tras restaurar PostgreSQL

- Verifica que los **triggers** se cargaron correctamente consultando `pg_trigger`.
- Confirma que los **stored procedures** estén disponibles consultando `pg_proc`.
- Valida que las **vistas** existan consultando `pg_views`.

```sql
-- Conectarse a la base de datos
sudo -u postgres psql -d sistemavacunacion

-- Listar triggers
SELECT trigger_name, event_object_table FROM information_schema.triggers;

-- Listar funciones/SPs
SELECT routine_name FROM information_schema.routines WHERE routine_type = 'FUNCTION';

-- Listar vistas
SELECT table_name FROM information_schema.views WHERE table_schema = 'public';
```

### Tras restaurar MongoDB

- Verifica que las colecciones se importaron correctamente:

```javascript
use sistemavacunacion_mongo
show collections
db.nombre_coleccion.countDocuments()
```

### Buenas prácticas generales

- No incluyas la carpeta `venv/` en el `.zip` ni en el repositorio; cada desarrollador debe generarla localmente.
- No distribuyas archivos `.sql` ni respaldos de MongoDB con datos sensibles de producción.
- Utiliza un archivo `.gitignore` que excluya al menos:

```
venv/
__pycache__/
*.pyc
*.sql
dump/
.env
*.log
```

- Considera usar variables de entorno (`.env` + `python-dotenv`) para manejar credenciales de ambas bases de datos en lugar de escribirlas directamente en el código.

---

> **Proyecto:** Sistema de Vacunación Infantil  
> **Stack:** Flask + PostgreSQL + MongoDB  
> **Entorno objetivo:** Google Cloud VM (Linux / RHEL)
