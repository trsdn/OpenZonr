import Foundation

/// A zone the pointer is currently over, resolved to concrete screen geometry.
///
/// Carries the identifiers as well as the frame, because a drop has two
/// consumers: the placement, which needs the frame, and the offer to remember
/// the choice as a rule, which needs to name the zone.
public struct DropCandidate: Hashable, Sendable, Identifiable {
    public var display: DisplayAlias
    public var layout: LayoutID
    public var zone: ZoneID
    /// Human readable zone name, for the overlay label.
    public var name: String
    /// Absolute frame in AppKit screen coordinates.
    public var frame: WindowFrame

    public var id: String { "\(display.rawValue)|\(layout.rawValue)|\(zone.rawValue)" }

    public init(
        display: DisplayAlias,
        layout: LayoutID,
        zone: ZoneID,
        name: String,
        frame: WindowFrame
    ) {
        self.display = display
        self.layout = layout
        self.zone = zone
        self.name = name
        self.frame = frame
    }
}

/// Finds the zones under a pointer.
///
/// The inverse of automatic placement, and deliberately built on the same
/// geometry (see ``ZoneGeometry``): a window must land exactly where the
/// overlay said it would.
///
/// Overlapping zones are the interesting case. A layout may legitimately stack
/// a large "focus" zone on top of two halves, so a pointer is often inside
/// several zones at once. Returning only the smallest would make the large one
/// unreachable by mouse; returning only the largest would do the same to the
/// small ones. The resolver therefore returns *all* of them, most specific
/// first, and leaves the choice to ``DropZoneSession``, which lets the user
/// cycle. Picking one here would have quietly amputated part of the layout.
public struct DropZoneResolver: Sendable {

    public init() {}

    /// The display whose visible frame contains `point`, if any.
    ///
    /// Displays do not overlap, so the first hit is the only hit. A pointer
    /// between two displays — possible when their frames are not flush — hits
    /// none, which is reported honestly rather than snapped to the nearest.
    public func display(
        at point: ScreenPoint,
        visibleFrames: VisibleFrames
    ) -> DisplayAlias? {
        visibleFrames.aliases
            .sorted { $0.rawValue < $1.rawValue }
            .first { alias in
                guard let frame = visibleFrames[alias] else { return false }
                return ZoneGeometry.contains(
                    WindowFrame(x: frame.x, y: frame.y, width: frame.width, height: frame.height),
                    point
                )
            }
    }

    /// Every zone of the active layout that contains `point`, most specific
    /// (smallest area) first.
    ///
    /// Ties break on the zone identifier, so the order is stable across runs —
    /// a cycling order that reshuffled between drags would be worse than no
    /// cycling at all.
    public func candidates(
        at point: ScreenPoint,
        profile: Profile,
        configuration: Configuration,
        visibleFrames: VisibleFrames
    ) -> [DropCandidate] {
        guard let alias = display(at: point, visibleFrames: visibleFrames),
              let visibleFrame = visibleFrames[alias],
              let descriptor = configuration.displays.first(where: { $0.alias == alias })
        else { return [] }

        let layoutID = profile.layouts[alias] ?? descriptor.defaultLayoutID
        guard let layout = descriptor.layouts.first(where: { $0.id == layoutID }) else {
            return []
        }

        return layout.zones
            .map { zone in
                DropCandidate(
                    display: alias,
                    layout: layout.id,
                    zone: zone.id,
                    name: zone.name,
                    frame: ZoneGeometry.absoluteFrame(of: zone.frame, in: visibleFrame)
                )
            }
            .filter { ZoneGeometry.contains($0.frame, point) }
            .sorted { left, right in
                let leftArea = ZoneGeometry.area(left.frame)
                let rightArea = ZoneGeometry.area(right.frame)
                if leftArea != rightArea { return leftArea < rightArea }
                return left.zone.rawValue < right.zone.rawValue
            }
    }
}
