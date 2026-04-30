@echo off
setlocal

cd /d "%~dp0"

echo ===========================================
echo  INICIANDO APP
echo ===========================================

call :load_env

echo [1/4] Verificando entorno virtual...
if not exist ".venv\Scripts\python.exe" (
    echo [ERROR] No existe entorno virtual.
    echo [TIP] Ejecuta primero CONFIGURAR_ENTORNO.bat.
    pause
    exit /b 1
)

set "VENV_PY=.venv\Scripts\python.exe"
if not exist "%VENV_PY%" (
    echo [ERROR] No existe el Python del entorno virtual.
    pause
    exit /b 1
)

echo [2/4] Verificando dependencias...
"%VENV_PY%" -c "import flask, psycopg, bcrypt" >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Faltan dependencias en el entorno virtual.
    echo [TIP] Ejecuta primero CONFIGURAR_ENTORNO.bat.
    pause
    exit /b 1
)

echo [3/4] Verificando base de datos PostgreSQL...
if "%DATABASE_URL%"=="" (
    set "DATABASE_URL=postgresql://postgres:postgres@localhost:5432/sistemaVacunacion"
)
"%VENV_PY%" scripts\bootstrap_postgres.py
if errorlevel 1 (
    echo [ERROR] No se pudo inicializar la base de datos.
    echo [TIP] Verifica que PostgreSQL este encendido y que DATABASE_URL sea valida.
    pause
    exit /b 1
)

echo [4/4] Iniciando servidor Flask...
start "" http://127.0.0.1:5000
"%VENV_PY%" app_2daE.py

exit /b 0

:load_env
if exist ".env" (
    for /f "usebackq eol=# tokens=1,* delims==" %%A in (".env") do (
        if not "%%A"=="" set "%%A=%%B"
    )
)
exit /b 0
