import Foundation

/// A modifier key, as far as the drag path is concerned.
///
/// Its own type rather than `NSEvent.ModifierFlags` because the decision it
/// feeds is pure and lives in ``OpenZonrCore``, which has no AppKit. The macOS
/// layer translates once, at the edge.
public enum DropzoneModifier: String, Codable, Hashable, Sendable, CaseIterable {
    case none
    case shift
    case control
    case option
    case command

    /// German label for the menu and for log lines.
    public var label: String {
        switch self {
        case .none: return "keine"
        case .shift: return "Umschalt (⇧)"
        case .control: return "Control (⌃)"
        case .option: return "Option (⌥)"
        case .command: return "Befehl (⌘)"
        }
    }
}

/// Which modifier keys are held right now.
///
/// An option set so the macOS layer can hand over what it read without deciding
/// anything, and so a test can construct a state without a keyboard.
public struct ModifierState: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let shift = ModifierState(rawValue: 1 << 0)
    public static let control = ModifierState(rawValue: 1 << 1)
    public static let option = ModifierState(rawValue: 1 << 2)
    public static let command = ModifierState(rawValue: 1 << 3)

    /// Whether the configured suppression key is among the keys held.
    ///
    /// Named `holds` rather than `contains` after the first version overloaded
    /// `contains` and called `contains(.shift)` inside it: the compiler resolved
    /// that to the new overload rather than to `OptionSet.contains`, and every
    /// call recursed until the stack ran out. The tests died with SIGBUS, which
    /// says nothing about the cause. A distinct name makes the mistake
    /// unavailable.
    public func holds(_ modifier: DropzoneModifier) -> Bool {
        switch modifier {
        case .none: return false
        case .shift: return contains(ModifierState.shift)
        case .control: return contains(ModifierState.control)
        case .option: return contains(ModifierState.option)
        case .command: return contains(ModifierState.command)
        }
    }
}

/// When the dropzones appear during a drag.
///
/// Two forms, so the two ways of thinking about the modifier are one field
/// rather than two that could disagree:
///
/// - ``showsUnless(_:)`` — the older behaviour. Zones show on every drag; the
///   key silences them.
/// - ``showsWhile(_:)`` — the new default. Zones stay away and only appear
///   while the key is held.
///
/// The move to *shows while* is deliberate and has a measured price: ⌘ on a
/// window drag already means *bewegen, ohne zu aktivieren* — the drag does not
/// bring a background window forward. Making ⌘ the switch that lights up the
/// zones therefore trades away the old *drag with no key* gesture. See
/// `docs/dropzones.md` for the measurements and the reasoning.
///
/// ``DropzoneModifier/none`` is refused for both forms: *always show* was the
/// old *shows unless none* and is not a mode worth adding a case for; *never
/// show* is what `enabled = false` already says.
public enum DropzoneActivationRule: Hashable, Sendable {
    case showsUnless(DropzoneModifier)
    case showsWhile(DropzoneModifier)

    /// The key involved either way — for the menu, the log, and the tests.
    public var modifier: DropzoneModifier {
        switch self {
        case let .showsUnless(modifier), let .showsWhile(modifier):
            return modifier
        }
    }
}

/// How the dropzones behave while a window is being dragged.
public struct DropzoneSettings: Codable, Hashable, Sendable {

    /// Whether dragging a window shows the zones at all.
    public var enabled: Bool

    /// When the zones appear.
    ///
    /// Defaults to *shows while ⌘*: the zones stay away and only light up while
    /// Command is held. This trades away the old *drag without a key* gesture
    /// on purpose — on this machine, ⌘-dragging a background window already
    /// means *move it without activating the application*, so with ⌘ as the
    /// switch the zones appear in exactly the situation where the drag does
    /// not bring focus with it.
    ///
    /// The other form, ``DropzoneActivationRule/showsUnless(_:)``, is what the
    /// old ``suppressionModifier`` field expressed and is kept for users who
    /// prefer the old polarity: zones every drag, key silences them.
    public var activation: DropzoneActivationRule

    /// Whether a drop offers to write a rule — "Diese App immer hier öffnen?".
    ///
    /// Off by default. The panel used to appear after every drop, which is the
    /// worst possible moment for a question: the user has just finished a
    /// gesture. Nothing is lost — the menu entry *„Aktuelles Fenster hier
    /// festhalten"* writes the same rule through the same ``QuickPin``, and the
    /// zone's own pin badge (see ``DropzoneMap/pinBadgeFrame(for:)``) offers
    /// the same choice inside the gesture. The switch stays so anyone who
    /// wants the old prompt can keep it.
    public var offerRule: Bool

