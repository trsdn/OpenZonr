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

/// How the dropzones behave while a window is being dragged.
public struct DropzoneSettings: Codable, Hashable, Sendable {

    /// Whether dragging a window shows the zones at all.
    public var enabled: Bool

    /// Hold this key while dragging and OpenZonr stays out of the way.
    ///
    /// Defaults to Option (⌥) rather than Command (⌘) although Command is what
    /// Windows-style snapping usually suppresses with. On macOS, ⌘-dragging a
    /// window moves it *without* activating its application — a real, long
    /// established interaction — and taking that over would remove a capability
    /// to add one. ⌥ carries no such meaning for window frames.
    ///
    /// ``DropzoneModifier/none`` switches suppression off; there is then no way
    /// to drag freely, which is a choice the user is allowed to make but not the
    /// default.
    public var suppressionModifier: DropzoneModifier

    /// Whether a drop offers to write a rule — "Diese App immer hier öffnen?".
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
        suppressionModifier: DropzoneModifier = .option,
        offerRule: Bool = true,
        minimumDragDistance: Double = 12,
        warnAboutCompetingManagers: Bool = true
    ) {
        self.enabled = enabled
        self.suppressionModifier = suppressionModifier
        self.offerRule = offerRule
        self.minimumDragDistance = minimumDragDistance
        self.warnAboutCompetingManagers = warnAboutCompetingManagers
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, suppressionModifier, offerRule, minimumDragDistance, warnAboutCompetingManagers
    }

    /// Every field is omissible, like the rest of the configuration's optional
    /// sections: a file written before this feature existed must keep loading,
    /// and a hand-written `{"enabled": false}` must be a complete answer.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DropzoneSettings()
        self.enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? defaults.enabled
        self.suppressionModifier = try container.decodeIfPresent(
            DropzoneModifier.self, forKey: .suppressionModifier
        ) ?? defaults.suppressionModifier
        self.offerRule = try container.decodeIfPresent(Bool.self, forKey: .offerRule) ?? defaults.offerRule
        self.minimumDragDistance = try container.decodeIfPresent(
            Double.self, forKey: .minimumDragDistance
        ) ?? defaults.minimumDragDistance
        self.warnAboutCompetingManagers = try container.decodeIfPresent(
            Bool.self, forKey: .warnAboutCompetingManagers
        ) ?? defaults.warnAboutCompetingManagers
    }
}

/// Whether the zones should be on screen at this moment of a drag.
public enum DropzoneActivation: Hashable, Sendable {
    /// Show the zones and follow the pointer.
    case show
    /// The feature is switched off in the configuration.
    case disabled
    /// The user is holding the suppression key — drag freely.
    case suppressed(DropzoneModifier)
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
        if settings.suppressionModifier != .none, modifiers.holds(settings.suppressionModifier) {
            return .suppressed(settings.suppressionModifier)
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
