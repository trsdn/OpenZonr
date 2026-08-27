import Foundation

/// Short, human chosen handle for a display, used to reference it from profiles
/// and role bindings, e.g. `"dell-u2723"`.
///
/// The alias exists so that a configuration file stays readable. It is *not* an
/// identity: the alias is resolved to a ``DisplayIdentity`` through the
/// ``DisplayDescriptor`` table.
///
/// The `CodingKeyRepresentable` conformance inherited from ``StringIdentifier``
/// keeps dictionaries keyed by an alias encoded as a plain JSON object instead
/// of a flattened key/value array.
public struct DisplayAlias: StringIdentifier {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// A stable, reconnect-proof identity of a physical display.
///
/// Deliberately **not** used as identity:
/// - screen position or index in `NSScreen.screens` — changes as soon as cables
///   are swapped or the arrangement is edited,
/// - resolution alone — two identical monitors become indistinguishable,
/// - `CGDirectDisplayID` — assigned per session, not stable across reboots.
///
/// The preferred source is the EDID data exposed by CoreGraphics
/// (`CGDisplayVendorNumber`, `CGDisplayModelNumber`, `CGDisplaySerialNumber`).
/// Some monitors report a serial number of `0`; for those a weaker fallback is
/// used that additionally pins the native pixel size and the port index. The
/// fallback is explicitly marked as such so the UI can warn that two identical
/// monitors on swapped ports may be confused.
public enum DisplayIdentity: Codable, Hashable, Sendable {

    /// The built-in laptop display, detected via `CGDisplayIsBuiltin`.
    ///
    /// The built-in panel is a special case because it is the only display that
    /// is present in every setup and is never swapped for a different model
    /// without also swapping the machine.
    case builtin

    /// Full EDID identity — the preferred, strongest case.
    case edid(vendorNumber: UInt32, modelNumber: UInt32, serialNumber: UInt32)

    /// Fallback for displays that report no usable serial number.
    ///
    /// Vendor + model + native pixel size + port index is not globally unique,
    /// but it is stable enough as long as the user does not swap two identical
    /// monitors between ports.
    case fallback(vendorNumber: UInt32, modelNumber: UInt32, pixelWidth: Int, pixelHeight: Int, portIndex: Int)

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case kind, vendorNumber, modelNumber, serialNumber, pixelWidth, pixelHeight, portIndex
    }

    private enum Kind: String, Codable {
        case builtin, edid, fallback
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .builtin:
            self = .builtin
        case .edid:
            self = .edid(
                vendorNumber: try container.decode(UInt32.self, forKey: .vendorNumber),
                modelNumber: try container.decode(UInt32.self, forKey: .modelNumber),
                serialNumber: try container.decode(UInt32.self, forKey: .serialNumber)
            )
        case .fallback:
            self = .fallback(
                vendorNumber: try container.decode(UInt32.self, forKey: .vendorNumber),
                modelNumber: try container.decode(UInt32.self, forKey: .modelNumber),
                pixelWidth: try container.decode(Int.self, forKey: .pixelWidth),
                pixelHeight: try container.decode(Int.self, forKey: .pixelHeight),
                portIndex: try container.decode(Int.self, forKey: .portIndex)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .builtin:
            try container.encode(Kind.builtin, forKey: .kind)
        case let .edid(vendorNumber, modelNumber, serialNumber):
            try container.encode(Kind.edid, forKey: .kind)
            try container.encode(vendorNumber, forKey: .vendorNumber)
            try container.encode(modelNumber, forKey: .modelNumber)
            try container.encode(serialNumber, forKey: .serialNumber)
        case let .fallback(vendorNumber, modelNumber, pixelWidth, pixelHeight, portIndex):
            try container.encode(Kind.fallback, forKey: .kind)
            try container.encode(vendorNumber, forKey: .vendorNumber)
            try container.encode(modelNumber, forKey: .modelNumber)
            try container.encode(pixelWidth, forKey: .pixelWidth)
            try container.encode(pixelHeight, forKey: .pixelHeight)
            try container.encode(portIndex, forKey: .portIndex)
        }
    }
}

/// Everything the configuration knows about one physical display.
///
/// This is the place where a display's *identity* meets its *layouts*, because
/// layouts are a property of the panel geometry, not of the setup the user
/// happens to be in.
public struct DisplayDescriptor: Codable, Hashable, Sendable, Identifiable {
    public var id: DisplayAlias { alias }

    /// Handle used to reference this display elsewhere in the configuration.
    public var alias: DisplayAlias
    /// Label for the UI, e.g. "Dell U2723QE (Büro)".
    public var displayName: String
    /// Stable hardware identity.
    public var identity: DisplayIdentity
    /// All layouts defined for this display.
    public var layouts: [Layout]
    /// Layout used when a profile does not select one explicitly.
    public var defaultLayoutID: LayoutID

    public init(
        alias: DisplayAlias,
        displayName: String,
        identity: DisplayIdentity,
        layouts: [Layout],
        defaultLayoutID: LayoutID
    ) {
        self.alias = alias
        self.displayName = displayName
        self.identity = identity
        self.layouts = layouts
        self.defaultLayoutID = defaultLayoutID
    }
}
