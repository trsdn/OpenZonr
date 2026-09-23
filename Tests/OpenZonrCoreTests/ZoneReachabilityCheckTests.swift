import Foundation
import Testing

@testable import OpenZonrCore

/// Der Befund, der den Fehler des Autors sichtbar gemacht hätte.
@Suite("Prüfung — erreichbare Zonen")
struct ZoneReachabilityCheckTests {

    /// Hausmuster: nur die Zonen der einen Ebene ersetzen, alles andere aus
    /// ``TestConfigurations/minimal()`` übernehmen.
    private func configuration(zones: [Zone]) -> Configuration {
        TestConfigurations.minimal { config in
            config.displays[0].layouts[0].zones = zones
        }
    }

    private func zone(_ id: String, _ frame: RelativeRect, activation: RelativeRect? = nil) -> Zone {
        Zone(id: ZoneID(rawValue: id), name: id, frame: frame, activationArea: activation)
    }

    /// Die echte Ebene des Autors, Stand 23.09.2026: „Rechts außen" wird von
    /// „Rechts oben" und „Rechts unten" lückenlos überdeckt.
    @Test("Die Ebene des Autors meldet right-quarter als unerreichbar")
    func reportsTheAuthorsUnreachableZone() {
        let configuration = configuration(zones: [
            zone("left-quarter",  RelativeRect(x: 0, y: 0, width: 0.25, height: 1)),
            zone("center-half",   RelativeRect(x: 0.25, y: 0, width: 0.41666666666666663, height: 1)),
            zone("right-quarter", RelativeRect(x: 0.6666666666666666, y: 0, width: 0.33333333333333337, height: 1)),
            zone("neue-zone",     RelativeRect(x: 0.6666666666666666, y: 0, width: 0.33333333333333337, height: 0.5)),
            zone("neue-zone-2",   RelativeRect(x: 0.6666666666666666, y: 0.5, width: 0.33333333333333337, height: 0.5))
        ])

        let findings = ZoneReachabilityCheck().findings(in: configuration)
        let unreachable = findings.filter { $0.code == .zoneUnreachable }

        #expect(unreachable.count == 1)
        // In eine Variable ausgelagert: das verschachtelte "?" in
        // `unreachable.first?.path` bringt das Optional-Chaining der
        // #expect-Makroexpansion sonst durcheinander.
        let pathDescription = String(describing: unreachable.first?.path)
        #expect(pathDescription.contains("right-quarter"))
        #expect(unreachable.first?.severity == .warning)
    }

    /// Der Hauptfall der Funktion: die Zielrahmen sind drei disjunkte,
    /// bildschirmhohe Spalten — über sie allein wäre niemand unerreichbar.
    /// Erst die deklarierten Trefferflächen stapeln sich, alle im selben
    /// waagerechten Band: „oben" und „unten" überdecken zusammen lückenlos
    /// die Trefferfläche von „ganz".
    ///
    /// Weil die Trefferflächen bewusst weit von den eigenen Zielrahmen weg
    /// liegen (Spalten bei x=0…0.6, Trefferflächen bei x=0.8…1), meldet die
    /// Prüfung für „ganz" und „oben" zusätzlich ``ValidationCode/activationAreaDetached`` —
    /// das ist das bereits an anderer Stelle getestete, eigenständige Verhalten
    /// dieses Checks und hier ein erwarteter Nebeneffekt der Geometrie, kein
    /// Fehler. Für „unten" liegt die Trefferfläche innerhalb des eigenen
    /// Zielrahmens, also kein solcher Zusatzbefund.
    @Test("Deckt sich über deklarierte Trefferflächen: die grosse Zone ist unerreichbar")
    func reportsUnreachableZoneThroughDeclaredActivationAreas() {
        let configuration = configuration(zones: [
            zone("ganz",  RelativeRect(x: 0, y: 0, width: 0.3, height: 1),
                 activation: RelativeRect(x: 0.8, y: 0.4, width: 0.2, height: 0.2)),
            zone("oben",  RelativeRect(x: 0.3, y: 0, width: 0.3, height: 1),
                 activation: RelativeRect(x: 0.8, y: 0.4, width: 0.1, height: 0.2)),
            zone("unten", RelativeRect(x: 0.6, y: 0, width: 0.4, height: 1),
                 activation: RelativeRect(x: 0.9, y: 0.4, width: 0.1, height: 0.2))
        ])

        let findings = ZoneReachabilityCheck().findings(in: configuration)
        let unreachable = findings.filter { $0.code == .zoneUnreachable }

        #expect(unreachable.count == 1)
        let pathDescription = String(describing: unreachable.first?.path)
        #expect(pathDescription.contains("ganz"))
    }

