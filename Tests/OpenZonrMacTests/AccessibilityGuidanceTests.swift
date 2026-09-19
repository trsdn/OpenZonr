import Foundation
import Testing

@testable import OpenZonrMac

/// The permission text is the one thing a stuck user reads. Naming the wrong
/// program there costs an hour, so the bundle detection is pinned down.
@Suite("Accessibility guidance")
struct AccessibilityGuidanceTests {
    @Test("Finds the bundle a binary lives in")
    func findsEnclosingBundle() {
        let executable = URL(fileURLWithPath: "/Users/x/Applications/OpenZonr.app/Contents/MacOS/OpenZonr")
        #expect(
            Accessibility.enclosingApplicationBundle(of: executable)?.path
                == "/Users/x/Applications/OpenZonr.app"
        )
    }

    @Test("Finds it for the command line inside the same bundle")
    func findsBundleForNestedCommandLine() {
        let executable = URL(fileURLWithPath: "/Applications/OpenZonr.app/Contents/Helpers/deep/openzonr")
        #expect(
            Accessibility.enclosingApplicationBundle(of: executable)?.path
                == "/Applications/OpenZonr.app"
        )
    }

    @Test("Reports none for a bare build product")
    func reportsNoneForBareBinary() {
        let executable = URL(fileURLWithPath: "/Volumes/dev/OpenZonr/.build/debug/openzonr")
        #expect(Accessibility.enclosingApplicationBundle(of: executable) == nil)
    }

    @Test("Reports none rather than looping when there is no path")
    func reportsNoneForMissingExecutable() {
        #expect(Accessibility.enclosingApplicationBundle(of: nil) == nil)
    }

    @Test("A directory merely named like an app does not count as one")
    func ignoresUnrelatedDirectories() {
        let executable = URL(fileURLWithPath: "/Users/x/apps/OpenZonr/openzonr")
        #expect(Accessibility.enclosingApplicationBundle(of: executable) == nil)
    }

    // MARK: - Issue #35: the promise must not be stronger than the measurement

    /// On 2026-08-30 a rebuild at the same path with an unchanged designated
    /// requirement still left the grant invalid. "Survives every rebuild" is
    /// therefore not something the help text may say.
    @Test("No guidance text promises that the grant survives every rebuild")
    func doesNotPromiseEveryRebuild() {
        let texts = [
            Accessibility.degradedAccessInstructions,
            Accessibility.permissionInstructions,
        ]
        for text in texts {
            #expect(!text.contains("jeden Neubau"))
            #expect(!text.contains("überlebt"))
        }
    }

    @Test("The degraded text names the second case and the way out")
    func degradedTextNamesRemoveAndReAdd() {
        let text = Accessibility.degradedAccessInstructions
        // The case that is not "started from a shell": a bundle started by
        // LaunchServices that still reports degraded.
        #expect(text.contains("launchd"))
        #expect(text.contains("ENTFERNEN"))
        // Toggling the checkbox is the advice that does not work.
        #expect(text.contains("Haken nur aus- und wieder"))
        // The cause is not known and must not be presented as if it were.
        #expect(text.contains("nicht geklärt"))
    }
}
