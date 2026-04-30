# Segunda Entrega (PostgreSQL + psycopg)

Aplicacion Flask conectada a PostgreSQL usando `psycopg`.

## Requisitos
- Python 3.10+
- PostgreSQL 14+
- Dependencias de Python:
  - `pip install -r requirements_2daE.txt`

## Configuracion de entorno
- Variable opcional `SECRET_KEY`
- Variable `DATABASE_URL` con el host, usuario y contrasena reales de la maquina donde corre PostgreSQL.
- Referencia de ejemplo: [.env.example](.env.example)
- Si no se define `DATABASE_URL`, la app intenta el valor local:
   - `postgresql://postgres:postgres@localhost:5432/sistemaVacunacion`
- En otra maquina, ese valor solo funcionara si existe un usuario `postgres` con esa clave y esa base de datos.

## Orden recomendado de SQL
1. `sql/esquema_postgres_2daE.sql`
2. `sql/vistas.sql`
3. `sql/SP.sql`
4. `sql/triggers.sql`
5. `sql/datos_postgres_2daE.sql`

## Ejecutar
1. Ejecutar `CONFIGURAR_ENTORNO.bat` una sola vez para crear `.env`, entorno virtual, dependencias y base.
2. Ejecutar `INICIAR_TODO.bat` para levantar la app.

## Nota operativa
- El backend usa funciones SP para altas principales.
- Si las secuencias `SERIAL` quedaron desfasadas por inserts con IDs fijos del seed, el backend ya sincroniza secuencias antes de insertar.
