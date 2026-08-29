# Dropzones — Fenster mit der Maus in Zonen ziehen

Die Hälfte, die von Anfang an vorausgesetzt war. Das Vorhaben begann mit dem
Satz: *„Könnte man einen Fenstermanager bauen, der so Dropzones hat, wie die
meisten — mich nervt aber, dass eine neu geöffnete App nicht automatisch in der
Zone landet."* Gebaut war bisher nur der zweite Teil. Dies ist der erste.

Umgesetzt in Issue #10, danach fortgeschrieben in Issue #23. Kurz:

- Beim Ziehen eines Fensters mit gehaltenem **⌘** erscheinen die Zonen des
  aktiven Profils auf dem Display unter dem Zeiger; die getroffene Zone ist
  hervorgehoben.
- Beim Loslassen wird das Fenster in diese Zone gelegt — **über denselben Code
  wie die Automatik**, nicht über einen zweiten Pfad.
- Loslassen auf der **Anheft-Marke** einer Zone schreibt zusätzlich eine Regel
  über den bestehenden `QuickPin`, in derselben Bewegung. Loslassen daneben
  bleibt eine einmalige Platzierung.
- Die alte Rückfrage „Diese App immer hier öffnen?" ist als Vorgabe **aus**;
  wer sie will, schaltet `defaults.dropzones.offerRule` an.
- Die Aktivierungsregel `defaults.dropzones.activation` hat zwei Formen: die
  Vorgabe `{"showsWhile": "command"}` — Zonen erscheinen nur mit ⌘ — und die
  ältere `{"showsUnless": "option"}` — Zonen bei jedem Zug, ⌥ silent. Eine
  bestehende `config.json` mit `suppressionModifier: "option"` liest weiter
  und bildet automatisch auf die ältere Form ab (siehe *Migration* unten).

---

---

## Der Tausch bei ⌘ als Einschalter, gemessen

Seit Issue #23 ist die Vorgabe: **die Zonen erscheinen nur, solange ⌘ gehalten
wird**, statt „bei jedem Zug, außer bei ⌥". Die Umkehrung ist bewusst und hat
einen Preis, der gemessen ist.

**Drei Läufe am 29.08.2026:** Ein Zug an der Titelleiste eines Hintergrund­fensters
holt es nach vorn. **Derselbe Zug mit ⌘ lässt die vordere App vorne.** ⌘ ist auf
Fenster­zügen also bereits belegt und bedeutet dort *bewegen, ohne zu aktivieren*.

Folge: Mit ⌘ als Einschalter erscheinen die Zonen genau dann, wenn nicht
aktiviert werden soll — ein Hintergrund­fenster einsortieren, ohne den Fokus zu
verlieren. Es heißt aber auch, dass es die alte Geste *ohne die neue* nicht mehr
gibt: wer einfach ein Fenster ziehen will, ohne dass Zonen aufleuchten, muss
nichts drücken (das ist jetzt der Normalfall) — wer sie sehen will, drückt ⌘.

*Nicht gemessen:* ob ⌘-Ziehen ein Hintergrund­fenster tatsächlich **bewegt**. In
keinem Lauf hat sich ein Hintergrund­fenster bewegt, auch nicht ohne ⌘ — der
synthetische Zug kann das nicht beantworten. Belegt ist ausschließlich der
Unterschied bei der Aktivierung.

*Ebenfalls nicht gemessen:* ob sich ⌘ beim Ziehen bequem anfühlt und ob die
Anheft-Marke auffindbar ist. Das braucht eine Hand an der Maus; siehe die
Tabelle „Was gemessen ist und was nicht" weiter unten.

## Migration bestehender Konfigurationen

Eine `config.json`, die vor Issue #23 geschrieben wurde, trägt
`defaults.dropzones.suppressionModifier: "option"`. Ohne Migration stünde ein
Nutzer nach dem Update mit der neuen Vorgabe da — Zonen erscheinen nur mit ⌘ —
und wüsste nicht, dass eine unbenutzte Sekunde Ziehen jetzt genau das *nicht*
mehr bedeutet, was sie gestern bedeutet hat.

