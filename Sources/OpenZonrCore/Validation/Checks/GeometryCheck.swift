import Foundation

public struct GeometryCheck: ConfigurationCheck {

    private let overflowSlack = 1e-9

    public init() {}

    public func findings(in configuration: Configuration) -> [ValidationFinding] {
        var findings: [ValidationFinding] = []

        for display in configuration.displays {
            for layout in display.layouts {
                for zone in layout.zones {
                    let zonePath = ConfigurationPath()
                        .element("displays", display.alias)
                        .element("layouts", layout.id)
                        .element("zones", zone.id)
                    findings.append(contentsOf: validate(rect: zone.frame, at: zonePath.field("frame")))
                    if let activationArea = zone.activationArea {
                        findings.append(contentsOf: validate(rect: activationArea, at: zonePath.field("activationArea")))
                    }
                }
            }
        }

        for rule in configuration.rules {
            guard let share = rule.action.share else { continue }
            let sharePath = ConfigurationPath().element("rules", rule.id).field("action").field("share")

            if share.slots < 2 {
                findings.append(ValidationFinding(
                    code: .zoneShareTooFewSlots,
                    path: sharePath.field("slots"),
                    message: L.string(
                        "geometry.zoneShare.tooFewSlots",
                        "A zone share needs at least two slots."
                    )
                ))
            }
            if share.slotIndex < 0 || share.slotIndex >= share.slots {
                findings.append(ValidationFinding(
                    code: .zoneShareSlotIndexOutOfRange,
                    path: sharePath.field("slotIndex"),
                    message: L.string(
                        "geometry.zoneShare.slotIndexOutOfRange",
                        "Slot index %lld is outside the %lld slots.",
                        share.slotIndex, share.slots
                    )
                ))
            }
        }

        return findings
    }

    private func validate(rect: RelativeRect, at path: ConfigurationPath) -> [ValidationFinding] {
        var findings: [ValidationFinding] = []
        appendRangeFinding(rect.x, field: "x", path: path, to: &findings)
        appendRangeFinding(rect.y, field: "y", path: path, to: &findings)
        let widthOutOfRange = appendRangeFinding(rect.width, field: "width", path: path, to: &findings)
        let heightOutOfRange = appendRangeFinding(rect.height, field: "height", path: path, to: &findings)

        if rect.width <= 0, !widthOutOfRange {
            findings.append(ValidationFinding(
                code: .relativeRectNonPositiveSize,
                path: path.field("width"),
                message: L.string("geometry.rect.nonPositiveWidth", "The zone's width must be greater than 0.")
            ))
        }
        if rect.height <= 0, !heightOutOfRange {
            findings.append(ValidationFinding(
                code: .relativeRectNonPositiveSize,
                path: path.field("height"),
                message: L.string("geometry.rect.nonPositiveHeight", "The zone's height must be greater than 0.")
            ))
        }
        if !widthOutOfRange, rect.x + rect.width > 1 + overflowSlack {
            findings.append(ValidationFinding(
                code: .relativeRectOverflow,
                path: path.field("width"),
                message: L.string("geometry.rect.overflowHorizontal", "The zone extends past the visible area horizontally.")
            ))
        }
        if !heightOutOfRange, rect.y + rect.height > 1 + overflowSlack {
            findings.append(ValidationFinding(
                code: .relativeRectOverflow,
                path: path.field("height"),
                message: L.string("geometry.rect.overflowVertical", "The zone extends past the visible area vertically.")
            ))
        }

        return findings
    }

    @discardableResult
    private func appendRangeFinding(
        _ value: Double,
        field: String,
        path: ConfigurationPath,
        to findings: inout [ValidationFinding]
    ) -> Bool {
        guard value < 0 || value > 1 else { return false }
        findings.append(ValidationFinding(
            code: .relativeRectOutOfRange,
            path: path.field(field),
            message: L.string(
                "geometry.rect.valueOutOfRange",
                "Value %g is outside the allowed range 0 to 1.",
                value
            )
        ))
        return true
    }
}
