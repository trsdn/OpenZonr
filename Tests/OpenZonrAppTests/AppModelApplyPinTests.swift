import Foundation
import Testing
@testable import OpenZonrApp
@testable import OpenZonrCore

/// `AppModel.apply(_:to:)` bündelt die vier Ausgänge, an denen der Menüweg,
/// der Ziehen-Weg und der Rechtsklick-Weg zusammenlaufen: Erfolg mit Speichern,
/// Erfolg mit Editor-Session (kein Speichern), Einspruch (Report-Fehler), und
/// `QuickPin.Failure`. Die interessante Zusicherung — und der wiederkehrende
/// Fund — ist: **bei Einspruch darf die Erfolgszusammenfassung nicht in der
/// Menüzeile stehen**, denn genau das war das Muster hinter mehreren Bugs
/// (`lastPinMessage` sagt „getan", Nutzer glaubt es, tatsächlich ist nichts
/// geschehen).
@Suite("AppModel — apply(_:to:)")
@MainActor
struct AppModelApplyPinTests {

    /// Erfolg ohne offene Editor-Session: die Zusammenfassung landet in der
    /// Menüzeile, `lastPinFailed` steht auf `false`, und `session.save()` hat
    /// die Regel wirklich in die Datei geschrieben.
    @Test("Erfolg ohne Editor: Zusammenfassung erscheint und Datei ist geschrieben")
    func successWithoutEditorReportsSummary() throws {
        let loaded = try AppModelFixtures.modelWithLoadedConfiguration()
        let model = loaded.model
        let base = model.configuration!

        let ok = model.apply(
            QuickPin.Request(
                bundleIdentifier: "com.example.new",
                applicationName: "Neu",
                profile: "solo",
                target: QuickPin.Target(display: "main", zone: "left")
            ),
            to: base
        )

        #expect(ok == true)
        #expect(model.lastPinFailed == false)
        #expect(model.lastPinMessage != nil)
        // Eine Zusammenfassung erwähnt die App und die Zone — die genaue
        // Wortwahl gehört QuickPin, nicht diesem Test.
        #expect(model.lastPinMessage?.contains("Neu") == true)
        // Erfolg heißt: die neue Regel steht in der Datei, nicht nur im
        // Speicher. Alles andere wäre die stille Zusicherung aus PR #15.
        let onDisk = ConfigurationStore().load(at: loaded.temp.url)
        guard case let .loaded(configuration, _, _) = onDisk else {
            Issue.record("Konfiguration nach save() nicht wieder ladbar: \(onDisk)")
            return
        }
        #expect(configuration.rules.contains(where: { $0.match.bundleIdentifier == "com.example.new" }))
    }

    /// Erfolg mit offener Editor-Session: die Änderung wandert in die
    /// Arbeitskopie, aber die Datei bleibt unangetastet, und die Menüzeile
    /// sagt genau das.
    @Test("Erfolg mit offenem Editor: Änderung im Editor, Datei unverändert")
    func successWithEditorLeavesFileUntouched() throws {
        let loaded = try AppModelFixtures.modelWithLoadedConfiguration()
        let model = loaded.model
        let base = model.configuration!
        let dataBefore = try Data(contentsOf: loaded.temp.url)

        // Editor öffnen — die Editor-Session ist der einzige Weg, `document`
        // in `AppModel` von aussen zu belegen.
        _ = model.editorDocument()
        #expect(model.document != nil)

        let ok = model.apply(
            QuickPin.Request(
                bundleIdentifier: "com.example.new",
                applicationName: "Neu",
                profile: "solo",
                target: QuickPin.Target(display: "main", zone: "left")
            ),
            to: base
        )

        #expect(ok == true)
        #expect(model.lastPinFailed == false)
        #expect(model.lastPinMessage?.contains("im Editor eingetragen") == true)
        #expect(model.lastPinMessage?.contains("nicht gesichert") == true)

        // Datei bleibt Byte für Byte wie vorher — anders als ohne Editor,
        // wo `save()` durchläuft.
        let dataAfter = try Data(contentsOf: loaded.temp.url)
        #expect(dataAfter == dataBefore)
    }

