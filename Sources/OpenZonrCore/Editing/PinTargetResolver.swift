import Foundation

/// Turns "the window is *there*" into "the window belongs into that zone".
///
/// This is the half of the 90 % case that has to do geometry, and it is kept
/// pure so it can be tested without a screen: the caller supplies the window
/// frame and the visible frames of the attached displays, both of which the
/// macOS layer already produces for the placement path.
public enum PinTargetResolver {

    /// The display and zone a window currently sits in.
    ///
    /// - Parameters:
    ///   - windowFrame: the window in **AppKit** coordinates, origin bottom-left
    ///     — the same space ``VisibleFrame`` uses and the space
    ///     ``ScreenArrangement/flipVertically(_:)`` converts Accessibility
    ///     frames into.
    ///   - visibleFrames: the visible frames of the configured displays.
    /// - Returns: the target, or `nil` when the window overlaps no configured
    ///   display or the resolved layout has no zones.
    public static func resolve(
        windowFrame: WindowFrame,
        configuration: Configuration,
        profile: ProfileID,
        visibleFrames: VisibleFrames
    ) -> QuickPin.Target? {
        guard let alias = display(containing: windowFrame, in: configuration, visibleFrames: visibleFrames),
              let visibleFrame = visibleFrames[alias],
              let layout = configuration.layout(forDisplay: alias, inProfile: profile),
              let relative = relativeRect(of: windowFrame, in: visibleFrame),
              let zone = zone(bestMatching: relative, in: layout)
        else { return nil }

        return QuickPin.Target(display: alias, zone: zone)
    }

    /// The configured display that shows most of `windowFrame`.
    ///
    /// Largest overlap, not the origin: a window straddling two screens belongs
    /// to the one it is mostly on, and one dragged half off the edge still gets
    /// an answer. Same rule as ``ScreenArrangement/display(containingAccessibilityFrame:)``,
    /// deliberately, so the pin lands on the display the placement path would
    /// also have picked.
    public static func display(
        containing windowFrame: WindowFrame,
        in configuration: Configuration,
        visibleFrames: VisibleFrames
    ) -> DisplayAlias? {
        var best: (alias: DisplayAlias, area: Double)?
        for descriptor in configuration.displays {
            guard let frame = visibleFrames[descriptor.alias] else { continue }
            let area = windowFrame.intersectionArea(
                with: WindowFrame(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
            )
            guard area > 0 else { continue }
            if best == nil || area > best!.area {
                best = (descriptor.alias, area)
            }
        }
        return best?.alias
    }

    /// Expresses an AppKit window frame as a fraction of a visible frame, in the
    /// top-left space ``RelativeRect`` uses.
    ///
    /// The exact inverse of what ``DefaultZoneResolver`` does on the way out.
    /// Both directions of that conversion now exist in the project, so the round
    /// trip can be — and is — tested against each other rather than against a
    /// hand-computed number that could be wrong in the same way twice.
    public static func relativeRect(of windowFrame: WindowFrame, in visibleFrame: VisibleFrame) -> RelativeRect? {
        guard visibleFrame.width > 0, visibleFrame.height > 0 else { return nil }
        let top = visibleFrame.maxY - (windowFrame.y + windowFrame.height)
        return RelativeRect(
            x: (windowFrame.x - visibleFrame.x) / visibleFrame.width,
            y: top / visibleFrame.height,
            width: windowFrame.width / visibleFrame.width,
            height: windowFrame.height / visibleFrame.height
        )
    }

    /// The zone of `layout` that fits `rect` best.
    ///
    /// Scored by intersection over union rather than by raw overlap. Overlap
    /// alone would always favour the largest zone: a full-screen zone contains
    /// every window completely and would win against the narrow column the
    /// window actually fills. Ties — two identical zones — are broken by
    /// identifier so the answer never depends on array order.
    public static func zone(bestMatching rect: RelativeRect, in layout: Layout) -> ZoneID? {
        var best: (id: ZoneID, score: Double)?
        for zone in layout.zones {
            let intersection = rect.intersectionArea(with: zone.frame)
            let union = rect.area + zone.frame.area - intersection
            guard union > 0 else { continue }
            let score = intersection / union
            guard score > 0 else { continue }
            if best == nil || score > best!.score || (score == best!.score && zone.id < best!.id) {
                best = (zone.id, score)
            }
        }
        return best?.id
    }
}

extension RelativeRect {

    /// Area covered, in fractions of the visible frame.
    public var area: Double { max(0, width) * max(0, height) }

    /// Area shared with another rectangle, `0` when they do not overlap.
    public func intersectionArea(with other: RelativeRect) -> Double {
        let width = min(x + self.width, other.x + other.width) - max(x, other.x)
        let height = min(y + self.height, other.y + other.height) - max(y, other.y)
        guard width > 0, height > 0 else { return 0 }
        return width * height
    }

    /// The rectangle clamped into the unit square, keeping at least `minimum` of
    /// each dimension.
    ///
    /// The zone editor calls this when a drag ends. During the drag nothing is
    /// clamped, so a zone pushed past the edge visibly snaps back instead of
    /// quietly deforming under the pointer.
    public func clampedToUnitSquare(minimum: Double = 0.05) -> RelativeRect {
        let width = min(max(self.width, minimum), 1)
        let height = min(max(self.height, minimum), 1)
        return RelativeRect(
            x: min(max(x, 0), 1 - width),
            y: min(max(y, 0), 1 - height),
            width: width,
            height: height
        )
    }

    /// The rectangle with every edge snapped to a grid of `divisions` steps.
    ///
    /// Zones that are meant to be halves have to *be* halves; a zone dragged to
    /// 0.4993 looks right and produces a one-point gap on a wide display. Twelve
    /// divisions is the default because it covers halves, thirds and quarters,
    /// which is what layouts are actually made of.
    public func snapped(toDivisions divisions: Int = 12) -> RelativeRect {
        guard divisions > 0 else { return self }
        let step = 1.0 / Double(divisions)
        func snap(_ value: Double) -> Double { (value / step).rounded() * step }

        let left = snap(x)
        let top = snap(y)
        let right = snap(x + width)
        let bottom = snap(y + height)
        return RelativeRect(
            x: left,
            y: top,
            width: max(right - left, step),
            height: max(bottom - top, step)
        )
    }
}
