# OpenZonr

**Status: lauffähiges Kommandozeilenwerkzeug und eine Menüleisten-App.**
Datenmodell, Konfigurationsspeicher, Regel-Engine und die Anbindung an
Accessibility und CoreGraphics sind gebaut und getestet.

**Der Kern funktioniert und ist gemessen.** Am echten Vier-Display-Schreibtisch
landen TextEdit und Outlook beim Start in ihrer Zone — jeweils beim ersten
Versuch, mit einer Abweichung von 1,0 beziehungsweise 0,0 Punkten. Die Zahlen
und der Weg dorthin stehen in [`docs/tracer-bullet.md`](docs/tracer-bullet.md).

Zwei Einschränkungen, die man vor dem Ausprobieren kennen sollte:

1. **Es braucht ein signiertes Bundle.** `Scripts/bundle.sh` erledigt das. Eine
   unsignierte Binärdatei verliert die Bedienungshilfen-Berechtigung nach jedem
   Neubau — sie startet, sieht aber keine Fenster. Ohne Developer-ID-Zertifikat
   ist OpenZonr derzeit nicht benutzbar.
2. **Die Oberfläche ist eine Menüleisten-App, mehr nicht.** Sie beherbergt den
   Watcher, zeigt Zustand, Profil und die letzten Platzierungen und startet auf
   Wunsch beim Anmelden mit — [`docs/menueleisten-app.md`](docs/menueleisten-app.md).
   Regeln werden weiterhin als JSON bearbeitet, und Dropzones zum Hineinziehen
   gibt es nicht.

OpenZonr ist ein Fenstermanager für macOS mit Dropzones. Der Unterschied zu allem,
was es sonst gibt, steckt in einem einzigen Satz:

> **Apps öffnen sich von selbst in der Zone, die für sie vorgesehen ist.**

## Das Problem

Bestehende Tools lösen das Verschieben, nicht das Öffnen:

> „Ich will, dass Outlook immer in Zone 2 aufgeht. Heute geht es irgendwo auf,
> außer ich ziehe es selbst in die Dropzone."

Genau dieses Ziehen ist der wunde Punkt. Jede App, jeden Tag, nach jedem Neustart,
nach jedem Monitorwechsel. Zonen zu definieren ist gelöst — Fenster automatisch
dort landen zu lassen nicht.

## Der Ansatz

1. **Fenster erkennen** — `NSWorkspace.didLaunchApplication` plus ein `AXObserver`
   je App auf `kAXWindowCreatedNotification`.
2. **Regel finden** — Match-Kriterien wie Bundle-ID, Titel-Regex, Subrole,
   Fenstergröße.
