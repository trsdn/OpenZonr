import Foundation

/// One entry of a display's mode list, reduced to plain values so the identity
/// derivation can be tested without a display attached.
public struct DisplayModeSample: Hashable, Sendable {

    /// `kDisplayModeNativeFlag` from IOKit's `IOGraphicsTypes.h`.
    public static let nativeIOFlag: UInt32 = 0x0200_0000

    public var pixelWidth: Int
    public var pixelHeight: Int
    /// `CGDisplayModeGetIOFlags`.
    public var ioFlags: UInt32

    public var isFlaggedNative: Bool { ioFlags & Self.nativeIOFlag != 0 }

    public init(pixelWidth: Int, pixelHeight: Int, ioFlags: UInt32) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.ioFlags = ioFlags
    }
}

/// Derives ``DisplayIdentity/fallback(vendorNumber:modelNumber:pixelWidth:pixelHeight:portIndex:)``
/// from values that do not change when the user switches the display mode.
///
/// The current mode is deliberately not an input. The native panel size is only
/// available when the driver flags exactly one size as native; otherwise it is
/// recorded as `0 x 0` (unknown) rather than guessed, because the largest mode
/// can be a scaled backing store larger than the panel. The pixel size is
/// informational only — see ``DisplayIdentity`` equality.
public enum FallbackIdentityDerivation {

    /// Size of the single mode flagged native, or nil when the flag is absent,
    /// ambiguous (several different flagged sizes) or the mode list is empty.
    public static func nativePixelSize(from modes: [DisplayModeSample]) -> (width: Int, height: Int)? {
        let sizes = Set(
            modes.filter(\.isFlaggedNative).map { Size(width: $0.pixelWidth, height: $0.pixelHeight) }
        )
        guard sizes.count == 1, let size = sizes.first else { return nil }
        return (size.width, size.height)
    }

    /// Identity for a display without a usable serial number. Never reads the
    /// current mode: unknown native size is recorded as 0 x 0.
    public static func identity(
        vendorNumber: UInt32,
        modelNumber: UInt32,
        unitNumber: Int,
        modes: [DisplayModeSample]
    ) -> DisplayIdentity {
        let size = nativePixelSize(from: modes)
        return .fallback(
            vendorNumber: vendorNumber,
            modelNumber: modelNumber,
            pixelWidth: size?.width ?? 0,
            pixelHeight: size?.height ?? 0,
            portIndex: unitNumber
        )
    }

    private struct Size: Hashable {
        var width: Int
        var height: Int
    }
}
