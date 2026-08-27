import Foundation

/// The set of criteria a window must satisfy for a ``PlacementRule`` to apply.
///
/// All properties are optional and combined with logical **AND**. An empty match
/// therefore matches every window, which is useful for a catch-all rule at the
/// end of the list but dangerous anywhere else.
///
/// The criteria intentionally mirror what the Accessibility API can report
/// cheaply at `kAXWindowCreatedNotification` time: bundle identifier, title,
/// role, subrole and frame. Anything that requires deeper inspection would slow
/// down the placement path, which is already racing the app's own layout code.
public struct WindowMatch: Codable, Hashable, Sendable {

    /// Bundle identifier of the owning application, e.g. `com.microsoft.Outlook`.
    ///
    /// This is the base case and covers the vast majority of rules.
    public var bundleIdentifier: String?

    /// Regular expression matched against the window title (ICU syntax).
    ///
    /// This is what separates "Posteingang" from a compose window. Titles are
    /// localised and often change moments after the window appears, so a title
    /// pattern should be a deliberate choice, not a default.
    public var titlePattern: String?

    /// Accepted values of `kAXRoleAttribute`, e.g. `AXWindow`.
    public var roles: [String]?

    /// Accepted values of `kAXSubroleAttribute`.
    ///
    /// `AXStandardWindow` is the workhorse: it excludes dialogs, sheets, system
    /// floating windows and most popups without any further configuration.
    public var subroles: [String]?

    /// Minimum window size in points; smaller windows do not match.
    ///
    /// Filters reminder popups, notification-style windows and tool palettes.
    public var minimumSize: WindowSize?

    /// Maximum window size in points; larger windows do not match.
    public var maximumSize: WindowSize?

    /// Accepted range of width/height ratios.
    ///
    /// Catches the remaining odd shapes — a very wide, very short window is
    /// almost never a document window.
    public var aspectRatio: AspectRatioRange?

    /// Restricts the rule to the first qualifying window an application opens
    /// after it was launched.
    ///
    /// This is the single most effective default: dialogs, compose windows and
    /// popups appear *later* and are therefore excluded automatically, without
    /// anyone having to write a title regex. When `nil`, the global default from
    /// ``GlobalDefaults`` applies.
    public var onlyFirstWindowAfterLaunch: Bool?

    public init(
        bundleIdentifier: String? = nil,
        titlePattern: String? = nil,
        roles: [String]? = nil,
        subroles: [String]? = nil,
        minimumSize: WindowSize? = nil,
        maximumSize: WindowSize? = nil,
        aspectRatio: AspectRatioRange? = nil,
        onlyFirstWindowAfterLaunch: Bool? = nil
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.titlePattern = titlePattern
        self.roles = roles
        self.subroles = subroles
        self.minimumSize = minimumSize
        self.maximumSize = maximumSize
        self.aspectRatio = aspectRatio
        self.onlyFirstWindowAfterLaunch = onlyFirstWindowAfterLaunch
    }
}

/// Inclusive range of accepted width/height ratios.
public struct AspectRatioRange: Codable, Hashable, Sendable {
    /// Smallest accepted `width / height`.
    public var minimum: Double
    /// Largest accepted `width / height`.
    public var maximum: Double

    public init(minimum: Double, maximum: Double) {
        self.minimum = minimum
        self.maximum = maximum
    }
}
