import AppKit
import ApplicationServices
import Foundation
import OpenZonrCore

/// `openzonr watch` — the tracer bullet.
///
/// Runs in the foreground and logs every step, because the point of this stage
/// is not convenience but evidence: does a newly opened window actually end up
/// in its zone, and how many attempts does that take against an application that
/// resizes itself after opening?
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
        // Placing windows would silently do nothing, so refuse loudly instead.
        if Accessibility.probeWindowAccess() == .degraded {
            throw CommandError(Accessibility.degradedAccessInstructions)
        }

        let configuration = try ConfigurationLoader.load(from: configurationURL)
        Log.info("Konfiguration geladen: \(configurationURL.path)")
        Log.info("\(configuration.displays.count) Displays, \(configuration.profiles.count) Profile, \(configuration.rules.filter(\.enabled).count) aktive Regeln")

        let session = try WatchSession(configuration: configuration, dryRun: dryRun)
        session.start()

        Log.info("Warte auf neue Fenster. Beenden mit Strg-C.")
        CFRunLoopRun()
        exit(0)
    }
}

/// The running daemon state: observers, profile, geometry, per-app counters.
@MainActor
final class WatchSession {

    private let configuration: Configuration
    private let dryRun: Bool
    private let profile: Profile
    private var geometry: DisplayGeometry
    private let coordinator = PlacementCoordinator()

    /// One observer per watched application. Held for their lifetime — releasing
    /// the observer silently removes the notification.
    private var observers: [pid_t: AXObserver] = [:]

    /// Number of qualifying windows seen per process since OpenZonr noticed it.
    ///
    /// Applications that were already running when the daemon started begin at a
    /// value that can never be "first", because their first window happened
    /// before anyone was watching and pretending otherwise would place windows
    /// the user did not ask about.
    private var windowsSeen: [pid_t: Int] = [:]

    init(configuration: Configuration, dryRun: Bool) throws {
        self.configuration = configuration
        self.dryRun = dryRun

        let snapshots = SystemDisplays.snapshots()
        self.geometry = DisplayGeometry(snapshots: snapshots, descriptors: configuration.displays)

        let fingerprint = SetupFingerprint(snapshots: snapshots, ignoring: configuration.ignoredDisplays)
        Log.info("Angeschlossene Displays: \(snapshots.count), davon \(fingerprint.displays.count) im Fingerprint")
        for snapshot in snapshots {
            let ignored = configuration.ignoredDisplays.contains(snapshot.identity)
            Log.detail("\(snapshot.localizedName) — \(describe(snapshot.identity))\(ignored ? "  [ignoriert]" : "")")
        }

        switch DefaultProfileResolver().matchingProfile(for: fingerprint, in: configuration) {
        case let .success(profile):
            self.profile = profile
            Log.success("Aktives Profil: \(profile.name) (\(profile.id))")
        case let .failure(problem):
            throw CommandError(Self.explain(problem, configuration: configuration))
        }
    }

    private static func explain(
        _ problem: DefaultProfileResolver.Problem,
        configuration: Configuration
    ) -> String {
        switch problem {
        case let .unknownAlias(profileID, alias):
            return """
            Profil "\(profileID)" nennt im Fingerprint das Display "\(alias)",
            das in "displays" nicht deklariert ist.
            """
        case let .noMatchingProfile(current, unknown):
            var text = """
            Kein Profil passt zum aktuellen Setup — es wird nichts platziert.

            Aktueller Fingerprint (\(current.count) Displays):
            """
            for identity in current.sorted(by: { describeIdentity($0) < describeIdentity($1) }) {
                text += "\n    \(describeIdentity(identity))"
            }
            if !unknown.isEmpty {
                text += "\n\nDavon in der Konfiguration unbekannt:"
                for identity in unknown.sorted(by: { describeIdentity($0) < describeIdentity($1) }) {
                    text += "\n    \(describeIdentity(identity))"
                }
            }
            text += """


            Absichtlich kein Rateversuch: das ähnlichste Profil würde Fenster auf
            Bildschirme legen, die der Nutzer nie dafür vorgesehen hat.

            Nächster Schritt:
              openzonr displays --config-fragment
            Das Ergebnis in "displays" übernehmen und ein Profil mit genau diesem
            Fingerprint anlegen. Software-Displays gehören stattdessen unter
            "ignoredDisplays" (aktuell: \(configuration.ignoredDisplays.count)).
            """
            return text
        }
    }

