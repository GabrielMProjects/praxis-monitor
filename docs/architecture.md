# Architektur

> Technische Demonstration mit synthetischen Daten – kein medizinisches Entscheidungssystem.

## Überblick

```
Flutter (Web)                              Spring Boot 4.1.2 / Java 21
┌───────────────────────────┐   REST       ┌───────────────────────────────────────┐
│ UI (Pages/Widgets)        │ ───────────► │ api (Controller, DTOs, Validierung)   │
│   │ Events/States         │              │   │                                   │
│ BLoC / Cubit              │ ◄─────────── │ application (Services, PracticeLock)  │
│   │ Streams               │   JSON       │   │               │ Domain-Events     │
│ Repository (Interface)    │              │ domain (Patient, Room, TriageQueue)   │
│   │                       │   STOMP      │   │               ▼                   │
│ Repository-Impl           │ ◄═══════════ │ infrastructure   realtime/publisher   │
│  ├ ApiClient (HTTP)       │  /topic/...  │ (In-Memory)      (SimpMessaging)      │
│  └ RealtimeClient (1x)    │              └───────────────────────────────────────┘
└───────────────────────────┘
```

### Backend-Pakete (`com.praxismonitor`)

| Paket | Inhalt | Abhängigkeiten |
|---|---|---|
| `patient.domain` | `Patient` (immutable record), `Urgency`, `PatientStatus`, `PatientRepository` | nur Java |
| `triage.domain` | `TriageQueue`, `QueueEntry` (+ Comparator) | nur Java (+ `Urgency`) |
| `room.domain` | `Room`, `RoomStatus`, `RoomRepository` | nur Java |
| `*.application` | `PatientService`, `RoomService`, `TriageService` | Domain, Spring Stereotype, Events |
| `*.api`, `*.api.dto` | REST-Controller, Request/Response-Records | Spring MVC, Validation |
| `*.infrastructure` | In-Memory-Repositories | Domain |
| `realtime.event` | `DomainEvent` (sealed) + Events | nur Java |
| `realtime.publisher` / `realtime.dto` | `WebSocketEventPublisher`, Nachrichtenhülle/Payloads | Spring Messaging |
| `common.exception` / `common.time` / `common.concurrent` | `GlobalExceptionHandler`, `Clock`-Bean, `PracticeLock` | – |
| `config` | `WebSocketConfig`, `CorsConfig`, `DemoDataSeeder` | Spring |

Regeln: Domain-Klassen kennen weder Spring noch REST noch WebSocket. Services veröffentlichen nur
`DomainEvent`s über `ApplicationEventPublisher`; ausschließlich `WebSocketEventPublisher` kennt STOMP.

## Fachliche Zustände

```
Patient:  WAITING ──assign/call-next──► IN_TREATMENT ──complete-treatment──► COMPLETED
Raum:     AVAILABLE ──assign/call-next──► OCCUPIED ──complete-treatment──► CLEANING ──PUT status AVAILABLE──► AVAILABLE
          AVAILABLE ──PUT status CLEANING──► CLEANING            (manuelle Reinigung)
```

Der Raum kehrt **nie automatisch** nach `AVAILABLE` zurück; Reinigungsende ist eine explizite Aktion.

| Aktion | Bedingung | sonst |
|---|---|---|
| assign / call-next | Raum `AVAILABLE`, Patient `WAITING` (call-next: Queue nicht leer) | 409 |
| complete-treatment | Raum `OCCUPIED` | 409 |
| `PUT status=CLEANING` | Raum `AVAILABLE` | 409 (bei `OCCUPIED`: „complete the treatment first“) |
| `PUT status=AVAILABLE` | Raum `CLEANING` | 409 |
| `PUT status=OCCUPIED` | nie manuell | 409 |
| `PUT /patients/{id}` | Patient `WAITING` | 409 |
| `DELETE /patients/{id}` | Patient nicht `IN_TREATMENT` | 409 |

Alle Validierungen laufen **vor** dem ersten Schreibzugriff (`RoomService.assign`): ein abgelehnter Request
hinterlässt keinen halben Zustand (getestet in `RoomServiceTest`). Ein Raum hält höchstens einen Patienten
(Invariante im `Room`-Konstruktor: `OCCUPIED ⇔ patientId != null`), ein Patient ist durch den Statuswechsel
`WAITING → IN_TREATMENT` höchstens einem Raum zugeordnet.

## Triage-Algorithmus

