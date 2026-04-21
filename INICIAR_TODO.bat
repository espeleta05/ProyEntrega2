@echo off
setlocal

cd /d "%~dp0"

echo ===========================================
echo  INICIANDO APP (SIN REINSTALAR)
echo ===========================================

echo [1/5] Verificando entorno virtual...
if not exist ".venv\Scripts\python.exe" (
    echo [ERROR] No existe entorno virtual.
    echo [TIP] Ejecuta primero INSTALAR_PRIMERA_VEZ.bat
    pause
    exit /b 1
)

set "VENV_PY=.venv\Scripts\python.exe"
if not exist "%VENV_PY%" (
    echo [ERROR] No existe el Python del entorno virtual.
    pause
    exit /b 1
)

echo [2/5] Verificando dependencias...
"%VENV_PY%" -c "import flask, psycopg, bcrypt" >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Faltan dependencias en el entorno virtual.
    echo [TIP] Ejecuta INSTALAR_PRIMERA_VEZ.bat para instalarlas.
    pause
    exit /b 1
)

echo [3/5] Verificando base de datos PostgreSQL...
if "%DATABASE_URL%"=="" (
    set "DATABASE_URL=postgresql://postgres:postgres@localhost:5432/sistemaVacunacion"
)
"%VENV_PY%" scripts\bootstrap_postgres.py
if errorlevel 1 (
    echo [ERROR] No se pudo inicializar la base de datos.
    echo [TIP] Verifica que PostgreSQL este encendido y que DATABASE_URL sea valida.
    echo [TIP] Si quieres reiniciar todo manualmente usa: python scripts\bootstrap_postgres.py --force-reset
    pause
    exit /b 1
)

echo [4/5] Probando conexion a la base...
"%VENV_PY%" -c "import os, psycopg; conn=psycopg.connect(os.getenv('DATABASE_URL','postgresql://postgres:postgres@localhost:5432/sistemaVacunacion')); cur=conn.cursor(); cur.execute('SELECT 1'); print(cur.fetchone()[0]); conn.close()" >nul 2>nul
if errorlevel 1 (
    echo [ERROR] La conexion a PostgreSQL fallo.
    pause
    exit /b 1
)

echo [5/5] Iniciando servidor Flask...
start "" http://127.0.0.1:5000
"%VENV_PY%" app_2daE.py

endlocal
