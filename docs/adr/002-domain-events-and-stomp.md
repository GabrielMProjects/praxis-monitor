# ADR-002: Domain-Events + separater STOMP-Publisher

- Status: akzeptiert

## Entscheidung

Application-Services veröffentlichen sealed `DomainEvent`s über `ApplicationEventPublisher`. Nur
`WebSocketEventPublisher` (`@EventListener`) übersetzt sie in STOMP-Nachrichten (`/topic/queue`, `/topic/rooms`).
Nachrichtenhülle `{type, occurredAt, payload}`; `QUEUE_CHANGED` trägt die komplette sortierte Queue.

## Begründung

- Services/Domain bleiben ohne WebSocket-Abhängigkeit testbar (`PracticeFixture` fängt Events in einer Liste).
- Komplette Snapshots statt Deltas: Clients bleiben einfach und idempotent; verpasste Nachrichten werden durch den
  nächsten Snapshot bzw. den REST-Abgleich nach Reconnect korrigiert.
- Ein fehlgeschlagener Broadcast darf die Fachoperation nicht zurückrollen (try/catch + Log).

## Konsequenzen / Alternativen

- Einfacher Broker (in-memory), keine Skalierung auf mehrere Instanzen (dafür externer Broker nötig).
- Reines WebSocket statt SockJS (Flutter-Client unterstützt es direkt).
- Delta-Events wären kleiner, erfordern aber Reihenfolge-/Verlustbehandlung im Client – für die Demo unnötig komplex.