`TriageQueue` (reines Java, nicht thread-safe; Synchronisation außen):

- `PriorityQueue<QueueEntry>` mit explizitem Comparator `QueueEntry.ORDER`:
  `comparingInt(urgency.priority()).thenComparingLong(sequence)`.
- `HashMap<String, QueueEntry>` als Index (Mitgliedschaft in O(1), verhindert Duplikate und veraltete Einträge).
- `long nextSequence`: monoton, vom **Backend** bei der Aufnahme vergeben. Clientzeiten beeinflussen die Reihenfolge nie.
  `Instant arrivedAt` (UTC) ist nur die sichtbare Aufnahmezeit.
- Java-`PriorityQueue` ist nicht stabil → ohne die eindeutige Sequenz wäre FIFO bei gleicher Priorität nicht garantiert.
- Einträge sind immutable; Änderung = neuer Eintrag mit **gleicher Sequenz** (Dringlichkeitsänderung behält die Ankunftsreihenfolge).
  Erneute Anmeldung nach Abschluss = neue Aufnahme = neue Sequenz.
- Anzeige: `snapshot()` kopiert und sortiert (`PriorityQueue.iterator()` ist **nicht** sortiert und wird nie verwendet).

| Operation | Laufzeit | Anmerkung |
|---|---|---|
| `enqueue` | O(log n) | `offer` + `put` |
| `peek` | O(1) | |
| `poll` | O(log n) | |
| `contains` | O(1) | Index |
| `remove(id)` | **O(n)** | `PriorityQueue.remove(Object)` sucht linear |
| `changeUrgency` | **O(n)** | remove + offer |
| `snapshot` | O(n log n) | Kopie + Sortierung |
| Speicher | O(n) | Heap + Map (+ O(n) je Snapshot) |

Alternativen (indizierter Heap für O(log n)-Update, Lazy Deletion, `TreeSet`) siehe [ADR-001](adr/001-priority-queue.md).

## Nebenläufigkeit

Eine reentrante `PracticeLock` schützt alle Mutationen und konsistente Lesezugriffe über Patienten, Räume und Queue
(ADR-004). Events werden innerhalb der Sperre veröffentlicht, ihre Reihenfolge entspricht der Zustandsreihenfolge.
`PatientServiceTest.concurrentAdmissionsKeepQueueConsistent` prüft 8 Threads × 50 Aufnahmen.

## REST-API

Fehlerformat (alle 4xx/5xx):

```json
{ "timestamp": "2026-01-01T10:00:00Z", "status": 409, "error": "Conflict",
  "message": "Room room-1 is OCCUPIED and cannot accept a patient (requires AVAILABLE)", "details": [] }
```

`400` bei Validierung (`details`: `["name: must not be blank", "urgency: must not be null"]`), unlesbarem JSON oder
unbekanntem Enum-Wert (z. B. das verworfene `NORMAL`), `404` unbekannte ID, `409` unzulässiger Zustandswechsel,
`500` unerwarteter Fehler (nur generische Meldung, Details im Log).

`POST /api/patients` – Request / Response `201`:

```json
{ "name": "Alex Beispiel", "urgency": "HIGH" }
```
```json
{ "id": "5bedb081-…", "name": "Alex Beispiel", "urgency": "HIGH", "priority": 2,
  "arrivedAt": "2026-11-12T21:17:37.847Z", "status": "WAITING", "queuePosition": 1 }
```

`POST /api/rooms/room-1/call-next` → `200`:

```json
{ "patient": { "id": "…", "name": "…", "urgency": "HIGH", "priority": 2, "arrivedAt": "…", "status": "IN_TREATMENT", "queuePosition": null },
  "room":    { "id": "room-1", "name": "Raum 1", "status": "OCCUPIED", "patientId": "…", "patientName": "…" } }
```

Eingabegrenzen: `name` nicht leer, höchstens 80 Zeichen; `urgency` ∈ `CRITICAL|HIGH|MEDIUM|LOW`.

## WebSocket-Vertrag

- Handshake: `ws://localhost:8080/ws` (STOMP über reines WebSocket). Erlaubte Origins: `praxis.cors.allowed-origin-patterns`.
- Nur Server → Client: Broker `/topic`, Anwendungspräfix `/app` (derzeit ungenutzt). Heartbeat 10 s/10 s.
- Topics: `/topic/queue` (Patienten/Queue), `/topic/rooms` (Räume/Zuweisung).
- Hülle: `{ "type": "<EventType>", "occurredAt": "<ISO-8601 UTC>", "payload": { … } }`