Der Codec liest den alten Schlüssel weiter und bildet ihn auf
`activation: {"showsUnless": "option"}` ab — dieselbe Polarität, die die alte
Datei ausdrückte. **Neu geschrieben wird nur der neue Schlüssel.** Beide Namen
in derselben Datei würden sich beim nächsten Bearbeiten von Hand widersprechen,
und der Codec müsste einen Vorrang festlegen: er tut es (`activation` schlägt
`suppressionModifier`), damit eine handbearbeitete neue Datei nicht von einem
übrig­gebliebenen alten Feld überstimmt wird. `DropzoneSettingsDecodingTests`
hält beide Fälle fest.

## Die Anheft-Marke — Regel im Zug statt Rückfrage danach

Solange die Zonen sichtbar sind, trägt jede Zone eine kleine Marke, oben rechts.
Normal loslassen: einmalige Platzierung, keine Regel, keine Frage. Auf der
Marke loslassen: dieselbe Platzierung und `QuickPin` schreibt die Regel — in
derselben Bewegung.

Die Trefferprüfung ist eine **reine Funktion** neben `DropzoneMap`
(`DropzoneMap.pinBadgeFrame(for:)` und `DropzoneMap.isOnPinBadge(_:of:)`), damit
sie ohne die Bedienungshilfen-Freigabe geprüft werden kann — dieselbe Trennung,
die der Rest der Dropzones-Hälfte durchzieht. Der Codepfad im Controller ist
zwei Zeilen: liegt der Zeiger beim Loslassen auf der Marke, wird über die
Fabrik `DropRuleOffer.pin(...)` (kein Panel-Gate) direkt eine `QuickPin.Request`
gebaut und angewendet — sonst der bisherige *Panel-anbieten*-Zweig, der aber
per Vorgabe schweigt.

**Warum die Marke oben rechts und nicht in der Mitte.** Auf einer kleinen Zone
würde eine mittige Marke die ganze Zone abdecken; die einmalige Platzierung
*ohne* Regel wäre unerreichbar. Der Sicherheitstest
`theBadgeNeverSwallowsTheWholeZone` zieht über Zonengrößen von 60 bis 4000
Punkten und stellt sicher, dass die Mitte jeder Zone, für die überhaupt eine
Marke gezeichnet wird, kein Marken-Treffer ist. Ist die Zone zu klein für Marke
plus verbleibenden Streifen, wird gar keine Marke gezeichnet — dann ist jeder
Drop einmalig, ohne dass der Controller einen zweiten Pfad kennen muss.

## Was ausdrücklich nicht gebaut wird — und warum

Drei naheliegende Wege, die Regel *im Zug* zu setzen, sind gemessen ausgeschieden.
Ohne diese Liste baut sie jemand erneut.

**Rechtsklick auf die Titelleiste — kollidiert.** Instrument: Klick und
Erkennung in *einem* Programm (ein Kontextmenü kann zwischen zwei Aufrufen
zugehen), Menüfenster über `CGWindowList` an Ebene 101. Positivkontrolle
bestanden, 3/3.

| Wohin geklickt | App-Menü? | Läufe |
|---|---|---|
| TextEdit — Textbereich *(Positivkontrolle)* | **ja**, 290×543 | 3/3 |
| TextEdit — leere Titelleiste | nein | 3/3 |
| TextEdit — Titeltext / Proxy-Symbol | **ja**, 197×82 | 1/1 |
| TextEdit — grüner Knopf, Rechtsklick | nein | 1/1 |
| **Safari — vereinheitlichte Symbolleiste, leere Stelle** | **ja**, 206×34 | 3/3 |
| Safari — dieselbe Stelle mit ⌥ / ⌘ / ⇧ | **ja, jedes Mal** | je 1 |

