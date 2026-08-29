import Foundation
import Testing

@testable import OpenZonrCore

/// The part of dropzones that needs no permission, no window server and no
/// hand on the mouse.
///
/// That is deliberate. Observing a drag requires the Accessibility permission
/// that cannot be granted from here, so the feature was cut so that the
/// decisions — which zone is under this point, is the overlay suppressed, what
/// rule does this drop imply — are arithmetic, and arithmetic is provable.
struct DropzoneMapTests {

    private let visibleFrame = VisibleFrame(x: 0, y: 0, width: 1000, height: 1000)

    private func zone(_ id: String, _ rect: RelativeRect, display: DisplayAlias = "main") -> Dropzone {
        Dropzone(
            display: display,
            zone: ZoneID(rawValue: id),
            name: id,
            relativeFrame: rect,
            frame: ZoneGeometry.absoluteFrame(for: rect, in: visibleFrame),
            visibleFrame: visibleFrame
        )
    }

    @Test("Ein Punkt in der linken Hälfte trifft die linke Zone")
    func pointHitsLeftHalf() {
        let zones = [
            zone("left", RelativeRect(x: 0, y: 0, width: 0.5, height: 1)),
            zone("right", RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1)),
        ]
        #expect(DropzoneMap.zone(at: ScreenPoint(x: 100, y: 500), in: zones)?.zone == "left")
        #expect(DropzoneMap.zone(at: ScreenPoint(x: 900, y: 500), in: zones)?.zone == "right")
    }

    @Test("Die geteilte Kante gehört genau einer Zone")
    func sharedEdgeBelongsToExactlyOneZone() {
        let zones = [
            zone("left", RelativeRect(x: 0, y: 0, width: 0.5, height: 1)),
            zone("right", RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1)),
        ]
        // x = 500 is the right edge of "left" and the left edge of "right".
        // Without a rule both contain it and the answer depends on array order,
        // which is how a hit test becomes irreproducible.
        #expect(DropzoneMap.zone(at: ScreenPoint(x: 500, y: 500), in: zones)?.zone == "right")
    }

    @Test("Bei überlappenden Zonen gewinnt die kleinere")
    func smallerZoneWinsWhenOverlapping() {
        // The layout the concept encourages: a large focus zone stacked over two
        // halves. If the big one won, the halves could not be reached with the
        // mouse at all and the feature would be broken for exactly the layouts
        // it exists for.
        let zones = [
            zone("focus", RelativeRect(x: 0, y: 0, width: 1, height: 1)),
            zone("left", RelativeRect(x: 0, y: 0, width: 0.5, height: 1)),
        ]
        #expect(DropzoneMap.zone(at: ScreenPoint(x: 100, y: 500), in: zones)?.zone == "left")
        #expect(DropzoneMap.zone(at: ScreenPoint(x: 900, y: 500), in: zones)?.zone == "focus")
    }

    @Test("Gleich große Zonen werden nach Kennung entschieden, nicht nach Reihenfolge")
    func equalAreasAreDecidedDeterministically() {
        let a = zone("alpha", RelativeRect(x: 0, y: 0, width: 0.5, height: 1))
        let b = zone("beta", RelativeRect(x: 0, y: 0, width: 0.5, height: 1))
        let point = ScreenPoint(x: 100, y: 100)
        #expect(DropzoneMap.zone(at: point, in: [a, b])?.zone == "alpha")
        #expect(DropzoneMap.zone(at: point, in: [b, a])?.zone == "alpha")
    }

    @Test("Ein Punkt außerhalb aller Zonen trifft nichts")
    func pointOutsideHitsNothing() {
        let zones = [zone("left", RelativeRect(x: 0, y: 0, width: 0.5, height: 1))]
        #expect(DropzoneMap.zone(at: ScreenPoint(x: 5000, y: 5000), in: zones) == nil)
    }

    @Test("Nur die Zonen des Displays unter dem Zeiger werden gezeigt")
    func onlyZonesOfTheDisplayUnderThePointer() {
        // The real arrangement of the measuring machine: a 5120×1440 display at
        // the origin and a 1920×1080 one above it. Getting this wrong does not
        // place a window slightly off — it places it on the wrong screen.
        let wide = VisibleFrame(x: 0, y: 0, width: 5120, height: 1440)
        let above = VisibleFrame(x: 0, y: 1440, width: 1920, height: 1080)
        let zones = [
            Dropzone(
                display: "wide", zone: "left", name: "Links",
                relativeFrame: RelativeRect(x: 0, y: 0, width: 0.5, height: 1),
                frame: ZoneGeometry.absoluteFrame(for: RelativeRect(x: 0, y: 0, width: 0.5, height: 1), in: wide),
                visibleFrame: wide
            ),
            Dropzone(
                display: "above", zone: "full", name: "Ganz",
                relativeFrame: RelativeRect(x: 0, y: 0, width: 1, height: 1),
                frame: ZoneGeometry.absoluteFrame(for: RelativeRect(x: 0, y: 0, width: 1, height: 1), in: above),
                visibleFrame: above
            ),
        ]

        let onWide = DropzoneMap.zones(onDisplayUnder: ScreenPoint(x: 200, y: 200), in: zones)
        #expect(onWide.map(\.display) == ["wide"])

        let onAbove = DropzoneMap.zones(onDisplayUnder: ScreenPoint(x: 200, y: 2000), in: zones)
        #expect(onAbove.map(\.display) == ["above"])
    }

    @Test("In einer Lücke zwischen Zonen bleiben die Zonen sichtbar")
    func zonesStayVisibleInAGapBetweenThem() {
        // Layouts need not cover their screen. Deciding the display from the zone
        // under the pointer would make the whole overlay disappear whenever the
        // pointer crossed a gap — a flicker on every drag across a margin. The
        // display's own area decides instead.
        let zones = [
            zone("left", RelativeRect(x: 0, y: 0, width: 0.4, height: 1)),
            zone("right", RelativeRect(x: 0.6, y: 0, width: 0.4, height: 1)),
        ]
        let gap = ScreenPoint(x: 500, y: 500)
        #expect(DropzoneMap.zone(at: gap, in: zones) == nil)
        #expect(DropzoneMap.zones(onDisplayUnder: gap, in: zones).count == 2)
    }

    @Test("Zonen entstehen aus dem Profil, Displays ohne Bild werden übersprungen")
    func zonesComeFromTheProfileAndSkipDetachedDisplays() throws {
        let configuration = TestConfigurations.minimal()
        let profile = try #require(configuration.profiles.first)

        let attached = DropzoneMap.zones(
            in: configuration,
            profile: profile.id,
            visibleFrames: ["main": TestConfigurations.mainVisibleFrame]
        )
        #expect(attached.count == 2)

        // A display that is described but not attached has no visible frame, and
        // a zone on a monitor that is not there cannot be dropped into.
        let detached = DropzoneMap.zones(in: configuration, profile: profile.id, visibleFrames: [:])
        #expect(detached.isEmpty)
    }

    @Test("Die Zone liefert eine Platzierung im selben Typ wie der Regelweg")
    func zoneProducesTheSamePlacementTypeAsTheRulePath() throws {
        let configuration = TestConfigurations.minimal()
        let profile = try #require(configuration.profiles.first)
        let zones = DropzoneMap.zones(
            in: configuration,
            profile: profile.id,
            visibleFrames: ["main": TestConfigurations.mainVisibleFrame]
        )
        let dropped = try #require(zones.first)

        // Not a cosmetic check. Issue #10 requires the drop to use the automatic
        // half's placement logic; a Dropzone that produced its own frame type
        // would be the beginning of the second path the issue rules out.
        let placement = dropped.placement
        #expect(placement.frame == dropped.frame)
        #expect(placement.display == dropped.display)
        #expect(placement.zone == dropped.zone)
        #expect(placement.usedFallback == false)
    }

    @Test("Die Zonengeometrie ist dieselbe wie im Regelweg")
    func geometryMatchesTheResolver() throws {
        // ZoneGeometry was extracted from DefaultZoneResolver so that both paths
        // round edges identically. If they drift apart, dragging and the
        // automatic placement put the same window in two slightly different
        // places, and the gap between zones comes back.
        let configuration = TestConfigurations.minimal()
        let profile = try #require(configuration.profiles.first)
        let frames: VisibleFrames = ["main": TestConfigurations.mainVisibleFrame]

        let resolved = try DefaultZoneResolver().resolve(
            role: "communication",
            share: nil,
            profile: profile,
            configuration: configuration,
            visibleFrames: frames
        ).get()

        let zones = DropzoneMap.zones(in: configuration, profile: profile.id, visibleFrames: frames)
        let matching = try #require(zones.first { $0.zone == resolved.zone && $0.display == resolved.display })
        #expect(matching.frame == resolved.frame)
    }
}

