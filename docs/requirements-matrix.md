# Anforderung → Datei / Test → Status

Stand: 2026-11-17 (Veröffentlichungs-Vorbereitung), Windows 10, JDK Temurin 21.0.13, Flutter 3.50.0 (Dart 3.14.0), Chrome 148, Node 24.

Status ausschließlich: **implementiert und getestet** (✔) · **implementiert, nicht getestet** (◐) · **teilweise umgesetzt** (◔) · **fehlend** (✘).

## Tatsächlich ausgeführte Tests (Abschlusslauf)

| Kommando | Ergebnis |
|---|---|
| `backend\mvnw.cmd clean test` | **BUILD SUCCESS – 60 Tests, 0 Fehler** (Triage 18, PatientService 12, RoomService 12, REST-Integration 12, WebSocket-Integration 3, GlobalExceptionHandler 2, ContextLoads 1); `mvnw clean verify` ebenfalls erfolgreich |
| `flutter analyze` | **No issues found** |
| `flutter test` | **70 Tests, alle bestanden** (inkl. 3 Architekturtests) |
| `scripts\e2e.ps1` (echtes Jar auf Port 18080 + echter Flutter-Datenstack, inkl. Backend-Kill/Reconnect) | **7/7 bestanden** |
| `scripts\e2e-browser.ps1` (echte Flutter-**Oberfläche** in headless Chrome per DevTools-Protokoll, echtes Jar auf Port 18082) | **15/15 Schritte bestanden** |
| `flutter run -d chrome --web-port 5556` gegen Backend auf **8080** (Standard-URLs, kein `--dart-define`) | startet (Debug-Service verbunden). Der Ablauf wurde über denselben Dev-Server im Browser-Panel bedient: Live-POST per REST erscheint sofort, „Nächsten aufrufen“ ruft den kritischen Patienten, „Behandlung abschließen“ → Reinigung, „Reinigung beendet“ → Verfügbar |
| Docker | nicht Teil des Veröffentlichungsumfangs (siehe Zeile 50) |
| `flutter run -d windows` | **nicht getestet** (VS-C++-Workload fehlt; optional) |

Der Browser-E2E nutzt ausschließlich vorhandene Werkzeuge (Node 24 mit globalem WebSocket/fetch, installiertes Chrome, Jar, `flutter build web`);
nichts wurde zusätzlich installiert. Er bedient die UI über den Accessibility-Baum von Flutter (Labels) und ist damit zugleich ein Zugänglichkeitstest.

### Schritte des Browser-E2E (`frontend/e2e_browser/browser_e2e.mjs`)
1 Laden, WebSocket verbunden, Leerzustand, Überschriften · 2 „Demo-Patient hinzufügen“ ×3 (Maus), Queue sortiert · 3 Live-Update einer per REST angelegten Aufnahme ·
4 Dringlichkeit per Dropdown ändern, Ankunftsrang bleibt (FIFO) · 5 Dialog öffnen, **Esc schließt**, Raum wählen · 6 „Nächsten aufrufen“ · 7 Abschluss → **Reinigung** → „Reinigung beendet“ →
8 Raumänderung via REST live im UI · 9 **nur Tastatur**: Tab erreicht den Button, Enter aktiviert · 9b **logische Fokusreihenfolge** (Queue-Controls vor Raum-Controls) · 10 Entfernen über beschrifteten Papierkorb ·
11 schmales Fenster (375 px): Tabs, Räume erreichbar · 12 **Backend beenden → Banner „getrennt“, Daten bleiben → Neustart → Auto-Reconnect + REST-Resync** · 13 Ereignis nach Reconnect genau einmal · 14 keine JS-Ausnahmen.

### Bei der Abschlussprüfung gefundene und behobene Mängel
- **Zugänglichkeit:** Das Kachel-Gruppenlabel verschmolz die ganze Kachel zu einem unbeschrifteten „Button“; das Dringlichkeits-Dropdown fehlte im Accessibility-Baum; Entfernen-Buttons ohne Patientenname; Überschriften und Live-Regionen fehlten.
  → Kachel mit einer Zusammenfassung („Position 1: Name, Dringlichkeit …, Ankunft …, Status …“), beschriftetes Dropdown, Name im Entfernen-Button, `header`/`liveRegion`-Semantik (Queue- und Raumzähler, Verbindungsstatus, Lade-/Fehleransicht).
