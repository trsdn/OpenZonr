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
    private var arrangement: ScreenArrangement
    private let rules: CompiledRuleSet
    private let decider: PlacementDecider

    /// Which zone currently holds which window. Owned by the session because a
    /// decision and the bookkeeping that follows it must not drift apart.
    private var occupancy = ZoneOccupancy()

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

    /// Windows replayed by ``sweepExistingWindows(of:)``, with the time of replay.
    private var recentlySwept: [String: Date] = [:]

    /// How often a swept window is re-read before it is given up on.
    ///
    /// Six attempts at one second cover the seven seconds Outlook needed on the
    /// author's machine, with headroom. Each read can itself block for around
    /// three seconds while the application is unresponsive, so the wall clock
    /// budget is considerably larger than the nominal six seconds.
    private static let frameReadAttempts = 6
    private static let frameReadDelay: TimeInterval = 1.0

    init(configuration: Configuration, dryRun: Bool) throws {
        self.configuration = configuration
        self.dryRun = dryRun
        self.rules = CompiledRuleSet(rules: configuration.rules)
        self.decider = PlacementDecider.standard(for: rules)

        let snapshots = SystemDisplays.snapshots()
        self.arrangement = ScreenArrangement(snapshots: snapshots)

        for unusable in rules.unusableRules {
            Log.warn("Regel \"\(unusable.rule)\" wird übersprungen: \(unusable.reason) Muster: \(unusable.pattern)")
        }

        let fingerprint = SetupFingerprint(snapshots: snapshots, ignoring: configuration.ignoredDisplays)
        Log.info("Angeschlossene Displays: \(snapshots.count), davon \(fingerprint.displays.count) im Fingerprint")
        for snapshot in snapshots {
            let ignored = configuration.ignoredDisplays.contains(snapshot.identity)
            Log.detail("\(snapshot.localizedName) — \(describe(snapshot.identity))\(ignored ? "  [ignoriert]" : "")")
        }

        guard let profile = DefaultProfileResolver().activeProfile(for: fingerprint, in: configuration) else {
            throw CommandError(Self.explainMissingProfile(fingerprint, configuration: configuration))
        }
        self.profile = profile
        Log.success("Aktives Profil: \(profile.name) (\(profile.id))")

        let frames = arrangement.visibleFrames(for: configuration.displays)
        let missing = Set(profile.fingerprint.normalized).subtracting(frames.aliases)
        if !missing.isEmpty {
            Log.warn("Für diese Displays liegt kein sichtbarer Frame vor: \(missing.map(\.rawValue).sorted().joined(separator: ", "))")
        }
    }

    /// The loud, specific complaint that replaces silently guessing a profile.
    private static func explainMissingProfile(
        _ fingerprint: SetupFingerprint,
        configuration: Configuration
    ) -> String {
        let known = Set(configuration.displays.map(\.identity))
        let unknown = fingerprint.displays.filter { !known.contains($0) }

        var text = """
        Kein Profil passt zum aktuellen Setup — es wird nichts platziert.

        Aktueller Fingerprint (\(fingerprint.displays.count) Displays):
        """
        for identity in fingerprint.displays.map(describe).sorted() {
            text += "\n    \(identity)"
        }
        if !unknown.isEmpty {
            text += "\n\nDavon in der Konfiguration unbekannt:"
            for identity in unknown.map(describe).sorted() {
                text += "\n    \(identity)"
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
                // `app` is captured strongly on purpose. The instance handed to
                // us by the launch notification is not retained anywhere else,
                // so a weak capture is deallocated before the first retry fires
                // — the chain then aborts without ever reaching the warning
                // below, and the window that mattered is missed in silence.
                // `isTerminated` keeps a quitting app from being held alive in
                // a retry loop.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self, app] in
                    guard let self, !app.isTerminated else { return }
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
        sweepExistingWindows(of: app)
    }

    /// Catches windows that appeared while the observer was still attaching.
    ///
    /// A freshly launched process rejects `AXObserverAddNotification` for a few
    /// hundred milliseconds, and applications open their first window inside
    /// exactly that gap — measured at 389 ms for TextEdit against a window that
    /// was already on screen. Waiting for the notification alone therefore
    /// misses the one window the whole feature exists for.
    ///
    /// Overlap is almost excluded by construction: the API only reports windows
    /// created *after* registration, so anything found here predates it. The
    /// remaining sliver is a window born between the successful registration and
    /// this call, which would arrive twice. `recentlySwept` closes it — the
    /// element address cannot serve as the key, because the notification hands
    /// out a different `AXUIElement` instance for the same window.
    private func sweepExistingWindows(of app: NSRunningApplication) {
        let pid = app.processIdentifier
        let element = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement],
              !windows.isEmpty
        else { return }

        Log.detail("Hole \(windows.count) bereits offene(s) Fenster von \(app.bundleIdentifier ?? "pid \(pid)") nach.")
        for window in windows {
            handleWindowCreated(window, viaSweep: true)
        }
    }

    /// A short-lived identity for a window, stable across `AXUIElement` instances.
    ///
    /// Deliberately coarse: it only has to tell two windows apart for the couple
    /// of seconds in which a duplicate could arrive.
    private func signature(of element: AXUIElement, pid: pid_t, frame: WindowFrame? = nil) -> String? {
        guard let frame = frame ?? Accessibility.frame(of: element) else { return nil }
        var title: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
        return "\(pid)|\(title as? String ?? "")|\(Int(frame.x)),\(Int(frame.y)),\(Int(frame.width))x\(Int(frame.height))"
    }

    /// Whether this window was just replayed by the sweep.
    ///
    /// Entries expire after two seconds so that an app legitimately reopening an
    /// identical window later is not silently ignored.
    private func wasJustSwept(_ element: AXUIElement, pid: pid_t) -> Bool {
        let cutoff = Date().addingTimeInterval(-2)
        recentlySwept = recentlySwept.filter { $0.value > cutoff }
        guard let signature = signature(of: element, pid: pid) else { return false }
        return recentlySwept[signature] != nil
    }

    // MARK: - Reaction

    func handleWindowCreated(
        _ element: AXUIElement,
        viaSweep: Bool = false,
        frameAttempt: Int = 0
    ) {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              let app = NSRunningApplication(processIdentifier: pid)
        else { return }

        if !viaSweep, wasJustSwept(element, pid: pid) {
            Log.detail("Fenster von \(app.bundleIdentifier ?? "pid \(pid)") wurde soeben nachgeholt — Benachrichtigung übersprungen.")
            return
        }

        // A window replayed by the sweep may belong to an application that is
        // still starting up and has not laid it out yet. Outlook made this
        // concrete: for roughly seven seconds after launch every attribute read
        // blocked for three seconds and returned nothing. Giving up on the first
        // empty frame loses exactly the window the rule was written for, and no
        // notification follows, because the window already existed when the
        // observer was registered. So wait it out.
        guard let frame = Accessibility.frame(of: element) else {
            guard frameAttempt < Self.frameReadAttempts else {
                Log.warn("Neues Fenster von \(app.bundleIdentifier ?? "pid \(pid)") ohne lesbaren Frame — nach \(Self.frameReadAttempts) Versuchen aufgegeben.")
                return
            }
            if frameAttempt == 0 {
                Log.detail("Fenster von \(app.bundleIdentifier ?? "pid \(pid)") noch ohne Frame — die App ist vermutlich noch am Starten. Versuche es erneut.")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.frameReadDelay) { [weak self] in
                self?.handleWindowCreated(element, viaSweep: viaSweep, frameAttempt: frameAttempt + 1)
            }
            return
        }

        if viaSweep, let signature = signature(of: element, pid: pid, frame: frame) {
            recentlySwept[signature] = Date()
        }

        // Count only windows that could plausibly be placed. Outlook opens an
        // AXUnknown window before its real one; counting that window made the
        // mail window the *second* one and silenced the rule that asked for the
        // first. Measured on 2026-08-28, see docs/tracer-bullet.md.
        let probe = WindowInventory.snapshot(
            of: element,
            application: app,
            frame: frame,
            layer: CoreGraphicsWindowIndex().layer(forPID: pid, frame: frame) ?? 0,
            isFirstWindowAfterLaunch: false
        )
        let structural = DefaultWindowFilter.structuralVerdict(probe, defaults: configuration.defaults)

        let seen: Int
        if case .accepted = structural {
            seen = windowsSeen[pid] ?? Int.max / 2
            windowsSeen[pid] = seen == Int.max / 2 ? seen : seen + 1
        } else {
            seen = Int.max / 2
        }

        let snapshot = WindowInventory.snapshot(
            of: element,
            application: app,
            frame: frame,
            layer: probe.windowLayer,
            isFirstWindowAfterLaunch: seen == 0
        )

        Log.event("Neues Fenster: \(snapshot.bundleIdentifier ?? "?")  \(snapshot.frame.shortDescription)  subrole=\(snapshot.subrole ?? "—")  Ebene \(snapshot.windowLayer)  Titel \"\(snapshot.title ?? "")\"")

        // Displays may have changed since startup; re-reading is cheap compared
        // to placing a window on a monitor that is no longer there.
        let snapshots = SystemDisplays.snapshots()
        arrangement = ScreenArrangement(snapshots: snapshots)

        let decision = decider.decide(
            for: snapshot,
            identifier: WindowIdentifier(processIdentifier: pid, token: token(for: element)),
            configuration: configuration,
            rules: rules,
            setup: SetupFingerprint(snapshots: snapshots, ignoring: configuration.ignoredDisplays),
            visibleFrames: arrangement.visibleFrames(for: configuration.displays),
            occupancy: &occupancy,
            now: Date()
        )

        switch decision {
        case let .skip(_, reason):
            log(reason)

        case let .suggest(placement, rule):
            Log.warn("""
            Regel "\(rule.id)" verlangt mode=suggest — im Tracer Bullet noch nicht implementiert.
            Es fehlt das Overlay, das den Vorschlag anzeigen würde. Ziel wäre gewesen:
            \(placement.display)/\(placement.zone) \(placement.frame.shortDescription)
            """)

        case let .place(placement, rule, displacing):
            for displacement in displacing {
                Log.detail("verdrängt \(displacement.window) nach \(displacement.newPlacement.display)/\(displacement.newPlacement.zone)")
            }
            place(element: element, snapshot: snapshot, rule: rule, placement: placement)
        }
    }

    /// Explains a skipped window in one line, because "nothing happened" is the
    /// hardest state to debug from the outside.
    private func log(_ reason: SkipReason) {
        switch reason {
        case let .filtered(rejection):
            Log.detail("ignoriert — \(rejection)")
        case .noMatchingRule:
            Log.detail("keine Regel trifft zu")
        case let .unknownSetup(fingerprint):
            Log.warn("Setup passt zu keinem Profil (\(fingerprint.displays.count) Displays) — es wird nichts platziert.")
        case .manuallyOverridden:
            Log.detail("Fenster wurde von Hand bewegt — die Regel hält sich zurück.")
        case let .unresolvableZone(failure):
            Log.warn("Zone nicht auflösbar: \(failure)")
        case let .zoneOccupied(display, zone):
            Log.detail("Zone \(display)/\(zone) ist belegt, Policy sagt: stehen lassen.")
        }
    }

    /// A per-process unique handle for a window element.
    ///
    /// The Accessibility API exposes no window id, so the element's own address
    /// serves as the token. It is stable for the lifetime of the window, which is
    /// exactly the lifetime the occupancy table cares about.
    private func token(for element: AXUIElement) -> String {
        String(UInt(bitPattern: Unmanaged.passUnretained(element).toOpaque()), radix: 16)
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
        // Everything above this line works in AppKit coordinates, because that
        // is what NSScreen reports and what the zone resolver computes in. The
        // Accessibility API wants the mirrored space, and this is the one place
        // that conversion happens.
        let target = ResolvedPlacement(
            frame: arrangement.flipVertically(placement.frame),
            display: placement.display,
            zone: placement.zone,
            usedFallback: placement.usedFallback
        )
        Log.detail("Soll-Frame \(placement.frame.shortDescription) (AppKit) → \(target.frame.shortDescription) (AX)")

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

            let outcome = await placer.place(window, at: target, retry: retry)

            switch outcome {
            case let .placed(attempts):
                Log.success("Platziert nach \(attempts) Versuch\(attempts == 1 ? "" : "en").")
            case let .rejectedByApplication(actual, attempts):
                Log.warn("""
                Die App hat den Frame nach \(attempts) Versuchen nicht übernommen.
                Ist: \(actual.shortDescription), Soll: \(target.frame.shortDescription)
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

extension Duration {
    var milliseconds: Int {
        Int((Double(components.seconds) * 1000) + (Double(components.attoseconds) / 1e15))
    }
}
