# Trefferflächen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eine Zone bekommt eine Trefferfläche, die vom Zielrahmen getrennt ist, damit gestapelte Zonen einzeln erreichbar werden.

**Architecture:** Ein optionales Feld `activationArea` an `Zone` (bildschirmbezogen, wie `frame`), sein absolutes Gegenstück `activationFrame` an `Dropzone`, und ein Treffertest, der statt `frame` künftig `activationFrame` prüft. Die Regel *kleinste gewinnt* bleibt unverändert — sie wird nur auf das richtige Rechteck angewandt. Dazu ein Prüfschritt, der Zonen meldet, die durch die **Vereinigung** anderer Trefferflächen unerreichbar werden.

**Tech Stack:** Swift 6, SwiftPM, Swift Testing (`@Suite`/`@Test`/`#expect`), AppKit nur im Zeichenteil.

**Spec:** `docs/superpowers/specs/2026-09-23-trefferflaechen-design.md`

## Global Constraints

- Sprache der Kommentare und Nutzertexte: **Deutsch**, wie im übrigen Projekt. Bestehende englische Doc-Kommentare bleiben englisch; neue folgen der Datei, in der sie stehen.
- `Configuration.currentVersion` bleibt **`1`**. Kein Migrationsschritt.
- Jede bestehende Konfiguration ohne `activationArea` muss sich **bit-genau wie heute** verhalten.
- Koordinaten: `RelativeRect` ist `0…1` mit Ursprung **oben links**; `WindowFrame` ist absolut in **AppKit**-Koordinaten mit Ursprung **unten links**. Die Umrechnung macht ausschliesslich `ZoneGeometry.absoluteFrame(for:in:)`.
- Kantenregel unverändert: `WindowFrame.contains` ist links/unten inklusiv, rechts/oben exklusiv (`ZoneGeometry.swift:80`).
- TDD: erst der rote Test, dann die Implementierung. Bau muss **ohne Warnungen** durchlaufen.
- Ausgangslage: 589 Tests grün auf `main` (Stand `b4afc97`).

---

## File Structure

| Datei | Verantwortung |
|---|---|
| `Sources/OpenZonrCore/Geometry/Zone.swift` | Feld `activationArea` am Modell |
| `Sources/OpenZonrCore/Dropzone/DropzoneMap.swift` | `activationFrame`, Treffertest, Anheft-Punkt |
| `Sources/OpenZonrCore/Geometry/RectangleCoverage.swift` | **neu** — reine Geometrie: wird ein Rechteck von einer Menge Rechtecke überdeckt? |
| `Sources/OpenZonrCore/Validation/Checks/ZoneReachabilityCheck.swift` | **neu** — Befunde „unerreichbar" und „zeigt ins Leere" |
| `Sources/OpenZonrCore/Validation/ValidationFinding.swift` | zwei neue Codes, beide `warning` |
| `Sources/OpenZonrCore/Validation/ConfigurationValidator.swift` | den neuen Check registrieren |
| `Sources/OpenZonrApp/Dropzone/DropzoneOverlay.swift` | Kontur der Trefferflächen, Füllung des getroffenen Zielrahmens |
| `docs/dropzones.md`, `docs/konfiguration.md` | Begriff und JSON-Feld |

`DropzoneOverlayPlan` bleibt **unverändert**: `Plan.show(zones:highlighted:)` trägt bereits alles, weil jede `Dropzone` ihre eigene Trefferfläche mitbringt. Das ist kein Zufall, sondern der Grund, das Feld an `Dropzone` zu hängen statt an den Plan.

---

### Task 1: Feld `activationArea` am Modell

**Files:**
- Modify: `Sources/OpenZonrCore/Geometry/Zone.swift:14-25`
- Test: `Tests/OpenZonrCoreTests/ZoneActivationAreaTests.swift` (neu)

**Interfaces:**
- Consumes: nichts
- Produces: `Zone.activationArea: RelativeRect?`, `Zone.init(id:name:frame:activationArea:)` mit `activationArea: RelativeRect? = nil`

- [ ] **Step 1: Write the failing test**

`Tests/OpenZonrCoreTests/ZoneActivationAreaTests.swift`:

```swift
import Foundation
import Testing

@testable import OpenZonrCore

/// Die Trefferfläche ist optional und bildschirmbezogen — derselbe Raum wie
/// ``Zone/frame``. Fehlt sie, ist sie der Zielrahmen; bestehende
/// Konfigurationen verhalten sich dadurch unverändert.
@Suite("Zone — Trefferfläche")
struct ZoneActivationAreaTests {

    @Test("Ohne Feld im JSON bleibt die Trefferfläche nil")
    func decodesMissingActivationAreaAsNil() throws {
        let json = """
        {"id":"links","name":"Links","frame":{"x":0,"y":0,"width":0.5,"height":1}}
        """
        let zone = try JSONDecoder().decode(Zone.self, from: Data(json.utf8))

        #expect(zone.activationArea == nil)
        #expect(zone.frame == RelativeRect(x: 0, y: 0, width: 0.5, height: 1))
    }

    @Test("Mit Feld im JSON wird die Trefferfläche gelesen")
    func decodesActivationArea() throws {
        let json = """
        {"id":"links","name":"Links",
         "frame":{"x":0,"y":0,"width":0.5,"height":1},
         "activationArea":{"x":0,"y":0.4,"width":0.5,"height":0.2}}
        """
        let zone = try JSONDecoder().decode(Zone.self, from: Data(json.utf8))

        #expect(zone.activationArea == RelativeRect(x: 0, y: 0.4, width: 0.5, height: 0.2))
    }

    @Test("Hin und zurück durch JSON verliert nichts")
    func roundTrips() throws {
        let zone = Zone(
            id: ZoneID(rawValue: "rechts"),
            name: "Rechts",
            frame: RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1),
            activationArea: RelativeRect(x: 0.9, y: 0, width: 0.1, height: 1)
        )

        let data = try JSONEncoder().encode(zone)
        #expect(try JSONDecoder().decode(Zone.self, from: data) == zone)
    }

    @Test("Ohne Trefferfläche bleibt das Feld beim Kodieren weg")
    func omitsNilActivationArea() throws {
        let zone = Zone(
            id: ZoneID(rawValue: "links"),
            name: "Links",
            frame: RelativeRect(x: 0, y: 0, width: 0.5, height: 1)
        )

        let text = String(decoding: try JSONEncoder().encode(zone), as: UTF8.self)
        #expect(text.contains("activationArea") == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "Zone — Trefferfläche"`
Expected: Compile-Fehler, `extra argument 'activationArea' in call` bzw. `value of type 'Zone' has no member 'activationArea'`.

- [ ] **Step 3: Write minimal implementation**

In `Sources/OpenZonrCore/Geometry/Zone.swift`, `Zone` ersetzen durch:

```swift
public struct Zone: Codable, Hashable, Sendable, Identifiable {
    public var id: ZoneID
    /// Human readable label shown in the UI, e.g. "rechts oben".
    public var name: String
    /// Wohin das Fenster kommt. Relativ zum sichtbaren Rahmen des Displays.
    public var frame: RelativeRect
    /// Wo losgelassen werden muss, im **selben** Raum wie ``frame`` — also
    /// bildschirmbezogen, nicht zonenbezogen. Die Fläche muss deshalb nicht im
    /// Zielrahmen liegen: „am linken Rand loslassen, Fenster landet rechts" ist
    /// ausdrücklich erlaubt.
    ///
    /// `nil` heisst: der Zielrahmen selbst. Genau das lässt jede Konfiguration,
    /// die dieses Feld nicht kennt, unverändert weiterlaufen — weshalb hier
    /// auch kein Schemawechsel nötig ist.
    ///
    /// Der Sinn der Trennung: mit **einem** Rechteck für beides ist ein Stapel
    /// überlappender Zonen nicht auflösbar. Welche Regel der Treffertest auch
    /// wählt, eine Ebene verliert vollständig — siehe
    /// `docs/superpowers/specs/2026-09-23-trefferflaechen-design.md`.
    public var activationArea: RelativeRect?

    public init(
        id: ZoneID,
        name: String,
        frame: RelativeRect,
        activationArea: RelativeRect? = nil
    ) {
        self.id = id
        self.name = name
        self.frame = frame
        self.activationArea = activationArea
    }
}
```

