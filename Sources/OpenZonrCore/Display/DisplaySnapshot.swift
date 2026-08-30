import Foundation

/// What OpenZonr knows about a display that is *currently attached*.
///
/// This is the runtime counterpart of ``DisplayDescriptor``: the descriptor is
/// what the configuration file declares, the snapshot is what the system
/// reports right now. Keeping the two apart is what allows the whole placement
/// logic to be tested without a window server — a snapshot is a plain value.
///
/// All rectangles are in **AppKit global coordinates**: origin bottom-left of
/// the primary display, `y` growing upwards. The conversion into the
/// Accessibility coordinate space happens in ``DisplayGeometry``, in exactly one
/// place, because doing it ad hoc is the classic source of "window lands on the
/// wrong monitor" bugs in multi-display setups.
public struct DisplaySnapshot: Hashable, Sendable {

    /// Stable hardware identity, derived from EDID data or `CGDisplayIsBuiltin`.
    public var identity: DisplayIdentity

    /// Name as reported by the system, e.g. "Dell U2723QE".
    public var localizedName: String

    /// `CGDirectDisplayID` of this session. Deliberately *not* part of the
    /// identity — it is only kept so the CLI can print it for diagnostics.
    public var displayID: UInt32

    /// Native pixel width of the panel.
    public var pixelWidth: Int

    /// Native pixel height of the panel.
    public var pixelHeight: Int

    /// Backing scale factor, `2.0` on Retina panels.
    public var backingScaleFactor: Double

    /// Full frame in AppKit global coordinates, including menu bar and Dock.
    public var frame: WindowFrame

    /// Usable frame in AppKit global coordinates, menu bar and Dock excluded.
    public var visibleFrame: WindowFrame

    /// `true` when the monitor reported a serial number of `0` and the weaker
    /// ``DisplayIdentity/fallback(vendorNumber:modelNumber:pixelWidth:pixelHeight:portIndex:)``
    /// identity had to be used.
    ///
    /// Measurements on real hardware showed this to be the **common** case, not
    /// the exception: a Samsung C49RG9x used as the primary monitor reports
    /// serial `0`. The fallback path is therefore treated as first class
    /// everywhere, and `openzonr displays` says so explicitly, because two
    /// identical monitors on swapped ports remain the one case it cannot tell
    /// apart.
    public var usesSerialFallback: Bool

    /// Physical panel size in millimetres as reported by `CGDisplayScreenSize`.
    ///
    /// Kept because it is the only public signal that reliably separates a real
    /// panel from a software display: virtual displays have no physical size and
    /// report `0 × 0`.
    public var physicalSizeMillimeters: WindowSize

    /// Heuristic marker for software displays such as OBS virtual cameras or
    /// teleprompter mirrors.
    ///
    /// Purely informational — it drives a *warning*, never a silent exclusion.
    /// Excluding a display from the setup fingerprint is an explicit decision
    /// the user makes through ``Configuration/ignoredDisplays``, because
    /// guessing wrong would swap the whole profile.
    public var isLikelyVirtual: Bool

    /// `true` for the primary display, the one that owns the menu bar and the
    /// origin of both coordinate systems.
    public var isPrimary: Bool

    public init(
        identity: DisplayIdentity,
        localizedName: String,
        displayID: UInt32,
        pixelWidth: Int,
        pixelHeight: Int,
        backingScaleFactor: Double,
        frame: WindowFrame,
        visibleFrame: WindowFrame,
        usesSerialFallback: Bool,
        physicalSizeMillimeters: WindowSize = WindowSize(width: 0, height: 0),
        isLikelyVirtual: Bool = false,
        isPrimary: Bool
    ) {
        self.identity = identity
        self.localizedName = localizedName
        self.displayID = displayID
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.backingScaleFactor = backingScaleFactor
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.usesSerialFallback = usesSerialFallback
        self.physicalSizeMillimeters = physicalSizeMillimeters
        self.isLikelyVirtual = isLikelyVirtual
        self.isPrimary = isPrimary
    }
}

extension SetupFingerprint {
    /// The fingerprint of the currently attached displays.
    ///
    /// - Parameters:
    ///   - snapshots: every attached display.
    ///   - ignoring: identities the user declared irrelevant for profile
    ///     selection. Software displays appear and disappear while nothing
    ///     physically changes; without this filter every OBS start would swap
    ///     the active profile — the exact behaviour OpenZonr exists to avoid.
    public init(snapshots: [DisplaySnapshot], ignoring ignored: [DisplayIdentity] = []) {
        let ignoredSet = Set(ignored)
        self.init(displays: Set(snapshots.map(\.identity).filter { !ignoredSet.contains($0) }))
    }
}

