# Segunda Entrega (Flask + DB configurable)

Aplicacion Flask con conexion centralizada en `config.py` y `db.py`.

## Requisitos
- Python 3.10+
- PostgreSQL 14+ o MariaDB/MySQL 10+
- Dependencias de Python:
  - `pip install -r requirements.txt`

## Configuracion de entorno
- Variable opcional `SECRET_KEY`
- Variable `DB_ENGINE` (`postgres` o `mariadb`)
- Variables `PG_*` para PostgreSQL y `MYSQL_*` para MariaDB
- Referencia de ejemplo: [.env.example](.env.example)

## Orden recomendado de SQL
1. `sql/esquema_postgres_2daE.sql`
2. `sql/vistas.sql`
3. `sql/SP.sql`
4. `sql/triggers.sql`
5. `sql/datos_postgres_2daE.sql`

## Ejecutar
1. Ejecutar `INSTALAR_DEPENDENCIAS.bat` una sola vez.
2. Configurar `.env` con `DB_ENGINE` y credenciales.
3. Ejecutar `INICIAR.bat` para levantar la app.

## Nota operativa
- El backend usa funciones SP para altas principales.
- Si las secuencias `SERIAL` quedaron desfasadas por inserts con IDs fijos del seed, el backend ya sincroniza secuencias antes de insertar.
