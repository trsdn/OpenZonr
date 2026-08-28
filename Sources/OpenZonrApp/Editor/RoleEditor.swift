import OpenZonrCore
import SwiftUI

/// Roles, and where each role sits in each profile.
///
/// The split between rule → role → zone is the one concept the configuration
/// asks the user to learn, and it exists for a reason: „Mail“ means the right
/// half at the desk and the whole screen on the laptop. The editor therefore
/// shows a role's bindings as one row per profile rather than hiding them in a
/// separate list — the question is always "and where is that here?".
struct RoleEditor: View {

    @Bindable var document: ConfigurationDocument
    @State private var selection: RoleID?

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 220, idealWidth: 240)
            detail
                .frame(minWidth: 420)
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(document.configuration.roles) { role in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(role.name)
                            Text(role.id.rawValue)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        FindingBadge(path: .role(role.id), index: document.findings)
                    }
                    .tag(role.id)
                }
            }
            Divider()
            HStack(spacing: 6) {
                Button {
                    addRole()
                } label: { Image(systemName: "plus") }
                    .help("Rolle hinzufügen")
                Button {
                    if let selection { document.apply { $0.removingRole(selection) } }
                    selection = nil
                } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)
                    .help("Rolle entfernen — Regeln, die sie nutzen, bleiben stehen und werden als Befund gemeldet")
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    private func addRole() {
        let id = document.configuration.availableRoleID(basedOn: "Neue Rolle")
        document.apply { $0.adding(role: ZoneRole(id: id, name: "Neue Rolle")) }
        selection = id
    }

    @ViewBuilder
    private var detail: some View {
        if let selection, let role = document.configuration.roles.first(where: { $0.id == selection }) {
            RoleForm(document: document, role: role)
                .id(role.id)
        } else {
            ContentUnavailableMessage(
                symbol: "square.grid.2x2",
                title: "Keine Rolle gewählt",
                message: """
                Eine Rolle ist ein Platz mit Namen — „Mail“, „Notizen“. Wo dieser \
                Platz liegt, entscheidet jedes Profil für sich.
                """
            )
        }
    }
}

private struct RoleForm: View {

    @Bindable var document: ConfigurationDocument
    let role: ZoneRole

    var body: some View {
        Form {
            Section("Rolle") {
                TextField("Name", text: Binding(
                    get: { role.name },
                    set: { name in update { $0.name = name } }
                ))
                LabeledContent("Kennung") {
                    Text(role.id.rawValue)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                OptionalTextField(
                    title: "Notiz",
                    prompt: "Wofür ist dieser Platz da?",
                    path: .role(role.id).field("summary"),
                    index: document.findings,
                    value: Binding(
                        get: { role.summary },
                        set: { summary in update { $0.summary = summary } }
                    )
                )
                FieldFindings(path: .role(role.id), index: document.findings)
            }

            Section("Wo liegt sie?") {
                ForEach(document.configuration.profiles) { profile in
                    BindingRow(document: document, profile: profile, role: role.id)
                }
            }

            Section("Auffangregel je Profil") {
                Text("Wohin Fenster gehen, für die keine Regel greift.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(document.configuration.profiles) { profile in
                    FallbackRow(document: document, profile: profile)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func update(_ mutate: (inout ZoneRole) -> Void) {
        guard var edited = document.configuration.roles.first(where: { $0.id == role.id }) else { return }
        mutate(&edited)
        document.apply { $0.updating(role: edited) }
    }
}

/// One profile's answer to "where does this role sit here?".
private struct BindingRow: View {

    @Bindable var document: ConfigurationDocument
    let profile: Profile
    let role: RoleID

    var body: some View {
        let index = profile.roleBindings.firstIndex { $0.role == role }
        let binding = index.map { profile.roleBindings[$0] }

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(profile.name)
                    .frame(width: 120, alignment: .leading)
                ZoneTargetPicker(
                    document: document,
                    profile: profile.id,
                    display: binding?.display,
                    zone: binding?.zone
                ) { display, zone in
                    document.apply {
                        $0.setting(
                            binding: RoleBinding(role: role, display: display, zone: zone),
                            inProfile: profile.id
                        )
                    }
                }
                if binding != nil {
                    Button {
                        document.apply { $0.removingBinding(role: role, fromProfile: profile.id) }
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Bindung entfernen")
                }
            }
            if let index {
                FieldFindings(path: .roleBinding(profile.id, at: index).field("display"), index: document.findings)
                FieldFindings(path: .roleBinding(profile.id, at: index).field("zone"), index: document.findings)
            }
        }
    }
}

private struct FallbackRow: View {

    @Bindable var document: ConfigurationDocument
    let profile: Profile

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(profile.name)
                    .frame(width: 120, alignment: .leading)
                ZoneTargetPicker(
                    document: document,
                    profile: profile.id,
                    display: profile.fallback.display,
                    zone: profile.fallback.zone
                ) { display, zone in
                    var fallback = profile.fallback
                    fallback.display = display
                    fallback.zone = zone
                    document.apply { $0.setting(fallback: fallback, inProfile: profile.id) }
                }
            }
            FieldFindings(path: .profileFallback(profile.id).field("display"), index: document.findings)
            FieldFindings(path: .profileFallback(profile.id).field("zone"), index: document.findings)
        }
    }
}

/// Display and zone in one control.
///
/// One picker rather than two, because a zone identifier only means anything
/// together with the display whose layout defines it — two independent pickers
/// would let the user build a combination that cannot exist.
struct ZoneTargetPicker: View {

    @Bindable var document: ConfigurationDocument
    let profile: ProfileID
    let display: DisplayAlias?
    let zone: ZoneID?
    let onChange: (DisplayAlias, ZoneID) -> Void

    var body: some View {
        Picker("", selection: Binding(
            get: { display.flatMap { d in zone.map { Selection(display: d, zone: $0) } } },
            set: { selection in
                if let selection { onChange(selection.display, selection.zone) }
            }
        )) {
            if display == nil || zone == nil {
                Text("— nicht gesetzt —").tag(Selection?.none)
            }
            ForEach(document.configuration.displays) { descriptor in
                if let layout = document.configuration.layout(forDisplay: descriptor.alias, inProfile: profile) {
                    Section(descriptor.displayName) {
                        ForEach(layout.zones) { zone in
                            Text(zone.name)
                                .tag(Selection?.some(Selection(display: descriptor.alias, zone: zone.id)))
                        }
                    }
                }
            }
            // A binding may point at a zone the layout no longer has. Showing it
            // keeps the picker honest instead of silently displaying the first
            // entry as if it were the stored value.
            if let display, let zone, !isKnown(display: display, zone: zone) {
                Text("\(zone.rawValue) (unbekannt)")
                    .tag(Selection?.some(Selection(display: display, zone: zone)))
            }
        }
        .labelsHidden()
    }

    private func isKnown(display: DisplayAlias, zone: ZoneID) -> Bool {
        document.configuration
            .layout(forDisplay: display, inProfile: profile)?
            .zones.contains { $0.id == zone } ?? false
    }

    struct Selection: Hashable {
        var display: DisplayAlias
        var zone: ZoneID
    }
}

/// A small stand-in for `ContentUnavailableView`, which is not available on the
/// deployment target this package builds against.
struct ContentUnavailableMessage: View {

    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 380)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
