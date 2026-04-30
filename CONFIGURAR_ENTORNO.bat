@echo off
setlocal

cd /d "%~dp0"

echo ===========================================
echo  CONFIGURAR ENTORNO PARA ESTA MAQUINA
echo ===========================================

echo Este asistente deja lista la maquina: crea .env, entorno virtual, dependencias y base.
echo.

call :load_env

if exist ".env" (
    choice /m "Ya existe .env. Deseas reescribirlo"
    if errorlevel 2 goto after_env
)

set /p DB_HOST=Host de PostgreSQL [127.0.0.1]: 
if "%DB_HOST%"=="" set "DB_HOST=127.0.0.1"

set /p DB_PORT=Puerto de PostgreSQL [5432]: 
if "%DB_PORT%"=="" set "DB_PORT=5432"

set /p DB_NAME=Nombre de la base [sistemaVacunacion]: 
if "%DB_NAME%"=="" set "DB_NAME=sistemaVacunacion"

set /p DB_USER=Usuario de PostgreSQL [postgres]: 
if "%DB_USER%"=="" set "DB_USER=postgres"

set /p DB_PASSWORD=Contrasena de PostgreSQL: 
set "DATABASE_URL=postgresql://%DB_USER%:%DB_PASSWORD%@%DB_HOST%:%DB_PORT%/%DB_NAME%"

echo SECRET_KEY=segunda-entrega-demo> .env
echo DATABASE_URL=%DATABASE_URL%>> .env

:after_env
call :load_env

echo [1/5] Buscando Python...
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

echo [2/5] Creando entorno virtual...
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

echo [3/5] Actualizando pip...
"%VENV_PY%" -m pip install --upgrade pip
if errorlevel 1 (
    echo [ERROR] Fallo al actualizar pip.
    pause
    exit /b 1
)

echo [4/5] Instalando dependencias...
"%VENV_PIP%" install -r requirements_2daE.txt
if errorlevel 1 (
    echo [ERROR] Fallo instalando dependencias.
    pause
    exit /b 1
)

echo [5/5] Inicializando base de datos PostgreSQL...
"%VENV_PY%" scripts\bootstrap_postgres.py --force-reset
if errorlevel 1 (
    echo [ERROR] No se pudo inicializar la base de datos.
    echo [TIP] Verifica que PostgreSQL este encendido y que DATABASE_URL sea valida.
    pause
    exit /b 1
)

echo.
echo [OK] Configuracion terminada.
echo [OK] Ya puedes usar INICIAR_TODO.bat.
pause
exit /b 0

:load_env
if exist ".env" (
    for /f "usebackq eol=# tokens=1,* delims==" %%A in (".env") do (
        if not "%%A"=="" set "%%A=%%B"
    )
)
exit /b 0
