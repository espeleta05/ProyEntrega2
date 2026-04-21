@echo off
setlocal

cd /d "%~dp0"

echo ===========================================
echo  INSTALACION INICIAL (SOLO 1 VEZ)
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

set "VENV_PY=.venv\Scripts\python.exe"
set "VENV_PIP=.venv\Scripts\pip.exe"
if not exist "%VENV_PY%" (
    echo [ERROR] No existe el Python del entorno virtual.
    pause
    exit /b 1
)

echo [3/6] Actualizando pip...
"%VENV_PY%" -m pip install --upgrade pip
if errorlevel 1 (
    echo [ERROR] Fallo al actualizar pip.
    pause
    exit /b 1
)

echo [4/6] Instalando dependencias del proyecto...
"%VENV_PIP%" install -r requirements_2daE.txt
if errorlevel 1 (
    echo [ERROR] Fallo instalando dependencias.
    pause
    exit /b 1
)

echo [4.1/6] Instalando wrapper binario de psycopg...
"%VENV_PIP%" install psycopg-binary==3.2.13
if errorlevel 1 (
    echo [ERROR] No se pudo instalar psycopg-binary.
    echo [TIP] Instala Python 3.12/3.13 y vuelve a ejecutar este instalador.
    pause
    exit /b 1
)

echo [5/6] Limpiando driver no requerido (psycopg2-binary)...
"%VENV_PIP%" uninstall -y psycopg2-binary >nul 2>nul

echo [6/6] Inicializando base de datos PostgreSQL...
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

echo [OK] Instalacion inicial terminada.
echo [OK] Ahora usa INICIAR_TODO.bat para ejecutar sin reinstalar.
pause
endlocal
