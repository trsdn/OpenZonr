import Foundation

/// Every change the rule editor can make to a configuration, as pure functions.
///
/// The operations live here rather than in the user interface for one reason:
/// this is the layer that can be proven without a screen, without the
/// Accessibility permission and without a window server. The editor window is
/// then a thin thing that calls these and hands the result to
/// ``ConfigurationStore``.
///
/// Nothing here validates. Refusing an edit because the intermediate state is
/// invalid would make the editor unusable — half-typed input is invalid by
/// definition. ``ConfigurationValidator`` runs *after* every edit and the
/// findings are shown at the field they belong to; that is the whole design.
extension Configuration {

    // MARK: - Rules

    /// The rules in the order they are actually evaluated: priority descending,
    /// ties broken by position in the file.
    ///
    /// The editor shows this order, never the raw array. A list that claims to
    /// be "the order" while the engine uses another one is a lie the user pays
    /// for later.
    public var rulesInEvaluationOrder: [PlacementRule] {
        rules.enumerated()
            .sorted { lhs, rhs in
                if lhs.element.priority != rhs.element.priority {
                    return lhs.element.priority > rhs.element.priority
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    /// Distance between two neighbouring priorities after a reorder.
    ///
    /// Ten, not one: it leaves room to slip a hand-written rule in between two
    /// generated ones without renumbering the file.
    public static let rulePriorityStep = 10

    /// Returns a copy whose rule array is in evaluation order and whose
    /// priorities descend in steps of ``rulePriorityStep``.
    ///
    /// Applied after every reorder, so that what the list shows and what the
    /// engine does cannot drift apart. It is deliberately *not* applied when the
    /// editor merely opens a file: rewriting priorities nobody asked to change
    /// would turn opening a window into a diff.
    public func normalisingRuleOrder() -> Configuration {
        renumbering(rulesInEvaluationOrder)
    }

    /// Returns a copy whose rule array is exactly `ordered`, with priorities
    /// descending in steps of ``rulePriorityStep``.
    ///
    /// Separate from ``normalisingRuleOrder()`` on purpose, and the separation
    /// was worth a failing test: sorting by priority *after* a reorder undoes
    /// the reorder, because the priorities still describe the old order.
    private func renumbering(_ ordered: [PlacementRule]) -> Configuration {
        var copy = self
        copy.rules = ordered.enumerated().map { index, rule in
            var rule = rule
            rule.priority = (ordered.count - index) * Configuration.rulePriorityStep
            return rule
        }
        return copy
    }

    /// Returns a copy with `rule` appended, keeping its priority.
    public func adding(rule: PlacementRule) -> Configuration {
        var copy = self
        copy.rules.append(rule)
        return copy
    }

    /// Returns a copy in which the rule with the same identifier is replaced.
    ///
    /// Unknown identifiers are ignored rather than trapped: the editor and the
    /// file can disagree for a moment when the file changed underneath, and
    /// crashing over it would lose the user's work.
    public func updating(rule: PlacementRule) -> Configuration {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return self }
        var copy = self
        copy.rules[index] = rule
        return copy
    }

    /// Returns a copy without the rule `id`.
    public func removingRule(_ id: RuleID) -> Configuration {
        var copy = self
        copy.rules.removeAll { $0.id == id }
        return copy
    }

    /// Returns a copy in which rule `id` sits at `index` of the evaluation
    /// order, with all priorities renumbered to match.
    public func movingRule(_ id: RuleID, to index: Int) -> Configuration {
        var ordered = rulesInEvaluationOrder
        guard let current = ordered.firstIndex(where: { $0.id == id }) else { return self }

        let rule = ordered.remove(at: current)
        ordered.insert(rule, at: min(max(index, 0), ordered.count))
        return renumbering(ordered)
    }

    /// Returns a copy in which rule `id` moved one position earlier or later in
    /// the evaluation order.
    public func movingRule(_ id: RuleID, by offset: Int) -> Configuration {
        guard let current = rulesInEvaluationOrder.firstIndex(where: { $0.id == id }) else { return self }
        return movingRule(id, to: current + offset)
    }

    /// Returns a copy in which rule `id` is enabled or disabled.
    public func settingRule(_ id: RuleID, enabled: Bool) -> Configuration {
        guard var rule = rules.first(where: { $0.id == id }) else { return self }
        rule.enabled = enabled
        return updating(rule: rule)
    }

    /// A rule identifier that is free in this configuration.
    public func availableRuleID(basedOn name: String) -> RuleID {
        IdentifierFactory.unique(name, taken: rules.map(\.id), fallback: "regel")
    }

    // MARK: - Roles

    public func adding(role: ZoneRole) -> Configuration {
        var copy = self
        copy.roles.append(role)
        return copy
    }

    public func updating(role: ZoneRole) -> Configuration {
        guard let index = roles.firstIndex(where: { $0.id == role.id }) else { return self }
        var copy = self
        copy.roles[index] = role
        return copy
    }

    /// Returns a copy without role `id` and without the bindings that pointed at
    /// it.
    ///
    /// The bindings go too, because a binding for a role that no longer exists
    /// is dead weight the validator cannot even complain about — a binding names
    /// its role, and an unknown role in a binding is not one of the checks.
    /// Rules keep their reference on purpose: that *is* a check
    /// (``ValidationCode/unknownRoleInRule``), and it points the user at the
    /// rules that now need a decision instead of silently rewriting them.
    public func removingRole(_ id: RoleID) -> Configuration {
        var copy = self
        copy.roles.removeAll { $0.id == id }
        copy.profiles = copy.profiles.map { profile in
            var profile = profile
            profile.roleBindings.removeAll { $0.role == id }
            return profile
        }
        return copy
    }

    public func availableRoleID(basedOn name: String) -> RoleID {
        IdentifierFactory.unique(name, taken: roles.map(\.id), fallback: "rolle")
    }

    // MARK: - Role bindings

    /// Returns a copy in which `binding` is the binding for its role in
    /// `profile`, replacing an existing one.
    public func setting(binding: RoleBinding, inProfile profile: ProfileID) -> Configuration {
        guard let index = profiles.firstIndex(where: { $0.id == profile }) else { return self }
        var copy = self
        if let existing = copy.profiles[index].roleBindings.firstIndex(where: { $0.role == binding.role }) {
            copy.profiles[index].roleBindings[existing] = binding
        } else {
            copy.profiles[index].roleBindings.append(binding)
        }
        return copy
    }

    public func removingBinding(role: RoleID, fromProfile profile: ProfileID) -> Configuration {
        guard let index = profiles.firstIndex(where: { $0.id == profile }) else { return self }
        var copy = self
        copy.profiles[index].roleBindings.removeAll { $0.role == role }
        return copy
    }

    public func setting(fallback: RoleBinding, inProfile profile: ProfileID) -> Configuration {
        guard let index = profiles.firstIndex(where: { $0.id == profile }) else { return self }
        var copy = self
        copy.profiles[index].fallback = fallback
        return copy
    }

    /// Returns a copy in which `profile` uses `layout` on `display`.
    public func setting(layout: LayoutID, forDisplay display: DisplayAlias, inProfile profile: ProfileID) -> Configuration {
        guard let index = profiles.firstIndex(where: { $0.id == profile }) else { return self }
        var copy = self
        copy.profiles[index].layouts[display] = layout
        return copy
    }

    /// The layout `profile` uses on `display`, falling back to the display's
    /// default — the same resolution ``DefaultZoneResolver`` performs.
    public func layoutID(forDisplay display: DisplayAlias, inProfile profile: ProfileID) -> LayoutID? {
        guard let descriptor = displays.first(where: { $0.alias == display }) else { return nil }
        guard let profile = profiles.first(where: { $0.id == profile }) else { return descriptor.defaultLayoutID }
        return profile.layouts[display] ?? descriptor.defaultLayoutID
    }

    /// The layout `profile` uses on `display`, resolved to the layout itself.
    public func layout(forDisplay display: DisplayAlias, inProfile profile: ProfileID) -> Layout? {
        guard
            let descriptor = displays.first(where: { $0.alias == display }),
            let id = layoutID(forDisplay: display, inProfile: profile)
        else { return nil }
        return descriptor.layouts.first { $0.id == id }
    }

    // MARK: - Zones

    /// Returns a copy in which the geometry of one zone changed.
    ///
    /// This is what the zone editor calls on every drag step, so it does the
    /// least possible work and leaves clamping to the caller — a zone dragged
    /// past the edge should snap back visibly, not be silently corrected while
    /// the mouse is still down.
    public func settingZoneFrame(
        _ frame: RelativeRect,
        zone: ZoneID,
        layout: LayoutID,
        display: DisplayAlias
    ) -> Configuration {
        mutatingZones(layout: layout, display: display) { zones in
            guard let index = zones.firstIndex(where: { $0.id == zone }) else { return }
            zones[index].frame = frame
        }
    }

    public func updating(zone: Zone, layout: LayoutID, display: DisplayAlias) -> Configuration {
        mutatingZones(layout: layout, display: display) { zones in
            guard let index = zones.firstIndex(where: { $0.id == zone.id }) else { return }
            zones[index] = zone
        }
    }

    public func adding(zone: Zone, layout: LayoutID, display: DisplayAlias) -> Configuration {
        mutatingZones(layout: layout, display: display) { zones in
            zones.append(zone)
        }
    }

    /// Returns a copy without zone `id`.
    ///
    /// Bindings pointing at the zone are left alone deliberately: removing them
    /// would silently move every app of that role to the profile's fallback,
    /// while leaving them produces ``ValidationCode/unknownZoneInBinding`` at
    /// exactly the binding that now needs a decision.
    public func removingZone(_ id: ZoneID, layout: LayoutID, display: DisplayAlias) -> Configuration {
        mutatingZones(layout: layout, display: display) { zones in
            zones.removeAll { $0.id == id }
        }
    }

    /// A zone identifier that is free within one layout.
    public func availableZoneID(basedOn name: String, layout: LayoutID, display: DisplayAlias) -> ZoneID {
        let taken = displays
            .first { $0.alias == display }?
            .layouts.first { $0.id == layout }?
            .zones.map(\.id) ?? []
        return IdentifierFactory.unique(name, taken: taken, fallback: "zone")
    }

    private func mutatingZones(
        layout: LayoutID,
        display: DisplayAlias,
        _ mutate: (inout [Zone]) -> Void
    ) -> Configuration {
        guard
            let displayIndex = displays.firstIndex(where: { $0.alias == display }),
            let layoutIndex = displays[displayIndex].layouts.firstIndex(where: { $0.id == layout })
        else { return self }

        var copy = self
        mutate(&copy.displays[displayIndex].layouts[layoutIndex].zones)
        return copy
    }
}
