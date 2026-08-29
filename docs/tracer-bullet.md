# Tracer Bullet — der Durchstich

Der kleinste vollständige Weg vom App-Start bis zum platzierten Fenster, als
Kommandozeilenwerkzeug `openzonr`. Kein UI, kein Regel-Editor, keine
Menüleisten-App — nur der Durchstich und die Diagnosewerkzeuge, die man braucht,
um ihn zu benutzen.

Der Zweck ist nicht Bequemlichkeit, sondern Beweisführung: **Lässt sich ein neu
geöffnetes Fenster zuverlässig in eine definierte Zone platzieren, auch wenn die
App sich nach dem Öffnen selbst noch einmal skaliert?**

Die Antwort ist gemessen und lautet ja. Die Zahlen stehen unter
[Verifiziert: die Platzierung](#verifiziert-die-platzierung); den Weg dorthin
versperrte lange ein Berechtigungsproblem, dessen Auflösung im selben Abschnitt
beschrieben ist.

---

## Was der Durchstich abdeckt

Die Kette, die `openzonr watch` durchläuft:

1. Konfiguration laden, migrieren und validieren
   (`ConfigurationStore`, Standardpfad
   `~/Library/Application Support/OpenZonr/config.json`, überschreibbar per
   `--config` oder `OPENZONR_CONFIG`)
2. Angeschlossene Displays lesen und zum `SetupFingerprint` verdichten,
   **ohne** die unter `ignoredDisplays` eingetragenen Software-Displays
3. Aktives Profil bestimmen. Passt keines, bricht `watch` mit einer
   ausführlichen Meldung ab, statt still das nächstbeste zu nehmen
4. `NSWorkspace.didLaunchApplicationNotification` beobachten und pro relevanter
   App einen `AXObserver` auf `kAXWindowCreatedNotification` hängen — auch für
   Apps, die beim Start schon laufen
5. Neues Fenster vorfiltern: Fensterebene, Subrolle, Mindestgröße,
   `onlyFirstWindowAfterLaunch`
6. Regeln nach Priorität auswerten, erste passende gewinnt
7. Rolle über das aktive Profil zu Display und Zone auflösen, Fallback beachten
8. `RelativeRect` gegen den `visibleFrame` des Zieldisplays in AppKit-Koordinaten
   umrechnen und anschließend in AX-Koordinaten spiegeln
9. Über `kAXPositionAttribute` und `kAXSizeAttribute` setzen, den erreichten
   Frame zurücklesen, mit der Toleranz aus `RetryPolicy` vergleichen und
   gegebenenfalls erneut versuchen
10. Jeden Versuch protokollieren: Soll-Frame, Ist-Frame, Abweichung,
    Versuchsnummer, Dauer

Dazu die beiden Diagnosebefehle `openzonr displays` und `openzonr windows`, ohne
die Schritt 1 bis 3 reine Ratearbeit wären.

## Was bewusst noch fehlt

| Fehlt | Warum |
|---|---|
| `mode: "suggest"` | Braucht ein Overlay, das den Vorschlag anzeigt. `watch` protokolliert die Regel und den Ziel-Frame ausführlich, platziert aber nichts. |
| Regel-Editor, Zonen-Editor | Nicht Teil des Durchstichs. Die Menüleisten-App gibt es inzwischen — [`menueleisten-app.md`](menueleisten-app.md). |
| Reaktion auf Display-Änderungen zur Laufzeit | Teilweise gelöst: `WatchEngine` bestimmt das Profil bei `NSApplication.didChangeScreenParametersNotification` neu. Nicht gemessen. |
| Dauerhafte Überwachung platzierter Fenster | Bewusst nicht: nach einer erfolgreichen Platzierung gehört das Fenster dem Nutzer. |
| Notarisierung | Für den eigenen Rechner nicht nötig. Die Signierung ist es sehr wohl — siehe „Der Blocker und seine Auflösung". |

---

## Verifikationsstand

### Verifiziert auf echter Hardware

Gemessen auf dem Schreibtisch des Nutzers: vier Displays, davon zwei physisch
(Samsung C49RG9x 5120×1440 als Hauptmonitor, Samsung U28E590 1920×1080 darüber
rechts) und zwei virtuell („AAA", „Teleprompter Source").

```
· Konfiguration geladen: /tmp/ozconf/config.json
· 2 Displays, 1 Profile, 3 aktive Regeln
· Angeschlossene Displays: 4, davon 2 im Fingerprint
    C49RG9x — fallback vendor=19501 model=3996 5120×1440 port=1
    U28E590 — edid vendor=19501 model=3149 serial=810375238
    AAA — fallback vendor=21252 model=0 1920×1080 port=2  [ignoriert]
    Teleprompter Source — edid vendor=21581 model=1 serial=1  [ignoriert]
✓ Aktives Profil: Schreibtisch (desk)
    Beobachte com.apple.Terminal
    Beobachte com.microsoft.Outlook
· Beobachte 2 laufende Apps plus alle neu gestarteten.
· Warte auf neue Fenster. Beenden mit Strg-C.
· App gestartet: com.apple.TextEdit (pid 2608)
    Beobachte com.apple.TextEdit
! Neues Fenster von com.apple.TextEdit ohne lesbaren Frame.
```

Damit sind belegt:

- **Displayerkennung und Identitätsbildung.** Der Hauptmonitor meldet
  Seriennummer 0 und läuft über den Fallback-Pfad; der Nebenmonitor über EDID.
- **Der Fingerprint-Fix trägt.** Vier angeschlossene Displays, zwei im
  Fingerprint. Das Auftauchen von OBS oder des Teleprompters verschiebt das
  Profil nicht mehr.
- **Die Profilwahl.** „Schreibtisch" wurde über den reduzierten Fingerprint
  eindeutig bestimmt.
- **Die Beobachtungskette.** Nach `didLaunchApplicationNotification` hing der
  `AXObserver` 37 ms später an der neuen App, und
  `kAXWindowCreatedNotification` wurde weitere 310 ms danach zugestellt.

  Diese erste Messung verleitete zu dem Schluss, das Zeitfenster sei „klein,
  aber ausreichend". Das war zu optimistisch verallgemeinert: 37 ms waren der
  günstigste beobachtete Fall. Spätere Messungen ergaben 124 ms für TextEdit und
  2,2 s für Outlook — und in dieser Lücke öffnen Apps ihr erstes Fenster. Siehe
  Fehler 2 weiter unten.

### Der Blocker und seine Auflösung: Signierung

Lange sah es so aus, als sei der letzte Schritt nicht messbar. Der Befund war
eindeutig und reproduzierbar:

```
AXIsProcessTrusted()                                        → true
AXUIElementCopyAttributeValue(app, kAXWindowsAttribute)     → .success
  Safari      n=1   Rolle des „Fensters": AXApplication
  Outlook     n=1   Rolle des „Fensters": AXApplication
  … 21 Apps, keine einzige liefert ein Element mit Rolle AXWindow
AXPosition / AXSize auf diesen Elementen                    → -25205
```

`-25205` ist `kAXErrorAttributeUnsupported`. Jede App antwortete auf `AXWindows`
mit einem Stellvertreter, der die Rolle `AXApplication` trug und weder Position
noch Größe hatte. Ein separat kompiliertes Sondenprogramm, das nichts aus diesem
Repository verwendet, bekam exakt dieselben Stubs — die Ursache lag also nicht
im Code.

**Die Erklärung war fast richtig und die Schlussfolgerung zu schnell.** Vermutet
wurde, die Berechtigung hänge am *verantwortlichen* Prozess und sei deshalb
nicht erreichbar. Der ausschlaggebende Hebel ist die **Code-Signatur**: eine
unsignierte Binärdatei bekommt bei jedem Neubau eine andere Prüfsumme, und TCC
erkennt sie nicht wieder — der Haken in den Systemeinstellungen bleibt gesetzt
und meint ein anderes Programm. Dass der verantwortliche Prozess ebenfalls
mitspielt, zeigt der Nachtrag weiter unten.

Die Auflösung ist ein signiertes App-Bundle. Die Designated Requirement einer
Developer-ID-Signatur bindet an Identifier und Team, nicht an die Prüfsumme:

```
designated => identifier "com.trsdn.openzonr" and anchor apple generic
  and certificate 1[field.1.2.840.113635.100.6.2.6]
  and certificate leaf[field.1.2.840.113635.100.6.1.13]
  and certificate leaf[subject.OU] = G69Z5BNY97
```

Damit überlebt die Freigabe jeden Neubau. `Scripts/bundle.sh` baut, packt und
signiert in einem Schritt. Ein Ad-hoc-Zertifikat genügt nicht, es hat keine
solche Kette.

Nach der Signierung liefert derselbe Aufruf 19 echte `AXWindow` mit lesbarem
Frame. Ein neuer manueller Grant war nicht nötig.

**Nachtrag — eine Behauptung dieses Dokuments war zu weit gefasst.** Hier stand,
die Freigabe überlebe „sogar einen Umzug des Bundles an einen anderen Pfad, was
gegengeprüft wurde". Eine spätere, sorgfältigere Gegenprobe widerlegt das:

```
frischer Klon → Scripts/bundle.sh → identische Designated Requirement
  Start aus der Shell        : "Zugriff degradiert"
  Start über LaunchServices  : "Kein Zugriff — nicht vertraut"
```

Der zweite Befund ist der aussagekräftige. Aus der Shell gestartet erbt der
Prozess das Vertrauen des Terminals, weshalb `AXIsProcessTrusted()` weiterhin
`true` meldet — die Fensterzugriffe erben es nicht. Über LaunchServices ist die
App für sich selbst verantwortlich, und dort zeigt sich die Wahrheit: dieses
Bundle ist nicht freigegeben. **Die Freigabe gilt dem Programm an seinem Platz,
nicht dem Identifier allein.** Die ursprüngliche Vermutung über den
verantwortlichen Prozess war damit nicht falsch, sondern unvollständig; beide
Mechanismen wirken.

Praktische Folge, umgesetzt in `Scripts/bundle.sh`: das Bundle landet
standardmäßig unter `~/Applications/OpenZonr.app` statt in `.build`. Dort
überlebt die einmalige Freigabe `swift package clean`, einen zweiten Klon und
jeden Neubau. In `.build` wäre sie bei der ersten Aufräumaktion verloren.

**Nachtrag zum Nachtrag, 28.08.2026:** Dieser Befund ist inzwischen in einem
Befehl reproduzierbar. `openzonr selftest` meldet neben Signatur und
Fensterzugriff auch den *Startweg* — und beantwortet damit die Frage, die den
Unterschied ausmacht. Zwei Läufe derselben Binärdatei aus
`~/Applications/OpenZonr.app`, dieselbe Signatur, dieselbe Sekunde:

```
# open -n -a … --args selftest --out /tmp/openzonr.txt
  Start:                  über LaunchServices (Elternprozess launchd)
  AXIsProcessTrusted():   false
  probeWindowAccess():    notTrusted — keine Freigabe für dieses Bundle

# …/Contents/MacOS/OpenZonr selftest
  Start:                  aus einer Shell — erbt fremdes Vertrauen
  AXIsProcessTrusted():   true
  probeWindowAccess():    degraded — Vertrauen gemeldet, aber nur Stellvertreter
```

`--out` ist dabei kein Komfort, sondern Notwendigkeit: LaunchServices verwirft die
Standardausgabe, und ohne Datei bliebe genau der maßgebliche Fall unbeobachtbar.

Bemerkenswert und für die spätere Fehlersuche wichtig: **Benachrichtigungen
funktionieren auch im degradierten Zustand.** `AXObserverAddNotification`
gelingt und `kAXWindowCreatedNotification` wird zugestellt — nur die Attribute
des gemeldeten Elements sind leer. Ein Werkzeug, das sich auf
`AXIsProcessTrusted()` verlässt, täte in genau dieser Lage stumm gar nichts.
`openzonr` prüft deshalb zusätzlich, ob irgendeine App ein Element mit der Rolle
`AXWindow` **und** lesbarem Frame liefert, und verweigert `watch` andernfalls
mit Begründung.

### Verifiziert: die Platzierung

Gemessen am 28.08.2026 auf dem oben beschriebenen Vier-Display-Aufbau, mit
beendetem Magnet.

| Fall | Zone | Soll | Ist | Abweichung | Versuche | Dauer |
|---|---|---|---|---|---|---|
| TextEdit, Kaltstart | `c49rg9x/right-quarter` | `3840,31 1280x1344` | `3840,31 1280x1343` | 1,0 pt | **1** | 122 ms |
| Outlook, laufend | `c49rg9x/center-half` | `1280,31 2560x1344` | `1280,31 2560x1344` | 0,0 pt | **1** | 236 ms |

Beide Male unabhängig gegengeprüft mit `openzonr windows --bundle …`.

**Damit ist die Frage „reichen drei Versuche über 500 ms?" beantwortet: ja, mit
großem Abstand.** Beide gemessenen Apps fügen sich beim ersten Schreiben. Die
eine Abweichung von 1,0 pt bei TextEdit liegt weit innerhalb der Toleranz von
4 pt und stammt aus der Höhenrundung, nicht aus einem Rückschlag der App.

Die Retry-Schleife bleibt trotzdem nötig — sie ist gegen Apps gerichtet, die
sich wehren, und deren Verhalten ist mit einem Fake-Fenster abgedeckt
(`Tests/OpenZonrCoreTests/RetryingWindowPlacerTests.swift`).

> **Nachgetragen am 29.08.2026 — der letzte Satz dieses Abschnitts war falsch.**
> Er lautete: „Was die Messung zeigt, ist, dass sie im Normalfall nicht in
> Anspruch genommen wird." Das galt für zwei Fälle, in denen das Fenster kaum
> etwas zurücklegen musste. Sobald ein echtes Fenster über den Bildschirm zu
> ziehen ist, wird die Schleife sehr wohl in Anspruch genommen — siehe
> [„Verifiziert: die Platzierung bei laufender App"](#verifiziert-die-platzierung-bei-laufender-app).
> Der Grund, warum sie damals nicht auffiel, ist derselbe, der die Outlook-Zeile
> oben angreifbar macht: Outlook stand bereits an der Soll-Position.

### Verifiziert: die Platzierung bei laufender App

Gemessen am 29.08.2026, `main` auf `28d84e7`. Der Unterschied zur Tabelle oben
ist nicht die Logik, sondern der **Startweg**: nicht `openzonr watch` aus einer
Shell, sondern das signierte Bundle unter `~/Applications/OpenZonr.app`, über
LaunchServices gestartet, mit der von Hand erteilten Bedienungshilfen-Freigabe.
Das war die Lücke, die [`menueleisten-app.md`](menueleisten-app.md) offen ließ.

Vorbedingungen, jede einzeln geprüft statt angenommen:

```
selftest über LaunchServices (Elternprozess launchd)
  probeWindowAccess():  granted
Gegenprobe an fremder App: Safari → AXWindow / AXStandardWindow, Frame 1820,74 1202x1108
Magnet:                   läuft nicht (pgrep, nicht vermutet)
Displays:                 4 aktiv, beide Fingerprint-Displays vorhanden
Profil:                   „Schreibtisch" (messung) greift
```

| Fall | Zone | Ist **mit** OpenZonr | Ist **ohne** OpenZonr | Aussagekraft |
|---|---|---|---|---|
| TextEdit, Kaltstart | `c49rg9x/right-quarter` | `3840,31 1280x1343` | `1920,32 1280x1343` | **beweisend** — 1920 pt Versatz, gleiche Größe |
| Outlook, Kaltstart | `c49rg9x/center-half` | `1280,31 2560x1344` | `1280,31 2560x1344` | **wertlos** — siehe unten |
| Outlook gegen die eigene Erinnerung | `c49rg9x/left-quarter` | `0,31 1280x1344` | (erinnert `1280,…`) | **beweisend** — siehe unten |

**Die mittlere Zeile steht absichtlich in dieser Tabelle.** Outlook stellt die
Position seines Fensters selbst wieder her. Es landet also auch dann in
`center-half`, wenn OpenZonr gar nicht läuft — die Messung gelingt ohne die
Sache, die sie belegen soll, und belegt damit nichts. Sie war der erste Versuch
und wäre als Erfolg durchgegangen.

Entscheidbar wird der Fall erst, wenn beide Antworten **auseinanderfallen**:
eine Kopie der Konfiguration (`watch --config`, nichts am Original verändert)
schickt die Rolle `mail` nach `left-quarter`. Outlook erinnert `x=1280`, die
Regel verlangt `x=0`. Wörtlich aus dem Protokoll:

```
▸ Neues Fenster: com.microsoft.Outlook  1280,31 2560x1344  subrole=AXUnknown
  ignoriert — Subrole AXUnknown ist nicht freigegeben.
▸ Neues Fenster: com.microsoft.Outlook  1280,31 2560x1344  subrole=AXStandardWindow
✓ Regel "outlook" → Rolle "mail" → c49rg9x/left-quarter
  Soll-Frame 0,65 1280x1344 (AppKit) → 0,31 1280x1344 (AX)
  Versuch 1: Soll 0,31 1280x1344 | Ist -0,31 1288x1344 | Abweichung 8.0 pt | Abweichung zu groß | 121 ms
  Versuch 2: Soll 0,31 1280x1344 | Ist -0,31 1280x1344 | Abweichung 0.0 pt | innerhalb der Toleranz | 218 ms
✓ Platziert nach 2 Versuchen.
```

Drei Dinge, die diese acht Zeilen belegen und die vorherige Messung nicht konnte:

1. **Die App gewinnt gegen die Positionserinnerung der Ziel-App.** Genau das war
   der Anlass des Projekts.
2. **Die Retry-Schleife ist tragend, nicht Zierde.** Outlook fügte sich beim
   ersten Schreiben *nicht*: 1288 statt 1280 pt breit, 8 pt über der Toleranz von
   4 pt. Ohne den zweiten Versuch wäre das Fenster falsch stehengeblieben — und
   die Abweichung wäre klein genug gewesen, dass niemand sie als Fehler erkannt
   hätte. Die Aussage weiter oben, die Schleife werde „im Normalfall nicht in
   Anspruch genommen", ist damit widerlegt.
3. **Der Subrole-Filter arbeitet.** Outlook meldet zwei Fenster mit identischem
   Frame; eines trägt `AXUnknown`. Ohne den Filter wäre die Platzierung auf ein
   Phantom gegangen.

**Ein Methodenfehler, der beinahe eine zweite wertlose Messung erzeugt hätte:**
`pgrep -x Outlook` findet Outlook **nicht** — der Prozess heißt
`Microsoft Outlook`. Ein Test, der daraufhin „nicht laufend" annimmt und
anschließend einen Frame misst, misst ein Fenster, das seit Stunden dort steht.
Aufgefallen ist es nur an `ps -p <pid> -o lstart`. Wer eine Platzierung als
frisch ausgibt, muss die **Startzeit des Prozesses** belegen, nicht seine
Abwesenheit vermuten. Aus demselben Grund taugt `ps aux | grep -i openzonr`
nicht zur Prüfung, ob die App läuft: es trifft jeden Prozess, der den Pfad im
Aufruf trägt. Richtig ist `pgrep -lf 'OpenZonr.app/Contents/MacOS'`.

Ungemessen bleibt: der Autostart über `SMAppService` nach einer echten
Neuanmeldung, und alles, was eine Hand an der Maus braucht — Overlay,
echter Zug, Magnet im Konflikt, Angebotspanel (siehe
[`dropzones.md`](dropzones.md)).

### Was die Messung an Fehlern zutage gefördert hat

Drei Fehler, die alle einzeln unsichtbar waren und zusammen dazu führten, dass
kein einziges Fenster platziert wurde. Keiner davon wäre ohne echte Hardware
aufgefallen; alle drei erzeugten ein leeres Protokoll statt einer Fehlermeldung.

**1. Die Anwendung wurde schwach gehalten.** Die Retry-Schleife, die den
`AXObserver` anhängt, hielt `NSRunningApplication` schwach, und niemand sonst
hielt sie. Vor dem ersten Wiederholungsversuch nach 150 ms war die Instanz
freigegeben, das `guard` schlug fehl, und die Schleife kehrte zurück, ohne
Erfolg *oder* Fehler zu melden. Im Protokoll stand „App gestartet" und danach
nichts — ununterscheidbar davon, dass die App kein Fenster geöffnet hätte.

**2. Das Fenster war schneller als der Observer.** Das Anhängen dauert Zeit:
124 ms bei TextEdit, 2,2 s bei Outlook. Apps öffnen ihr erstes Fenster genau in
dieser Lücke. Da die API nur Fenster meldet, die *nach* der Registrierung
entstehen, war dieses Fenster endgültig verloren — ausgerechnet das eine, für
das die Regel geschrieben wurde. Bereits vorhandene Fenster werden jetzt einmal
nachgeholt.

**3. Der Frame war noch nicht lesbar.** Ein nachgeholtes Fenster kann zu einer
App gehören, die noch startet. Outlook lieferte sieben Sekunden lang gar nichts,
wobei jeder einzelne Lesezugriff drei Sekunden blockierte. Beim ersten leeren
Frame aufzugeben verwarf genau das gesuchte Fenster. Der Frame wird jetzt bis zu
sechsmal erneut gelesen.

Ein vierter Fehler betraf die Regelauswahl statt der Mechanik: Outlook öffnet
ein `AXUnknown`-Fenster derselben Größe **vor** seinem echten. Der Zähler für
„erstes Fenster nach dem Start" lief vor dem Strukturfilter und zählte dieses
Attrappenfenster mit, wodurch das Postfach zum *zweiten* Fenster wurde und die
Regel nicht mehr griff. Der Zähler läuft jetzt hinter dem Filter.

### Was die Messung über Outlook gelehrt hat

Outlook startet sich nach einem `quit` selbsttätig neu. Es gilt dadurch beim
nächsten Start von `watch` als bereits laufende App und nie als frisch
gestartete. Für den Anwendungsfall „Outlook soll *immer* in seiner Zone liegen"
ist deshalb `onlyFirstWindowAfterLaunch: false` die richtige Einstellung — die
Vorgabe `true` ist für Apps gedacht, die beim Arbeiten weitere Fenster öffnen.

---

## Bekannte Interferenzquelle: konkurrierende Fenstermanager

Auf dem Messrechner laufen parallel:

| Bundle ID | Werkzeug |
|---|---|
| `com.crowdcafe.windowmagnet` | Magnet |
| `com.openswitchr.app` | eigenes Overlay des Nutzers, Ebene 3 |

**Magnet platziert Fenster über dieselbe Accessibility-API.** Es kann eine
Platzierung von OpenZonr überschreiben, und OpenZonr kann eine von Magnet
überschreiben. Für die Auswertung des Retry-Protokolls heißt das: eine Abweichung
zwischen Soll- und Ist-Frame ist nicht automatisch das Selbst-Resize der App —
sie kann genauso gut von Magnet stammen. Wer das nicht weiß, misst Magnet und
hält das Ergebnis für Outlook.

**Für eine saubere Messung Magnet vorübergehend beenden.** Wenn das nicht in
Frage kommt, mindestens im Protokoll vermerken, dass es lief.

**Mit den Dropzones (#10) ist Magnet vom Messproblem zum Entwurfsproblem
geworden**, weil beide Programme beim Ziehen ein Overlay einblenden. Wie sich
OpenZonr dann verhält — erkennen und einmal warnen, nicht um die Vorherrschaft
kämpfen — steht in [dropzones.md](dropzones.md).

---

## Die Koordinatenfalle, mit echten Zahlen

Zwei Koordinatensysteme treffen aufeinander:

| | Ursprung | y wächst |
|---|---|---|
| AppKit (`NSScreen.frame`, `visibleFrame`, `ZoneResolver`) | unten links des Hauptdisplays | nach oben |
| Accessibility (`kAXPositionAttribute`, `CGDisplayBounds`, `CGWindowListCopyWindowInfo`) | oben links des Hauptdisplays | nach unten |

Umrechnung: `y' = primaryTopY - (y + height)`, selbstinvers.

Auf dem gemessenen Schreibtisch:

| Display | AppKit `frame` | AX-Bounds (gemessen) |
|---|---|---|
| C49RG9x (Haupt) | `0, 0, 5120×1440` | `0, 0, 5120×1440` |
| U28E590 | `2833, 1440, 1920×1080` | `2833, -1080, 1920×1080` |
| AAA | `-1007, 1440, 1920×1080` | `-1007, -1080, 1920×1080` |
| Teleprompter Source | `913, 1440, 1920×1080` | `913, -1080, 1920×1080` |

Diese Anordnung ist der eigentliche Testfall: der Hauptmonitor ist 1440 hoch, die
darüber liegenden 1080. Bei gleich hohen Displays landet ein Fenster trotz
falscher Umrechnung noch auf dem richtigen Bildschirm und der Fehler überlebt.
Hier nicht — `ScreenArrangementTests` rechnet genau diese Werte nach.

Ebenso wichtig: **der `visibleFrame` wird pro Display gelesen.** Nur der
Hauptmonitor meldet einen reduzierten (1344 statt 1440, also 96 Punkte für
Menüleiste und Dock); die drei anderen melden `visibleFrame == frame`, obwohl auf
jedem eine Menüleiste sichtbar ist. Ein globaler Menüleisten-Abzug wäre auf drei
von vier Displays falsch.

---

## Nachvollziehen

```bash
Scripts/bundle.sh                       # baut, packt und signiert
```

Das Bundle einmalig in Systemeinstellungen → Datenschutz & Sicherheit →
Bedienungshilfen eintragen. Bei einem vorhandenen Eintrag aus einem unsignierten
Lauf: entfernen und neu hinzufügen — den Haken nur neu zu setzen genügt nicht.

```bash
APP=.build/OpenZonr.app/Contents/MacOS/OpenZonr
"$APP" windows --bundle com.apple.Safari       # muss AXStandardWindow ≠ 0x0 zeigen
"$APP" displays --config-fragment              # Displays für die Konfiguration
"$APP" watch --config <pfad>
```

Vor Messungen konkurrierende Fenstermanager beenden (siehe oben). Danach die
Ziel-App beenden und neu starten; die Versuchszeilen stehen im Protokoll.

---

## Weiterlesen

- [README.md](../README.md) — Bauen, Berechtigung, die drei Unterbefehle
- [docs/konfiguration.md](konfiguration.md) — Feldreferenz, inklusive
  `ignoredDisplays` und der Warnung vor Titel-Regex
- [docs/offene-fragen.md](offene-fragen.md) — was der Durchstich beantwortet und
  was er neu aufgeworfen hat
