# Captures the README screenshots (docs\screenshots\*.png) from the real app with synthetic data.
# Uses its own backend (port 18082) and web server (18083); does not touch the demo on 8080/5555.
# Requires JDK 21, Flutter, Node >= 22, Chrome.
param([int]$ApiPort = 18082, [int]$WebPort = 18083)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ($env:FLUTTER_BIN) { $env:Path = "$env:FLUTTER_BIN;$env:Path" }

Push-Location "$root\backend"
.\mvnw.cmd -B -ntp -q -DskipTests package
if ($LASTEXITCODE -ne 0) { throw 'backend build failed' }
$jar = (Get-ChildItem target -Filter 'praxismonitor-*.jar' | Where-Object { $_.Name -notmatch 'original' } | Select-Object -First 1).FullName
Pop-Location

Push-Location "$root\frontend"
flutter pub get | Out-Null
flutter build web --release --output build/web_screens "--dart-define=API_BASE_URL=http://localhost:$ApiPort" "--dart-define=WS_URL=ws://localhost:$ApiPort/ws"
if ($LASTEXITCODE -ne 0) { throw 'flutter build web failed' }
Pop-Location

$env:E2E_BACKEND_JAR = $jar
$env:E2E_WEB_DIR = (Resolve-Path "$root\frontend\build\web_screens").Path
$env:SHOT_API_PORT = "$ApiPort"
$env:SHOT_WEB_PORT = "$WebPort"
$env:SHOT_OUT = "$root\docs\screenshots"
node "$root\scripts\capture-screenshots.mjs"
exit $LASTEXITCODE
