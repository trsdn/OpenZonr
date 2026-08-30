import Foundation

/// A point in AppKit's global screen space.
///
/// Same convention as ``VisibleFrame``: origin bottom-left, `y` grows upwards,
/// and displays left of or below the main one carry negative coordinates. This
/// is what `NSEvent.mouseLocation` reports, so the pointer needs no conversion
/// on its way in.
public struct ScreenPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}