    /// Alle anderen Tests dieser Datei rufen den Check direkt auf. Fiele
    /// ``ZoneReachabilityCheck()`` aus ``ConfigurationValidator/init()``
    /// heraus, blieben sie trotzdem grün — nur dieser Test, der über den
    /// Validator läuft, würde es merken. Dieselbe Ebene des Autors wie oben.
    @Test("Der Validator meldet right-quarter als unerreichbar, nicht nur der Check direkt")
    func configurationValidatorReportsTheAuthorsUnreachableZone() {
        let configuration = configuration(zones: [
            zone("left-quarter",  RelativeRect(x: 0, y: 0, width: 0.25, height: 1)),
            zone("center-half",   RelativeRect(x: 0.25, y: 0, width: 0.41666666666666663, height: 1)),
            zone("right-quarter", RelativeRect(x: 0.6666666666666666, y: 0, width: 0.33333333333333337, height: 1)),
            zone("neue-zone",     RelativeRect(x: 0.6666666666666666, y: 0, width: 0.33333333333333337, height: 0.5)),
            zone("neue-zone-2",   RelativeRect(x: 0.6666666666666666, y: 0.5, width: 0.33333333333333337, height: 0.5))
        ])

        let report = ConfigurationValidator().validate(configuration)
        let unreachable = report.findings.filter { $0.code == .zoneUnreachable }

        #expect(unreachable.count == 1)
        let pathDescription = String(describing: unreachable.first?.path)
        #expect(pathDescription.contains("right-quarter"))
    }

    @Test("Mit disjunkten Trefferflächen ist niemand mehr unerreichbar")
    func separateActivationAreasResolveTheStack() {
        let configuration = configuration(zones: [
            zone("ganz",  RelativeRect(x: 0.6, y: 0, width: 0.4, height: 1),
                 activation: RelativeRect(x: 0.6, y: 0.4, width: 0.4, height: 0.2)),
            zone("oben",  RelativeRect(x: 0.6, y: 0, width: 0.4, height: 0.5),
                 activation: RelativeRect(x: 0.6, y: 0, width: 0.4, height: 0.2)),
            zone("unten", RelativeRect(x: 0.6, y: 0.5, width: 0.4, height: 0.5),
                 activation: RelativeRect(x: 0.6, y: 0.8, width: 0.4, height: 0.2))
        ])

        #expect(ZoneReachabilityCheck().findings(in: configuration).isEmpty)
    }

    @Test("Nebeneinander liegende Zonen melden nichts")
    func adjacentZonesAreFine() {
        let configuration = configuration(zones: [
            zone("links",  RelativeRect(x: 0, y: 0, width: 0.5, height: 1)),
            zone("rechts", RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1))
        ])

        #expect(ZoneReachabilityCheck().findings(in: configuration).isEmpty)
    }

    @Test("Eine Trefferfläche ohne Bezug zum Zielrahmen ist ein Hinweis, kein Fehler")
    func detachedActivationAreaIsAWarning() {
        let configuration = configuration(zones: [
            zone("rechts", RelativeRect(x: 0.6, y: 0, width: 0.4, height: 1),
                 activation: RelativeRect(x: 0, y: 0, width: 0.05, height: 1))
        ])

        let findings = ZoneReachabilityCheck().findings(in: configuration)
        #expect(findings.count == 1)
        #expect(findings.first?.code == .activationAreaDetached)
        #expect(findings.first?.severity == .warning)
    }

    /// Die Prüfung darf die Konfiguration nie unbenutzbar machen: eine
    /// unerreichbare Zone ist ärgerlich, kein Grund, die Datei abzulehnen.
    @Test("Beide Befunde lassen die Konfiguration benutzbar")
    func findingsNeverMakeTheConfigurationUnusable() {
        #expect(ValidationCode.zoneUnreachable.severity == .warning)
        #expect(ValidationCode.activationAreaDetached.severity == .warning)
    }
}
