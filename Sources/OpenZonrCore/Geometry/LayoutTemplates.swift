import Foundation

/// Ready-made zone sets for the usual splits.
///
/// The editor offers them as templates so the path from *"I want three
/// columns"* to *three cleanly-closing rectangles* does not run through eight
/// numbers. The existing example configuration `c49rg9x-three-columns` is a
/// **hand-built 25/50/25** — the argument that templates are needed comes
/// from the project itself.
///
/// Every template sits on the twelfths or twentieths grid and so closes
/// without a seam. The zone IDs are stable: `applying` replaces a layout's
/// zones completely, and applying a template twice yields the same IDs
/// twice — otherwise bindings would silently point at nothing, with nobody
/// having touched them.
public enum LayoutTemplate: String, CaseIterable, Sendable {

    /// Two equally wide columns: 6/12 left, 6/12 right.
    case halves = "halves"
    /// Three equally wide columns: 4/12 · 4/12 · 4/12.
    case thirds = "thirds"
    /// Four equally wide columns: 3/12 · 3/12 · 3/12 · 3/12.
    case quarters = "quarters"
    /// Three columns 25 · 50 · 25 — the existing configuration, in numbers.
    case twentyFiveFiftyTwentyFive = "twenty-five-fifty-twenty-five"
    /// Five equally wide columns — on 5120 px, thirds are 1706 px windows,
    /// too wide for the usual window sizes.
    case fifths = "fifths"

    /// Caption for the menu.
    public var displayName: String {
        switch self {
        case .halves: return L.string("layoutTemplate.displayName.halves", "Halves")
        case .thirds: return L.string("layoutTemplate.displayName.thirds", "Thirds")
        case .quarters: return L.string("layoutTemplate.displayName.quarters", "Quarters")
        case .twentyFiveFiftyTwentyFive: return "25 · 50 · 25"
        case .fifths: return L.string("layoutTemplate.displayName.fifths", "Fifths")
        }
    }

    /// The template's zones in the unit square, in reading order.
    public var zones: [Zone] {
        switch self {
        case .halves:
            return [
                zone("halves-left", L.string("layoutTemplate.zone.left", "Left"), 0, 0, 6.0 / 12, 1),
                zone("halves-right", L.string("layoutTemplate.zone.right", "Right"), 6.0 / 12, 0, 6.0 / 12, 1),
            ]
        case .thirds:
            return [
                zone("thirds-left", L.string("layoutTemplate.zone.left", "Left"), 0, 0, 4.0 / 12, 1),
                zone("thirds-center", L.string("layoutTemplate.zone.center", "Center"), 4.0 / 12, 0, 4.0 / 12, 1),
                zone("thirds-right", L.string("layoutTemplate.zone.right", "Right"), 8.0 / 12, 0, 4.0 / 12, 1),
            ]
        case .quarters:
            return [
                zone("quarters-1", L.string("layoutTemplate.zone.quarter.1", "First quarter"), 0, 0, 3.0 / 12, 1),
                zone(
                    "quarters-2", L.string("layoutTemplate.zone.quarter.2", "Second quarter"),
                    3.0 / 12, 0, 3.0 / 12, 1
                ),
                zone(
                    "quarters-3", L.string("layoutTemplate.zone.quarter.3", "Third quarter"),
                    6.0 / 12, 0, 3.0 / 12, 1
                ),
                zone(
                    "quarters-4", L.string("layoutTemplate.zone.quarter.4", "Fourth quarter"),
                    9.0 / 12, 0, 3.0 / 12, 1
                ),
            ]
        case .twentyFiveFiftyTwentyFive:
            return [
                zone("wide-left", L.string("layoutTemplate.zone.left", "Left"), 0, 0, 0.25, 1),
                zone("wide-center", L.string("layoutTemplate.zone.center", "Center"), 0.25, 0, 0.5, 1),
                zone("wide-right", L.string("layoutTemplate.zone.right", "Right"), 0.75, 0, 0.25, 1),
            ]
        case .fifths:
            return [
                zone("fifths-1", L.string("layoutTemplate.zone.fifth.1", "First fifth"), 0, 0, 0.2, 1),
                zone("fifths-2", L.string("layoutTemplate.zone.fifth.2", "Second fifth"), 0.2, 0, 0.2, 1),
                zone("fifths-3", L.string("layoutTemplate.zone.fifth.3", "Third fifth"), 0.4, 0, 0.2, 1),
                zone("fifths-4", L.string("layoutTemplate.zone.fifth.4", "Fourth fifth"), 0.6, 0, 0.2, 1),
                zone("fifths-5", L.string("layoutTemplate.zone.fifth.5", "Fifth fifth"), 0.8, 0, 0.2, 1),
            ]
        }
    }

