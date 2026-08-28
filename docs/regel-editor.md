# Regeln bearbeiten, ohne JSON anzufassen

Dieses Dokument beschreibt den Regel-Editor aus
[#9](https://github.com/trsdn/OpenZonr/issues/9): was er kann, warum er so
gebaut ist, wo er vom Issue abweicht — und, getrennt davon, was gemessen ist und
was nicht.

## Zwei Ebenen

Der Ausgangsschmerz ist ein Satz: „Outlook soll immer in Zone 2 aufgehen." Für
diesen Satz braucht niemand einen Editor, und deshalb gibt es zwei Ebenen.

**Der 90-Prozent-Fall** ist ein Menüeintrag: **„Aktuelles Fenster hier
festhalten"**. Der Nutzer schiebt das Fenster dorthin, wo es hingehört, und
klickt den Eintrag. Im Hintergrund entstehen eine Regel, gegebenenfalls eine
Rolle und eine Bindung im aktiven Profil. Keiner dieser drei Begriffe kommt
dabei vor. Rückmeldung ist ein Satz im Menü, etwa „Regel „Safari → Mitte"
angelegt, Priorität 10."

**Der Editor** ist für den Rest: drei Bereiche in einem Fenster —
Regeln, Rollen & Profile, Zonen.

## Abweichung vom Issue: kein Rechtsklick auf das Fenster

Das Issue beschreibt den 90-Prozent-Fall als **Rechtsklick auf ein platziertes
Fenster**. Das ist mit öffentlichen APIs nicht erreichbar, und zwar aus zwei
unabhängigen Gründen:

1. Ein Kontextmenü im Fenster einer fremden App müsste in deren eigene
   Ereignisbehandlung eingehängt werden. macOS bietet keinen unterstützten Weg,
   einem anderen Prozess einen Menüeintrag hinzuzufügen; die Accessibility-API
   kann Fenster lesen und bewegen, aber keine Menüs beisteuern.
2. Der Ausweg wäre ein transparentes Fenster über allen Bildschirmen, das
   Rechtsklicks abfängt. Es würde Klicks schlucken, die der App darunter
   gehören, und bräuchte zusätzlich zur Bedienungshilfen-Freigabe eine
   Bildschirmaufnahme-Freigabe.

Der gewählte Weg hat dasselbe Ergebnis mit derselben Eingabe — diese App, dieser
Ort — und kostet eine Mausbewegung mehr. Die Begründung steht als Kommentar auch
im Quelltext (`Sources/OpenZonrMac/Accessibility/FrontmostWindow.swift`), damit
sie beim Lesen des Codes nicht gesucht werden muss.

## Wo die Logik liegt

Die gesamte Editier-Logik liegt als **pure Funktionen** in `OpenZonrCore`
(`Sources/OpenZonrCore/Editing/`), nicht in der Oberfläche. Das ist keine
Stilfrage, sondern die Bedingung dafür, dass dieser Teil überhaupt beweisbar
ist: die Bedienungshilfen-Freigabe lässt sich nicht automatisieren, eine
Konfiguration zu laden, zu ändern, zu validieren, zu schreiben und wieder zu
laden dagegen vollständig.

| Datei | Aufgabe |
|---|---|
| `ConfigurationEditing.swift` | Alle Änderungen an der Konfiguration als `Configuration -> Configuration` |
| `QuickPin.swift` | Der 90-Prozent-Fall: aus App + Ziel werden Regel, Rolle und Bindung |
| `PinTargetResolver.swift` | Geometrie für „hier": Fensterrahmen → Bildschirm + Zone |
| `FindingIndex.swift` | Validierungsbefunde nach `ConfigurationPath` adressierbar |
| `Identifiers.swift` | Lesbare, kollisionsfreie Bezeichner aus deutschen Namen |

Die Oberfläche (`Sources/OpenZonrApp/Editor/`) ruft nur diese Funktionen auf und
schreibt ausschließlich über `ConfigurationStore.save(_:to:)` — atomar und mit
Migration. Es gibt keinen zweiten Schreibweg.

## Entscheidungen, die nicht offensichtlich sind

### Die Liste ist die Wahrheit, nicht ihr Abbild

Die Engine wertet Regeln nach `priority` absteigend aus, bei Gleichstand in
Dateireihenfolge. Der Editor zeigt genau diese Reihenfolge. Wird eine Regel
verschoben, werden die Prioritäten in Schritten von 10 **neu vergeben** — sonst
zeigt die Liste eine Reihenfolge, nach der die Engine nicht arbeitet.

Beim bloßen Öffnen der Datei passiert das ausdrücklich **nicht**. Ein Fenster zu
öffnen darf keinen Diff erzeugen.

### Löschen ist absichtlich asymmetrisch

Wird eine **Rolle** gelöscht, verschwinden ihre Bindungen mit — eine Bindung auf
eine unbekannte Rolle prüft der Validator nicht, sie wäre totes Gewicht. Die
**Regeln**, die diese Rolle nennen, bleiben stehen: dafür gibt es den Check
`unknownRoleInRule`, und er zeigt dem Nutzer genau die Regeln, die jetzt eine
Entscheidung brauchen. Ebenso bleiben Bindungen auf eine gelöschte **Zone**
stehen und erzeugen `unknownZoneInBinding`.

Kurz: gelöscht wird, was stumm verschwinden kann; stehen bleibt, was gemeldet
wird.

### Priorität beim Festhalten

Konkurrenz sind alle **aktivierten** Regeln **ohne Titelmuster**, die dieselbe
App treffen könnten. Die neue Regel bekommt deren höchste Priorität + 10, ohne
Konkurrenz 10.

Regeln **mit** Titelmuster zählen nicht mit. Eine von Hand geschriebene Regel
wie „Outlook-Fenster mit Titel `^Verfassen`" ist spezifischer als „Outlook", und
sie soll ihren Vorrang behalten. Regeln fremder Apps zählen ebenfalls nicht mit,
damit die Zahlen nicht mit jeder Nutzung wachsen.

### Zweimal festhalten hängt um, statt zu verdoppeln

Eine bestehende Regel wird wiederverwendet, wenn sie **ausschließlich** über die
Bundle-Kennung trifft — kein Titelmuster, keine Rollen, keine Größen, kein
Seitenverhältnis. Das ist die Form, die diese Funktion selbst schreibt. War sie
abgeschaltet, wird sie wieder eingeschaltet: „hier festhalten" auf eine
deaktivierte Regel als „nichts passiert" zu beantworten wäre ein stiller Fehler.

Eine Regel, die der Nutzer von Hand verfeinert hat, wird nie überschrieben.

**Und sie steigt, wenn sie sonst überdeckt bliebe.** Aus einer Durchsicht kam
der Befund, dass das Umhängen die Priorität unangetastet ließ. Kam nach dem
ersten Festhalten eine Auffangregel mit höherer Priorität dazu, war die
angeheftete Regel überdeckt und feuerte nie — der Nutzer las „zeigt jetzt auf
Zone 2", das Fenster ging weiter woanders auf. Dasselbe beim Wiedereinschalten
einer abgeschalteten Regel. Beim Umhängen wird die Priorität deshalb angehoben,
wenn eine konkurrierende Regel gleich hoch oder höher steht.

Gleichstand zählt mit Absicht als Konkurrenz: bei gleicher Priorität entscheidet
die Reihenfolge in der Datei, und die kann der Nutzer über einen Menüeintrag
weder sehen noch beeinflussen. Ohne Konkurrenz bleibt die Zahl unverändert —
sonst wüchse sie bei jedem Klick um 10.

### Auch der Schnellbefehl validiert

Der Menüeintrag lief zunächst am `ConfigurationDocument` vorbei in den Store,
wenn das Editor-Fenster geschlossen war — also lief der häufigste Fall über den
einzigen ungeprüften Pfad und meldete trotzdem Erfolg. Er läuft jetzt **immer**
über ein Dokument; ist der Editor zu, ist es ein kurzlebiges.

Anders als der Editor hat der Schnellbefehl kein Feld, unter das er einen Befund
hängen könnte: er sagt einen Satz und verschwindet. Also muss er ablehnen können.
`QuickPin.objection(to:report:)` entscheidet das, und zwar im Kern statt in der
Oberfläche — dadurch ist die Ablehnung ohne Bedienungshilfen-Freigabe beweisbar.
Es widersprechen genau zwei Dinge: jeder Fehler irgendwo, und eine
`shadowedRule`-Warnung an genau dieser Regel. Auf jede Warnung abzulehnen würde
die Funktion unbenutzbar machen.

### Fehler stehen am Feld

`ConfigurationValidator` liefert jeden Befund mit `ConfigurationPath` und
Schweregrad. `FindingIndex` indiziert sie nach **Pfad-Komponenten**, nicht nach
gerenderten Zeichenketten — `rules[a]` ist ein Zeichenpräfix von `rules[ab]`,
aber eine andere Regel. So steht die Meldung unter dem Feld, das sie betrifft,
und die Zeile in der Liste trägt ein Abzeichen für alles, was in ihr steckt.

Eine Ausnahme gibt es: die Eindeutigkeits-Checks melden über die **Position**
(`rules[2].id`), weil bei zwei gleichen Bezeichnern gerade der Bezeichner nicht
adressieren kann. Solche Befunde beansprucht kein Feld. Sie stehen deshalb in
einer schmalen Leiste über der Sicherungszeile — über `findings(notUnder:)`
ermittelt, nicht per Hand gepflegt, damit kein Befund unsichtbar wird.

### Zonen werden gezogen, nicht getippt

Zonen sind Bruchteile des sichtbaren Bereichs. Das ist das richtige Modell und
das falsche Eingabefeld: `0.5 / 0 / 0.5 / 1` ist ein Satz über die rechte
Hälfte, den niemand als solchen liest. Der Editor zeigt ein Miniaturbild des
Bildschirms mit den Zonen als Rechtecken.

Beim Loslassen wird auf **Zwölftel** gerastet und in das Einheitsquadrat
geklemmt. Zwölftel, weil Hälften, Drittel und Viertel alle darauf fallen — so
schließen die üblichen Aufteilungen lückenlos. Eine Fuge von zwei Pixeln
zwischen zwei Zonen ist im Editor unsichtbar und auf dem Bildschirm sehr
sichtbar. Die Zahlenfelder bleiben daneben stehen, für die Fälle, in denen eine
Zone exakt zu einer Zone auf einem anderen Bildschirm passen muss.

Das Seitenverhältnis der Miniatur ist fest 16:10 und **keine Messung**: das
echte Verhältnis eines Bildschirms ist nur bekannt, solange er angeschlossen
ist, und der Editor muss auch für einen abgezogenen Monitor funktionieren.

## Was gemessen ist und was nicht

| Behauptung | Stand |
|---|---|
| `swift build` und `swift test` sind grün | **gemessen** — 207 Tests in 21 Suites, headless (vorher 156 in 17) |
| Die Editier-Funktionen tun, was sie sollen | **gemessen** — 51 neue Tests in 4 Suites, darunter Reihenfolge, Löschsemantik, Bezeichner-Eindeutigkeit |
| Eine umgehängte Regel gewinnt gegen eine später dazugekommene Auffangregel | **gemessen** — Gegenprobe an `DefaultRuleEngine`, und der Fehlerfall vorher bewusst reproduziert (siehe unten) |
| Der Schnellbefehl lehnt ab, statt Wirkung zuzusagen, die ausbleibt | **gemessen** — 4 Tests an `QuickPin.objection(to:report:)`, headless |
| **Ob der Schnellbefehl am echten Menü ablehnt** | **nicht gemessen** — `AppModel` braucht die Freigabe; geprüft ist die Entscheidung, nicht ihre Anzeige |
| `PinTargetResolver` ist die Umkehrung von `DefaultZoneResolver` | **gemessen** — Rundlauftest gegen den echten Resolver, nicht gegen handgerechnete Zahlen |
| Der 90-Prozent-Fall erzeugt eine Regel, die die Engine auch wählt | **gemessen** — Gegenprobe an `DefaultRuleEngine` im Test und am echten Konfigurationsstand, siehe unten |
| Rundlauf gegen die **echte** Konfiguration des Nutzers | **gemessen** — auf einer Kopie, Original unverändert; Zahlen unten |
| Befunde landen am richtigen Feld | **gemessen** — `FindingIndex` gegen echte Validator-Ausgaben, inklusive des Falls „Befund, den kein Feld beansprucht" |
| **Ob der Editor auf dem Bildschirm bedienbar ist** | **nicht gemessen** — Begründung unten |
| **Ob „Aktuelles Fenster hier festhalten" am echten Fenster funktioniert** | **nicht gemessen** — Begründung unten |
| **Ob eine gezogene Zone am echten Bildschirm richtig sitzt** | **nicht gemessen** — dieselbe Begründung |

### Der reproduzierte Fehlerfall

Ein grüner Test beweist wenig, wenn er auch ohne die Korrektur grün wäre. Für den
Befund aus der Durchsicht wurde die Korrektur in `QuickPin` deshalb einmal
vorübergehend außer Kraft gesetzt. Ergebnis, bevor sie zurückkam:

```
✘ Eine umgehängte Regel steigt über eine dazugekommene Auffangregel
    (rule.priority → 10) > 500
    (after?.id → catch-all) == (outcome.rule → editor-rule)
    (shadowed → [warning shadowedRule at rules[editor-rule]:
     Die Regel editor-rule wird vollständig von Regel catch-all überdeckt.])
✘ Auch bei Gleichstand steigt die umgehängte Regel
✘ Eine wiedereingeschaltete Regel, die überdeckt war, greift danach wirklich
```

Die dritte Zeile ist der Kern: `RuleHygieneCheck` kannte den Befund die ganze
Zeit, er wurde auf diesem Pfad nur nie erhoben.

### Der gemessene Rundlauf

Ein Wegwerf-Programm gegen eine **Kopie** von
`~/Library/Application Support/OpenZonr/config.json`, ohne jede Freigabe:

```
1 geladen: 2 Regeln, 2 Rollen, 1 Profile, 2 Displays
2 Validierung vorher: 0 Befunde, nutzbar=true
3 Ziel: Profil Schreibtisch, Display c49rg9x, Zone center-half (Mitte)
4 QuickPin: Regel „Safari → Mitte“ angelegt, Priorität 10. |
  Regel=safari Rolle=mail neueRolle=false wiederverwendet=false
5 Validierung nachher: 0 Befunde, nutzbar=true
  Befunde an rules[safari]: 0
6 zurückgelesen: identisch=true, Regeln=3
7 Regelauswahl für Safari: safari
8 Bindung: mail → c49rg9x/center-half
9 Quelle unverändert: true
```

Bemerkenswert ist Zeile 4: `neueRolle=false`. Die Rolle `mail` zeigte im Profil
„Schreibtisch" bereits auf genau diese Zone, also wurde sie wiederverwendet
statt eine zweite Rolle für denselben Platz anzulegen. Zeile 7 ist die
eigentliche Gegenprobe — die Engine wählt für ein Safari-Fenster tatsächlich die
Regel, die entstanden ist.

### Warum die Oberfläche nicht nachgemessen wurde

Aus demselben Grund wie in [docs/menueleisten-app.md](menueleisten-app.md): die
Bedienungshilfen-Freigabe für `~/Applications/OpenZonr.app` muss der Nutzer von
Hand erteilen, und der Bereich „Bedienungshilfen" der Systemeinstellungen
liefert weder einen Accessibility-Baum noch ein Bildschirmfoto — beides bleibt
schwarz. Das ist geprüft und nicht umgehbar.

Ohne diese Freigabe liest die App kein einziges Fenster. Damit lässt sich
„Aktuelles Fenster hier festhalten" nicht auslösen und die Wirkung einer
gezogenen Zone nicht am echten Bildschirm prüfen. Der Editor selbst ließe sich
zwar öffnen, aber ohne geladene Fenster ist das eine halbe Messung, die mehr
suggeriert als sie zeigt.

Die Verifikation ist deshalb bewusst dorthin gelegt, wo sie ohne Freigabe
vollständig ist: in die pure Schicht darunter. Was zwischen `QuickPin` und dem
Pixel auf dem Bildschirm liegt — Accessibility lesen, Frame drehen, Fenster
setzen — ist die Kette aus [docs/tracer-bullet.md](tracer-bullet.md), und die
ist dort am echten Fenster gemessen.

Was nach der Freigabe zuerst zu prüfen wäre:

1. Menü öffnen, ein Safari-Fenster nach vorne, „Aktuelles Fenster hier
   festhalten" — kommt die erwartete Meldung, steht die Regel in der Datei?
2. Safari beenden und neu starten — landet das Fenster in der Zone?
3. Eine Zone im Editor ziehen, sichern, App neu starten — sitzt das Fenster an
   der neuen Stelle?

Diese Schritte müssen aus dem Bundle laufen, dem die Freigabe erteilt wurde —
`~/Applications/OpenZonr.app`, gebaut über `Scripts/bundle.sh`. Nicht aus
`swift run`: die Freigabe bindet an das Bundle an seinem Pfad, und ein
unsignierter Neubau bekommt eine neue Prüfsumme und wird nicht mehr erkannt.
Der Haken bliebe gesetzt und wäre wirkungslos — das ist in
[docs/menueleisten-app.md](menueleisten-app.md) gemessen. Wer das übersieht,
misst eine Stunde lang nichts und hält es für einen Fehler im Editor.

## Grenze zu #10

Der Zoneneditor zeichnet Zonen und lässt sie ziehen. Das ist **nicht** die
Dropzone-Funktion aus
[#10](https://github.com/trsdn/OpenZonr/issues/10): dort geht es darum, ein
Fenster mit der Maus in eine eingeblendete Zone zu ziehen. Hier wird nur die
Konfiguration bearbeitet, es wird kein Fenster bewegt und nichts eingeblendet.
An #10 wurde nichts vorweggenommen.
