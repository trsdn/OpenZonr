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

Das Seitenverhältnis der Miniatur ist **nicht mehr fest 16:10**. Ist der zum
gerade bearbeiteten Alias gehörende Bildschirm angeschlossen, kommt das
Verhältnis aus dessen **sichtbarem Rahmen** (`visibleFrame`, nicht `frame`) —
denn Zonen werden ohnehin gegen den sichtbaren Bereich aufgelöst
(`DefaultZoneResolver`). Ist der Bildschirm gerade nicht da, bleibt 16:10 der
Platzhalter — dann steht aber sichtbar an der Vorschau **„Bildschirm nicht
angeschlossen, Seitenverhältnis geschätzt"**. Eine unbeschriftete Schätzung, die
aussieht wie eine Messung, war die Fehlerklasse aus
[#18](https://github.com/trsdn/OpenZonr/issues/18): ein Ultrawide mit 3,81:1
wurde 1,6:1 gezeichnet, `left-quarter` sah aus wie eine schmale Säule und war
in Wahrheit fast quadratisch. Die Auswahl „echte Maße oder Schätzung" liegt als
reine Funktion `canvasAspect(for:snapshots:)` in `OpenZonrCore/Display/` und ist
damit ohne angeschlossenen Bildschirm prüfbar.

Solange echte Maße vorliegen, steht im Zonenformular neben jedem Bruch das
zugehörige Punktmaß — aus `0,25` wird `≙ 1280 pt`. Bei einer Schätzung entfällt
der Zusatz: eine geschätzte Punktzahl neben einer gespeicherten Zahl behauptete
mehr, als sie belegt.

## Was gemessen ist und was nicht

| Behauptung | Stand |
|---|---|
| `swift build` und `swift test` sind grün | **gemessen** — 281 Tests in 31 Suites, headless (zuletzt 274 in 30) |
| Die Editier-Funktionen tun, was sie sollen | **gemessen** — 51 neue Tests in 4 Suites, darunter Reihenfolge, Löschsemantik, Bezeichner-Eindeutigkeit |
| Das Vorschau-Seitenverhältnis kommt aus `visibleFrame`, wenn der Bildschirm da ist | **gemessen** — 7 Tests an `canvasAspect(for:snapshots:)` gegen ein Ultrawide-Fixture (5120×1344), einschließlich Gegenprobe „nicht `frame`", „falscher Bildschirm angeschlossen ≠ stiller Ersatz" und „direkt gebauter `NaN`-Wert wird auf `.estimated` gezwungen" |
| **Ob die Vorschau am echten Bildschirm danach passt** | **nicht gemessen** — die Rechnung ist geprüft, das Bild braucht eine Hand an der Maus |
| Eine umgehängte Regel gewinnt gegen eine später dazugekommene Auffangregel | **gemessen** — Gegenprobe an `DefaultRuleEngine`, und der Fehlerfall vorher bewusst reproduziert (siehe unten) |
| Der Schnellbefehl lehnt ab, statt Wirkung zuzusagen, die ausbleibt | **gemessen** — 4 Tests an `QuickPin.objection(to:report:)`, headless |
| **Ob der Schnellbefehl am echten Menü ablehnt** | **nicht gemessen** — geprüft ist die Entscheidung, nicht ihre Anzeige; es fehlt eine Hand an der Maus, seit dem 29.08.2026 nicht mehr die Freigabe |
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

> **Teilweise überholt am 29.08.2026.** Die Bedienungshilfen-Freigabe ist erteilt,
> und die App liest Fenster — belegt in [docs/tracer-bullet.md](tracer-bullet.md).
> Der ursprüngliche Hinderungsgrund gilt damit **nicht mehr**. Was bleibt, ist ein
> anderer und kleinerer: Menü aufklappen, Knopf drücken, Zone ziehen — das
> verlangt eine Hand an der Maus, keine Berechtigung. Wer diesen Abschnitt liest
> und in den Systemeinstellungen nach einem fehlenden Haken sucht, sucht
> vergeblich. Die Prüfliste am Ende ist unverändert gültig und jetzt
> **durchführbar**.

Der ursprüngliche Grund war derselbe wie in
[docs/menueleisten-app.md](menueleisten-app.md): die
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

**Nachtrag:** #10 ist inzwischen gebaut — [dropzones.md](dropzones.md). Es
benutzt `QuickPin` aus diesem Issue unverändert weiter: Das Angebot „Diese App
immer hier öffnen?" nach einem Ablegen leitet seine Regel über dieselbe
`QuickPin.Request`, die auch der Menüpunkt „Aktuelles Fenster hier festhalten"
erzeugt. Damit gibt es weiterhin genau einen Weg, aus einem Fenster eine Regel
zu machen.

## Dry-Run-Zeile und Übersicht (aus #19)

[Issue #19](https://github.com/trsdn/OpenZonr/issues/19) hat zwei Dinge
angebracht: eine Zeile, die zu einer bearbeiteten Regel sagt, was gerade
passieren würde, und eine Übersicht, die zeigt, welche App in welcher Zone
landet — ohne dass man die Kette Regel → Rolle → Bindung → Zone im Kopf
zusammensetzen muss. Beide sind gebaut, mit unterschiedlicher Beweislage.

### Die Zeile im Regel-Editor

Unter jeder ausgewählten Regel steht eine Zeile mit einem Pfeilsymbol
(Messung) oder einem Fragezeichen (bedingte Auskunft). Der Text kommt aus
`DryRunPreviewFormatter.line(for:subject:configuration:)` in
`OpenZonrCore/Placement/`, die Auswertung selbst aus
`DryRunPreview.evaluate(...)`. Beide sind pur, headless testbar, und werden
von `Tests/OpenZonrCoreTests/DryRunPreview{,Formatter}Tests.swift`
abgesichert.

Die zwei Fälle sind bewusst getrennt:

- **Ein Fenster der App ist offen** — die Zeile ist eine **Messung**. Der
  Snapshot wird durch dieselbe Kette geschickt, die die Platzierung selbst
  benutzt (`DefaultWindowFilter` → `CompiledRuleSet` → `DefaultRuleEngine` →
  `DefaultZoneResolver`). Die Zeile nennt Zone, Bildschirm, Regelname,
  Priorität und Zielrahmen in Punkten.
- **Die App läuft nicht** — die Zeile ist **bedingt**. Sie nennt Regel und
  Rolle, und darunter steht eine kleine Liste unter „Nicht geprüft — die
  Regel prüft es, aber es steht erst am offenen Fenster fest:" mit den
  Kriterien, die ohne Fenster nicht entscheidbar sind. In der real
  existierenden Konfiguration prüfen alle drei Regeln ausschließlich das
  Bundle; die Liste ist dann leer, die Auskunft ist trotzdem als bedingt
  markiert, sobald Fenstertitel, Rolle, Größen, Seitenverhältnis oder
  „nur erstes Fenster" die Auswahl beeinflussen könnten.

Der eigentliche Wert liegt in
`RuleCriteria.report(for:defaults:)` — die Funktion, die einer
`WindowMatch` samt globalen Voreinstellungen ansieht, welche Kriterien
*entscheidbar* und welche *unentscheidbar* sind. Sie ist der Grund, dass
diese Auskunft ehrlich bleibt: ein naiver Dry-Run wäre in der heutigen
Konfiguration zufällig exakt und würde in dem Moment still falsch, in dem
jemand die erste Titelregel oder Größenbedingung anlegt. Die Zeile im
Editor benennt genau dieses „still falsch" — und ist deshalb der Kern des
Nachtrags aus dem Issue-Kommentar.

Die einzige Accessibility-Lesemessung des Editors passiert hier: der
Editor fragt `WindowInventory.allWindows(bundleIdentifier:)`, um Fall A von
Fall B zu unterscheiden. Der Aufruf ist auf die eine aktuell ausgewählte
Regel beschränkt und passiert nicht im Leerlauf.

### Die Übersicht „Wohin geht was?"

Als erster Reiter im Editor (vor Regeln, Rollen & Profile, Zonen) steht ein
Bild aller Bildschirme des gewählten Profils, jeder in seinem
Größenverhältnis. In jeder Zone stehen die Regeln, die dort landen — quer
über die Bindungen des Profils.

Sichtbar wird damit ohne Weiteres:

- Zonen, auf die *nichts* zeigt, werden gezeichnet und tragen „keine Regel
  zeigt hierher". In der real existierenden Konfiguration betrifft das
  z. B. `u28e590-full`; das war ohne Übersicht nur der Konfiguration selbst
  anzusehen, und dazu nur, wenn jemand die Kette bis dorthin verfolgte.
- Die Auffangzone des Profils ist mit „(Auffang)" beschriftet — man sieht
  in einem Blick, ob unerkannte Fenster auf derselben Zone landen wie
  eine benannte Regel (in der heutigen Konfiguration teilt der Auffang die
  Zone mit der TextEdit-Regel).
- Deaktivierte Regeln stehen mit Strichlinie im Namen: sie sind da, aber
  wirken nicht. Sie wegzulassen wäre eine Konfiguration zu zeigen, die es
  so nicht gibt.

Die Zuordnung selbst ist eine reine Funktion, `PlacementOverview.build(for:
configuration:)`, und ist in
`Tests/OpenZonrCoreTests/PlacementOverviewTests.swift` gemessen.

### Was hier bewusst nicht gebaut ist

- **Ziehen eines App-Etiketts in eine andere Zone.** Das griffe in die
  Regel- bzw. Rollenbindung ein und in denselben Zoneneditor, an dem eine
  parallele Sitzung arbeitet. Trennlinie gehalten. Ohne das ist die
  Übersicht ein *Bild*, kein Editor — das gilt es im PR zu benennen.
- **Räumliche Anordnung (links/rechts/oben/unten) im Bild.** Die Übersicht
  zeigt die Bildschirme *nebeneinander*, jeder in seinem *Verhältnis*, mit
  einem Zettel „Nicht gemessen: die räumliche Anordnung". Der Grund: die
  echte Anordnung käme aus den AppKit-Rahmen der `DisplaySnapshot`s und
  müsste auf ein Bild abgebildet werden. Diese Abbildung lebt in
  `Sources/OpenZonrCore/Geometry/`, dessen Verantwortung eine parallele
  Sitzung (Issue #21) hat. Für dieses Feature ist die *Regel-zu-Zone*-Frage
  die dringlichere; die räumliche Anordnung lässt sich später ergänzen,
  ohne die Datei umzukrempeln.

### Nicht gemessen

- Wie der Reiter mit vier Bildschirmen und drei Profilen am Schirm
  aussieht — welche Zonen zu klein für ihr Etikett werden und wie SwiftUI
  in engen Rechtecken umbricht. Ohne Hand an der Maus lässt sich das nicht
  belegen; die Datei enthält deshalb kein UI-Testziel für diesen Reiter.
- Ob der Fragezeichen-Marker für die bedingte Dry-Run-Zeile am Schirm
  besser wirkt als ein alternatives Symbol. Die Wahl beruht auf dem
  Muster der übrigen `Image(systemName:)`-Aufrufe im Editor, nicht auf
  einer Messung.
- Das Verhalten bei einer Konfiguration ohne Profil (kein Auffang, keine
  Bindungen) ist als „kein Layout beschrieben"-Meldung angelegt, aber am
  Schirm ungeprüft.