- **Fokus:** Material-Fokus war kaum sichtbar → 3-px-Fokusring für Filled/Outlined/Icon-Buttons, kräftigerer Dropdown-Fokus.
- **Tab-Reihenfolge:** Die Tastaturreihenfolge sprang zeilenweise zwischen Queue und Räumen (Lesereihenfolge-Policy bei zwei Spalten). → `FocusTraversalGroup` je Spalte; vom Browser-Test (9b) belegt (der Test schlug vor dem Fix fehl).
- **Deaktiviertes „Aufrufen“** erklärte den Grund nur per Tooltip → sichtbarer Text „Aufrufen (kein Raum frei)“.
- Zuvor: `StompRealtimeClient._onConnect` nach `dispose()` (Null-Check-Fehler), durch Unit-Test entdeckt und behoben.

### Layout-Prüfung (echtes Chrome-Fenster, Breiten 320, 360, 375, 640, 899, 900, 1024, 1280, 1440)
Kein Layout-Überlauf, keine Konsolenfehler außer dem Dev-Tooling-Hinweis des Flutter-Dev-Servers. < 900 px: Tabs „Warteschlange/Räume“; ≥ 900 px: zwei Spalten.
Dialog bei 360 px, Dropdown-Menü, Raumkarten und Snackbar visuell geprüft. Der frühere Überlauf im Dringlichkeits-Dropdown (Testfont) wurde schon im ersten Durchlauf behoben.
Grenze: Größere System-Schriftgrade/Browser-Zoom 200 % wurden nicht systematisch geprüft.

## Matrix

Backend-Tests: `B:` = `backend\src\test\java\com\praxismonitor\…`, Frontend-Tests: `F:` = `frontend\test\…`.

