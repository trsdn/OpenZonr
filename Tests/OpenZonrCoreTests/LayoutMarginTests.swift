import Foundation
import Testing

@testable import OpenZonrCore

/// Der Randwert eines Layouts wirkt beim Platzieren, nicht beim Treffertest.
///
/// Zwei Tests, ein Prinzip: das Fenster bekommt seine Luft (``ZoneResolver``),
/// das Overlay bleibt lückenlos (``DropzoneMap``). Wer den Rand an beiden
/// Stellen abzöge, hätte optisch dasselbe Ergebnis und ein Overlay, das an
/// jeder Naht blinkt — der Zusammenhang wäre schwer zu finden, weil die
/// Fenster ja richtig liegen. Dieser Test hält das Prinzip fest.
struct LayoutMarginTests {

    private let display: DisplayAlias = "main"
    private let layoutID: LayoutID = "halves"

    private func makeConfiguration(margin: Double) -> Configuration {
        var config = TestConfigurations.minimal()
        config.displays[0].layouts[0].margin = margin
        return config
    }

    @Test("Beim Platzieren schrumpft die Zone um den Rand")
    func placementShrinksByMargin() {
        let config = makeConfiguration(margin: 0.05)
        let resolver = DefaultZoneResolver()
        let profile = config.profiles[0]
        let visible = VisibleFrame(x: 0, y: 0, width: 1000, height: 1000)

        let result = resolver.resolve(
            role: "editor",
            share: nil,
            profile: profile,
            configuration: config,
            visibleFrames: [display: visible]
        )
        let placement = try? result.get()
        // Zone „left" (0/0/0.5/1) → ohne Rand: x=0 y=0 w=500 h=1000.
        // Mit Rand 5 % (50 pt an jeder Seite): x=50 y=50 w=400 h=900.
        #expect(placement?.frame.x == 50)
        #expect(placement?.frame.width == 400)
        #expect(placement?.frame.height == 900)
    }

    @Test("Beim Treffertest bleibt die Zone ungeschrumpft")
    func hitTestKeepsFullZone() {
        let config = makeConfiguration(margin: 0.05)
        let visible = VisibleFrame(x: 0, y: 0, width: 1000, height: 1000)
        let zones = DropzoneMap.zones(
            in: config,
            profile: config.profiles[0].id,
            visibleFrames: [display: visible]
        )
        // Ohne Rand-Effekt im Treffertest: die halben Zonen kacheln die
        // Fläche lückenlos. Ein Punkt in der Mitte der linken Hälfte trifft
        // „left", ein Punkt weit in der rechten Hälfte trifft „right".
        #expect(DropzoneMap.zone(at: ScreenPoint(x: 100, y: 500), in: zones)?.zone == "left")
        #expect(DropzoneMap.zone(at: ScreenPoint(x: 900, y: 500), in: zones)?.zone == "right")
    }

    @Test("Ein Punkt exakt auf der Naht liefert genau eine Zone")
    func seamBelongsToExactlyOneZone() {
        // Wer den Rand an beiden Stellen abzöge, hätte an der Naht (x=500)
        // zwei Randabstände, die sich nicht berühren — und der Zeiger fiele
        // ins Nichts. Der Treffertest darf das nicht: die Kante gehört
        // *einer* Zone.
        let config = makeConfiguration(margin: 0.05)
        let visible = VisibleFrame(x: 0, y: 0, width: 1000, height: 1000)
        let zones = DropzoneMap.zones(
            in: config,
            profile: config.profiles[0].id,
            visibleFrames: [display: visible]
        )
        let hit = DropzoneMap.zone(at: ScreenPoint(x: 500, y: 500), in: zones)
        #expect(hit != nil, "Ein Punkt auf der Naht darf nicht ins Leere fallen")
        // Ohne asymmetrische Kantenregel wäre die Antwort von der
        // Reihenfolge abhängig; ``WindowFrame.contains`` schließt die rechte
        // Kante aus, also gehört x=500 zur rechten Zone.
        #expect(hit?.zone == "right")
    }

    @Test("Rand von Null erhält das bisherige Verhalten")
    func zeroMarginPreservesLegacyBehaviour() {
        let config = makeConfiguration(margin: 0)
        let resolver = DefaultZoneResolver()
        let visible = VisibleFrame(x: 0, y: 0, width: 1000, height: 1000)
        let result = resolver.resolve(
            role: "editor",
            share: nil,
            profile: config.profiles[0],
            configuration: config,
            visibleFrames: [display: visible]
        )
        let placement = try? result.get()
        #expect(placement?.frame.x == 0)
        #expect(placement?.frame.width == 500)
        #expect(placement?.frame.height == 1000)
    }
}

/// Coding-Verhalten des neuen ``Layout/margin``-Feldes.
///
/// Ohne diese Zusicherungen würde eine Konfiguration aus der Zeit vor dem
/// Feld beim Laden abgelehnt, und jede Anzeige des Editors, die einen Rand
/// von Null trägt, machte eine neue Zeile im Diff.
struct LayoutMarginCodingTests {

    @Test("Ein fehlender Rand im JSON wird als Null gelesen")
    func missingMarginDecodesAsZero() throws {
        let json = #"""
        {"id":"halves","name":"Zwei Hälften","zones":[]}
        """#.data(using: .utf8)!
        let layout = try JSONDecoder().decode(Layout.self, from: json)
        #expect(layout.margin == 0)
    }

    @Test("Ein Rand von Null wird beim Kodieren nicht geschrieben")
    func zeroMarginIsOmittedOnEncoding() throws {
        let layout = Layout(id: "halves", name: "Zwei Hälften", zones: [], margin: 0)
        let data = try JSONEncoder().encode(layout)
        let json = String(data: data, encoding: .utf8)!
        #expect(!json.contains("margin"))
    }

    @Test("Ein Rand ungleich Null wird beim Kodieren geschrieben und wieder gelesen")
    func nonZeroMarginRoundTrips() throws {
        let original = Layout(id: "halves", name: "Zwei Hälften", zones: [], margin: 0.05)
        let data = try JSONEncoder().encode(original)
        let json = String(data: data, encoding: .utf8)!
        #expect(json.contains("margin"))
        let decoded = try JSONDecoder().decode(Layout.self, from: data)
        #expect(decoded.margin == 0.05)
    }
}
