# ADR-005: Konfiguration, Profile, CORS

- Status: akzeptiert

## Entscheidung

- Nur `application.yml` (sicherer lokaler Standard) und `application-dev.yml` (nur mit explizitem Profil `dev`).
  Keine konkurrierende `application.yaml`.
- CORS (REST) und WebSocket-Handshake akzeptieren ausschließlich konfigurierte Origin-Muster
  (`praxis.cors.allowed-origin-patterns`, Standard: `http://localhost:*`, `http://127.0.0.1:*`). Kein `*`.
- Demo-Daten (`praxis.demo.seed-patients`) nur im Profil `dev`.
- Heartbeats (10 s) auf dem STOMP-Broker, damit Clients tote Verbindungen erkennen.

## Begründung / Test

Flutter-Web-Dev-Server verwendet zufällige lokale Ports, daher Muster statt fester Origin. Fremde Origins werden
abgelehnt (`PracticeRestIntegrationTest.corsAllowsLocalOriginAndRejectsForeignOrigin`,
`WebSocketIntegrationTest.foreignOriginIsRejectedAtHandshake`). Ein Produktivbetrieb bräuchte zusätzlich TLS und
Authentifizierung (nicht Teil dieser Demo).
