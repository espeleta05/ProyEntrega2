import os
from dotenv import load_dotenv

load_dotenv()

SECRET_KEY = os.getenv("SECRET_KEY", "segunda-entrega-demo")
DB_ENGINE = os.getenv("DB_ENGINE", "postgres").strip().lower()
if DB_ENGINE not in {"postgres", "mariadb"}:
    DB_ENGINE = "postgres"

# PostgreSQL
PG_HOST = os.getenv("PG_HOST", "localhost")
PG_PORT = os.getenv("PG_PORT", "5432")
PG_USER = os.getenv("PG_USER", "PG_USER")
PG_PASSWORD = os.getenv("PG_PASSWORD", "PG_PASSWORD")
PG_DB = os.getenv("PG_DB", "PG_DB")

# MariaDB / MySQL
MYSQL_HOST = os.getenv("MYSQL_HOST", "localhost")
MYSQL_PORT = os.getenv("MYSQL_PORT", "3306")
MYSQL_USER = os.getenv("MYSQL_USER", "root")
MYSQL_PASSWORD = os.getenv("MYSQL_PASSWORD", "root")
MYSQL_DB = os.getenv("MYSQL_DB", "sistemavacunacion")


def build_postgres_url() -> str:
    return f"postgresql://{PG_USER}:{PG_PASSWORD}@{PG_HOST}:{PG_PORT}/{PG_DB}"


def build_mysql_url() -> str:
    return f"mysql://{MYSQL_USER}:{MYSQL_PASSWORD}@{MYSQL_HOST}:{MYSQL_PORT}/{MYSQL_DB}"


DATABASE_URL = build_postgres_url() if DB_ENGINE == "postgres" else build_mysql_url()


def _database_url_hint() -> str:
    if DB_ENGINE == "postgres":
        return f"{PG_USER}@{PG_HOST}:{PG_PORT}/{PG_DB}"
    return f"{MYSQL_USER}@{MYSQL_HOST}:{MYSQL_PORT}/{MYSQL_DB}"