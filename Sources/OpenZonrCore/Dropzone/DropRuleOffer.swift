import Foundation

/// The window that was dragged, reduced to what a rule needs.
public struct DroppedWindow: Hashable, Sendable {
    public var bundleIdentifier: String?
    public var applicationName: String

    public init(bundleIdentifier: String?, applicationName: String) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
    }
}

/// "Diese App immer hier öffnen?" — the offer that follows a drop.
///
/// The drop is the most natural moment there is to write a rule: the user has
/// just said, with the mouse, where this application belongs. What it must *not*
/// become is a second way of deriving rules. Everything after "which app, which
/// zone" is ``QuickPin``'s job — priority, role reuse, retargeting an existing
/// rule instead of duplicating it — and this type does no more than assemble its
/// request.
public enum DropRuleOffer {

    /// Why no offer can be made.
    public enum Refusal: Error, Hashable, Sendable, CustomStringConvertible {
        case missingBundleIdentifier(applicationName: String)
        case offerSwitchedOff

        public var description: String {
            switch self {
            case let .missingBundleIdentifier(name):
                return "„\(name)“ meldet keine Bundle-Kennung; ohne sie lässt sich keine Regel schreiben."
            case .offerSwitchedOff:
                return "Das Angebot nach dem Ablegen ist in der Konfiguration abgeschaltet."
            }
        }
    }

    /// The request ``QuickPin/pin(_:into:)`` needs, or the reason there is none.
    public static func request(
        for window: DroppedWindow,
        droppedInto zone: Dropzone,
        profile: ProfileID,
        settings: DropzoneSettings
    ) -> Result<QuickPin.Request, Refusal> {
        guard settings.offerRule else { return .failure(.offerSwitchedOff) }
        guard let bundleIdentifier = window.bundleIdentifier, !bundleIdentifier.isEmpty else {
            return .failure(.missingBundleIdentifier(applicationName: window.applicationName))
        }
        return .success(
            QuickPin.Request(
                bundleIdentifier: bundleIdentifier,
                applicationName: window.applicationName,
                profile: profile,
                target: QuickPin.Target(display: zone.display, zone: zone.zone)
            )
        )
    }

    /// The question, with the place named.
    ///
    /// Naming the zone is the point: "Diese App immer hier öffnen?" leaves the
    /// user guessing what "hier" resolved to when zones overlap, and a rule
    /// written from a misunderstanding is worse than no rule.
    public static func question(for window: DroppedWindow, zone: Dropzone) -> String {
        "„\(window.applicationName)“ immer in \(zone.name) (\(zone.display)) öffnen?"
    }
}
