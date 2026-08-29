import Foundation
import Testing

@testable import OpenZonrCore

/// Die Auswahl „echte Maße oder Schätzung" für die Editor-Vorschau.
///
/// Der Test ist der Beleg, dass der Fehler aus #18 nicht wiederkommen kann:
/// an einem gemessenen Ultrawide muss `canvasAspect` 3,81:1 melden, nicht
/// 1,6:1 — und wenn der Bildschirm gerade nicht da ist, muss der Rückfall als
/// solcher beschriftet sein.
@Suite("Seitenverhältnis der Editor-Vorschau")
struct CanvasAspectTests {

    // MARK: - Fixtures aus einer realen Anordnung

    /// Samsung C49RG9x, Hauptbildschirm — gemessen am 29.08.2026.
    /// 5120×1440, sichtbar 5120×1344 (65 pt Menüleiste). 3,81:1.
    static let ultrawideIdentity: DisplayIdentity = .fallback(
        vendorNumber: 19501,
        modelNumber: 3996,
        pixelWidth: 5120,
        pixelHeight: 1440,
        portIndex: 1
    )

    static func ultrawideSnapshot() -> DisplaySnapshot {
        DisplaySnapshot(
            identity: ultrawideIdentity,
            localizedName: "C49RG9x",
            displayID: 2,
            pixelWidth: 5120,
            pixelHeight: 1440,
            backingScaleFactor: 1,
            frame: WindowFrame(x: 0, y: 0, width: 5120, height: 1440),
            visibleFrame: WindowFrame(x: 0, y: 65, width: 5120, height: 1344),
            portIndex: 1,
            isPrimary: true
        )
    }

    static func ultrawideDescriptor() -> DisplayDescriptor {
        DisplayDescriptor(
            alias: DisplayAlias(rawValue: "c49rg9x"),
            displayName: "C49RG9x",
            identity: ultrawideIdentity,
            layouts: [],
            defaultLayoutID: LayoutID(rawValue: "three-columns")
        )
    }

    // MARK: - Fälle

    @Test("Angeschlossen: sichtbarer Rahmen, gemessen")
    func measuredFromVisibleFrame() {
        let aspect = canvasAspect(
            for: Self.ultrawideDescriptor(),
            snapshots: [Self.ultrawideSnapshot()]
        )
        #expect(aspect.source == .measured)
        // 5120 / 1344 = 3,8095…, gerundet auf drei Stellen 3,810.
        #expect((aspect.ratio - 5120.0 / 1344.0).magnitude < 1e-9)
        #expect(aspect.visibleSize == WindowSize(width: 5120, height: 1344))
    }

    @Test("Angeschlossen: der sichtbare Rahmen zählt, nicht der volle")
    func measuredIgnoresFullFrame() {
        // Wenn der Editor gegen `frame` statt gegen `visibleFrame` zöge,
        // käme hier 5120/1440 = 3,555… heraus. Der Unterschied zwischen den
        // beiden ist genau der, den das Issue anmahnt.
        let aspect = canvasAspect(
            for: Self.ultrawideDescriptor(),
            snapshots: [Self.ultrawideSnapshot()]
        )
        let visibleRatio = 5120.0 / 1344.0
        let fullFrameRatio = 5120.0 / 1440.0
        #expect((aspect.ratio - visibleRatio).magnitude < 1e-9)
        #expect((aspect.ratio - fullFrameRatio).magnitude > 0.1)
    }

    @Test("Nicht angeschlossen: Schätzung, beschriftet")
    func fallbackWhenUnplugged() {
        let aspect = canvasAspect(
            for: Self.ultrawideDescriptor(),
            snapshots: [] // Kein Snapshot passt zur Identität.
        )
        #expect(aspect.source == .estimated)
        #expect(aspect.ratio == 16.0 / 10.0)
        #expect(aspect.visibleSize == nil)
    }

    @Test("Falscher Bildschirm angeschlossen: Schätzung, kein stiller Ersatz")
    func fallbackWhenAnotherDisplayIsAttached() {
        // Der Editor bearbeitet den C49RG9x, aber angeschlossen ist ein U28E590.
        // Ohne die Identitätsprüfung würde die Vorschau die Maße des falschen
        // Bildschirms zeigen. Genau das darf nicht passieren.
        let unrelated = DisplaySnapshot(
            identity: .edid(vendorNumber: 19501, modelNumber: 3149, serialNumber: 810_375_238),
            localizedName: "U28E590",
            displayID: 1,
            pixelWidth: 3840,
            pixelHeight: 2160,
            backingScaleFactor: 2,
            frame: WindowFrame(x: 2833, y: 1440, width: 1920, height: 1080),
            visibleFrame: WindowFrame(x: 2833, y: 1440, width: 1920, height: 1080),
            portIndex: 0
        )
        let aspect = canvasAspect(
            for: Self.ultrawideDescriptor(),
            snapshots: [unrelated]
        )
        #expect(aspect.source == .estimated)
        #expect(aspect.visibleSize == nil)
    }

    @Test("Entartete Werte werden nicht in NaN weitergereicht")
    func fallbackForDegenerateVisibleFrame() {
        // Konstruiert, nicht gemessen: ein sichtbarer Rahmen der Höhe 0 ist
        // an realer Hardware nie aufgetreten. Der Test hält fest, dass die
        // Funktion trotzdem einen benutzbaren Wert liefert, keinen `NaN`.
        var snapshot = Self.ultrawideSnapshot()
        snapshot.visibleFrame = WindowFrame(x: 0, y: 0, width: 5120, height: 0)
        let aspect = canvasAspect(
            for: Self.ultrawideDescriptor(),
            snapshots: [snapshot]
        )
        #expect(aspect.source == .estimated)
        #expect(aspect.ratio.isFinite)
        #expect(aspect.ratio > 0)
    }

    @Test("Der Fallback selbst ist als Schätzung beschriftet")
    func fallbackIsLabelled() {
        #expect(CanvasAspect.fallback.source == .estimated)
        #expect(CanvasAspect.fallback.ratio == 16.0 / 10.0)
        #expect(CanvasAspect.fallback.visibleSize == nil)
    }
}
