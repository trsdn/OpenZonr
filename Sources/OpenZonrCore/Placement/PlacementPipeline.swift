import Foundation

/// The read-only view of a window that the rule engine works on.
///
/// Deliberately a plain value type rather than an `AXUIElement`: it makes the
/// matching logic testable without a running window server, and it pins down
/// exactly which attributes are read on the hot path.
public struct WindowSnapshot: Hashable, Sendable {
    /// Bundle identifier of the owning application.
    public var bundleIdentifier: String?
    /// Process identifier of the owning application.
    public var processIdentifier: Int32
    /// `kAXTitleAttribute` at the moment the window appeared.
    public var title: String?
    /// `kAXRoleAttribute`.
    public var role: String?
    /// `kAXSubroleAttribute`.
    public var subrole: String?
    /// Frame in global screen points, as reported by the Accessibility API.
    public var frame: WindowFrame
    /// `true` if this is the first qualifying window since the app launched.
    public var isFirstWindowAfterLaunch: Bool
    /// When the window was observed.
    public var observedAt: Date

    public init(
        bundleIdentifier: String?,
        processIdentifier: Int32,
        title: String?,
        role: String?,
        subrole: String?,
        frame: WindowFrame,
        isFirstWindowAfterLaunch: Bool,
        observedAt: Date
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.processIdentifier = processIdentifier
        self.title = title
        self.role = role
        self.subrole = subrole
        self.frame = frame
        self.isFirstWindowAfterLaunch = isFirstWindowAfterLaunch
        self.observedAt = observedAt
    }
}

/// An absolute window frame in global screen points.
public struct WindowFrame: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// Source of window-created events.
///
/// Implemented on top of `NSWorkspace.didLaunchApplicationNotification` plus one
/// `AXObserver` per running application listening for
/// `kAXWindowCreatedNotification`. Applications that were already running when
/// OpenZonr starts get an observer attached during the initial scan.
public protocol WindowEventSource: AnyObject {
    /// Starts observing. Requires the Accessibility permission.
    func start() throws
    /// Stops observing and releases all per-application observers.
    func stop()
}

/// Decides whether a window is a placement candidate at all.
///
/// Runs before the rule engine and applies the cheap, global filters: subrole,
/// minimum size, and the "first window after launch" default. Anything rejected
/// here never reaches rule evaluation.
public protocol WindowFilter: Sendable {
    func accepts(_ window: WindowSnapshot, defaults: GlobalDefaults) -> Bool
}

/// Picks the first matching rule for a window.
public protocol RuleEngine: Sendable {
    /// Returns the highest-priority enabled rule whose match applies, or `nil`.
    func firstMatch(for window: WindowSnapshot, in rules: [PlacementRule], defaults: GlobalDefaults) -> PlacementRule?
}

/// Determines the currently active profile from the attached displays.
public protocol ProfileResolver: Sendable {
    /// Returns the profile whose fingerprint equals the current setup.
    ///
    /// Returns `nil` for an unknown setup — the caller then asks the user to
    /// create a profile rather than falling back to a guess.
    func activeProfile(for fingerprint: SetupFingerprint, in configuration: Configuration) -> Profile?
}

/// Translates a role into concrete screen geometry.
public protocol ZoneResolver: Sendable {
    /// Resolves `role` through `profile` to an absolute frame, applying the
    /// optional ``ZoneShare`` subdivision. Falls back to the profile's
    /// ``Profile/fallback`` binding when the role is unmapped.
    func resolve(
        role: RoleID,
        share: ZoneShare?,
        profile: Profile,
        configuration: Configuration
    ) -> ResolvedPlacement?
}

/// A fully resolved placement target, ready to be written to a window.
public struct ResolvedPlacement: Hashable, Sendable {
    /// Target frame in global screen points.
    public var frame: WindowFrame
    /// Display the frame belongs to.
    public var display: DisplayAlias
    /// Zone the frame was derived from.
    public var zone: ZoneID
    /// `true` if the profile fallback was used because the role was unmapped.
    public var usedFallback: Bool

    public init(frame: WindowFrame, display: DisplayAlias, zone: ZoneID, usedFallback: Bool) {
        self.frame = frame
        self.display = display
        self.zone = zone
        self.usedFallback = usedFallback
    }
}

/// Writes position and size to a window.
///
/// Implemented via `kAXPositionAttribute` and `kAXSizeAttribute` on the window's
/// `AXUIElement`, wrapped in the retry loop described by ``RetryPolicy``.
public protocol WindowPlacer: Sendable {
    func place(_ window: WindowSnapshot, at placement: ResolvedPlacement, retry: RetryPolicy) async -> PlacementOutcome
}

/// Result of a placement attempt, used for logging and for the diagnostics UI.
public enum PlacementOutcome: Hashable, Sendable {
    /// The window ended up within tolerance of the requested frame.
    case placed(attempts: Int)
    /// The window was only proposed, per ``PlacementMode/suggest``.
    case suggested
    /// No rule matched, or the window was filtered out.
    case notApplicable
    /// The user had moved this window manually, so the rule stood down.
    case skippedManualOverride
    /// The app refused to honour the requested frame after all retries.
    ///
    /// Some Java toolkits and a few Electron builds ignore Accessibility
    /// positioning, or clamp it to their own idea of a valid frame. This case
    /// exists so the UI can name the offending app instead of failing silently.
    case rejectedByApplication(actual: WindowFrame, attempts: Int)
    /// Placement could not run because the Accessibility permission is missing.
    case missingPermission
}
