# Reproducible end-to-end test: real Spring Boot jar + real Flutter data stack (HTTP + STOMP WebSocket),
# including backend kill/restart (reconnect). Does not touch port 8080 (default test port 18080).
# Usage:  .\scripts\e2e.ps1 [-Port 18080]     Requires JDK 21 and Flutter on PATH (or $env:FLUTTER_BIN).
param([int]$Port = 18080)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ($env:FLUTTER_BIN) { $env:Path = "$env:FLUTTER_BIN;$env:Path" }

Push-Location "$root\backend"
.\mvnw.cmd -B -ntp -q -DskipTests package
if ($LASTEXITCODE -ne 0) { throw 'backend build failed' }
$jar = (Get-ChildItem target -Filter 'praxismonitor-*.jar' | Where-Object { $_.Name -notmatch 'original' } | Select-Object -First 1).FullName
Pop-Location

$env:E2E_BACKEND_JAR = $jar
$env:E2E_PORT = "$Port"
Push-Location "$root\frontend"
flutter pub get | Out-Null
flutter test e2e/praxis_e2e_test.dart --timeout 5m
$code = $LASTEXITCODE
Pop-Location
exit $code