| `type` | Topic | `payload` | Auslöser |
|---|---|---|---|
| `PATIENT_ADDED` | queue | Patient (wie REST) | `POST /api/patients` |
| `PATIENT_REMOVED` | queue | `{ "patientId" }` | `DELETE` |
| `PATIENT_URGENCY_CHANGED` | queue | `{ "patient", "previousUrgency" }` | `PUT` mit anderer Dringlichkeit |
| `QUEUE_CHANGED` | queue | `{ "patients": [Patient…] }` **vollständig, sortiert, mit `queuePosition`** | jede Änderung der Queue |
| `ROOM_STATUS_CHANGED` | rooms | Raum | jede Raumänderung |
| `PATIENT_ASSIGNED` | rooms | `{ "patient", "room" }` | assign / call-next |

`QUEUE_CHANGED` ist autoritativ: Clients ersetzen ihre Liste, sie sortieren nie selbst. Alle Events sind idempotent
anwendbar. Ein fehlgeschlagener Broadcast bricht die Fachoperation nicht ab (nur Log-Warnung).

## Flutter-Frontend (feature-first, BLoC)

```
lib/
├── main.dart                 schlanker Startpunkt
├── app/{app.dart, router/, theme/, di/}   Composition Root (AppDependencies), Providers, Theme
├── core/{network, error, constants}       ApiClient (HTTP), RealtimeClient (Interface) + StompRealtimeClient, Exceptions
├── shared/widgets/                        StatusChip, Loading/Error/Empty-Views
└── features/
    ├── triage_queue/{data/{models,datasources,repositories}, domain/{entities,repositories}, presentation/{bloc,pages,widgets}}
    ├── rooms/{…gleiche Struktur…}
    └── dashboard/presentation/{pages,widgets,cubit}
```

- UI → BLoC-Events → Repository-Interface (Domain) → Impl (Data) → `ApiClient`/`RealtimeClient`. Widgets sprechen nie direkt HTTP/WebSocket.
- **Ein** `RealtimeClient` pro App (im Composition Root erzeugt und freigegeben). `StompRealtimeClient` nutzt den
  Auto-Reconnect von `stomp_dart_client`, bricht veraltete Abos vor dem erneuten Abonnieren ab (kein doppeltes
  Abonnieren) und meldet `connecting/connected/disconnected` als Stream (`replayCurrent`).
- Repositories bieten `watch…()`-Streams: sie liefern `QUEUE_CHANGED`/`ROOM_STATUS_CHANGED` und führen **nach jedem
  (Re-)Connect einen REST-Abgleich** durch – der REST-Snapshot ist nach einem Ausfall die Wahrheit.
- BLoCs abonnieren zuerst den Stream, laden dann per REST (kein verpasstes Event), laden nach jeder Benutzeraktion
  per REST nach (korrekt auch ohne WebSocket) und geben Abos in `close()` frei. Fehler → `failure`-State mit Retry bzw.
  transienter `actionError` (Snackbar) ohne die Liste zu verlieren.
- UI: ab 900 px Breite zwei Spalten, darunter Tabs; Status immer mit Text + Icon + Farbe; Dropdown/Buttons sind
  tastaturbedienbar; Ladezustand, Fehlerzustand und Leerzustand sind umgesetzt.

## Entwicklungs-Konfiguration

`application.yml` (sicherer Standard) · `application-dev.yml` (nur mit Profil `dev`): Demo-Patienten, DEBUG-Logging,
zusätzlicher lokaler Origin `http://[::1]:*`. Port 8080.


## Nachträge der Abschlussprüfung

- **Begrenzter Verlauf:** abgeschlossene Patienten (`COMPLETED`) werden höchstens `praxis.history.max-completed-patients` (Standard 100) im Speicher gehalten, die ältesten fliegen zuerst raus (O(n) pro Abschluss, getestet in `PatientServiceTest`). Wartende und behandelte Patienten sind nie betroffen.
- **Sicherheits-Header:** `SecurityHeadersFilter` setzt `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy` und `Cache-Control: no-store` für `/api/**` (getestet).
- **Entkoppelte Features (Frontend):** `triage_queue` und `rooms` importieren sich nicht mehr gegenseitig; das Dashboard übergibt die zuweisbaren Räume bzw. die Information "Warteschlange nicht leer". Durchgesetzt durch `frontend/test/architecture_test.dart`.
