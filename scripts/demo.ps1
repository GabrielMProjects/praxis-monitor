# Praxis Monitor - one-command demo start (Windows PowerShell 5.1+)
#
#   .\scripts\demo.ps1            start everything, open the browser
#   .\scripts\stop-demo.ps1       stop what this script started
#
# - Backend (Spring Boot, profile dev) on port 8080: an already running, healthy backend is REUSED and never stopped.
# - Frontend (Flutter web) on port 5555, opened in your default browser.
# - Logs and PID files live in <project>\.demo\
param(
    [int]$BackendPort = 8080,
    [int]$WebPort = 5555,
    [switch]$NoBrowser,
    [int]$BackendTimeoutSec = 120,
    [int]$FrontendTimeoutSec = 300
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$stateDir = Join-Path $root '.demo'
New-Item -ItemType Directory -Force $stateDir | Out-Null

function Fail($message) { Write-Host "`nFEHLER: $message" -ForegroundColor Red; exit 1 }
function Info($message) { Write-Host $message -ForegroundColor Cyan }
function Ok($message) { Write-Host $message -ForegroundColor Green }

function Test-Url($url, $timeoutSec = 3) {
    try { return (Invoke-WebRequest $url -UseBasicParsing -TimeoutSec $timeoutSec).StatusCode -eq 200 } catch { return $false }
}
function Get-ListenerPid($port) {
    $c = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.OwningProcess } else { return $null }
}
function Stop-Tree($processId) {
    if ($processId) { cmd.exe /c "taskkill /T /F /PID $processId >nul 2>&1" }
}

# ---------------------------------------------------------------- prerequisites
Info 'Pruefe Voraussetzungen ...'

if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
    Fail 'Java wurde nicht gefunden. Bitte JDK 21 installieren und "java -version" pruefen.'
}
# java prints its version on stderr; with ErrorActionPreference=Stop that would count as an error
$javaVersion = (cmd.exe /c 'java -version 2>&1' | Select-Object -First 1)
if ($javaVersion -notmatch '"(2[1-9]|[3-9]\d)') { Fail "JDK 21 oder neuer erforderlich, gefunden: $javaVersion" }

if ($env:FLUTTER_BIN) { $env:Path = "$env:FLUTTER_BIN;$env:Path" }
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    $default = Join-Path $env:USERPROFILE 'tools\flutter\bin'
    if (Test-Path (Join-Path $default 'flutter.bat')) { $env:Path = "$default;$env:Path" }
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    Fail 'Flutter wurde nicht gefunden. Entweder in den PATH aufnehmen oder fuer diese Sitzung setzen: $env:FLUTTER_BIN = "<flutter-sdk>\bin"'
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    # Flutter needs git; add the usual Git for Windows locations for this session only
    foreach ($dir in 'C:\Program Files\Git\cmd', 'C:\Program Files\Git\bin', 'C:\Program Files\Git\mingw64\bin', 'C:\Program Files\Git\usr\bin') {
        if (Test-Path $dir) { $env:Path = "$env:Path;$dir" }
    }
}
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail 'git wurde nicht gefunden (Flutter benoetigt es). Bitte Git for Windows installieren.' }
Ok "  Java OK, Flutter OK ($((Get-Command flutter).Source)), git OK"

