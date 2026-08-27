import Foundation

/// What OpenZonr does with a window once a rule matched.
public struct PlacementAction: Codable, Hashable, Sendable {

    /// Semantic target. Resolved to a concrete zone by the active ``Profile``.
    public var role: RoleID

    /// Optional subdivision of the target zone.
    ///
    /// Lets two windows share one zone without defining a second zone in the
    /// layout — for example a chat client in the lower third of the
    /// communication zone while mail takes the upper two thirds.
    public var share: ZoneShare?

    /// Whether the window should be raised and focused after placement.
    public var focus: FocusBehavior?

    /// Whether the window is moved outright or the placement is only offered.
    public var mode: PlacementMode?

    public init(
        role: RoleID,
        share: ZoneShare? = nil,
        focus: FocusBehavior? = nil,
        mode: PlacementMode? = nil
    ) {
        self.role = role
        self.share = share
        self.focus = focus
        self.mode = mode
    }
}

/// Subdivision of a zone into equal slots.
///
/// Kept deliberately simple: an axis, a slot count and the slot this window
/// takes. Anything more expressive belongs into the layout as its own zone.
public struct ZoneShare: Codable, Hashable, Sendable {
    public enum Axis: String, Codable, Sendable {
        /// Slots are placed left to right.
        case horizontal
        /// Slots are placed top to bottom.
        case vertical
    }

    public var axis: Axis
    /// Number of slots the zone is divided into, `>= 2`.
    public var slots: Int
    /// Zero-based index of the slot this window occupies.
    public var slotIndex: Int

    public init(axis: Axis, slots: Int, slotIndex: Int) {
        self.axis = axis
        self.slots = slots
        self.slotIndex = slotIndex
    }
}

/// Whether a placed window steals focus.
public enum FocusBehavior: String, Codable, Sendable {
    /// Raise and activate the window after placing it.
    case activate
    /// Place the window but keep the currently focused window in front.
    ///
    /// The sane default for apps that are launched in the background, such as a
    /// mail client started at login.
    case leaveAsIs
}

/// Whether a matching rule acts on its own or only proposes.
public enum PlacementMode: String, Codable, Sendable {
    /// Move and resize the window immediately.
    case place
    /// Do not move the window; offer the placement (notification / overlay hint)
    /// and let the user confirm.
    ///
    /// Useful while tuning a new rule, and for apps that react badly to being
    /// moved during startup.
    case suggest
}
