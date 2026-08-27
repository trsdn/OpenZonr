import Foundation

/// How OpenZonr behaves when a placement collides with reality.
///
/// Conflict handling is spelled out explicitly because it is where automatic
/// window management usually becomes annoying: a tool that insists on its rules
/// fights the user instead of helping.
public struct ConflictPolicy: Codable, Hashable, Sendable {

    /// What to do when the target zone already holds a window.
    public var occupiedZone: OccupiedZoneStrategy

    /// Whether a manual move by the user suppresses further automatic placement
    /// of that window.
    ///
    /// When the user drags a window out of its zone, that is an explicit
    /// statement. OpenZonr must not pull it back. The window is marked as
    /// manually overridden for the rest of its lifetime (or until
    /// ``manualOverrideTimeout`` elapses).
    public var honorManualOverride: Bool

    /// Optional lifetime of a manual override, in seconds.
    ///
    /// `nil` means the override lasts as long as the window exists.
    public var manualOverrideTimeout: Double?

    public init(
        occupiedZone: OccupiedZoneStrategy = .stack,
        honorManualOverride: Bool = true,
        manualOverrideTimeout: Double? = nil
    ) {
        self.occupiedZone = occupiedZone
        self.honorManualOverride = honorManualOverride
        self.manualOverrideTimeout = manualOverrideTimeout
    }
}

/// Strategies for a zone that is already taken.
public enum OccupiedZoneStrategy: String, Codable, Sendable {
    /// Place the new window into the same zone, on top of the existing one.
    ///
    /// The conservative default: nothing is displaced, the zone simply holds
    /// several windows the user can cycle through.
    case stack
    /// Place the new window and move the previous occupant to the profile
    /// fallback zone.
    case replace
    /// Leave the new window wherever the system opened it.
    case skip
}

/// How often and how patiently a placement is retried.
///
/// A window frequently exists before it has settled: Electron apps and the
/// Office suite resize themselves after their first paint, and restoring a
/// saved window state happens asynchronously. Setting position and size once is
/// therefore unreliable — the app overwrites it milliseconds later.
///
/// OpenZonr places the window, reads the resulting frame back, and repeats while
/// the frame does not match. The defaults (three attempts spread over roughly
/// 500 ms) are the smallest thing that reliably beats self-resizing apps
/// without keeping windows visibly jumping.
public struct RetryPolicy: Codable, Hashable, Sendable {
    /// Total number of attempts, including the first one.
    public var attempts: Int
    /// Delay before the first attempt, in seconds.
    public var initialDelay: Double
    /// Delay between subsequent attempts, in seconds.
    public var interval: Double
    /// Tolerance in points when comparing the requested and the actual frame.
    ///
    /// Some apps enforce size increments (terminals) or a minimum size; a small
    /// tolerance prevents pointless retries against a window that is as close as
    /// it will ever get.
    public var tolerance: Double

    public init(
        attempts: Int = 3,
        initialDelay: Double = 0.05,
        interval: Double = 0.2,
        tolerance: Double = 4
    ) {
        self.attempts = attempts
        self.initialDelay = initialDelay
        self.interval = interval
        self.tolerance = tolerance
    }
}
