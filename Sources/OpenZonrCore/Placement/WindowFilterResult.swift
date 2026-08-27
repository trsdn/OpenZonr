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
            return "Fenster liegt auf Ebene \(layer) statt auf Ebene 0 und ist damit Systemoberfläche."
        case let .disallowedSubrole(subrole):
            return "Subrole \(subrole ?? "(keine)") ist nicht freigegeben."
        case let .tooSmall(actual, minimum):
            return "Fenster \(actual.width)×\(actual.height) unterschreitet die Mindestgröße \(minimum.width)×\(minimum.height)."
        case .notFirstWindowAfterLaunch:
            return "Nicht das erste Fenster nach dem App-Start."
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
