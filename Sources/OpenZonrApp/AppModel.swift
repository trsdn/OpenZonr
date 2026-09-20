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

    // MARK: - Shared guard sentences

    /// Die zwei Sätze, die drei verschiedene Wege bei fehlender Voraussetzung
    /// zeigen müssen: der Menüweg (``pinFrontmostWindow``), die Anheft-Marke
    /// (``DropzoneController.pin``) und der Rechtsklick am grünen Knopf
    /// (``ZoomButtonMenu.presentMenu``). Sie stehen hier gemeinsam, damit die
    /// drei Wege dieselbe Stimme sprechen — der Fund aus PR #24 war, dass
    /// zwei davon die Sätze auseinandergeschrieben hatten und nur eine
    /// Kollation im Review es merkte.
    enum GuardSentence {
        static let noConfigurationLoaded = "Es ist keine Konfiguration geladen."
        static let noActiveProfile = "Kein Profil ist aktiv — ohne Profil ist nicht bekannt, was „hier“ bedeutet."
    }

    var isPaused = false {
        didSet {
            guard isPaused != oldValue else { return }
            engine?.isPaused = isPaused
            // The pause covers the drag half too, and the controller only learns
            // that by being restarted. Leaving this out was a real bug: the
            // overlay kept appearing and drops kept placing while the menu said
            // nothing would be placed.
            dropzones.restart()
            updateStatus()
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

    /// Die Systemzugriffe hinter der Berechtigungsprüfung. Ein Test kann so
    /// „Berechtigung erteilt / entzogen“ herstellen, ohne Bedienungshilfen und
    /// ohne einen echten `WatchEngine`, der sich an laufende Apps hängt.
    struct Platform {
        var isTrusted: @MainActor () -> Bool
        var probeWindowAccess: @MainActor () -> Accessibility.WindowAccess
        var startEngine: @MainActor (WatchEngine) -> Void
        /// Das Gegenstück zu ``startEngine``. Eigene Naht, weil das Anhalten vor
        /// einem Update-Tausch die Zusicherung trägt und ein Test es deshalb
        /// beobachten können muss — ein echter ``WatchEngine`` läuft im Test
        /// nicht und liesse sich an seinem Anhalten nicht erkennen.
        var stopEngine: @MainActor (WatchEngine) -> Void = { $0.stop() }

        @MainActor static var live: Platform {
            Platform(
                isTrusted: { Accessibility.isTrusted() },
                probeWindowAccess: { Accessibility.probeWindowAccess() },
                startEngine: { $0.start() },
                stopEngine: { $0.stop() }
            )
        }
    }

    @ObservationIgnored private let platform: Platform

    // MARK: - Lifecycle

    /// The one instance. A menu bar app has exactly one of everything in here,
    /// and the app delegate needs the same object the menu is bound to.
    static let shared = AppModel()

    init(
        configurationURL: URL = ConfigurationLocation.resolve(explicitPath: nil),
        platform: Platform = .live,
        updates: UpdateManager = UpdateManager()
    ) {
        self.configurationURL = configurationURL
        self.platform = platform
        self.updates = updates
    }

    /// Called once the app has finished launching.
    func bootstrap() {
        signing = CodeSigningStatus.current()

        logObservation = Log.addObserver { [weak self] entry in
            Task { @MainActor in
                self?.append(entry)
            }
        }

        Log.info("OpenZonr — Menüleisten-App gestartet.")
        Log.detail("Signatur: \(signing.summary)")
        loginItemProblem = LoginItem.lastProblem

        reloadConfiguration()
        refreshPermission(probe: true)
        startPermissionPolling()
        // Erst hier, nicht im Initialisierer: ein `AppModel` in einem Test soll
        // nicht ins Netz greifen.
        updates.startAutomaticChecks()
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
        let trusted = platform.isTrusted()
        let wasUsable = windowAccess.isUsable

        if !trusted {
            windowAccess = .notTrusted
        } else if probe || !wasUsable || windowAccess == .notTrusted {
            // Trusted now: find out whether that trust is worth anything.
            windowAccess = platform.probeWindowAccess()
        }

        if windowAccess.isUsable {
            // Nur der Übergang „unbrauchbar → brauchbar“ ist ein Grund, den
            // Tracker neu aufzusetzen. Ein unveränderter Tick darf weder eine
            // laufende Geste verwerfen noch das Overlay ausblenden (#44).
            startEngineIfPossible(restartDropzones: !wasUsable)
        } else {
            stopEngine()
            // Ohne Berechtigung liefert der Tracker nichts Brauchbares mehr;
            // beim Verlust anhalten (nur beim Übergang, nicht bei jedem Tick).
            if wasUsable { dropzones.stop() }
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
        stopEngine()
        engine = nil
        dropzones.stop()
        profileState = nil
        let bytes = ConfigurationDocument.bytes(at: configurationURL)
        loadedFileBytes = bytes

        do {
            let loaded = try ConfigurationLoading.load(from: configurationURL)
            configuration = loaded
            configurationProblem = nil
            reconcileEditor(with: loaded, bytes: bytes)
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
        if configuration == nil { reconcileEditor(with: nil, bytes: bytes) }

        if windowAccess.isUsable { startEngineIfPossible() }
        updateStatus()
    }

    /// Zieht die zwischengespeicherte Editor-Sitzung nach einem Laden nach:
    /// sauber → neuer Dateistand, schmutzig → Änderungen bleiben und werden als
    /// Konflikt markiert, Datei nicht ladbar und Sitzung sauber → verwerfen,
    /// damit kein Altstand weiterlebt.
    private func reconcileEditor(with loaded: Configuration?, bytes: Data?) {
        guard let document else { return }
        if let loaded {
            document.reconcile(with: loaded, bytes: bytes)
        } else if document.hasUnsavedChanges {
            document.noteUnreadableDisk(bytes: bytes)
        } else {
            self.document = nil
        }
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

    /// Hält den Engine an, wenn es einen gibt — über die Naht, damit ein Test
    /// es sehen kann.
    private func stopEngine() {
        guard let engine else { return }
        platform.stopEngine(engine)
    }

    private func startEngineIfPossible(restartDropzones: Bool = false) {
        guard let configuration else { return }

        var created = false
        if engine == nil {
            let engine = WatchEngine(configuration: configuration, dryRun: false)
            engine.isPaused = isPaused
            engine.onChange = { [weak self] in
                self?.syncFromEngine()
            }
            self.engine = engine
            created = true
        }

        if let engine { platform.startEngine(engine) }
        // Dragging follows the engine: both need the same permission and the
        // same configuration, and a drop is placed by the engine itself. Neu
        // aufgesetzt wird nur, wenn der Engine neu ist (Reload) oder der Aufrufer
        // einen Übergang meldet — sonst läuft der bestehende Tracker weiter.
        if created || restartDropzones { dropzones.restart() }
        syncFromEngine()
    }

    /// The manual half — dragging a window onto a zone.
    ///
    /// Built on first use because the controller needs the model, which does
    /// not exist yet while the model's own stored properties are initialised.
    var dropzones: DropzoneController {
        if let existing = dropzoneController { return existing }
        let created = DropzoneController(model: self)
        dropzoneController = created
        return created
    }

    @ObservationIgnored private var dropzoneController: DropzoneController?

    /// Whether dragging a window onto a zone is switched on.
    ///
    /// The write goes through ``ConfigurationDocument`` like every other write
    /// in this app, so the setting survives a restart and is visible in the file
    /// the user edits — a toggle that only lived in memory would be forgotten on
    /// the next launch and blamed on the feature.
    var dropzonesEnabled: Bool {
        get { configuration?.defaults.dropzones.enabled ?? false }
        set { setDropzonesEnabled(newValue) }
    }

    private func setDropzonesEnabled(_ enabled: Bool) {
        updateDropzoneSettings { settings in
            var settings = settings
            settings.enabled = enabled
            return settings
        }
    }

    /// Wann die Zonen beim Ziehen erscheinen — die drei Wahlmöglichkeiten des
    /// Menüs, aus der **geladenen** Konfiguration gelesen.
    ///
    /// `nil` heisst: in der Datei steht eine Regel, die keine der drei
    /// Möglichkeiten ausdrückt (etwa „nur mit ⌥"). Das Menü zeigt sie dann als
    /// eigene Zeile an, statt einen falschen Haken zu setzen.
    var dropzoneTrigger: DropzoneTrigger? {
        guard let settings = configuration?.defaults.dropzones else { return nil }
        return DropzoneTrigger.current(settings)
    }

    func setDropzoneTrigger(_ trigger: DropzoneTrigger) {
        updateDropzoneSettings(trigger.applied(to:))
    }

    /// Betriebliche Einstellung: wirkt sofort und wird sofort gesichert — mit
    /// oder ohne Editor-Sitzung. Geschrieben wird immer „geladene
    /// Konfiguration plus diese Einstellung“, nie der ungesicherte Editorstand.
    /// Eine vorhandene Sitzung bekommt dieselbe Einstellung in Arbeitskopie und
    /// Ausgangsstand, damit ihre eigenen ungesicherten Änderungen bleiben.
    ///
    /// Seit dem Menü-Umbau geht **jede** Ziehen-Einstellung hier durch — der
    /// Ein/Aus-Schalter wie die Frage, wann die Zonen kommen. Zwei Wege mit
    /// derselben Sorgfalt nebeneinander wären zwei Wege, die auseinanderlaufen
    /// können; der Schreibweg ist deshalb einer, und nur die Umformung
    /// unterscheidet sich.
    private func updateDropzoneSettings(_ transform: (DropzoneSettings) -> DropzoneSettings) {
        guard let current = configuration else { return }
        let previous = current.defaults.dropzones
        let next = transform(previous)
        guard next != previous else { return }
        var base = current
        base.defaults.dropzones = next

        // Zuerst die Sitzung anpassen: das anschliessende Neuladen (onSave)
        // sieht dann Datei == Ausgangsstand und nimmt keine Fremdänderung an.
        document?.applyOperational { c in
            var c = c
            c.defaults.dropzones = next
            return c
        }

        // Die Wegwerf-Sitzung startet mit dem geladenen Stand und bekommt die
        // Änderung als Bearbeitung: nur dann erkennt sie eine außerhalb
        // geänderte Datei als Konflikt, statt sie als sauber zu übernehmen.
        let writer = makeDocument(for: current)
        writer.apply { _ in base }
        guard writer.save() else {
            // Bei einer Fremdänderung hat `onExternalChange` die Sitzung schon
            // auf den Dateistand gebracht; ein Zurückrollen würde ihn überschreiben.
            // Bei anderen Fehlern blieb die Datei, wie sie war: dann zurückrollen.
            if !writer.hasExternalChange {
                document?.applyOperational { c in
                    var c = c
                    c.defaults.dropzones = previous
                    return c
                }
            }
            lastPinMessage = writer.saveProblem ?? "Speichern fehlgeschlagen."
            lastPinFailed = true
            return
        }
        // `onSave` hat neu geladen und dabei den Tracker neu aufgesetzt.
    }

    // MARK: - Letzter Zug

    /// Was beim zuletzt beobachteten Zug herauskam.
    ///
    /// Diagnose, und zwar sichtbare: „die Zonen kommen nicht, wenn ich ⌘
    /// drücke" ist ein offener Fehler, dessen Ursache unbekannt ist, und keine
    /// der möglichen Ursachen ist von aussen zu sehen. Eine graue Zeile im
    /// Menü macht aus „es passiert nichts" eine Aussage, mit der man weiterkommt.
    private(set) var lastDragOutcome: DragOutcome?

    func recordDragOutcome(_ outcome: DragOutcome) {
        lastDragOutcome = outcome
        Log.detail("Zug-Ergebnis: \(DragOutcomeWording.sentence(for: outcome) ?? "—")")
    }

    /// Die Fassung aus dem Bundle, für die Kopfzeile des Menüs.
    ///
    /// `nil` ausserhalb eines Bundles (Test, `swift run`) — dann steht dort nur
    /// der Name. Eine erfundene Nummer wäre schlimmer als keine.
    var appVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// Other window managers that are running right now.
    ///
    /// Recomputed on demand rather than cached: the answer changes when the user
    /// quits Magnet, and a cached "Magnet is running" would keep warning about a
    /// program that is gone.
    var competingWindowManagers: [CompetingWindowManagers.Known] {
        guard configuration?.defaults.dropzones.warnAboutCompetingManagers ?? true else { return [] }
        return CompetingWindowManagers.detected(
            among: NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )
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

    #if DEBUG
    /// Nur für Tests: setzt `profileState` von aussen, damit die App-Zustand-
    /// Tests einen Profil-Aktivzustand herbeiführen können, ohne einen echten
    /// `WatchEngine` samt Bedienungshilfen zu bauen. In der App selbst gibt es
    /// keinen zweiten Weg, `profileState` zu setzen — er kommt ausschliesslich
    /// aus `syncFromEngine()`.
    func _setProfileStateForTesting(_ state: WatchEngine.ProfileState) {
        profileState = state
        updateStatus()
    }
    #endif

    // MARK: - Updates

    /// Die Update-Suche. Siehe ``UpdateManager``.
    @ObservationIgnored let updates: UpdateManager

    /// Wahr, solange die App für einen Bundle-Tausch angehalten ist.
    ///
    /// Sichtbarer Zustand und nicht nur eine lokale Variable, weil genau er die
    /// Zusicherung trägt, um die es hier geht: beim Tausch darf kein Fenster
    /// mehr unterwegs sein.
    private(set) var isStoppedForUpdate = false

    /// Die Naht, an der ein Test den echten Bundle-Tausch ersetzt.
    ///
    /// `nil` heisst: der echte Weg über ``UpdateManager``. Ein Test setzt hier
    /// eine Attrappe ein und kann darin nachsehen, ob vorher wirklich angehalten
    /// wurde — der echte Weg beendet den Prozess und kehrt nie zurück, ist also
    /// nicht beobachtbar.
    @ObservationIgnored var installAction: (@MainActor () async -> Bool)?

    /// Hält alles an, was ein Fenster noch bewegen könnte.
    ///
    /// Zwei Dinge, und beide zählen. ``WatchEngine/stop()`` löst die
    /// Fensterbeobachtung *und* leert den ``PlacementScheduler`` — ein Auftrag,
    /// der auf sein Fenster wartet, würde sonst mitten im Bundle-Tausch
    /// zuschlagen und die Fenster halb verschoben zurücklassen. Der
    /// ``DropzoneController`` hängt am selben Zugriff und am selben Ereignis-Tap
    /// und muss deshalb ebenfalls weg.
    func stopForUpdate() {
        isStoppedForUpdate = true
        stopEngine()
        dropzones.stop()
        Log.info("Fensterbeobachtung für den Update-Tausch angehalten.")
    }

    /// Nimmt die Arbeit wieder auf, wenn der Tausch nicht stattgefunden hat.
    private func resumeAfterFailedInstall() {
        isStoppedForUpdate = false
        refreshPermission(probe: true)
        if windowAccess.isUsable { dropzones.restart() }
        Log.info("Update nicht installiert — Fensterbeobachtung läuft weiter.")
    }

    /// Hält die eigene Arbeit an und tauscht dann das Bundle.
    ///
    /// Die Reihenfolge ist der ganze Punkt: erst anhalten, dann installieren.
    /// Im Erfolgsfall kehrt das hier nie zurück, weil die App neu startet.
    ///
    /// Ein zweiter Anstoss während eines laufenden Tauschs prallt ab. Das ist
    /// keine Feinheit: es gibt zwei Wege hierher (Menüknopf und Hinweisfenster),
    /// und der zweite Aufruf fände in ``UpdateManager`` nichts Vorbereitetes
    /// mehr vor, bekäme `false` zurück und würde Fensterbeobachtung und
    /// Ziehen-Tracker mitten im Bundle-Tausch wieder anwerfen — also genau das
    /// herbeiführen, wogegen ``stopForUpdate()`` schützt.
    @discardableResult
    func installUpdate() async -> Bool {
        guard !isStoppedForUpdate else { return false }
        stopForUpdate()
        let install = installAction ?? { [updates] in await updates.installAndRelaunch() }
        if await install() { return true }
        resumeAfterFailedInstall()
        return false
    }

    // MARK: - Editor

    /// The open editing session, so that reopening the window does not throw
    /// away unsaved changes.
    private(set) var document: ConfigurationDocument?

    /// Die Dateibytes des letzten Ladens. Jede Sitzung, die dieses Modell
    /// erzeugt, bekommt sie als Ausgangsstand — auch die Wegwerf-Sitzungen von
    /// Schnellanheften und Menü-Schalter, damit auch sie eine außerhalb
    /// geänderte Datei nicht überschreiben.
    @ObservationIgnored private var loadedFileBytes: Data?

    /// The result of the last quick pin, for the menu to show.
    private(set) var lastPinMessage: String?
    private(set) var lastPinFailed = false

    /// Trägt eine Ablehnung so ein, wie es der Menüweg auch tut.
    ///
    /// Der Marken-Weg beim Ziehen braucht dieselbe Stimme: eine getroffene
    /// Marke, deren Regel nicht geschrieben werden konnte, muss dem Nutzer
    /// erklärt werden — nicht nur ins Protokoll. `apply(_:to:)` setzt beide
    /// Felder selbst, aber wenn wir vor `apply` scheitern (kein Profil, keine
    /// Konfiguration, `QuickPin.Request` nicht baubar), muss das genauso
    /// sichtbar sein.
    func reportPinFailure(_ message: String) {
        lastPinFailed = true
        lastPinMessage = message
        Log.warn(message)
    }

    /// The editing session for the loaded configuration, created on first use.
    ///
    /// Returns `nil` when there is nothing to edit. Offering an editor on a
    /// configuration that failed to load would mean editing an invented one and
    /// writing it over the user's file.
    func editorDocument() -> ConfigurationDocument? {
        // Ein zwischengespeicherter Editor darf nie einen Altstand liefern: hat
        // sich die Datei seit seinem Ausgangsstand geändert, wird neu geladen
        // (das gleicht die Sitzung ab, siehe `reconcileEditor`).
        if document?.fileChangedOnDisk == true
            || (document == nil && ConfigurationDocument.bytes(at: configurationURL) != loadedFileBytes) {
            reloadConfiguration()
        }
        if let document { return document }
        guard let configuration else { return nil }
        let document = makeDocument(for: configuration)
        self.document = document
        return document
    }

    /// An editing session wired up to reload the engine after a successful write.
    private func makeDocument(for configuration: Configuration) -> ConfigurationDocument {
        // Snapshots werden hier einmalig eingesammelt und ins Document gereicht,
        // damit der Zoneneditor die Vorschau am echten Seitenverhältnis
        // ausrichten kann. `SystemDisplays` liegt in `OpenZonrMac` und ist im
        // Editor selbst nicht erreichbar — die Trennung bleibt so bestehen.
        let document = ConfigurationDocument(
            configuration: configuration,
            url: configurationURL,
            displaySnapshots: SystemDisplays.snapshots(),
            baseline: loadedFileBytes
        )
        document.onSave = { [weak self] _ in
            // Reload rather than adopting the in-memory copy: what the engine
            // runs on should be what is on disk, migration and all.
            self?.reloadConfiguration()
        }
        document.onExternalChange = { [weak self] in
            self?.reloadConfiguration()
        }
        return document
    }

    /// „Aktuelles Fenster hier festhalten“ — the 90 % case.
    ///
    /// Reads the frontmost window, works out which zone it is sitting in, and
    /// lets ``QuickPin`` derive rule, role and binding. The write goes through
    /// the same ``ConfigurationStore`` as the editor's save button; there is no
    /// second path.
    ///
    /// Unsaved editor changes are the base when the editor is open, so that the
    /// pin does not silently discard them.
    func pinFrontmostWindow() {
        lastPinFailed = true

        guard let base = document?.configuration ?? configuration else {
            lastPinMessage = GuardSentence.noConfigurationLoaded
            return
        }
        guard let profile = activeProfile else {
            lastPinMessage = GuardSentence.noActiveProfile
            return
        }

        let snapshots = SystemDisplays.snapshots()
        let arrangement = ScreenArrangement(snapshots: snapshots)
        let frames = arrangement.visibleFrames(
            for: base.displays,
            reconciler: base.displayReconciler(observing: snapshots)
        )

        let window: FrontmostWindow.Snapshot
        switch FrontmostWindow.read(primaryTopY: arrangement.primaryTopY) {
        case let .success(snapshot):
            window = snapshot
        case let .failure(failure):
            lastPinMessage = failure.description
            return
        }

        guard let target = PinTargetResolver.resolve(
            windowFrame: window.frame,
            configuration: base,
            profile: profile.id,
            visibleFrames: frames
        ) else {
            lastPinMessage = "Unter diesem Fenster liegt keine Zone des Profils „\(profile.name)“."
            return
        }

        apply(
            QuickPin.Request(
                bundleIdentifier: window.bundleIdentifier,
                applicationName: window.applicationName,
                profile: profile.id,
                target: target
            ),
            to: base
        )
    }

    /// Writes one ``QuickPin`` request, whatever produced it.
    ///
    /// Extracted so that dropping a window on a zone and the menu entry share a
    /// path instead of resembling one. Both derive a request; only this function
    /// knows how a request becomes a saved configuration, which objection can
    /// stop it, and what the user is told either way.
    @discardableResult
    func apply(_ request: QuickPin.Request, to base: Configuration) -> Bool {
        lastPinFailed = true
        do {
            let outcome = try QuickPin.pin(request, into: base)

            // Always through a document, open editor or not. It is the only
            // place that validates, and this menu entry is precisely what gets
            // used *without* opening the editor — so routing around it would
            // leave the most common path as the only unchecked one.
            let hasEditorSession = document != nil
            let session = document ?? makeDocument(for: base)
            session.replace(with: outcome.configuration)

            if let objection = session.objection(to: outcome) {
                // Reporting success here would be the failure this project keeps
                // paying for: a sentence promising an effect that does not happen.
                // With the editor open the change stays in the working copy, so
                // the finding is visible at the field; without it the short-lived
                // document is simply dropped.
                lastPinMessage = objection + (hasEditorSession
                    ? " Die Änderung steht im Editor, ist aber nicht gesichert."
                    : " Nichts wurde geändert.")
                Log.warn(objection)
                return false
            }

            if hasEditorSession {
                // The editor is open: put the change in front of the user
                // instead of writing behind their back over their edits.
                lastPinMessage = outcome.summary + " — im Editor eingetragen, noch nicht gesichert."
                lastPinFailed = false
                return true
            }

            guard session.save() else {
                lastPinMessage = session.saveProblem ?? "Speichern fehlgeschlagen."
                return false
            }
            Log.success(outcome.summary)
            lastPinMessage = outcome.summary
            lastPinFailed = false
            return true
        } catch let error as QuickPin.Failure {
            lastPinMessage = error.description
            return false
        } catch {
            lastPinMessage = "Festhalten fehlgeschlagen: \(error)"
            return false
        }
    }

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