    /// How far the pointer must travel before the zones appear, in points.
    ///
    /// A window is "dragged" by any mouse-down on its title bar, including the
    /// one that just brings it to the front. Showing four zones for a two-pixel
    /// tremor would make the overlay flicker on every click, so the drag has to
    /// mean it first.
    public var minimumDragDistance: Double

    /// Whether OpenZonr warns when another window manager that reacts to drags
    /// is running.
    ///
    /// See ``CompetingWindowManagers`` for why warning is the answer and
    /// fighting is not.
    public var warnAboutCompetingManagers: Bool

    public init(
        enabled: Bool = true,
        activation: DropzoneActivationRule = .showsWhile(.command),
        offerRule: Bool = false,
        minimumDragDistance: Double = 12,
        warnAboutCompetingManagers: Bool = true
    ) {
        self.enabled = enabled
        self.activation = activation
        self.offerRule = offerRule
        self.minimumDragDistance = minimumDragDistance
        self.warnAboutCompetingManagers = warnAboutCompetingManagers
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, activation, suppressionModifier, offerRule, minimumDragDistance, warnAboutCompetingManagers
    }

    /// Every field is omissible, like the rest of the configuration's optional
    /// sections: a file written before this feature existed must keep loading,
    /// and a hand-written `{"enabled": false}` must be a complete answer.
    ///
    /// **The activation rule reads two keys, one of them old.** Files written
    /// before the new field existed carry `suppressionModifier: "option"`; the
    /// obvious alternative — ignoring the old key and quietly moving every
    /// existing user to the new default — would leave anyone who never touched
    /// the setting with zones that no longer appear on a plain drag, and no
    /// hint why. So the old key still counts: seeing it means the file is old,
    /// and the old polarity (*shows unless*) is what it meant. If both the new
    /// `activation` and the legacy `suppressionModifier` are present, the new
    /// one wins — a hand-written override is not overturned by an outdated
    /// sibling.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DropzoneSettings()
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        if let activation = try container.decodeIfPresent(DropzoneActivationRule.self, forKey: .activation) {
            self.activation = activation
        } else if let legacy = try container.decodeIfPresent(
            DropzoneModifier.self, forKey: .suppressionModifier
        ) {
            self.activation = .showsUnless(legacy)
        } else {
            self.activation = defaults.activation
        }
        self.offerRule = try container.decodeIfPresent(Bool.self, forKey: .offerRule) ?? defaults.offerRule
        self.minimumDragDistance = try container.decodeIfPresent(
            Double.self, forKey: .minimumDragDistance
        ) ?? defaults.minimumDragDistance
        self.warnAboutCompetingManagers = try container.decodeIfPresent(
            Bool.self, forKey: .warnAboutCompetingManagers
        ) ?? defaults.warnAboutCompetingManagers
    }

    /// Only the new field is written. The legacy `suppressionModifier` is a
    /// read-only migration bridge; emitting it again would leave two
    /// descriptions of the same setting in every saved file, and the next round
    /// of hand editing would have to keep them agreeing.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(activation, forKey: .activation)
        try container.encode(offerRule, forKey: .offerRule)
        try container.encode(minimumDragDistance, forKey: .minimumDragDistance)
        try container.encode(warnAboutCompetingManagers, forKey: .warnAboutCompetingManagers)
    }
}

extension DropzoneActivationRule: Codable {
    private enum CodingKeys: String, CodingKey {
        case showsWhile
        case showsUnless
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let modifier = try container.decodeIfPresent(DropzoneModifier.self, forKey: .showsWhile) {
            self = .showsWhile(modifier)
            return
        }
        if let modifier = try container.decodeIfPresent(DropzoneModifier.self, forKey: .showsUnless) {
            self = .showsUnless(modifier)
            return
        }
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription:
                    "Ein Aktivierungs-Feld ohne showsWhile oder showsUnless ist kein Angebot: es lässt offen, wann die Zonen kommen. Erlaubte Formen: {\"showsWhile\": \"command\"} oder {\"showsUnless\": \"option\"}."
            )
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .showsWhile(modifier):
            try container.encode(modifier, forKey: .showsWhile)
        case let .showsUnless(modifier):
            try container.encode(modifier, forKey: .showsUnless)
        }
    }
}

