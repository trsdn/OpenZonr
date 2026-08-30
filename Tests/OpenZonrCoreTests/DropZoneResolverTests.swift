import Foundation
import Testing

@testable import OpenZonrCore

/// The pointer half of dropzones.
///
/// All of it is arithmetic on frames, so it can be pinned down exactly — which
/// is the point: the accessibility grant is what stops the drag from being
/// measured end to end, and everything that does *not* depend on it should
/// therefore be proven rather than assumed.
struct DropZoneResolverTests {

    // MARK: - Fixtures

    /// `minimal()` plus a "focus" zone covering the middle 60 %, stacked on top
    /// of the two halves. Overlap is a documented, legitimate layout, so the
    /// resolver has to cope with it rather than assume it away.
    private static func overlapping() -> Configuration {
        TestConfigurations.minimal { configuration in
            configuration.displays[0].layouts[0].zones.append(
                Zone(
                    id: "focus",
                    name: "Fokus",
                    frame: RelativeRect(x: 0.2, y: 0.1, width: 0.6, height: 0.8)
                )
            )
        }
    }

    private static var frames: VisibleFrames {
        ["main": TestConfigurations.mainVisibleFrame]
    }

    private static func profile(_ configuration: Configuration) -> Profile {
        configuration.profiles[0]
    }

    // MARK: - Display hit-testing

    @Test("Findet den Bildschirm unter dem Zeiger")
    func findsDisplayUnderPointer() {
        let resolver = DropZoneResolver()
        #expect(resolver.display(at: ScreenPoint(x: 500, y: 500), visibleFrames: Self.frames) == "main")
    }

    @Test("Meldet keinen Bildschirm statt auf den nächsten zu raten")
    func reportsNoDisplayRatherThanGuessing() {
        let resolver = DropZoneResolver()
        // Below the visible frame: inside the Dock strip, which belongs to no zone.
        #expect(resolver.display(at: ScreenPoint(x: 500, y: 10), visibleFrames: Self.frames) == nil)
        #expect(resolver.display(at: ScreenPoint(x: 5000, y: 500), visibleFrames: Self.frames) == nil)
    }

    // MARK: - Zone hit-testing

    @Test("Trifft die Zone unter dem Zeiger")
    func findsZoneUnderPointer() {
        let configuration = TestConfigurations.minimal()
        let resolver = DropZoneResolver()

        let left = resolver.candidates(
            at: ScreenPoint(x: 500, y: 500),
            profile: Self.profile(configuration),
            configuration: configuration,
            visibleFrames: Self.frames
        )
        let right = resolver.candidates(
            at: ScreenPoint(x: 1400, y: 500),
            profile: Self.profile(configuration),
            configuration: configuration,
            visibleFrames: Self.frames
        )

        #expect(left.map(\.zone) == ["left"])
        #expect(right.map(\.zone) == ["right"])
    }

    @Test("Die gemeinsame Kante gehört genau einer Zone")
    func theSharedEdgeBelongsToExactlyOneZone() {
        let configuration = TestConfigurations.minimal()
        let resolver = DropZoneResolver()

        // x = 960 is the boundary. Half-open frames mean the right zone owns it,
        // and crucially that it is not claimed by both.
        let onEdge = resolver.candidates(
            at: ScreenPoint(x: 960, y: 500),
            profile: Self.profile(configuration),
            configuration: configuration,
            visibleFrames: Self.frames
        )

        #expect(onEdge.count == 1)
        #expect(onEdge.first?.zone == "right")
    }

    @Test("Der gemeldete Rahmen ist derselbe, den die Automatik platzieren würde")
    func theReportedFrameIsTheOneAutomaticPlacementWouldUse() {
        let configuration = TestConfigurations.minimal()
        let resolver = DropZoneResolver()

        let candidate = resolver.candidates(
            at: ScreenPoint(x: 500, y: 500),
            profile: Self.profile(configuration),
            configuration: configuration,
            visibleFrames: Self.frames
        ).first

        let placed = DefaultZoneResolver().resolve(
            role: "editor",
            share: nil,
            profile: Self.profile(configuration),
            configuration: configuration,
            visibleFrames: Self.frames
        )

        // The profile binds "editor" to the left zone, which is where the
        // pointer is. Overlay and placement must agree to the point, otherwise
        // a window lands somewhere the highlight never promised.
        #expect(candidate?.zone == "left")
        #expect((try? placed.get())?.frame == candidate?.frame)
    }

    @Test("Überlappende Zonen kommen von spezifisch nach großzügig")
    func overlappingZonesComeFromSpecificToGenerous() {
        let configuration = Self.overlapping()
        let resolver = DropZoneResolver()

        // Inside both the left half and the focus zone.
        let candidates = resolver.candidates(
            at: ScreenPoint(x: 700, y: 500),
            profile: Self.profile(configuration),
            configuration: configuration,
            visibleFrames: Self.frames
        )

        #expect(candidates.count == 2)
        #expect(candidates.map(\.zone) == ["focus", "left"])
    }

    @Test("Kein Layout, keine Kandidaten — statt eines Absturzes")
    func noLayoutMeansNoCandidates() {
        let configuration = TestConfigurations.minimal { configuration in
            configuration.profiles[0].layouts = ["main": "gibt-es-nicht"]
        }
        let resolver = DropZoneResolver()

        #expect(
            resolver.candidates(
                at: ScreenPoint(x: 500, y: 500),
                profile: Self.profile(configuration),
                configuration: configuration,
                visibleFrames: Self.frames
            ).isEmpty
        )
    }
}
