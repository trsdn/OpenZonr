import AppKit
import Foundation
import Observation
import OpenZonrCore
import OpenZonrMac

/// Everything the menu shows and everything the menu can do.
///
/// One model, because the pieces are not independent: whether the engine may
/// run depends on the permission, which profile is active depends on the
/// configuration, and the icon depends on all of it. Splitting that into
/// several observable objects would only spread the same state over more
/// places to forget one.
@Observable
@MainActor
final class AppModel {

    /// What the icon says, in one value.
    ///
    /// Ordered by urgency: a missing permission hides every other problem,
    /// because nothing works without it.
    enum Status: Equatable {
        /// No Accessibility permission, or a degraded one.
        case needsPermission
        /// No configuration file, or one that does not load.
        case needsConfiguration
        /// A configuration, but no profile for the attached displays.
        case noProfile
        /// Everything in place, placement switched off by the user.
        case paused
        /// Working.
        case active

        var symbolName: String {
            switch self {
            case .needsPermission: return "exclamationmark.triangle.fill"
            case .needsConfiguration: return "questionmark.circle.fill"
            case .noProfile: return "rectangle.dashed"
            case .paused: return "pause.rectangle.fill"
            case .active: return "rectangle.3.group.fill"
            }
        }

        var headline: String {
            switch self {
            case .needsPermission: return "Keine Berechtigung"
            case .needsConfiguration: return "Keine Konfiguration"
            case .noProfile: return "Kein Profil passt"
            case .paused: return "Pausiert"
            case .active: return "Aktiv"
            }
        }
    }

    // MARK: - State

    private(set) var status: Status = .needsPermission
    private(set) var windowAccess: Accessibility.WindowAccess = .notTrusted
    private(set) var signing: CodeSigningStatus = .unknown

    /// The loaded configuration, or the reason there is none.
    private(set) var configuration: Configuration?
    private(set) var configurationProblem: String?
    private(set) var configurationURL: URL

    private(set) var engine: WatchEngine?

    /// Mirrors of the engine's state so SwiftUI observes them. ``WatchEngine``
    /// deliberately has no SwiftUI dependency — it is shared with the CLI.
    private(set) var profileState: WatchEngine.ProfileState?
    private(set) var records: [PlacementRecord] = []
    private(set) var observedApplications = 0