`Codable` bleibt synthetisiert: ein `Optional` wird beim Dekodieren zu `nil`, wenn der Schlüssel fehlt, und beim Kodieren weggelassen.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter "Zone — Trefferfläche"`
Expected: 4 Tests grün.

- [ ] **Step 5: Run the whole suite**

Run: `swift test`
Expected: 593 Tests grün (589 + 4). Keine bestehende Datei bricht, weil `activationArea` einen Vorgabewert hat.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenZonrCore/Geometry/Zone.swift Tests/OpenZonrCoreTests/ZoneActivationAreaTests.swift
git commit -m "feat(core): Zone bekommt eine optionale Trefferfläche

Bildschirmbezogen wie der Zielrahmen, damit sie auch ausserhalb liegen darf.
nil heisst: der Zielrahmen selbst — bestehende Konfigurationen verhalten sich
unverändert, deshalb bleibt currentVersion bei 1 und es gibt keinen
Migrationsschritt."
```

---

### Task 2: `Dropzone.activationFrame`

**Files:**
- Modify: `Sources/OpenZonrCore/Dropzone/DropzoneMap.swift:8-66` (Struct und `init`), `:100-113` (`zones(in:profile:visibleFrames:)`)
- Test: `Tests/OpenZonrCoreTests/DropzoneActivationFrameTests.swift` (neu)

**Interfaces:**
- Consumes: `Zone.activationArea` aus Task 1
- Produces: `Dropzone.activationFrame: WindowFrame`; `Dropzone.init(..., activationFrame: WindowFrame? = nil)` — `nil` bedeutet „gleich `frame`"

- [ ] **Step 1: Write the failing test**

`Tests/OpenZonrCoreTests/DropzoneActivationFrameTests.swift`:

```swift
import Foundation
import Testing

@testable import OpenZonrCore

/// ``Dropzone`` trägt die Trefferfläche absolut mit, damit der Zug nichts
/// nachschlagen muss, während die Maus läuft — dieselbe Begründung wie für
/// ``Dropzone/frame``.
@Suite("Dropzone — absolute Trefferfläche")
struct DropzoneActivationFrameTests {

    private static let visible = VisibleFrame(x: 0, y: 0, width: 1000, height: 800)

    private func configuration(activation: RelativeRect?) -> Configuration {
        var configuration = Configuration()
        configuration.displays = [
            DisplayDescriptor(
                alias: DisplayAlias(rawValue: "haupt"),
                displayName: "Haupt",
                identity: .fallback(vendorNumber: 1, modelNumber: 1, pixelWidth: 1000, pixelHeight: 800, portIndex: 0),
                layouts: [
                    Layout(
                        id: LayoutID(rawValue: "eine"),
                        name: "Eine",
                        zones: [
                            Zone(
                                id: ZoneID(rawValue: "rechts"),
                                name: "Rechts",
                                frame: RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1),
                                activationArea: activation
                            )
                        ]
                    )
                ],
                defaultLayoutID: LayoutID(rawValue: "eine")
            )
        ]
        configuration.profiles = [
            Profile(
                id: ProfileID(rawValue: "p"),
                name: "P",
                fingerprint: ProfileFingerprint(displays: [DisplayAlias(rawValue: "haupt")]),
                layouts: [DisplayAlias(rawValue: "haupt"): LayoutID(rawValue: "eine")]
            )
        ]
        return configuration
    }

    private func onlyZone(activation: RelativeRect?) -> Dropzone {
        let frames: VisibleFrames = [DisplayAlias(rawValue: "haupt"): Self.visible]
        let zones = DropzoneMap.zones(
            in: configuration(activation: activation),
            profile: ProfileID(rawValue: "p"),
            visibleFrames: frames
        )
        return zones[0]
    }

    @Test("Ohne Trefferfläche ist sie der Zielrahmen")
    func fallsBackToFrame() {
        let zone = onlyZone(activation: nil)

        #expect(zone.activationFrame == zone.frame)
    }

    @Test("Mit Trefferfläche wird sie absolut gerechnet, wie der Zielrahmen")
    func computesAbsoluteActivationFrame() {
        // Oberes Viertel der rechten Hälfte, relativ mit Ursprung OBEN links.
        let zone = onlyZone(activation: RelativeRect(x: 0.5, y: 0, width: 0.5, height: 0.25))

        #expect(zone.activationFrame == ZoneGeometry.absoluteFrame(
            for: RelativeRect(x: 0.5, y: 0, width: 0.5, height: 0.25),
            in: Self.visible
        ))
        // Der Zielrahmen bleibt davon unberührt.
        #expect(zone.frame == ZoneGeometry.absoluteFrame(
            for: RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1),
            in: Self.visible
        ))
        #expect(zone.activationFrame != zone.frame)
    }

    @Test("Die Trefferfläche darf ganz ausserhalb des Zielrahmens liegen")
    func activationMayLieOutsideTheFrame() {
        let zone = onlyZone(activation: RelativeRect(x: 0, y: 0, width: 0.1, height: 1))

        #expect(zone.activationFrame.x == 0)
        #expect(zone.frame.x == 500)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "Dropzone — absolute Trefferfläche"`
Expected: `value of type 'Dropzone' has no member 'activationFrame'`.

- [ ] **Step 3: Write minimal implementation**

In `DropzoneMap.swift`, im `Dropzone`-Struct nach `frame` einfügen:

```swift
    /// Wo losgelassen werden muss, absolut, im selben Raum wie ``frame``.
    ///
    /// Gleich ``frame``, solange die Zone keine eigene Trefferfläche trägt.
    /// Getrennt mitgeführt, weil ein Stapel überlappender Zielrahmen sonst
    /// nicht auflösbar ist: erst disjunkte Trefferflächen machen jede Ebene
    /// einzeln erreichbar.
    ///
    /// Der ``margin`` wirkt hierauf **nicht**. Er ist ein Platzierungsrand;
    /// eine Fläche zu schrumpfen, die der Nutzer selbst gezeichnet hat, wäre
    /// Bevormundung.
    public var activationFrame: WindowFrame
```

und die `init` ersetzen durch:

```swift
    public init(
        display: DisplayAlias,
        zone: ZoneID,
        name: String,
        relativeFrame: RelativeRect,
        frame: WindowFrame,
        visibleFrame: VisibleFrame,
        margin: Double = 0,
        activationFrame: WindowFrame? = nil
    ) {
        self.display = display
        self.zone = zone
        self.name = name
        self.relativeFrame = relativeFrame
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.margin = margin
        // Vorgabe statt eigenem Feldtyp: jede bestehende Konstruktionsstelle —
        // auch jeder von Hand gebaute Testfall — bleibt gültig.
        self.activationFrame = activationFrame ?? frame
    }
```

In `zones(in:profile:visibleFrames:)` den `Dropzone(...)`-Aufruf (`DropzoneMap.swift:103-112`) um ein Argument ergänzen:

```swift
                        margin: layout.margin,
                        activationFrame: zone.activationArea.map {
                            ZoneGeometry.absoluteFrame(for: $0, in: visibleFrame)
                        }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter "Dropzone — absolute Trefferfläche"`
