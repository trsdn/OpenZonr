import Foundation

/// Where in the update flow the app currently stands.
///
/// Its own type, not `AppUpdater`'s own state: what the menu bar shows is
/// this app's own decision, and it should be checkable without a network,
/// without a bundle and without `AppUpdater`.
enum UpdateState: Equatable {
    /// Nothing is running, nothing is ready.
    case idle
    /// A check the user triggered is running.
    case checking
    /// The last explicit check found nothing newer.
    case upToDate
    /// A found update is downloading and being verified.
    case downloading(version: String)
    /// Downloaded and verified — a click is all it takes.
    case readyToInstall(version: String)
    /// The bundle swap is running. The app relaunches afterwards.
    case installing
    /// The check or the installation failed.
    case failed(String)
}

/// The pure decisions around updates: when one is due, what the default is,
/// what the menu says.
///
/// Separate from ``UpdateManager``, because everything there depends on the
/// network and a real bundle. Nothing here does, and that is exactly what
/// is tested (see `Tests/OpenZonrAppTests/UpdatePolicyTests.swift`).
enum UpdatePolicy {

    /// Checked at most once a day.
    static let checkInterval: TimeInterval = 24 * 60 * 60

    /// Checked hourly whether the daily deadline has passed.
    ///
    /// A plain 24-hour alarm would never fire, for an arbitrarily long time,
    /// on a Mac that sleeps at night: the timer does not keep running
    /// through sleep, and the next deadline shifts with every sleep cycle.
    /// Waking hourly and reading the clock does not have that problem.
    static let wakeInterval: TimeInterval = 60 * 60

    /// The preferences key for automatic checking.
    static let automaticChecksKey = "checkForUpdatesAutomatically"

    /// The preferences key for the last automatic check.
    ///
    /// In the preferences, not just in memory: a menu bar app is rarely
    /// quit, but a machine does get restarted. With a purely remembered
    /// timestamp, every launch would start with a due check, and "at most
    /// once a day" would really mean "at every login".
    static let lastAutomaticCheckKey = "lastAutomaticUpdateCheck"

    /// Reads the stored timestamp, or `nil` when nothing usable is there.
    static func lastAutomaticCheck(stored: Any?) -> Date? {
        stored as? Date
    }

    /// Whether an automatic check is due.
    ///
    /// With no previous check, it is due immediately — otherwise a freshly
    /// launched app would not learn about an update until the next day.
    ///
    /// A stored timestamp that lies in the future also counts as due.
    /// Otherwise a clock that jumps backward once — a time zone change,
    /// NTP, or set by hand — would be enough to permanently disable
    /// automatic checking: the difference would stay negative forever and
    /// never reach the daily deadline.
    static func isCheckDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        let elapsed = now.timeIntervalSince(lastCheck)
        if elapsed < 0 { return true }
        return elapsed >= checkInterval
    }

    /// The initial value of the "Automatically check for updates" switch.
    ///
    /// On by default. `UserDefaults.bool(forKey:)` would not give that:
    /// it returns `false` when the key is missing, which cannot tell "never
    /// set" apart from "switched off". Hence the route through
    /// `object(forKey:)`.
    static func automaticChecksEnabled(stored: Any?) -> Bool {
        (stored as? Bool) ?? true
    }

    /// Whether something is running right now that a second check would
    /// disrupt.
    static func isBusy(_ state: UpdateState) -> Bool {
        switch state {
        case .checking, .downloading, .installing: return true
        case .idle, .upToDate, .readyToInstall, .failed: return false
        }
    }

    /// The line that sits above the update entries in the menu — or `nil`
    /// when there is nothing to say.
    ///
    /// `.idle` says nothing: a line saying "nothing going on" would be noise
    /// in a menu that is already long.
    static func statusLine(for state: UpdateState) -> String? {
        switch state {
        case .idle:
            return nil
        case .checking:
            return localized("updatePolicy.statusLine.checking", "Checking for updates …")
        case .upToDate:
            return localized("updatePolicy.statusLine.upToDate", "OpenZonr is up to date")
        case let .downloading(version):
            return localized("updatePolicy.statusLine.downloading", "Downloading update %@ …", version)
        case let .readyToInstall(version):
            return localized("updatePolicy.statusLine.readyToInstall", "Update %@ is ready", version)
        case .installing:
            return localized("updatePolicy.statusLine.installing", "Installing update …")
        case let .failed(message):
            return localized("updatePolicy.statusLine.failed", "Update failed: %@", message)
        }
    }

    /// The install button's caption — or `nil` while nothing is ready and
    /// the button therefore does not appear at all.
    static func installTitle(for state: UpdateState) -> String? {
        guard case let .readyToInstall(version) = state else { return nil }
        return localized("updatePolicy.installTitle", "Install and Relaunch (%@)", version)
    }
}
