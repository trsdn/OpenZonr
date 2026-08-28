# Offene Fragen

Entscheidungen, die für den Konzeptstand bewusst offen geblieben sind, sowie
Abweichungen vom ursprünglich diskutierten Modell. Jede Frage nennt die Optionen
und, wo vorhanden, eine Tendenz.

Fragen, die die Praxis inzwischen beantwortet hat, tragen den Vermerk
*entschieden* oder *geklärt* in der Überschrift. Sie bleiben stehen statt gelöscht
zu werden — die widerlegten Annahmen sind aufschlussreicher als die richtigen.

---

## 1. Spaces und Mission Control

**Frage:** Gehören Zonen zu einem Space? Was passiert, wenn die Zielzone auf
einem anderen Space liegt als der, den der Nutzer gerade sieht?

Die Accessibility-API kennt Spaces nicht. Es gibt keine offizielle Möglichkeit,
ein Fenster auf einen bestimmten Space zu legen; die privaten
`CGSSpace`-Funktionen sind undokumentiert und brechen regelmäßig mit
macOS-Updates.

Optionen:

- **Spaces ignorieren.** Fenster werden im aktuellen Space platziert. Einfach,
  ehrlich, aber „Outlook immer im zweiten Space" ist damit nicht abbildbar.
- **Space als Teil der Rollenbindung**, umgesetzt über private APIs. Mächtig,
  aber fragil und ein dauerhaftes Wartungsrisiko.
- **Space-Wechsel simulieren** über Tastaturkurzbefehle vor dem Platzieren.
  Sichtbar ruckelig und schwer robust zu bekommen.

*Tendenz:* Spaces zunächst ignorieren und erst nach Stufe 6 der Roadmap neu
bewerten.

**Direkt betroffen:** das ursprünglich diskutierte Profil „Unterwegs" sah
„Kommunikation = Builtin, Vollbild Space 2" vor. Weil Spaces ungelöst sind, bindet
das Beispielprofil `mobile` die Rolle stattdessen auf die rechte Hälfte des
integrierten Displays. Das ist eine bewusste Abweichung, keine Auslassung.

---

## 2. Mehrere Fenster derselben App

**Frage:** Was passiert beim zweiten, dritten, zehnten Fenster derselben App?

Die Voreinstellung `onlyFirstWindowAfterLaunch` löst den häufigsten Fall — sie
verhindert, dass Dialoge platziert werden. Sie beantwortet aber nicht, was mit
einem legitimen zweiten Hauptfenster geschehen soll, etwa einem zweiten
VS-Code-Fenster für ein anderes Projekt.

Optionen:

- **Nur das erste Fenster platzieren**, alle weiteren ignorieren. Heutiger Stand.
- **Alle passenden Fenster platzieren**, Konflikte über `occupiedZone` regeln.
- **Sekundärregel:** das zweite Fenster geht in eine andere Rolle (z. B.
  „Editor" → „Referenz"). Ausdrucksstark, aber eine deutliche Erweiterung des
  Regelmodells.

Verwandt: soll `share` automatisch greifen, wenn mehrere Fenster in dieselbe Zone
wollen — also eine Zone dynamisch aufteilen statt stapeln?

---

## 3. Vollbild-Apps

**Frage:** Unterdrückt eine Vollbild-App auf dem Zieldisplay die Regel?

Ein Fenster in eine Zone eines Displays zu legen, das gerade von einer
Vollbild-App belegt ist, ist meist nicht das, was der Nutzer will — das neue
Fenster verschwindet hinter dem Vollbildfenster oder reißt aus dem Vollbildmodus
heraus.

Optionen:

- Regel überspringen, Fenster bleibt wo es ist.
- Trotzdem platzieren; das Fenster liegt dann auf dem darunterliegenden Space.
- Auf `suggest` herabstufen und den Nutzer entscheiden lassen.

