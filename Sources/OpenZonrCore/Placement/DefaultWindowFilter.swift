import Foundation

/// The global pre-filter that every window passes before rule evaluation.
///
/// Rejection reasons are returned instead of a bare `Bool` so that `watch` can
/// log *why* a window was ignored. "Nothing happened" without an explanation is
/// the worst possible behaviour for a tool that acts on window creation.
public struct DefaultWindowFilter: WindowFilter {

    /// Why a window was rejected before rule evaluation.
    public enum Rejection: Hashable, Sendable, CustomStringConvertible {
        case notOnBaseLayer(Int)
        case disallowedSubrole(String?)
        case tooSmall(WindowFrame, WindowSize)
        case notFirstWindowAfterLaunch

        public var description: String {
            switch self {
            case let .notOnBaseLayer(layer):
                return "Fensterebene \(layer) statt 0 (Systemfenster, kein App-Fenster)"
            case let .disallowedSubrole(subrole):
                return "Subrole \(subrole ?? "—") ist nicht in allowedSubroles"
            case let .tooSmall(frame, minimum):
                return "zu klein: \(Int(frame.width))×\(Int(frame.height)), Minimum \(Int(minimum.width))×\(Int(minimum.height))"
            case .notFirstWindowAfterLaunch:
                return "nicht das erste Fenster seit dem App-Start"
            }
        }
    }

    public init() {}

    public func accepts(_ window: WindowSnapshot, defaults: GlobalDefaults) -> Bool {
        rejection(for: window, defaults: defaults) == nil
    }

    /// The reason a window is not a placement candidate, or `nil` if it is one.
    public func rejection(for window: WindowSnapshot, defaults: GlobalDefaults) -> Rejection? {
        // Layer first, and unconditionally. The notification centre panel is as
        // large as the whole ultrawide display and carries a plausible subrole;
        // its layer is the only thing that gives it away. Dock, menu bars and
        // control-centre items are rejected here as well.
        guard window.windowLayer == 0 else {
            return .notOnBaseLayer(window.windowLayer)
        }

        if !defaults.allowedSubroles.isEmpty {
            guard let subrole = window.subrole, defaults.allowedSubroles.contains(subrole) else {
                return .disallowedSubrole(window.subrole)
            }
        }

        let minimum = defaults.minimumWindowSize
        if window.frame.width < minimum.width || window.frame.height < minimum.height {
            return .tooSmall(window.frame, minimum)
        }

        if defaults.onlyFirstWindowAfterLaunch, !window.isFirstWindowAfterLaunch {
            return .notFirstWindowAfterLaunch
        }

        return nil
    }
}