    // MARK: - Observation

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            MainActor.assumeIsolated {
                self?.applicationLaunched(app)
            }
        }

        for app in NSWorkspace.shared.runningApplications where isRelevant(app) {
            // Already running: their first window is long gone.
            windowsSeen[app.processIdentifier] = Int.max / 2
            attachObserver(to: app)
        }

        Log.info("Beobachte \(observers.count) laufende Apps plus alle neu gestarteten.")
    }

    /// Whether any enabled rule could ever apply to this application.
    ///
    /// A rule without a bundle identifier (the catch-all) forces observation of
    /// every regular application; otherwise only the named ones are watched,
    /// which keeps the number of observers small.
    private func isRelevant(_ app: NSRunningApplication) -> Bool {
        guard app.activationPolicy == .regular else { return false }
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return false }

        let enabled = configuration.rules.filter(\.enabled)
        if enabled.contains(where: { $0.match.bundleIdentifier == nil }) { return true }
        guard let bundleIdentifier = app.bundleIdentifier else { return false }
        return enabled.contains { $0.match.bundleIdentifier == bundleIdentifier }
    }

    private func applicationLaunched(_ app: NSRunningApplication) {
        guard isRelevant(app) else { return }
        Log.info("App gestartet: \(app.bundleIdentifier ?? "?") (pid \(app.processIdentifier))")
        windowsSeen[app.processIdentifier] = 0
        attachObserver(to: app, retriesLeft: 20)
    }

    /// Attaches the window-created observer, retrying while the app boots.
    ///
    /// A freshly launched process is not immediately reachable over
    /// Accessibility; `AXObserverAddNotification` returns `cannotComplete` for a
    /// few hundred milliseconds. Retrying is the difference between catching the
    /// first window and missing exactly the one that matters.
    private func attachObserver(to app: NSRunningApplication, retriesLeft: Int = 0) {
        let pid = app.processIdentifier
        guard observers[pid] == nil else { return }

        var observer: AXObserver?
        guard AXObserverCreate(pid, windowCreatedCallback, &observer) == .success,
              let observer
        else {
            Log.warn("Konnte keinen AXObserver für pid \(pid) anlegen.")
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let result = AXObserverAddNotification(
            observer,
            appElement,
            kAXWindowCreatedNotification as CFString,
            refcon
        )

        guard result == .success else {
            if retriesLeft > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, weak app] in
                    guard let self, let app, !app.isTerminated else { return }
                    MainActor.assumeIsolated {
                        self.attachObserver(to: app, retriesLeft: retriesLeft - 1)
                    }
                }
            } else {
                Log.warn("AXObserverAddNotification für \(app.bundleIdentifier ?? "pid \(pid)") fehlgeschlagen: \(result.rawValue)")
            }
            return
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        observers[pid] = observer
        Log.detail("Beobachte \(app.bundleIdentifier ?? "pid \(pid)")")
    }

    // MARK: - Reaction

    func handleWindowCreated(_ element: AXUIElement) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              let app = NSRunningApplication(processIdentifier: pid)
        else { return }

        // The window exists but is not laid out yet at notification time; the
        // frame read a millisecond later is the placeholder frame, not the one
        // the app will settle on. The retry loop deals with that — the snapshot
        // only needs to be good enough for matching.
        guard let frame = Accessibility.frame(of: element) else {
            Log.warn("Neues Fenster von \(app.bundleIdentifier ?? "pid \(pid)") ohne lesbaren Frame.")
            return
        }

        let seen = windowsSeen[pid] ?? Int.max / 2
        windowsSeen[pid] = seen == Int.max / 2 ? seen : seen + 1

        let snapshot = WindowInventory.snapshot(
            of: element,
            application: app,
            frame: frame,
            layer: CoreGraphicsWindowIndex().layer(forPID: pid, frame: frame) ?? 0,
            isFirstWindowAfterLaunch: seen == 0
        )

        Log.event("Neues Fenster: \(snapshot.bundleIdentifier ?? "?")  \(snapshot.frame.shortDescription)  subrole=\(snapshot.subrole ?? "—")  Ebene \(snapshot.windowLayer)  Titel \"\(snapshot.title ?? "")\"")

        // Displays may have changed since startup; re-reading is cheap compared
        // to placing a window on a monitor that is no longer there.
        geometry = DisplayGeometry(snapshots: SystemDisplays.snapshots(), descriptors: configuration.displays)

        let decision = coordinator.decide(
            for: snapshot,
            configuration: configuration,
            profile: profile,
            geometry: geometry
        )

        switch decision {
        case let .filtered(rejection):
            Log.detail("ignoriert — \(rejection)")

        case .noRuleMatched:
            Log.detail("keine Regel trifft zu")

        case let .unresolvable(rule, problem):
            Log.warn("Regel \"\(rule.id)\" trifft zu, aber die Rolle \"\(rule.action.role)\" ist nicht auflösbar: \(problem)")

        case let .suggestion(rule, placement):
            Log.warn("""
            Regel "\(rule.id)" verlangt mode=suggest — im Tracer Bullet noch nicht implementiert.
            Es fehlt das Overlay, das den Vorschlag anzeigen würde. Ziel wäre gewesen:
            \(placement.display)/\(placement.zone) \(placement.frame.shortDescription)
            """)

        case let .place(rule, placement):
            place(element: element, snapshot: snapshot, rule: rule, placement: placement)
        }
    }

    private func place(
        element: AXUIElement,
        snapshot: WindowSnapshot,
        rule: PlacementRule,
        placement: ResolvedPlacement
    ) {
        let fallbackNote = placement.usedFallback ? " (über den Profil-Fallback)" : ""
        Log.success("Regel \"\(rule.id)\" → Rolle \"\(rule.action.role)\"\(fallbackNote) → \(placement.display)/\(placement.zone)")
        if let share = rule.action.share {
            Log.detail("share: \(share.axis.rawValue), Slot \(share.slotIndex + 1) von \(share.slots)")
        }
        Log.detail("Soll-Frame \(placement.frame.shortDescription)  (AX-Koordinaten)")

        guard !dryRun else {
            Log.detail("dry-run — es wird nichts gesetzt")
            return
        }

        let window = AccessibilityWindow(element: element, snapshot: snapshot)
        let retry = configuration.defaults.retry

        Task { @MainActor in
            let placer = RetryingWindowPlacer(record: { attempt in
                let actual = attempt.actual?.shortDescription ?? "nicht lesbar"
                let deviation = attempt.deviation.map { String(format: "%.1f pt", $0) } ?? "—"
                let verdict = attempt.accepted ? "innerhalb der Toleranz" : "Abweichung zu groß"
                Log.detail("""
                Versuch \(attempt.number): Soll \(attempt.requested.shortDescription) \
                | Ist \(actual) | Abweichung \(deviation) (Toleranz \(format(retry.tolerance)) pt) \
                | \(verdict) | \(attempt.elapsed.milliseconds) ms
                """)
            })

            let outcome = await placer.place(window, at: placement, retry: retry)

            switch outcome {
            case let .placed(attempts):
                Log.success("Platziert nach \(attempts) Versuch\(attempts == 1 ? "" : "en").")
            case let .rejectedByApplication(actual, attempts):
                Log.warn("""
                Die App hat den Frame nach \(attempts) Versuchen nicht übernommen.
                Ist: \(actual.shortDescription), Soll: \(placement.frame.shortDescription)
                Mögliche Ursachen: die App klemmt ihre Fenstergröße, oder ein zweiter
                Fenstermanager (z. B. Magnet) hat gegengehalten.
                """)
            case .missingPermission:
                Log.warn(Accessibility.permissionInstructions)
            case .suggested, .notApplicable, .skippedManualOverride:
                Log.detail("Ergebnis: \(outcome)")
            }

            if rule.action.focus == .activate {
                Accessibility.raise(window.element, pid: snapshot.processIdentifier)
            }
        }
    }
}

/// Bridges the C callback back into the session.
///
/// `AXObserverCallback` is a bare C function pointer and cannot capture context,
/// so the session is handed through the `refcon`. The callback is delivered on
/// the run loop that the observer source was added to — the main one — which is
/// why assuming main actor isolation here is sound rather than optimistic.
private let windowCreatedCallback: AXObserverCallback = { _, element, _, refcon in
    guard let refcon else { return }
    let session = Unmanaged<WatchSession>.fromOpaque(refcon).takeUnretainedValue()
    // `AXUIElement` is a CoreFoundation type and therefore not `Sendable`.
    // Crossing into the main actor is nevertheless safe here because the
    // callback already runs on the main run loop — the box states that
    // explicitly instead of hiding it behind a compiler diagnostic.
    let box = UncheckedBox(element)
    MainActor.assumeIsolated {
        session.handleWindowCreated(box.value)
    }
}

private struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

private func describeIdentity(_ identity: DisplayIdentity) -> String { describe(identity) }

extension Duration {
    var milliseconds: Int {
        Int((Double(components.seconds) * 1000) + (Double(components.attoseconds) / 1e15))
    }
}
