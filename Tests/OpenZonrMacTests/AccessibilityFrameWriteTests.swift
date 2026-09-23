import CoreGraphics
import Foundation
import Testing

@testable import OpenZonrCore
@testable import OpenZonrMac

/// Belege für die Schreibfolge eines Fensterrahmens.
///
/// Die Reihenfolge ist keine Geschmacksfrage. `kAXPositionAttribute` und
/// `kAXSizeAttribute` sind bei manchen Apps **nicht** unabhängig: Safari leitet
/// seine Größe neu ab, sobald danach noch eine Position geschrieben wird, und
/// verwirft die eben gesetzte — während jeder einzelne Aufruf `.success`
/// meldet.
///
/// Gemessen am 23.09.2026 an Safari (Ziel `1340,277 966x688`, Ausgang
/// `1280,227 1610x1147`), je drei Versuche mit der echten Voreinstellung
/// (`attempts 3`, `initialDelay 50 ms`, `interval 200 ms`, `tolerance 4`):
///
/// | Folge              | V1        | V2       | V3       | Ergebnis        |
/// |--------------------|-----------|----------|----------|-----------------|
/// | `pos, size, pos`   | Abw. 607  | Abw. 607 | Abw. 607 | nie angenommen  |
/// | `pos, size`        | Abw. 60   | **0**    | —        | **angenommen**  |
///
/// Die dritte Schreibung war als Abkürzung gedacht („kostet nichts, wenn die
/// App sich anständig verhält"). Bei Safari kostet sie die gesamte
/// Größenänderung: das Fenster sprang bei jedem Versuch an eine neue Stelle,
/// ohne je seine Größe anzunehmen.
///
/// Kontrolle am selben Tag: Finder nimmt beide Folgen im **ersten** Versuch an.
@Suite("Rahmen schreiben — Reihenfolge")
struct AccessibilityFrameWriteTests {

    private final class Recorder {
        var writes: [Accessibility.FrameWrite] = []
        var failOn: Accessibility.FrameWrite?

        func write(_ w: Accessibility.FrameWrite) -> Bool {
            writes.append(w)
            return w != failOn
        }
    }

    private static let frame = WindowFrame(x: 1340, y: 277, width: 966, height: 688)
    private static let position = CGPoint(x: 1340, y: 277)
    private static let size = CGSize(width: 966, height: 688)

    private func apply(
        _ recorder: Recorder,
        enhancedWasOn: Bool = false,
        maySuppress: Bool = true
    ) -> Bool {
        Accessibility.applyFrame(
            Self.frame,
            enhancedUserInterfaceWasOn: enhancedWasOn,
            maySuppressEnhancedUserInterface: maySuppress,
            write: recorder.write
        )
    }

    @Test("Erst die Position, dann die Größe — und sonst nichts")
    func writesPositionThenSizeOnly() {
        let recorder = Recorder()

        let ok = apply(recorder)

        #expect(ok)
        #expect(recorder.writes == [.position(Self.position), .size(Self.size)])
    }

    /// Der eigentliche Rückfallschutz: nach der Größe darf **keine** Position
    /// mehr kommen. Genau daran ist die Größenänderung in Safari gescheitert.
    @Test("Nach der Größe folgt keine Position mehr")
    func noPositionWriteAfterSize() {
        let recorder = Recorder()

        _ = apply(recorder)

        let lastSizeIndex = recorder.writes.lastIndex { if case .size = $0 { return true }; return false }
        #expect(lastSizeIndex != nil)
        guard let lastSizeIndex else { return }
        let afterSize = recorder.writes[(lastSizeIndex + 1)...]
        #expect(afterSize.allSatisfy { if case .position = $0 { return false }; return true })
    }

    @Test("Genau zwei Schreibungen, keine Wiederholung")
    func writesExactlyTwice() {
        let recorder = Recorder()

        _ = apply(recorder)

        #expect(recorder.writes.count == 2)
    }

    // MARK: - AXEnhancedUserInterface

