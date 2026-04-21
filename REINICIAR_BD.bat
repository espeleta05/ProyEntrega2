@echo off
setlocal

cd /d "%~dp0"

if "%DATABASE_URL%"=="" (
    set "DATABASE_URL=postgresql://postgres:postgres@localhost:5432/sistemaVacunacion"
)

if not exist ".venv\Scripts\python.exe" (
    echo [ERROR] No existe entorno virtual. Ejecuta primero INICIAR_TODO.bat
    pause
    exit /b 1
)

call ".venv\Scripts\activate.bat"
python scripts\bootstrap_postgres.py --force-reset

if errorlevel 1 (
    echo [ERROR] No se pudo reiniciar la base de datos.
    pause
    exit /b 1
)

echo [OK] Base de datos reiniciada correctamente.
pause
endlocal
