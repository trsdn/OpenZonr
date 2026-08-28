import AppKit
import ApplicationServices
import Foundation
import OpenZonrCore

/// The running daemon: observers, profile, geometry, per-app counters.
///
/// Extracted from `openzonr watch`, unchanged in substance. Three details in
/// here were bought with a day of measuring on real hardware and are the
/// difference between a working tool and an empty log — they are marked
/// individually below, and none of them may be simplified away:
///
/// 1. the strong capture of `NSRunningApplication` across the observer retry,
/// 2. sweeping windows that already existed when the observer attached,
/// 3. re-reading a frame that an application has not laid out yet.
///
/// See `docs/tracer-bullet.md`. The menu bar app hosts this type rather than
/// reimplementing it, which is the whole reason it is a type at all.
@MainActor
public final class WatchEngine {

    /// Which profile the engine is placing against, and how it got there.
    public enum ProfileState: Sendable {
        /// The attached displays match this profile exactly.
        case matched(Profile)
        /// The user pinned this profile by hand. `automatic` is what the
        /// hardware would have selected, when it selects anything.
        case pinned(Profile, automatic: Profile?)
        /// No profile matches, and OpenZonr does not guess. The string is the
        /// full explanation, ready to be shown.
        case unmatched(explanation: String)

        public var profile: Profile? {
            switch self {
            case let .matched(profile), let .pinned(profile, _): return profile
            case .unmatched: return nil
            }
        }

        public var isPinned: Bool {
            if case .pinned = self { return true }
            return false
        }
    }

    // MARK: - Observable state

    public private(set) var configuration: Configuration
    public private(set) var profileState: ProfileState
    public private(set) var isRunning = false

