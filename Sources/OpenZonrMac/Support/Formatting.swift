import Foundation
import OpenZonrCore

/// Human readable rendering of a display identity, used everywhere a display is
/// named to the user — the CLI subcommands, the watch log and the app's
/// permission and profile screens.
public func describe(_ identity: DisplayIdentity) -> String {
    switch identity {
    case .builtin:
        return "builtin (integriertes Display)"
    case let .edid(vendor, model, serial):
        return "edid vendor=\(vendor) model=\(model) serial=\(serial)"
    case let .fallback(vendor, model, width, height, port):
        return "fallback vendor=\(vendor) model=\(model) \(width)×\(height) port=\(port)"
    }
}

/// Renders a measurement without a trailing `.0` when it is whole.
public func format(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
}

extension Duration {
    public var milliseconds: Int {
        Int((Double(components.seconds) * 1000) + (Double(components.attoseconds) / 1e15))
    }
}
