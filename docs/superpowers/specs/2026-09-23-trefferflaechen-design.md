# Trefferflächen: Auslösefläche getrennt vom Zielrahmen

**Stand:** 23.09.2026 · **Zustand:** entworfen, nicht gebaut

## Das Problem, gemessen

Auf dem C49RG9x (5120×1440) des Autors liegt die Ebene `c49rg9x-three-columns`
mit fünf Zonen. Drei davon stapeln sich:

| Zone | x | Breite | y | Höhe | rel. Fläche |
|---|---|---|---|---|---|
| Links außen | 0 | 0,25 | 0 | 1 | 0,250 |
| Mitte | 0,25 | 0,417 | 0 | 1 | 0,417 |
| **Rechts außen** | 0,667 | 0,333 | 0 | 1 | **0,333** |
| Rechts oben | 0,667 | 0,333 | 0 | 0,5 | 0,167 |
| Rechts unten | 0,667 | 0,333 | 0,5 | 0,5 | 0,167 |

„Rechts außen" wird von „Rechts oben" und „Rechts unten" lückenlos überdeckt.
`DropzoneMap.zone(at:)` lässt die **kleinste** enthaltende Zone gewinnen
(`Sources/OpenZonrCore/Dropzone/DropzoneMap.swift:131`). Jeder Punkt in „Rechts
außen" liegt damit auch in einer der beiden Hälften, und die sind kleiner:

**„Rechts außen" ist per Maus nicht erreichbar.** Nicht schwer zu treffen —
unerreichbar.

## Warum das keine Regelfrage ist

Der Kommentar an `DropzoneMap.swift:123` begründet *kleinste gewinnt* damit,
dass sonst die Hälften unerreichbar wären. Das stimmt. Aber es zeigt zugleich,
dass keine Regel das Problem lösen kann: solange **ein** Rechteck zugleich
Zielrahmen und Trefferfläche ist, sind die Punkte eines Stapels unteilbar. Wer
auch immer gewinnt — die andere Ebene verliert vollständig.

`Layout` (`Sources/OpenZonrCore/Geometry/Zone.swift:41`) nennt gestapelte Zonen
ausdrücklich „a legitimate design". Das Modell hält dieses Versprechen heute
nicht ein.

Magnet und Rectangle Pro trennen deshalb zwei Rechtecke: *wohin das Fenster
kommt* und *wo man loslassen muss*. Erst diese Trennung macht einen Stapel
auflösbar, weil die Trefferflächen disjunkt sein können, auch wenn die
Zielrahmen es nicht sind.

## Entscheidungen

Getroffen im Gespräch am 23.09.2026:

1. **Bezug: bildschirmbezogen, nicht zonenbezogen.** Die Trefferfläche ist ein
   eigenes Rechteck im selben Koordinatenraum wie der Zielrahmen und muss
   *nicht* in ihm liegen. Damit ist Randauslösung möglich („am linken Rand
   loslassen → Fenster landet rechts"). Der Fall „innerhalb der Zone" bleibt
   möglich; man zeichnet sie eben hinein.
   *Preis:* eine Trefferfläche kann ins Leere zeigen. Dagegen steht ein
   Prüfhinweis, kein Verbot.

2. **Fehlt die Trefferfläche, ist sie der Zielrahmen.** Erzwungen durch
   Verträglichkeit: jede bestehende Konfiguration verhält sich unverändert.

3. **Bei überlappenden Trefferflächen gilt weiter: die kleinste gewinnt.** Keine
   neue Rangordnung, kein Prioritätsfeld. Die bestehende Regel wird nur auf das
   richtige Rechteck angewandt.

4. **Overlay: Trefferflächen dezent, Zielrahmen beim Treffer.** Alle
   Trefferflächen der Ebene als dünne Kontur, damit sichtbar ist, wohin man
   zielen kann; die getroffene Zone zeigt ihren **Zielrahmen** gefüllt, damit
   sichtbar ist, wo das Fenster landet.

## Datenmodell

`Zone` (`Sources/OpenZonrCore/Geometry/Zone.swift:14`):

```swift
public struct Zone: Codable, Hashable, Sendable, Identifiable {
    public var id: ZoneID
    public var name: String
    /// Wohin das Fenster kommt. Relativ zum sichtbaren Rahmen des Displays.
    public var frame: RelativeRect
    /// Wo losgelassen werden muss. Derselbe Raum wie `frame`.
    /// `nil` heisst: der Zielrahmen selbst.
    public var activationArea: RelativeRect?
}
```

In JSON:

```json
{
  "id": "right-quarter",
  "name": "Rechts außen",
  "frame":          { "x": 0.667, "y": 0,   "width": 0.333, "height": 1   },
  "activationArea": { "x": 0.667, "y": 0.4, "width": 0.333, "height": 0.2 }
}
```

**Kein Schemawechsel.** `Configuration.currentVersion`
(`Sources/OpenZonrCore/Configuration/Configuration.swift:165`) bleibt bei `1`.
Ein optionales Feld dekodiert aus einer Datei, die es nicht enthält; der
Migrator hat heute keine Schritte und bekommt auch keinen.

`Dropzone` (`DropzoneMap.swift:8`) bekommt das absolute Gegenstück:

```swift
public var activationFrame: WindowFrame   // = frame, wenn keine gesetzt ist
```

gerechnet mit `ZoneGeometry.absoluteFrame(for:in:)`
(`Sources/OpenZonrCore/Placement/ZoneGeometry.swift:18`), genau wie `frame`. Der
`margin` wirkt auf die Trefferfläche **nicht** — er ist ein Platzierungsrand
(siehe `Zone.swift:46`), und eine Trefferfläche zu schrumpfen, die der Nutzer
selbst gezeichnet hat, wäre Bevormundung.

## Treffertest

`DropzoneMap.zone(at:)` prüft `activationFrame` statt `frame`. Alles andere
bleibt: kleinste Fläche gewinnt, Gleichstand über Display-Alias und dann
Zonen-ID, nie über die Reihenfolge im Array.

`DropzoneMap.pinBadgeFrame(for:)` (`DropzoneMap.swift:189`) rechnet künftig mit
der **Trefferfläche** statt mit dem Zielrahmen. Begründung: der Anheft-Punkt ist
das zweite Ziel derselben Mausbewegung. Bei Randauslösung läge er sonst am
anderen Ende des Bildschirms und wäre unbenutzbar.

**Folge, die ausgesprochen gehört:** die Funktion gibt heute schon `nil` zurück,
wenn die Zone zu klein für Rand, Abstand, Marke und einen verbleibenden Streifen
zum gewöhnlichen Loslassen ist — zusammen `4·2 + 8·2 + 24 + 24 = 72` Punkte in
der kleineren Kante. Wer eine Trefferfläche kleiner als das zeichnet, bekommt
für diese Zone **keinen Anheft-Punkt** mehr; das Loslassen zum Platzieren
funktioniert weiter, die Regel muss dann über das Menü entstehen. Das ist
hinnehmbar und ausdrücklich kein Fehler — aber der Editor sollte es später
sichtbar machen.

`DropzoneMap.zones(onDisplayUnder:)` bleibt unverändert — es fragt nach dem
Display, nicht nach der Zone.

## Overlay

`DropzoneOverlayPlan.show` führt künftig beides: die Zonen der Ebene (für die
Konturen ihrer Trefferflächen) und die getroffene Zone (für den gefüllten
Zielrahmen). `DropzoneOverlay` zeichnet entsprechend.

Nachzuziehen ist die Begründung des `margin` in `Zone.swift:49`: „damit sieht
man Luft zwischen den Fenstern und zieht trotzdem über eine geschlossene
Fläche". Mit eigenen Trefferflächen ist die Fläche nicht mehr geschlossen — das
ist gewollt und gehört so im Kommentar.

## Prüfung

Zwei neue Befunde in `ConfigurationStore`:

* **Warnung — Zone unerreichbar.** Genau formuliert: die Trefferfläche einer
  Zone `Z` ist vollständig von der **Vereinigung** der Trefferflächen jener
  Zonen derselben Ebene überdeckt, die der Treffertest `Z` vorzieht — also
  kleinere Fläche, oder gleiche Fläche und früher in der Ordnung aus
  Display-Alias und Zonen-ID. Dann gibt der Treffertest `Z` für keinen Punkt
  zurück.

  Die Vereinigung ist der Kern: „Rechts außen" wird von *keiner* einzelnen Zone
  überdeckt, sondern erst von „Rechts oben" **und** „Rechts unten" zusammen. Eine
  Prüfung, die nur paarweise vergleicht, fände den Fall des Autors nicht.

  Der Befund nennt die Zone beim Namen. Für die heutige Konfiguration des Autors
  muss er genau `right-quarter` melden.

* **Hinweis — Trefferfläche zeigt ins Leere.** Die Trefferfläche liegt ganz
  außerhalb des sichtbaren Rahmens, oder sie überschneidet den eigenen
  Zielrahmen nicht. Kein Fehler: freie Platzierung ist der Sinn der
  Entscheidung 1. Aber häufiger ein Tippfehler als eine Absicht.

Die Überdeckungsprüfung ist reine Geometrie über Rechtecke einer Ebene und
braucht weder Display noch Bedienungshilfen — sie ist headless prüfbar.

## Tests

Test zuerst, rot bestätigt, dann Implementierung.

| Beleg | Was er festhält |
|---|---|
| Gestapelte Zonen mit disjunkten Trefferflächen | jede Ebene einzeln erreichbar — der eigentliche Zweck |
| Zone ohne `activationArea` | verhält sich bit-genau wie heute (Rückfallschutz für alle bestehenden Konfigurationen) |
| Die echte Ebene des Autors als Fixture | Prüfung meldet `right-quarter` als unerreichbar |
| Trefferfläche ausserhalb des Zielrahmens | Treffer gilt, Zielrahmen bleibt der entfernte (Randauslösung) |
| Anheft-Punkt | sitzt an der Trefferfläche, nicht am Zielrahmen |
| Trefferfläche unter 72 Punkten | kein Anheft-Punkt (`nil`), Platzieren geht weiter |
| Überdeckung nur durch **Vereinigung** zweier Zonen | Prüfung meldet sie trotzdem — paarweiser Vergleich reichte nicht |
| Overlay-Plan | Konturen für alle Zonen der Ebene, Füllung für die getroffene |
| Gleichstand zweier gleich grosser Trefferflächen | weiterhin über Display und Zonen-ID, nicht über Array-Reihenfolge |

## Nicht in diesem Vorhaben

* **Der Editor.** Zonen bequemer anlegen ist der zweite Durchgang und setzt
  dieses Modell voraus. Bis dahin entstehen Trefferflächen von Hand im JSON.
* **Automatisches Ableiten** von Trefferflächen aus einem Stapel. Wäre Raterei;
  der Nutzer soll sagen, wo er loslassen will.
* **Monitor-Bindung, Profile, Rollen.** Funktionieren und bleiben unangetastet.

## Was hier nicht behauptet wird

Dass die Randauslösung sich gut anfühlt. Sie ist möglich, sobald der Bezug
bildschirmbezogen ist — ob sie im Gebrauch taugt, ist ungemessen, und das Modell
zwingt niemanden dazu.

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `Sources/OpenZonrCore/Geometry/Zone.swift` | Feld `activationArea`, Kommentar zum `margin` |
| `Sources/OpenZonrCore/Dropzone/DropzoneMap.swift` | `activationFrame`, Treffertest, Anheft-Punkt |
| `Sources/OpenZonrCore/Dropzone/DropzoneOverlayPlan.swift` | Plan trägt Trefferflächen und getroffenen Zielrahmen |
| `Sources/OpenZonrApp/Dropzone/DropzoneOverlay.swift` | Kontur + Füllung zeichnen |
| `Sources/OpenZonrCore/Configuration/ConfigurationStore.swift` | zwei Befunde |
| `docs/dropzones.md`, `docs/konfiguration.md` | Begriff und JSON-Feld |