| # | Anforderung | Datei(en) | Beleg | Status |
|---|---|---|---|---|
| 1 | Java 21, Spring Boot 4.1.2, Maven, Web MVC, WebSocket, Validation, JUnit 5 | `backend/pom.xml` | `mvnw clean test` grün (60) | ✔ |
| 2 | Flutter, feature-first, BLoC, REST initial, WebSocket live | `frontend/lib/**` | `flutter test` (70), E2E (7 + 15) | ✔ |
| 3 | Clean Code/SOLID/DI/Testbarkeit | siehe `docs/architecture.md`, Code-Review unten | qualitatives Review, kein Messwert | ◔ (qualitativ) |
| 4 | Bestehendes Projekt analysiert, Duplikat `backend/praxismonitor/` bereinigt | lokales Backup außerhalb des Repositorys | Dateien byte-identisch verglichen, gesichert, entfernt | ✔ |
| 5 | Hauptklasse `PraxismonitorApplication` erhalten | `backend/.../PraxismonitorApplication.java` | `PraxismonitorApplicationTests` | ✔ |
| 6 | Backend-Paketstruktur wie gefordert | `backend/src/main/java/com/praxismonitor/**` | Kompilierung + Tests | ✔ (zusätzlich `common/concurrent`) |
| 7 | Domain ohne Spring/REST/WebSocket | `*/domain` | Imports geprüft | ✔ |
| 8 | Patientenmodell | `patient/domain/Patient.java` | `PatientServiceTest` | ✔ |
| 9 | Dringlichkeit exakt `CRITICAL(1) HIGH(2) MEDIUM(3) LOW(4)`; `NORMAL` verworfen | `Urgency.java` | `TriageQueueTest.urgencyPrioritiesAreExactlyOneToFour`, REST-400 bei `NORMAL` | ✔ |
| 10 | REST: anlegen, abrufen, ändern, entfernen | `PatientController` | `PracticeRestIntegrationTest` | ✔ |
| 11 | In-Memory-Repository, DTO-Validierung | `patient/infrastructure`, `PatientRequest` | `invalidInputGives400WithDetails` | ✔ |
| 12 | Triage mit `PriorityQueue`, expliziter Comparator | `QueueEntry`, `TriageQueue` | `TriageQueueTest` (18) | ✔ |
| 13 | Höhere Dringlichkeit zuerst; FIFO bei Gleichstand | – | `servesAllFour…`, `isFifoWithinSameUrgency`, `mixedUrgencies…` (200 zufällig); Browser-E2E 2 + 4 | ✔ |
| 14 | Backend-Sequenznummer, Clientzeit ohne Einfluss | `TriageQueue.nextSequence` | `PatientServiceTest`; DTO enthält keine Zeit | ✔ |
| 15 | Keine inkonsistenten Einträge, leere Queue, ungültige Zustände | `TriageQueue` | `removalLeavesNoStaleEntries`, `emptyQueueBehavesSafely`, `heapAndIndexStayConsistentUnderRandomOperations` | ✔ |
| 16 | Sequenz bleibt bei Änderung; neue Aufnahme = neue Sequenz | – | `urgencyChangeReordersButKeepsOriginalSequence`, `readmissionGetsNewSequence`; Browser-E2E 4 | ✔ |
| 17 | Sortierter Snapshot statt `iterator()` | `TriageQueue.snapshot()` | `snapshotIsSortedAndDetached` | ✔ |
| 18 | Ehrliche Laufzeit-/Speicherdokumentation | Javadoc, `docs/adr/001`, `architecture.md` | Doku | ✔ (Doku) |
| 19 | Triage unabhängig von Spring | `triage/domain` | `TriageQueueTest` ohne Spring | ✔ |
| 20 | „Nur technische Demo“-Hinweis | README, Dashboard-Banner | `dashboard_page_test`, Browser-E2E 1 | ✔ |
| 21 | Räume: anzeigen, Status, zuweisen, freigeben, Konsistenz | `room/**` | `RoomServiceTest` (12), REST-Flow | ✔ |
| 22 | Zustandsfolgen (Raum nie automatisch `AVAILABLE`) | `Patient`, `Room`, `RoomService` | `fullLifecycle…`, `fullDemoFlowOverRest`, Browser-E2E 7 | ✔ |
| 23 | Unzulässige Übergänge → dokumentierte 4xx | `GlobalExceptionHandler` | `roomCannotHoldTwoPatients`, `invalidManualTransitionsAreRejected`, REST-409-Fälle | ✔ |
| 24 | Raum nie mit 2 Patienten, Patient nie in 2 Räumen, kein halber Zustand | `Room`-Invariante, `RoomService.assign` | `roomCannotHoldTwoPatients`, `patientCannotBeInTwoRooms` | ✔ |
| 25 | Gleichzeitige Anfragen | `PracticeLock` | `concurrentAdmissionsKeepQueueConsistent`, `concurrentAssignmentsToOneRoomLetExactlyOnePatientWin` | ✔ |
| 26 | STOMP-Vertrag dokumentiert | `WebSocketConfig`, `realtime/**` | `WebSocketIntegrationTest` | ✔ |
| 27 | Alle Events (hinzugefügt/entfernt, Dringlichkeit, Queue, Raumstatus, Zuweisung) | `realtime/event/*` | WS-Tests über echte STOMP-Verbindung: ADDED, QUEUE_CHANGED, ASSIGNED, ROOM_STATUS_CHANGED, URGENCY_CHANGED, REMOVED | ✔ |
| 28 | Domain-Events + separater Publisher, Services ohne WebSocket | `PracticeFixture` | Service-Tests ohne Spring | ✔ |
| 29 | Zentrale Fehlerbehandlung inkl. **500-Pfad** | `common/exception` | `GlobalExceptionHandlerTest` (500 mit generischer Meldung ohne Leck; 405/404/415 bleiben erhalten), REST-Tests 400/404/409 | ✔ |
| 30 | Testbare Zeitabstraktion | `ClockConfig` | `PracticeFixture` mit `Clock.fixed` | ✔ |
| 31 | Nur `application.yml` + `application-dev.yml`, Profil nur explizit | `src/main/resources` | Dateien geprüft; `dev` explizit aktiviert (Demo-Patienten sichtbar) | ✔ |
| 32 | CORS/WebSocket-Origins nur lokal | `CorsConfig`, `WebSocketConfig` | `corsAllows…`, `foreignOriginIsRejectedAtHandshake` | ✔ |
| 33 | Port 8080 dokumentiert/Konflikt behandelt | README, `scripts/demo.ps1` | Backend läuft auf 8080, Flutter (`flutter run -d chrome`) verbunden und bedient | ✔ |
| 34 | `backend\mvnw.cmd` unter Windows | – | verwendet | ✔ |
| 35 | Flutter-Toolchain geprüft; Projekt `praxis_monitor`, Org `com.praxismonitor` | `frontend/pubspec.yaml` | `flutter doctor -v`, `flutter create …` | ✔ (SDK lokal geklont, PATH nicht verändert; nur Plattform `web`) |
| 36 | Flutter-Dateien/Ordner exakt | `frontend/lib/**` | `flutter analyze` | ✔ |
| 37 | `analysis_options.yaml`, schlanke `main.dart` | – | `flutter analyze` | ✔ |
| 38 | BLoC über Repository-Abstraktionen/Streams, keine HTTP/WS in Widgets | `domain/repositories`, `presentation/bloc` | Bloc-Tests | ✔ |
| 39 | Dashboard-Inhalte, Echtzeit ohne Reload | `features/**/presentation` | Widget-Tests, Browser-E2E 1–8 | ✔ |
| 40 | Benutzeraktionen (Demo-Patient, Dringlichkeit, aufrufen, zuweisen, abschließen, Raumstatus) | dito | Browser-E2E 2, 4, 5, 6, 7 | ✔ |
| 41 | Eine zentrale WebSocket-Verbindung, Aufbau, Auto-Reconnect, Dispose | `stomp_realtime_client.dart`, `app_dependencies.dart` | `F:core/stomp_realtime_client_test.dart` (8), `app_test`, Daten-E2E 6–7, Browser-E2E 12–13 (echter Reconnect) | ✔ |
| 42 | Loading-/Fehler-/Leerzustände; Reconnect-Resync | `state_views.dart`, Repositories | `dashboard_page_test`, Repository-Tests, Browser-E2E 1, 12 | ✔ |
| 43 | Responsiv, Statuslabels zusätzlich zu Farbe, **Tastaturbedienbarkeit, Fokus, Semantik** | `StatusChip`, `PatientTile`, `AppTheme`, `DashboardPage` | Browser-E2E 9 (Tab+Enter), 9b (Fokusreihenfolge), 5 (Esc), 11 (schmal); Accessibility-Baum geprüft; Layouts 320–1440 px | ✔ (mit Einschränkung: kein echter Screenreader, kein 200-%-Zoom getestet) |
| 44 | Flutter Web (`flutter run -d chrome`) als primäres Ziel | – | siehe Tabelle oben | ✔ |
| 45 | Windows-Desktop (optional) | – | VS-C++-Workload fehlt | ✘ nicht getestet (optional) |
| 46 | Java-Tests vollständig | siehe oben | `mvnw clean test` (60) | ✔ |
| 47 | Flutter-Tests: BLoCs, Repositories, Widgets, Fehler/Reconnect | `frontend/test/**` | `flutter test` (70) | ✔ |
| 48 | README mit vollständigem Start; Ein-Befehl-Start | `README.md`, `docs/demo-guide.md`, `scripts/demo.ps1`, `scripts/stop-demo.ps1` | `demo.ps1` real getestet: Kaltstart (~60 s, startet Backend + Flutter), Wiederverwendung eines laufenden Backends, zweiter Aufruf, Browser öffnet, Seite lädt; Fehlerfälle (fremdes Programm auf dem Port, Flutter fehlt); `stop-demo.ps1` beendet alles ohne verwaiste Prozesse | ✔ |
| 49 | `docs/architecture.md`, `docs/adr/` | `docs/` | – | ✔ (Doku) |
| 50 | Docker/Compose (optional) | – | **Aus dem Veröffentlichungsumfang entfernt** (nie getestet, vom Auftraggeber ausgeschlossen); Dateien liegen als Sicherung außerhalb des Repositorys | ✘ bewusst nicht enthalten |
| 51 | Nur synthetische Daten, keine externen Dienste | `DemoDataSeeder`, `DemoPatientGenerator` | Code-Durchsicht | ✔ |
| 52 | Keine Auth/DB/Cloud/DSGVO (bewusst) | README „Bekannte Grenzen“ | – | ✔ (dokumentiert) |
| 53 | Gesamtablauf mit realem Flutter-Client + Spring-Backend, automatisiert | `frontend/e2e/`, `frontend/e2e_browser/`, `scripts/e2e*.ps1` | 7/7 + 15/15 | ✔ |
| 54 | Spring Boot startet erfolgreich | – | `spring-boot:run` (dev) auf 8080, `contextLoads` | ✔ |