/// The pin badge each zone carries while the overlay is up — hit test and
/// placement, as arithmetic.
///
/// Its own suite because the badge is a second target the mouse can hit, and
/// the whole design of Issue #23 rests on this being one function rather than
/// a hover state or a menu. If any of these tests starts asking for AppKit,
/// the badge has silently grown a permission requirement.
struct DropzonePinBadgeTests {

    private func zone(_ frame: WindowFrame) -> Dropzone {
        Dropzone(
            display: "main",
            zone: "left",
            name: "Links",
            relativeFrame: RelativeRect(x: 0, y: 0, width: 0.5, height: 1),
            frame: frame,
            visibleFrame: VisibleFrame(x: 0, y: 0, width: 1920, height: 1080)
        )
    }

    @Test("Die Marke sitzt oben rechts in der Zone")
    func theBadgeSitsInTheTopRightCorner() throws {
        // Corner rather than centre: on a small zone, a centred badge would
        // cover the whole zone and every drop would be a pin — the *drop
        // without pinning* case would be unreachable. The top-right corner
        // leaves most of the zone free for the plain drop.
        let z = zone(WindowFrame(x: 100, y: 200, width: 600, height: 400))
        let badge = try #require(DropzoneMap.pinBadgeFrame(for: z))
        // The badge is inside the zone…
        #expect(badge.x >= z.frame.x)
        #expect(badge.y >= z.frame.y)
        #expect(badge.x + badge.width <= z.frame.x + z.frame.width)
        #expect(badge.y + badge.height <= z.frame.y + z.frame.height)
        // …and towards the top-right, in AppKit coordinates (origin
        // bottom-left, so *top* is *higher y*).
        #expect(badge.x > z.frame.x + z.frame.width / 2)
        #expect(badge.y > z.frame.y + z.frame.height / 2)
    }

