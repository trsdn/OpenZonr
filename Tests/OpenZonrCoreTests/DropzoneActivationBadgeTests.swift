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
    func badgeSitsOnTheActivationFrame() throws {
        let subject = zone(
            frame: WindowFrame(x: 600, y: 0, width: 400, height: 800),
            activation: WindowFrame(x: 0, y: 0, width: 200, height: 200)
        )

        let badge = try #require(DropzoneMap.pinBadgeFrame(for: subject))
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