Hängt eng an Frage 1: das Erkennen von Vollbildzuständen ist ebenfalls
Space-Territorium.

---

## 4. Nicht-kooperative Apps

**Frage:** Wie weit wird nachgesetzt, wenn eine App die AX-Positionierung
ignoriert oder überschreibt?

Java-Toolkits (AWT/Swing) und einzelne Electron-Builds klemmen den gesetzten
Frame auf ihre eigene Vorstellung eines gültigen Fensters. Der Retry-Loop
erkennt das über `PlacementOutcome.rejectedByApplication`, aber danach?

Optionen:

- **Aufgeben und melden.** Der Nutzer sieht, welche App sich weigert. Heutiger
  Stand.
- **Aggressiver Retry** mit mehr Versuchen über längere Zeit. Riskiert sichtbar
  springende Fenster.
- **Dauerhafte Überwachung** des Fensters über `kAXWindowMovedNotification`.
  Widerspricht dem Nicht-Ziel „keine kontinuierliche Überwachung" und läuft dem
  Prinzip zuwider, dass das Fenster nach dem Platzieren dem Nutzer gehört.
- **Bekannte Problem-Apps** in einer mitgelieferten Liste führen und dort direkt
  auf `suggest` gehen.

---

## 5. Fingerprint-Matching bei unbekannten Setups

**Frage:** Soll es neben dem exakten Vergleich einen Teilmengen-Modus geben?

Heute wird das Set der Display-Identitäten exakt verglichen. Steckt im Büro
zusätzlich ein Beamer, passt kein Profil und der Nutzer wird gefragt.

Optionen:

- **Exakt bleiben** und fragen. Vorhersagbar, aber lästig bei Konferenzräumen und
  wechselnden Beamern.
- **Beste Teilmenge**: das Profil mit der größten Überschneidung gewinnt, das
  unbekannte Display bleibt ungenutzt. Bequem, aber es platziert Fenster ohne
  ausdrückliche Zustimmung.
- **Displays als „ignorieren" markierbar**, sodass sie nicht in den Fingerprint
  eingehen. Kompromiss, erfordert aber eine einmalige Nutzerentscheidung je
  Display.

---

## 6. Speicherort der Konfiguration und Migration — *entschieden*

**Frage:** Wohin gehört die Datei?

**Entscheidung:** Standardablage in `~/Library/Application Support/OpenZonr/config.json`,
mit einem Override über die Umgebungsvariable `OPENZONR_CONFIG` und, davor, über
einen expliziten Pfad, den der Aufrufer übergibt.

Damit sind beide Nutzergruppen bedient: wer die Datei nie anfasst, findet sie
dort, wo Apple sie erwartet, und wer seine Dotfiles versioniert, legt sie ins
eigene Repository und setzt eine Variable. Der Preis ist eine einzige
Umgebungsvariable — deutlich weniger als der Streit, den ein einzelner erzwungener
Ort dauerhaft erzeugt. Umgesetzt in `ConfigurationLocation`; die Auflösung liest
weder Umgebung noch Home-Verzeichnis selbst, beides wird übergeben.

**Migration:** automatisch beim Laden, ohne Rückfrage, aber nie stillschweigend
zerstörend. Eine ältere `version` wird schrittweise auf
`Configuration.currentVersion` gehoben; vor einer *schreibenden* Migration wird
die Ursprungsdatei als `config.json.v<alte Version>.backup` daneben gesichert.
Eine **neuere** Version wird rundheraus abgelehnt statt halb interpretiert: ein
neueres Schema kann Felder verschoben haben, und eine halb verstandene
Konfiguration platziert Fenster dort, wo niemand sie haben wollte.

Weiterhin offen ist ein expliziter Import/Export in der Oberfläche.

---

## 7. Verteilung und Signierung — *teilweise entschieden*

