import Foundation

/// What the overlay should show at a given moment, decided without AppKit.
///
/// The drawing needs a screen, a window server and — because a drag has to be
/// observed to exist — the Accessibility permission this project does not have
/// on hand. The *decision* needs none of that: given a pointer, a profile and
/// the state of the modifier keys, which zones belong on screen and which one
/// is under the pointer is arithmetic.
///
/// So it lives here, apart from the view, and is tested headlessly. What is
/// left in the view is drawing, which fails visibly.
public enum DropzoneOverlayPlan {

    /// The overlay's whole state as one value.
    public enum Plan: Hashable, Sendable {
        /// Draw `zones` on the display under the pointer, with `highlighted`
        /// picked out.
        case show(zones: [Dropzone], highlighted: Dropzone?)
        /// Draw nothing, for the stated reason.
        case hidden(DropzoneActivation)

        public var zones: [Dropzone] {
            if case let .show(zones, _) = self { return zones }
            return []
        }

        public var highlighted: Dropzone? {
            if case let .show(_, highlighted) = self { return highlighted }
            return nil
        }

        public var isVisible: Bool {
            if case .show = self { return true }
            return false
        }
    }

    /// Decides what to show.
    ///
    /// Only the zones of the display under the pointer are returned. Showing
    /// every display's zones at once was the obvious alternative and is worse:
    /// on the measuring machine that is a 5120-point-wide display next to two
    /// smaller ones, and a full-width overlay turns a drag into a light show
    /// while hiding the window being dragged.
    ///
    /// - Parameters:
    ///   - pointer: Where the pointer is, in AppKit coordinates.
    ///   - origin: Where the drag started, for the distance threshold.
    ///   - configuration: The loaded configuration.
    ///   - profile: The active profile, or `nil` when none matches — then there
    ///     is nothing to offer and the overlay stays away.
    ///   - visibleFrames: The usable area per display, already resolved.
    ///   - settings: The user's dropzone settings.
    ///   - modifiers: The modifier keys held *now*, not at the start of the
    ///     drag: pressing the suppression key mid-drag means it.
    public static func plan(
        pointer: ScreenPoint,
        origin: ScreenPoint,
        configuration: Configuration,
        profile: ProfileID?,
        visibleFrames: VisibleFrames,
        settings: DropzoneSettings,
        modifiers: ModifierState
    ) -> Plan {
        let activation = DropzoneActivator.activation(
            settings: settings,
            modifiers: modifiers,
            travelled: DropzoneActivator.distance(from: origin, to: pointer)
        )
        guard activation.showsZones else { return .hidden(activation) }
        guard let profile else { return .hidden(.disabled) }

        let all = DropzoneMap.zones(in: configuration, profile: profile, visibleFrames: visibleFrames)
        let onDisplay = DropzoneMap.zones(onDisplayUnder: pointer, in: all)
        guard !onDisplay.isEmpty else { return .hidden(.disabled) }

        return .show(zones: onDisplay, highlighted: DropzoneMap.zone(at: pointer, in: onDisplay))
    }
}
