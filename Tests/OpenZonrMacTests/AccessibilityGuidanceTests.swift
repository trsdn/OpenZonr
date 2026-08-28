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
}