## Kurzes Code-Review (Clean Code, SOLID, Wartbarkeit)

**Stärken**
- **SRP/DIP:** Domain ohne Framework (`Patient`, `Room`, `TriageQueue`), Services hinter Repository-Interfaces, `RealtimeClient`/`PatientRepository`/`RoomRepository` als Abstraktionen im Frontend → alles mit Fakes testbar.
- **OCP:** `DomainEvent` ist `sealed`; der Publisher-`switch` ist exhaustiv, ein neues Event erzwingt Compilerfehler statt stillem Verlust.
- **Konsistenz:** immutable Records, Invarianten im Konstruktor (`OCCUPIED ⇔ Patient`), Validierung vor dem ersten Schreibzugriff, eine Sperre für Mehrstruktur-Operationen (ADR-004).
- **Nachvollziehbarkeit:** fünf ADRs, ehrliche Laufzeitangaben, Tests benennen das Verhalten.

**Schwächen / bewusste Kompromisse (nicht geändert, um die funktionierende Architektur nicht unnötig anzutasten)**
1. ~~Kopplung `TriageQueuePage` ↔ `RoomsBloc`~~ **behoben**: Die Features importieren sich nicht mehr; das Dashboard reicht zuweisbare Räume bzw. "Queue nicht leer" durch (`RoomOption`, `hasWaitingPatients`). Durchgesetzt durch `frontend/test/architecture_test.dart`.
2. `TriageQueueBloc` und `RoomsBloc` duplizieren das `_action`/Fehler-Muster (kleine Basisklasse wäre möglich).
3. `PatientController` berechnet Queue-Positionen pro Anfrage neu (O(n), bei Praxisgröße irrelevant).
4. `Room.patientName` ist ein denormalisierter Snapshot; umbenannte Patienten (nur `WAITING` änderbar) können dadurch nie abweichen, ein späteres Umbenennen im Raum würde es.
5. ~~Unbegrenztes Wachstum abgeschlossener Patienten~~ **behoben**: höchstens `praxis.history.max-completed-patients` (Standard 100) `COMPLETED`-Patienten, älteste zuerst entfernt (`PatientServiceTest.completedHistoryIsBoundedAndEvictsOldestFirst`, `historyLimitNeverTouchesWaitingOrInTreatmentPatients`).
6. Events werden innerhalb der Sperre veröffentlicht (einfach und geordnet, aber ein langsamer Broker würde Anfragen verlangsamen).
7. Manuelles DI statt Service-Locator – bei dieser Größe gewollt.
8. `flutter format`-Lauf hat mehrere Dateien umformatiert (reine Formatänderung).

