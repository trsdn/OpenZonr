import Foundation
import OpenZonrCore

/// `openzonr watch` — the tracer bullet.
///
/// Runs in the foreground and logs every step, because the point of this stage
/// is not convenience but evidence: does a newly opened window actually end up
/// in its zone, and how many attempts does that take against an application that
/// resizes itself after opening?
///
/// The mechanics live in ``WatchEngine`` so that the menu bar app inherits them
/// rather than reimplementing them. What stays here is the part that only makes
/// sense in a terminal: refusing to start when the situation is hopeless, and
/// running the run loop until Ctrl-C.
struct WatchCommand {

    var configurationURL: URL
    var dryRun: Bool

    @MainActor
    func run() throws -> Never {
        guard Accessibility.isTrusted(promptIfNeeded: true) else {
            throw CommandError(Accessibility.permissionInstructions)
        }

        // Trust alone is not enough: the permission can be attributed to the
        // launching terminal while this binary still receives stub elements.
        // Placing windows would silently do nothing, so refuse loudly instead —
        // except under --dry-run, where nothing is placed anyway and the run is
        // still useful for checking the configuration and the profile match.
        if Accessibility.probeWindowAccess() == .degraded {
            guard dryRun else { throw CommandError(Accessibility.degradedAccessInstructions) }
            Log.warn(Accessibility.degradedAccessInstructions)
        }

        let configuration = try ConfigurationLoading.load(from: configurationURL)
        Log.info("Konfiguration geladen: \(configurationURL.path)")
        Log.info("\(configuration.displays.count) Displays, \(configuration.profiles.count) Profile, \(configuration.rules.filter(\.enabled).count) aktive Regeln")

        let engine = WatchEngine(configuration: configuration, dryRun: dryRun)

        // The engine tolerates an unmatched setup because the app has to show
        // that state in its menu. A command line run has nobody to show it to
        // and nothing it could do afterwards, so it stops with the explanation.
        if case let .unmatched(explanation) = engine.profileState {
            throw CommandError(explanation)
        }

        engine.start()

        Log.info("Warte auf neue Fenster. Beenden mit Strg-C.")
        CFRunLoopRun()
        exit(0)
    }
}
