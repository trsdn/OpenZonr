import Foundation
import Testing

@testable import OpenZonrCore

/// Proves the plumbing `L.string(...)` depends on: that this target's
/// compiled String Catalog is reachable through `Bundle.module`, and that a
/// German-locale lookup actually returns the German translation rather than
/// silently falling back to the English default forever.
///
/// This is a build-artifact check, not a UI test, and needs neither a display
/// nor a granted permission. It is the closest thing this project has to
/// Xcode's own "missing translation" tooling, which does not apply here since
/// there is no Xcode project — see #83.
@Suite("Localization — OpenZonrCore")
struct LocalizationTests {

    @Test("A key with no catalog entry falls back to its English value")
    func missingKeyFallsBackToItsEnglishValue() {
        let result = L.string("localizationTests.missing", "the English fallback")
        #expect(result == "the English fallback")
    }

    /// The one test that would have caught the mistake this project's own
    /// `bundle.sh` comment warns about: a translation that is present locally
    /// but silently missing once released. Loading `de.lproj` directly —
    /// rather than forcing the process's locale — sidesteps every ambiguity
    /// about *which* bundle a default lookup would have searched, and checks
    /// the one fact that actually matters: the compiled German table exists
    /// and carries the real value.
    @Test("The compiled German table carries the real translation")
    func germanTableCarriesTheRealTranslation() throws {
        let deLproj = try #require(
            Bundle.module.url(forResource: "de", withExtension: "lproj"),
            "Bundle.module has no de.lproj — the resource bundle did not compile a German localization at all."
        )
        let german = try #require(Bundle(url: deLproj), "de.lproj exists but is not a loadable bundle.")
        let value = german.localizedString(forKey: "localizationTests.probe", value: "MISSING", table: nil)
        #expect(value == "de-Probe")
    }

    @Test("Interpolated messages substitute their arguments")
    func interpolatedMessagesSubstituteArguments() {
        let result = L.string(
            "localizationTests.interpolationProbe",
            "Zone %@ has %lld pixels",
            "Rechts außen", 42
        )
        #expect(result == "Zone Rechts außen has 42 pixels")
    }

    @Test("Numbered placeholders allow reordering the arguments")
    func numberedPlaceholdersAllowReordering() {
        // The case German actually needs: a translation putting the count
        // before the noun where English put the noun first. Nothing in this
        // project depends on that yet, but the mechanism must exist before
        // anything can lean on it.
        let result = L.string(
            "localizationTests.reorderProbe",
            "%2$lld items in %1$@",
            "Rechts außen", 3
        )
        #expect(result == "3 items in Rechts außen")
    }
}
