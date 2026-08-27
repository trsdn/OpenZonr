import AppKit
import CoreGraphics
import Foundation
import OpenZonrCore

/// Reads the currently attached displays from CoreGraphics and AppKit.
///
/// CoreGraphics owns the identity (EDID data, builtin flag, unit number),
/// AppKit owns the geometry (`frame`, `visibleFrame`, backing scale). The two
/// are joined over `NSScreenNumber`, which is the `CGDirectDisplayID` of a
/// screen — the only officially supported bridge between the two worlds.
enum SystemDisplays {

    /// Every attached display.
    ///
    /// Enumeration goes through `NSScreen`, not `CGGetActiveDisplayList`: the
    /// latter reports zero displays in a plain command line process on current
    /// macOS, while `NSScreen` is reliable and carries the `visibleFrame` that is
    /// needed anyway. The `CGDirectDisplayID` is recovered from each screen's
    /// `NSScreenNumber`, which is the officially supported bridge into the
    /// CoreGraphics identity functions.
    static func snapshots() -> [DisplaySnapshot] {
        NSScreen.screens.compactMap { screen -> DisplaySnapshot? in
            guard let number = screen.deviceDescription[
                NSDeviceDescriptionKey("NSScreenNumber")
            ] as? NSNumber else { return nil }
            return snapshot(for: CGDirectDisplayID(number.uint32Value), screen: screen)
        }
    }

    private static func snapshot(for id: CGDirectDisplayID, screen: NSScreen?) -> DisplaySnapshot {
        let isBuiltin = CGDisplayIsBuiltin(id) != 0
        let vendor = CGDisplayVendorNumber(id)
        let model = CGDisplayModelNumber(id)
        let serial = CGDisplaySerialNumber(id)

        // Native pixel dimensions, not the current scaled mode: a Retina panel
        // running a scaled resolution must keep the same identity.
        let mode = CGDisplayCopyDisplayMode(id)
        let pixelWidth = mode.map { $0.pixelWidth } ?? CGDisplayPixelsWide(id)
        let pixelHeight = mode.map { $0.pixelHeight } ?? CGDisplayPixelsHigh(id)

        let identity: DisplayIdentity
        if isBuiltin {
            identity = .builtin
        } else if serial == 0 {
            identity = .fallback(
                vendorNumber: vendor,
                modelNumber: model,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                // The unit number is stable per physical connection and is the
                // closest public equivalent of a port index.
                portIndex: Int(CGDisplayUnitNumber(id))
            )
        } else {
            identity = .edid(vendorNumber: vendor, modelNumber: model, serialNumber: serial)
        }

        let physical = CGDisplayScreenSize(id)
        let bounds = CGDisplayBounds(id)
        let frame = screen?.frame ?? bounds
        let visibleFrame = screen?.visibleFrame ?? frame

        return DisplaySnapshot(
            identity: identity,
            localizedName: screen?.localizedName ?? "Display \(id)",
            displayID: id,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            backingScaleFactor: Double(screen?.backingScaleFactor ?? 1),
            frame: WindowFrame(frame),
            visibleFrame: WindowFrame(visibleFrame),
            physicalSizeMillimeters: WindowSize(width: physical.width, height: physical.height),
            portIndex: Int(CGDisplayUnitNumber(id)),
            isPrimary: CGDisplayIsMain(id) != 0,
            isLikelyVirtual: Self.looksVirtual(
                isBuiltin: isBuiltin,
                model: model,
                serial: serial,
                physical: physical
            )
        )
    }

    /// Weak, explicitly fallible hint that a display is a software display.
    ///
    /// There is no public API that answers this. `CGDisplayScreenSize` was the
    /// obvious candidate and turned out to be useless: measured software
    /// displays report perfectly plausible physical sizes (a screen sharing
    /// surface claimed 677 × 381 mm).
    ///
    /// What did separate them in practice is the EDID product code. Real panels
    /// carry a manufacturer-assigned product and serial number; the measured
    /// software displays reported model `0` and `1` with serial `0` and `1`.
    /// That is a plausible tell, not a proof — which is exactly why this only
    /// produces a warning and never an automatic exclusion. The decision belongs
    /// in ``Configuration/ignoredDisplays``, where the user made it on purpose.
    static func looksVirtual(isBuiltin: Bool, model: UInt32, serial: UInt32, physical: CGSize) -> Bool {
        guard !isBuiltin else { return false }
        if physical.width == 0 || physical.height == 0 { return true }
        return model <= 1
    }
}

extension WindowFrame {
    init(_ rect: CGRect) {
        self.init(
            x: Double(rect.origin.x),
            y: Double(rect.origin.y),
            width: Double(rect.size.width),
            height: Double(rect.size.height)
        )
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }

    /// Compact `x,y wxh` rendering used throughout the CLI output.
    var shortDescription: String {
        String(format: "%.0f,%.0f %.0fx%.0f", x, y, width, height)
    }
}
