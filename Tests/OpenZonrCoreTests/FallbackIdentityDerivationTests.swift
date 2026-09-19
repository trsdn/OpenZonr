import Testing
@testable import OpenZonrCore

/// Ein Panel, viele Modi: die Identität eines Monitors ohne Seriennummer darf
/// sich nicht ändern, wenn der Nutzer die Auflösung umschaltet.
struct FallbackIdentityDerivationTests {

    private static let native = DisplayModeSample.nativeIOFlag

    /// Ein 4K-Panel mit nativem Modus und mehreren skalierten Modi.
    private static let panelModes: [DisplayModeSample] = [
        DisplayModeSample(pixelWidth: 3840, pixelHeight: 2160, ioFlags: native),
        DisplayModeSample(pixelWidth: 2560, pixelHeight: 1440, ioFlags: 0),
        DisplayModeSample(pixelWidth: 5120, pixelHeight: 2880, ioFlags: 0),
        DisplayModeSample(pixelWidth: 1920, pixelHeight: 1080, ioFlags: 0)
    ]

    @Test("Die native Größe kommt aus dem markierten Modus, nicht aus dem größten")
    func picksFlaggedNativeMode() {
        let size = FallbackIdentityDerivation.nativePixelSize(from: Self.panelModes)
        #expect(size?.width == 3840)
        #expect(size?.height == 2160)
    }

    @Test("Die Identität hängt nicht davon ab, welcher Modus aktiv ist")
    func identityIsIndependentOfModeOrder() {
        // Die Modusliste eines Panels ist immer dieselbe, egal welcher Modus
        // gerade aktiv ist; die Reihenfolge darf ebenfalls nichts ändern.
        let a = FallbackIdentityDerivation.identity(
            vendorNumber: 19501, modelNumber: 7, unitNumber: 1, modes: Self.panelModes
        )
        let b = FallbackIdentityDerivation.identity(
            vendorNumber: 19501, modelNumber: 7, unitNumber: 1, modes: Self.panelModes.reversed()
        )
        #expect(a == b)
        #expect(a == .fallback(vendorNumber: 19501, modelNumber: 7, pixelWidth: 3840, pixelHeight: 2160, portIndex: 1))
    }

    @Test("Ohne Native-Flag wird die Größe als unbekannt geführt, nicht geraten")
    func noFlagYieldsUnknownSize() {
        let modes = Self.panelModes.map { DisplayModeSample(pixelWidth: $0.pixelWidth, pixelHeight: $0.pixelHeight, ioFlags: 0) }
        #expect(FallbackIdentityDerivation.nativePixelSize(from: modes) == nil)
        let identity = FallbackIdentityDerivation.identity(
            vendorNumber: 1, modelNumber: 2, unitNumber: 0, modes: modes
        )
        #expect(identity == .fallback(vendorNumber: 1, modelNumber: 2, pixelWidth: 0, pixelHeight: 0, portIndex: 0))
    }

    @Test("Mehrdeutige Native-Flags (verschiedene Größen) gelten als unbekannt")
    func ambiguousFlagsYieldUnknownSize() {
        let modes = [
            DisplayModeSample(pixelWidth: 3840, pixelHeight: 2160, ioFlags: Self.native),
            DisplayModeSample(pixelWidth: 2560, pixelHeight: 1440, ioFlags: Self.native)
        ]
        #expect(FallbackIdentityDerivation.nativePixelSize(from: modes) == nil)
    }

    @Test("Dieselbe native Größe in mehreren Modi (Refresh-Raten) ist eindeutig")
    func duplicateFlaggedSizesAreUnambiguous() {
        let modes = [
            DisplayModeSample(pixelWidth: 3840, pixelHeight: 2160, ioFlags: Self.native),
            DisplayModeSample(pixelWidth: 3840, pixelHeight: 2160, ioFlags: Self.native | 0x1)
        ]
        let size = FallbackIdentityDerivation.nativePixelSize(from: modes)
        #expect(size?.width == 3840)
    }

    @Test("Zwei baugleiche Monitore bleiben über die Unit-Nummer unterscheidbar")
    func identicalMonitorsDifferByUnit() {
        let first = FallbackIdentityDerivation.identity(
            vendorNumber: 19501, modelNumber: 7, unitNumber: 1, modes: Self.panelModes
        )
        let second = FallbackIdentityDerivation.identity(
            vendorNumber: 19501, modelNumber: 7, unitNumber: 2, modes: Self.panelModes
        )
        #expect(first != second)
        #expect(Set([first, second]).count == 2)
    }

    @Test("Leere Modusliste führt zu unbekannter Größe statt Absturz")
    func emptyModes() {
        #expect(FallbackIdentityDerivation.nativePixelSize(from: []) == nil)
    }
}