    /// While paused, windows are still observed but nothing is placed.
    ///
    /// Observers stay attached on purpose: detaching them would mean losing the
    /// first window of every application launched while paused, and resuming
    /// would be silently degraded for the rest of the session.
    public var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            Log.info(isPaused ? "Pausiert — es wird nichts mehr platziert." : "Fortgesetzt.")
            notifyChange()
        }
    }

    /// The most recent decisions, newest first.
    public private(set) var records: [PlacementRecord] = []

    /// Called after any of the published properties changed.
    public var onChange: (@MainActor () -> Void)?

    /// Whether windows are actually moved. `false` decides and logs only.
    public var dryRun: Bool

    private static let recordLimit = 100

    // MARK: - Internals

    private var arrangement: ScreenArrangement
    private let rules: CompiledRuleSet
    private var decider: PlacementDecider

    /// Which zone currently holds which window. Owned by the engine because a
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

    private var launchObservation: (any NSObjectProtocol)?
    private var terminationObservation: (any NSObjectProtocol)?
    private var screenObservation: (any NSObjectProtocol)?

    /// The profile the user pinned by hand, if any.
    private var pinnedProfile: ProfileID?

    /// How often a swept window is re-read before it is given up on.
    ///
    /// Six attempts at one second cover the seven seconds Outlook needed on the
    /// author's machine, with headroom. Each read can itself block for around
    /// three seconds while the application is unresponsive, so the wall clock
    /// budget is considerably larger than the nominal six seconds.
    private static let frameReadAttempts = 6
    private static let frameReadDelay: TimeInterval = 1.0

    // MARK: - Lifecycle

    /// Builds the engine and reports the display situation.
    ///
    /// Deliberately does not fail when no profile matches. The command line
    /// refuses to run in that state and says why, but the app has to survive it
    /// — showing "kein Profil passt" in the menu with a way out is the entire
    /// point of having a menu.
    public init(configuration: Configuration, dryRun: Bool, announce: Bool = true) {
        self.configuration = configuration
        self.dryRun = dryRun
        self.rules = CompiledRuleSet(rules: configuration.rules)
        self.decider = PlacementDecider.standard(for: rules)

        let snapshots = SystemDisplays.snapshots()
        self.arrangement = ScreenArrangement(snapshots: snapshots)
        self.profileState = .unmatched(explanation: "")

        if announce {
            for unusable in rules.unusableRules {
                Log.warn("Regel \"\(unusable.rule)\" wird übersprungen: \(unusable.reason) Muster: \(unusable.pattern)")
            }

            let fingerprint = SetupFingerprint(snapshots: snapshots, ignoring: configuration.ignoredDisplays)
            Log.info("Angeschlossene Displays: \(snapshots.count), davon \(fingerprint.displays.count) im Fingerprint")
            for snapshot in snapshots {
                let ignored = configuration.ignoredDisplays.contains(snapshot.identity)
                Log.detail("\(snapshot.localizedName) — \(describe(snapshot.identity))\(ignored ? "  [ignoriert]" : "")")
            }
        }

        resolveProfile(announce: announce)
    }

    // No `deinit` teardown on purpose. The observations are main-actor state and
    // a nonisolated `deinit` may not touch them; more to the point, an engine
    // that is being deallocated while still observing is a bug in the caller,
    // not something to paper over. Both front ends call ``stop()``.

    /// The current fingerprint, recomputed from the attached displays.
    public var setupFingerprint: SetupFingerprint {
        SetupFingerprint(
            snapshots: SystemDisplays.snapshots(),
            ignoring: configuration.ignoredDisplays
        )
    }

    /// All profiles the configuration offers, for the manual switch.
    public var availableProfiles: [Profile] { configuration.profiles }

    // MARK: - Profile

    /// Determines the active profile and rebuilds the decider around it.
    private func resolveProfile(announce: Bool) {
        let fingerprint = setupFingerprint
        let automatic = DefaultProfileResolver().activeProfile(for: fingerprint, in: configuration)

        let previous = profileState.profile?.id

        if let pinnedProfile, let profile = configuration.profiles.first(where: { $0.id == pinnedProfile }) {
            profileState = .pinned(profile, automatic: automatic)
        } else if let automatic {
            profileState = .matched(automatic)
        } else {
            profileState = .unmatched(
                explanation: Self.explainMissingProfile(fingerprint, configuration: configuration)
            )
        }

        decider = PlacementDecider(
            filter: DefaultWindowFilter(rules: rules),
            profileResolver: PinnedProfileResolver(pinned: pinnedProfile)
        )

        guard announce else { return }
        switch profileState {
        case let .matched(profile):
            if previous != profile.id { Log.success("Aktives Profil: \(profile.name) (\(profile.id))") }
            warnAboutMissingFrames(for: profile)
        case let .pinned(profile, _):
            if previous != profile.id { Log.success("Profil von Hand gewählt: \(profile.name) (\(profile.id))") }
            warnAboutMissingFrames(for: profile)
        case let .unmatched(explanation):
            if previous != nil || !explanation.isEmpty { Log.warn(explanation) }
        }
    }

    private func warnAboutMissingFrames(for profile: Profile) {
        let frames = arrangement.visibleFrames(for: configuration.displays)
        let missing = Set(profile.fingerprint.normalized).subtracting(frames.aliases)
        if !missing.isEmpty {
            Log.warn("Für diese Displays liegt kein sichtbarer Frame vor: \(missing.map(\.rawValue).sorted().joined(separator: ", "))")
        }
    }

    /// Pins a profile by hand, or returns to the automatic match with `nil`.
    public func pinProfile(_ id: ProfileID?) {
        pinnedProfile = id
        resolveProfile(announce: true)
        notifyChange()
    }

    /// Re-reads the displays and re-determines the profile.
    ///
    /// Called on every screen parameter change, so that docking a laptop or
    /// waking a monitor updates the menu instead of leaving a stale answer in
    /// it. Windows already placed are left alone — that is a watching behaviour
    /// the concept rules out.
    public func refreshProfile() {
        arrangement = ScreenArrangement(snapshots: SystemDisplays.snapshots())
        resolveProfile(announce: true)
        notifyChange()
    }

    /// The loud, specific complaint that replaces silently guessing a profile.
    public static func explainMissingProfile(
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

    public func start() {
        guard !isRunning else { return }
        isRunning = true

        launchObservation = NSWorkspace.shared.notificationCenter.addObserver(
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

        terminationObservation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pruneTerminatedApplications()
            }
        }

        screenObservation = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshProfile()
            }
        }

        for app in NSWorkspace.shared.runningApplications where isRelevant(app) {
            // Already running: their first window is long gone.
            windowsSeen[app.processIdentifier] = Int.max / 2
            attachObserver(to: app)
        }

        Log.info("Beobachte \(observers.count) laufende Apps plus alle neu gestarteten.")
        notifyChange()
    }

    /// Detaches everything. The engine can be started again afterwards.
    public func stop() {
        guard isRunning else { return }
        isRunning = false

        if let launchObservation {
            NSWorkspace.shared.notificationCenter.removeObserver(launchObservation)
        }
        launchObservation = nil
        if let terminationObservation {
            NSWorkspace.shared.notificationCenter.removeObserver(terminationObservation)
        }
        terminationObservation = nil
        if let screenObservation {
            NotificationCenter.default.removeObserver(screenObservation)
        }
        screenObservation = nil

        for observer in observers.values {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        observers.removeAll()
        windowsSeen.removeAll()
        recentlySwept.removeAll()

        Log.info("Beobachtung beendet.")
        notifyChange()
    }

    /// How many applications currently carry an observer.
    public var observedApplicationCount: Int { observers.count }

    /// Drops the bookkeeping of applications that are no longer running.
    ///
    /// Not a housekeeping nicety. macOS reuses process ids, and a stale entry
    /// turns a live application into an invisible one: ``attachObserver`` bails
    /// out on `observers[pid] == nil`, so the new application inherits an
    /// observer belonging to a dead process that will never fire again, and the
    /// sweep that would have caught its already-open windows sits below that
    /// early return and never runs. Meanwhile ``applicationLaunched`` has just
    /// recorded that this pid still owes its first window. The result is
    /// silence — no placement, no log line, no error — and it hits exactly the
    /// applications `onlyFirstWindowAfterLaunch` was written for.
    ///
    /// The live process list is consulted rather than the pid from the
    /// termination notification, because `NSRunningApplication` reports -1 once
    /// the process is gone. Reconciling is also self-healing: a notification
    /// that was missed still gets cleaned up at the next one.
    private func pruneTerminatedApplications() {
        let live = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))
        let gone = observers.keys.filter { !live.contains($0) }
        guard !gone.isEmpty else { return }

        for pid in gone {
            if let observer = observers.removeValue(forKey: pid) {
                CFRunLoopRemoveSource(
                    CFRunLoopGetMain(),
                    AXObserverGetRunLoopSource(observer),
                    .defaultMode
                )
            }
            windowsSeen.removeValue(forKey: pid)
            recentlySwept = recentlySwept.filter { !$0.key.hasPrefix("\(pid)|") }
            Log.detail("App beendet (pid \(pid)) — Beobachtung aufgeräumt.")
        }
        notifyChange()
    }

    /// Whether any enabled rule could ever apply to this application.
    ///
    /// A rule without a bundle identifier (the catch-all) forces observation of
    /// every regular application; otherwise only the named ones are watched,
    /// which keeps the number of observers small.
    ///
    /// Deliberately every enabled rule of the *configuration*, not only those
    /// reachable from the active profile. Rules are hardware-independent;
    /// profiles only translate them into the desk at hand. Narrowing this to the
    /// active profile would look like a tidy-up and would in fact make the
    /// observation lossy the moment the profile changes at runtime — the
    /// application would already be running, unobserved, when it becomes
    /// interesting again.
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
        // Belt and braces against a missed termination notification: a stale
        // entry for this pid would make the launch below a no-op.
        pruneTerminatedApplications()
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

        // Pause stops here, before the per-process window counter, and not later
        // where the frame is written.
        //
        // The counter is what makes `onlyFirstWindowAfterLaunch` work. If a
        // window that appears during a pause were counted, it would consume the
        // "first window after launch" slot, and after resuming the rule would
        // silently skip exactly the window it was written for — a failure with
        // no error message, which is the class of bug this project keeps
        // running into. Pausing means the engine watches and reports; it does
        // not mean it half-decides.
        if isPaused {
            Log.detail("pausiert — Fenster von \(app.bundleIdentifier ?? "pid \(pid)") wird nicht bewertet.")
            record(
                PlacementRecord(
                    applicationName: app.localizedName ?? "pid \(pid)",
                    bundleIdentifier: app.bundleIdentifier,
                    windowTitle: Accessibility.string(element, kAXTitleAttribute as String),
                    ruleID: nil,
                    display: nil,
                    zone: nil,
                    outcome: .notExecuted("pausiert")
                )
            )
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
            Log.detail(Self.explain(reason))
            // Only reasons that survived rule matching are worth a row: the
            // filter rejects dozens of windows nobody ever asked about.
            if Self.isWorthRecording(reason) {
                record(
                    application: app,
                    snapshot: snapshot,
                    ruleID: nil,
                    placement: nil,
                    outcome: .skipped(Self.explain(reason))
                )
            }

        case let .suggest(placement, rule):
            Log.warn("""
            Regel "\(rule.id)" verlangt mode=suggest — im Tracer Bullet noch nicht implementiert.
            Es fehlt das Overlay, das den Vorschlag anzeigen würde. Ziel wäre gewesen:
            \(placement.display)/\(placement.zone) \(placement.frame.shortDescription)
            """)
            record(
                application: app,
                snapshot: snapshot,
                ruleID: rule.id,
                placement: placement,
                outcome: .suggested
            )

        case let .place(placement, rule, displacing):
            for displacement in displacing {
                Log.detail("verdrängt \(displacement.window) nach \(displacement.newPlacement.display)/\(displacement.newPlacement.zone)")
            }
            place(element: element, application: app, snapshot: snapshot, rule: rule, placement: placement)
        }
    }

    /// Explains a skipped window in one line, because "nothing happened" is the
    /// hardest state to debug from the outside.
    public static func explain(_ reason: SkipReason) -> String {
        switch reason {
        case let .filtered(rejection):
            return "ignoriert — \(rejection)"
        case .noMatchingRule:
            return "keine Regel trifft zu"
        case let .unknownSetup(fingerprint):
            return "Setup passt zu keinem Profil (\(fingerprint.displays.count) Displays) — es wird nichts platziert."
        case .manuallyOverridden:
            return "Fenster wurde von Hand bewegt — die Regel hält sich zurück."
        case let .unresolvableZone(failure):
            return "Zone nicht auflösbar: \(failure)"
        case let .zoneOccupied(display, zone):
            return "Zone \(display)/\(zone) ist belegt, Policy sagt: stehen lassen."
        }
    }

    private static func isWorthRecording(_ reason: SkipReason) -> Bool {
        switch reason {
        case .filtered, .noMatchingRule:
            return false
        case .unknownSetup, .manuallyOverridden, .unresolvableZone, .zoneOccupied:
            return true
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

    /// Places a window the user dropped on a zone.
    ///
    /// Deliberately not a second placement path. Issue #10 asks for the drop to
    /// use the same logic as the automatic half, and this is how: it builds the
    /// same snapshot and calls the same ``place(element:application:snapshot:rule:placement:)``
    /// with no rule. Everything the automatic path learned the hard way — the
    /// coordinate flip, the retry policy, the tolerance, the record — applies
    /// unchanged, because it is literally the same code.
    ///
    /// Two things it refuses to do, both of them for the same reason: not to
    /// report something that did not happen.
    ///
    /// - While paused it places nothing. The menu says "es wird nichts mehr
    ///   platziert" and the log says the same; a drop that placed anyway would
    ///   make both untrue. The controller already stops listening when the pause
    ///   goes on, so this is the second lock rather than the first — but the
    ///   promise belongs to the engine that makes it, not to a caller that has
    ///   to remember.
    /// - Without a readable frame it places nothing either. The first version
    ///   substituted `0×0 bei 0,0` here, and that value travelled straight into
    ///   the rejection message as "Ist:" — a measurement that was never taken.
    @MainActor
    public func place(dropped element: AXUIElement, application: NSRunningApplication, into placement: ResolvedPlacement) {
        guard !isPaused else {
            Log.info("pausiert — das abgelegte Fenster bleibt, wo es ist.")
            return
        }
        guard let frame = Accessibility.frame(of: element) else {
            Log.warn("Der Rahmen des abgelegten Fensters ist nicht lesbar; es wird nichts gesetzt.")
            return
        }
        let snapshot = WindowInventory.snapshot(
            of: element,
            application: application,
            frame: frame,
            layer: 0,
            isFirstWindowAfterLaunch: false
        )
        place(element: element, application: application, snapshot: snapshot, rule: nil, placement: placement)
    }

    private func place(
        element: AXUIElement,
        application: NSRunningApplication,
        snapshot: WindowSnapshot,
        rule: PlacementRule?,
        placement: ResolvedPlacement
    ) {
        let fallbackNote = placement.usedFallback ? " (über den Profil-Fallback)" : ""
        if let rule {
            Log.success("Regel \"\(rule.id)\" → Rolle \"\(rule.action.role)\"\(fallbackNote) → \(placement.display)/\(placement.zone)")
        } else {
            Log.success("Abgelegt → \(placement.display)/\(placement.zone)")
        }
        if let share = rule?.action.share {
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
            record(
                application: application,
                snapshot: snapshot,
                ruleID: rule?.id,
                placement: placement,
                outcome: .notExecuted("dry-run")
            )
            return
        }

        let window = AccessibilityWindow(element: element, snapshot: snapshot)
        let retry = configuration.defaults.retry

        Task { @MainActor in
            var lastDeviation: Double?

            let placer = RetryingWindowPlacer(record: { attempt in
                lastDeviation = attempt.deviation
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

            let recorded: PlacementRecord.Outcome
            switch outcome {
            case let .placed(attempts):
                Log.success("Platziert nach \(attempts) Versuch\(attempts == 1 ? "" : "en").")
                recorded = .placed(attempts: attempts, deviation: lastDeviation)
            case let .rejectedByApplication(actual, attempts):
                Log.warn("""
                Die App hat den Frame nach \(attempts) Versuchen nicht übernommen.
                Ist: \(actual.shortDescription), Soll: \(target.frame.shortDescription)
                Mögliche Ursachen: die App klemmt ihre Fenstergröße, oder ein zweiter
                Fenstermanager (z. B. Magnet) hat gegengehalten.
                """)
                recorded = .rejected(actual: actual, attempts: attempts)
            case .missingPermission:
                Log.warn(Accessibility.permissionInstructions)
                recorded = .notExecuted("keine Berechtigung")
            case .suggested, .notApplicable, .skippedManualOverride:
                Log.detail("Ergebnis: \(outcome)")
                recorded = .notExecuted("\(outcome)")
            }

            record(
                application: application,
                snapshot: snapshot,
                ruleID: rule?.id,
                placement: placement,
                outcome: recorded
            )

            // A dropped window is already the one the user has hold of; raising
            // it would be a no-op at best and a focus steal at worst.
            if rule?.action.focus == .activate {
                Accessibility.raise(window.element, pid: snapshot.processIdentifier)
            }
        }
    }

    // MARK: - Records

    private func record(
        application: NSRunningApplication,
        snapshot: WindowSnapshot,
        ruleID: RuleID?,
        placement: ResolvedPlacement?,
        outcome: PlacementRecord.Outcome
    ) {
        record(
            PlacementRecord(
                applicationName: application.localizedName
                    ?? snapshot.bundleIdentifier
                    ?? "pid \(snapshot.processIdentifier)",
                bundleIdentifier: snapshot.bundleIdentifier,
                windowTitle: snapshot.title,
                ruleID: ruleID,
                display: placement?.display,
                zone: placement?.zone,
                outcome: outcome
            )
        )
    }

    /// Newest first — the menu shows the top of this list.
    private func record(_ entry: PlacementRecord) {
        records.insert(entry, at: 0)
        if records.count > Self.recordLimit {
            records.removeLast(records.count - Self.recordLimit)
        }
        notifyChange()
    }

    public func clearRecords() {
        records.removeAll()
        notifyChange()
    }

    private func notifyChange() {
        onChange?()
    }
}

/// Bridges the C callback back into the engine.
///
/// `AXObserverCallback` is a bare C function pointer and cannot capture context,
/// so the engine is handed through the `refcon`. The callback is delivered on
/// the run loop that the observer source was added to — the main one — which is
/// why assuming main actor isolation here is sound rather than optimistic.
private let windowCreatedCallback: AXObserverCallback = { _, element, _, refcon in
    guard let refcon else { return }
    let engine = Unmanaged<WatchEngine>.fromOpaque(refcon).takeUnretainedValue()
    // `AXUIElement` is a CoreFoundation type and therefore not `Sendable`.
    // Crossing into the main actor is nevertheless safe here because the
    // callback already runs on the main run loop — the box states that
    // explicitly instead of hiding it behind a compiler diagnostic.
    let box = UncheckedBox(element)
    MainActor.assumeIsolated {
        engine.handleWindowCreated(box.value)
    }
}

private struct UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
