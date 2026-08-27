import Foundation

/// A stable reference to one window, used to track occupancy and manual
/// overrides.
///
/// ``WindowSnapshot`` deliberately describes a window at a point in time and
/// carries no identity — two snapshots of the same window taken a second apart
/// differ in title and frame. Occupancy and manual overrides need something
/// that survives that, so the identity is kept separate.
///
/// The token is opaque on purpose. The layer that talks to the Accessibility
/// API decides what it derives the token from (the `AXUIElement`, a window
/// number, a synthesised counter); the resolution logic only ever compares
/// tokens for equality, which keeps it testable without a window server.
public struct WindowIdentifier: Hashable, Sendable, CustomStringConvertible {

    /// Process identifier of the owning application.
    public var processIdentifier: Int32

    /// Opaque, per-process unique handle of the window.
    public var token: String

    public init(processIdentifier: Int32, token: String) {
        self.processIdentifier = processIdentifier
        self.token = token
    }

    public var description: String { "\(processIdentifier):\(token)" }
}