# ---------------------------------------------------------------- backend
$backendUrl = "http://localhost:$BackendPort/api/rooms"
$backendLog = Join-Path $stateDir 'backend.log'
$backendPidFile = Join-Path $stateDir 'backend.pid'
if (Test-Url $backendUrl -timeoutSec 10) {
    if (Test-Path $backendPidFile) {
        Ok "Backend laeuft bereits auf Port $BackendPort (von einem frueheren demo.ps1-Lauf gestartet) - wird wiederverwendet."
    } else {
        Ok "Backend laeuft bereits auf Port $BackendPort und antwortet - wird wiederverwendet (und von stop-demo.ps1 NICHT beendet)."
    }
} else {
    $owner = Get-ListenerPid $BackendPort
    if ($owner) {
        $name = (Get-Process -Id $owner -ErrorAction SilentlyContinue).ProcessName
        Fail "Port $BackendPort ist von einem anderen Programm belegt (PID $owner, $name), das nicht wie der Praxis-Monitor-Server antwortet. Beenden Sie es oder geben Sie Port $BackendPort frei (Beenden: Stop-Process -Id $owner)."
    }
    Info "Starte Backend (Profil dev, Port $BackendPort) ..."
    $cmd = "cd /d `"$root\backend`" && call .\mvnw.cmd -B -ntp spring-boot:run -Dspring-boot.run.profiles=dev > `"$backendLog`" 2>&1"
    if ($BackendPort -ne 8080) { $cmd = $cmd.Replace('-Dspring-boot.run.profiles=dev', "-Dspring-boot.run.profiles=dev -Dspring-boot.run.arguments=--server.port=$BackendPort") }
    $p = Start-Process -FilePath cmd.exe -ArgumentList '/c', $cmd -WindowStyle Hidden -PassThru
    Set-Content $backendPidFile $p.Id

    $deadline = (Get-Date).AddSeconds($BackendTimeoutSec)
    while (-not (Test-Url $backendUrl)) {
        if ($p.HasExited) {
            Fail "Backend wurde vorzeitig beendet. Letzte Log-Zeilen:`n$((Get-Content $backendLog -Tail 15 -ErrorAction SilentlyContinue) -join "`n")`nVollstaendiges Log: $backendLog"
        }
        if ((Get-Date) -gt $deadline) {
            Stop-Tree $p.Id
            Fail "Backend antwortete nicht innerhalb von $BackendTimeoutSec s. Log: $backendLog"
        }
        Start-Sleep -Seconds 2
    }
    Ok "Backend bereit: http://localhost:$BackendPort (Log: $backendLog)"
}

# ---------------------------------------------------------------- frontend
$webUrl = "http://localhost:$WebPort"
$flutterLog = Join-Path $stateDir 'flutter.log'
$flutterPidFile = Join-Path $stateDir 'flutter.pid'
if (Test-Url $webUrl -timeoutSec 15) {
    Ok "Flutter-Webanwendung laeuft bereits auf $webUrl - wird wiederverwendet."
} else {
    $owner = Get-ListenerPid $WebPort
    if ($owner) { Fail "Port $WebPort ist belegt (PID $owner) und antwortet nicht wie die Flutter-Webanwendung. Mit -WebPort <andere Nummer> einen freien Port waehlen oder das Programm beenden (Stop-Process -Id $owner)." }

    Info 'Starte Flutter-Webanwendung (Release-Build, Kompilieren dauert ca. 1 Minute) ...'
    $defines = ''
    if ($BackendPort -ne 8080) { $defines = "--dart-define=API_BASE_URL=http://localhost:$BackendPort --dart-define=WS_URL=ws://localhost:$BackendPort/ws" }
    $cmd = "cd /d `"$root\frontend`" && flutter --suppress-analytics pub get && flutter --suppress-analytics run --release -d web-server --web-hostname localhost --web-port $WebPort $defines > `"$flutterLog`" 2>&1"
    $f = Start-Process -FilePath cmd.exe -ArgumentList '/c', $cmd -WindowStyle Hidden -PassThru
    Set-Content $flutterPidFile $f.Id

    $deadline = (Get-Date).AddSeconds($FrontendTimeoutSec)
    while (-not ((Get-Content $flutterLog -ErrorAction SilentlyContinue) -match 'is being served at') -or -not (Test-Url $webUrl)) {
        if ($f.HasExited) {
            Fail "Flutter wurde vorzeitig beendet. Letzte Log-Zeilen:`n$((Get-Content $flutterLog -Tail 15 -ErrorAction SilentlyContinue) -join "`n")`nVollstaendiges Log: $flutterLog"
        }
        if ((Get-Date) -gt $deadline) {
            Stop-Tree $f.Id
            Fail "Flutter wurde nicht innerhalb von $FrontendTimeoutSec s bereit. Log: $flutterLog"
        }
        Start-Sleep -Seconds 3
    }
    Ok "Flutter bereit: $webUrl (Log: $flutterLog)"
}

# ---------------------------------------------------------------- browser
if (-not $NoBrowser) {
    Info 'Oeffne Browser ...'
    Start-Process $webUrl
}

Write-Host ''
Ok "Praxis Monitor laeuft:  $webUrl   (Backend: http://localhost:$BackendPort)"
Write-Host 'Sauber beenden:        .\scripts\stop-demo.ps1'
Write-Host "Logs:                  $stateDir"
