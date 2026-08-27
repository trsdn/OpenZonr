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
