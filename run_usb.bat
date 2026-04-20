@echo off
setlocal
cd /d "%~dp0"

set "ADB=%LOCALAPPDATA%\Microsoft\WinGet\Packages\Google.PlatformTools_Microsoft.Winget.Source_8wekyb3d8bbwe\platform-tools\adb.exe"

if not exist "%ADB%" (
  echo [ERROR] No se encontro adb en: %ADB%
  echo Instala Android Platform-Tools o ajusta la ruta en este archivo.
  pause
  exit /b 1
)

echo Verificando telefono USB...
"%ADB%" devices

echo.
echo Si no aparece como "device":
echo 1) Activa Depuracion USB en el telefono
echo 2) Acepta la huella RSA
echo 3) Cambia USB a Transferencia de archivos
echo.

echo Creando tunel USB local (adb reverse tcp:5000 tcp:5000)...
"%ADB%" reverse tcp:5000 tcp:5000
if errorlevel 1 (
  echo [ERROR] No se pudo crear adb reverse. Revisa autorizacion USB.
  pause
  exit /b 1
)

call .venv\Scripts\activate.bat
set "PYTHON_EXE=%~dp0.venv\Scripts\python.exe"
if not exist "%PYTHON_EXE%" (
  echo [ERROR] No se encontro Python del entorno virtual: %PYTHON_EXE%
  pause
  exit /b 1
)
set DATABASE_URL=postgresql://postgres@localhost:5432/sistemaVacunacion
set NFC_BRIDGE_TOKEN=mi_token_nfc_2026

"%PYTHON_EXE%" -c "import app_2daE; import sys; ok=(app_2daE._db_configured() and app_2daE._db_is_reachable()); print('DB_OK='+str(ok)); sys.exit(0 if ok else 1)"
if errorlevel 1 (
  echo [ERROR] No hay conexion a PostgreSQL. Revisa DATABASE_URL y servicio de postgres.
  pause
  exit /b 1
)

echo.
echo Flask por USB listo.
echo En Automate usa URL: http://127.0.0.1:5000/api/nfc/ingest?token=mi_token_nfc_2026^&uid=... 
echo.
"%PYTHON_EXE%" -m flask --app app_2daE run --host 127.0.0.1 --port 5000

endlocal
