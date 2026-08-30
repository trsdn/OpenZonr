import Foundation

/// Settings that apply to every rule unless the rule overrides them.
public struct GlobalDefaults: Codable, Hashable, Sendable {

    /// Default for ``WindowMatch/onlyFirstWindowAfterLaunch``.
    ///
    /// Enabled by default. It removes the entire class of "why did my compose
    /// window jump" problems before it appears.
    public var onlyFirstWindowAfterLaunch: Bool

    /// Subroles considered placeable when a rule does not say otherwise.
    public var allowedSubroles: [String]

    /// Windows smaller than this are ignored by default.
    public var minimumWindowSize: WindowSize

    /// Retry behaviour for the placement itself.
    public var retry: RetryPolicy

    /// Behaviour on collisions and after manual moves.
    public var conflict: ConflictPolicy

    public init(
        onlyFirstWindowAfterLaunch: Bool = true,
        allowedSubroles: [String] = ["AXStandardWindow"],
        minimumWindowSize: WindowSize = WindowSize(width: 400, height: 300),
        retry: RetryPolicy = RetryPolicy(),
        conflict: ConflictPolicy = ConflictPolicy()
    ) {
        self.onlyFirstWindowAfterLaunch = onlyFirstWindowAfterLaunch
        self.allowedSubroles = allowedSubroles
        self.minimumWindowSize = minimumWindowSize
        self.retry = retry
        self.conflict = conflict
    }
}

/// Root of the on-disk configuration.
///
/// Stored as JSON so it can be versioned, diffed, shared and hand-edited. JSON
/// has no comments; the annotated walkthrough of the shipped example lives in
/// `docs/konfiguration.md`.
///
/// The file is organised along the indirection that defines OpenZonr:
///
/// ```text
/// rules ──match──> role ──profile──> display + zone ──layout──> geometry
/// ```
///
/// Rules are written once and are independent of the current hardware; profiles
/// translate them into the setup at hand.
public struct Configuration: Codable, Hashable, Sendable {

    /// Schema version, incremented on breaking changes so migrations can be
    /// applied deterministically.
    public var version: Int

    /// Every display OpenZonr knows about, with its layouts.
    public var displays: [DisplayDescriptor]

    /// Semantic placement targets referenced by rules.
    public var roles: [ZoneRole]

    /// Display setups and their role mappings.
    public var profiles: [Profile]

    /// Match → action entries, evaluated by descending priority.
    public var rules: [PlacementRule]

    /// Settings inherited by rules that do not override them.
    public var defaults: GlobalDefaults

    /// Displays that must not influence profile selection.
    ///
    /// Software displays — OBS virtual cameras, teleprompter mirrors, screen
    /// sharing surfaces — appear and disappear while the physical desk does not
    /// change. Without this list every such start would alter the setup
    /// fingerprint and swap the active profile, which is precisely the
    /// behaviour OpenZonr exists to prevent.
    ///
    /// Exclusion is an explicit user decision rather than a heuristic: no public
    /// API reliably distinguishes a virtual display from a real panel, and
    /// guessing wrong would rearrange the whole desktop. `openzonr displays`
    /// flags likely candidates and emits ready-made entries for this list.
    public var ignoredDisplays: [DisplayIdentity]

    public init(
        version: Int,
        displays: [DisplayDescriptor],
        roles: [ZoneRole],
        profiles: [Profile],
        rules: [PlacementRule],
        defaults: GlobalDefaults = GlobalDefaults(),
        ignoredDisplays: [DisplayIdentity] = []
    ) {
        self.version = version
        self.displays = displays
        self.roles = roles
        self.profiles = profiles
        self.rules = rules
        self.defaults = defaults
        self.ignoredDisplays = ignoredDisplays
    }

    private enum CodingKeys: String, CodingKey {
        case version, displays, roles, profiles, rules, defaults, ignoredDisplays
    }

    /// Decoded by hand so that optional sections may be omitted from the file.
    /// A configuration without `defaults` or `ignoredDisplays` stays valid, which
    /// keeps hand-written minimal files — and older files — loadable.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decode(Int.self, forKey: .version)
        self.displays = try container.decode([DisplayDescriptor].self, forKey: .displays)
        self.roles = try container.decode([ZoneRole].self, forKey: .roles)
        self.profiles = try container.decode([Profile].self, forKey: .profiles)
        self.rules = try container.decode([PlacementRule].self, forKey: .rules)
        self.defaults = try container.decodeIfPresent(GlobalDefaults.self, forKey: .defaults) ?? GlobalDefaults()
        self.ignoredDisplays = try container.decodeIfPresent([DisplayIdentity].self, forKey: .ignoredDisplays) ?? []
    }

    /// Schema version this build writes.
    public static let currentVersion = 1
}
