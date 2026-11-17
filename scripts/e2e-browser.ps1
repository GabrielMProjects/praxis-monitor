# Browser end-to-end test: real Flutter web UI in headless Chrome (DevTools Protocol, no extra installs)
# against a real Spring Boot jar on its own port (default 18082; never touches 8080).
# Usage: .\scripts\e2e-browser.ps1      Requires JDK 21, Flutter (PATH or $env:FLUTTER_BIN), Chrome, Node 22+.
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
# separate output dir so the normal `flutter build web` output is untouched
flutter build web --output build/web_e2e "--dart-define=API_BASE_URL=http://localhost:$ApiPort" "--dart-define=WS_URL=ws://localhost:$ApiPort/ws"
if ($LASTEXITCODE -ne 0) { throw 'flutter build web failed' }
$env:E2E_BACKEND_JAR = $jar
$env:E2E_WEB_DIR = (Resolve-Path 'build\web_e2e').Path
$env:E2E_PORT = "$ApiPort"
$env:E2E_WEB_PORT = "$WebPort"
node e2e_browser/browser_e2e.mjs
$code = $LASTEXITCODE
Pop-Location
exit $code
