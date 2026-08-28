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

    /// How dragging a window into a zone behaves.
    public var dropzones: DropzoneSettings

    public init(
        onlyFirstWindowAfterLaunch: Bool = true,
        allowedSubroles: [String] = ["AXStandardWindow"],
        minimumWindowSize: WindowSize = WindowSize(width: 400, height: 300),
        retry: RetryPolicy = RetryPolicy(),
        conflict: ConflictPolicy = ConflictPolicy(),
        dropzones: DropzoneSettings = DropzoneSettings()
    ) {
        self.onlyFirstWindowAfterLaunch = onlyFirstWindowAfterLaunch
        self.allowedSubroles = allowedSubroles
        self.minimumWindowSize = minimumWindowSize
        self.retry = retry
        self.conflict = conflict
        self.dropzones = dropzones
    }

    private enum CodingKeys: String, CodingKey {
        case onlyFirstWindowAfterLaunch, allowedSubroles, minimumWindowSize, retry, conflict, dropzones
    }

    /// Decodes with every field omissible.
    ///
    /// Written by hand for the same reason ``Configuration`` is: a file that
    /// predates a field must keep loading. Adding `dropzones` to a synthesised
    /// decoder would have made every existing configuration fail — the whole
    /// file, not the section — which is the loudest possible way to break
    /// something that has nothing to do with dragging windows.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = GlobalDefaults()
        self.onlyFirstWindowAfterLaunch = try container.decodeIfPresent(
            Bool.self, forKey: .onlyFirstWindowAfterLaunch
        ) ?? defaults.onlyFirstWindowAfterLaunch
        self.allowedSubroles = try container.decodeIfPresent(
            [String].self, forKey: .allowedSubroles
        ) ?? defaults.allowedSubroles
        self.minimumWindowSize = try container.decodeIfPresent(
            WindowSize.self, forKey: .minimumWindowSize
        ) ?? defaults.minimumWindowSize
        self.retry = try container.decodeIfPresent(RetryPolicy.self, forKey: .retry) ?? defaults.retry
        self.conflict = try container.decodeIfPresent(ConflictPolicy.self, forKey: .conflict) ?? defaults.conflict
        self.dropzones = try container.decodeIfPresent(
            DropzoneSettings.self, forKey: .dropzones
        ) ?? defaults.dropzones
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

    /// Displays that must not influence the setup fingerprint.
    ///
    /// Virtual displays — an OBS capture surface, a teleprompter mirror, a
    /// screen-sharing dummy — appear and disappear while the desk does not
    /// change. Without this list every such appearance rewrites the fingerprint
    /// and the active profile jumps, which is precisely the behaviour the
    /// concept set out to avoid.
    ///
    /// This is an explicit list rather than a heuristic on purpose. Measured on
    /// the author's machine, the two virtual displays report entirely plausible
    /// physical dimensions (677×381 mm and 478×269 mm), so "no physical size
    /// means virtual" is simply wrong. `openzonr displays` marks the likely
    /// candidates and emits them ready to paste; the decision stays with the
    /// user.
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

    /// Decodes a configuration, tolerating absent optional sections.
    ///
    /// Written by hand because `defaults` and `ignoredDisplays` must be
    /// omissible: a hand-written file that only lists displays, roles, profiles
    /// and rules is a perfectly good configuration, and refusing it over a
    /// missing key would be hostile.
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
