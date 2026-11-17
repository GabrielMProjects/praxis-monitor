#!/usr/bin/env bash
# End-to-end tests for Linux/macOS/CI (the Windows equivalents are scripts/e2e.ps1 and scripts/e2e-browser.ps1).
#   1. data-stack E2E: real Spring Boot jar + real Flutter repositories/BLoCs over HTTP and STOMP WebSocket (incl. reconnect)
#   2. browser E2E: real Flutter web UI in headless Chrome (DevTools Protocol, no extra installs) (incl. reconnect)
# Requires: JDK 21, Flutter, Node >= 22, Chrome/Chromium (CHROME_BIN, default: google-chrome). Never uses port 8080.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Git Bash on Windows: hand native-style paths to java/node (no-op on Linux/macOS)
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
api_port="${E2E_API_PORT:-18080}"
browser_api_port="${E2E_BROWSER_API_PORT:-18082}"

echo "== build backend jar"
(cd "$root/backend" && chmod +x mvnw && ./mvnw -B -ntp -q -DskipTests package)
jar="$(native "$(ls "$root"/backend/target/praxismonitor-*.jar | grep -v original | head -n 1)")"

cd "$root/frontend"
flutter pub get

echo "== data-stack E2E (port $api_port)"
E2E_BACKEND_JAR="$jar" E2E_PORT="$api_port" flutter test e2e/praxis_e2e_test.dart --timeout 5m

echo "== build web bundle for browser E2E"
flutter build web --release --output build/web_e2e \
  --dart-define="API_BASE_URL=http://localhost:${browser_api_port}" \
  --dart-define="WS_URL=ws://localhost:${browser_api_port}/ws"

echo "== browser E2E (backend port $browser_api_port)"
E2E_BACKEND_JAR="$jar" E2E_WEB_DIR="$(native "$PWD/build/web_e2e")" E2E_PORT="$browser_api_port" node e2e_browser/browser_e2e.mjs
