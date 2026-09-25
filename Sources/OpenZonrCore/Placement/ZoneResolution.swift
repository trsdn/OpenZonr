import Foundation

/// Why a role could not be turned into a concrete frame.
///
/// Every case here is a configuration problem that ``ConfigurationValidator``
/// would have caught, or a display that is described in the configuration but
/// not currently attached. The resolver still has to handle them: a
/// configuration can be edited by hand between validation and use, and a
/// resolver that traps on bad input would take the whole app down over a typo.
public enum ZoneResolutionFailure: Error, Hashable, Sendable, CustomStringConvertible {

    /// The binding points at a display the configuration does not describe.
    case unknownDisplay(DisplayAlias)

    /// The profile selects a layout the display does not own.
    case unknownLayout(LayoutID, display: DisplayAlias)

    /// The layout in use does not contain the bound zone.
    case unknownZone(ZoneID, layout: LayoutID, display: DisplayAlias)

    /// The display is configured but currently has no visible frame — it is not
    /// attached, or the caller did not supply it.
    case missingVisibleFrame(DisplayAlias)

    /// The ``ZoneShare`` is not usable: fewer than two slots, or an index
    /// outside the slot range.
    case invalidShare(ZoneShare)

    public var description: String {
        switch self {
        case let .unknownDisplay(alias):
            return L.string("zoneResolutionFailure.unknownDisplay", "Unknown display %@.", alias.rawValue)
        case let .unknownLayout(layout, display):
            return L.string(
                "zoneResolutionFailure.unknownLayout",
                "Display %@ has no layout %@.",
                display.rawValue, layout.rawValue
            )
        case let .unknownZone(zone, layout, display):
            return L.string(
                "zoneResolutionFailure.unknownZone",
                "Layout %@ on display %@ has no zone %@.",
                layout.rawValue, display.rawValue, zone.rawValue
            )
        case let .missingVisibleFrame(alias):
            return L.string(
                "zoneResolutionFailure.missingVisibleFrame",
                "Display %@ has no visible frame.",
                alias.rawValue
            )
        case let .invalidShare(share):
            return L.string(
                "zoneResolutionFailure.invalidShare",
                "Invalid zone share: %lld slots, index %lld.",
                share.slots, share.slotIndex
            )
        }
    }
}