## Veröffentlichungs-Vorbereitung (Stand der lokalen Prüfung)

| Punkt | Status |
|---|---|
| Lokales Git-Repository | neu initialisiert (`main`); es gab kein vorheriges Repository, daher keine Historie zu erhalten |
| `.gitignore` / `.gitattributes` | Build-Ausgaben, Caches, Logs, PID-Dateien, `.demo/`, IDE-Dateien, Secrets-Muster ausgeschlossen; Wrapper, Lockfiles, Konfiguration enthalten; `mvnw`/Shell-Skripte mit LF |
| Secret-/PII-Prüfung der getrackten Dateien | Muster für Token, Schlüssel, Passwörter, E-Mail-Adressen, Benutzernamen und lokale Pfade: **keine Treffer** (git grep); nur synthetische Patientendaten |
| Benutzerspezifische Pfade | aus README/Docs/Skripten entfernt (Platzhalter `<flutter-sdk>`, `<path-to>`) |
| Docker | Dateien aus dem Veröffentlichungsumfang entfernt (Sicherung außerhalb des Repositorys) |
| CI-Workflows (`.github/workflows/ci.yml`, `security.yml`, `dependabot.yml`) | offline validiert (`scripts/validate-workflows.dart`) **und auf GitHub gelaufen**: CI (Backend, Frontend, E2E) und Security (CodeQL Java/JS, gitleaks) erfolgreich auf `main` (Initial-Commit); Dependency Review nur für PRs und benötigt aktivierte Dependabot-Alerts/Dependency Graph |
| `scripts/e2e.sh` (Linux/CI-Variante) | lokal über Git Bash gegen Windows-Chrome erfolgreich (7/7 + 15/15); echter Linux-Lauf: **auf GitHub erfolgreich** (Ubuntu-Runner, headless Chrome mit `--no-sandbox`) |
| Screenshots | 7 Bilder aus der laufenden App (`scripts/capture-screenshots.ps1`) |
| Demo-Video | Platzhalter in README, Ablaufplan `docs/recording-plan.md`; Aufnahme durch den Auftraggeber |
| Lizenz | **Proprietär / All Rights Reserved** (`LICENSE`, Copyright 2026; Repository öffentlich einsehbar, aber nicht Open Source; GitHub-Ansehen/Forken gemäß GitHub-Nutzungsbedingungen zulässig; keine kommerzielle Nutzung; früher wirksam eingeräumte Lizenzrechte bleiben unberührt; Lizenzhinweise fremder Komponenten bleiben bei diesen) |

