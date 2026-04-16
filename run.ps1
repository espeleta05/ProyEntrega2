# Configurar política de ejecución
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned -Force

# Obtener la ruta del script actual
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

# Cambiar al directorio de la aplicación
Set-Location $scriptPath

# Activar entorno virtual
& .\.venv\Scripts\Activate.ps1

# Configurar variables de entorno
$env:DATABASE_URL='postgresql://postgres@localhost:5432/sistemaVacunacion'
$env:NFC_BRIDGE_TOKEN='mi_token_nfc_2026'

# Matar cualquier proceso Flask en puerto 5000 antes de iniciar
$pid5000 = Get-NetTCPConnection -LocalPort 5000 -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique
if ($pid5000) {
    Stop-Process -Id $pid5000 -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
}

# Iniciar Flask
python -m flask --app app_2daE run --host 0.0.0.0 --port 5000