    /// Der eigentliche Beschleuniger. Steht die Bedienungshilfen-Kennung der
    /// App auf wahr, animiert Safari jede Rahmenänderung — die Größenschreibung
    /// landet dann mitten in der laufenden Animation und rechnet gegen eine
    /// Position, die es noch gar nicht gibt.
    ///
    /// Gemessen am 23.09.2026 an Safari, je vier Runden, ein einziger Versuch:
    ///
    /// | Vorgehen                                   | Treffer | grösste Abw. |
    /// |--------------------------------------------|---------|--------------|
    /// | nur `pos, size`                            | 0/4     | 91           |
    /// | Kennung aus, `pos, size`, Kennung an       | **4/4** | **0**        |
    /// | `AXFrame` in einem Rutsch                  | 0/4     | 873 (nicht setzbar, −25205) |
    @Test("Kennung an: aus, schreiben, wieder an")
    func suppressesAndRestoresEnhancedUserInterface() {
        let recorder = Recorder()

        let ok = apply(recorder, enhancedWasOn: true)

        #expect(ok)
        #expect(recorder.writes == [
            .enhancedUserInterface(false),
            .position(Self.position),
            .size(Self.size),
            .enhancedUserInterface(true)
        ])
    }

    /// War die Kennung ohnehin aus, wird sie nicht angefasst — sonst schalteten
    /// wir sie einer App **ein**, die sie nie hatte.
    @Test("Kennung aus: sie wird gar nicht angefasst")
    func leavesEnhancedUserInterfaceAloneWhenAlreadyOff() {
        let recorder = Recorder()

        _ = apply(recorder, enhancedWasOn: false)

        #expect(recorder.writes == [.position(Self.position), .size(Self.size)])
    }

    /// Läuft VoiceOver oder die Schaltersteuerung, bleibt die Kennung stehen.
    /// Sie abzuschalten wäre genau die Sekunde, in der ein Mensch, der auf sie
    /// angewiesen ist, sein Werkzeug verliert — ein langsamer Zug ist der
    /// bessere Preis.
    @Test("Aktive Bedienungshilfe: Kennung bleibt unangetastet")
    func neverSuppressesWhileAssistiveTechnologyRuns() {
        let recorder = Recorder()

        _ = apply(recorder, enhancedWasOn: true, maySuppress: false)

        #expect(recorder.writes == [.position(Self.position), .size(Self.size)])
    }

    /// Wiederherstellen ist Pflicht, nicht Kür: bleibt die Kennung aus, weil
    /// eine Schreibung scheiterte, hinterlässt jede misslungene Platzierung
    /// eine App mit abgeschalteter Bedienungshilfen-Kennung.
    @Test("Auch nach einer gescheiterten Schreibung wird die Kennung zurückgesetzt")
    func restoresEnhancedUserInterfaceEvenWhenAWriteFails() {
        let recorder = Recorder()
        recorder.failOn = .size(Self.size)

        let ok = apply(recorder, enhancedWasOn: true)

        #expect(ok == false)
        #expect(recorder.writes.last == .enhancedUserInterface(true))
    }

    /// Eine fehlgeschlagene Schreibung hält die andere nicht auf — sonst bliebe
    /// das Fenster in einem halb gesetzten Zustand stehen. Gemeldet wird
    /// trotzdem ein Fehlschlag, damit die Wiederholung greift.
    @Test("Scheitert die Position, wird die Größe trotzdem geschrieben")
    func sizeIsWrittenEvenWhenPositionFails() {
        let recorder = Recorder()
        recorder.failOn = .position(Self.position)

        let ok = apply(recorder)

        #expect(ok == false)
        #expect(recorder.writes == [.position(Self.position), .size(Self.size)])
    }

    @Test("Scheitert die Größe, ist das Ergebnis ein Fehlschlag")
    func failingSizeIsReported() {
        let recorder = Recorder()
        recorder.failOn = .size(Self.size)

        #expect(apply(recorder) == false)
    }

    /// Eine Kennung, die sich nicht zurückschreiben lässt, darf die
    /// Platzierung nicht als gescheitert melden — das Fenster sitzt ja.
    @Test("Eine misslungene Kennungs-Schreibung macht die Platzierung nicht kaputt")
    func failingEnhancedUserInterfaceWriteDoesNotFailThePlacement() {
        let recorder = Recorder()
        recorder.failOn = .enhancedUserInterface(false)

        #expect(apply(recorder, enhancedWasOn: true))
    }
}
