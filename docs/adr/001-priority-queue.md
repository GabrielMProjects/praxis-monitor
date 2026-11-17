# ADR-001: `PriorityQueue` + Sequenznummer statt sortierter Liste

- Status: akzeptiert
- Kontext: Die Warteschlange muss nach Dringlichkeit, bei Gleichstand nach Ankunft sortiert sein (technische Demo).

## Entscheidung

`java.util.PriorityQueue<QueueEntry>` mit explizitem Comparator (`priority`, dann `sequence`) plus `HashMap`-Index
und monotoner, backendseitig vergebener Sequenznummer. Anzeige über sortierten Snapshot.

## Begründung

- `PriorityQueue` ist nicht stabil: gleiche Elemente kommen in unspezifizierter Reihenfolge. Die eindeutige Sequenz
  macht die Ordnung total und deterministisch.
- Die Sequenz kommt vom Backend, nicht vom Client (Uhren/Manipulation). `Instant` dient nur der Anzeige.
- Eine Dringlichkeitsänderung behält die Sequenz (kein Nachteil/Vorteil beim Ankunftsrang).

## Laufzeitvergleich (n = wartende Patienten)

| Operation | `PriorityQueue` + Index (gewählt) | Sortierte `ArrayList` | `TreeSet<QueueEntry>` | Indizierter Heap |
|---|---|---|---|---|
| Einfügen | O(log n) | O(n) (Einfügeposition + Verschieben) | O(log n) | O(log n) |
| Nächster (`peek`/`poll`) | O(1) / O(log n) | O(1) / O(n) | O(log n) | O(1) / O(log n) |
| Entfernen beliebig | **O(n)** | O(n) | O(log n) | O(log n) |
| Dringlichkeit ändern | **O(n)** | O(n) | O(log n) | O(log n) |
| Sortierte Anzeige | O(n log n) | O(n) | O(n) | O(n log n) |

Ehrliche Einordnung: Die Stärke der Wahl liegt bei `offer`/`poll`/`peek`. Beliebiges Entfernen und Updates sind in
der Standard-`PriorityQueue` O(n) (lineare Suche). Für eine Praxis (n im zweistelligen Bereich) ist das irrelevant.
Ein `TreeSet` wäre asymptotisch besser für Updates, bietet aber keinen Mehrwert für die Demonstration des
Heap-/Comparator-/Stabilitätsthemas. Skalierung: indizierter Heap oder Lazy Deletion.

## Konsequenzen

- Eager Removal hält Heap und Index immer identisch (keine veralteten Einträge); Property-artiger Test
  (`TriageQueueTest.heapAndIndexStayConsistentUnderRandomOperations`) prüft das mit 2000 Zufallsoperationen.
- `PriorityQueue.iterator()` darf nie als sortierte Ansicht dienen.
