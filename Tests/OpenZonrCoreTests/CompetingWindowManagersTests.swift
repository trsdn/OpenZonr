import Foundation
import Testing

@testable import OpenZonrCore

/// What OpenZonr does when Magnet is running.
///
/// This is not a measurement artefact but a design question, and it has one
/// answer here: detect it, say it once, and change nothing else. The tests hold
/// that answer in place — in particular that no code path starts fighting for
/// dominance without somebody noticing.
struct CompetingWindowManagersTests {

    @Test("Magnet wird an seiner Bundle-Kennung erkannt")
    func magnetIsDetected() {
        let detected = CompetingWindowManagers.detected(among: ["com.crowdcafe.windowmagnet"])
        #expect(detected.count == 1)
        #expect(detected.first?.name == "Magnet")
        #expect(detected.first?.showsDragOverlay == true)
    }

    @Test("Unbekannte Programme lösen keine Warnung aus")
    func unknownApplicationsAreIgnored() {
        #expect(CompetingWindowManagers.detected(among: ["com.apple.TextEdit", "com.apple.Safari"]).isEmpty)
        #expect(CompetingWindowManagers.warning(for: []) == nil)
    }

    @Test("Zwei Kennungen desselben Programms warnen einmal")
    func twoIdentifiersOfTheSameProgramWarnOnce() {
        // Magnet ships under more than one identifier across its versions and
        // yabai has two. Warning twice about one program reads like two problems.
        let all = CompetingWindowManagers.known.filter { $0.name == "yabai" }.map(\.bundleIdentifier)
        let detected = CompetingWindowManagers.detected(among: all)
        #expect(detected.count == 1)
    }

    @Test("Die Warnung nennt das Programm und was es tut")
    func theWarningNamesTheProgramAndWhatItDoes() {
        let detected = CompetingWindowManagers.detected(among: ["com.crowdcafe.windowmagnet"])
        let warning = CompetingWindowManagers.warning(for: detected)
        let text = try? #require(warning)
        #expect(text?.contains("Magnet") == true)
    }

    @Test("Ein Programm mit Zieh-Overlay wird anders beschrieben als eines ohne")
    func overlayAndNonOverlayProgramsAreDescribedDifferently() {
        // The distinction is the whole content of the warning: another tool that
        // merely uses the same API can be lived with, one that also draws zones
        // during a drag produces a result the user cannot predict.
        let overlay = CompetingWindowManagers.detected(among: ["com.crowdcafe.windowmagnet"])
        let noOverlay = CompetingWindowManagers.detected(among: ["com.lwouis.alt-tab-macos"])
        #expect(overlay.first?.showsDragOverlay == true)
        #expect(noOverlay.first?.showsDragOverlay == false)
        #expect(CompetingWindowManagers.warning(for: overlay) != CompetingWindowManagers.warning(for: noOverlay))
    }

    @Test("Die Liste enthält keine doppelte Bundle-Kennung")
    func theListHasNoDuplicateIdentifiers() {
        let identifiers = CompetingWindowManagers.known.map(\.bundleIdentifier)
        #expect(Set(identifiers).count == identifiers.count)
    }

    @Test("Die Warnung ist eine Mitteilung, keine Sperre")
    func theWarningIsAdviceRatherThanABlock() {
        // Deliberate: the detection produces text and nothing else. There is no
        // "disable" and no "take over" in this type, because silently fighting
        // another window manager is the behaviour that was ruled out.
        var settings = DropzoneSettings()
        #expect(settings.warnAboutCompetingManagers)
        settings.warnAboutCompetingManagers = false
        // Switching the warning off is the user's business; it does not switch
        // dragging off.
        #expect(settings.enabled)
    }
}
