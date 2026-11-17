# Ablaufplan für das Demo-Video (60–120 Sekunden)

Ziel: kurze Bildschirmaufnahme der **tatsächlich laufenden** Anwendung für GitHub und LinkedIn. Es entsteht keine öffentliche Live-Demo und es fallen keine Hosting-Kosten an.

## Vorbereitung (einmalig, ca. 5 Minuten)

1. Alte Instanzen beenden und frisch starten (saubere Demodaten: drei synthetische Patienten):
   ```powershell
   .\scripts\stop-demo.ps1 -Backend
   .\scripts\demo.ps1 -NoBrowser
   ```
2. **Zwei Browserfenster** nebeneinander öffnen (je halbe Bildschirmbreite, z. B. Windows-Taste + ←/→), beide `http://localhost:5555`.
   Das linke Fenster ist das „Bedienfenster“, das rechte zeigt die Echtzeit-Synchronisierung.
3. Browser-Zoom 100 %, Lesezeichenleiste und Erweiterungen ausblenden, Benachrichtigungen aus (Windows „Nicht stören“).
4. Aufnahmewerkzeug: Windows-Spielleiste (`Win + G`, 1080p, ohne Mikrofon) oder OBS Studio (kostenlos). Ein kurzer Kommentar kann nachträglich eingesprochen werden; Untertitel sind für LinkedIn hilfreich.
5. Optional: Beide Fenster einmal neu laden und warten bis „Live verbunden“ erscheint.

## Drehbuch

| Zeit | Aktion | Was der Zuschauer sieht / Sprechtext (Vorschlag) |
|---|---|---|
| 0:00–0:08 | **Dashboard öffnen** (beide Fenster) | „Echtzeit-Dashboard einer Praxis: links die Warteschlange, rechts die Behandlungsräume – synthetische Daten, kein medizinisches System.“ |
| 0:08–0:20 | **Demo-Patient hinzufügen** (2–3×, links) | Patienten erscheinen sofort **auch im rechten Fenster** – ohne Neuladen (WebSocket). |
| 0:20–0:35 | **Dringlichkeit ändern**: einen Patienten mit „Niedrig“ auf „Kritisch“ stellen | „Die PriorityQueue sortiert automatisch neu: Priorität 1 steht vorn, bei gleicher Stufe gilt die Ankunftsreihenfolge (FIFO).“ |
| 0:35–0:45 | **Neusortierung zeigen** (kurz auf die Positionsnummern zeigen, beide Fenster) | Reihenfolge ist in beiden Fenstern identisch. |
| 0:45–0:55 | **Patient aufrufen**: bei einem freien Raum „Nächsten aufrufen“ | Der Kopf der Queue geht in den Raum, Raum → *Belegt*. |
| 0:55–1:05 | **Patient einem Raum zuweisen**: bei einem anderen Patienten „Aufrufen“ → Raum wählen | Dialog zeigt nur freie Räume; Status *Wartet → In Behandlung*. |
| 1:05–1:15 | **Behandlung abschließen** | Raum wechselt auf **Reinigung** – er wird *nicht* automatisch frei. |
| 1:15–1:25 | **Raum reinigen und freigeben**: „Reinigung beendet“ | Raum wieder *Verfügbar*; im zweiten Fenster zeitgleich. |
| 1:25–1:40 | **Echtzeit zweier Fenster**: im rechten Fenster etwas ändern (z. B. Demo-Patient), im linken zeigen | „Jede Änderung wird per STOMP an alle Dashboards verteilt.“ |
| 1:40–2:00 | Optional: **Wiederverbindung** – `.\scripts\stop-demo.ps1 -Backend` im Terminal, Banner „getrennt“ zeigen, Backend neu starten, „Live verbunden“ | „Automatischer Reconnect, danach REST-Abgleich.“ |

Tipp: Für 60 Sekunden die Schritte 0:35 und die Wiederverbindung weglassen.

## Nach der Aufnahme

- Video als `docs/media/demo.mp4` **nicht** ins Repository committen (Größe). Stattdessen auf GitHub (Release/Issue/PR hochladen, „drag & drop“ ergibt eine `user-images`-URL) oder YouTube/LinkedIn hochladen.
- Den Link in der README unter „Demo“ eintragen (`🎬 **Demo video:** [...]`). Optional ein kurzes GIF (≤ 5 MB) als `docs/media/demo.gif` einbinden.
- Vorher prüfen: keine persönlichen Daten im Bild (Lesezeichen, Tabs, Benutzername in der Taskleiste, Dateipfade).

## Screenshots neu erzeugen

```powershell
.\scripts\capture-screenshots.ps1   # schreibt docs\screenshots\*.png (eigenes Backend auf Port 18082, synthetische Daten)
```
