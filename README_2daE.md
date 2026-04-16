# Segunda Entrega (Flask + PostgreSQL)

Esta carpeta contiene el sistema en Flask + HTML con soporte para PostgreSQL.

## Credenciales demo
- Usuario: `admin`
- Contrasena: `123`

## Credenciales PostgreSQL
Si configuras PostgreSQL, el login usa la tabla `workers` y `worker_emails`.
La contrasena del seed SQL debe coincidir con la que tengas cargada en tu base; usa ese valor real al iniciar sesion.

## Variables de entorno
Configura una de estas opciones antes de ejecutar Flask:
- `DATABASE_URL=postgresql://usuario:contrasena@host:5432/sistemaVacunacion`
- o `PGHOST`, `PGPORT`, `PGDATABASE`, `PGUSER`, `PGPASSWORD`

## NFC
El modulo NFC usa `nfc_id` y permite vincular y borrar uniones desde la pantalla `NFC Bridge`.

## Que incluye
- Backend Flask con datos hardcodeados en memoria.
- HTML completos con sufijo `_2daE`.
- CSS copiados desde el proyecto original.
- Scripts SQL para PostgreSQL normalizados y con SP simples.

## Ejecutar
1. Crear y activar entorno virtual (opcional).
2. Instalar dependencias:
   - `pip install -r segunda_entrega/requirements_2daE.txt`
3. Ejecutar:
   - `python segunda_entrega/app_2daE.py`
4. Abrir:
   - `http://127.0.0.1:5000`

## Nota
Si no configuras PostgreSQL, el sistema sigue funcionando con datos demo en memoria.
