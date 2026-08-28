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
        case alreadyPinned(applicationName: String, zoneName: String)
        case pinImpossible(reason: String)

        public var description: String {
            switch self {
            case let .missingBundleIdentifier(name):
                return "„\(name)“ meldet keine Bundle-Kennung; ohne sie lässt sich keine Regel schreiben."
            case .offerSwitchedOff:
                return "Das Angebot nach dem Ablegen ist in der Konfiguration abgeschaltet."
            case let .alreadyPinned(name, zone):
                return "„\(name)“ zeigt bereits auf \(zone); es gibt nichts zu entscheiden."
            case let .pinImpossible(reason):
                return "Aus dem Ablegen ließe sich keine Regel schreiben: \(reason)"
            }
        }
    }

    /// The request ``QuickPin/pin(_:into:)`` needs, or the reason there is none.
    ///
    /// The last two checks are the interesting ones, and they are why this takes
    /// the whole configuration rather than just a profile ID.
    ///
    /// An offer is only worth making when a yes would change something.
    /// Dropping Outlook into the zone its rule already points at and being asked
    /// anyway ends with a saved-but-identical configuration and a `Log.success`
    /// reporting a change that did not happen — the silent-success failure this
    /// project keeps paying for, in a new place.
    ///
    /// **Whether it would change something is not decided here.** That would be
    /// a second opinion about rules, and two opinions drift. ``QuickPin`` is
    /// asked instead: it derives the configuration a yes would produce, and if
    /// that is the configuration we already have, there is nothing to ask. The
    /// same call surfaces the case where a pin could not be derived at all, so
    /// the question is never posed to a yes that would then fail.
    public static func request(
        for window: DroppedWindow,
        droppedInto zone: Dropzone,
        profile: ProfileID,
        settings: DropzoneSettings,
        configuration: Configuration
    ) -> Result<QuickPin.Request, Refusal> {
        guard settings.offerRule else { return .failure(.offerSwitchedOff) }
        guard let bundleIdentifier = window.bundleIdentifier, !bundleIdentifier.isEmpty else {
            return .failure(.missingBundleIdentifier(applicationName: window.applicationName))
        }
        let request = QuickPin.Request(
            bundleIdentifier: bundleIdentifier,
            applicationName: window.applicationName,
            profile: profile,
            target: QuickPin.Target(display: zone.display, zone: zone.zone)
        )

        let outcome: QuickPin.Outcome
        do {
            outcome = try QuickPin.pin(request, into: configuration)
        } catch {
            return .failure(.pinImpossible(reason: "\(error)"))
        }
        guard outcome.configuration != configuration else {
            return .failure(.alreadyPinned(applicationName: window.applicationName, zoneName: zone.name))
        }
        return .success(request)
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