In modernen Apps *ist* die Titelleiste die Symbolleiste — Safari, Finder, Mail.
TextEdit war die Ausnahme, nicht die Regel. Modifier unterdrücken das App-Menü
nicht.

**Aktiver Event-Tap, um den Rechtsklick zu schlucken — zu teuer.**
`EventTapDragTracker.swift:74` erstellt den Tap mit `options: .listenOnly`; er
kann nichts verschlucken. Mit `.defaultTap` ginge es, aber dann liefe **jeder
Rechtsklick der Maschine** durch unseren Rückruf, bevor irgendeine App ihn
sieht. Ist er zu langsam, schaltet macOS den Tap ab — und dann hört auch die
Drag-Erkennung auf, ohne dass es auffällt. Genau die Fehlerklasse, die dieses
Projekt sonst jagt.

**Panel unter dem grünen Knopf — fremdes Revier.** Der Knopf ist auffindbar
(gemessen: `AXButton … AXZoomWindow` bei `3894,39 16×16`), und ein Rechtsklick
darauf zeigt kein App-Menü. Aber macOS blendet dort beim *Schweben* sein
eigenes Menü ein. Zwei Menüs am selben Pixel.

**Erst nach mehrfacher Wiederholung fragen** („du hast das jetzt dreimal so
gemacht") — streckt das Ärgernis, statt es zu beheben, und braucht Zustand über
Sitzungen hinweg.

Die tatsächliche Antwort ist stattdessen die Anheft-Marke: kein neuer Eingriff
ins System, keine Kollision mit fremden Apps, kein aktiver Event-Tap.

---

## Die zwei gemessenen Fragen

### 1. `kAXMovedNotification` oder `CGEventTap`?

Beide Wege sind gebaut (`AXMovedDragTracker`, `EventTapDragTracker`) und werden
von `openzonr dragprobe` nebeneinander gemessen. Drei Läufe à 3 s auf dem
Rechner des Nutzers, Ereignisse synthetisch erzeugt (siehe unten, warum):

| Größe | `CGEventTap` | `kAXMovedNotification` |
|---|---|---|
| Einrichtung | gelingt | gelingt |
| Berechtigung | Bedienungshilfen | Bedienungshilfen — **dieselbe**, keine zusätzliche |
| Empfangen von 40 gesendeten | 40 (+ Down + Up = 42) | 40 |
| Verlust | 0 von 40, in 3 von 3 Läufen | 0 von 40, in 3 von 3 Läufen |
| Rate | 44,3 / 50,3 / 53,7 pro s | 52,6 / 52,5 / 50,8 pro s |
| Größte Lücke | 55,7 / 38,1 / 39,2 ms | 39,9 / 37,1 / 38,5 ms |
| Loslassen | **1 Ereignis pro Zug**, exakt | **0** — nur per Abfrage feststellbar |
| Latenz | nicht messbar (Begründung unten) | grundsätzlich nicht messbar |

**Die Rate ist die Rate des Erzeugers, nicht die Obergrenze des Weges.** Der
Messtreiber gibt pro Run-Loop-Durchlauf ein Ereignis ab (Timer, 8 ms). Dass
beide Wege bei rund 50 Ereignissen pro Sekunde exakt das ankommen lassen, was
gesendet wurde, ist die Aussage — nicht, dass 50 das Maximum wäre.

**Die erste Version dieser Messung war falsch, und das gehört hierher.** Sie
schickte die 40 Ereignisse in einer `usleep`-Schleife und meldete daraufhin
753 Ereignisse pro Sekunde bei 51,5 ms größter Lücke. Beides waren Artefakte
einer Warteschlange, die sich nach dem Blockieren auf einmal leerte. Wer den
Hauptthread blockiert, während er den Hauptthread misst, misst das Blockieren.
Deshalb läuft die Erzeugung jetzt über den Run Loop (`SyntheticDriver`).

**Entschieden wurde für den `CGEventTap`, und zwar wegen einer einzigen Zeile
der Tabelle: dem Loslassen.** Der Tap meldet es als Ereignis. Accessibility
meldet es überhaupt nicht — dort muss der Mausknopf abgefragt werden, 60 mal pro
Sekunde, solange der Zug dauert (`AXMovedDragTracker.startPolling`). Für eine
Funktion, deren ganzer Sinn der Moment des Ablegens ist, ist das der Unterschied
zwischen messen und schätzen. Dazu kommt, dass Accessibility auch Bewegungen
meldet, die keine Züge sind — fremde Werkzeuge, die App selbst, OpenZonrs eigene
Platzierung —, sodass dieselbe Abfrage nicht nur für das Ende, sondern für die
Korrektheit gebraucht wird.

Der zweite Weg bleibt im Code. Nicht als Reserve für den Fall, dass der Tap
nicht funktioniert, sondern als Vergleichsmaßstab: Wenn jemand die Entscheidung
später anzweifelt, kann er sie nachmessen statt nachlesen.

### 2. Magnet

`com.crowdcafe.windowmagnet` läuft auf diesem Rechner. In
[`tracer-bullet.md`](tracer-bullet.md) war Magnet eine Messstörung; hier ist es
ein Entwurfsproblem, weil beide Programme beim Ziehen ein Overlay einblenden und
auf dieselben Ereignisse hören.

**OpenZonr erkennt es und sagt es. Mehr nicht.** `CompetingWindowManagers` kennt
15 Bundle-Kennungen, meldet Treffer im Menü und unterscheidet dabei, ob das
andere Programm ebenfalls beim Ziehen ein Overlay zeigt (Magnet, Rectangle,
BetterSnapTool …) oder nur dieselbe API benutzt (AltTab, Bartender …). Das Erste
ist ein Konflikt um dieselbe Geste, das Zweite bloß Nachbarschaft.

Verworfen wurden:

- **Um die Vorherrschaft kämpfen** — beim Loslassen ein zweites Mal setzen,
  später als der andere. Das ist ein Wettrennen ohne Ziellinie: wer zuletzt
  schreibt, gewinnt, und beide Programme können jederzeit schneller werden. Der
  Nutzer sähe ein Fenster, das nach dem Loslassen springt.
- **Magnet beenden** — nicht die Aufgabe eines Fenstermanagers, fremde Programme
  zu schließen.
- **Stillschweigend abschalten** — dann täte OpenZonr beim Ziehen nichts, ohne
  zu sagen, warum. Genau die Klasse Fehler, an der dieses Projekt schon dreimal
  bezahlt hat.

Die Warnung lässt sich über `defaults.dropzones.warnAboutCompetingManagers`
abstellen; sie schaltet das Ziehen nicht ab. Damit ist Punkt 11 aus
[`offene-fragen.md`](offene-fragen.md) für den Zieh-Fall beantwortet.

---

## Was gemessen ist und was nicht

| Gegenstand | Stand | Begründung |
|---|---|---|
| Zuordnung Zeiger → Display → Zone | **Bewiesen**, headless | 10 Tests in `DropzoneMapTests`, inklusive der echten Anordnung 5120×1440 mit 1920×1080 darüber |
| Überlappende Zonen: kleinere gewinnt | **Bewiesen**, headless | ohne diese Regel wären die Hälften unter einer Fokuszone per Maus unerreichbar |
| Geteilte Kante gehört genau einer Zone | **Bewiesen**, headless | links/unten inklusiv, rechts/oben exklusiv |
| Gleiche Fläche → deterministische Wahl | **Bewiesen**, headless | nach Display- und Zonenkennung, nie nach Array-Reihenfolge |
| Zonen bleiben in einer Lücke sichtbar | **Bewiesen**, headless | das Display entscheidet, nicht die getroffene Zone |
| Overlay-Entscheidung (zeigen/verstecken) | **Bewiesen**, headless | `DropzoneOverlayPlanTests` |
| Unterdrückung per ⌥ (`showsUnless`-Form) | **Bewiesen**, headless | `DropzoneActivationTests`, inklusive „⌘ unterdrückt bei `showsUnless(.option)` nicht" |
| Einschalter per ⌘ (`showsWhile`-Form, neue Vorgabe) | **Bewiesen**, headless | `DropzoneActivationTests`; ohne ⌘ liefert die Aktivierung `awaitingModifier(.command)` mit deutschem Grund |
| Migration alter Konfigurationen (`suppressionModifier` → `showsUnless`) | **Bewiesen**, headless | `DropzoneSettingsDecodingTests`, mit Vorrangregel für gleichzeitig vorhandene alte und neue Schlüssel |
| Trefferprüfung auf der Anheft-Marke | **Bewiesen**, headless | `DropzonePinBadgeTests`, samt Invariante „Marke schluckt nie die ganze Zone" über Zonengrößen von 60 bis 4000 Punkten |
| Marken-Pfad umgeht den `offerRule`-Schalter | **Bewiesen**, headless | `DropRuleOfferPinTests`; sonst würde bei ausgeschaltetem Panel jede Marke stumm nichts tun |
| Mindeststrecke vor dem Einblenden | **Bewiesen**, headless | verhindert Flackern beim bloßen Anklicken |
| Ableitung Ablegen → Regel | **Bewiesen**, headless | `DropRuleOfferTests`; zweimal Ablegen verdoppelt die Regel nicht |
| Alte Konfiguration ohne `dropzones` lädt | **Bewiesen**, headless | sonst wäre nicht der Schlüssel kaputt, sondern die ganze Datei |
| Pause schaltet auch das Ziehen ab | **Bewiesen**, headless | `DropzoneActivator.suspension`; die Entscheidung liegt an einer Stelle, nicht in Controller und Menütext getrennt |
| Kein Angebot, wenn die Regel schon dorthin zeigt | **Bewiesen**, headless | `DropRuleOffer` fragt `QuickPin`, ob ein Ja etwas änderte; ein Test hält auch das Gegenstück fest (andere Zone → es wird gefragt) |
| Zonengeometrie identisch mit dem Regelweg | **Bewiesen**, headless | `ZoneGeometry` ist die einzige Umrechnung, ein Test vergleicht beide Ergebnisse |
| Ereignisrate und Verlust beider Wege | **Gemessen**, synthetisch | drei Läufe, Tabelle oben; 0 von 40 verloren |
| Loslassen als Ereignis vs. Abfrage | **Gemessen** | der Grund für die Entscheidung |
| Einrichtbarkeit beider Wege | **Gemessen** | beide gelingen, beide mit derselben Berechtigung |
| **Latenz eines Ereignisses** | **Nicht gemessen** | Selbst gepostete `CGEvent`s werden erst bei der Zustellung gestempelt; die Differenz zu `mach_absolute_time()` ist nicht positiv und wird deshalb als „nicht messbar" gemeldet statt als 0,0 ms. Accessibility-Benachrichtigungen tragen überhaupt keinen Zeitstempel — dort ist Latenz auch bei echten Zügen prinzipiell nicht messbar. |
| **Ein echter Zug mit der Hand** | **Nicht gemessen** | Die Bedienungshilfen-Freigabe für `~/Applications/OpenZonr.app` liegt seit dem 29.08.2026 vor — daran liegt es also **nicht mehr**. Was fehlt, ist eine Hand an der Maus: ein Zug ist nicht automatisierbar, und synthetische Ereignisse belegen nur den Empfang, nicht die Bedienung. |
| **Overlay auf dem Bildschirm** | **Nicht gemessen** | Zeichnen braucht ein sichtbares Fenster während eines echten Zugs — also dieselbe Hand, nicht dieselbe Freigabe. Die *Entscheidung*, was gezeichnet wird, ist getestet; das Zeichnen selbst ist absichtlich dünn gehalten. |
| **Verhalten mit laufendem Magnet im Zug** | **Nicht gemessen** | Setzt einen echten Zug voraus. Die Erkennung ist getestet, das Verhalten bei Konflikt ist entworfen und begründet, nicht beobachtet. |
| **Ruhe der Hervorhebung auf einer Zonenkante** | **Nicht gemessen** | Die Zuordnung ist eindeutig, aber zustandslos: auf einer Kante kippt die Hervorhebung bei einem Punkt Zittern. Ob das im Gebrauch stört und welche Totzone richtig wäre, ist ohne echten Zug nicht zu beurteilen — deshalb ist keine Hysterese gebaut, sondern Punkt 13 in [`offene-fragen.md`](offene-fragen.md) eröffnet, samt der Falle, in die ein erster Versuch dazu bereits gelaufen ist. |
| **Platzierung nach dem Ablegen** | **Nicht gemessen für das Ablegen**, aber für denselben Code | Der Drop ruft `WatchEngine.place(dropped:application:into:)` auf, das die private `place(…)` mit `rule: nil` benutzt — dieselbe Funktion, deren Platzierung in [`tracer-bullet.md`](tracer-bullet.md) inzwischen auch bei laufender App gemessen ist, samt eines Falls, in dem Outlook sich beim ersten Schreiben wehrt und ein zweiter Versuch nötig ist. |
| **Angebotspanel im Betrieb** | **Nicht gemessen** | Erscheint nur nach einem echten Ablegen. Dass es den Fokus nicht stiehlt, folgt aus `.nonactivatingPanel`; belegt ist es nicht. Seit Issue #23 ist die Vorgabe ohnehin *aus* — der Weg bleibt nur, weil er ohne zusätzlichen Zustand verlässlich ist. |
| **Auffindbarkeit der Anheft-Marke** | **Nicht gemessen** | Ob eine 24-Punkt-Marke oben rechts einer Zone im Gebrauch als *hier festhalten* verstanden wird — oder ob sie zwischen Titel­leisten und Fenster­rand unauffällig verschwindet — braucht eine Hand an der Maus und mehrere Nutzer. Was headless prüfbar ist (sitzt sie in der Ecke, deckt sie nie die ganze Zone ab), ist geprüft. |
| **Verhalten von ⌘-Ziehen mit der Hand** | **Nicht gemessen** | Ob es angenehm ist, ⌘ über die Dauer eines Zugs zu halten, und ob die Umkehrung „nichts drücken heißt: keine Zonen" für den Nutzer stimmig ist, ist ohne echten Zug nicht zu beurteilen. Was gemessen ist, ist der Preis: ⌘-Ziehen bringt heute schon Hintergrundfenster nicht nach vorn, und diese Nebenwirkung wandert mit. |

Kurz: Alles, was ohne einen echten Zug beweisbar ist, ist bewiesen. Alles, was
einen braucht, ist als ungemessen ausgewiesen. Der Schnitt zwischen beidem war
die eigentliche Entwurfsarbeit.

> **Stand 29.08.2026:** Die Bedienungshilfen-Freigabe ist erteilt, und die
> Platzierung ist bei laufender App gemessen ([`tracer-bullet.md`](tracer-bullet.md)).
> Der verbleibende Rest dieser Tabelle hängt damit **nicht mehr an einer
> Berechtigung, sondern an einer Hand an der Maus**. Wer die Zeilen anders liest
> und in den Systemeinstellungen nach einem fehlenden Haken sucht, sucht
> vergeblich.

---

## Aufbau

```
Sources/OpenZonrCore/
  Placement/ZoneGeometry.swift        Zone → Punkte. Die einzige Umrechnung.
  Dropzone/DropzoneMap.swift          Zonen des Profils, Zone unter dem Zeiger.
  Dropzone/DropzoneSettings.swift     Einstellungen, Modifikator, Aktivierung.
  Dropzone/DropzoneOverlayPlan.swift  Was das Overlay zeigen soll.
  Dropzone/DropRuleOffer.swift        Ablegen → QuickPin.Request.
  Dropzone/CompetingWindowManagers.swift

Sources/OpenZonrMac/
  Dropzone/WindowDragTracker.swift    Gemeinsame Typen beider Wege.
  Dropzone/EventTapDragTracker.swift  Der gewählte Weg.
  Dropzone/AXMovedDragTracker.swift   Der Vergleichsmaßstab.
  Dropzone/DragMeasurement.swift      Die Statistik der Messung.
  CommandLine/DragProbeCommand.swift  openzonr dragprobe.

Sources/OpenZonrApp/
  Dropzone/DropzoneController.swift   Verdrahtung, sonst nichts.
  Dropzone/DropzoneOverlay.swift      Ein durchlässiges Fenster je Display.
  Dropzone/DropOfferPanel.swift       „Immer hier öffnen?"
```

Die Trennung ist die Antwort auf die fehlende Berechtigung: In `OpenZonrCore`
steht nichts, was ein Ereignis braucht, und deshalb ist dort alles prüfbar.

---

## Entscheidungen, die nicht offensichtlich sind

**Die Pause hält auch das Ziehen an.** Der Menüpunkt heißt „Platzierung
pausieren", das Protokoll sagt „es wird nichts mehr platziert" — ein Ablegen,
das trotzdem platziert, macht beides zur Lüge. Dass eine ausdrückliche
Mausgeste weiterläuft, während die Automatik ruht, wäre für sich genommen
vertretbar; beides gleichzeitig zu behaupten nicht. Für die strengere Variante
spricht der übliche Anlass zu pausieren: ein zweiter Fenstermanager, der
gegenhält — genau die Lage, in der ein zweites Overlay beim Ziehen am meisten
stört. Während der Pause steht im Menü „Ziehen ist nicht aktiv: Die Platzierung
ist pausiert", und `WatchEngine.place(dropped:)` verweigert zusätzlich von sich
aus. Zwei Schlösser, weil das Versprechen der Engine gehört, die es gibt, und
nicht einem Aufrufer, der daran denken muss. Entschieden wurde das erst in der
Durchsicht zu PR #15; die erste Fassung hörte während der Pause weiter zu und
sagte das Gegenteil.

**Gefragt wird nur, wenn eine Antwort etwas ändert.** Ob eine Regel schon auf
diese Zone zeigt, entscheidet nicht das Angebot, sondern `QuickPin` selbst:
`DropRuleOffer.request` lässt es die Konfiguration ableiten, die ein Ja erzeugen
würde, und schweigt, wenn das die Konfiguration ist, die schon da ist. Ein
eigener Vergleich wäre eine zweite Meinung über Regeln, und zwei Meinungen
laufen auseinander. Ohne diese Prüfung führte das Ziehen einer bereits
festgehaltenen App in ihre eigene Zone zur Frage, ein Ja in den Retarget-Zweig,
zum Speichern einer unveränderten Datei und zu `Log.success` — eine
Erfolgsmeldung ohne Wirkung. Derselbe Aufruf fängt außerdem den Fall ab, dass
sich aus dem Ablegen überhaupt keine Regel schreiben ließe; dann wird gar nicht
erst gefragt.

**Ein unlesbarer Fensterrahmen wird nicht erfunden.** `place(dropped:)` ersetzte
ihn zunächst durch `0×0 bei 0,0`, und dieser Wert wanderte unverändert in die
Ablehnungsmeldung als „Ist:" — ein Messwert, der nie gemessen wurde. Jetzt wird
nichts gesetzt und gesagt, dass der Rahmen nicht lesbar war.

**⌘ als Einschalter, seit Issue #23.** Die frühere Vorgabe hatte ⌥ als
*Silence*-Taste; Zonen erschienen bei jedem Zug, ⌥ unterdrückte sie. Die neue
Vorgabe ist die Umkehrung: nichts drücken → keine Zonen, ⌘ drücken → Zonen. Der
Tausch ist bewusst — der Preis ist im Kopfabschnitt gemessen — und die alte
Polarität lebt in `activation: {"showsUnless": "option"}` weiter. Wer will,
schaltet zurück. Die Migration bestehender Konfigurationen bildet den alten
`suppressionModifier` automatisch auf `showsUnless` ab; ohne sie fänden Nutzer
ihre Zonen nach dem Update ohne Grund still verschwunden.

**Anheft-Marke statt Rückfrage.** Das Panel „Diese App immer hier öffnen?"
unterbricht eine gerade beendete Geste; die Anheft-Marke verlegt die
Entscheidung nach *vor* das Loslassen. Der Panel-Weg bleibt (über den Menü­eintrag
und einen ausschaltbaren Vorgabeschalter), damit nichts an Fähigkeit verloren
geht, was sich Nutzer vielleicht anders zurechtlegen wollen. Die Marken-Fabrik
`DropRuleOffer.pin(...)` und der Panel-Weg `DropRuleOffer.request(...)` bauen
dieselbe `QuickPin.Request` — zwei Eingänge, ein Rechnen, keine zweite Regel­art.

**Der Modifikator zählt jetzt, nicht beim Zugbeginn.** Wer mitten im Ziehen ⌘
drückt, meint es. (Bei `showsWhile` erscheint der Overlay dann, bei `showsUnless`
verschwindet er.)

**Nur das Display unter dem Zeiger.** Auf diesem Schreibtisch ist der
Hauptmonitor 5120 Punkte breit. Alle Displays gleichzeitig zu beleuchten macht
aus einem Zug eine Lichtorgel und verdeckt das Fenster, um das es geht.

**Die kleinste enthaltende Zone gewinnt.** Das Konzept erlaubt überlappende
Zonen. Gewänne die große, wären die kleinen per Maus unerreichbar — die Funktion
wäre kaputt für genau die Layouts, für die es sie gibt.

**Das Angebot nennt die Zone beim Namen.** „Diese App immer hier öffnen?" lässt
offen, was „hier" bei überlappenden Zonen geworden ist. Eine Regel aus einem
Missverständnis ist schlechter als keine Regel.

**Das Angebot ist ein `.nonactivatingPanel`, kein `NSAlert`.** Ein Alert
aktiviert die App und nimmt damit dem gerade platzierten Fenster den Fokus —
eine Geste, nachdem der Nutzer es bewusst irgendwohin gelegt hat.

**Ein Fehler, den die Tests gefunden haben, gehört auch hierher.** `ModifierState`
hatte eine Überladung `contains(_ modifier: DropzoneModifier)`, die intern
`contains(.shift)` aufrief. Der Compiler löste das auf die neue Überladung auf
statt auf `OptionSet.contains`: unendliche Rekursion, SIGBUS in jedem Test, der
die Einstellungen anfasste — und ein Absturz, der über die Ursache nichts sagt.
Die Methode heißt jetzt `holds(_:)`, damit der Fehler nicht wieder möglich ist.

---

## Bedienung

Menüleiste → „Fenster in Zonen ziehen". Der Schalter schreibt
`defaults.dropzones.enabled` über dasselbe `ConfigurationDocument` wie jede
andere Änderung, überlebt also den Neustart und steht in der Datei, die der
Nutzer bearbeitet.

„Platzierung pausieren" schaltet das Ziehen mit ab — unter dem Schalter steht
dann „Ziehen ist nicht aktiv: Die Platzierung ist pausiert", damit niemand
gegen ein Overlay drückt, das nicht kommt.

Konfiguration siehe [`konfiguration.md`](konfiguration.md), Abschnitt
`defaults.dropzones`.

Messen:

```
openzonr dragprobe --seconds 5 --synthesize --out /tmp/dragprobe.txt
```

Ohne `--synthesize` erwartet der Befehl, dass in den Messsekunden von Hand ein
Fenster gezogen wird. Stehen dann bei beiden Wegen null Ereignisse, ist nichts
gemessen worden — dann fehlt die Freigabe oder es wurde nicht gezogen, und keine
Zahl im Bericht trägt eine Aussage. Der Bericht sagt das selbst.