/// Whether the zones should be on screen at this moment of a drag.
public enum DropzoneActivation: Hashable, Sendable {
    /// Show the zones and follow the pointer.
    case show
    /// The feature is switched off in the configuration.
    case disabled
    /// The user is holding the suppression key — drag freely.
    ///
    /// Only produced by ``DropzoneActivationRule/showsUnless(_:)``. The other
    /// form has no *suppress* concept: absence of the key is the same as being
    /// switched off for this drag, not a separate reason.
    case suppressed(DropzoneModifier)
    /// The rule requires the modifier, and it is not held right now.
    ///
    /// Only produced by ``DropzoneActivationRule/showsWhile(_:)``. Told apart
    /// from ``suppressed(_:)`` so the log and the menu can explain *press ⌘*
    /// instead of *release ⌥* — the sentence a first-time user needs.
    case awaitingModifier(DropzoneModifier)
    /// The pointer has not moved far enough yet.
    case belowThreshold(travelled: Double, required: Double)

    public var showsZones: Bool { self == .show }

    /// One German sentence, for the log and for the diagnostics window.
    public var explanation: String {
        switch self {
        case .show:
            return "Zonen werden eingeblendet."
        case .disabled:
            return "Dropzones sind in der Konfiguration abgeschaltet."
        case let .suppressed(modifier):
            return "\(modifier.label) gedrückt — es wird frei gezogen."
        case let .awaitingModifier(modifier):
            return "\(modifier.label) drücken, damit die Zonen erscheinen."
        case let .belowThreshold(travelled, required):
            return "Erst \(Int(travelled.rounded())) von \(Int(required.rounded())) Punkten gezogen."
        }
    }
}

/// The decision "show the zones or not", as a pure function of the drag.
///
/// Separated from the tracker because it is the part that can be proven without
/// the Accessibility permission — which, for this feature, is most of what can
/// be proven at all.
public enum DropzoneActivator {

    /// - Parameters:
    ///   - travelled: distance the pointer has covered since the drag started,
    ///     in points.
    ///   - modifiers: keys held at this moment, not at the start. A user who
    ///     starts dragging and then presses ⌥ means it, and the zones have to
    ///     disappear.
    public static func activation(
        settings: DropzoneSettings,
        modifiers: ModifierState,
        travelled: Double
    ) -> DropzoneActivation {
        guard settings.enabled else { return .disabled }
        switch settings.activation {
        case let .showsUnless(modifier):
            if modifier != .none, modifiers.holds(modifier) {
                return .suppressed(modifier)
            }
        case let .showsWhile(modifier):
            // A rule that requires `.none` is meaningless — it would mean *the
            // zones appear only when no key at all is held*, which is what
            // `showsUnless(.none)` already says. Fall through to the threshold
            // check so the file still loads and the user sees the zones.
            if modifier != .none, !modifiers.holds(modifier) {
                return .awaitingModifier(modifier)
            }
        }
        guard travelled >= settings.minimumDragDistance else {
            return .belowThreshold(travelled: travelled, required: settings.minimumDragDistance)
        }
        return .show
    }

    /// Distance between two points, in points.
    public static func distance(from origin: ScreenPoint, to point: ScreenPoint) -> Double {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// Why the drag half is not listening at all.
///
/// Different from ``DropzoneActivation``, which decides within a running drag.
/// This decides whether there is anything to run — and it exists as its own type
/// because the first version answered the question in two places that disagreed:
/// the controller started listening whenever the feature was switched on, while
/// the menu and the log announced that a pause stopped everything. Both cannot
/// be true, and the one that was wrong was the silent one.
public enum DropzoneSuspension: Hashable, Sendable {
    case switchedOff
    case paused

    /// One German sentence, shown in the menu under the toggle.
    public var explanation: String {
        switch self {
        case .switchedOff:
            return "Dropzones sind in der Konfiguration abgeschaltet."
        case .paused:
            return "Die Platzierung ist pausiert."
        }
    }
}

extension DropzoneActivator {

    /// Whether the tracker should be listening, or why it should not.
    ///
    /// The pause takes the drag half with it. Letting an explicit mouse gesture
    /// through while the automatic half rests would be defensible on its own —
    /// but not while the menu entry is called "Platzierung pausieren" and the
    /// log says "es wird nichts mehr platziert". Of the two ways to make those
    /// agree, this is the one that also helps in the situation that usually
    /// causes a pause: a second window manager pulling the other way, which is
    /// exactly when a second overlay during a drag is worst.
    public static func suspension(settings: DropzoneSettings, isPaused: Bool) -> DropzoneSuspension? {
        guard settings.enabled else { return .switchedOff }
        guard !isPaused else { return .paused }
        return nil
    }
}
