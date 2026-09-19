# Changelog

Alle nennenswerten Änderungen an diesem Projekt stehen in dieser Datei.

Das Format folgt [Keep a Changelog](https://keepachangelog.com/de/1.1.0/), die
Versionierung [Semantic Versioning](https://semver.org/lang/de/).

Bei einem Release werden die Einträge unter „Unreleased“ in einen Abschnitt für
die neue Version verschoben. Der Broker (`scripts/request.sh … --publish`)
veröffentlicht nur, wenn „Unreleased“ leer ist und für die Version ein Abschnitt
existiert; dessen Text wird zu den Release-Notes.

## [Unreleased]

### Hinzugefügt

- **In-App-Updates aus GitHub Releases** über AppUpdater 4.1.2 (#47): Menüpunkte
  „Nach Updates suchen…“ und „Automatisch nach Updates suchen“ (standardmäßig an).
  Vor der Installation hält die App Beobachtung und ausstehende Platzierungen an.
  Installierte Versionen ohne Updater müssen einmal von Hand ersetzt werden.
- Zoneneditor mit Raster, Kantenfang, Abdeckungsprüfung und Vorlagen; Übersicht
  „Wohin geht was?“ und Dry-Run-Zeile im Regel-Editor.

### Geändert

- Die ausführbare Datei im App-Bundle heißt jetzt `OpenZonrApp` (vorher
  `OpenZonr`), weil der Broker Produkt- und Dateinamen gleichsetzt. Pfad,
  Bundle-Identifier und Signatur bleiben gleich.
- Die Zusage zur Bedienungshilfen-Freigabe lautet jetzt „übersteht einen Neubau in
  der Regel“; ist sie danach ungültig, hilft nur Eintrag entfernen und neu
  hinzufügen (#35).

### Behoben

- Ausstehende Platzierungen laufen nach Pause, Stopp, Reload oder einer neueren
  Anfrage nicht mehr weiter (#38).
- Bei „Ersetzen“ wird der bisherige Bewohner tatsächlich an den Fallback
  verschoben, und die Zonenbelegung folgt dem echten Ergebnis: Belegung wird
  beim Beenden von Apps und bei fehlgeschlagenen Platzierungen bereinigt (#40,
  #45).
- Der Menü-Schalter für Dropzones wirkt sofort, auch wenn der Editor schon
  geöffnet war (#41).
- Der Editor überschreibt nach einem Neuladen keine extern geänderte
  Konfiguration mehr; bei Konflikt wird das Speichern blockiert (#42).
- Ablegen und das Zoom-Menü beachten den Layout-Rand wie die Automatik (#43).
- Die Berechtigungsabfrage startet das Verfolgen eines Zugs nicht mehr alle zwei
  Sekunden neu (#44).
- Ziehen von Fensterinhalt (Text, Scrollleiste, Größenänderung) löst kein
  Platzieren oder Anheften mehr aus; ein Fensterzug wird an der tatsächlichen
  Fensterbewegung erkannt (#37). Bisher nur in TextEdit gemessen; die Anzeige des
  Overlays beginnt dadurch etwa 150 ms später.
- Die Identität eines Monitors ohne Seriennummer hängt nicht mehr vom aktuellen
  Anzeigemodus ab; bestehende Konfigurationen werden weiter erkannt (#39).
