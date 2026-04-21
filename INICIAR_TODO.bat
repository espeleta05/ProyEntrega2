@echo off
setlocal

cd /d "%~dp0"

echo ===========================================
echo  INICIANDO SETUP COMPLETO (1 clic)
echo ===========================================

echo [1/6] Buscando Python...
where py >nul 2>nul
if %errorlevel%==0 (
    set "PYTHON_CMD=py -3"
) else (
    where python >nul 2>nul
    if %errorlevel%==0 (
        set "PYTHON_CMD=python"
    ) else (
        echo [ERROR] No se encontro Python. Instala Python 3.10+ y vuelve a intentar.
        pause
        exit /b 1
    )
)

echo [2/6] Creando entorno virtual...
if not exist ".venv\Scripts\python.exe" (
    %PYTHON_CMD% -m venv .venv
    if errorlevel 1 (
        echo [ERROR] No se pudo crear el entorno virtual.
        pause
        exit /b 1
    )
)

call ".venv\Scripts\activate.bat"
if errorlevel 1 (
    echo [ERROR] No se pudo activar el entorno virtual.
    pause
    exit /b 1
)

echo [3/6] Actualizando pip...
python -m pip install --upgrade pip
if errorlevel 1 (
    echo [ERROR] Fallo al actualizar pip.
    pause
    exit /b 1
)

echo [4/6] Instalando dependencias...
pip install -r requirements_2daE.txt
if errorlevel 1 (
    echo [ERROR] Fallo instalando dependencias.
    pause
    exit /b 1
)

echo [5/6] Verificando base de datos PostgreSQL...
if "%DATABASE_URL%"=="" (
    set "DATABASE_URL=postgresql://postgres:postgres@localhost:5432/sistemaVacunacion"
)
python scripts\bootstrap_postgres.py
if errorlevel 1 (
    echo [ERROR] No se pudo inicializar la base de datos.
    echo [TIP] Verifica que PostgreSQL este encendido y que DATABASE_URL sea valida.
    echo [TIP] Si quieres reiniciar todo manualmente usa: python scripts\bootstrap_postgres.py --force-reset
    pause
    exit /b 1
)

echo [6/6] Iniciando servidor Flask...
start "" http://127.0.0.1:5000
python app_2daE.py

endlocal
