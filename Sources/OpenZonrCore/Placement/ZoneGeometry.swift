import Foundation

/// The one conversion from a zone rectangle to points on a screen.
///
/// It used to be a private method of ``DefaultZoneResolver``, which was fine
/// while placement had a single entry point. It no longer does: dragging a
/// window into a zone resolves the same zone from a pointer position instead of
/// from a role. Two copies of this arithmetic would drift — and the way they
/// would drift is the worst kind, a window landing one point off in one path and
/// not the other, with nothing to see in a log.
///
/// So both paths call this, and the edge-rounding rule that makes adjacent zones
/// meet exactly is stated exactly once.
public enum ZoneGeometry {

    /// Converts a zone rectangle from the configuration's top-left space into an
    /// absolute frame in AppKit coordinates (origin bottom-left).
    public static func absoluteFrame(for rect: RelativeRect, in frame: VisibleFrame) -> WindowFrame {
        let left = frame.x + rect.x * frame.width
        let right = frame.x + (rect.x + rect.width) * frame.width
        let top = frame.y + frame.height - rect.y * frame.height
        let bottom = frame.y + frame.height - (rect.y + rect.height) * frame.height

        let roundedLeft = left.rounded()
        let roundedRight = right.rounded()
        let roundedTop = top.rounded()
        let roundedBottom = bottom.rounded()

        // Round shared edges before deriving size so adjacent zones meet exactly
        // instead of gaining overlaps or one-point gaps from independent rounding.
        return WindowFrame(
            x: roundedLeft,
            y: roundedBottom,
            width: roundedRight - roundedLeft,
            height: roundedTop - roundedBottom
        )
    }

    /// The frame a window is placed at for a zone: the zone shrunk by the
    /// layout's margin on every side, then converted like any zone.
    ///
    /// The **only** place the margin is applied. ``DefaultZoneResolver`` (rules)
    /// and ``Dropzone/placement`` (drag/drop and zoom menu) both call it, so the
    /// three placement routes cannot disagree. Hit testing deliberately does not
    /// call it: it works against ``Dropzone/activationFrame``, not
    /// ``Dropzone/frame``, and with a declared activation area that surface is
    /// meant to have gaps — margin plays no part in that either way.
    public static func placementFrame(
        for rect: RelativeRect,
        margin: Double,
        in frame: VisibleFrame
    ) -> WindowFrame {
        let placed = margin > 0 ? rect.inset(by: margin) : rect
        return absoluteFrame(for: placed, in: frame)
    }
}

/// A point in global screen coordinates.
///
/// Which of the two coordinate systems it is in is not part of the type — the
/// same trap ``WindowFrame`` carries — so every function taking one says so in
/// its documentation. ``ScreenArrangement/flipVertically(_:)`` has a point
/// overload for the conversion.
public struct ScreenPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

extension WindowFrame {

    /// `true` when `point` lies inside the frame.
    ///
    /// Left and bottom edges belong to the frame, right and top do not. Without
    /// that asymmetry the shared edge of two adjacent zones belongs to both, and
    /// which one a drop lands in would depend on array order.
    public func contains(_ point: ScreenPoint) -> Bool {
        point.x >= x && point.x < x + width && point.y >= y && point.y < y + height
    }

    /// Area of the frame, `0` when either dimension is negative.
    public var area: Double { max(0, width) * max(0, height) }
}

extension VisibleFrame {
    /// Whether the point lies on this display's usable area.
    ///
    /// Same edge rule as ``WindowFrame/contains(_:)``: left and bottom
    /// inclusive, right and top exclusive, so two displays that touch never both
    /// claim the same point.
    public func contains(_ point: ScreenPoint) -> Bool {
        point.x >= x && point.x < maxX && point.y >= y && point.y < maxY
    }
}