    /// Einspruch — der `ConfigurationDocument` findet die Änderung
    /// nicht schreibbar. Der Menüweg muss den Einspruchssatz zeigen und
    /// **nicht** die Erfolgszusammenfassung. Wir zwingen den Einspruch,
    /// indem wir eine Editor-Session mit einer bereits fehlerhaften
    /// Arbeitskopie öffnen — der Editor lehnt Zwischenzustände nicht ab, die
    /// Zusicherung „speichern erst, wenn es sicher ist" hängt an genau
    /// dieser Kontrolle. `apply(_:to:)` sieht danach einen Report mit Fehler
    /// und meldet den Einspruch weiter.
    @Test("Einspruch: keine Erfolgszusammenfassung, Fehlerflagge steht")
    func objectionReportsFailureNotSummary() throws {
        let loaded = try AppModelFixtures.modelWithLoadedConfiguration()
        let model = loaded.model
        // Editor öffnen, dann eine fehlerhafte Arbeitskopie einlegen:
        // dieselbe Regel-ID zweimal produziert `duplicateRuleID` — Fehler,
        // nicht Warnung, damit `QuickPin.objection` das aufgreift.
        guard let document = model.editorDocument() else {
            Issue.record("Editor-Session konnte nicht geöffnet werden.")
            return
        }
        var broken = document.configuration
        broken.rules.append(
            PlacementRule(
                id: "editor-rule",
                name: "Duplikat",
                priority: 1,
                match: WindowMatch(bundleIdentifier: "com.example.duplicate"),
                action: PlacementAction(role: "editor")
            )
        )
        document.replace(with: broken)
        #expect(document.report.findings.contains(where: { $0.severity == .error }))

        let base = model.document!.configuration
        let ok = model.apply(
            QuickPin.Request(
                bundleIdentifier: "com.example.new",
                applicationName: "Neu",
                profile: "solo",
                target: QuickPin.Target(display: "main", zone: "left")
            ),
            to: base
        )

        #expect(ok == false)
        #expect(model.lastPinFailed == true)
        #expect(model.lastPinMessage != nil)
        // Der Satz sagt „Die Konfiguration hätte danach einen Fehler …"
        // (siehe `QuickPin.objection`) — nicht „Regel angelegt".
        #expect(model.lastPinMessage?.contains("Fehler") == true)
        #expect(model.lastPinMessage?.contains("Regel „Neu → Links“ angelegt") == false,
                "Bei Einspruch darf keine Erfolgszusammenfassung erscheinen.")
        // Editor ist offen: Nachricht weist darauf hin, dass die Änderung im
        // Editor steht, aber nicht gesichert ist.
        #expect(model.lastPinMessage?.contains("nicht gesichert") == true)
    }

    /// Ohne offene Editor-Session, aber mit Einspruch: der Satz sagt
    /// „Nichts wurde geändert." — nicht „im Editor eingetragen". Die zwei
    /// Formen dürfen nicht durcheinandergeraten.
    @Test("Einspruch ohne Editor: „Nichts wurde geändert.“")
    func objectionWithoutEditorSaysNothingChanged() throws {
        // Wir bauen einen Einspruch, der ohne Editor-Session bereits am
        // ersten Aufruf sichtbar wird. Dazu belegen wir `document` von Hand
        // (über `editorDocument()`), machen die Kopie kaputt, und schmeissen
        // die Session dann *nicht* weg — die Nachricht müsste sich am Editor
        // ausrichten. Für den „ohne Editor"-Zweig führen wir den Test
        // parallel über einen unabhängigen Aufbau.
        //
        // Aber: `apply(_:to:)` legt bei fehlender Session selbst eine
        // Wegwerf-Session an und stellt den Einspruch aus deren Report fest.
        // Damit *dieser* Einspruch entsteht, muss die übergebene `base`
        // schon einen Fehler enthalten. Wir umgehen den Loader, indem wir
        // die Basis direkt reichen — `apply(_:to:)` verlangt keinen
        // Konfigurationsstatus in `AppModel`, sondern nimmt sie als Parameter.
        let loaded = try AppModelFixtures.modelWithLoadedConfiguration()
        let model = loaded.model
        // WICHTIG: Der Editor darf nicht offen sein — wir wollen den
        // „Nichts wurde geändert."-Zweig sehen.
        #expect(model.document == nil)

        var broken = model.configuration!
        broken.rules.append(
            PlacementRule(
                id: "editor-rule",
                name: "Duplikat",
                priority: 1,
                match: WindowMatch(bundleIdentifier: "com.example.duplicate"),
                action: PlacementAction(role: "editor")
            )
        )

        let ok = model.apply(
            QuickPin.Request(
                bundleIdentifier: "com.example.new",
                applicationName: "Neu",
                profile: "solo",
                target: QuickPin.Target(display: "main", zone: "left")
            ),
            to: broken
        )

        #expect(ok == false)
        #expect(model.lastPinFailed == true)
        #expect(model.lastPinMessage?.contains("Nichts wurde geändert") == true)
    }

    /// Einspruch mit offener Editor-Session: die Menüzeile weist auf den
    /// Editor hin — die Alternative wäre, so zu tun als sei alles gut, wo doch
    /// die Änderung ungesichert im Editor liegt.
    @Test("Einspruch mit Editor: Meldung weist auf ungesicherte Änderung hin")
    func objectionWithEditorPointsAtEditor() throws {
        let loaded = try AppModelFixtures.modelWithLoadedConfiguration()
        let model = loaded.model
        guard let document = model.editorDocument() else {
            Issue.record("Editor-Session konnte nicht geöffnet werden.")
            return
        }
        var broken = document.configuration
        broken.rules.append(
            PlacementRule(
                id: "editor-rule",
                name: "Duplikat",
                priority: 1,
                match: WindowMatch(bundleIdentifier: "com.example.duplicate"),
                action: PlacementAction(role: "editor")
            )
        )
        document.replace(with: broken)

        let base = model.document!.configuration
        let ok = model.apply(
            QuickPin.Request(
                bundleIdentifier: "com.example.new",
                applicationName: "Neu",
                profile: "solo",
                target: QuickPin.Target(display: "main", zone: "left")
            ),
            to: base
        )

        #expect(ok == false)
        #expect(model.lastPinFailed == true)
        #expect(model.lastPinMessage?.contains("Editor") == true)
        #expect(model.lastPinMessage?.contains("nicht gesichert") == true)
    }

    /// `QuickPin.Failure` — z. B. leere Bundle-ID — bubblet als Meldung durch.
    @Test("QuickPin-Ablehnung: Nachricht kommt sichtbar an")
    func quickPinFailureIsSurfaced() throws {
        let loaded = try AppModelFixtures.modelWithLoadedConfiguration()
        let model = loaded.model
        let base = model.configuration!

        let ok = model.apply(
            QuickPin.Request(
                bundleIdentifier: "",  // provoziert `missingBundleIdentifier`
                applicationName: "Leer",
                profile: "solo",
                target: QuickPin.Target(display: "main", zone: "left")
            ),
            to: base
        )

        #expect(ok == false)
        #expect(model.lastPinFailed == true)
        #expect(model.lastPinMessage == QuickPin.Failure.missingBundleIdentifier.description)
    }
}
