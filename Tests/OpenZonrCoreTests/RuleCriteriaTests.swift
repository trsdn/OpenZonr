import Foundation
import Testing
@testable import OpenZonrCore

/// Prüft die eigentliche Aussage aus dem Nachtrag zu Issue #19: welche
/// Kriterien einer Regel sind ohne ein tatsächlich beobachtetes Fenster
/// überhaupt entscheidbar?
struct RuleCriteriaTests {

    @Test("Leere Regel: nichts zu entscheiden, nichts undentscheidbar")
    func emptyMatch() {
        let report = RuleCriteria.report(for: WindowMatch())
        #expect(report.decidable.isEmpty)
        #expect(report.undecidable.isEmpty)
        #expect(!report.requiresObservation)
    }

    @Test("Nur die Bundle-Kennung ist ohne Fenster sicher zu prüfen")
    func onlyBundleIsDecidable() {
        let match = WindowMatch(
            bundleIdentifier: "com.microsoft.Outlook",
            titlePattern: "^Posteingang",
            roles: ["AXWindow"],
            subroles: ["AXStandardWindow"],
            minimumSize: WindowSize(width: 200, height: 150),
            maximumSize: WindowSize(width: 4000, height: 3000),
            aspectRatio: AspectRatioRange(minimum: 1.0, maximum: 2.5),
            onlyFirstWindowAfterLaunch: true
        )
        let report = RuleCriteria.report(for: match)

        #expect(report.decidable == [.bundleIdentifier("com.microsoft.Outlook")])
        #expect(report.undecidable.count == 7)
        #expect(report.requiresObservation)
    }

    @Test("Titel, Rolle, Subrolle, Größen, Verhältnis und Erstfenster sind unentscheidbar")
    func fensterabhängigeKriterienStehenAlleUnter() {
        // Jedes einzeln geprüft — sonst könnte ein Kriterium versehentlich
        // still in „entscheidbar" gerutscht sein und die Zeile behauptete, was
        // sie ohne Fenster nicht wissen kann.
        let bausteine: [(String, WindowMatch, RuleCriteria.Criterion)] = [
            ("Titel", WindowMatch(titlePattern: "^Posteingang"), .title(pattern: "^Posteingang")),
            ("Rolle", WindowMatch(roles: ["AXWindow"]), .roles(["AXWindow"])),
            ("Subrolle", WindowMatch(subroles: ["AXStandardWindow"]), .subroles(["AXStandardWindow"])),
            ("Mindestgröße", WindowMatch(minimumSize: WindowSize(width: 400, height: 300)),
             .minimumSize(WindowSize(width: 400, height: 300))),
            ("Höchstgröße", WindowMatch(maximumSize: WindowSize(width: 2000, height: 1200)),
             .maximumSize(WindowSize(width: 2000, height: 1200))),
            ("Seitenverhältnis", WindowMatch(aspectRatio: AspectRatioRange(minimum: 1.0, maximum: 2.0)),
             .aspectRatio(AspectRatioRange(minimum: 1.0, maximum: 2.0))),
            ("Erstfenster", WindowMatch(onlyFirstWindowAfterLaunch: false),
             .onlyFirstWindowAfterLaunch(false))
        ]
        for (name, match, kriterium) in bausteine {
            let report = RuleCriteria.report(for: match)
            #expect(report.decidable.isEmpty, "\(name): darf nichts als entscheidbar zählen")
            #expect(report.undecidable == [kriterium], "\(name) fehlt oder ist falsch")
        }
    }

    @Test("Geerbtes 'nur erstes Fenster' wird als unentscheidbar mitgemeldet, wenn die Voreinstellung es fordert")
    func inheritedFirstWindowIsUndecidable() {
        let match = WindowMatch(bundleIdentifier: "com.example.app")
        let defaultsAn = GlobalDefaults(onlyFirstWindowAfterLaunch: true)
        let defaultsAus = GlobalDefaults(onlyFirstWindowAfterLaunch: false)

        let mitVoreinstellung = RuleCriteria.report(for: match, defaults: defaultsAn)
        #expect(mitVoreinstellung.undecidable.contains(.onlyFirstWindowAfterLaunch(true)))
        #expect(mitVoreinstellung.requiresObservation)

        let ohneVoreinstellung = RuleCriteria.report(for: match, defaults: defaultsAus)
        #expect(!ohneVoreinstellung.requiresObservation)
    }

    @Test("Explizit gesetztes onlyFirstWindowAfterLaunch überschreibt die Voreinstellung, wird aber trotzdem gezählt")
    func explicitOverridesInheritedButStillCounts() {
        let match = WindowMatch(
            bundleIdentifier: "com.example.app",
            onlyFirstWindowAfterLaunch: false
        )
        let defaults = GlobalDefaults(onlyFirstWindowAfterLaunch: true)
        let report = RuleCriteria.report(for: match, defaults: defaults)

        // Genau einmal — der Anhang aus den Voreinstellungen darf nicht
        // *zusätzlich* dazukommen, wenn die Regel selbst schon etwas sagt.
        let treffer = report.undecidable.filter {
            if case .onlyFirstWindowAfterLaunch = $0 { return true } else { return false }
        }
        #expect(treffer == [.onlyFirstWindowAfterLaunch(false)])
    }
}
