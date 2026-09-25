import Foundation

/// Why a window was not considered for placement at all.
///
/// The filter returns a reason rather than a bare `false` so a diagnostics mode
/// can answer the only question a user ever asks about this stage: *why was my
/// window not moved?* Without the reason that question can only be answered by
/// reading the source.
public enum WindowRejectionReason: Hashable, Sendable, CustomStringConvertible {

    /// The window does not live on the application layer.
    ///
    /// Measured, not assumed: on the author's machine the Notification Centre
    /// occupies a 5120×1440 window on layer 21 and would pass every other
    /// filter. See ``WindowSnapshot/windowLayer``.
    case notOnApplicationLayer(Int)

    /// The subrole is not in ``GlobalDefaults/allowedSubroles``.
    case disallowedSubrole(String?)

    /// The window is smaller than ``GlobalDefaults/minimumWindowSize``.
    case tooSmall(actual: WindowSize, minimum: WindowSize)

    /// Only the first window after launch is placed, and this is not it.
    case notFirstWindowAfterLaunch

    public var description: String {
        switch self {
        case let .notOnApplicationLayer(layer):
            return L.string(
                "windowRejectionReason.notOnApplicationLayer",
                "Window is on layer %lld instead of layer 0, so it is system chrome.",
                layer
            )
        case let .disallowedSubrole(subrole):
            return L.string(
                "windowRejectionReason.disallowedSubrole",
                "Subrole %@ is not allowed.",
                subrole ?? L.string("windowRejectionReason.disallowedSubrole.none", "(none)")
            )
        case let .tooSmall(actual, minimum):
            return L.string(
                "windowRejectionReason.tooSmall",
                "Window %g×%g is below the minimum size %g×%g.",
                actual.width, actual.height, minimum.width, minimum.height
            )
        case .notFirstWindowAfterLaunch:
            return L.string(
                "windowRejectionReason.notFirstWindowAfterLaunch",
                "Not the first window after the app launched."
            )
        }
    }
}

/// Outcome of the cheap, global pre-filter.
public enum WindowFilterResult: Hashable, Sendable {
    case accepted
    case rejected(WindowRejectionReason)

    public var isAccepted: Bool {
        if case .accepted = self { return true }
        return false
    }

    /// The rejection reason, or `nil` when the window was accepted.
    public var rejectionReason: WindowRejectionReason? {
        if case let .rejected(reason) = self { return reason }
        return nil
    }
}
