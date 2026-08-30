import Foundation

/// Turns a role into an absolute frame: role → binding → display + zone →
/// layout geometry → points in the Accessibility coordinate space.
///
/// This is the step where the indirection chain from the concept is actually
/// walked, and the only place a ``RelativeRect`` becomes concrete.
public struct DefaultZoneResolver: ZoneResolver {

    /// Why a role could not be turned into a frame.
    public enum Problem: Error, Hashable, Sendable, CustomStringConvertible {
        case displayNotAttached(DisplayAlias)
        case unknownDisplay(DisplayAlias)
        case unknownLayout(DisplayAlias, LayoutID)
        case unknownZone(DisplayAlias, LayoutID, ZoneID)

        public var description: String {
            switch self {
            case let .displayNotAttached(alias):
                return "Display \"\(alias)\" ist konfiguriert, aber gerade nicht angeschlossen"
            case let .unknownDisplay(alias):
                return "Display \"\(alias)\" ist in der Konfiguration nicht deklariert"
            case let .unknownLayout(alias, layout):
                return "Display \"\(alias)\" kennt kein Layout \"\(layout)\""
            case let .unknownZone(alias, layout, zone):
                return "Layout \"\(layout)\" auf \"\(alias)\" enthält keine Zone \"\(zone)\""
            }
        }
    }

    public init() {}

    public func resolve(
        role: RoleID,
        share: ZoneShare?,
        profile: Profile,
        configuration: Configuration,
        geometry: DisplayGeometry
    ) -> ResolvedPlacement? {
        switch resolvePlacement(
            role: role,
            share: share,
            profile: profile,
            configuration: configuration,
            geometry: geometry
        ) {
        case let .success(placement): return placement
        case .failure: return nil
        }
    }

    /// Same as ``resolve(role:share:profile:configuration:geometry:)`` but keeps
    /// the failure reason so `watch` can log why nothing happened.
    public func resolvePlacement(
        role: RoleID,
        share: ZoneShare?,
        profile: Profile,
        configuration: Configuration,
        geometry: DisplayGeometry
    ) -> Result<ResolvedPlacement, Problem> {
        let binding = profile.roleBindings.first { $0.role == role }
        let usedFallback = binding == nil
        let effective = binding ?? profile.fallback

        guard let descriptor = configuration.displays.first(where: { $0.alias == effective.display }) else {
            return .failure(.unknownDisplay(effective.display))
        }
        guard let snapshot = geometry.snapshot(for: effective.display) else {
            return .failure(.displayNotAttached(effective.display))
        }

        let layoutID = profile.layouts[effective.display] ?? descriptor.defaultLayoutID
        guard let layout = descriptor.layouts.first(where: { $0.id == layoutID }) else {
            return .failure(.unknownLayout(effective.display, layoutID))
        }
        guard let zone = layout.zones.first(where: { $0.id == effective.zone }) else {
            return .failure(.unknownZone(effective.display, layoutID, effective.zone))
        }

        let rect = share.map { Self.slot($0, in: zone.frame) } ?? zone.frame

        return .success(
            ResolvedPlacement(
                frame: geometry.absoluteFrame(for: rect, on: snapshot),
                display: effective.display,
                zone: zone.id,
                usedFallback: usedFallback
            )
        )
    }

    /// Subdivides a zone into equally sized slots.
    ///
    /// Anything beyond equal slots belongs into the layout as its own zone —
    /// otherwise a second, parallel layout system grows inside the rule set.
    /// Out-of-range indices are clamped rather than rejected, because a
    /// half-broken configuration should still place the window somewhere
    /// sensible instead of silently dropping it.
    public static func slot(_ share: ZoneShare, in rect: RelativeRect) -> RelativeRect {
        let slots = max(1, share.slots)
        let index = min(max(0, share.slotIndex), slots - 1)
        let fraction = 1.0 / Double(slots)

        switch share.axis {
        case .horizontal:
            // Slots are stacked along the horizontal axis, i.e. side by side.
            return RelativeRect(
                x: rect.x + rect.width * fraction * Double(index),
                y: rect.y,
                width: rect.width * fraction,
                height: rect.height
            )
        case .vertical:
            // Slots are stacked along the vertical axis, i.e. above each other.
            return RelativeRect(
                x: rect.x,
                y: rect.y + rect.height * fraction * Double(index),
                width: rect.width,
                height: rect.height * fraction
            )
        }
    }
}
