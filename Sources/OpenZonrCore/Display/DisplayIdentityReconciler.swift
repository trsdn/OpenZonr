import Foundation

/// Maps the display identities a machine **observes** onto the identities a
/// configuration **knows**, and tolerates a drifting port index exactly as far
/// as it can do so without guessing.
///
/// ## Why this exists
///
/// ``DisplayIdentity/fallback(vendorNumber:modelNumber:pixelWidth:pixelHeight:portIndex:)``
/// pins the port index because vendor plus model alone cannot tell two identical
/// monitors apart. The port index is `CGDisplayUnitNumber`, and the assumption
/// behind that choice — that the number stays put as long as the cable does —
/// is now **measured to be false**:
///
/// - 2026-08-29: C49RG9x (vendor 19501, model 3996, serial 0) reported unit `0`.
/// - 2026-09-19: the same monitor on the same cable reported unit `1`.
///
/// Nothing on the desk had moved. What changed was that software displays
/// ("AAA", vendor 21252 model 0, and "Teleprompter Source") were present at
/// enumeration time; the unit numbers 0, 1, 2, 3 were handed out in enumeration
/// order to AAA, C49RG9x, U28E590 and Teleprompter, so every physical display
/// behind a virtual one shifted by one. The configuration said `portIndex: 0`,
/// the machine said `1`, no profile matched — and because both dropzone entry
/// points bail out on `activeProfile == nil`, the entire drag overlay and the
/// right-click menu on the green button disappeared.
///
/// ## The rule
///
/// 1. **Exact first.** An observed identity that a configured identity equals is
///    that configured identity. This also settles the case where several
///    configured displays share vendor and model: one of them is an exact hit and
///    the others are irrelevant.
/// 2. **Unique-on-both-sides.** Otherwise, a fallback identity is mapped to a
///    configured one when *exactly one* configured fallback and *exactly one*
///    observed fallback carry that vendor + model pair. There is only one
///    candidate and only one claimant, so the answer cannot be wrong for the
///    reason the port index was introduced against.
/// 3. **Otherwise nothing.** Two identical monitors without a serial number are
///    still told apart by the port index alone, and still get confused when their
///    cables are swapped. That limitation is unchanged and deliberately not
///    papered over: guessing would move windows onto the wrong panel.
///
/// ``DisplayIdentity/edid(vendorNumber:modelNumber:serialNumber:)`` and
/// ``DisplayIdentity/builtin`` are never touched. They carry a real serial
/// number (or are unique by construction), so any tolerance there would only
/// ever be wrong.
///
/// `==` and `hash(into:)` of ``DisplayIdentity`` stay exactly as they were: the
/// tolerance lives here, and every lookup that translates observed identities
/// into configured ones goes through this type.
///
/// Deterministic and cheap: two passes over the identities, dictionary lookups
/// afterwards, and ``portDrifts`` sorted by vendor, model and port so that the
/// diagnostics do not depend on enumeration order. Build it **once per display
/// arrangement refresh** and hand it to the lookups.
public struct DisplayIdentityReconciler: Hashable, Sendable {

    /// One display that was recognised although its port index had moved.
    ///
    /// Carried out of the reconciler so the diagnostics can say what happened
    /// instead of silently repairing the match — a silent repair is how the
    /// original assumption survived unmeasured for so long.
    public struct PortDrift: Hashable, Sendable {

        /// The identity as the machine reports it right now.
        public let observed: DisplayIdentity
        /// The identity as the configuration stores it.
        public let configured: DisplayIdentity
        public let observedPortIndex: Int
        public let configuredPortIndex: Int

        /// The one German line the diagnostics print.
        public var sentence: String {
            "konfiguriert als port=\(configuredPortIndex), aktuell port=\(observedPortIndex): erkannt, weil eindeutig"
        }
    }

    /// Observed identity → configured identity, for the tolerated matches only.
    ///
    /// Exact matches are absent on purpose: ``resolve(_:)`` returns the input
    /// unchanged for them, which is the same answer with no table to keep.
    private let mapping: [DisplayIdentity: DisplayIdentity]

    /// Every tolerated match, sorted, for the `displays` and `watch` diagnostics.
    public let portDrifts: [PortDrift]

    /// The reconciler that changes nothing.
    ///
    /// The default for call sites that genuinely have no configuration at hand —
    /// `openzonr displays` without a config file, and tests that state their
    /// identities exactly. It is *not* a shortcut for "I did not want to pass one
    /// in": a lookup against a configuration needs the real thing.
    public static let passthrough = DisplayIdentityReconciler()

    public init() {
        self.mapping = [:]
        self.portDrifts = []
    }