    /// The most recent log lines, newest last. Bounded, because the engine can
    /// be talkative and nobody scrolls back three hours.
    private(set) var logEntries: [Log.Entry] = []
    private static let logLimit = 500

    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            engine?.isPaused = isPaused
            dropzones?.isPaused = isPaused
            updateStatus()
        }
    }

    // MARK: - Dropzones

    private(set) var dropzones: DropZoneController?

    /// Kept in `UserDefaults`, not in the configuration file.
    ///
    /// The configuration describes the setup and is meant to be shared between
    /// machines; whether this machine's pointer draws overlays is not part of
    /// that. It also avoids a schema change while the rule editor is in flight.
    private static let dropzonesDefaultsKey = "dropzones.enabled"

    var areDropzonesEnabled: Bool {
        get { UserDefaults.standard.object(forKey: Self.dropzonesDefaultsKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: Self.dropzonesDefaultsKey)
            applyDropzonePreference()
        }
    }

    /// Why dropzones are off, when they were asked to be on.
    var dropzoneProblem: String? {
        guard areDropzonesEnabled, let dropzones, !dropzones.isEnabled else { return nil }
        return dropzones.lastFailure
    }

    private func applyDropzonePreference() {
        guard let engine else { return }
        if dropzones == nil {
            dropzones = DropZoneController(engine: engine)
        }
        dropzones?.isPaused = isPaused
        if areDropzonesEnabled {
            dropzones?.enable()
        } else {
            dropzones?.disable()
        }
    }

    var launchesAtLogin: Bool {
        get { LoginItem.isEnabled }
        set {
            LoginItem.setEnabled(newValue)
            loginItemProblem = LoginItem.lastProblem
        }
    }

    private(set) var loginItemProblem: String?

    /// Called after ``status`` changed, so the app shell can react — showing the
    /// permission window the first time it is needed, above all.
    var onStatusChange: ((Status) -> Void)?

    private var permissionTimer: Timer?
    private var logObservation: UUID?

    // MARK: - Lifecycle

    /// The one instance. A menu bar app has exactly one of everything in here,
    /// and the app delegate needs the same object the menu is bound to.
    static let shared = AppModel()

    init(configurationURL: URL = ConfigurationLocation.resolve(explicitPath: nil)) {
        self.configurationURL = configurationURL
    }

    /// Called once the app has finished launching.
    func bootstrap() {
        signing = CodeSigningStatus.current()

        logObservation = Log.addObserver { entry in
            Task { @MainActor [weak self] in
                self?.append(entry)
            }
        }

        Log.info("OpenZonr — Menüleisten-App gestartet.")
        Log.detail("Signatur: \(signing.summary)")
        loginItemProblem = LoginItem.lastProblem

        reloadConfiguration()
        refreshPermission(probe: true)
        startPermissionPolling()
    }

    private func append(_ entry: Log.Entry) {
        logEntries.append(entry)
        if logEntries.count > Self.logLimit {
            logEntries.removeFirst(logEntries.count - Self.logLimit)
        }
    }

    // MARK: - Permission

    /// Watches for the permission arriving while the app is already running.
    ///
    /// `AXIsProcessTrusted()` is cheap and can be polled. The deeper probe is
    /// not — it reads attributes from every running application, and an
    /// unresponsive one blocks for seconds — so it runs only when the cheap
    /// answer changed, or when the user asks.
    private func startPermissionPolling() {
        permissionTimer?.invalidate()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshPermission(probe: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        permissionTimer = timer
    }

    /// Re-reads the permission and starts or stops the engine accordingly.
    func refreshPermission(probe: Bool) {
        let trusted = Accessibility.isTrusted()
        let wasUsable = windowAccess.isUsable

        if !trusted {
            windowAccess = .notTrusted
        } else if probe || !wasUsable || windowAccess == .notTrusted {
            // Trusted now: find out whether that trust is worth anything.
            windowAccess = Accessibility.probeWindowAccess()
        }

        if windowAccess.isUsable {
            startEngineIfPossible()
        } else {
            engine?.stop()
        }
        updateStatus()
    }

    /// Asks macOS for the permission, which shows the system dialog once.
    func requestPermission() {
        _ = Accessibility.isTrusted(promptIfNeeded: true)
        refreshPermission(probe: true)
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Reveals this app in the Finder, so it can be dragged into the list.
    ///
    /// The "+" button in the settings pane opens a file dialog that does not
    /// find a bundle in `.build` on its own. Dragging is the reliable path, and
    /// for that the bundle has to be visible.
    func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
    }

    /// The bundle this app runs from, or the bare executable if there is none.
    ///
    /// Shown verbatim, because the grant is bound to the bundle at its path: a
    /// second copy elsewhere looks identical in the settings list and does
    /// nothing. Naming the path turns "add OpenZonr" into an unambiguous
    /// instruction.
    var bundlePath: String? {
        Accessibility.enclosingApplicationBundle()?.path
    }

    private var bundleURL: URL {
        Accessibility.enclosingApplicationBundle() ?? Bundle.main.bundleURL
    }

    // MARK: - Configuration

    func reloadConfiguration() {
        engine?.stop()
        engine = nil
        profileState = nil

        do {
            let loaded = try ConfigurationLoading.load(from: configurationURL)
            configuration = loaded
            configurationProblem = nil
            Log.info("Konfiguration geladen: \(configurationURL.path)")
            Log.info("\(loaded.displays.count) Displays, \(loaded.profiles.count) Profile, \(loaded.rules.filter(\.enabled).count) aktive Regeln")
        } catch let error as CommandError {
            configuration = nil
            configurationProblem = error.description
            Log.warn(error.description)
        } catch let error as ConfigurationStoreError {
            configuration = nil
            configurationProblem = error.description
            Log.warn(error.description)
        } catch {
            configuration = nil
            configurationProblem = "Fehler beim Laden: \(error)"
            Log.warn("Fehler beim Laden: \(error)")
        }

        if windowAccess.isUsable { startEngineIfPossible() }
        updateStatus()
    }

    func revealConfiguration() {
        let directory = configurationURL.deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: configurationURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([configurationURL])
        } else if FileManager.default.fileExists(atPath: directory.path) {
            NSWorkspace.shared.activateFileViewerSelecting([directory])
        } else {
            NSWorkspace.shared.open(directory.deletingLastPathComponent())
        }
    }

    // MARK: - Engine

    private func startEngineIfPossible() {
        guard let configuration else { return }

        if engine == nil {
            let engine = WatchEngine(configuration: configuration, dryRun: false)
            engine.isPaused = isPaused
            engine.onChange = { [weak self] in
                self?.syncFromEngine()
            }
            self.engine = engine
        }

        engine?.start()
        applyDropzonePreference()
        syncFromEngine()
    }

    private func syncFromEngine() {
        guard let engine else { return }
        profileState = engine.profileState
        records = engine.records
        observedApplications = engine.observedApplicationCount
        updateStatus()
    }

    /// Pins a profile by hand, or returns to the automatic match with `nil`.
    func selectProfile(_ id: ProfileID?) {
        engine?.pinProfile(id)
        syncFromEngine()
    }

    func clearRecords() {
        engine?.clearRecords()
        records = []
    }

    var availableProfiles: [Profile] { configuration?.profiles ?? [] }

    /// The active profile, when there is one.
    var activeProfile: Profile? { profileState?.profile }

    /// Why no profile is active, ready to be shown.
    var missingProfileExplanation: String? {
        if case let .unmatched(explanation) = profileState { return explanation }
        return nil
    }

    // MARK: - Status

    private func updateStatus() {
        let next: Status
        if !windowAccess.isUsable {
            next = .needsPermission
        } else if configuration == nil {
            next = .needsConfiguration
        } else if profileState == nil || activeProfile == nil {
            next = .noProfile
        } else if isPaused {
            next = .paused
        } else {
            next = .active
        }

        guard next != status else { return }
        status = next
        onStatusChange?(next)
    }

    /// The line under the headline in the menu: the one detail that matters
    /// most in the current state.
    var statusDetail: String {
        switch status {
        case .needsPermission:
            switch windowAccess {
            case .degraded:
                return "Vertrauen erteilt, aber keine echten Fenster lesbar"
            case .notTrusted:
                return "Bedienungshilfen nicht freigegeben"
            case .inconclusive:
                return "Keine App zum Prüfen erreichbar"
            case .granted:
                return "—"
            }
        case .needsConfiguration:
            return configurationURL.lastPathComponent
        case .noProfile:
            return "\(availableProfiles.count) Profile in der Konfiguration"
        case .paused, .active:
            guard let profile = activeProfile else { return "—" }
            let pinned = profileState?.isPinned == true ? " (von Hand)" : ""
            return "Profil: \(profile.name)\(pinned)"
        }
    }
}
