# Die Menüleisten-App

Die Oberfläche zu [`openzonr watch`](../README.md#openzonr-watch--der-durchstich):
ein Symbol in der Menüleiste, das den Watcher beherbergt, statt ihn im
Vordergrund eines Terminals laufen zu lassen. Umgesetzt für
[#8](https://github.com/trsdn/OpenZonr/issues/8).

Dieses Dokument hält die Entscheidungen fest, die dabei zu treffen waren, und —
getrennt davon — was von der App tatsächlich gemessen ist und was nicht.

## Was sie kann

| | |
|---|---|
| **Zustand** | Das Symbol unterscheidet fünf Fälle: aktiv, pausiert, keine Berechtigung, keine Konfiguration, kein Profil passt. Jeder hat ein eigenes Symbol und eine Überschrift im Menü. |
| **Profil** | Das erkannte Profil steht im Menü; jedes konfigurierte Profil lässt sich von Hand wählen. |
| **Pause** | Platzierung anhalten und fortsetzen, ohne die App zu beenden. Der Watcher läuft weiter und protokolliert, bewegt aber nichts. |
| **Autostart** | Über `SMAppService.mainApp`. |
| **Berechtigung** | Ein eigenes Fenster, das den konkreten Zustand erklärt und die drei Wege dorthin anbietet. Siehe unten. |
| **Letzte Platzierungen** | Die letzten Entscheidungen als Liste, dazu der vollständige Protokollstrom. |

## Entscheidungen

### Ein SwiftPM-Executable, kein Xcode-Target

Das Issue ließ die Wahl offen. Es wurde ein `.executableTarget` mit `MenuBarExtra`
daraus, aus vier Gründen:

- `MenuBarExtra`, `@Observable` und `SMAppService` brauchen nichts, was ein
  SwiftPM-Executable nicht kann.
- Das signierte Bundle erzeugt `Scripts/bundle.sh` bereits — Xcode würde diesen
  Schritt nicht abnehmen, sondern ersetzen, und zwar durch einen, der sich nicht
  im Diff lesen lässt.
- `swift build` und `swift test` bleiben die ganze Wahrheit. Zwei Buildsysteme
  wären zwei Wahrheiten, von denen eine unbemerkt veraltet.
- Keine `.pbxproj`-Merge-Konflikte.

Die frühere Ankündigung im README, die App-Hülle komme als Xcode-Target, ist
damit revidiert. Zu revidieren wäre diese Entscheidung erst, wenn Entitlements
nötig werden, die ein Provisioning-Profil verlangen — davon braucht die App
heute keines.

### Eine Binärdatei für App und Kommandozeile

Im Bundle liegt genau ein Programm. Ohne Argumente startet es als Menüleisten-App,
mit einem bekannten Unterbefehl als Kommandozeilenwerkzeug:

```bash
~/Applications/OpenZonr.app/Contents/MacOS/OpenZonr windows --bundle com.apple.Safari
```

Das ist keine Spielerei, sondern folgt aus der Art, wie macOS die Berechtigung
vergibt: **Die Freigabe gilt einem Programm an seinem Pfad.** Zwei Binärdateien
im selben Bundle wären zwei Freigaben — und die Gegenprobe würde etwas anderes
messen als das, was tatsächlich platziert. So misst sie genau das Programm, das
auch die App ist.

Die Unterscheidung geschieht in `OpenZonrMenuBarApp.init()`, bevor irgendeine
Szene existiert, gegen eine **feste Liste** von Unterbefehlen. Nicht gegen „alles,
was kein Flag ist": LaunchServices übergibt eigene Argumente, und eines davon für
einen Unterbefehl zu halten hieße, dass das Menüleisten-Symbol nie erscheint —
ein Fehler ohne Fehlermeldung. Die Liste ist deshalb getestet.

`swift run openzonr` bleibt über ein eigenes, triviales Target erhalten; im Alltag
ist es das Werkzeug für den Entwicklungsrechner, nicht das ausgelieferte.

### Der Watcher wurde extrahiert, nicht neu geschrieben

Die Beobachtungs- und Platzierungslogik liegt jetzt in `WatchEngine`
(`Sources/OpenZonrMac/Watch/`), das sich CLI und App teilen. Drei Eigenschaften
dieser Logik sind auf echter Hardware gemessen und wurden wörtlich übernommen;
jede einzelne stand für einen Fehler, der ein *leeres Protokoll* erzeugte statt
einer Fehlermeldung ([`tracer-bullet.md`](tracer-bullet.md)):

1. **Die `NSRunningApplication` wird stark gehalten**, solange die Retry-Schleife
   für den Observer läuft. Sonst ist sie vor dem ersten Versuch nach 150 ms
   freigegeben.
2. **Bereits offene Fenster werden nachgeholt**, nachdem der Observer hängt. Das
   Anhängen dauert 124 ms (TextEdit) bis 2,2 s (Outlook), und die API meldet nur
   Fenster, die *danach* entstehen.
3. **Der Frame wird geduldig gelesen** — sechs Versuche im Abstand von einer
   Sekunde. Outlook antwortet beim Start rund sieben Sekunden nicht, und jeder
   Lesezugriff blockiert dabei drei.

Ein vierter, subtilerer Punkt ist ebenfalls erhalten: der Zähler der gesehenen
Fenster läuft *hinter* der Strukturprüfung, weil Outlook ein Attrappenfenster der
Rolle `AXUnknown` vor dem echten öffnet.

### Manuelles Profil gilt nur für diese Sitzung

`PinnedProfileResolver` schiebt eine Handauswahl vor die automatische Erkennung.
Persistiert wird sie nicht — sie ist eine Korrektur für den Schreibtisch, an dem
der Nutzer gerade sitzt, keine neue Regel. Eine Handauswahl, die einen Neustart
in ein anderes Setup überlebte, würde still auf dem falschen Bildschirm
platzieren; genau das soll der exakte Abgleich verhindern.

Fehlt das gewählte Profil in der Konfiguration, greift wieder die Erkennung. Auch
das ist getestet, denn die Konfiguration kann sich ändern, während die App läuft.

### Die Pause greift vor dem Fensterzähler

`isPaused` wird geprüft, sobald ein Fenster gemeldet wird — nicht erst dort, wo
der Frame geschrieben würde. Der Unterschied ist nicht kosmetisch.

Der Zähler pro Prozess ist es, der `onlyFirstWindowAfterLaunch` überhaupt
funktionieren lässt. Würde ein Fenster, das während einer Pause auftaucht,
mitgezählt, verbrauchte es den Platz „erstes Fenster nach dem Start" — und nach
dem Fortsetzen überspränge die Regel stillschweigend genau das Fenster, für das
sie geschrieben wurde. Wieder ein Fehler ohne Fehlermeldung, also die Sorte, die
dieses Projekt schon dreimal gekostet hat.

Pausiert heißt deshalb: beobachten und berichten, nicht halb entscheiden. Die
Zeile „pausiert" erscheint weiterhin in der Liste, nur ohne Regel und Ziel — die
wurden bewusst nicht ermittelt.

### Nicht jede Entscheidung wird zur Zeile

Im Menü landen nur Entscheidungen, die eine Regel erreicht haben. Jedes Fenster
jeder beobachteten App durchläuft den Filter; würden die Hunderte, die nie
Kandidat waren, mitgelistet, wäre die Handvoll echter Treffer nicht mehr zu
finden. Der vollständige Strom steht weiterhin im Protokollfenster.

## Der Weg zur Berechtigung

Das Issue verlangt hierfür ausdrücklich Sorgfalt statt eines Fehlertexts, und der
Grund dafür ist gemessen: **Über LaunchServices gestartet — also per Doppelklick
oder als Anmeldeobjekt — ist die App für ihre Berechtigung selbst verantwortlich.**
Aus einer Shell gestartet erbt der Prozess das Vertrauen des Terminals, und
`AXIsProcessTrusted()` meldet dann irreführend `true`, während die Fensterzugriffe
nichts erben. Die App prüft deshalb `Accessibility.probeWindowAccess()`, nicht
`AXIsProcessTrusted()`.

Konkret:

- Beim ersten Start ohne Berechtigung öffnet sich das Statusfenster **einmal** von
  selbst. Ein Symbol in der Menüleiste allein erklärt niemandem, was zu tun ist.
- Das Fenster unterscheidet die Fälle. „Nicht freigegeben" und „freigegeben, aber
  nur Stellvertreter" haben verschiedene Ursachen und verschiedene Abhilfen.
- Es zeigt die eigene Signatur an. Ohne Developer-ID ist die Freigabe nach dem
  nächsten Neubau wieder weg — das gehört gesagt, bevor jemand sucht.
- Es zeigt den eigenen Pfad und öffnet ihn im Finder, weil in die Liste der
  Bedienungshilfen genau dieses Bundle gehört.
- Es verlinkt direkt in den richtigen Bereich der Systemeinstellungen.

### `openzonr selftest`

```bash
open -n -a ~/Applications/OpenZonr.app --args selftest --out /tmp/openzonr.txt
```

Meldet Signatur, Startweg und den *tatsächlichen* Fensterzugriff. `--out` gibt es,
weil LaunchServices die Standardausgabe verwirft — und der über LaunchServices
gestartete Fall ist der maßgebliche. Derselbe Aufruf aus einer Shell misst etwas
anderes, und der Bericht sagt auch das:

```
Start:       aus einer Shell (Elternprozess PID 31134) — erbt fremdes Vertrauen
```

## Stand der Messung

Was am 28.08.2026 auf der Zielmaschine (macOS 26.6.2, Mac16,11) belegt ist:

| Behauptung | Stand |
|---|---|
| `swift build` und `swift test` sind grün | **gemessen** — 156 Tests in 17 Suites, headless |
| Das Bundle wird signiert und trägt die erwartete Designated Requirement | **gemessen** — `identifier "com.trsdn.openzonr" and … subject.OU = G69Z5BNY97` |
| Die App startet über LaunchServices und läuft ohne Dock-Symbol | **gemessen** — Prozess stabil, `lsappinfo` meldet `ApplicationType = UIElement` |
| Das Statusfenster öffnet sich beim Start ohne Berechtigung von selbst | **gemessen** — Fenster „OpenZonr — Status und Berechtigung", 505×462 pt |
| Die Kommandozeile funktioniert aus derselben Binärdatei | **gemessen** — `selftest` und `windows` liefern ihre Berichte |
| Der Unterschied zwischen Shell- und LaunchServices-Start | **gemessen** — siehe unten |
| **Ob TextEdit beim Start in seiner Zone landet, während die App läuft** | **nicht gemessen** — Begründung unten |

Der Startweg-Unterschied, wörtlich aus zwei Läufen derselben Binärdatei:

```
# open -n -a … --args selftest
  Start:                  über LaunchServices (Elternprozess launchd)
  AXIsProcessTrusted():   false
  probeWindowAccess():    notTrusted — keine Freigabe für dieses Bundle

# …/Contents/MacOS/OpenZonr selftest
  Start:                  aus einer Shell — erbt fremdes Vertrauen
  AXIsProcessTrusted():   true
  probeWindowAccess():    degraded — Vertrauen gemeldet, aber nur Stellvertreter
```

Das bestätigt den Nachtrag in [`tracer-bullet.md`](tracer-bullet.md) unabhängig
und macht ihn in einem Befehl reproduzierbar.

### Warum die Platzierung nicht nachgemessen wurde

Das neu gebaute Bundle unter `~/Applications/OpenZonr.app` ist in den
Bedienungshilfen **nicht freigegeben**. Ohne diese Freigabe sieht der Prozess
keine Fenster, und ohne Fenster ist keine Platzierung messbar.

Die Freigabe zu erteilen war nicht automatisierbar, und zwar aus einem Grund, der
selbst geprüft ist: macOS schirmt genau diese Oberflächen gegen Automatisierung
ab. Sowohl der Systemdialog „Zugriff auf Bedienungshilfen" als auch die
Systemeinstellungen liefern auf dem Bedienungshilfen-Bereich **keinen
Accessibility-Baum und ein schwarzes Bildschirmfoto**. Das ist die beabsichtigte
Härtung — ein Werkzeug, das sich seine eigene Fensterberechtigung erteilen könnte,
wäre der Sinn der Sperre.

Es fehlt also ein Handgriff, kein Code:

1. Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen
2. `~/Applications/OpenZonr.app` hinzufügen und aktivieren
   (ein vorhandener Eintrag aus einem unsignierten Lauf: entfernen und neu
   hinzufügen — den Haken nur neu zu setzen genügt nicht)
3. Gegenprobe, die ohne weitere Annahmen auskommt:

```bash
open -n -a ~/Applications/OpenZonr.app --args selftest --out /tmp/openzonr.txt
cat /tmp/openzonr.txt      # muss "granted" melden
```

Danach ist die eigentliche Messung ein Neustart von TextEdit bei laufender App.
**Vorher Magnet beenden** (`com.crowdcafe.windowmagnet`) — es arbeitet auf
derselben API und verfälscht das Ergebnis.

Die Platzierungslogik selbst ist gegenüber der gemessenen Fassung unverändert:
`WatchEngine` ist aus `WatchCommand` extrahiert, nicht neu geschrieben, und das
CLI ruft heute denselben Code auf, mit dem die Messung in
[`tracer-bullet.md`](tracer-bullet.md) entstanden ist. Das ist ein Argument, keine
Messung — und wird hier bewusst nicht als eine ausgegeben.