    /// Builds the mapping from the configured identities and the observed ones.
    ///
    /// - Parameters:
    ///   - configured: every identity the configuration names — the display
    ///     descriptors **and** `ignoredDisplays`. Both pools together, because a
    ///     vendor + model pair that appears in each of them is ambiguous and must
    ///     fall back to an exact comparison.
    ///   - observed: the identities the machine reports right now.
    public init(configured: [DisplayIdentity], observed: [DisplayIdentity]) {
        let configuredIdentities = Self.distinct(configured)
        let observedIdentities = Self.distinct(observed)
        let configuredSet = Set(configuredIdentities)

        var configuredByModel: [ModelKey: [DisplayIdentity]] = [:]
        for identity in configuredIdentities {
            guard let key = ModelKey(identity) else { continue }
            configuredByModel[key, default: []].append(identity)
        }

        var observedCountByModel: [ModelKey: Int] = [:]
        for identity in observedIdentities {
            guard let key = ModelKey(identity) else { continue }
            observedCountByModel[key, default: 0] += 1
        }

        var mapping: [DisplayIdentity: DisplayIdentity] = [:]
        var drifts: [PortDrift] = []
        for identity in observedIdentities {
            // Rule 1: an exact hit needs no translation and blocks rule 2.
            guard !configuredSet.contains(identity) else { continue }
            // `.edid` and `.builtin` are exact-only and stop here.
            guard let key = ModelKey(identity), case let .fallback(_, _, _, _, port) = identity else { continue }
            // Rule 2: exactly one candidate, exactly one claimant.
            guard
                let candidates = configuredByModel[key], candidates.count == 1,
                observedCountByModel[key] == 1,
                let target = candidates.first,
                case let .fallback(_, _, _, _, configuredPort) = target
            else { continue }

            mapping[identity] = target
            drifts.append(
                PortDrift(
                    observed: identity,
                    configured: target,
                    observedPortIndex: port,
                    configuredPortIndex: configuredPort
                )
            )
        }

        self.mapping = mapping
        self.portDrifts = drifts.sorted {
            ($0.configured.sortKey, $0.observedPortIndex) < ($1.configured.sortKey, $1.observedPortIndex)
        }
    }

    /// The configured identity this observed one stands for, or the observed one
    /// unchanged when the configuration does not describe it.
    ///
    /// Idempotent: resolving an already-configured identity returns it, so a
    /// value may safely pass through twice.
    public func resolve(_ identity: DisplayIdentity) -> DisplayIdentity {
        mapping[identity] ?? identity
    }

    /// The drift record for an observed identity, when it was matched despite a
    /// different port index.
    public func portDrift(for observed: DisplayIdentity) -> PortDrift? {
        portDrifts.first { $0.observed == observed }
    }

    /// `true` when nothing was tolerated — the ordinary case.
    public var isExactThroughout: Bool { portDrifts.isEmpty }

    // MARK: - Internals

    /// Vendor + model of a fallback identity. `nil` for every other case, which
    /// is what keeps `.edid` and `.builtin` out of the tolerance.
    private struct ModelKey: Hashable {
        let vendorNumber: UInt32
        let modelNumber: UInt32

        init?(_ identity: DisplayIdentity) {
            guard case let .fallback(vendor, model, _, _, _) = identity else { return nil }
            self.vendorNumber = vendor
            self.modelNumber = model
        }
    }

    /// Removes duplicates while keeping file / enumeration order, so a
    /// configuration that names the same identity twice still counts as one
    /// candidate rather than as an ambiguity it never was.
    private static func distinct(_ identities: [DisplayIdentity]) -> [DisplayIdentity] {
        var seen: Set<DisplayIdentity> = []
        return identities.filter { seen.insert($0).inserted }
    }
}

extension DisplayIdentity {

    /// Order for diagnostics. Never used for matching.
    fileprivate var sortKey: String {
        switch self {
        case .builtin:
            return "0"
        case let .edid(vendor, model, serial):
            return "1|\(vendor)|\(model)|\(serial)"
        case let .fallback(vendor, model, _, _, port):
            return "2|\(vendor)|\(model)|\(port)"
        }
    }
}

extension Configuration {

    /// The reconciler for this configuration against what the machine reports.
    ///
    /// Both identity pools go in: the display descriptors and `ignoredDisplays`.
    /// Ignoring has to be as tolerant as matching — the user's own configuration
    /// carries software displays under `ignoredDisplays`, and an ignored display
    /// whose port drifted would otherwise reappear in the fingerprint and break
    /// the profile just as thoroughly as the drift it is meant to hide.
    public func displayReconciler(observing snapshots: [DisplaySnapshot]) -> DisplayIdentityReconciler {
        displayReconciler(observing: snapshots.map(\.identity))
    }

    /// Overload for callers that already hold identities rather than snapshots.
    public func displayReconciler(observing identities: [DisplayIdentity]) -> DisplayIdentityReconciler {
        DisplayIdentityReconciler(
            configured: displays.map(\.identity) + ignoredDisplays,
            observed: identities
        )
    }
}
