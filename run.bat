@echo off
setlocal
:: Cambiar al directorio del script
cd /d "%~dp0"

:: Activar entorno virtual
call .venv\Scripts\activate.bat

:: Definir python del entorno virtual explicitamente
set "PYTHON_EXE=%~dp0.venv\Scripts\python.exe"
if not exist "%PYTHON_EXE%" (
    echo [ERROR] No se encontro Python del entorno virtual: %PYTHON_EXE%
    pause
    exit /b 1
)

:: Configurar variables de entorno
set DATABASE_URL=postgresql://postgres@localhost:5432/sistemaVacunacion
set NFC_BRIDGE_TOKEN=mi_token_nfc_2026

:: Verificar conectividad a BD antes de iniciar Flask
"%PYTHON_EXE%" -c "import app_2daE; import sys; ok=(app_2daE._db_configured() and app_2daE._db_is_reachable()); print('DB_OK='+str(ok)); sys.exit(0 if ok else 1)"
if errorlevel 1 (
    echo [ERROR] No hay conexion a PostgreSQL. Revisa DATABASE_URL y servicio de postgres.
    pause
    exit /b 1
)

:: Matar procesos en puerto 5000 (opcional, requiere netstat)
for /f "tokens=5" %%a in ('netstat -ano ^| findstr :5000 ^| findstr LISTENING') do (
    taskkill /PID %%a /F >nul 2>&1
)

:: Iniciar Flask
"%PYTHON_EXE%" -m flask --app app_2daE run --host 0.0.0.0 --port 5000
pause
endlocal