### GitHub-Stand (2026-11-17, nach Neuanlage des Repositorys mit neuem Initial-Commit; Historie vor diesem Zeitpunkt nur in privaten Sicherungen)
- **Workflows:** CI (Backend, Frontend inkl. Web-Release-Build, E2E) und Security (CodeQL Java/JS, gitleaks über die gesamte Historie) erfolgreich; Status-Badges zeigen "passing".
- **Code Scanning:** 0 offene Hinweise (die früheren `js/bad-code-sanitization`-Funde waren vor der Neuanlage behoben); 0 Dependabot- und 0 Secret-Scanning-Alerts.
- **Einstellungen:** Dependabot-Alerts, Dependabot-Security-Updates, Dependency Graph (SBOM abrufbar), Secret-Scanning und Push-Protection aktiv; zusammengeführte PR-Branches werden automatisch gelöscht.
- **Dependabot-PRs:** Die früheren Updates (dependency-review-action 5.0.0, Maven-Wrapper 3.10.1) sind im Initial-Commit enthalten; es gibt keine offenen PRs. Der erste Dependabot-pub-Lauf scheiterte, weil das Repository dabei noch privat war; Dependabot läuft wöchentlich neu.
- **Branch Protection `main`:** Pull Request erforderlich (0 Pflicht-Reviews), Pflicht-Checks: Backend, Frontend, E2E, CodeQL (java-kotlin, javascript-typescript), Secret scan; Konversationen müssen aufgelöst sein; kein Force-Push, kein Löschen; Administratoren dürfen umgehen (Einzelentwickler). *Dependency review* ist bewusst kein Pflicht-Check (läuft nur in PRs).

## Verbleibende Lücken (ausdrücklich)

1. **Docker** ist nicht Teil des veröffentlichten Projekts (bewusst ausgeschlossen).
2. **Windows-Desktop** nicht getestet (VS-C++-Workload fehlt); optional.
3. **Echter Screenreader** (NVDA/Narrator), **Browser-Zoom 200 %** und andere Browser als Chromium wurden nicht getestet; Accessibility wurde über den Semantik-Baum, Tastatur-E2E und Sichtprüfung belegt.
4. **`scripts\demo.ps1`** ist inzwischen real getestet (siehe Zeile 48); nicht getestet: Start auf einem anderen Rechner/ohne Git im PATH-Fallback-Pfad `C:\Program Files\Git`.
5. `flutter run -d chrome` startet ein externes Chrome-Fenster, das ich nicht fernsteuern kann; die Bedienung lief über denselben Dev-Server im Browser-Panel.
6. Unter Windows-PowerShell 5.1 zeigt die Konsole Umlaute der Test-Ausgabe verfälscht an (nur Anzeige, Dateien sind UTF-8).
7. Bewusst nicht im Umfang: Authentifizierung, Datenbank, Cloud, DSGVO-Freigabe; Daten nur im Speicher, eine Instanz.
