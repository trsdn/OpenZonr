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
            return "Unbekanntes Display \(alias)."
        case let .unknownLayout(layout, display):
            return "Display \(display) kennt kein Layout \(layout)."
        case let .unknownZone(zone, layout, display):
            return "Layout \(layout) auf Display \(display) enthält keine Zone \(zone)."
        case let .missingVisibleFrame(alias):
            return "Für Display \(alias) liegt kein sichtbarer Frame vor."
        case let .invalidShare(share):
            return "Ungültige Zonenteilung: \(share.slots) Slots, Index \(share.slotIndex)."
        }
    }
}
