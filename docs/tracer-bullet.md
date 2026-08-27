# Tracer Bullet — der Durchstich

Der kleinste vollständige Weg vom App-Start bis zum platzierten Fenster, als
Kommandozeilenwerkzeug `openzonr`. Kein UI, kein Regel-Editor, keine
Menüleisten-App — nur der Durchstich und die Diagnosewerkzeuge, die man braucht,
um ihn zu benutzen.

Der Zweck ist nicht Bequemlichkeit, sondern Beweisführung: **Lässt sich ein neu
geöffnetes Fenster zuverlässig in eine definierte Zone platzieren, auch wenn die
App sich nach dem Öffnen selbst noch einmal skaliert?**

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
| `mode: "suggest"` | Braucht ein Overlay, das den Vorschlag anzeigt. `watch` protokolliert die Regel und den Ziel-Frame ausführlich, platziert aber nichts. || Menüleisten-App, Regel-Editor, Zonen-Editor | Nicht Teil des Durchstichs. |
| Reaktion auf Display-Änderungen zur Laufzeit | Die Anordnung wird bei jedem Fensterereignis neu gelesen, aber `CGDisplayRegisterReconfigurationCallback` wird nicht beobachtet und das Profil nicht neu bestimmt. |
| Dauerhafte Überwachung platzierter Fenster | Bewusst nicht: nach einer erfolgreichen Platzierung gehört das Fenster dem Nutzer. |
| Code-Signierung | Siehe „Was die Messung blockiert hat" — für den Accessibility-Grant ist genau das die entscheidende Lücke. |

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
  `kAXWindowCreatedNotification` wurde weitere 310 ms danach zugestellt. Das
  Zeitfenster zwischen App-Start und erstem Fenster ist also klein, aber
  ausreichend — der Observer war rechtzeitig da.

### Nicht verifiziert: die Platzierung selbst

Der letzte Schritt — schreiben, zurücklesen, wiederholen — konnte **nicht**
gemessen werden. Die letzte Zeile des Protokolls sagt warum: das Fenster wurde
gemeldet, aber sein Frame war nicht lesbar.

**Es fehlt nicht die Berechtigung, sondern ihre Wirkung.** Gemessen aus dem
Prozess, in dem `openzonr` läuft:

```
AXIsProcessTrusted()                                        → true
AXUIElementCopyAttributeValue(app, kAXWindowsAttribute)     → .success
  Safari      n=1   Rolle des „Fensters": AXApplication
  Terminal    n=0
  Outlook     n=1   Rolle des „Fensters": AXApplication
  … 21 Apps, keine einzige liefert ein Element mit Rolle AXWindow
AXPosition / AXSize auf diesen Elementen                    → nil
```

Jede App antwortet auf `AXWindows` mit einem Stellvertreter-Element, das die
Rolle `AXApplication` trägt und weder Position noch Größe hat. Das ist kein
Fehler im Werkzeug: ein zweites, unabhängig kompiliertes Probe-Programm im selben
Prozesskontext bekommt exakt dieselben Stubs. Die Berechtigung hängt am
startenden Programm und nicht an der unsignierten Binärdatei, weshalb
`AXIsProcessTrusted()` „true" meldet, der Lesezugriff aber leer bleibt.

Bemerkenswert und für die spätere Fehlersuche wichtig: **Benachrichtigungen
funktionieren in diesem Zustand trotzdem.** `AXObserverAddNotification` gelingt
und `kAXWindowCreatedNotification` wird zugestellt — nur die Attribute des
gemeldeten Elements sind leer. Ein Werkzeug, das sich auf
`AXIsProcessTrusted()` verlässt, würde in genau dieser Lage stumm gar nichts tun.
`openzonr` prüft deshalb zusätzlich, ob irgendeine App ein Element mit der Rolle
`AXWindow` liefert, und verweigert `watch` andernfalls mit Begründung.

### Was zur Verifikation noch aussteht

Ein manueller Schritt, der Rechte am Prozess selbst voraussetzt:

1. `swift build`
2. `.build/debug/openzonr` in Systemeinstellungen → Datenschutz & Sicherheit →
   Bedienungshilfen eintragen (bei einem vorhandenen Eintrag: entfernen und neu
   hinzufügen; der Haken allein genügt nach einem Rebuild oft nicht, weil die
   unsignierte Binärdatei nach jedem Build eine andere Prüfsumme hat)
3. Gegenprobe: `openzonr windows --bundle com.microsoft.Outlook` muss ein Fenster
   mit Subrolle `AXStandardWindow` und einer Größe ungleich `0x0` zeigen. Zeigt
   es `AXApplication` mit `0x0`, ist der Zugriff weiterhin degradiert.
4. Konkurrierende Fenstermanager beenden (siehe unten)
5. `openzonr watch --config <pfad>` starten, Outlook beenden und neu starten
6. Die Versuchszeilen aus dem Protokoll hier eintragen

**Bis dieser Schritt durchgeführt ist, gilt der Durchstich als gebaut und
teilweise gemessen, nicht als verifiziert.** Die Frage „reichen drei Versuche
über 500 ms?" ist damit weiterhin unbeantwortet.

Was in der Zwischenzeit belastbar ist: die Retry-Schleife selbst ist mit einem
Fake-Fenster getestet, das sich wie Outlook verhält und die ersten *n* Schreiben
rückgängig macht (`Tests/OpenZonrCoreTests/RetryingWindowPlacerTests.swift`).
Das beweist, dass die Schleife korrekt zählt, die Toleranz richtig anwendet und
die App als Ursache benennt, wenn sie sich nicht fügt — es beweist nicht, wie
oft echtes Outlook zurückschlägt.

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

## Weiterlesen

- [README.md](../README.md) — Bauen, Berechtigung, die drei Unterbefehle
- [docs/konfiguration.md](konfiguration.md) — Feldreferenz, inklusive
  `ignoredDisplays` und der Warnung vor Titel-Regex
- [docs/offene-fragen.md](offene-fragen.md) — was der Durchstich beantwortet und
  was er neu aufgeworfen hat
