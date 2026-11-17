# ADR-004: In-Memory-Persistenz und eine grobe Sperre

- Status: akzeptiert (Demo-Umfang)

## Entscheidung

Repositories sind `Map`-basiert im Speicher. Alle Mutationen und konsistenten Lesezugriffe über Patienten, Räume
und Queue laufen unter einer gemeinsamen reentranten `PracticeLock`.

## Begründung

„Patient einem Raum zuweisen“ verändert drei Strukturen (Patient, Raum, Queue) und muss atomar sein; zwei gleichzeitige
Zuweisungen dürfen weder einen Raum doppelt belegen noch einen Patienten doppelt zuweisen. Eine einzige Sperre ist
hier die einfachste korrekte Lösung (kein Deadlock-Risiko durch Sperrreihenfolgen).

## Konsequenzen

- Kein Durchsatz-Optimum (alles serialisiert) – bei Praxis-Größenordnung irrelevant.
- Datenverlust bei Neustart ist gewollt; die Repository-Interfaces erlauben später JPA/Datenbank. Eine Datenbank
  gehört **nicht** zum vereinbarten Umfang.
- Eine Instanz; für mehrere Instanzen wären DB-Transaktionen und ein externer Broker nötig.
