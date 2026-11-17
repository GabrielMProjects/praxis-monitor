# Demo-Anleitung (Windows, ca. 10 Minuten)

## Start mit einem Befehl

Voraussetzungen: JDK 21, Flutter-SDK, Git for Windows, ein Browser (siehe README). Flutter muss nicht im PATH stehen:
das Skript findet `$env:FLUTTER_BIN` bzw. `%USERPROFILE%\tools\flutter\bin`.

```powershell
cd <path-to>\praxis-monitor
.\scripts\demo.ps1
```

Das Skript (in ca. 1 Minute beim Kaltstart):
1. prüft Java 21, Flutter und Git und nennt fehlende Voraussetzungen im Klartext,
2. **erkennt ein bereits laufendes, gesundes Backend auf Port 8080 und verwendet es weiter** (es wird nie beendet, außer mit `-Backend`);
   ist der Port von einem anderen Programm belegt, gibt es eine Fehlermeldung mit PID und Hinweis, sonst startet es das Backend (Profil `dev`),
3. startet die Flutter-Web-App als Release-Build auf Port 5555 (erscheint im Browser nach wenigen Sekunden) und öffnet den Standardbrowser,
4. ist alles schon gestartet, werden beide Teile wiederverwendet (mehrfach aufrufbar).

Optionen: `-NoBrowser`, `-BackendPort 8081`, `-WebPort 5556`. Logs und PID-Dateien: `.demo\` (`backend.log`, `flutter.log`).

## Sauber beenden

```powershell
.\scripts\stop-demo.ps1            # beendet, was demo.ps1 gestartet hat (Flutter-Webserver, ggf. das von demo.ps1 gestartete Backend)
.\scripts\stop-demo.ps1 -Backend   # beendet zusätzlich ein Backend auf Port 8080, das demo.ps1 nicht gestartet hat
```

Ein vorher von Hand gestartetes Backend bleibt standardmäßig laufen. Die Prozessbäume werden mit `taskkill /T` beendet (kein verwaistes Java).

## Ablauf für den Interviewer (Live-Demo)

1. **Dashboard zeigen** – oben „Live verbunden“, links Warteschlange (Hoch → Mittel → Niedrig), rechts vier Räume.
   *Hinweis:* Farben sind nie das einzige Signal (Text + Icon), Disclaimer „technische Demonstration“ oben.
2. **Echtzeit** – in einem zweiten Fenster `Invoke-RestMethod -Method Post http://localhost:8080/api/patients -ContentType application/json -Body '{"name":"Live Test","urgency":"CRITICAL"}'`
   → der Patient erscheint ohne Reload auf Position 1 (WebSocket, Topic `/topic/queue`).
3. **Triage erklären** – „Demo-Patient hinzufügen“ mehrfach; Sortierung = Priorität, dann Ankunft (FIFO).
   Dropdown „Dringlichkeit ändern“: der Patient rückt vor, behält aber seinen Ankunftsrang (Sequenznummer bleibt).
4. **Zuweisung** – „Nächsten aufrufen“ (Raum) oder „Aufrufen“ (Patient → Dialog mit freien Räumen). Status `WAITING → IN_TREATMENT`.
5. **Raumzyklus** – „Behandlung abschließen“ → Raum **Reinigung** (nicht automatisch frei!) → „Reinigung beendet“ → Verfügbar.
6. **Fehlerbehandlung** – `curl -X POST http://localhost:8080/api/rooms/room-1/complete-treatment` auf freiem Raum → 409 mit Klartext.
7. **Reconnect** – Backend-Fenster schließen → Banner „Echtzeit-Verbindung getrennt“, Daten bleiben sichtbar; Backend neu starten
   (`cd backend; .\mvnw.cmd spring-boot:run "-Dspring-boot.run.profiles=dev"`) → automatisch wieder „Live verbunden“, Zustand per REST abgeglichen.
8. **Tastatur** – Tab durch die Oberfläche (sichtbarer Fokusring), Enter aktiviert; Pfeiltasten im Dropdown, Esc schließt den Dialog.
9. **Responsiv** – Browserfenster schmal ziehen (< 900 px): Tabs „Warteschlange / Räume“.

## Talking Points (Architektur)

- **Triage:** `PriorityQueue` + `HashMap`-Index + backendseitige Sequenznummer; `offer/poll` O(log n), Entfernen/Update O(n) – ehrlich benannt (ADR-001).
- **Schichten:** Domain ohne Spring; Services veröffentlichen Domain-Events; nur `WebSocketEventPublisher` kennt STOMP (ADR-002).
- **Konsistenz:** eine `PracticeLock`, Validierung vor dem ersten Schreibzugriff, `OCCUPIED ⇔ Patient gesetzt` (ADR-004).
- **Flutter:** feature-first, BLoC, Repository-Streams, **ein** WebSocket, REST-Resync nach jedem Reconnect (ADR-003).
- **Tests:** Backend 60, Flutter 70, Daten-Stack-E2E 7, Browser-E2E 15 (echte Oberfläche, Reconnect) – Details `docs/requirements-matrix.md`.
- **Grenzen offen ansprechen:** In-Memory, keine Auth, keine klinische Aussagekraft.

## Automatisierte Prüfung (optional, unabhängig von Port 8080)

```powershell
cd backend;  .\mvnw.cmd clean test
cd ..\frontend; flutter analyze; flutter test
cd ..; .\scripts\e2e.ps1            # Datenstack gegen echtes Backend (Port 18080)
.\scripts\e2e-browser.ps1           # echte Flutter-Oberfläche in headless Chrome (Port 18082/18083)
```
