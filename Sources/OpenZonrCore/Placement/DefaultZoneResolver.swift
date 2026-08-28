import Foundation

public struct DefaultZoneResolver: ZoneResolver {
    public init() {}

    public func resolve(
        role: RoleID,
        share: ZoneShare?,
        profile: Profile,
        configuration: Configuration,
        visibleFrames: VisibleFrames
    ) -> Result<ResolvedPlacement, ZoneResolutionFailure> {
        let explicitBinding = profile.roleBindings.first { $0.role == role }
        let binding = explicitBinding ?? profile.fallback
        let usedFallback = explicitBinding == nil

        return resolve(
            binding: binding,
            share: share,
            usedFallback: usedFallback,
            configuration: configuration,
            profile: profile,
            visibleFrames: visibleFrames
        )
    }

    public func resolveFallback(
        profile: Profile,
        configuration: Configuration,
        visibleFrames: VisibleFrames
    ) -> Result<ResolvedPlacement, ZoneResolutionFailure> {
        resolve(
            binding: profile.fallback,
            share: nil,
            usedFallback: true,
            configuration: configuration,
            profile: profile,
            visibleFrames: visibleFrames
        )
    }

    private func resolve(
        binding: RoleBinding,
        share: ZoneShare?,
        usedFallback: Bool,
        configuration: Configuration,
        profile: Profile,
        visibleFrames: VisibleFrames
    ) -> Result<ResolvedPlacement, ZoneResolutionFailure> {        guard let display = configuration.displays.first(where: { $0.alias == binding.display }) else {
            return .failure(.unknownDisplay(binding.display))
        }

        let layoutID = profile.layouts[binding.display] ?? display.defaultLayoutID
        guard let layout = display.layouts.first(where: { $0.id == layoutID }) else {
            return .failure(.unknownLayout(layoutID, display: binding.display))
        }

        guard let zone = layout.zones.first(where: { $0.id == binding.zone }) else {
            return .failure(.unknownZone(binding.zone, layout: layoutID, display: binding.display))
        }

        guard let visibleFrame = visibleFrames[binding.display] else {
            return .failure(.missingVisibleFrame(binding.display))
        }

        let relativeFrame: RelativeRect
        if let share {
            guard share.slots >= 2, (0..<share.slots).contains(share.slotIndex) else {
                return .failure(.invalidShare(share))
            }
            relativeFrame = subdivide(zone.frame, by: share)
        } else {
            relativeFrame = zone.frame
        }

        return .success(
            ResolvedPlacement(
                frame: absoluteFrame(for: relativeFrame, in: visibleFrame),
                display: binding.display,
                zone: binding.zone,
                usedFallback: usedFallback
            )
        )
    }

    private func subdivide(_ rect: RelativeRect, by share: ZoneShare) -> RelativeRect {
        switch share.axis {
        case .horizontal:
            let width = rect.width / Double(share.slots)
            return RelativeRect(
                x: rect.x + Double(share.slotIndex) * width,
                y: rect.y,
                width: width,
                height: rect.height
            )
        case .vertical:
            let height = rect.height / Double(share.slots)
            return RelativeRect(
                x: rect.x,
                y: rect.y + Double(share.slotIndex) * height,
                width: rect.width,
                height: height
            )
        }
    }

    /// Converts a zone rectangle from the configuration model's top-left origin
    /// into AppKit's bottom-left coordinate space.
    ///
    /// Delegated to ``ZoneGeometry`` since the drag path resolves the same zones
    /// from a pointer position: one arithmetic, two callers, no chance of the
    /// two disagreeing by a point.
    private func absoluteFrame(for rect: RelativeRect, in frame: VisibleFrame) -> WindowFrame {
        ZoneGeometry.absoluteFrame(for: rect, in: frame)
    }
}