3. **Rolle auflösen** — Regeln zeigen auf eine *Rolle* (z. B. „Kommunikation"),
   nicht auf eine Zone. Das aktive Profil übersetzt die Rolle in Display + Zone.
4. **Platzieren** — `kAXPositionAttribute` / `kAXSizeAttribute`, mit Retry-Loop
   gegen Apps, die sich nach dem Öffnen selbst nochmal resizen.

Alles Weitere steht in **[docs/konzept.md](docs/konzept.md)**.

## Abgrenzung

| Tool | Was es tut | Was fehlt |
|---|---|---|
| **Rectangle / Rectangle Pro** | Fenster per Shortcut oder Drag in Hälften, Drittel, benutzerdefinierte Zonen legen. Rectangle Pro kann App-Regeln beim Start anwenden. | Keine Rollen-Indirektion: Regeln hängen an konkreten Bildschirmbereichen und müssen pro Setup gepflegt werden. Keine EDID-stabile Monitoridentität. |
| **yabai** | Vollwertiger Tiling-WM mit Scripting-Sprache; sehr mächtig. | Verlangt teilweise das Deaktivieren von SIP. Automatisches Tiling statt fester, selbst gezeichneter Zonen. Regeln sind Skriptcode, keine teilbare Konfiguration. |
| **Amethyst** | Automatisches Tiling nach Layout-Algorithmen, App-Regeln vor allem als Float-Ausnahmen. | Man wählt ein Layout, keine frei platzierten Zonen. Kein „diese App gehört hierhin, unabhängig davon, was sonst offen ist". |
| **FancyZones (Windows)** | Das direkte konzeptionelle Vorbild inklusive App-Zuordnung zu Zonen. | Gibt es für macOS nicht — und die Layoutzuordnung hängt an Auflösung und Monitorreihenfolge statt an einer stabilen Monitoridentität. |
| **Moom, Magnet, Swish** | Komfortables manuelles Anordnen. | Ausdrücklich manuell. |

OpenZonr ist bewusst **kein** Tiling-Window-Manager. Es ordnet nicht automatisch
alles an, sondern platziert die wenigen Apps, für die man eine klare Vorstellung
hat, zuverlässig dort, wo sie hingehören — und lässt den Rest in Ruhe.

Zwei Dinge sind der Kern:

- **Rollen statt Zonen.** App-Regeln werden einmal geschrieben, nicht pro Setup
  dupliziert. Jedes Profil mappt Rollen auf seine eigenen Zonen.
- **Monitoridentität über EDID.** Ein Profil wird über das Set der tatsächlich
  angeschlossenen Monitore erkannt, nicht über Position, Index oder Auflösung.
  Umstecken ändert nichts.

## Projektstruktur

```
Package.swift                 SwiftPM-Manifest (macOS 14+)
Sources/OpenZonrCore/
  Geometry/                   RelativeRect, Zone, Layout
  Display/                    DisplayIdentity, SetupFingerprint, Anordnung
  Roles/                      ZoneRole, RoleBinding
  Rules/                      WindowMatch, PlacementAction, PlacementRule
  Profiles/                   Profile
  Configuration/              Configuration, Speicher, atomares Schreiben
    Migration/                Schrittkette zwischen Schemaversionen
  Validation/                 Validierung mit Dokumentpfaden
    Checks/                   Die einzelnen Prüfungen
  Placement/                  Filter, Regel-Engine, Profil- und Zonenauflösung,
                              Retry-Schleife
Sources/OpenZonrMac/          Die macOS-Anbindung, von beiden Oberflächen genutzt
  Accessibility/              AXObserver, Fensterinventar
  Displays/                   CGDisplay, Bildschirmidentität
  Watch/                      WatchEngine — Beobachtung und Platzierung
  CommandLine/                Die Unterbefehle
  Support/                    Protokoll, Konfigurationspfad, Signaturstatus
Sources/OpenZonrApp/          Menüleisten-App (MenuBarExtra, LSUIElement)
Sources/openzonr/             `swift run openzonr` für die Entwicklung
Tests/OpenZonrCoreTests/      Unit-Tests; Support/ enthält Fixtures
Tests/OpenZonrMacTests/       Die rein rechnenden Teile der macOS-Schicht
Examples/                     Beispielkonfiguration (Büro / Home / Unterwegs)
docs/                         Konzept, Konfiguration, Durchstich, offene Fragen
```

`OpenZonrCore` ist die plattformunabhängige, getestete Hälfte. `OpenZonrMac`
enthält alles, was mit macOS spricht — und wird von beiden Oberflächen geteilt,
statt von jeder neu geschrieben zu werden: die Beobachtungs- und
Platzierungslogik darin ist am echten Schreibtisch gemessen, und drei ihrer
Details waren nur durch Messen zu finden.

**Warum Swift Package Manager und kein Xcode-Projekt?** Das Manifest ist Text,
also diff- und reviewbar, und es gibt keine `.pbxproj`-Merge-Konflikte. Vor allem
bleiben `swift build` und `swift test` die ganze Wahrheit — zwei Buildsysteme
wären zwei Wahrheiten, von denen eine unbemerkt veraltet. Das Bundle samt Signatur
erzeugt `Scripts/bundle.sh` ohne Xcode. Ausführlich in
[docs/menueleisten-app.md](docs/menueleisten-app.md).

**Im Bundle liegt genau eine Binärdatei**, und sie ist beides: ohne Argumente die
Menüleisten-App, mit einem Unterbefehl das Kommandozeilenwerkzeug. Der Grund ist
die Art, wie macOS die Berechtigung vergibt — sie gilt einem Programm an seinem
Pfad, zwei Binärdateien wären zwei Freigaben.

## Bauen

```bash
swift build
swift test
```

Mindestanforderung: macOS 14, Swift 6. Die verwendeten APIs (Accessibility,
`CGDisplay*`, `NSWorkspace`) sind deutlich älter; macOS 14 ist für die spätere
UI-Schicht (Observation, `MenuBarExtra`) gesetzt.

## Das Kommandozeilenwerkzeug `openzonr`

Vier Unterbefehle: drei zur Diagnose, einer für den Durchstich.

```bash
swift run openzonr --help
```

### Accessibility freischalten

Ohne Berechtigung kann kein Werkzeug Fenster lesen oder bewegen. **Und ohne
Signatur greift die Berechtigung nicht** — das ist der Stolperstein, der beim
Bauen dieses Werkzeugs die meiste Zeit gekostet hat.

```bash
Scripts/bundle.sh
```

Das Skript baut, packt `~/Applications/OpenZonr.app` und signiert es mit dem
ersten gefundenen Developer-ID-Zertifikat (überschreibbar per
`CODESIGN_IDENTITY`). Danach einmalig:

1. Systemeinstellungen → Datenschutz & Sicherheit → **Bedienungshilfen**
2. `~/Applications/OpenZonr.app` hinzufügen und aktivieren
3. Gegenprobe — und zwar so, wie die App später wirklich startet:

   ```bash
   open -n -a ~/Applications/OpenZonr.app --args selftest --out /tmp/openzonr.txt
   cat /tmp/openzonr.txt      # muss "granted" melden
   ```

   Aus der Shell gestartet misst dieselbe Binärdatei etwas anderes: dort erbt sie
   das Vertrauen des Terminals, und `AXIsProcessTrusted()` meldet `true`, ohne
   dass ein Fenster lesbar wäre. `selftest` weist den Startweg deshalb aus.

Warum der Umweg über ein Bundle:

- **Eine unsignierte Binärdatei bekommt bei jedem `swift build` eine neue
  Prüfsumme.** Der Haken bleibt gesetzt und meint ein anderes Programm. Die
  Signatur bindet stattdessen an Bundle-Identifier und Team und überlebt jeden
  Neubau.
- **Die Freigabe gilt dem Bundle an seinem Pfad.** Deshalb legt
  `Scripts/bundle.sh` es unter `~/Applications` ab und nicht in `.build`: dort
  überlebt es `swift package clean`, einen zweiten Klon des Repos und den Umzug
  des Arbeitsverzeichnisses. Ein Bundle an einem neuen Pfad ist erneut
  freizugeben, auch bei identischer Signatur.
- **`AXIsProcessTrusted()` kann dabei `true` melden, ohne dass der Zugriff
  funktioniert.** Dann liefert jede App auf `AXWindows` nur ein
  Stellvertreter-Element der Rolle `AXApplication` ohne Position und Größe.
  Aus der Shell gestartet erbt der Prozess das Vertrauen des Terminals, die
  Fensterzugriffe erben es nicht. `openzonr` erkennt diesen Zustand und erklärt
  ihn, statt still nichts zu tun. Details in
  [docs/tracer-bullet.md](docs/tracer-bullet.md).
- Bei einem vorhandenen Eintrag aus einem unsignierten Lauf: **entfernen und neu
  hinzufügen.** Den Haken nur neu zu setzen genügt nicht.

### `openzonr displays` — welche Monitore sind da?

Zeigt jedes angeschlossene Display mit seiner stabilen Identität, Auflösung,
Backing-Scale, `frame` und `visibleFrame` sowie den daraus berechneten
Setup-Fingerprint.

```bash
swift run openzonr displays
```

```
Display 1 von 4  — C49RG9x
  Identität   fallback  vendor=19501 model=3996 5120×1440 port=1
              ⚠ Seriennummer ist 0 — Identität über Vendor, Modell,
                Auflösung und Port-Index
  Auflösung   5120×1440 @1.0x
  frame       (0, 0, 5120, 1440)
  visibleFrame (0, 65, 5120, 1344)
```

Virtuelle Displays werden als solche gekennzeichnet. Mit
`--config-fragment` gibt der Befehl stattdessen ein fertiges `displays`-Fragment
im Konfigurationsformat aus, das sich direkt übernehmen lässt:

```bash
swift run openzonr displays --config-fragment
```

**Das ist der verbindliche Weg zu echten Identitäten.** Die Zahlen in
`Examples/openzonr.config.json` sind erfunden.

### `openzonr windows` — wie sehen die Fenster aus?

Listet die Fenster der laufenden Apps mit Bundle ID, Titel, Subrolle, Position,
Größe und belegtem Display. Damit findet man Match-Kriterien für Regeln — etwa
wie sich Outlooks Haupt-, Verfassen- und Erinnerungsfenster unterscheiden.

```bash
swift run openzonr windows
swift run openzonr windows --bundle com.microsoft.Outlook
```

### `openzonr watch` — der Durchstich

Beobachtet neu geöffnete Fenster und platziert sie nach den Regeln der
Konfiguration. Läuft im Vordergrund und protokolliert jeden Schritt.

```bash
swift run openzonr watch
swift run openzonr watch --config ~/meine-config.json
swift run openzonr watch --dry-run     # rechnet und protokolliert, bewegt nichts
```

Konfigurationspfad in dieser Reihenfolge: `--config`, dann `OPENZONR_CONFIG`,
sonst `~/Library/Application Support/OpenZonr/config.json`.

### Ein Durchlauf von Anfang bis Ende

```bash
# 1. Bauen, signieren und freigeben (siehe oben — ohne Signatur sieht
#    das Werkzeug keine Fenster)
Scripts/bundle.sh
OZ=~/Applications/OpenZonr.app/Contents/MacOS/OpenZonr

# 2. Die echten Displays ermitteln und als Fragment ausgeben
"$OZ" displays --config-fragment > /tmp/displays.json

# 3. Konfiguration anlegen: Fragment übernehmen, Layouts, Rollen,
#    Profile und Regeln ergänzen. Als Vorlage dient
#    Examples/openzonr.config.json — aber mit den eigenen Identitäten.
#    Vermutlich virtuelle Displays stehen im Fragment bereits unter
#    ignoredDisplays; die Liste gehört geprüft, nicht blind übernommen.
mkdir -p ~/Library/Application\ Support/OpenZonr
$EDITOR ~/Library/Application\ Support/OpenZonr/config.json

# 4. Trocken prüfen: Wird das richtige Profil gewählt?
"$OZ" watch --dry-run

# 5. Match-Kriterien für die Regeln verifizieren
"$OZ" windows --bundle com.microsoft.Outlook

# 6. Scharf schalten, dann die Ziel-App neu starten
"$OZ" watch
```

## Die Menüleisten-App

Dieselbe Binärdatei, ohne Argumente gestartet: ein Symbol in der Menüleiste, das
den Watcher beherbergt, statt ihn im Vordergrund eines Terminals laufen zu lassen.

```bash
Scripts/bundle.sh
open -n ~/Applications/OpenZonr.app
```

Im Menü:

- **Zustand** — aktiv, pausiert, keine Berechtigung, keine Konfiguration oder
  kein passendes Profil. Das Symbol unterscheidet die Fälle.
- **Profil** — das erkannte Profil, und jedes konfigurierte zur Handauswahl. Die
  Auswahl gilt für die Sitzung und wird bewusst nicht gespeichert.
- **Pause** — hält die Platzierung an, ohne die App zu beenden.
- **Letzte Platzierungen** — was zuletzt wohin ging, samt vollständigem
  Protokollstrom in einem eigenen Fenster.
- **Beim Anmelden starten** — über `SMAppService`.

Fehlt die Berechtigung, öffnet sich beim Start einmal ein Fenster, das den
konkreten Zustand erklärt und den Weg dorthin anbietet. Das ist die häufigste
Hürde und in [docs/menueleisten-app.md](docs/menueleisten-app.md) im Detail
beschrieben — dort steht auch, was von der App gemessen ist und was nicht.

## Fahrplan

| Was | Stand |
|---|---|
| Konfiguration: laden, validieren, atomar schreiben, migrieren | fertig |
| Regel-Engine, Profil- und Zonenauflösung | fertig |
| Display-Identität und Setup-Fingerprint | fertig, am echten Schreibtisch geprüft |
| Fenstererkennung über `NSWorkspace` und `AXObserver` | fertig, gemessen: 124 ms bis zum Observer bei TextEdit, 2,2 s bei Outlook |
| Diagnose per Kommandozeile (`displays`, `windows`) | fertig |
| Signierung, damit der Grant Neubauten übersteht | fertig, `Scripts/bundle.sh` |
| Platzierung mit Retry-Schleife | **fertig und am echten Fenster gemessen**: TextEdit und Outlook je 1 Versuch, Abweichung 1,0 bzw. 0,0 pt |
| Menüleisten-App mit Autostart | gebaut, [#8](https://github.com/trsdn/OpenZonr/issues/8) — Zustand, Profilwahl, Pause, Autostart, letzte Platzierungen; Platzierung mit laufender App noch nicht nachgemessen, siehe [docs/menueleisten-app.md](docs/menueleisten-app.md) |
| Regeln bearbeiten ohne JSON | offen, [#9](https://github.com/trsdn/OpenZonr/issues/9) |
| Dropzones zum Hineinziehen | offen, [#10](https://github.com/trsdn/OpenZonr/issues/10) |

Die Reihenfolge war bewusst gewählt: erst die Signierung, damit die Platzierung
überhaupt messbar wird, und erst danach eine Oberfläche. Das hat sich gelohnt —
die Messung hat drei Fehler zutage gefördert, die alle ein leeres Protokoll
erzeugten statt einer Fehlermeldung, und die eine Oberfläche nur verdeckt hätte.
Sie sind in [docs/tracer-bullet.md](docs/tracer-bullet.md) beschrieben.

## Weiterlesen

- [docs/konzept.md](docs/konzept.md) — Architektur, Regelmodell, Monitor-Handling
- [docs/konfiguration.md](docs/konfiguration.md) — Feldreferenz und kommentierte
  Erklärung der Beispielkonfiguration
- [docs/menueleisten-app.md](docs/menueleisten-app.md) — die App: was sie kann,
  warum sie so gebaut ist, und was daran gemessen ist
- [docs/tracer-bullet.md](docs/tracer-bullet.md) — was der Durchstich abdeckt,
  was fehlt, und der Stand der Messung
- [docs/offene-fragen.md](docs/offene-fragen.md) — was noch nicht entschieden ist

## Lizenz

MIT — siehe [LICENSE](LICENSE).
