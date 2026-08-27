import Foundation
import Testing
@testable import OpenZonrCore

/// The pre-filter decides which windows reach rule evaluation at all. Its
/// mistakes are invisible in normal operation — a window simply stays where it
/// was — so the reasons it reports are tested as carefully as the decisions.
struct WindowFilterTests {

    private let filter = DefaultWindowFilter()
    private let defaults = GlobalDefaults()

    @Test("Ein gewöhnliches Standardfenster wird angenommen")
    func acceptsStandardWindow() {
        let result = filter.evaluate(TestConfigurations.window(), defaults: defaults)
        #expect(result == .accepted)
    }

    @Test("Fremde Subrollen werden mit Begründung abgelehnt", arguments: ["AXDialog", "AXSystemDialog", "AXFloatingWindow"])
    func rejectsForeignSubroles(subrole: String) {
        let result = filter.evaluate(
            TestConfigurations.window(subrole: subrole),
            defaults: defaults
        )
        #expect(result.rejectionReason == .disallowedSubrole(subrole))
    }

    @Test("Ein Fenster ohne Subrolle wird abgelehnt")
    func rejectsMissingSubrole() {
        let result = filter.evaluate(
            TestConfigurations.window(subrole: nil),
            defaults: defaults
        )
        #expect(result.rejectionReason == .disallowedSubrole(nil))
    }

    @Test(
        "Fenster unterhalb der Mindestgröße werden abgelehnt",
        arguments: [
            WindowFrame(x: 0, y: 0, width: 399, height: 800),
            WindowFrame(x: 0, y: 0, width: 800, height: 299),
            WindowFrame(x: 0, y: 0, width: 10, height: 10)
        ]
    )
    func rejectsSmallWindows(frame: WindowFrame) {
        let result = filter.evaluate(
            TestConfigurations.window(frame: frame),
            defaults: defaults
        )
        #expect(
            result.rejectionReason
                == .tooSmall(
                    actual: WindowSize(width: frame.width, height: frame.height),
                    minimum: defaults.minimumWindowSize
                )
        )
    }

    @Test("Die Mindestgröße selbst wird noch angenommen")
    func acceptsExactlyMinimumSize() {
        let result = filter.evaluate(
            TestConfigurations.window(frame: WindowFrame(x: 0, y: 0, width: 400, height: 300)),
            defaults: defaults
        )
        #expect(result == .accepted)
    }

    @Test("Nur das erste Fenster nach dem App-Start passiert den Filter")
    func rejectsLaterWindows() {
        let result = filter.evaluate(
            TestConfigurations.window(isFirstWindowAfterLaunch: false),
            defaults: defaults
        )
        #expect(result.rejectionReason == .notFirstWindowAfterLaunch)
    }

    @Test("Ist die Voreinstellung abgeschaltet, passieren auch spätere Fenster")
    func acceptsLaterWindowsWhenDefaultIsOff() {
        var defaults = GlobalDefaults()
        defaults.onlyFirstWindowAfterLaunch = false

        let result = filter.evaluate(
            TestConfigurations.window(isFirstWindowAfterLaunch: false),
            defaults: defaults
        )
        #expect(result == .accepted)
    }

    @Test("Eine Regel, die die Voreinstellung abwählt, bleibt erreichbar")
    func exemptsWindowsCoveredByAnOptOutRule() throws {
        // Genau der Fall aus der Beispielkonfiguration: das Outlook-Verfassen-Fenster
        // ist nie das erste Fenster nach dem Start. Würde der Filter die globale
        // Voreinstellung hart durchsetzen, könnte die Regel nie greifen.
        let configuration = try TestConfigurations.example()
        let filter = DefaultWindowFilter(rules: CompiledRuleSet(rules: configuration.rules))

        let compose = TestConfigurations.window(
            bundleIdentifier: "com.microsoft.Outlook",
            title: "Nachricht verfassen",
            isFirstWindowAfterLaunch: false
        )
        #expect(filter.evaluate(compose, defaults: configuration.defaults) == .accepted)

        // Für eine App ohne solche Regel bleibt die Voreinstellung in Kraft.
        let laterTerminal = TestConfigurations.window(
            bundleIdentifier: "com.apple.Terminal",
            title: "bash",
            isFirstWindowAfterLaunch: false
        )
        #expect(
            filter.evaluate(laterTerminal, defaults: configuration.defaults).rejectionReason
                == .notFirstWindowAfterLaunch
        )
    }

    @Test("Die Subrolle wird vor der Größe geprüft")
    func subroleIsCheckedFirst() {
        // Ein Fenster, das beide Kriterien verletzt, muss den billigeren Grund
        // nennen — sonst wandert die Diagnose mit jeder Umsortierung mit.
        let result = filter.evaluate(
            TestConfigurations.window(
                subrole: "AXDialog",
                frame: WindowFrame(x: 0, y: 0, width: 10, height: 10)
            ),
            defaults: defaults
        )
        #expect(result.rejectionReason == .disallowedSubrole("AXDialog"))
    }
}