Expected: 3 Tests grün.

- [ ] **Step 5: Run the whole suite**

Run: `swift test`
Expected: 596 grün. Bestehende `Dropzone(...)`-Aufrufe kompilieren unverändert, weil das neue Argument zuletzt steht und einen Vorgabewert hat.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenZonrCore/Dropzone/DropzoneMap.swift Tests/OpenZonrCoreTests/DropzoneActivationFrameTests.swift
git commit -m "feat(core): Dropzone trägt die Trefferfläche absolut mit

Gerechnet wie der Zielrahmen über ZoneGeometry.absoluteFrame, Rückfall auf den
Zielrahmen. Der margin wirkt nicht darauf: er ist ein Platzierungsrand."
```

---

### Task 3: Treffertest prüft die Trefferfläche

**Files:**
- Modify: `Sources/OpenZonrCore/Dropzone/DropzoneMap.swift:118-146` (`zone(at:in:)`)
- Test: `Tests/OpenZonrCoreTests/DropzoneActivationHitTests.swift` (neu)

**Interfaces:**
- Consumes: `Dropzone.activationFrame` aus Task 2
- Produces: keine neue Signatur — `zone(at:in:)` behält `(ScreenPoint, [Dropzone]) -> Dropzone?`

- [ ] **Step 1: Write the failing test**

`Tests/OpenZonrCoreTests/DropzoneActivationHitTests.swift`:

```swift
import Foundation
import Testing

@testable import OpenZonrCore

/// Der Zweck des ganzen Vorhabens: ein Stapel, dessen Ebenen einzeln erreichbar
/// sind.
///
/// Gemessen an der Ebene des Autors (C49RG9x, 5120x1440) war „Rechts außen"
/// unerreichbar, weil „Rechts oben" und „Rechts unten" es lückenlos überdecken
/// und beide kleiner sind.
@Suite("Treffertest — Trefferflächen")
struct DropzoneActivationHitTests {

    private static let visible = VisibleFrame(x: 0, y: 0, width: 1000, height: 800)

    private func zone(
        _ id: String,
        frame: WindowFrame,
        activation: WindowFrame? = nil
    ) -> Dropzone {
        Dropzone(
            display: DisplayAlias(rawValue: "haupt"),
            zone: ZoneID(rawValue: id),
            name: id,
            relativeFrame: .full,
            frame: frame,
            visibleFrame: Self.visible,
            activationFrame: activation
        )
    }

    /// Der Stapel aus der Konfiguration des Autors, auf 1000x800 verkleinert:
    /// eine ganze Spalte und die zwei Hälften darin, mit drei disjunkten
    /// Trefferstreifen.
    private var stack: [Dropzone] {
        [
            zone("ganz",
                 frame: WindowFrame(x: 600, y: 0, width: 400, height: 800),
                 activation: WindowFrame(x: 600, y: 350, width: 400, height: 100)),
            zone("oben",
                 frame: WindowFrame(x: 600, y: 400, width: 400, height: 400),
                 activation: WindowFrame(x: 600, y: 700, width: 400, height: 100)),
            zone("unten",
                 frame: WindowFrame(x: 600, y: 0, width: 400, height: 400),
                 activation: WindowFrame(x: 600, y: 0, width: 400, height: 100))
        ]
    }

    @Test("Jede Ebene des Stapels ist einzeln erreichbar")
    func everyLayerIsReachable() {
        let zones = stack

        #expect(DropzoneMap.zone(at: ScreenPoint(x: 700, y: 400), in: zones)?.zone.rawValue == "ganz")
        #expect(DropzoneMap.zone(at: ScreenPoint(x: 700, y: 750), in: zones)?.zone.rawValue == "oben")
        #expect(DropzoneMap.zone(at: ScreenPoint(x: 700, y: 50), in: zones)?.zone.rawValue == "unten")
    }

    @Test("Der getroffene Zielrahmen bleibt der grosse, nicht der Streifen")
    func hitCarriesTheTargetFrame() {
        let hit = DropzoneMap.zone(at: ScreenPoint(x: 700, y: 400), in: stack)

        #expect(hit?.frame == WindowFrame(x: 600, y: 0, width: 400, height: 800))
        #expect(hit?.placement.frame == WindowFrame(x: 600, y: 0, width: 400, height: 800))
    }

    @Test("Ausserhalb aller Trefferflächen wird nichts getroffen")
    func missesBetweenTheStrips() {
        #expect(DropzoneMap.zone(at: ScreenPoint(x: 700, y: 200), in: stack) == nil)
    }

    /// Rückfallschutz für jede bestehende Konfiguration: ohne Trefferflächen
    /// muss der Treffertest exakt so entscheiden wie vorher — kleinste gewinnt.
    @Test("Ohne Trefferflächen entscheidet weiter die kleinste Fläche")
    func withoutActivationAreasSmallestStillWins() {
        let zones = [
            zone("gross", frame: WindowFrame(x: 0, y: 0, width: 1000, height: 800)),
            zone("klein", frame: WindowFrame(x: 0, y: 0, width: 100, height: 100))
        ]

        #expect(DropzoneMap.zone(at: ScreenPoint(x: 50, y: 50), in: zones)?.zone.rawValue == "klein")
        #expect(DropzoneMap.zone(at: ScreenPoint(x: 500, y: 500), in: zones)?.zone.rawValue == "gross")
    }

    /// Randauslösung: die Trefferfläche liegt am linken Rand, das Fenster
    /// landet rechts.
    @Test("Trefferfläche ausserhalb des Zielrahmens löst trotzdem aus")
    func activationOutsideTheFrameStillHits() {
        let zones = [
            zone("rechts",
                 frame: WindowFrame(x: 600, y: 0, width: 400, height: 800),
                 activation: WindowFrame(x: 0, y: 0, width: 40, height: 800))
        ]

        let hit = DropzoneMap.zone(at: ScreenPoint(x: 20, y: 400), in: zones)
        #expect(hit?.zone.rawValue == "rechts")
        #expect(hit?.frame.x == 600)
    }

