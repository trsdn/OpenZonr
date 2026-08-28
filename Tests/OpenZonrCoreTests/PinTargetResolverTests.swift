import Foundation
import Testing
@testable import OpenZonrCore

/// "Das Fenster hier festhalten" needs to answer *where* "hier" is. That answer
/// is geometry, and geometry is where this project has already been bitten
/// once — the two coordinate systems disagree about which way `y` grows. These
/// tests check the conversion against the placement path's own conversion
/// rather than against a hand-computed number, because a number computed by
/// hand can be wrong the same way twice.
struct PinTargetResolverTests {

    private let frame = TestConfigurations.mainVisibleFrame

    // MARK: - The conversion

    @Test("Der Rundlauf durch beide Umrechnungen ergibt wieder denselben Frame")
    func conversionRoundTrips() throws {
        let zone = RelativeRect(x: 0.25, y: 0.1, width: 0.5, height: 0.4)

        // Der Weg hinaus ist der der Platzierung, gemessen an der bereits
        // getesteten Zonenauflösung.
        let configuration = TestConfigurations.minimal {
            $0.displays[0].layouts[0].zones = [Zone(id: "ziel", name: "Ziel", frame: zone)]
            $0.profiles[0].roleBindings = [RoleBinding(role: "editor", display: "main", zone: "ziel")]
            $0.profiles[0].fallback = RoleBinding(role: "editor", display: "main", zone: "ziel")
        }
        let resolved = try DefaultZoneResolver().resolve(
            role: "editor",
            share: nil,
            profile: configuration.profiles[0],
            configuration: configuration,
            visibleFrames: ["main": frame]
        ).get()

        let back = try #require(PinTargetResolver.relativeRect(of: resolved.frame, in: frame))
        #expect(abs(back.x - zone.x) < 0.001)
        #expect(abs(back.y - zone.y) < 0.001)
        #expect(abs(back.width - zone.width) < 0.001)
        #expect(abs(back.height - zone.height) < 0.001)
    }

    @Test("Der Ursprung liegt oben links, nicht unten links")
    func originIsTopLeft() throws {
        // Ein Fenster in der oberen Hälfte eines Bildschirms, dessen sichtbarer
        // Frame bei y = 70 beginnt und 985 Punkte hoch ist.
        let window = WindowFrame(x: 0, y: 70 + 985 / 2, width: 1920, height: 985 / 2)
        let relative = try #require(PinTargetResolver.relativeRect(of: window, in: frame))

        #expect(abs(relative.y - 0) < 0.001)
        #expect(abs(relative.height - 0.5) < 0.001)
    }

    @Test("Ein Bildschirm mit negativem Ursprung wird richtig gerechnet")
    func negativeOriginIsOrdinary() throws {
        let left = TestConfigurations.leftVisibleFrame
        let window = WindowFrame(x: -1440, y: 0, width: 720, height: 900)
        let relative = try #require(PinTargetResolver.relativeRect(of: window, in: left))

        #expect(abs(relative.x - 0) < 0.001)
        #expect(abs(relative.width - 0.5) < 0.001)
    }

    // MARK: - The display

    @Test("Das Fenster gehört dem Bildschirm, der das meiste davon zeigt")
    func displayIsChosenByOverlap() {
        let configuration = TestConfigurations.minimal {
            $0.displays.append(
                DisplayDescriptor(
                    alias: "links",
                    displayName: "Links",
                    identity: .edid(vendorNumber: 1, modelNumber: 2, serialNumber: 3),
                    layouts: [Layout(id: "voll", name: "Voll", zones: [Zone(id: "voll", name: "Voll", frame: .full)])],
                    defaultLayoutID: "voll"
                )
            )
        }
        let frames: VisibleFrames = ["main": frame, "links": TestConfigurations.leftVisibleFrame]

        // Ein Fenster, das über die Grenze ragt, aber überwiegend links liegt.
        let straddling = WindowFrame(x: -400, y: 100, width: 500, height: 600)
        #expect(
            PinTargetResolver.display(containing: straddling, in: configuration, visibleFrames: frames) == "links"
        )