    @Test("Ein Punkt in der Marke wird als Marke erkannt")
    func aPointOnTheBadgeIsDetected() throws {
        let z = zone(WindowFrame(x: 0, y: 0, width: 500, height: 500))
        let badge = try #require(DropzoneMap.pinBadgeFrame(for: z))
        let centre = ScreenPoint(x: badge.x + badge.width / 2, y: badge.y + badge.height / 2)
        #expect(DropzoneMap.isOnPinBadge(centre, of: z))
    }

    @Test("Ein Punkt daneben trifft die Marke nicht")
    func aPointNextToTheBadgeIsNotOnIt() {
        // The two everyday cases in one test: the centre of the zone is a
        // plain drop, so is a point in the outer corner but outside the
        // badge square.
        let z = zone(WindowFrame(x: 0, y: 0, width: 500, height: 500))
        #expect(DropzoneMap.isOnPinBadge(ScreenPoint(x: 250, y: 250), of: z) == false)
        #expect(DropzoneMap.isOnPinBadge(ScreenPoint(x: 5, y: 5), of: z) == false)
    }

    @Test("Eine winzige Zone hat gar keine Marke")
    func aTinyZoneHasNoBadge() {
        // A badge that covered the whole zone would silently take away the
        // plain drop; refusing to draw one is the honest answer. `isOnPinBadge`
        // returns false on such a zone, so the controller has a single line to
        // read: no badge means no pin, and every drop is a one-off.
        let z = zone(WindowFrame(x: 0, y: 0, width: 40, height: 40))
        #expect(DropzoneMap.pinBadgeFrame(for: z) == nil)
        #expect(DropzoneMap.isOnPinBadge(ScreenPoint(x: 20, y: 20), of: z) == false)
    }

    @Test("Die Marke verschluckt nie die ganze Zone")
    func theBadgeNeverSwallowsTheWholeZone() throws {
        // The invariant behind the *tiny zone has no badge* rule: every zone
        // that carries a badge must leave the plain drop reachable. The centre
        // of the zone must not be on the badge, at any size the function is
        // willing to draw a badge for.
        for side in stride(from: 60.0, through: 4000.0, by: 20.0) {
            let z = zone(WindowFrame(x: 0, y: 0, width: side, height: side))
            guard DropzoneMap.pinBadgeFrame(for: z) != nil else { continue }
            let centre = ScreenPoint(x: side / 2, y: side / 2)
            #expect(
                DropzoneMap.isOnPinBadge(centre, of: z) == false,
                "Zone \(side)×\(side): Marke deckt die Mitte ab"
            )
        }
    }
}