/// The bridge between the two coordinate systems macOS uses for window geometry
/// and between configured display aliases and physically attached panels.
///
/// **The trap this type exists for:** `NSScreen` reports frames with the origin
/// at the *bottom-left* of the primary display, `y` growing upwards.
/// Accessibility (`kAXPositionAttribute`) uses the *top-left* of the primary
/// display, `y` growing downwards. On a single display the mistake is invisible
/// as long as everything is full height; with a second, taller or shorter
/// monitor next to it, windows silently land vertically offset by the height
/// difference. The conversion therefore lives here and nowhere else.
public struct DisplayGeometry: Sendable {

    /// All attached displays, in system order.
    public let snapshots: [DisplaySnapshot]

    /// The `y` coordinate of the top edge of the primary display in AppKit
    /// coordinates. This is the value both coordinate systems pivot around.
    public let primaryTopY: Double

    /// Maps configured aliases onto the displays actually attached.
    private let byAlias: [DisplayAlias: DisplaySnapshot]

    /// - Parameters:
    ///   - snapshots: every currently attached display.
    ///   - descriptors: the `displays` table of the configuration, used to
    ///     resolve aliases. Displays that are configured but not attached are
    ///     simply absent from the mapping.
    public init(snapshots: [DisplaySnapshot], descriptors: [DisplayDescriptor]) {
        self.snapshots = snapshots

        let primary = snapshots.first(where: \.isPrimary) ?? snapshots.first
        self.primaryTopY = primary.map { $0.frame.y + $0.frame.height } ?? 0

        var mapping: [DisplayAlias: DisplaySnapshot] = [:]
        for descriptor in descriptors {
            if let match = snapshots.first(where: { $0.identity == descriptor.identity }) {
                mapping[descriptor.alias] = match
            }
        }
        self.byAlias = mapping
    }

    /// The attached display behind a configured alias, or `nil` when the alias
    /// refers to a monitor that is not plugged in right now.
    public func snapshot(for alias: DisplayAlias) -> DisplaySnapshot? {
        byAlias[alias]
    }

    /// Translates a rectangle between the AppKit and the Accessibility
    /// coordinate space.
    ///
    /// The transformation is its own inverse, which is why a single function
    /// covers both directions: mirroring at the primary display's top edge and
    /// mirroring back are the same operation.
    public static func flipVertically(_ rect: WindowFrame, primaryTopY: Double) -> WindowFrame {
        WindowFrame(
            x: rect.x,
            y: primaryTopY - (rect.y + rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    /// The visible frame of a display in Accessibility coordinates.
    public func accessibilityVisibleFrame(of display: DisplaySnapshot) -> WindowFrame {
        Self.flipVertically(display.visibleFrame, primaryTopY: primaryTopY)
    }

    /// Resolves a relative zone rectangle to an absolute frame in
    /// **Accessibility** coordinates — the space a window is actually set in.
    ///
    /// ``RelativeRect`` is top-left based within the visible frame, which is
    /// also the Accessibility orientation, so after flipping the visible frame
    /// the remaining arithmetic is a plain scale-and-offset.
    public func absoluteFrame(for rect: RelativeRect, on display: DisplaySnapshot) -> WindowFrame {
        let visible = accessibilityVisibleFrame(of: display)
        return WindowFrame(
            x: visible.x + rect.x * visible.width,
            y: visible.y + rect.y * visible.height,
            width: rect.width * visible.width,
            height: rect.height * visible.height
        )
    }

    /// The display a window currently sits on, determined by the largest
    /// overlap of the window with a display's full frame.
    ///
    /// Overlap rather than origin: a window dragged half across a monitor edge
    /// has an origin on one screen but visually belongs to the other, and macOS
    /// itself uses the same "mostly on" heuristic.
    public func display(containingAccessibilityFrame frame: WindowFrame) -> DisplaySnapshot? {
        var best: (display: DisplaySnapshot, area: Double)?
        for snapshot in snapshots {
            let screen = Self.flipVertically(snapshot.frame, primaryTopY: primaryTopY)
            let area = frame.intersectionArea(with: screen)
            if area > 0, area > (best?.area ?? 0) {
                best = (snapshot, area)
            }
        }
        return best?.display
    }
}

extension WindowFrame {
    /// Area shared with another frame, `0` when they do not overlap.
    public func intersectionArea(with other: WindowFrame) -> Double {
        let overlapWidth = min(x + width, other.x + other.width) - max(x, other.x)
        let overlapHeight = min(y + height, other.y + other.height) - max(y, other.y)
        guard overlapWidth > 0, overlapHeight > 0 else { return 0 }
        return overlapWidth * overlapHeight
    }

    /// The largest per-edge deviation from another frame.
    ///
    /// Used to decide whether a placement succeeded: apps round frames to their
    /// own increments, so an exact comparison would report failure for windows
    /// that are visually correct. ``RetryPolicy/tolerance`` is compared against
    /// this value.
    public func maximumDeviation(from other: WindowFrame) -> Double {
        max(
            abs(x - other.x),
            abs(y - other.y),
            abs(width - other.width),
            abs(height - other.height)
        )
    }
}