    private func zone(_ id: String, _ name: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Zone {
        Zone(id: ZoneID(rawValue: id), name: name, frame: RelativeRect(x: x, y: y, width: w, height: h))
    }
}

/// Effects of applying a template, shown to the user *beforehand*.
///
/// The editor already reports dangling bindings as a finding
/// (``ValidationCode/unknownZoneInBinding``) once they exist. For a template
/// that is too late — it replaces existing zones in one stroke.
/// ``PreviewedApplication`` says, before the application, which bindings
/// would then point at nothing, so whoever reads it decides with open eyes.
public struct LayoutTemplatePreview: Hashable, Sendable {

    /// Zone IDs that would disappear.
    public var removedZones: [ZoneID]

    /// Bindings that would report ``unknownZoneInBinding`` after the
    /// application.
    ///
    /// One entry per role only, because the data model allows at most one
    /// binding per role per profile — and this preview value comes from the
    /// same binding list.
    public var danglingBindings: [DanglingBinding]

    public init(removedZones: [ZoneID], danglingBindings: [DanglingBinding]) {
        self.removedZones = removedZones
        self.danglingBindings = danglingBindings
    }

    public struct DanglingBinding: Hashable, Sendable {
        public var profile: ProfileID
        public var role: RoleID
        public var display: DisplayAlias
        public var zone: ZoneID

        public init(profile: ProfileID, role: RoleID, display: DisplayAlias, zone: ZoneID) {
            self.profile = profile
            self.role = role
            self.display = display
            self.zone = zone
        }
    }
}

extension Configuration {

    /// Which bindings applying `template` would break by pointing at nothing.
    ///
    /// A plain comparison of zone IDs: every ID that **no longer** appears
    /// in the new layout is removed; every role binding that names such an
    /// ID on this display would then dangle.
    ///
    /// The function changes nothing. The editor calls it before the
    /// application, shows the list, and the user decides.
    public func previewApplying(
        template: LayoutTemplate,
        layout: LayoutID,
        display: DisplayAlias
    ) -> LayoutTemplatePreview {
        let existing = displays
            .first { $0.alias == display }?
            .layouts.first { $0.id == layout }?
            .zones.map(\.id) ?? []
        let newIDs = Set(template.zones.map(\.id))
        let removed = existing.filter { !newIDs.contains($0) }
        let removedSet = Set(removed)

        var dangling: [LayoutTemplatePreview.DanglingBinding] = []
        for profile in profiles where (profile.layouts[display] ?? layoutID(forDisplay: display, inProfile: profile.id)) == layout {
            for binding in profile.roleBindings where binding.display == display && removedSet.contains(binding.zone) {
                dangling.append(
                    LayoutTemplatePreview.DanglingBinding(
                        profile: profile.id,
                        role: binding.role,
                        display: display,
                        zone: binding.zone
                    )
                )
            }
        }
        return LayoutTemplatePreview(removedZones: removed, danglingBindings: dangling)
    }

    /// Replaces a layout's zones completely with the template's.
    ///
    /// Bindings are not carried along. Applying a template for which
    /// `previewApplying(template:…)` previously reported dangling bindings
    /// afterwards gets exactly those bindings reported as
    /// ``ValidationCode/unknownZoneInBinding`` — the intended chain: the
    /// preview shows it, validation records it, the sidebar badges make it
    /// visible.
    public func applying(
        template: LayoutTemplate,
        layout: LayoutID,
        display: DisplayAlias
    ) -> Configuration {
        guard
            let displayIndex = displays.firstIndex(where: { $0.alias == display }),
            let layoutIndex = displays[displayIndex].layouts.firstIndex(where: { $0.id == layout })
        else { return self }
        var copy = self
        copy.displays[displayIndex].layouts[layoutIndex].zones = template.zones
        return copy
    }
}