**Der Verdacht hat sich bestätigt, und zwar deutlicher als erwartet.** Der
Accessibility-Grant hängt an der Code-Signatur, und ohne sie ist das Werkzeug
nicht bloß unbequem, sondern unbrauchbar: `AXIsProcessTrusted()` meldet `true`,
aber jede App liefert auf `AXWindows` nur Stellvertreter mit Rolle
`AXApplication`, und `AXPosition` scheitert mit `-25205`. Der Haken in den
Systemeinstellungen bleibt gesetzt und meint nach jedem Neubau ein anderes
Programm.

**Entschieden ist die Entwicklungsseite.** `Scripts/bundle.sh` baut, packt und
signiert mit Developer ID. Die Designated Requirement bindet an Identifier und
Team statt an die Prüfsumme:

```
designated => identifier "com.trsdn.openzonr" and anchor apple generic
  and certificate leaf[subject.OU] = <TEAM>
```

Damit überlebt die Freigabe jeden Neubau. Ein Ad-hoc-Zertifikat genügt nicht, es
hat keine solche Kette.

**Der Pfad zählt trotzdem.** Ein frisch gebautes, identisch signiertes Bundle an
einem neuen Ort ist nicht freigegeben — über LaunchServices gestartet meldet es
„nicht vertraut". Die Freigabe gilt dem Programm an seinem Platz, nicht dem
Identifier allein. `Scripts/bundle.sh` legt das Bundle deshalb unter
`~/Applications/OpenZonr.app` ab statt in `.build`, wo die erste Aufräumaktion
sie kosten würde.

Praktische Folge für Mitwirkende: **ohne Developer-ID-Zertifikat
lässt sich an der Platzierung nicht sinnvoll arbeiten.** Die rechnende Hälfte in
`OpenZonrCore` bleibt headless testbar, die Anbindung nicht.

**Offen bleibt die Verteilung an andere:**

- **Notarisierte Direktverteilung** (Developer ID) — der naheliegende Weg, setzt
  die kostenpflichtige Entwicklermitgliedschaft voraus, die hier ohnehin
  vorhanden ist. Notarisierung ist noch nicht eingerichtet.
- **App Store** — scheidet praktisch aus: die Accessibility-API ist mit dem
  App-Sandbox nicht vereinbar.
- **Selbst gebaut aus dem Quellcode** — funktioniert nur mit eigenem
  Zertifikat, siehe oben.

Damit verbunden: ob und wie ein automatischer Update-Mechanismus eingebaut wird.
Da die Requirement an Identifier und Team bindet, sollte ein Update den Grant
nicht kosten — geprüft ist das noch nicht.

---

## 8. Zonenkonfiguration und Editor

Offen ist, wie Zonen tatsächlich gezeichnet werden: freies Zeichnen auf einer
Vorschau des Bildschirms, ein Raster mit einrastenden Kanten, oder mitgelieferte
Vorlagen (Hälften, Drittel, 25/50/25), die anschließend angepasst werden können.

Ebenfalls offen: ob Zonenränder und Abstände (Gaps) konfigurierbar sein sollen.
Das Datenmodell sieht sie derzeit nicht vor, weil sich Abstände auch als
prozentuale Ränder in den Zonen selbst ausdrücken lassen — nur eben umständlich.

---

## 9. Virtuelle Displays kippen den Setup-Fingerprint — *entschieden*

**Der Befund.** Auf dem Setup des Autors melden vier Displays, aber nur zwei sind
physisch. „AAA" (vermutlich OBS) und „Teleprompter Source" sind
Software-Displays. Sie erscheinen und verschwinden, während sich am Schreibtisch
nichts ändert.

Nach dem ursprünglichen Konzept ändert sich damit **jedes Mal der
Fingerprint**, das Profil springt um, und Fenster landen woanders — ausgelöst
davon, dass jemand OBS startet. Das ist kein Randfall, sondern ein
Konzeptfehler.

**Erwogene Wege:**

- **`CGDisplayIsOnline` / `CGDisplayIsAsleep` prüfen.** Hilft nicht: virtuelle
  Displays sind online und wach.
