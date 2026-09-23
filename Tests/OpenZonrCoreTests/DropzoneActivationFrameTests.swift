import Foundation
import Testing

@testable import OpenZonrCore

/// ``Dropzone`` trägt die Trefferfläche absolut mit, damit der Zug nichts
/// nachschlagen muss, während die Maus läuft — dieselbe Begründung wie für
/// ``Dropzone/frame``.
@Suite("Dropzone — absolute Trefferfläche")
struct DropzoneActivationFrameTests {

    private static let visible = VisibleFrame(x: 0, y: 0, width: 1000, height: 800)

    /// Hausmuster: ``TestConfigurations/minimal()`` liefert ein Display „main"
    /// mit der Ebene „halves" und den Zonen „left" und „right". Wir ersetzen
    /// nur die Zonen — alles andere (Profil „solo", Rollen, Regeln) steht
    /// schon und muss hier nicht erfunden werden.
    private func onlyZone(activation: RelativeRect?) -> Dropzone {
        let configuration = TestConfigurations.minimal { config in
            config.displays[0].layouts[0].zones = [
                Zone(
                    id: "rechts",
                    name: "Rechts",
                    frame: RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1),
                    activationArea: activation
                )
            ]
        }

        let zones = DropzoneMap.zones(
            in: configuration,
            profile: "solo",
            visibleFrames: ["main": Self.visible]
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
