import Foundation

/// A rectangle expressed as fractions of a display's *visible* frame.
///
/// OpenZonr never stores zone geometry in pixels or points. Displays differ in
/// size and resolution, the menu bar and Dock change the usable area, and users
/// change scaling. A relative rectangle survives all of that: it is resolved to
/// concrete points only at the moment a window is placed.
///
/// Coordinate space:
/// - origin `(0, 0)` is the **top-left** corner of the visible frame,
/// - `(1, 1)` is the bottom-right corner,
/// - the visible frame excludes the menu bar and the Dock.
///
/// AppKit screen coordinates are bottom-left based; the conversion happens in
/// ``ZoneGeometry``, not in the configuration format, because a top-left origin
/// is what users intuitively draw in a zone editor.
public struct RelativeRect: Codable, Hashable, Sendable {
    /// Horizontal offset of the left edge, `0…1`.
    public var x: Double
    /// Vertical offset of the top edge, `0…1`.
    public var y: Double
    /// Width as a fraction of the visible frame width, `0…1`.
    public var width: Double
    /// Height as a fraction of the visible frame height, `0…1`.
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// The complete visible frame of a display.
    public static let full = RelativeRect(x: 0, y: 0, width: 1, height: 1)
}

/// An absolute size in points, used for window *filters* — never for zones.
///
/// Filters such as "ignore anything smaller than 400×300" are naturally
/// expressed in absolute terms, because they describe popups and palettes whose
/// size does not scale with the display.
public struct WindowSize: Codable, Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}
