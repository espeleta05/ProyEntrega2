@echo off
setlocal
cd /d "%~dp0"

echo [0/2] Instalando dependencias...
call "%~dp0INSTALAR_DEPENDENCIAS.bat"
if errorlevel 1 (
    echo [ERROR] Fallo la instalacion de dependencias.
    pause
    exit /b 1
)

if exist ".env" (
    for /f "usebackq eol=# tokens=1,* delims==" %%A in (".env") do (
        if not "%%A"=="" set "%%A=%%B"
    )
)

set "VENV_PY=.venv\Scripts\python.exe"

REM Entrada oficial de Flask: modulo app_2daE, instancia app
REM Equivale a: export FLASK_APP=app_2daE:app   (Linux/macOS)
set "FLASK_APP=app_2daE:app"

if not defined FLASK_DEBUG set "FLASK_DEBUG=1"

echo [1/2] Inicializando base de datos ^(flask init-db^)...
"%VENV_PY%" -m flask init-db
if errorlevel 1 (
    echo [ERROR] flask init-db fallo. Revisa .env y el motor de base de datos.
    pause
    exit /b 1
)

echo [2/2] Servidor Flask ^(flask run^) en http://127.0.0.1:5000
start "" http://127.0.0.1:5000
"%VENV_PY%" -m flask run --host=127.0.0.1 --port=5000
