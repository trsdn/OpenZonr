import Foundation

/// One display as observed at runtime.
///
/// The type sits between the window server and the pure resolution logic: the
/// macOS layer fills it in from `NSScreen` and CoreGraphics, everything else
/// works on the values. That is what allows the coordinate conversion — the
/// single most error-prone piece of this project — to be tested without a
/// screen attached.
///
/// All frames here use **AppKit coordinates**: origin bottom-left of the main
/// display, `y` growing upwards. The conversion into the top-left space that
/// the Accessibility API uses happens in ``ScreenArrangement`` and nowhere else.
public struct DisplaySnapshot: Hashable, Sendable {

    /// Stable identity derived from EDID data, or ``DisplayIdentity/builtin``.
    public var identity: DisplayIdentity
    /// Name macOS shows for this display, e.g. "C49RG9x".
    public var localizedName: String
    /// `CGDirectDisplayID`. Session-scoped, useful for logs, never for identity.
    public var displayID: UInt32
    /// Native pixel width of the current mode.
    public var pixelWidth: Int
    /// Native pixel height of the current mode.
    public var pixelHeight: Int
    /// `NSScreen.backingScaleFactor`.
    public var backingScaleFactor: Double
    /// Full frame in AppKit coordinates.
    public var frame: WindowFrame
    /// Usable frame in AppKit coordinates, menu bar and Dock removed.
    ///
    /// Read per display, never derived globally. Measured on a four-display
    /// desk: every display carries its own menu bar, yet only the main display
    /// reports a reduced visible frame (1344 of 1440 points). The others report
    /// `visibleFrame == frame`. A global menu-bar subtraction would be wrong on
    /// three displays out of four.
    public var visibleFrame: WindowFrame
    /// Physical panel size in millimetres, as reported by `CGDisplayScreenSize`.
    public var physicalSizeMillimeters: WindowSize
    /// Index of the port the display is attached to, `CGDisplayUnitNumber`.
    public var portIndex: Int
    /// `true` when this display is the coordinate origin of the arrangement.
    public var isPrimary: Bool
    /// `true` when the display looks like a software surface rather than a panel.
    ///
    /// A hint for the user interface, never an automatic exclusion — see
    /// ``Configuration/ignoredDisplays``.
    public var isLikelyVirtual: Bool

    public init(
        identity: DisplayIdentity,
        localizedName: String,
        displayID: UInt32,
        pixelWidth: Int,
        pixelHeight: Int,
        backingScaleFactor: Double,
        frame: WindowFrame,
        visibleFrame: WindowFrame,
        physicalSizeMillimeters: WindowSize = WindowSize(width: 0, height: 0),
        portIndex: Int = 0,
        isPrimary: Bool = false,
        isLikelyVirtual: Bool = false
    ) {
        self.identity = identity
        self.localizedName = localizedName
        self.displayID = displayID
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.backingScaleFactor = backingScaleFactor
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.physicalSizeMillimeters = physicalSizeMillimeters
        self.portIndex = portIndex
        self.isPrimary = isPrimary
        self.isLikelyVirtual = isLikelyVirtual
    }

    /// `true` when the identity had to fall back because the panel reports no
    /// serial number.
    ///
    /// Not an edge case. On the author's desk the *main* monitor — a Samsung
    /// C49RG9x — reports serial number 0, so the fallback is the primary path.
    /// Note also that both attached Samsungs share vendor number 19501 and are
    /// told apart solely by their model number; a fallback built on vendor plus
    /// resolution would collide.
    public var usesSerialFallback: Bool {
        if case .fallback = identity { return true }
        return false
    }
}

extension SetupFingerprint {

    /// Builds a fingerprint from observed displays, dropping the ignored ones.
    ///
    /// The filter is the whole point of this initialiser. Without it, starting
    /// OBS adds a display, the fingerprint changes, and the active profile
    /// jumps although nothing on the desk moved.
    public init(snapshots: [DisplaySnapshot], ignoring ignored: [DisplayIdentity] = []) {
        let ignoredSet = Set(ignored)
        self.init(displays: Set(snapshots.map(\.identity).filter { !ignoredSet.contains($0) }))
    }
}

