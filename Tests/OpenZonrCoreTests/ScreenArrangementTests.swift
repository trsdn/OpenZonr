import Foundation
import Testing

@testable import OpenZonrCore

/// The coordinate conversion, tested against a real, measured arrangement.
///
/// The numbers in this suite are not invented. They were read from the author's
/// desk: a 5120×1440 Samsung C49RG9x as the main display, with three 1920×1080
/// panels placed *above* it. That arrangement is what makes the test sharp —
/// with displays of equal height a wrong conversion still lands on the right
/// screen, and the bug survives.
@Suite("Bildschirmanordnung und Koordinatenumrechnung")
struct ScreenArrangementTests {

    // MARK: - Measured fixtures

    /// Samsung C49RG9x, the main display. Serial number 0, hence the fallback.
    static func ultrawide() -> DisplaySnapshot {
        DisplaySnapshot(
            identity: .fallback(
                vendorNumber: 19501,
                modelNumber: 3996,
                pixelWidth: 5120,
                pixelHeight: 1440,
                portIndex: 1
            ),
            localizedName: "C49RG9x",
            displayID: 2,
            pixelWidth: 5120,
            pixelHeight: 1440,
            backingScaleFactor: 1,
            frame: WindowFrame(x: 0, y: 0, width: 5120, height: 1440),
            // Only the main display reports a reduced visible frame: 96 points
            // go to the menu bar and the Dock.
            visibleFrame: WindowFrame(x: 0, y: 65, width: 5120, height: 1344),
            portIndex: 1,
            isPrimary: true
        )
    }

    /// Samsung U28E590, placed above and to the right. Full EDID identity.
    static func secondary() -> DisplaySnapshot {
        DisplaySnapshot(
            identity: .edid(vendorNumber: 19501, modelNumber: 3149, serialNumber: 810_375_238),
            localizedName: "U28E590",
            displayID: 1,
            pixelWidth: 3840,
            pixelHeight: 2160,
            backingScaleFactor: 2,
            frame: WindowFrame(x: 2833, y: 1440, width: 1920, height: 1080),
            // Measured: the secondary displays report visibleFrame == frame,
            // although each of them carries its own menu bar.
            visibleFrame: WindowFrame(x: 2833, y: 1440, width: 1920, height: 1080),
            portIndex: 0
        )
    }

    /// "AAA", a virtual display, placed above and to the left.
    static func virtualDisplay() -> DisplaySnapshot {
        DisplaySnapshot(
            identity: .fallback(
                vendorNumber: 21252,
                modelNumber: 0,
                pixelWidth: 1920,
                pixelHeight: 1080,
                portIndex: 2
            ),
            localizedName: "AAA",
            displayID: 3,
            pixelWidth: 1920,
            pixelHeight: 1080,
            backingScaleFactor: 1,
            frame: WindowFrame(x: -1007, y: 1440, width: 1920, height: 1080),
            visibleFrame: WindowFrame(x: -1007, y: 1440, width: 1920, height: 1080),
            // Measured — a software display reporting a perfectly plausible
            // panel size, which is why size cannot be used to detect one.
            physicalSizeMillimeters: WindowSize(width: 677.3, height: 381.0),
            portIndex: 2,
            isLikelyVirtual: true
        )
    }

    static func arrangement() -> ScreenArrangement {
        ScreenArrangement(snapshots: [ultrawide(), secondary(), virtualDisplay()])
    }

    // MARK: - Tests

    @Test("Der Umrechnungspivot ist die Oberkante des Hauptbildschirms")
    func pivotIsPrimaryTopEdge() {
        #expect(Self.arrangement().primaryTopY == 1440)
    }

    @Test("AppKit-Frames der Nebenbildschirme werden auf die gemessenen AX-Werte gespiegelt")
    func secondaryDisplaysMatchMeasuredAccessibilityBounds() {
        let arrangement = Self.arrangement()

        // Measured with CGDisplayBounds: 2833,-1080 1920x1080.
        let secondary = arrangement.flipVertically(Self.secondary().frame)
        #expect(secondary.x == 2833)
        #expect(secondary.y == -1080)

        // Measured: -1007,-1080 1920x1080.
        let virtualDisplay = arrangement.flipVertically(Self.virtualDisplay().frame)
        #expect(virtualDisplay.x == -1007)
        #expect(virtualDisplay.y == -1080)
    }

    @Test("Der Hauptbildschirm liegt in beiden Systemen im Ursprung")
    func primaryDisplayStaysAtOrigin() {
        let flipped = Self.arrangement().flipVertically(Self.ultrawide().frame)
        #expect(flipped == Self.ultrawide().frame)
    }

    @Test("Die Spiegelung ist ihre eigene Umkehrung")
    func flipIsItsOwnInverse() {
        let arrangement = Self.arrangement()
        let original = WindowFrame(x: 2833, y: 1440, width: 800, height: 600)
        #expect(arrangement.flipVertically(arrangement.flipVertically(original)) == original)
    }