    /// Gleich grosse Trefferflächen werden weiter über Display und Zonen-ID
    /// entschieden, nie über die Reihenfolge im Array.
    @Test("Gleichstand entscheidet die Zonen-ID, nicht die Reihenfolge")
    func tiesAreBrokenByIdentifier() {
        let a = zone("aaa",
                     frame: WindowFrame(x: 0, y: 0, width: 500, height: 800),
                     activation: WindowFrame(x: 0, y: 0, width: 100, height: 100))
        let b = zone("bbb",
                     frame: WindowFrame(x: 500, y: 0, width: 500, height: 800),
                     activation: WindowFrame(x: 0, y: 0, width: 100, height: 100))

        #expect(DropzoneMap.zone(at: ScreenPoint(x: 50, y: 50), in: [a, b])?.zone.rawValue == "aaa")
        #expect(DropzoneMap.zone(at: ScreenPoint(x: 50, y: 50), in: [b, a])?.zone.rawValue == "aaa")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "Treffertest — Trefferflächen"`
Expected: `everyLayerIsReachable` schlägt fehl — bei `(700, 400)` gewinnt heute „oben" oder „unten" statt „ganz", weil noch `frame` geprüft wird. `missesBetweenTheStrips` schlägt ebenfalls fehl.

- [ ] **Step 3: Write minimal implementation**

In `DropzoneMap.zone(at:in:)` beide Vorkommen von `frame` durch `activationFrame` ersetzen:

```swift
    public static func zone(at point: ScreenPoint, in zones: [Dropzone]) -> Dropzone? {
        var best: Dropzone?
        for candidate in zones where candidate.activationFrame.contains(point) {
            guard let current = best else {
                best = candidate
                continue
            }
            if candidate.activationFrame.area < current.activationFrame.area {
                best = candidate
            } else if candidate.activationFrame.area == current.activationFrame.area,
                      isOrderedBefore(candidate, current) {
                best = candidate
            }
        }
        return best
    }
```

Und den Doc-Kommentar darüber (`DropzoneMap.swift:118-130`) ersetzen:

```swift
    /// The zone under `point`, or `nil` when the pointer is over none.
    ///
    /// - Parameter point: the pointer in **AppKit** coordinates, origin
    ///   bottom-left, the same space the zone frames are in.
    ///
    /// Geprüft wird die **Trefferfläche**, nicht der Zielrahmen. Ohne eigene
    /// Trefferfläche sind beide gleich, und dann entscheidet wie bisher die
    /// kleinste Fläche: ein Fokusfenster über zwei Hälften enthält jeden Punkt
    /// der Hälften, und gewänne es, wären die Hälften unerreichbar.
    ///
    /// Diese Regel allein reicht aber nicht, und das war der Fehler, den dieses
    /// Feld behebt: sie kippt das Problem nur auf die andere Seite. Deckt ein
    /// Stapel kleinerer Zonen eine grössere lückenlos ab, ist die **grosse**
    /// unerreichbar — gemessen an der Ebene des Autors, in der „Rechts außen"
    /// von „Rechts oben" und „Rechts unten" vollständig überdeckt wurde. Mit
    /// einem Rechteck für beides ist das nicht lösbar; mit getrennten
    /// Trefferflächen schon, weil die disjunkt sein dürfen, auch wenn die
    /// Zielrahmen es nicht sind.
    ///
    /// Equal areas are decided by display alias and then zone identifier, never
    /// by array order, so the same pointer always produces the same answer.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter "Treffertest — Trefferflächen"`
Expected: 6 Tests grün.

- [ ] **Step 5: Run the whole suite**

Run: `swift test`
Expected: 602 grün. Besonders zu beachten: bestehende `DropzoneMap`- und Overlay-Tests müssen unverändert grün bleiben, weil ihre Zonen keine Trefferflächen tragen und `activationFrame == frame` gilt.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenZonrCore/Dropzone/DropzoneMap.swift Tests/OpenZonrCoreTests/DropzoneActivationHitTests.swift
git commit -m "feat(core): Treffertest prüft die Trefferfläche statt des Zielrahmens

Die Regel 'kleinste gewinnt' bleibt Wort für Wort, samt Gleichstandsauflösung
über Display und Zonen-ID. Sie wirkt nur auf das richtige Rechteck. Damit ist
ein Stapel erstmals auflösbar: die Zielrahmen dürfen sich überlappen, die
Trefferflächen sind disjunkt."
```

---

### Task 4: Anheft-Punkt sitzt an der Trefferfläche

**Files:**
- Modify: `Sources/OpenZonrCore/Dropzone/DropzoneMap.swift:189-207` (`pinBadgeFrame(for:)`)
- Test: `Tests/OpenZonrCoreTests/DropzoneActivationBadgeTests.swift` (neu)

**Interfaces:**
- Consumes: `Dropzone.activationFrame` aus Task 2
- Produces: keine neue Signatur — `pinBadgeFrame(for:) -> WindowFrame?` bleibt

- [ ] **Step 1: Write the failing test**

`Tests/OpenZonrCoreTests/DropzoneActivationBadgeTests.swift`:

```swift
import Foundation
import Testing

@testable import OpenZonrCore

/// Der Anheft-Punkt ist das zweite Ziel derselben Mausbewegung. Er muss deshalb
/// dort sitzen, wo die Maus ist — an der Trefferfläche, nicht am Zielrahmen.
/// Bei Randauslösung läge er sonst am anderen Ende des Bildschirms.
@Suite("Anheft-Punkt — Trefferfläche")
struct DropzoneActivationBadgeTests {

    private static let visible = VisibleFrame(x: 0, y: 0, width: 1000, height: 800)

    private func zone(frame: WindowFrame, activation: WindowFrame?) -> Dropzone {
        Dropzone(
            display: DisplayAlias(rawValue: "haupt"),
            zone: ZoneID(rawValue: "z"),
            name: "Z",
            relativeFrame: .full,
            frame: frame,
            visibleFrame: Self.visible,
            activationFrame: activation
        )
    }

    @Test("Die Marke sitzt in der Trefferfläche, nicht im Zielrahmen")
    func badgeSitsOnTheActivationFrame() {
        let subject = zone(
            frame: WindowFrame(x: 600, y: 0, width: 400, height: 800),
            activation: WindowFrame(x: 0, y: 0, width: 200, height: 200)
        )

        let badge = try! #require(DropzoneMap.pinBadgeFrame(for: subject))
        // Oben rechts in der Trefferfläche: x = 0 + 200 - 4 - 8 - 24
        #expect(badge == WindowFrame(x: 164, y: 164, width: 24, height: 24))
        #expect(DropzoneMap.isOnPinBadge(ScreenPoint(x: 170, y: 170), of: subject))
        #expect(DropzoneMap.isOnPinBadge(ScreenPoint(x: 800, y: 700), of: subject) == false)
    }

    /// 4·2 + 8·2 + 24 + 24 = 72 Punkte in der kürzeren Kante. Darunter gibt es
    /// keine Marke — sonst verschluckte sie die ganze Fläche und das
    /// gewöhnliche Loslassen wäre nicht mehr erreichbar.
    @Test("Trefferfläche unter 72 Punkten trägt keine Marke")
    func tooSmallActivationFrameHasNoBadge() {
        let subject = zone(
            frame: WindowFrame(x: 0, y: 0, width: 1000, height: 800),
            activation: WindowFrame(x: 0, y: 0, width: 71, height: 400)
        )

        #expect(DropzoneMap.pinBadgeFrame(for: subject) == nil)
        #expect(DropzoneMap.isOnPinBadge(ScreenPoint(x: 10, y: 10), of: subject) == false)
    }

    @Test("Ohne Trefferfläche bleibt die Marke am Zielrahmen wie bisher")
    func withoutActivationFrameNothingChanges() {
        let subject = zone(frame: WindowFrame(x: 0, y: 0, width: 400, height: 400), activation: nil)

        #expect(DropzoneMap.pinBadgeFrame(for: subject) == WindowFrame(x: 364, y: 364, width: 24, height: 24))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "Anheft-Punkt — Trefferfläche"`
Expected: `badgeSitsOnTheActivationFrame` schlägt fehl — die Marke sitzt heute bei `x = 600 + 400 - 36 = 964`, erwartet ist `164`.

- [ ] **Step 3: Write minimal implementation**

In `pinBadgeFrame(for:)` nur die erste Zeile ändern:

```swift
    public static func pinBadgeFrame(for zone: Dropzone) -> WindowFrame? {
        // An der Trefferfläche, nicht am Zielrahmen: die Marke ist das zweite
        // Ziel derselben Mausbewegung. Bei Randauslösung läge sie sonst am
        // anderen Ende des Bildschirms und wäre unbenutzbar. Ohne eigene
        // Trefferfläche sind beide gleich und nichts ändert sich.
        let frame = zone.activationFrame
```

Und im Doc-Kommentar (`DropzoneMap.swift:164-188`) den Satz „A **pure function** of the zone's frame" zu „A **pure function** of the zone's activation frame" ändern sowie unter `- Returns:` ergänzen:

```swift
    ///   Eine Trefferfläche unter `4·2 + 8·2 + 24 + 24 = 72` Punkten in der
    ///   kürzeren Kante trägt deshalb **keine** Marke. Das Platzieren
    ///   funktioniert dort weiter; nur die Regel muss dann über das Menü
    ///   entstehen.
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter "Anheft-Punkt — Trefferfläche"`
Expected: 3 Tests grün.

- [ ] **Step 5: Run the whole suite**

Run: `swift test`
Expected: 605 grün.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenZonrCore/Dropzone/DropzoneMap.swift Tests/OpenZonrCoreTests/DropzoneActivationBadgeTests.swift
git commit -m "feat(core): Anheft-Punkt richtet sich nach der Trefferfläche

Er ist das zweite Ziel derselben Mausbewegung und muss dort sitzen, wo die Maus
ist. Folge, die im Test steht: eine Trefferfläche unter 72 Punkten trägt keine
Marke mehr — Platzieren geht weiter, die Regel entsteht dann über das Menü."
```

---

### Task 5: Überdeckung als reine Geometrie

**Files:**
- Create: `Sources/OpenZonrCore/Geometry/RectangleCoverage.swift`
- Test: `Tests/OpenZonrCoreTests/RectangleCoverageTests.swift` (neu)

**Interfaces:**
- Consumes: `WindowFrame` (`ZoneGeometry.swift`)
- Produces: `RectangleCoverage.isCovered(_ rect: WindowFrame, by others: [WindowFrame]) -> Bool`

- [ ] **Step 1: Write the failing test**

`Tests/OpenZonrCoreTests/RectangleCoverageTests.swift`:

```swift
import Foundation
import Testing

@testable import OpenZonrCore

/// Wird ein Rechteck von einer Menge anderer Rechtecke lückenlos überdeckt?
///
/// Der Fall, um den es geht, ist die **Vereinigung**: „Rechts außen" wird von
/// keiner einzelnen Zone überdeckt, sondern erst von „Rechts oben" und „Rechts
/// unten" zusammen. Eine paarweise Prüfung fände ihn nicht.
@Suite("Rechteck-Überdeckung")
struct RectangleCoverageTests {

    private func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> WindowFrame {
        WindowFrame(x: x, y: y, width: w, height: h)
    }

    @Test("Eine leere Menge überdeckt nichts")
    func emptySetCoversNothing() {
        #expect(RectangleCoverage.isCovered(rect(0, 0, 10, 10), by: []) == false)
    }

    @Test("Ein deckungsgleiches Rechteck überdeckt")
    func identicalRectangleCovers() {
        #expect(RectangleCoverage.isCovered(rect(0, 0, 10, 10), by: [rect(0, 0, 10, 10)]))
    }

    @Test("Ein grösseres Rechteck überdeckt")
    func largerRectangleCovers() {
        #expect(RectangleCoverage.isCovered(rect(2, 2, 6, 6), by: [rect(0, 0, 10, 10)]))
    }

    @Test("Zwei Hälften überdecken zusammen — der eigentliche Fall")
    func twoHalvesCoverTogether() {
        let whole = rect(0, 0, 10, 10)
        let lower = rect(0, 0, 10, 5)
        let upper = rect(0, 5, 10, 5)

        #expect(RectangleCoverage.isCovered(whole, by: [lower]) == false)
        #expect(RectangleCoverage.isCovered(whole, by: [upper]) == false)
        #expect(RectangleCoverage.isCovered(whole, by: [lower, upper]))
    }

    @Test("Eine Lücke von einem Punkt genügt, um nicht zu überdecken")
    func aSingleGapIsEnough() {
        let whole = rect(0, 0, 10, 10)
        let lower = rect(0, 0, 10, 4)
        let upper = rect(0, 5, 10, 5)

        #expect(RectangleCoverage.isCovered(whole, by: [lower, upper]) == false)
    }

    @Test("Überlappende Teile überdecken trotzdem")
    func overlappingPartsStillCover() {
        let whole = rect(0, 0, 10, 10)
        #expect(RectangleCoverage.isCovered(whole, by: [rect(0, 0, 10, 7), rect(0, 3, 10, 7)]))
    }

    @Test("Ein Rechteck ohne Fläche gilt als überdeckt")
    func emptyRectangleIsCovered() {
        #expect(RectangleCoverage.isCovered(rect(0, 0, 0, 10), by: []))
    }

    @Test("Teilweise Überdeckung reicht nicht")
    func partialCoverageIsNotEnough() {
        #expect(RectangleCoverage.isCovered(rect(0, 0, 10, 10), by: [rect(0, 0, 5, 10)]) == false)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "Rechteck-Überdeckung"`
Expected: `cannot find 'RectangleCoverage' in scope`.

- [ ] **Step 3: Write minimal implementation**

`Sources/OpenZonrCore/Geometry/RectangleCoverage.swift`:

```swift
import Foundation

/// Wird ein achsenparalleles Rechteck von einer Menge anderer lückenlos
/// überdeckt?
///
/// Gebraucht für den Befund „Zone unerreichbar": eine Zone verschwindet nicht
/// hinter *einer* anderen, sondern hinter der **Vereinigung** mehrerer. In der
/// Ebene des Autors überdecken „Rechts oben" und „Rechts unten" zusammen
/// „Rechts außen"; einzeln tut es keine von beiden. Eine paarweise Prüfung
/// fände den Fall nicht.
///
/// Verfahren: Gitterzerlegung. Alle Kanten der beteiligten Rechtecke, auf das
/// geprüfte Rechteck beschnitten, ergeben ein Gitter. Innerhalb einer Zelle
/// ändert sich nichts — entweder liegt sie ganz in einem der Rechtecke oder in
/// keinem. Es genügt also, je Zelle den Mittelpunkt zu prüfen. Das ist exakt,
/// nicht genähert, und bei der Zahl Zonen einer Ebene (einstellig) billig.
public enum RectangleCoverage {

    /// - Returns: `true`, wenn jeder Punkt von `rect` in mindestens einem der
    ///   `others` liegt. Ein Rechteck ohne Fläche gilt als überdeckt — es gibt
    ///   keinen Punkt, der unbedeckt bleiben könnte.
    public static func isCovered(_ rect: WindowFrame, by others: [WindowFrame]) -> Bool {
        guard rect.width > 0, rect.height > 0 else { return true }

        // Nur was das Rechteck überhaupt berührt, kann zur Überdeckung
        // beitragen.
        let relevant = others.filter { other in
            other.width > 0 && other.height > 0
                && other.x < rect.x + rect.width && other.x + other.width > rect.x
                && other.y < rect.y + rect.height && other.y + other.height > rect.y
        }
        guard !relevant.isEmpty else { return false }

        let xs = gridLines(
            from: relevant.flatMap { [$0.x, $0.x + $0.width] },
            low: rect.x, high: rect.x + rect.width
        )
        let ys = gridLines(
            from: relevant.flatMap { [$0.y, $0.y + $0.height] },
            low: rect.y, high: rect.y + rect.height
        )

        for xIndex in 0..<(xs.count - 1) {
            for yIndex in 0..<(ys.count - 1) {
                let midX = (xs[xIndex] + xs[xIndex + 1]) / 2
                let midY = (ys[yIndex] + ys[yIndex + 1]) / 2
                let covered = relevant.contains { other in
                    midX >= other.x && midX < other.x + other.width
                        && midY >= other.y && midY < other.y + other.height
                }
                if !covered { return false }
            }
        }
        return true
    }

    /// Die Schnittlinien innerhalb `low…high`, aufsteigend und ohne Dubletten.
    private static func gridLines(from values: [Double], low: Double, high: Double) -> [Double] {
        var lines = [low, high]
        for value in values where value > low && value < high {
            lines.append(value)
        }
        return Array(Set(lines)).sorted()
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter "Rechteck-Überdeckung"`
Expected: 8 Tests grün.

- [ ] **Step 5: Commit**

```bash
git add Sources/OpenZonrCore/Geometry/RectangleCoverage.swift Tests/OpenZonrCoreTests/RectangleCoverageTests.swift
git commit -m "feat(core): Überdeckung eines Rechtecks durch eine Menge Rechtecke

Gitterzerlegung, exakt statt genähert. Gebraucht wird die Vereinigung: eine Zone
verschwindet hinter mehreren anderen, nicht hinter einer einzelnen."
```

---

### Task 6: Prüfschritt „Zone unerreichbar"

**Files:**
- Create: `Sources/OpenZonrCore/Validation/Checks/ZoneReachabilityCheck.swift`
- Modify: `Sources/OpenZonrCore/Validation/ValidationFinding.swift:60-75` (zwei Codes, beide `warning`)
- Modify: `Sources/OpenZonrCore/Validation/ConfigurationValidator.swift:12-18` (registrieren)
- Test: `Tests/OpenZonrCoreTests/ZoneReachabilityCheckTests.swift` (neu)

**Interfaces:**
- Consumes: `RectangleCoverage.isCovered(_:by:)` aus Task 5, `Zone.activationArea` aus Task 1
- Produces: `ValidationCode.zoneUnreachable`, `ValidationCode.activationAreaDetached`, `ZoneReachabilityCheck()`

- [ ] **Step 1: Write the failing test**

`Tests/OpenZonrCoreTests/ZoneReachabilityCheckTests.swift`:

```swift
import Foundation
import Testing

@testable import OpenZonrCore

/// Der Befund, der den Fehler des Autors sichtbar gemacht hätte.
@Suite("Prüfung — erreichbare Zonen")
struct ZoneReachabilityCheckTests {

    private func configuration(zones: [Zone]) -> Configuration {
        var configuration = Configuration()
        configuration.displays = [
            DisplayDescriptor(
                alias: DisplayAlias(rawValue: "c49rg9x"),
                displayName: "C49RG9x",
                identity: .fallback(vendorNumber: 19501, modelNumber: 3996, pixelWidth: 5120, pixelHeight: 1440, portIndex: 1),
                layouts: [Layout(id: LayoutID(rawValue: "drei"), name: "Drei", zones: zones)],
                defaultLayoutID: LayoutID(rawValue: "drei")
            )
        ]
        return configuration
    }

    private func zone(_ id: String, _ frame: RelativeRect, activation: RelativeRect? = nil) -> Zone {
        Zone(id: ZoneID(rawValue: id), name: id, frame: frame, activationArea: activation)
    }

    /// Die echte Ebene des Autors, Stand 23.09.2026: „Rechts außen" wird von
    /// „Rechts oben" und „Rechts unten" lückenlos überdeckt.
    @Test("Die Ebene des Autors meldet right-quarter als unerreichbar")
    func reportsTheAuthorsUnreachableZone() {
        let configuration = configuration(zones: [
            zone("left-quarter",  RelativeRect(x: 0, y: 0, width: 0.25, height: 1)),
            zone("center-half",   RelativeRect(x: 0.25, y: 0, width: 0.41666666666666663, height: 1)),
            zone("right-quarter", RelativeRect(x: 0.6666666666666666, y: 0, width: 0.33333333333333337, height: 1)),
            zone("neue-zone",     RelativeRect(x: 0.6666666666666666, y: 0, width: 0.33333333333333337, height: 0.5)),
            zone("neue-zone-2",   RelativeRect(x: 0.6666666666666666, y: 0.5, width: 0.33333333333333337, height: 0.5))
        ])

        let findings = ZoneReachabilityCheck().findings(in: configuration)
        let unreachable = findings.filter { $0.code == .zoneUnreachable }

        #expect(unreachable.count == 1)
        #expect(unreachable.first?.path.description.contains("right-quarter") == true)
        #expect(unreachable.first?.severity == .warning)
    }

    @Test("Mit disjunkten Trefferflächen ist niemand mehr unerreichbar")
    func separateActivationAreasResolveTheStack() {
        let configuration = configuration(zones: [
            zone("ganz",  RelativeRect(x: 0.6, y: 0, width: 0.4, height: 1),
                 activation: RelativeRect(x: 0.6, y: 0.4, width: 0.4, height: 0.2)),
            zone("oben",  RelativeRect(x: 0.6, y: 0, width: 0.4, height: 0.5),
                 activation: RelativeRect(x: 0.6, y: 0, width: 0.4, height: 0.2)),
            zone("unten", RelativeRect(x: 0.6, y: 0.5, width: 0.4, height: 0.5),
                 activation: RelativeRect(x: 0.6, y: 0.8, width: 0.4, height: 0.2))
        ])

        #expect(ZoneReachabilityCheck().findings(in: configuration).isEmpty)
    }

    @Test("Nebeneinander liegende Zonen melden nichts")
    func adjacentZonesAreFine() {
        let configuration = configuration(zones: [
            zone("links",  RelativeRect(x: 0, y: 0, width: 0.5, height: 1)),
            zone("rechts", RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1))
        ])

        #expect(ZoneReachabilityCheck().findings(in: configuration).isEmpty)
    }

    @Test("Eine Trefferfläche ohne Bezug zum Zielrahmen ist ein Hinweis, kein Fehler")
    func detachedActivationAreaIsAWarning() {
        let configuration = configuration(zones: [
            zone("rechts", RelativeRect(x: 0.6, y: 0, width: 0.4, height: 1),
                 activation: RelativeRect(x: 0, y: 0, width: 0.05, height: 1))
        ])

        let findings = ZoneReachabilityCheck().findings(in: configuration)
        #expect(findings.count == 1)
        #expect(findings.first?.code == .activationAreaDetached)
        #expect(findings.first?.severity == .warning)
    }

    /// Die Prüfung darf die Konfiguration nie unbenutzbar machen: eine
    /// unerreichbare Zone ist ärgerlich, kein Grund, die Datei abzulehnen.
    @Test("Beide Befunde lassen die Konfiguration benutzbar")
    func findingsNeverMakeTheConfigurationUnusable() {
        #expect(ValidationCode.zoneUnreachable.severity == .warning)
        #expect(ValidationCode.activationAreaDetached.severity == .warning)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "Prüfung — erreichbare Zonen"`
Expected: `cannot find 'ZoneReachabilityCheck' in scope` und `type 'ValidationCode' has no member 'zoneUnreachable'`.

- [ ] **Step 3: Write minimal implementation**

In `ValidationFinding.swift` nach `case shadowedRule` (Zeile 61) einfügen:

```swift
    /// Die Trefferfläche der Zone ist von der Vereinigung der Trefferflächen
    /// bevorzugter Zonen lückenlos überdeckt — der Treffertest kann sie nie
    /// zurückgeben.
    case zoneUnreachable
    /// Die Trefferfläche überschneidet den eigenen Zielrahmen nicht oder liegt
    /// ausserhalb des sichtbaren Rahmens. Erlaubt, aber häufiger ein Tippfehler
    /// als eine Absicht.
    case activationAreaDetached
```

und die Severity-Liste (Zeile 70) erweitern:

```swift
        case .unusedRole, .shadowedRule, .zoneUnreachable, .activationAreaDetached:
            return .warning
```

`Sources/OpenZonrCore/Validation/Checks/ZoneReachabilityCheck.swift`:

```swift
import Foundation

/// Meldet Zonen, die der Treffertest nie zurückgeben kann.
///
/// Eine Zone `Z` ist unerreichbar, wenn ihre Trefferfläche von der
/// **Vereinigung** der Trefferflächen jener Zonen derselben Ebene überdeckt
/// wird, die der Treffertest ihr vorzieht — kleinere Fläche, oder gleiche
/// Fläche und früher in der Ordnung der Zonen-IDs. Genau diese Regel steht in
/// ``DropzoneMap/zone(at:in:)``; hier wird sie nur rückwärts gelesen.
///
/// Gerechnet wird in relativen Einheiten. Das ist zulässig, weil alle Zonen
/// einer Ebene denselben sichtbaren Rahmen teilen: die Umrechnung ist eine
/// gemeinsame affine Abbildung und ändert an Überdeckung und
/// Flächenvergleichen nichts. Die Prüfung braucht deshalb **kein** Display und
/// läuft headless.
public struct ZoneReachabilityCheck: ConfigurationCheck {

    public init() {}

    public func findings(in configuration: Configuration) -> [ValidationFinding] {
        var findings: [ValidationFinding] = []

        for display in configuration.displays {
            for layout in display.layouts {
                findings.append(contentsOf: self.findings(in: layout, of: display))
            }
        }
        return findings
    }

    private func findings(in layout: Layout, of display: DisplayDescriptor) -> [ValidationFinding] {
        var findings: [ValidationFinding] = []

        for zone in layout.zones {
            let path = ConfigurationPath()
                .element("displays", display.alias)
                .element("layouts", layout.id)
                .element("zones", zone.id)

            let activation = zone.activationArea ?? zone.frame

            if let declared = zone.activationArea, !intersects(declared, zone.frame) {
                findings.append(ValidationFinding(
                    code: .activationAreaDetached,
                    path: path.field("activationArea"),
                    message: "Die Trefferfläche der Zone „\(zone.name)" überschneidet ihren "
                        + "eigenen Zielrahmen nicht. Erlaubt — so lässt sich eine Zone am "
                        + "Bildschirmrand auslösen —, aber häufiger ein Versehen."
                ))
            }

            let preferred = layout.zones
                .filter { $0.id != zone.id }
                .filter { other in prefers(other, over: zone) }
                .map { $0.activationArea ?? $0.frame }

            if RectangleCoverage.isCovered(rect(activation), by: preferred.map(rect)) {
                findings.append(ValidationFinding(
                    code: .zoneUnreachable,
                    path: path,
                    message: "Die Zone „\(zone.name)" ist nicht erreichbar: ihre Trefferfläche "
                        + "wird von kleineren Zonen derselben Ebene vollständig überdeckt. "
                        + "Gib ihr eine eigene „activationArea", die frei liegt."
                ))
            }
        }
        return findings
    }

    /// Dieselbe Ordnung wie im Treffertest: kleinere Fläche gewinnt, bei
    /// Gleichstand die kleinere Zonen-ID. Die Displays sind hier immer gleich,
    /// weil eine Ebene zu genau einem Display gehört.
    private func prefers(_ candidate: Zone, over zone: Zone) -> Bool {
        let a = area(candidate.activationArea ?? candidate.frame)
        let b = area(zone.activationArea ?? zone.frame)
        if a != b { return a < b }
        return candidate.id < zone.id
    }

    private func area(_ rect: RelativeRect) -> Double {
        max(0, rect.width) * max(0, rect.height)
    }

    private func intersects(_ lhs: RelativeRect, _ rhs: RelativeRect) -> Bool {
        lhs.x < rhs.x + rhs.width && lhs.x + lhs.width > rhs.x
            && lhs.y < rhs.y + rhs.height && lhs.y + lhs.height > rhs.y
    }

    /// Relative Einheiten in ein `WindowFrame` umgedeutet, nur um
    /// ``RectangleCoverage`` benutzen zu können. Die Achsenrichtung spielt für
    /// Überdeckung keine Rolle, solange alle Rechtecke gleich behandelt werden.
    private func rect(_ relative: RelativeRect) -> WindowFrame {
        WindowFrame(x: relative.x, y: relative.y, width: relative.width, height: relative.height)
    }
}
```

In `ConfigurationValidator.swift` die Liste (Zeile 12-18) erweitern — nach `GeometryCheck()`:

```swift
            GeometryCheck(),
            ZoneReachabilityCheck(),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter "Prüfung — erreichbare Zonen"`
Expected: 5 Tests grün.

- [ ] **Step 5: Run the whole suite**

Run: `swift test`
Expected: 618 grün. **Achtung:** bestehende Validierungstests, die auf eine leere Befundliste prüfen, können jetzt zusätzlich `zoneUnreachable` melden, falls ihre Testkonfigurationen gestapelte Zonen enthalten. Schlägt ein solcher Test fehl, ist das ein **echter Fund** — die Testkonfiguration enthält dann eine unerreichbare Zone. Den Test anpassen, nicht den Check.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenZonrCore/Validation/ Tests/OpenZonrCoreTests/ZoneReachabilityCheckTests.swift
git commit -m "feat(core): Prüfung meldet unerreichbare Zonen

Eine Zone ist unerreichbar, wenn die Vereinigung der Trefferflächen bevorzugter
Zonen sie lückenlos überdeckt. Beide neuen Befunde sind Warnungen: eine
unerreichbare Zone ist ärgerlich, kein Grund, die Datei abzulehnen.

Die Ebene des Autors steht als Fixture im Test und meldet right-quarter."
```

---

### Task 7: Overlay zeichnet Kontur und Füllung

**Files:**
- Modify: `Sources/OpenZonrApp/Dropzone/DropzoneOverlay.swift:70-84` (`union(of:)`), `:87-140` (`DropzoneOverlayView`)
- Test: `Tests/OpenZonrCoreTests/DropzoneOverlayPlanActivationTests.swift` (neu)

**Interfaces:**
- Consumes: `Dropzone.activationFrame` aus Task 2
- Produces: keine — reine Zeichenänderung plus ein Beleg am Plan

`DropzoneOverlayPlan` bleibt unverändert: `Plan.show(zones:highlighted:)` trägt bereits beides, weil jede `Dropzone` ihre Trefferfläche mitbringt.

- [ ] **Step 1: Write the failing test**

`Tests/OpenZonrCoreTests/DropzoneOverlayPlanActivationTests.swift`:

```swift
import Foundation
import Testing

@testable import OpenZonrCore

/// Der Plan muss beides hergeben: die Trefferflächen aller Zonen der Ebene (für
/// die Konturen) und den Zielrahmen der getroffenen (für die Füllung).
@Suite("Overlay-Plan — Trefferflächen")
struct DropzoneOverlayPlanActivationTests {

    private static let visible = VisibleFrame(x: 0, y: 0, width: 1000, height: 800)

    private func zone(_ id: String, frame: WindowFrame, activation: WindowFrame) -> Dropzone {
        Dropzone(
            display: DisplayAlias(rawValue: "haupt"),
            zone: ZoneID(rawValue: id),
            name: id,
            relativeFrame: .full,
            frame: frame,
            visibleFrame: Self.visible,
            activationFrame: activation
        )
    }

    @Test("Der Plan trägt Trefferflächen und getroffenen Zielrahmen getrennt")
    func planCarriesBoth() {
        let zones = [
            zone("ganz",
                 frame: WindowFrame(x: 600, y: 0, width: 400, height: 800),
                 activation: WindowFrame(x: 600, y: 350, width: 400, height: 100)),
            zone("oben",
                 frame: WindowFrame(x: 600, y: 400, width: 400, height: 400),
                 activation: WindowFrame(x: 600, y: 700, width: 400, height: 100))
        ]
        let plan = DropzoneOverlayPlan.Plan.show(
            zones: zones,
            highlighted: DropzoneMap.zone(at: ScreenPoint(x: 700, y: 400), in: zones)
        )

        // Konturen: alle Trefferflächen der Ebene.
        #expect(plan.zones.map(\.activationFrame) == [
            WindowFrame(x: 600, y: 350, width: 400, height: 100),
            WindowFrame(x: 600, y: 700, width: 400, height: 100)
        ])
        // Füllung: der Zielrahmen der getroffenen Zone, nicht ihr Streifen.
        #expect(plan.highlighted?.frame == WindowFrame(x: 600, y: 0, width: 400, height: 800))
        #expect(plan.highlighted?.zone.rawValue == "ganz")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "Overlay-Plan — Trefferflächen"`
Expected: grün nach Task 2/3 — dieser Test ist ein **Beleg**, kein Treiber. Läuft er rot, ist etwas in Task 2 oder 3 falsch; dann dort nachbessern statt hier.

- [ ] **Step 3: Write the drawing change**

In `DropzoneOverlay.swift` muss `union(of:)` beide Rechtecke einschliessen, sonst wird eine Trefferfläche ausserhalb des Zielrahmens abgeschnitten:

```swift
    private func union(of zones: [Dropzone]) -> WindowFrame {
        // Beide Rechtecke jeder Zone: eine Trefferfläche darf ausserhalb ihres
        // Zielrahmens liegen (Randauslösung), und ein Fenster, das nur die
        // Zielrahmen umspannt, schnitte sie ab.
        let rects = zones.flatMap { [$0.frame, $0.activationFrame] }
        guard var minX = rects.first?.x, var minY = rects.first?.y else {
            return WindowFrame(x: 0, y: 0, width: 0, height: 0)
        }
        var maxX = minX
        var maxY = minY
        for rect in rects {
            minX = min(minX, rect.x)
            minY = min(minY, rect.y)
            maxX = max(maxX, rect.x + rect.width)
            maxY = max(maxY, rect.y + rect.height)
        }
        return WindowFrame(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
```

In `DropzoneOverlayView.draw(_:)` die Zeichnung so ordnen:

1. Für **jede** Zone der Ebene: `activationFrame` als dünne Kontur (1 Punkt, gedämpfte Farbe, kein Füllen).
2. Für die **getroffene** Zone: `frame` gefüllt, wie bisher die hervorgehobene Zone gezeichnet wurde, plus Name und Anheft-Marke.

Die Marke sitzt weiterhin dort, wo `DropzoneMap.pinBadgeFrame(for:)` sie meldet — nach Task 4 also an der Trefferfläche. Der Zeichencode muss diese Funktion aufrufen und darf die Position **nicht** selbst nachrechnen.

- [ ] **Step 4: Run the whole suite and build the app**

Run: `swift test && swift build`
Expected: 619 grün, Bau ohne Warnungen.

- [ ] **Step 5: Look at it**

```bash
./Scripts/bundle.sh && open -n ~/Applications/OpenZonr.app
```

Eine Zone der aktiven Ebene vorübergehend mit einer kleinen `activationArea` versehen, ein Fenster mit gehaltener ⌘ ziehen und prüfen: dünne Konturen für alle, gefüllter Zielrahmen beim Treffer.

- [ ] **Step 6: Commit**

```bash
git add Sources/OpenZonrApp/Dropzone/DropzoneOverlay.swift Tests/OpenZonrCoreTests/DropzoneOverlayPlanActivationTests.swift
git commit -m "feat(app): Overlay zeigt Trefferflächen als Kontur, Zielrahmen gefüllt

union(of:) schliesst beide Rechtecke ein, sonst schnitte das Overlay-Fenster
eine Trefferfläche ab, die ausserhalb ihres Zielrahmens liegt."
```

---

### Task 8: Dokumentation

**Files:**
- Modify: `docs/dropzones.md`, `docs/konfiguration.md`
- Modify: `Sources/OpenZonrCore/Geometry/Zone.swift:46-52` (Begründung des `margin`)

**Interfaces:**
- Consumes: alles Vorherige
- Produces: nichts

- [ ] **Step 1: Kommentar zum `margin` nachziehen**

In `Zone.swift` steht heute, der Rand wirke nur beim Platzieren, „damit sieht man Luft zwischen den Fenstern und zieht trotzdem über eine **geschlossene Fläche**". Mit eigenen Trefferflächen stimmt der zweite Teil nicht mehr. Ergänzen:

```swift
/// Seit es Trefferflächen gibt (``Zone/activationArea``), gilt der zweite Teil
/// nur noch für Ebenen ohne eigene Trefferflächen: wer welche zeichnet, macht
/// die Fläche absichtlich lückenhaft. Der Rand wirkt auf sie ohnehin nicht.
```

- [ ] **Step 2: `docs/konfiguration.md`**

Im Abschnitt über `zones` das Feld dokumentieren: `activationArea`, optional, derselbe Koordinatenraum wie `frame` (relativ zum sichtbaren Rahmen, Ursprung oben links), Rückfall auf `frame`. Mit dem Beispiel aus der Spec und dem Hinweis, dass eine Trefferfläche unter 72 Punkten keinen Anheft-Punkt mehr trägt.

- [ ] **Step 3: `docs/dropzones.md`**

Den Begriff einführen und den Fall erklären, der ihn nötig macht — gestapelte Zonen, „Rechts außen" unerreichbar. Die Tabelle der gemessenen Fälle bleibt unverändert; **nichts** als gemessen behaupten, was nicht gemessen wurde. Insbesondere gilt die Randauslösung als *möglich*, nicht als *erprobt*.

- [ ] **Step 4: Commit**

```bash
git add docs/ Sources/OpenZonrCore/Geometry/Zone.swift
git commit -m "docs: Trefferflächen beschreiben, margin-Begründung nachziehen

Die Begründung des Rands ('zieht über eine geschlossene Fläche') gilt nur noch
für Ebenen ohne eigene Trefferflächen. Randauslösung steht als möglich, nicht
als erprobt."
```

---

## Self-Review

**Spec coverage.** Datenmodell → Task 1 + 2. Treffertest → Task 3. Anheft-Punkt → Task 4. Overlay → Task 7. Prüfung (beide Befunde) → Task 5 + 6. Tests-Tabelle der Spec: gestapelt/disjunkt → Task 3; ohne Feld unverändert → Task 1, 2, 3; Ebene des Autors als Fixture → Task 6; ausserhalb des Zielrahmens → Task 3; Anheft-Punkt → Task 4; unter 72 Punkten → Task 4; Overlay-Plan → Task 7; Gleichstand → Task 3; Vereinigung statt paarweise → Task 5 + 6. Doku → Task 8. **Keine Lücke.**

**Placeholder scan.** Kein TBD, kein „siehe Task N", kein „Fehlerbehandlung ergänzen". Jeder Code-Schritt trägt den Code. Einzige Ausnahme mit Absicht: Task 7, Schritt 3 beschreibt die Zeichnung in Worten statt in Code — die Datei ist AppKit-Zeichencode, dessen genaue Gestalt (Farben, Linienstärke) Geschmack ist und im Bestand steht. Die *Regel* ist präzise: Kontur je Zone aus `activationFrame`, Füllung der getroffenen aus `frame`, Marke ausschliesslich über `pinBadgeFrame(for:)`.

**Type consistency.** `activationArea: RelativeRect?` (Zone) und `activationFrame: WindowFrame` (Dropzone) durchgängig; nie vertauscht. `RectangleCoverage.isCovered(_:by:)` in Task 5 definiert, in Task 6 mit derselben Signatur benutzt. `ValidationCode.zoneUnreachable` / `.activationAreaDetached` in Task 6 definiert und dort benutzt. `Dropzone.init` bekommt `activationFrame` als **letztes** Argument mit Vorgabe, damit alle bestehenden Aufrufstellen gültig bleiben — in Task 3, 4, 7 wird genau so konstruiert.

**Offen und bewusst so.** Die Testzahlen (593, 596, …) sind Erwartungen aus 589 plus den neuen Tests. Weicht eine ab, ist das kein Grund, die Zahl anzupassen, sondern nachzusehen warum — besonders in Task 6, wo ein bestehender Validierungstest einen echten Fund melden kann.
