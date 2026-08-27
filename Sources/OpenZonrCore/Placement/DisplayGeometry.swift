import Foundation

/// The usable area of one display, in AppKit screen coordinates.
///
/// Coordinate convention, stated once so it never has to be guessed again:
///
/// - the origin is **bottom-left**, `y` grows upwards — this is what
///   `NSScreen.visibleFrame` reports,
/// - the frame excludes the menu bar and the Dock,
/// - a display placed to the left of the main display has a negative `x`, and
///   one placed below it a negative `y`. Both are ordinary values here, not
///   special cases.
///
/// ``RelativeRect`` uses a top-left origin because that is how people draw
/// zones. The conversion between the two happens in the zone resolver and
/// nowhere else, which is why this type is explicit about which side of the
/// conversion it is on.
///
/// Where the frame comes from is not this layer's business: it is handed in.
/// That keeps the whole resolution path testable without a window server.
public struct VisibleFrame: Hashable, Sendable {
    /// Left edge in global screen points; may be negative.
    public var x: Double
    /// Bottom edge in global screen points; may be negative.
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    /// Top edge in AppKit coordinates.
    public var maxY: Double { y + height }
    /// Right edge in AppKit coordinates.
    public var maxX: Double { x + width }
}

/// The visible frames of all currently attached displays, keyed by alias.
///
/// A dedicated type rather than a bare dictionary so the meaning of the key —
/// the configuration alias, not a `CGDirectDisplayID` — is visible at every
/// call site.
public struct VisibleFrames: Hashable, Sendable, ExpressibleByDictionaryLiteral {

    private var frames: [DisplayAlias: VisibleFrame]

    public init(_ frames: [DisplayAlias: VisibleFrame] = [:]) {
        self.frames = frames
    }

    public init(dictionaryLiteral elements: (DisplayAlias, VisibleFrame)...) {
        self.frames = Dictionary(uniqueKeysWithValues: elements)
    }

    public subscript(alias: DisplayAlias) -> VisibleFrame? {
        get { frames[alias] }
        set { frames[alias] = newValue }
    }

    /// Aliases of all displays that have a frame.
    public var aliases: Set<DisplayAlias> { Set(frames.keys) }

    public var isEmpty: Bool { frames.isEmpty }
}