/// The set of attached displays, plus the one conversion everything depends on.
///
/// ## The coordinate trap
///
/// Two coordinate systems meet here, and they disagree about which way `y`
/// grows:
///
/// - **AppKit** (`NSScreen.frame`, `visibleFrame`, and therefore every frame
///   produced by ``ZoneResolver``): origin at the bottom-left of the main
///   display, `y` grows upwards.
/// - **Accessibility** (`kAXPositionAttribute`, `CGDisplayBounds`,
///   `CGWindowListCopyWindowInfo`): origin at the top-left of the main display,
///   `y` grows downwards.
///
/// The conversion is `y' = primaryTopY - (y + height)` and it is its own
/// inverse. It only looks harmless while all displays are the same height.
/// Measured on a real arrangement — a 5120×1440 ultrawide as the main display
/// with 1920×1080 panels placed *above* it — AppKit reports the secondary
/// displays at `y = 1440` while the window server reports them at `y = -1080`.
/// Getting this wrong does not produce a slightly misplaced window; it produces
/// a window on the wrong screen.
public struct ScreenArrangement: Sendable {

    /// All observed displays.
    public let snapshots: [DisplaySnapshot]

    /// Top edge of the main display in AppKit coordinates.
    ///
    /// The pivot of the conversion. It is the main display's height, because the
    /// main display sits at the origin — but reading it from the snapshot rather
    /// than assuming it keeps the code honest if that ever stops being true.
    public let primaryTopY: Double

    public init(snapshots: [DisplaySnapshot]) {
        self.snapshots = snapshots
        let primary = snapshots.first(where: \.isPrimary) ?? snapshots.first
        self.primaryTopY = primary.map { $0.frame.y + $0.frame.height } ?? 0
    }

    /// Mirrors a frame between AppKit and Accessibility coordinates.
    ///
    /// The same function serves both directions; applying it twice yields the
    /// original frame.
    public static func flipVertically(_ frame: WindowFrame, primaryTopY: Double) -> WindowFrame {
        WindowFrame(
            x: frame.x,
            y: primaryTopY - (frame.y + frame.height),
            width: frame.width,
            height: frame.height
        )
    }

    /// Mirrors a frame using this arrangement's main display as the pivot.
    public func flipVertically(_ frame: WindowFrame) -> WindowFrame {
        Self.flipVertically(frame, primaryTopY: primaryTopY)
    }

    /// The visible frames of all displays the configuration describes, keyed by
    /// alias — the input ``ZoneResolver`` expects.
    ///
    /// Displays that are attached but not described simply do not appear. The
    /// profile resolver has already decided whether that is acceptable.
    public func visibleFrames(for descriptors: [DisplayDescriptor]) -> VisibleFrames {
        var frames = VisibleFrames()
        for descriptor in descriptors {
            guard let snapshot = snapshots.first(where: { $0.identity == descriptor.identity }) else { continue }
            frames[descriptor.alias] = VisibleFrame(
                x: snapshot.visibleFrame.x,
                y: snapshot.visibleFrame.y,
                width: snapshot.visibleFrame.width,
                height: snapshot.visibleFrame.height
            )
        }
        return frames
    }

    /// The display a window sits on, given a frame in Accessibility coordinates.
    ///
    /// Decided by largest overlap rather than by the window's origin: a window
    /// straddling two displays belongs to the one showing most of it, and a
    /// window whose origin lies in a gap between displays still gets an answer.
    public func display(containingAccessibilityFrame frame: WindowFrame) -> DisplaySnapshot? {
        var best: (snapshot: DisplaySnapshot, area: Double)?
        for snapshot in snapshots {
            let bounds = flipVertically(snapshot.frame)
            let area = bounds.intersectionArea(with: frame)
            guard area > 0 else { continue }
            if best == nil || area > best!.area {
                best = (snapshot, area)
            }
        }
        return best?.snapshot
    }
}

extension WindowFrame {

    /// Area shared by two frames, `0` when they do not overlap.
    public func intersectionArea(with other: WindowFrame) -> Double {
        let width = min(x + self.width, other.x + other.width) - max(x, other.x)
        let height = min(y + self.height, other.y + other.height) - max(y, other.y)
        guard width > 0, height > 0 else { return 0 }
        return width * height
    }

    /// Largest deviation of any edge from `other`, in points.
    ///
    /// This is what the retry loop compares against ``RetryPolicy/tolerance``.
    /// A maximum rather than a sum, so a window that is off by 30 points in one
    /// dimension cannot hide behind three dimensions that are exact.
    public func maximumDeviation(from other: WindowFrame) -> Double {
        max(
            abs(x - other.x),
            abs(y - other.y),
            abs(width - other.width),
            abs(height - other.height)
        )
    }
}
