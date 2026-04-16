@echo off
:: Cambiar al directorio del script
cd /d "%~dp0"

:: Activar entorno virtual
call .venv\Scripts\activate.bat

:: Configurar variables de entorno
set DATABASE_URL=postgresql://postgres@localhost:5432/sistemaVacunacion
set NFC_BRIDGE_TOKEN=mi_token_nfc_2026

:: Matar procesos en puerto 5000 (opcional, requiere netstat)
for /f "tokens=5" %%a in ('netstat -ano ^| findstr :5000 ^| findstr LISTENING') do (
    taskkill /PID %%a /F >nul 2>&1
)

:: Iniciar Flask
python -m flask --app app_2daE run --host 0.0.0.0 --port 5000
pause
