# Stops what scripts\demo.ps1 started (Flutter web server and - only if demo.ps1 started it - the backend).
# A backend that was already running before demo.ps1 is left untouched unless you pass -Backend.
#   .\scripts\stop-demo.ps1            stop what demo.ps1 started
#   .\scripts\stop-demo.ps1 -Backend   additionally stop whatever listens on the backend port
param([switch]$Backend, [int]$BackendPort = 8080, [int]$WebPort = 5555)
$root = Split-Path -Parent $PSScriptRoot
$stateDir = Join-Path $root '.demo'

function Stop-Tree($processId, $label) {
    if (-not $processId) { return }
    if (Get-Process -Id $processId -ErrorAction SilentlyContinue) {
        cmd.exe /c "taskkill /T /F /PID $processId >nul 2>&1"
        Write-Host "Beendet: $label (PID $processId)" -ForegroundColor Green
    }
}

# Flutter web server: process started by demo.ps1 plus whatever still listens on the web port
$flutterPidFile = Join-Path $stateDir 'flutter.pid'
if (Test-Path $flutterPidFile) { Stop-Tree ([int](Get-Content $flutterPidFile)) 'Flutter (demo.ps1)'; Remove-Item $flutterPidFile }
$l = Get-NetTCPConnection -LocalPort $WebPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($l) { Stop-Tree $l.OwningProcess "Flutter-Webserver auf Port $WebPort" }

# Backend only if demo.ps1 started it (PID file) or -Backend was given
$backendPidFile = Join-Path $stateDir 'backend.pid'
if (Test-Path $backendPidFile) {
    Stop-Tree ([int](Get-Content $backendPidFile)) 'Backend (demo.ps1)'
    Remove-Item $backendPidFile
    $l = Get-NetTCPConnection -LocalPort $BackendPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($l) { Stop-Tree $l.OwningProcess "Backend-Java auf Port $BackendPort" }
} elseif ($Backend) {
    $l = Get-NetTCPConnection -LocalPort $BackendPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($l) { Stop-Tree $l.OwningProcess "Backend auf Port $BackendPort" } else { Write-Host "Kein Backend auf Port $BackendPort." }
} else {
    $l = Get-NetTCPConnection -LocalPort $BackendPort -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($l) { Write-Host "Backend auf Port $BackendPort wurde nicht von demo.ps1 gestartet und bleibt laufen (zum Beenden: -Backend)." -ForegroundColor Yellow }
}
Write-Host 'Fertig.'
