# Changelog

Alle nennenswerten Änderungen an diesem Projekt stehen in dieser Datei.

Das Format folgt [Keep a Changelog](https://keepachangelog.com/de/1.1.0/), die
Versionierung [Semantic Versioning](https://semver.org/lang/de/).

Bei einem Release werden die Einträge unter „Unreleased“ in einen Abschnitt für
die neue Version verschoben. Der Broker (`scripts/request.sh … --publish`)
veröffentlicht nur, wenn „Unreleased“ leer ist und für die Version ein Abschnitt
existiert; dessen Text wird zu den Release-Notes.

## [Unreleased]

## [0.1.2] - 2026-09-21

### Hinzugefügt

- **Die App hat ein Icon.** Bisher zeigte `OpenZonr.app` überall das generische
  Platzhalter-Symbol — im Finder, in der Liste unter Systemeinstellungen →
  Datenschutz & Sicherheit → Bedienungshilfen, im Update-Dialog, im
  DMG-Fenster. Das neue Icon zeigt ein Fenster, das in drei Zonen im Verhältnis
  25/50/25 geteilt ist — dieselbe Aufteilung wie die Vorlage „wide" —, die
  mittlere Zone in Akzentblau hervorgehoben wie das Ziel unter dem Zeiger beim
  Ziehen. Es entsteht aus Code (`swift Scripts/make-icon.swift`), liegt als
  `Resources/AppIcon.icns` im Repo und wird von `Scripts/bundle.sh` vor dem
  Signieren nach `Contents/Resources` kopiert; `Info.plist` verweist mit
  `CFBundleIconFile` darauf
  ([#55](https://github.com/trsdn/OpenZonr/issues/55)).
  Auch im veröffentlichten Bundle: der Broker kopiert die Datei über das
  Profilfeld `app_icon` (trsdn/macos-notarization-broker#66) vor dem
  Signieren in `Contents/Resources`. Bis das Icon im Finder erscheint, kann
  macOS noch das alte Platzhalter-Symbol aus seinem Cache zeigen
  (`killall Finder`).
- **Eine Zeile „Letzter Zug" im Menü, die sagt, warum die Zonen ausblieben.**
  „Letzter Zug: keine Zonen — ⌘ war nicht gedrückt.", „… kein Fenster unter dem
  Zeiger erkannt.", „… Bewegung nicht als Fensterzug erkannt.", „… losgelassen,
  bevor sich das Fenster bewegt hat." Vier Ursachen, die bisher alle gleich
  aussahen: es passiert nichts. `EventTapDragTracker` hat dafür einen zweiten
  Rückweg (`onOutcome`) für Drücke bekommen, die es nie bis zu einem Zug
  schaffen — höchstens ein Satz je Druck, keiner für einen gewöhnlichen Klick,
  und weiterhin kein AX-Aufruf im Tap-Rückruf
  ([#26](https://github.com/trsdn/OpenZonr/issues/26),
  [#37](https://github.com/trsdn/OpenZonr/issues/37)).

### Geändert

- **Das Menü der Menüleisten-App ist neu sortiert und spricht Alltagssprache.**
  Statt eines Zustandsnamens mit Zähler („Kein Profil passt — 2 Profile in der
  Konfiguration") steht jetzt **eine** Zeile da, die sagt, woran man ist, und
  höchstens ein Knopf, der sagt, was zu tun ist: „Zugriff fehlt — ohne ihn kann
  OpenZonr keine Fenster bewegen" mit „Zugriff freigeben …", „Bereit — Setup
  „Schreibtisch"", „Kein Setup passt zu den angeschlossenen Bildschirmen" mit
  „Was ist zu tun? …", „Pausiert". Ganz oben steht in **jedem** Zustand „OpenZonr"
  mit der Fassung aus dem Bundle ([#56](https://github.com/trsdn/OpenZonr/issues/56)).
  Alles Technische und Seltene — Setup von Hand wählen, letzte Platzierungen,
  Konfiguration neu laden, Status und Berechtigung, Autostart, die
  Update-Einstellungen — liegt unter „Mehr". Nichts ist weggefallen; ein
  bereitliegendes Update und die Warnung vor einem zweiten Fenstermanager
  bleiben oben, weil beides eine Entscheidung verlangt.
- **Aus zwei Schaltern fürs Ziehen ist eine Frage geworden: wann kommen die
  Zonen?** „Fenster in Zonen ziehen" plus eine unsichtbare Aktivierungsregel in
  der Datei sind ersetzt durch drei Zeilen unter „Zonen beim Ziehen": „Bei jedem
  Ziehen", „Nur mit gehaltener ⌘-Taste", „Aus". Der Haken steht am **wirksamen**
  Zustand aus der geladenen Konfiguration. Eine von Hand geschriebene Regel, die
  keine der drei ist (etwa „nur mit ⌥"), bekommt eine eigene, angehakte Zeile
  statt eines falschen Hakens — auch während „Aus" gilt, und dann ist die Zeile
  der Weg zurück: anklicken schaltet ein, ohne die Regel anzutasten. Der
  gewählte Zustand steht in der Aufschrift der Elternzeile („Zonen beim Ziehen:
  nur mit ⌘"), damit er ohne Aufklappen zu sehen ist. Geschrieben wird sofort
  und in die Datei, wie bisher der Schalter
  ([#41](https://github.com/trsdn/OpenZonr/issues/41)).
- Menüeinträge umbenannt: „Regeln bearbeiten …" heißt „Zonen und Regeln
  bearbeiten …", „Aktuelles Fenster hier festhalten" heißt „Aktuelles Fenster
  festhalten", „Platzierung pausieren" ist zu „Fenster automatisch platzieren"
  umgedreht.

## [0.1.1] - 2026-09-20

### Behoben

- **Monitore ohne Seriennummer werden trotz wandernder Port-Nummer erkannt.** Die
  Nummer (`CGDisplayUnitNumber`) verschiebt sich, wenn Software-Displays kommen
  und gehen (gemessen: derselbe Monitor, dasselbe Kabel, 0 am 29.08. und 1 am
  19.09.). Danach passte kein Profil mehr, und die gesamte Dropzone-Funktion
  (Overlay beim Ziehen und Zonenmenü am grünen Knopf) war ohne Meldung weg. Ein
  Monitor ohne Seriennummer wird jetzt unabhängig vom `portIndex` erkannt, wenn
  Hersteller und Modell in der Konfiguration und unter den angeschlossenen
  Bildschirmen genau einmal vorkommen; ein exakter Treffer gewinnt zuerst.
  Baugleiche Monitore ohne Seriennummer hängen weiter am `portIndex`, unbekannte
  Displays führen weiter zu „kein Profil“ (es wird nicht geraten).

### Geändert

- `openzonr displays` nimmt `--config <pfad>` und meldet einen so erkannten Fall
  als eine Zeile („konfiguriert als port=0, aktuell port=1: erkannt, weil
  eindeutig“); dieselbe Zeile steht in der Watch-Diagnose.

## [0.1.0] - 2026-09-19

Erster Release. Bestehende Installationen ohne Updater müssen einmal von Hand
ersetzt werden; ab dem zweiten Release aktualisiert sich die App selbst.

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