- **Über die physische Größe erkennen** (`CGDisplayScreenSize`). Getestet und
  **widerlegt**: „AAA" meldet 677,3 × 381,0 mm, „Teleprompter Source" 478,1 ×
  268,9 mm — beides völlig plausible Monitorgrößen. Die verbreitete Annahme
  „virtuelle Displays melden 0 × 0" trifft hier nicht zu.
- **Über unplausible EDID-Kennungen raten** (`modelNumber <= 1`, Seriennummer 0).
  Trifft die beiden Fälle, ist aber nachweislich unzuverlässig: der *echte*
  Hauptmonitor meldet ebenfalls Seriennummer 0.
- **Eine explizite Ignorierliste in der Konfiguration.**

**Entscheidung: explizite Liste `Configuration.ignoredDisplays`.** Displays
darin fließen nicht in den Fingerprint ein. `openzonr displays` markiert
Verdachtsfälle sichtbar mit `virtuell?` und
`openzonr displays --config-fragment` schlägt sie als `ignoredDisplays`-Einträge
vor — **entscheiden muss der Nutzer.**

Begründung: jede Heuristik, die stark genug ist, um beide virtuellen Displays zu
fangen, fängt auf anderen Setups auch echte Monitore. Ein Werkzeug, das einen
angeschlossenen Bildschirm stillschweigend aus dem Profil nimmt, ist schlimmer
als eines, das eine Zeile Konfiguration verlangt. Die Heuristik bleibt deshalb
eine *Anzeige*, nie eine *Aktion*.

**Neu aufgeworfen:** Die Markierung `virtuell?` ist eine Vermutung und als solche
beschriftet. Ob es eine belastbare öffentliche API zur Unterscheidung gibt, ist
weiterhin offen — die naheliegenden Kandidaten sind widerlegt.

---

## 10. `AXIsProcessTrusted()` ist kein verlässlicher Berechtigungstest — *geklärt*

**Der Befund.** Beim Bauen des Durchstichs trat ein Zustand auf, den das Konzept
nicht vorsah:

```
AXIsProcessTrusted()                                     → true
AXUIElementCopyAttributeValue(app, kAXWindowsAttribute)  → .success
  … liefert ein Element mit Rolle AXApplication, ohne Position und Größe
AXObserverAddNotification(kAXWindowCreatedNotification)  → .success
  … und die Benachrichtigung wird tatsächlich zugestellt
```

Die API meldet also durchgehend Erfolg, aber es kommen keine echten Fenster
zurück. Reproduziert mit `openzonr` **und** mit einem unabhängig kompilierten
Probe-Programm im selben Prozesskontext — es liegt nicht am Werkzeug.

**Die Ursache ist inzwischen weitgehend geklärt, und die erste Vermutung war
nicht falsch, sondern unvollständig.** Angenommen wurde, die Berechtigung hänge
am startenden Programm (Terminal, Editor, Agent-Prozess). Hinzu kommt die
Code-Signatur: eine unsignierte Binärdatei bekommt bei jedem Neubau eine neue
Prüfsumme, und TCC erkennt sie nicht wieder. Beide Mechanismen wirken zusammen,
und der degradierte Zustand ist genau ihr Zusammenspiel — `AXIsProcessTrusted()`
erbt das Vertrauen des startenden Terminals, die Fensterzugriffe erben es nicht.
Mit einem freigegebenen, signierten Bundle liefert derselbe Aufruf 19 echte
`AXWindow` mit lesbarem Frame. Einzelheiten in Frage 7.

**Konsequenz für die Implementierung:** `openzonr` verlässt sich nicht auf
`AXIsProcessTrusted()`, sondern führt einen echten Selbsttest aus
(`Accessibility.probeWindowAccess()`): Liefert *irgendeine* App ein Element mit
der Rolle `AXWindow` **und** lesbarem Frame? Nur dann gilt der Zugriff als
funktionsfähig. Die drei Ergebnisse — gewährt, nicht vertraut, degradiert — haben
je eine eigene deutschsprachige Anleitung. Unter `--dry-run` ist „degradiert" nur
eine Warnung, damit Konfiguration und Profilwahl trotzdem prüfbar bleiben.