    @Test("Eine Zone auf dem Nebenbildschirm landet nicht auf dem Hauptbildschirm")
    func zoneOnSecondaryDisplayDoesNotLandOnPrimary() throws {
        // The regression this whole suite exists for: without the flip, a frame
        // computed for the display above ends up with a positive y and therefore
        // inside the ultrawide.
        let arrangement = Self.arrangement()
        let visible = Self.secondary().visibleFrame

        // Top-left quarter of the secondary display, in AppKit coordinates.
        let appKitFrame = WindowFrame(
            x: visible.x,
            y: visible.y + visible.height / 2,
            width: visible.width / 2,
            height: visible.height / 2
        )
        let axFrame = arrangement.flipVertically(appKitFrame)

        #expect(axFrame.y == -1080)
        let display = try #require(arrangement.display(containingAccessibilityFrame: axFrame))
        #expect(display.localizedName == "U28E590")
    }

    @Test("Sichtbare Frames werden pro Bildschirm übernommen, nicht global abgeleitet")
    func visibleFramesArePerDisplay() throws {
        let descriptors = [
            descriptor(alias: "ultrawide", identity: Self.ultrawide().identity),
            descriptor(alias: "secondary", identity: Self.secondary().identity)
        ]
        let frames = Self.arrangement().visibleFrames(for: descriptors)

        let ultrawide = try #require(frames[DisplayAlias(rawValue: "ultrawide")])
        let secondary = try #require(frames[DisplayAlias(rawValue: "secondary")])

        // 1344 of 1440 on the main display, full height everywhere else. A
        // global menu bar subtraction would be wrong on three displays of four.
        #expect(ultrawide.height == 1344)
        #expect(secondary.height == 1080)
    }

    @Test("Nicht angeschlossene Bildschirme liefern keinen sichtbaren Frame")
    func unattachedDisplaysAreAbsent() {
        let descriptors = [
            descriptor(alias: "elsewhere", identity: .edid(vendorNumber: 1, modelNumber: 2, serialNumber: 3))
        ]
        #expect(Self.arrangement().visibleFrames(for: descriptors).isEmpty)
    }

    @Test("Der Bildschirm mit der größten Überdeckung gewinnt")
    func largestOverlapWins() throws {
        let arrangement = Self.arrangement()
        // Straddles the boundary, mostly on the ultrawide.
        let frame = WindowFrame(x: 2900, y: -100, width: 400, height: 400)
        let display = try #require(arrangement.display(containingAccessibilityFrame: frame))
        #expect(display.localizedName == "C49RG9x")
    }

    @Test("Ein Fenster außerhalb aller Bildschirme hat kein Display")
    func windowOutsideEveryDisplay() {
        #expect(
            Self.arrangement()
                .display(containingAccessibilityFrame: WindowFrame(x: 40_000, y: 40_000, width: 100, height: 100)) == nil
        )
    }

    @Test("Die Abweichung ist das Maximum über alle Kanten, nicht die Summe")
    func deviationIsMaximumPerEdge() {
        let target = WindowFrame(x: 100, y: 100, width: 800, height: 600)
        let actual = WindowFrame(x: 102, y: 100, width: 800, height: 570)
        #expect(actual.maximumDeviation(from: target) == 30)
    }

    // MARK: - Fingerprint

    @Test("Virtuelle Bildschirme verändern den Fingerprint nicht, wenn sie ignoriert werden")
    func ignoredDisplaysStayOutOfTheFingerprint() {
        let all = [Self.ultrawide(), Self.secondary(), Self.virtualDisplay()]

        let unfiltered = SetupFingerprint(snapshots: all)
        #expect(unfiltered.displays.count == 3)

        // Starting OBS must not move the desk.
        let filtered = SetupFingerprint(snapshots: all, ignoring: [Self.virtualDisplay().identity])
        #expect(filtered.displays.count == 2)
        #expect(filtered == SetupFingerprint(snapshots: [Self.ultrawide(), Self.secondary()]))
    }

    @Test("Der Fallback ohne Seriennummer trennt zwei Bildschirme desselben Herstellers")
    func fallbackSeparatesSameVendor() {
        // Both attached Samsungs report vendor 19501. Only the model number
        // tells them apart, so a fallback over vendor plus resolution would
        // collide — which is exactly why the model number is part of it.
        let ultrawide = Self.ultrawide()
        let sameVendorDifferentModel = DisplayIdentity.fallback(
            vendorNumber: 19501,
            modelNumber: 3149,
            pixelWidth: 5120,
            pixelHeight: 1440,
            portIndex: 1
        )

        #expect(ultrawide.usesSerialFallback)
        #expect(ultrawide.identity != sameVendorDifferentModel)
    }

    // MARK: - Helpers

    private func descriptor(alias: String, identity: DisplayIdentity) -> DisplayDescriptor {
        DisplayDescriptor(
            alias: DisplayAlias(rawValue: alias),
            displayName: alias,
            identity: identity,
            layouts: [
                Layout(
                    id: "full",
                    name: "Vollbild",
                    zones: [Zone(id: "full", name: "Vollbild", frame: RelativeRect(x: 0, y: 0, width: 1, height: 1))]
                )
            ],
            defaultLayoutID: "full"
        )
    }
}
