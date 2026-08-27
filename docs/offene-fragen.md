# Offene Fragen

Entscheidungen, die für den Konzeptstand bewusst offen geblieben sind, sowie
Abweichungen vom ursprünglich diskutierten Modell. Jede Frage nennt die Optionen
und, wo vorhanden, eine Tendenz — aber keine Festlegung.

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

## 7. Verteilung und Signierung

Der Accessibility-Grant hängt an der Code-Signatur. Eine unsignierte App verliert
ihn bei jedem Update, was in der Praxis unbenutzbar ist.

- **Notarisierte Direktverteilung** (Developer ID) — funktioniert, setzt aber eine
  kostenpflichtige Entwicklermitgliedschaft voraus.
- **App Store** — scheidet praktisch aus: die Accessibility-API ist mit dem
  App-Sandbox nicht vereinbar.
- **Selbst gebaut aus dem Quellcode** — für Entwickler in Ordnung, aber jeder
  Neubau erfordert eine neue Erteilung der Berechtigung.

Damit verbunden: ob und wie ein automatischer Update-Mechanismus eingebaut wird.

---

## 8. Zonenkonfiguration und Editor

Offen ist, wie Zonen tatsächlich gezeichnet werden: freies Zeichnen auf einer
Vorschau des Bildschirms, ein Raster mit einrastenden Kanten, oder mitgelieferte
Vorlagen (Hälften, Drittel, 25/50/25), die anschließend angepasst werden können.

Ebenfalls offen: ob Zonenränder und Abstände (Gaps) konfigurierbar sein sollen.
Das Datenmodell sieht sie derzeit nicht vor, weil sich Abstände auch als
prozentuale Ränder in den Zonen selbst ausdrücken lassen — nur eben umständlich.

---

## Abweichungen vom ursprünglich diskutierten Modell

Zur Nachvollziehbarkeit festgehalten:

| Abweichung | Begründung |
|---|---|
| **SwiftPM-Package statt Xcode-Projekt** | Der aktuelle Stand ist reines Datenmodell und lässt sich so headless mit `swift build` / `swift test` prüfen; das Manifest ist Text und damit reviewbar. Die App-Hülle mit Entitlements und Signierung kommt später als Xcode-Target hinzu, das `OpenZonrCore` einbindet. |
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