**Dieser Selbsttest bleibt trotzdem richtig.** Der degradierte Zustand tritt bei
jedem unsignierten Build auf, also bei jedem Mitwirkenden ohne Zertifikat. Ein
Werkzeug, das nur `AXIsProcessTrusted()` prüft, täte dort stumm gar nichts und
gäbe keinen Hinweis darauf, woran es liegt.

**Nachgetragen:** Das Retry-Verhalten ist inzwischen gemessen — beide getesteten
Apps fügen sich beim ersten Schreiben, siehe
[tracer-bullet.md](tracer-bullet.md).

---

## 11. Konkurrierende Fenstermanager — *offen*

Auf dem Messrechner läuft Magnet (`com.crowdcafe.windowmagnet`) parallel und
platziert Fenster über dieselbe Accessibility-API.

Zwei Konsequenzen:

- **Für die Messung.** Eine Abweichung zwischen Soll- und Ist-Frame im
  Retry-Protokoll ist nicht automatisch das Selbst-Resize der App. Sie kann
  ebenso gut von Magnet stammen. Wer das nicht weiß, misst Magnet und hält das
  Ergebnis für Outlook. Für saubere Messungen konkurrierende Werkzeuge
  vorübergehend beenden.
- **Für den Betrieb.** Zwei Werkzeuge, die auf dasselbe Ereignis reagieren,
  können sich gegenseitig überschreiben — im schlechtesten Fall abwechselnd, bis
  eines aufgibt. OpenZonr gibt nach `RetryPolicy.maximumAttempts` auf und
  protokolliert das; ein Werkzeug ohne Obergrenze täte das nicht.

**Offen:** Ob OpenZonr solche Werkzeuge erkennen und beim Start warnen sollte
(die Bundle-IDs der verbreiteten Kandidaten sind bekannt und stabil), oder ob
das übergriffig ist. Tendenz: eine einmalige Warnung beim Start von `watch` ist
angemessen, ein Blockieren nicht.

---

## 12. Fensterebene als Filterkriterium — *entschieden*

Der Konzeptstand filterte über Subrolle und Mindestgröße. Die Messung an der
echten Fensterlandschaft zeigt, dass das nicht reicht: die **Mitteilungszentrale
ist 5120 × 1440 groß** und besteht damit jede Mindestgrößen-Prüfung. Nur ihre
Fensterebene (21) unterscheidet sie von einem echten Fenster.

**Entscheidung:** `kCGWindowLayer == 0` ist ein **eigenständiges, standardmäßig
aktives und nicht abschaltbares** Filterkriterium — und zwar das erste, vor
Subrolle und Größe. Es ist bewusst *keine* Option in `WindowMatch`: eine Regel,
die Fenster auf Ebene 24 platzieren will, will in Wahrheit die Menüleiste
verschieben.

---


Zur Nachvollziehbarkeit festgehalten:

