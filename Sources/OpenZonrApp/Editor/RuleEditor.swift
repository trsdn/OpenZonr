import OpenZonrCore
import SwiftUI

/// The rule list and the form for one rule.
///
/// The list is ordered the way the engine evaluates — priority descending — and
/// says so, because the single most confusing thing about this model is that
/// the first matching rule wins and everything below it never runs. Moving a
/// rule rewrites priorities so that the list is not a pretty view of the truth
/// but the truth itself.
struct RuleEditor: View {

    @Bindable var document: ConfigurationDocument
    @State private var selection: RuleID?

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 260, idealWidth: 300)
            detail
                .frame(minWidth: 380)
        }
    }

    private var rules: [PlacementRule] { document.configuration.rulesInEvaluationOrder }

    // MARK: - List

    private var list: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section {
                    ForEach(rules) { rule in
                        row(rule)
                            .tag(rule.id)
                    }
                } header: {
                    Text("Auswertungsreihenfolge — die erste passende Regel gewinnt")
                        .font(.caption)
                        .textCase(nil)
                }
            }
            Divider()
            toolbar
        }
    }

    private func row(_ rule: PlacementRule) -> some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { rule.enabled },
                set: { enabled in document.apply { $0.settingRule(rule.id, enabled: enabled) } }
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 1) {
                Text(rule.name)
                    .foregroundStyle(rule.enabled ? .primary : .secondary)
                Text(subtitle(of: rule))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            FindingBadge(path: .rule(rule.id), index: document.findings)
        }
    }

    private func subtitle(of rule: PlacementRule) -> String {
        let match = rule.match.bundleIdentifier ?? "jede App"
        let role = document.configuration.roles.first { $0.id == rule.action.role }?.name
            ?? rule.action.role.rawValue
        return "\(match) → \(role)"
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            Button {
                addRule()
            } label: {
                Image(systemName: "plus")
            }
            .help("Regel hinzufügen")

            Button {
                if let selection { document.apply { $0.removingRule(selection) } }
                selection = nil
            } label: {
                Image(systemName: "minus")
            }
            .disabled(selection == nil)
            .help("Regel entfernen")

            Divider().frame(height: 16)

            Button {
                if let selection { document.apply { $0.movingRule(selection, by: -1) } }
            } label: {
                Image(systemName: "chevron.up")
            }
            .disabled(selection == nil)
            .help("Früher auswerten")

            Button {
                if let selection { document.apply { $0.movingRule(selection, by: 1) } }
            } label: {
                Image(systemName: "chevron.down")
            }
            .disabled(selection == nil)
            .help("Später auswerten")

            Spacer()
        }
        .buttonStyle(.borderless)
        .padding(8)
    }

    private func addRule() {
        let id = document.configuration.availableRuleID(basedOn: "Neue Regel")
        let role = document.configuration.roles.first?.id ?? "rolle"
        let priority = (document.configuration.rules.map(\.priority).max() ?? 0) + Configuration.rulePriorityStep
        document.apply {
            $0.adding(rule: PlacementRule(
                id: id,
                name: "Neue Regel",
                priority: priority,
                match: WindowMatch(),
                action: PlacementAction(role: role)
            ))
        }
        selection = id
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let selection, let rule = document.configuration.rules.first(where: { $0.id == selection }) {
            RuleForm(document: document, rule: rule)
                .id(rule.id)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
                Text("Keine Regel gewählt")
                    .font(.headline)
                Text("""
                Eine Regel beschreibt, welche Fenster wohin gehören. Für den \
                Normalfall genügt „Aktuelles Fenster hier festhalten“ im Menü — \
                hier stehen die Fälle, für die das nicht reicht.
                """)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The form for one rule.
private struct RuleForm: View {

    @Bindable var document: ConfigurationDocument
    let rule: PlacementRule

    var body: some View {
        Form {
            Section("Regel") {
                TextField("Name", text: binding(\.name))
                LabeledContent("Kennung") {
                    Text(rule.id.rawValue)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Toggle("Aktiv", isOn: binding(\.enabled))
                LabeledContent("Priorität") {
                    Text("\(rule.priority)")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Wann greift sie?") {
                OptionalTextField(
                    title: "Bundle-Kennung",
                    prompt: "com.microsoft.Outlook",
                    path: .ruleMatch(rule.id).field("bundleIdentifier"),
                    index: document.findings,
                    value: optionalBinding(\.match.bundleIdentifier)
                )
                OptionalTextField(
                    title: "Titelmuster",
                    prompt: "^Posteingang",
                    path: .ruleMatch(rule.id).field("titlePattern"),
                    index: document.findings,
                    value: optionalBinding(\.match.titlePattern)
                )
                Picker("Erstes Fenster nach Start", selection: Binding(
                    get: { rule.match.onlyFirstWindowAfterLaunch },
                    set: { value in update { $0.match.onlyFirstWindowAfterLaunch = value } }
                )) {
                    Text("Voreinstellung (\(document.configuration.defaults.onlyFirstWindowAfterLaunch ? "nur erstes" : "jedes"))")
                        .tag(Bool?.none)
                    Text("Nur das erste").tag(Bool?.some(true))
                    Text("Jedes Fenster").tag(Bool?.some(false))
                }
                sizeFields
            }

            Section("Wohin?") {
                Picker("Rolle", selection: Binding(
                    get: { rule.action.role },
                    set: { role in update { $0.action.role = role } }
                )) {
                    ForEach(document.configuration.roles) { role in
                        Text(role.name).tag(role.id)
                    }
                }
                FieldFindings(path: .ruleAction(rule.id).field("role"), index: document.findings)

                Picker("Beim Platzieren", selection: Binding(
                    get: { rule.action.mode ?? .place },
                    set: { mode in update { $0.action.mode = mode } }
                )) {
                    Text("Fenster verschieben").tag(PlacementMode.place)
                    Text("Nur vorschlagen").tag(PlacementMode.suggest)
                }
                Picker("Fokus", selection: Binding(
                    get: { rule.action.focus ?? .leaveAsIs },
                    set: { focus in update { $0.action.focus = focus } }
                )) {
                    Text("Vordergrund unverändert lassen").tag(FocusBehavior.leaveAsIs)
                    Text("Fenster nach vorne holen").tag(FocusBehavior.activate)
                }
            }

            if !document.findings.findings(under: .rule(rule.id)).isEmpty {
                Section("Befunde zu dieser Regel") {
                    ForEach(document.findings.findings(under: .rule(rule.id)), id: \.self) { finding in
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(finding.message)
                                Text(finding.path.description)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: finding.severity.symbolName)
                                .foregroundStyle(finding.severity.tint)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var sizeFields: some View {
        LabeledContent("Mindestgröße") {
            HStack(spacing: 6) {
                TextField("Breite", value: Binding(
                    get: { rule.match.minimumSize?.width ?? 0 },
                    set: { width in
                        let height = rule.match.minimumSize?.height ?? 0
                        update { $0.match.minimumSize = size(width: width, height: height) }
                    }
                ), format: .number)
                .frame(width: 70)
                Text("×")
                TextField("Höhe", value: Binding(
                    get: { rule.match.minimumSize?.height ?? 0 },
                    set: { height in
                        let width = rule.match.minimumSize?.width ?? 0
                        update { $0.match.minimumSize = size(width: width, height: height) }
                    }
                ), format: .number)
                .frame(width: 70)
                Text("pt").foregroundStyle(.secondary)
            }
        }
        FieldFindings(path: .ruleMatch(rule.id).field("minimumSize"), index: document.findings)
    }

    /// `0 × 0` means "no size criterion", which is what an empty field should do.
    private func size(width: Double, height: Double) -> WindowSize? {
        (width <= 0 && height <= 0) ? nil : WindowSize(width: width, height: height)
    }

    // MARK: - Bindings

    private func update(_ mutate: (inout PlacementRule) -> Void) {
        guard var edited = document.configuration.rules.first(where: { $0.id == rule.id }) else { return }
        mutate(&edited)
        document.apply { $0.updating(rule: edited) }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<PlacementRule, Value>) -> Binding<Value> {
        Binding(
            get: { rule[keyPath: keyPath] },
            set: { newValue in update { $0[keyPath: keyPath] = newValue } }
        )
    }

    private func optionalBinding(_ keyPath: WritableKeyPath<PlacementRule, String?>) -> Binding<String?> {
        Binding(
            get: { rule[keyPath: keyPath] },
            set: { newValue in update { $0[keyPath: keyPath] = newValue } }
        )
    }
}