/// The layer filter, tested against windows that were actually measured on the
/// author's machine. Every fixture in this suite comes from a
/// `CGWindowListCopyWindowInfo` dump, not from imagination.
struct WindowLayerFilterTests {

    private let filter = DefaultWindowFilter()
    private let defaults = GlobalDefaults()

    @Test("Die Mitteilungszentrale wird trotz voller Bildschirmgröße abgelehnt")
    func rejectsNotificationCentre() {
        // Measured: 5120×1440 on layer 21. It passes the minimum size check with
        // room to spare and carries no distinguishing subrole — the layer is the
        // only attribute that separates it from a real window.
        let window = TestConfigurations.window(
            bundleIdentifier: "com.apple.notificationcenterui",
            title: "Mitteilungszentrale",
            frame: WindowFrame(x: 0, y: 0, width: 5120, height: 1440),
            windowLayer: 21
        )

        #expect(filter.evaluate(window, defaults: defaults).rejectionReason == .notOnApplicationLayer(21))
    }

    @Test(
        "Systemoberfläche auf höheren Ebenen wird abgelehnt",
        arguments: [3, 20, 21, 24, 25, 2_147_483_630]
    )
    func rejectsSystemLayers(layer: Int) {
        let window = TestConfigurations.window(windowLayer: layer)
        #expect(filter.evaluate(window, defaults: defaults).rejectionReason == .notOnApplicationLayer(layer))
    }

    @Test("Die Ebenenprüfung läuft vor allen anderen Kriterien")
    func layerIsCheckedFirst() {
        // Too small *and* on the wrong layer: the reported reason must be the
        // layer, otherwise a user would chase the size threshold in vain.
        let window = TestConfigurations.window(
            subrole: "AXDialog",
            frame: WindowFrame(x: 0, y: 0, width: 10, height: 10),
            windowLayer: 25
        )
        #expect(filter.evaluate(window, defaults: defaults).rejectionReason == .notOnApplicationLayer(25))
    }

    @Test("Ebene 0 bleibt der einzige akzeptierte Fall")
    func acceptsApplicationLayerOnly() {
        #expect(filter.evaluate(TestConfigurations.window(windowLayer: 0), defaults: defaults) == .accepted)
    }

    @Test("Vier deckungsgleiche Fenster derselben App: nur das erste ist ein Kandidat")
    func duplicateWindowsAreFilteredByFirstWindowRule() {
        // Measured: com.corecode.MacUpdater shows four identical 420×206 windows
        // with an empty title. Minimum size catches them here; when an app opens
        // duplicates that are large enough, onlyFirstWindowAfterLaunch does.
        let small = TestConfigurations.window(
            bundleIdentifier: "com.corecode.MacUpdater",
            title: "",
            frame: WindowFrame(x: 750, y: 230, width: 420, height: 206)
        )
        #expect(filter.evaluate(small, defaults: defaults).rejectionReason != nil)

        let large = WindowFrame(x: 750, y: 230, width: 900, height: 700)
        let first = TestConfigurations.window(title: "", frame: large, isFirstWindowAfterLaunch: true)
        let second = TestConfigurations.window(title: "", frame: large, isFirstWindowAfterLaunch: false)

        #expect(filter.evaluate(first, defaults: defaults) == .accepted)
        #expect(filter.evaluate(second, defaults: defaults).rejectionReason == .notFirstWindowAfterLaunch)
    }
}
