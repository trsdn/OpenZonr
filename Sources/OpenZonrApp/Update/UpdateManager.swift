import AppUpdater
import Foundation
import Observation
import OpenZonrMac

/// Looks for a newer OpenZonr in the GitHub Releases and swaps the bundle in
/// place.
///
/// [AppUpdater](https://github.com/mxcl/AppUpdater) sits underneath. It only
/// accepts a release asset named exactly `OpenZonr-<semver>.dmg`, containing
/// exactly one app with the installed one's file name — and only when its
/// Developer ID team, signing identifier and bundle identifier match those
/// of the running app.
///
/// **Without `GitHubAttestationPolicy`.** Two reasons, both measured
/// elsewhere: the notarization broker builds the release in its own
/// repository, so there is no provenance from `trsdn/OpenZonr` to check
/// against; and for `swift build` products, AppUpdater's `Bundle.module`
/// never looks in `Contents/Resources`, so a check ends in a `fatalError`
/// (trsdn/OpenWritr#31). Requiring an attestation would therefore reject
/// every real release, and crash while doing it. The checks on Developer
/// ID, team and bundle identifier stay.
@Observable
@MainActor
final class UpdateManager {

    /// What the menu bar displays.
    private(set) var state: UpdateState = .idle

    /// The "Automatically check for updates" switch. On by default, saved
    /// in the preferences.
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
    @ObservationIgnored private var automaticCheckTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        automaticChecksEnabled = UpdatePolicy.automaticChecksEnabled(
            stored: defaults.object(forKey: UpdatePolicy.automaticChecksKey)
        )
    }

    var isBusy: Bool { UpdatePolicy.isBusy(state) }

    var hasPreparedUpdate: Bool { preparedUpdate != nil }

    // MARK: - Automatic checking

    /// Starts checking hourly whether the daily deadline has passed.
    func startAutomaticChecks() {
        automaticCheckTask?.cancel()
        guard automaticChecksEnabled else {
            automaticCheckTask = nil
            return
        }
        automaticCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                // If the model is gone, the loop is done too. A bare `if let
                // self` would instead sleep hourly forever and do nothing.
                guard let self else { return }
                if self.isAutomaticCheckDue {
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

    /// When the last automatic check ran — saved in the preferences, see
    /// ``UpdatePolicy/lastAutomaticCheckKey``.
    var lastAutomaticCheck: Date? {
        get {
            UpdatePolicy.lastAutomaticCheck(
                stored: defaults.object(forKey: UpdatePolicy.lastAutomaticCheckKey)
            )
        }
        set { defaults.set(newValue, forKey: UpdatePolicy.lastAutomaticCheckKey) }
    }

    var isAutomaticCheckDue: Bool {
        UpdatePolicy.isCheckDue(lastCheck: lastAutomaticCheck, now: Date())
    }

    // MARK: - Checking, installing, discarding

    /// Checks for a newer release and downloads and verifies it right away,
    /// so installing stays a single click.
    ///
    /// A failed background check is only logged — being offline is not worth
    /// a message. A check the user triggered always responds.
    func check(userInitiated: Bool) async {
        guard !isBusy, preparedUpdate == nil else { return }
        // The background check also marks itself as "busy". Without that, a
        // user-triggered check could run alongside it, both would reach the
        // preparation step, and the second assignment would lose the already
        // downloaded update — unpacked directory and all.
        state = .checking
        if !userInitiated { lastAutomaticCheck = Date() }

        do {
            guard let update = try await updater.check() else {
                state = userInitiated ? .upToDate : .idle
                return
            }
            Log.info(localized("updateManager.updateAvailable", "Update available: %@", update.version))
            state = .downloading(version: update.version)
            let prepared = try await update.prepareInstallation()
            // Belt and braces: if something prepared already arrives here
            // despite the guard above, it is cleaned up rather than forgotten.
            if let stale = preparedUpdate {
                preparedUpdate = nil
                await stale.discard()
            }
            preparedUpdate = prepared
            state = .readyToInstall(version: update.version)
        } catch is CancellationError {
            state = .idle
        } catch {
            Log.warn(
                localized("updateManager.checkFailed", "Update check failed: %@", error.localizedDescription)
            )
            state = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    /// Swaps the bundle and relaunches the app. On success, this never
    /// returns. `false` means: the installation failed and the app keeps
    /// running — the caller may resume whatever it paused.
    ///
    /// Pausing happens *before* this call, not here: what OpenZonr needs to
    /// pause is ``AppModel``'s business (see ``AppModel/installUpdate()``),
    /// and an updater that reaches into window observation would be a second
    /// bookkeeping of the same thing.
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
            Log.warn(
                localized(
                    "updateManager.installFailed", "Update installation failed: %@", error.localizedDescription
                )
            )
            // The unpacked download is worthless after a failed swap and
            // would otherwise sit in the temporary directory until the next
            // restart. The next check finds the release again anyway.
            await prepared.discard()
            state = .failed(error.localizedDescription)
            startAutomaticChecks()
            return false
        }
    }

    /// Discards the downloaded update. The next check finds it again.
    func dismiss() async {
        if let prepared = preparedUpdate {
            preparedUpdate = nil
            await prepared.discard()
        }
        state = .idle
    }
}
