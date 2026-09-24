import Foundation
import Testing

@testable import OpenZonrApp

/// The same proof as `OpenZonrCoreTests/LocalizationTests.swift`, for this
/// target's own catalog and resource bundle
/// (`OpenZonr_OpenZonrApp.bundle`). Two targets, two bundles — a SwiftPM
/// resource bundle is scoped to the target that declares it, so each needs
/// its own version of this check; one passing tells nothing about the other.
@Suite("Localization — OpenZonrApp")
struct LocalizationTests {

    @Test("A key with no catalog entry falls back to its English value")
    func missingKeyFallsBackToItsEnglishValue() {
        let result = localized("localizationTests.missing", "the English fallback")
        #expect(result == "the English fallback")
    }

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
        let result = localized("localizationTests.interpolationProbe", "Zone %@ has %lld pixels", "Links außen", 7)
        #expect(result == "Zone Links außen has 7 pixels")
    }
}
