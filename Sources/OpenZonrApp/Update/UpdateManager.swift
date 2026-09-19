import AppUpdater
import Foundation
import Observation
import OpenZonrMac

/// Sucht in den GitHub Releases nach einem neueren OpenZonr und tauscht das
/// Bundle an Ort und Stelle aus.
///
/// Darunter liegt [AppUpdater](https://github.com/mxcl/AppUpdater). Es nimmt
/// nur ein Release-Anhängsel, das genau `OpenZonr-<semver>.dmg` heisst und
/// darin genau eine App mit dem Dateinamen der installierten trägt — und nur,
/// wenn deren Developer-ID-Team, Signatur-Identifier und Bundle-Identifier mit
/// denen der laufenden App übereinstimmen.
///
/// **Ohne `GitHubAttestationPolicy`.** Zwei Gründe, beide gemessen anderswo:
/// der Notarisierungs-Broker baut das Release in seinem eigenen Repository, es
/// gibt also gar keine Provenienz aus `trsdn/OpenZonr`, gegen die geprüft
/// werden könnte; und bei `swift build`-Produkten sucht AppUpdaters
/// `Bundle.module` nie in `Contents/Resources`, sodass eine Prüfung in einem
/// `fatalError` endet (trsdn/OpenWritr#31). Eine Attestierung zu verlangen
/// würde also jedes echte Release ablehnen und dabei noch abstürzen. Die
/// Prüfungen auf Developer ID, Team und Bundle-Identifier bleiben.
@Observable
@MainActor
final class UpdateManager {

    /// Was die Menüleiste anzeigt.
    private(set) var state: UpdateState = .idle

    /// Der Schalter „Automatisch nach Updates suchen“. Voreingestellt an,
    /// gesichert in den Voreinstellungen.
    var automaticChecksEnabled: Bool {
        didSet {
            guard automaticChecksEnabled != oldValue else { return }
            defaults.set(automaticChecksEnabled, forKey: UpdatePolicy.automaticChecksKey)
            if automaticChecksEnabled { startAutomaticChecks() } else { stopAutomaticChecks() }
        }
    }

    @ObservationIgnored private let updater = AppUpdater(owner: "trsdn", repo: "OpenZonr")
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var preparedUpdate: PreparedUpdate?
    @ObservationIgnored private var lastAutomaticCheck: Date?
    @ObservationIgnored private var automaticCheckTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        automaticChecksEnabled = UpdatePolicy.automaticChecksEnabled(
            stored: defaults.object(forKey: UpdatePolicy.automaticChecksKey)
        )
    }

    var isBusy: Bool { UpdatePolicy.isBusy(state) }

    var hasPreparedUpdate: Bool { preparedUpdate != nil }

    // MARK: - Automatische Suche

    /// Beginnt, stündlich nachzusehen, ob die Tagesfrist abgelaufen ist.
    func startAutomaticChecks() {
        automaticCheckTask?.cancel()
        guard automaticChecksEnabled else {
            automaticCheckTask = nil
            return
        }
        automaticCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                if let self, self.isAutomaticCheckDue {
                    await self.check(userInitiated: false)
                }
                try? await Task.sleep(for: .seconds(UpdatePolicy.wakeInterval))
            }
        }
    }

    func stopAutomaticChecks() {
        automaticCheckTask?.cancel()
        automaticCheckTask = nil
    }

    private var isAutomaticCheckDue: Bool {
        UpdatePolicy.isCheckDue(lastCheck: lastAutomaticCheck, now: Date())
    }

    // MARK: - Suchen, installieren, verwerfen

    /// Sucht nach einem neueren Release und lädt und prüft es gleich mit, damit
    /// das Installieren ein einziger Klick bleibt.
    ///
    /// Eine gescheiterte Hintergrundsuche wird nur protokolliert — offline zu
    /// sein ist keine Meldung wert. Eine Suche, die der Nutzer angestossen hat,
    /// antwortet immer.
    func check(userInitiated: Bool) async {
        guard !isBusy, preparedUpdate == nil else { return }
        if userInitiated {
            state = .checking
        } else {
            lastAutomaticCheck = Date()
        }

        do {
            guard let update = try await updater.check() else {
                state = userInitiated ? .upToDate : .idle
                return
            }
            Log.info("Update verfügbar: \(update.version)")
            state = .downloading(version: update.version)
            preparedUpdate = try await update.prepareInstallation()
            state = .readyToInstall(version: update.version)
        } catch is CancellationError {
            state = .idle
        } catch {
            Log.warn("Update-Suche fehlgeschlagen: \(error.localizedDescription)")
            state = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    /// Tauscht das Bundle aus und startet die App neu. Im Erfolgsfall kehrt das
    /// hier nie zurück. `false` heisst: die Installation ist gescheitert und die
    /// App läuft weiter — der Aufrufer darf wieder aufnehmen, was er angehalten
    /// hat.
    ///
    /// Angehalten wird *vor* diesem Aufruf, nicht hier: was OpenZonr anhalten
    /// muss, weiss ``AppModel`` (siehe ``AppModel/installUpdate()``), und ein
    /// Updater, der in die Fensterbeobachtung greift, wäre eine zweite
    /// Buchhaltung derselben Sache.
    @discardableResult
    func installAndRelaunch() async -> Bool {
        guard let prepared = preparedUpdate else { return false }
        preparedUpdate = nil
        state = .installing
        stopAutomaticChecks()

        do {
            try await prepared.installAndRelaunch()
            return true
        } catch {
            Log.warn("Update-Installation fehlgeschlagen: \(error.localizedDescription)")
            state = .failed(error.localizedDescription)
            startAutomaticChecks()
            return false
        }
    }

    /// Wirft das geladene Update weg. Die nächste Suche findet es wieder.
    func dismiss() async {
        if let prepared = preparedUpdate {
            preparedUpdate = nil
            await prepared.discard()
        }
        state = .idle
    }
}
