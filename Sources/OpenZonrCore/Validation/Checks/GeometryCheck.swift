import Foundation

public struct GeometryCheck: ConfigurationCheck {

    private let overflowSlack = 1e-9

    public init() {}

    public func findings(in configuration: Configuration) -> [ValidationFinding] {
        var findings: [ValidationFinding] = []

        for display in configuration.displays {
            for layout in display.layouts {
                for zone in layout.zones {
                    let path = ConfigurationPath()
                        .element("displays", display.alias)
                        .element("layouts", layout.id)
                        .element("zones", zone.id)
                        .field("frame")
                    findings.append(contentsOf: validate(rect: zone.frame, at: path))
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
                    message: "Eine Zonenteilung braucht mindestens zwei Slots."
                ))
            }
            if share.slotIndex < 0 || share.slotIndex >= share.slots {
                findings.append(ValidationFinding(
                    code: .zoneShareSlotIndexOutOfRange,
                    path: sharePath.field("slotIndex"),
                    message: "Der Slot-Index \(share.slotIndex) liegt außerhalb der \(share.slots) Slots."
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
                message: "Die Breite der Zone muss größer als 0 sein."
            ))
        }
        if rect.height <= 0, !heightOutOfRange {
            findings.append(ValidationFinding(
                code: .relativeRectNonPositiveSize,
                path: path.field("height"),
                message: "Die Höhe der Zone muss größer als 0 sein."
            ))
        }
        if !widthOutOfRange, rect.x + rect.width > 1 + overflowSlack {
            findings.append(ValidationFinding(
                code: .relativeRectOverflow,
                path: path.field("width"),
                message: "Die Zone ragt horizontal über den sichtbaren Bereich hinaus."
            ))
        }
        if !heightOutOfRange, rect.y + rect.height > 1 + overflowSlack {
            findings.append(ValidationFinding(
                code: .relativeRectOverflow,
                path: path.field("height"),
                message: "Die Zone ragt vertikal über den sichtbaren Bereich hinaus."
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
            message: "Der Wert \(value) liegt außerhalb des erlaubten Bereichs 0 bis 1."
        ))
        return true
    }
}
