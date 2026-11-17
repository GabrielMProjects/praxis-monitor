# ADR-003: Flutter feature-first mit BLoC, Repository-Streams und einem WebSocket

- Status: akzeptiert

## Entscheidung

- Struktur `features/<feature>/{data,domain,presentation}` plus `core/`, `shared/`, `app/`.
- BLoC (`flutter_bloc`); Zugriff auf Daten nur über Repository-Interfaces.
- Genau **ein** `RealtimeClient` (STOMP) im Composition Root (`AppDependencies`, manuelle Konstruktor-Injektion).
- Repositories liefern `watch…()`-Streams und synchronisieren nach jedem (Re-)Connect per REST.

## Begründung

- Fachlich getrennte Features, einfache Tests (Fakes für `RealtimeClient`, `MockClient` für HTTP).
- Der REST-Snapshot nach Reconnect behebt Lücken, die während eines Verbindungsabbruchs entstanden sind.
- Manuelles DI genügt bei dieser Größe; kein Service-Locator nötig (`get_it` wäre später ein kleiner Schritt).

## Konsequenzen

- Die Features kennen sich nicht: das Dashboard (Kompositionsebene) übergibt der Queue-Seite die zuweisbaren Räume und der Raum-Seite, ob jemand wartet. Das ersetzt die frühere Kopplung der Seiten über den jeweils anderen BLoC (Architekturtest in `test/architecture_test.dart`).
- Nach jeder Benutzeraktion wird zusätzlich per REST nachgeladen: Ein Roundtrip mehr, dafür funktioniert die UI auch
  bei ausgefallener WebSocket-Verbindung.