| Abweichung | Begründung |
|---|---|
| **SwiftPM-Package statt Xcode-Projekt** | Der Anfangsstand war reines Datenmodell und ließ sich so headless mit `swift build` / `swift test` prüfen; das Manifest ist Text und damit reviewbar. Die damalige Annahme, Signierung erfordere ein Xcode-Target, hat sich als falsch erwiesen: `Scripts/bundle.sh` baut aus dem Package ein signiertes `.app`, und der Accessibility-Grant hält. Ein Xcode-Projekt wird damit erst nötig, wenn das Menüleisten-Target mehr braucht als SwiftPM liefert. |
| **Profil „Unterwegs" ohne Space 2** | Spaces sind über die öffentliche API nicht adressierbar, siehe Frage 1. Die Rolle `communication` liegt im Beispiel stattdessen auf der rechten Hälfte des integrierten Displays. |
| **`fallback` ist Pflichtfeld im Profil** | Das Konzept forderte eine definierte Default-Zone für nicht gemappte Rollen. Als optionales Feld wäre sie in der Praxis leer geblieben — genau der Zustand, den sie verhindern soll. |
| **JSON statt YAML** | Bewusst gewählt: `Codable` ohne externe Abhängigkeit. Der Preis sind fehlende Kommentare, weshalb die kommentierte Erklärung in `docs/konfiguration.md` liegt. |
| **`share` nur als gleichmäßige Slot-Teilung** | Das Konzept nannte „optional Zone teilen", ohne die Ausdrucksstärke festzulegen. Alles über gleich große Slots hinaus gehört als eigene Zone ins Layout, sonst entsteht ein zweites, paralleles Layoutsystem in den Regeln. |
| **Zonen dürfen sich überlappen** | Nicht explizit im Konzept. Überlappung wird zugelassen, weil eine große Fokuszone über zwei Hälften eine legitime Gestaltung ist. Mehrdeutigkeit löst die Rollenbindung, nicht die Geometrie. |
| **`RuleEngine` nimmt einen vorbereiteten `CompiledRuleSet` statt `[PlacementRule]`** | Die Skizze übergab die Regeln je Fenster. Damit ließe sich die Forderung „reguläre Ausdrücke werden einmal übersetzt" nur über einen Cache erfüllen, der über Array-Gleichheit rät. Ein explizit vorbereiteter Regelsatz macht stattdessen sichtbar, dass die Übersetzung eines Musters fehlschlagen kann, und zwingt dazu, diesen Fall an einer definierten Stelle zu behandeln — statt mitten in der Auswertung. Eine Regel mit ungültigem Muster landet in `unusableRules` und wird übersprungen; der Durchlauf scheitert nie an einer kaputten Regel. |
| **`ZoneResolver` rechnet in AppKit-Koordinaten, nicht in AX-Koordinaten** | Das Modell beschreibt Zonen von oben links, AppKit misst von unten links, die Accessibility-API wieder von oben links. Die Umrechnung Modell → AppKit passiert genau einmal, nämlich hier; die Rückrechnung nach AX gehört in die Schicht, die tatsächlich `kAXPositionAttribute` schreibt. Ein eigener Typ `VisibleFrame` macht die Konvention an jeder Aufrufstelle sichtbar, statt sie einem `WindowFrame` anzusehen zu versuchen. |
| **Kantenweises Runden statt Runden von Ursprung und Größe** | Zwei nebeneinanderliegende Zonen müssen sich exakt berühren. Würden Ursprung und Größe getrennt gerundet, entstünde je nach Displaybreite eine Lücke oder eine Überlappung von einem Punkt. Stattdessen werden die vier Kanten gerundet und Breite und Höhe daraus abgeleitet. |
| **`WindowFilter` kennt die Regeln, die `onlyFirstWindowAfterLaunch` abwählen** | Die Skizze sah den Filter als reinen Vorfilter vor globalen Vorgaben. Ein Filter, der die Vorgabe hart durchsetzt, macht aber genau die Regeln unerreichbar, die sie abwählen — das Outlook-Verfassen-Fenster der Beispielkonfiguration ist per Definition nie das erste Fenster. Der Filter leitet seine Ausnahmen deshalb einmalig aus dem Regelsatz ab: jede aktivierte Regel, die das Flag auf `false` setzt, nimmt die Fenster ihrer Bundle-ID aus (oder alle, wenn sie keine nennt). |
| **`Displacement` und `SkipReason` als eigene Ergebnistypen** | `PlacementOutcome` beschreibt, was mit einem Fenster geschehen *ist*. Für die rein rechnende Hälfte fehlte ein Typ, der beschreibt, was geschehen *soll* — inklusive Begründung, wenn nichts geschieht. `PlacementDecision` füllt diese Lücke; ohne sie wäre „nicht platziert" eine Sammelantwort für sehr verschiedene Situationen. |
| **`ZoneResolver.resolveFallback` neben der Auflösung über die Rolle** | Die Fallback-Bindung eines Profils über ihre Rolle aufzulösen wäre falsch: hat diese Rolle eine eigene Bindung, käme deren reguläre Zone heraus. Ein verdrängtes Fenster landete dann in genau der Zone, aus der es gerade weichen musste. |

