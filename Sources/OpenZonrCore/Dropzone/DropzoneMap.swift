import Foundation

/// One zone of the active profile, as a place a window can be dropped into.
///
/// Everything the overlay needs to draw it and everything the placement needs to
/// use it, in one value: the drag path never looks anything up a second time
/// while the mouse is moving.
public struct Dropzone: Hashable, Sendable, Identifiable {

    public var display: DisplayAlias
    public var zone: ZoneID
    /// Label shown in the overlay, e.g. "rechts oben".
    public var name: String
    /// The zone as it stands in the layout, for diagnostics and tests.
    public var relativeFrame: RelativeRect
    /// The zone in absolute **AppKit** coordinates, origin bottom-left.
    public var frame: WindowFrame
    /// The usable area of the display this zone belongs to.
    ///
    /// Carried along so that "which display is the pointer over" never depends
    /// on the pointer being inside a zone. Zones need not cover their screen —
    /// a layout may leave gaps, and the menu bar is outside every zone — and an
    /// overlay that vanished whenever the pointer crossed a gap would flicker
    /// through every drag.
    public var visibleFrame: VisibleFrame

    public init(
        display: DisplayAlias,
        zone: ZoneID,
        name: String,
        relativeFrame: RelativeRect,
        frame: WindowFrame,
        visibleFrame: VisibleFrame
    ) {
        self.display = display
        self.zone = zone
        self.name = name
        self.relativeFrame = relativeFrame
        self.frame = frame
        self.visibleFrame = visibleFrame
    }

    public var id: String { "\(display)/\(zone)" }

    /// The zone as a placement target.
    ///
    /// Deliberately the same type the rule path produces, so that a dropped
    /// window and an automatically placed one go through
    /// ``RetryingWindowPlacer`` in exactly the same way. `usedFallback` is
    /// `false` because nothing fell back: the user pointed at this zone.
    public var placement: ResolvedPlacement {
        ResolvedPlacement(frame: frame, display: display, zone: zone, usedFallback: false)
    }
}

/// The zones of the active profile, and which one a pointer is over.
///
/// Pure on purpose. Everything that decides *where* a dragged window will land
/// is computable from a point, a configuration and the visible frames — none of
/// which needs an event, a screen or the Accessibility permission. That is what
/// makes the interesting half of this feature testable at all: observing a drag
/// requires a grant that only the user can give by hand.
public enum DropzoneMap {

    /// Every zone the active profile shows, across all configured displays.
    ///
    /// Order is the configuration's: displays in file order, zones in layout
    /// order. The overlay draws in this order and the hit test breaks ties with
    /// it, so a layout that is ambiguous is at least consistently ambiguous.
    ///
    /// Displays without a visible frame are skipped — they are described but not
    /// attached, and a zone on a monitor that is not there cannot be dropped
    /// into.
    public static func zones(
        in configuration: Configuration,
        profile: ProfileID,
        visibleFrames: VisibleFrames
    ) -> [Dropzone] {
        var result: [Dropzone] = []
        for descriptor in configuration.displays {
            guard let visibleFrame = visibleFrames[descriptor.alias],
                  let layout = configuration.layout(forDisplay: descriptor.alias, inProfile: profile)
            else { continue }

            for zone in layout.zones {
                result.append(
                    Dropzone(
                        display: descriptor.alias,
                        zone: zone.id,
                        name: zone.name,
                        relativeFrame: zone.frame,
                        frame: ZoneGeometry.absoluteFrame(for: zone.frame, in: visibleFrame),
                        visibleFrame: visibleFrame
                    )
                )
            }
        }
        return result
    }

    /// The zone under `point`, or `nil` when the pointer is over none.
    ///
    /// - Parameter point: the pointer in **AppKit** coordinates, origin
    ///   bottom-left, the same space the zone frames are in.
    ///
    /// Zones may overlap — a large focus zone stacked on two halves is an
    /// explicitly supported layout — so "contains the point" is not enough of an
    /// answer. The **smallest** containing zone wins: the focus zone contains
    /// every point the halves contain, and if it won, the halves would be
    /// unreachable by mouse and the feature would be broken for exactly the
    /// layouts the concept encourages.
    ///
    /// Equal areas are decided by display alias and then zone identifier, never
    /// by array order, so the same pointer always produces the same answer.
    public static func zone(at point: ScreenPoint, in zones: [Dropzone]) -> Dropzone? {
        var best: Dropzone?
        for candidate in zones where candidate.frame.contains(point) {
            guard let current = best else {
                best = candidate
                continue
            }
            if candidate.frame.area < current.frame.area {
                best = candidate
            } else if candidate.frame.area == current.frame.area,
                      isOrderedBefore(candidate, current) {
                best = candidate
            }
        }
        return best
    }

    /// The zones that lie on the display under `point`.
    ///
    /// What the overlay shows: the zones of the screen the pointer is on, not of
    /// every screen. Lighting up four monitors because a window is being nudged
    /// on one of them is noise, and on the author's desk it is a lot of noise.
    public static func zones(onDisplayUnder point: ScreenPoint, in zones: [Dropzone]) -> [Dropzone] {
        // By the display's own area, not by which zone was hit: a pointer in a
        // gap between zones, or over the menu bar, is still on that display and
        // the zones must stay on screen.
        if let display = zones.first(where: { $0.visibleFrame.contains(point) })?.display {
            return zones.filter { $0.display == display }
        }
        guard let hit = zone(at: point, in: zones) else { return [] }
        return zones.filter { $0.display == hit.display }
    }

    private static func isOrderedBefore(_ lhs: Dropzone, _ rhs: Dropzone) -> Bool {
        lhs.display == rhs.display ? lhs.zone < rhs.zone : lhs.display < rhs.display
    }
}
