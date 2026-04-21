@echo off
setlocal

cd /d "%~dp0"

echo ===========================================
echo  CONFIGURAR ENTORNO PARA ESTA MAQUINA
echo ===========================================

echo Este asistente crea el archivo .env para que la app use la base correcta.
echo.

if exist ".env" (
    choice /m "Ya existe .env. Deseas reescribirlo"
    if errorlevel 2 (
        echo Se conservara el .env actual.
        pause
        exit /b 0
    )
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

echo SECRET_KEY=segunda-entrega-demo> .env
echo DATABASE_URL=postgresql://%DB_USER%:%DB_PASSWORD%@%DB_HOST%:%DB_PORT%/%DB_NAME%>> .env

echo.
echo [OK] Archivo .env creado.
echo [TIP] Si quieres revisarlo, se abrira en el Bloc de notas.
start notepad .env
pause
endlocal
