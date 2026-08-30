import Foundation

/// The one place where zone geometry becomes screen geometry.
///
/// Both directions live here on purpose. Automatic placement asks "where does
/// this zone sit on that display", dropzones ask the inverse, "which zone is
/// under this pointer" — and if those two answers were computed by separate
/// code, a window could highlight one zone and land in another. That class of
/// bug is invisible in tests that only exercise one direction, so the two are
/// kept adjacent and share the rounding.
public enum ZoneGeometry {

    /// Converts a zone rectangle from the configuration model's top-left origin
    /// into AppKit's bottom-left coordinate space.
    ///
    /// Shared edges are rounded before the size is derived, so adjacent zones
    /// meet exactly instead of gaining overlaps or one-point gaps from
    /// independent rounding.
    public static func absoluteFrame(
        of rect: RelativeRect,
        in frame: VisibleFrame
    ) -> WindowFrame {
        let left = frame.x + rect.x * frame.width
        let right = frame.x + (rect.x + rect.width) * frame.width
        let top = frame.y + frame.height - rect.y * frame.height
        let bottom = frame.y + frame.height - (rect.y + rect.height) * frame.height

        let roundedLeft = left.rounded()
        let roundedRight = right.rounded()
        let roundedTop = top.rounded()
        let roundedBottom = bottom.rounded()

        return WindowFrame(
            x: roundedLeft,
            y: roundedBottom,
            width: roundedRight - roundedLeft,
            height: roundedTop - roundedBottom
        )
    }

    /// Whether `point` lies inside `frame`.
    ///
    /// Half-open on the far edges: a point exactly on the right or top edge
    /// belongs to the neighbour, not to both. Without that, the shared edge of
    /// two adjacent zones would be ambiguous, and which one won would depend on
    /// the order they happen to sit in the layout.
    public static func contains(_ frame: WindowFrame, _ point: ScreenPoint) -> Bool {
        point.x >= frame.x
            && point.x < frame.x + frame.width
            && point.y >= frame.y
            && point.y < frame.y + frame.height
    }

    /// Whether `point` lies inside `frame` with at least `margin` to every edge.
    ///
    /// Used for hysteresis while dragging: brushing a boundary is not enough to
    /// change the highlighted zone, the pointer has to commit. A margin wider
    /// than half the frame would make a zone unreachable, so it is clamped.
    public static func contains(
        _ frame: WindowFrame,
        _ point: ScreenPoint,
        margin: Double
    ) -> Bool {
        let horizontal = min(margin, frame.width / 2)
        let vertical = min(margin, frame.height / 2)
        let inset = WindowFrame(
            x: frame.x + horizontal,
            y: frame.y + vertical,
            width: frame.width - 2 * horizontal,
            height: frame.height - 2 * vertical
        )
        return contains(inset, point)
    }

    /// Area in square points. Used to order overlapping zones from most to
    /// least specific.
    public static func area(_ frame: WindowFrame) -> Double {
        max(0, frame.width) * max(0, frame.height)
    }
}
