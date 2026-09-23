import Foundation
import Testing

@testable import OpenZonrCore

/// Trefferflächen vom Editor aus setzen und wieder entfernen.
@Suite("Trefferfläche bearbeiten")
struct ZoneActivationEditingTests {

    private let display: DisplayAlias = "main"
    private let layout: LayoutID = "halves"
    private let area = RelativeRect(x: 0.8, y: 0.4, width: 0.1, height: 0.2)

    @Test("Setzen schreibt die Trefferfläche, ohne den Zielrahmen anzufassen")
    func settingLeavesTheFrameAlone() {
        let before = TestConfigurations.minimal()
        let frameBefore = before.displays[0].layouts[0].zones[0].frame

        let after = before.settingZoneActivationArea(area, zone: "left", layout: layout, display: display)

        #expect(after.displays[0].layouts[0].zones[0].activationArea == area)
        #expect(after.displays[0].layouts[0].zones[0].frame == frameBefore)
    }

    /// Ohne diesen Weg liesse sich eine einmal gezeichnete Trefferfläche im
    /// Editor nie wieder loswerden.
    @Test("nil entfernt die Trefferfläche, statt nichts zu tun")
    func nilRemovesTheActivationArea() {
        let withArea = TestConfigurations.minimal()
            .settingZoneActivationArea(area, zone: "left", layout: layout, display: display)
        #expect(withArea.displays[0].layouts[0].zones[0].activationArea != nil)

        let cleared = withArea.settingZoneActivationArea(nil, zone: "left", layout: layout, display: display)

        #expect(cleared.displays[0].layouts[0].zones[0].activationArea == nil)
    }

    @Test("Nur die benannte Zone ändert sich")
    func onlyTheNamedZoneChanges() {
        let after = TestConfigurations.minimal()
            .settingZoneActivationArea(area, zone: "left", layout: layout, display: display)

        #expect(after.displays[0].layouts[0].zones[0].activationArea == area)
        #expect(after.displays[0].layouts[0].zones[1].activationArea == nil)
    }

    @Test("Eine unbekannte Zone lässt die Konfiguration unverändert")
    func unknownZoneIsANoOp() {
        let before = TestConfigurations.minimal()

        let after = before.settingZoneActivationArea(area, zone: "gibtsnicht", layout: layout, display: display)

        #expect(after == before)
    }

    /// Der Zielrahmen bleibt beim Verschieben erhalten — und die Trefferfläche
    /// bleibt stehen, wo sie war. Genau daraus entsteht der Befund
    /// `activationAreaDetached`, der den Nutzer darauf hinweist.
    @Test("Den Zielrahmen zu verschieben lässt die Trefferfläche stehen")
    func movingTheFrameLeavesTheActivationAreaBehind() {
        let moved = TestConfigurations.minimal()
            .settingZoneActivationArea(area, zone: "left", layout: layout, display: display)
            .settingZoneFrame(RelativeRect(x: 0, y: 0, width: 0.25, height: 1),
                              zone: "left", layout: layout, display: display)

        #expect(moved.displays[0].layouts[0].zones[0].activationArea == area)
        #expect(moved.displays[0].layouts[0].zones[0].frame.width == 0.25)
    }
}
