@echo off
setlocal

cd /d "%~dp0"

if not exist ".venv\Scripts\python.exe" (
    py -3 -m venv .venv 2>nul || python -m venv .venv
)

if not exist ".venv\Scripts\python.exe" (
    echo [ERROR] No se pudo crear el entorno virtual.
    exit /b 1
)

set "VENV_PY=.venv\Scripts\python.exe"

"%VENV_PY%" -m pip install --upgrade pip
"%VENV_PY%" -m pip install -r requirements.txt
:: instalar herramientas adicionales necesarias
"%VENV_PY%" -m pip install psycopg[binary] requests --upgrade

echo [OK] Dependencias instaladas.

:: Crear .env si no existe con valores por defecto (no sobreescribe)
if not exist .env (
    echo PG_USER=mi_usuario> .env
    echo PG_PASSWORD=666>> .env
    echo PG_DB=sistemavacunacion>> .env
    echo PG_HOST=localhost>> .env
    echo PG_PORT=5432>> .env
    echo [INFO] Archivo .env creado con valores por defecto (PG_PASSWORD=666). Editalo si es necesario.
)

:: Preguntar si ejecutar la migración ahora
set /p RUNMIG="¿Deseas ejecutar la migración ahora? (S/N) > "
if /I "%RUNMIG%"=="S" (
    echo Introduce PG_SUPERUSER_URL (enter para omitir):
    set /p SUPERURL=
    if not "%SUPERURL%"=="" (
        set "PG_SUPERUSER_URL=%SUPERURL%"
    )
    echo Si la base necesita crearse/aplicarse esquema, escribe 1 para APPLY_SCHEMA, sino deja vacío:
    set /p APPLYSC=
    if "%APPLYSC%"=="1" set "APPLY_SCHEMA=1"
    echo Ejecutando run_migration_all.py ...
    set "PG_SUPERUSER_URL=%PG_SUPERUSER_URL%"
    set "APPLY_SCHEMA=%APPLY_SCHEMA%"
    "%VENV_PY%" .\run_migration_all.py
)

exit /b 0