        // Und eines, das gar keinen Bildschirm berührt.
        let nowhere = WindowFrame(x: 100_000, y: 100_000, width: 100, height: 100)
        #expect(
            PinTargetResolver.display(containing: nowhere, in: configuration, visibleFrames: frames) == nil
        )
    }

    // MARK: - The zone

    @Test("Die passende Zone gewinnt gegen die größere")
    func snugZoneBeatsTheLargeOne() {
        let layout = Layout(
            id: "gemischt",
            name: "Gemischt",
            zones: [
                Zone(id: "voll", name: "Voll", frame: .full),
                Zone(id: "rechts", name: "Rechts", frame: RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1))
            ]
        )

        // Die volle Zone enthält das Fenster ganz — nach reiner Überlappung
        // würde sie immer gewinnen. Gemessen wird deshalb Schnitt durch
        // Vereinigung.
        let window = RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1)
        #expect(PinTargetResolver.zone(bestMatching: window, in: layout) == "rechts")
    }

    @Test("Ohne Überschneidung gibt es keine Zone")
    func noOverlapMeansNoAnswer() {
        let layout = Layout(
            id: "halb",
            name: "Halb",
            zones: [Zone(id: "links", name: "Links", frame: RelativeRect(x: 0, y: 0, width: 0.5, height: 1))]
        )

        #expect(
            PinTargetResolver.zone(
                bestMatching: RelativeRect(x: 0.6, y: 0, width: 0.4, height: 1),
                in: layout
            ) == nil
        )
    }

    @Test("Gleichstand entscheidet der Bezeichner, nicht die Reihenfolge im Array")
    func tiesAreBrokenDeterministically() {
        let frame = RelativeRect(x: 0, y: 0, width: 0.5, height: 1)
        let ab = Layout(id: "l", name: "L", zones: [
            Zone(id: "b", name: "B", frame: frame),
            Zone(id: "a", name: "A", frame: frame)
        ])
        let ba = Layout(id: "l", name: "L", zones: [
            Zone(id: "a", name: "A", frame: frame),
            Zone(id: "b", name: "B", frame: frame)
        ])

        #expect(PinTargetResolver.zone(bestMatching: frame, in: ab) == "a")
        #expect(PinTargetResolver.zone(bestMatching: frame, in: ba) == "a")
    }

    // MARK: - The whole answer

    @Test("Aus Fenster und Bildschirmen wird ein Ziel")
    func resolveProducesATarget() throws {
        let configuration = TestConfigurations.minimal()
        // Rechte Hälfte des Hauptbildschirms.
        let window = WindowFrame(x: 960, y: 70, width: 960, height: 985)

        let target = try #require(
            PinTargetResolver.resolve(
                windowFrame: window,
                configuration: configuration,
                profile: "solo",
                visibleFrames: ["main": frame]
            )
        )
        #expect(target == QuickPin.Target(display: "main", zone: "right"))
    }

    @Test("Das Ziel folgt dem Layout, das das Profil wählt")
    func targetFollowsTheProfileLayout() throws {
        let configuration = TestConfigurations.minimal {
            $0.displays[0].layouts.append(
                Layout(id: "drittel", name: "Drittel", zones: [
                    Zone(id: "links-drittel", name: "Links", frame: RelativeRect(x: 0, y: 0, width: 1.0 / 3, height: 1)),
                    Zone(id: "mitte-drittel", name: "Mitte", frame: RelativeRect(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1)),
                    Zone(id: "rechts-drittel", name: "Rechts", frame: RelativeRect(x: 2.0 / 3, y: 0, width: 1.0 / 3, height: 1))
                ])
            )
            $0.profiles[0].layouts = ["main": "drittel"]
        }
        let window = WindowFrame(x: 640, y: 70, width: 640, height: 985)

        let target = try #require(
            PinTargetResolver.resolve(
                windowFrame: window,
                configuration: configuration,
                profile: "solo",
                visibleFrames: ["main": frame]
            )
        )
        #expect(target.zone == "mitte-drittel")
    }

    // MARK: - Editing geometry

    @Test("Zonen rasten auf Hälften, Drittel und Viertel ein")
    func snappingHitsTheUsualFractions() {
        let snapped = RelativeRect(x: 0.4993, y: 0.01, width: 0.2512, height: 0.98).snapped()

        #expect(abs(snapped.x - 0.5) < 0.0001)
        #expect(abs(snapped.y - 0) < 0.0001)
        #expect(abs(snapped.width - 0.25) < 0.0001)
        #expect(abs(snapped.height - 1) < 0.0001)
    }

    @Test("Eine Zone jenseits des Randes wird zurückgeholt, nicht verformt")
    func clampingKeepsTheSize() {
        let clamped = RelativeRect(x: 0.8, y: -0.3, width: 0.5, height: 0.5).clampedToUnitSquare()

        #expect(clamped.width == 0.5)
        #expect(clamped.height == 0.5)
        #expect(clamped.x == 0.5)
        #expect(clamped.y == 0)
    }

    @Test("Eine auf null geschrumpfte Zone behält eine Mindestgröße")
    func clampingKeepsAMinimum() {
        let clamped = RelativeRect(x: 0.5, y: 0.5, width: 0, height: -0.2).clampedToUnitSquare(minimum: 0.05)

        #expect(clamped.width == 0.05)
        #expect(clamped.height == 0.05)
        // Und das Ergebnis ist gültig, statt den Validator zu beschäftigen.
        let configuration = TestConfigurations.minimal {
            $0.displays[0].layouts[0].zones[0].frame = clamped
        }
        #expect(ConfigurationValidator().validate(configuration).errors.isEmpty)
    }
}