---

## Designentscheidungen des Durchstichs

Getroffen beim Bauen von `openzonr`, ohne dass das Konzept sie vorgab:

| Entscheidung | Begründung |
|---|---|
| **Displays über `NSScreen.screens` statt `CGGetActiveDisplayList` aufzählen** | `CGGetActiveDisplayList` liefert in einem reinen Kommandozeilenprozess **null** Displays — reproduzierbar gemessen. Die `CGDirectDisplayID` kommt stattdessen aus `NSScreen.deviceDescription["NSScreenNumber"]`; alle EDID-Abfragen laufen danach unverändert über die `CGDisplay*`-Funktionen. |
| **Argument-Parsing von Hand statt `swift-argument-parser`** | Drei Unterbefehle mit zusammen fünf Optionen rechtfertigen keine externe Abhängigkeit. `swift build` bleibt ohne Netzwerkzugriff lauffähig. |
| **Die Umrechnung nach AX-Koordinaten passiert an genau einer Stelle** | `ZoneResolver` liefert AppKit-Koordinaten, die Accessibility-API will den Ursprung oben links. Die Spiegelung liegt ausschließlich in `WatchCommand.place(…)` über `ScreenArrangement.flipVertically`. Zwei Umrechnungsstellen wären zwei Gelegenheiten, das Vorzeichen zu verlieren. |
| **Schreibsequenz Position → Größe → Position** | Setzt man nur Position und dann Größe, verschiebt eine App, die die Größe begrenzt, das Fenster erneut. Die zweite Positionszuweisung korrigiert das innerhalb desselben Versuchs, bevor überhaupt zurückgelesen wird. |
| **Erfolg heißt: maximale Kantenabweichung ≤ `tolerance`** | Nicht die Fläche und nicht der Abstand der Ursprünge. Eine App, die nur die Breite ignoriert, fällt sonst durch, obwohl das Fenster sichtbar falsch sitzt — oder umgekehrt. |
| **Nach erfolgreicher Platzierung wird nicht weiter beobachtet** | Ein Fenster, das nach der Platzierung bewegt wird, wurde vom Nutzer bewegt. Ein Werkzeug, das das rückgängig macht, ist ein Gefängnis. |
| **Bereits laufende Apps gelten nie als „erstes Fenster nach Start"** | Ihr Zähler startet bei `Int.max / 2`. Sonst würde `onlyFirstWindowAfterLaunch` beim Start von `watch` auf ein beliebiges bestehendes Fenster zutreffen. |
| **`AXObserverAddNotification` wird bis zu 20× im Abstand von 150 ms wiederholt** | Ein frisch gestarteter Prozess ist für kurze Zeit nicht über die Accessibility-API erreichbar. Ein einzelner Versuch direkt nach `didLaunchApplicationNotification` schlägt regelmäßig fehl — und genau dann verpasst man das erste Fenster, also das interessanteste. |
| **`mode: "suggest"` wird nur protokolliert** | Ein Vorschlag ohne Overlay ist kein Vorschlag. Die Regel, die Rolle und der Ziel-Frame werden ausführlich ausgegeben, damit sichtbar ist, was passiert *wäre*; bewegt wird nichts. `share` dagegen ist über `DefaultZoneResolver` vollständig umgesetzt und wird nur zusätzlich protokolliert. |
