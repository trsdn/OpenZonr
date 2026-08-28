import AppKit
import OpenZonrCore
import OpenZonrMac
import SwiftUI

/// What drops out of the menu bar icon.
///
/// Deliberately a plain `.menu`-style menu rather than a custom panel: the four
/// things this app has to offer — see the state, switch the profile, pause,
/// start at login — are exactly what a menu is for, and a menu is keyboard
/// navigable and legible at every text size without any work.
struct MenuContent: View {

    @Bindable var model: AppModel

    var body: some View {
        Section {
            Text("\(model.status.headline) — \(model.statusDetail)")
        }

        if model.status == .needsPermission {
            Button("Berechtigung einrichten …") { showStatusWindow() }
        }

        if model.status == .needsConfiguration {
            Button("Was fehlt? …") { showStatusWindow() }
        }

        Divider()

        profileMenu

        Toggle("Platzierung pausieren", isOn: $model.isPaused)
            .disabled(model.status == .needsPermission || model.status == .needsConfiguration)

        Divider()

        pinEntry

        Button("Regeln bearbeiten …") { showEditorWindow() }
            .disabled(model.configuration == nil)

        Divider()

        recentPlacements

        Divider()

        Toggle("Bei Anmeldung starten", isOn: Binding(
            get: { model.launchesAtLogin },
            set: { model.launchesAtLogin = $0 }
        ))

        Button("Status und Berechtigung …") { showStatusWindow() }
        Button("Konfiguration neu laden") { model.reloadConfiguration() }

        Divider()

        Button("OpenZonr beenden") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    // MARK: - Profile

    @ViewBuilder
    private var profileMenu: some View {
        if model.availableProfiles.isEmpty {
            Text("Keine Profile in der Konfiguration")
        } else {
            Menu("Profil") {
                Button {
                    model.selectProfile(nil)
                } label: {
                    // A checkmark is not available on a plain menu Button, so the
                    // marker is part of the title. Ugly in code, unambiguous on
                    // screen — and unlike a disabled item it stays clickable, so
                    // "back to automatic" is always one click away.
                    Text(marker(active: model.profileState?.isPinned == false) + "Automatisch")
                }
                Divider()
                ForEach(model.availableProfiles) { profile in
                    Button {
                        model.selectProfile(profile.id)
                    } label: {
                        Text(marker(active: model.activeProfile?.id == profile.id) + profile.name)
                    }
                }
            }
        }
    }

    private func marker(active: Bool) -> String {
        active ? "✓ " : "   "
    }

    // MARK: - Quick pin

    /// The 90 % case: „diese App immer hier öffnen“.
    ///
    /// The issue asks for a right click on the placed window. That is not
    /// reachable with public API — see ``FrontmostWindow`` for why — so the same
    /// intent is expressed from the menu: the user has already put the window
    /// where it belongs, this entry writes that down.
    @ViewBuilder
    private var pinEntry: some View {
        Button("Aktuelles Fenster hier festhalten") { model.pinFrontmostWindow() }
            .disabled(model.status == .needsPermission || model.configuration == nil)

        if let message = model.lastPinMessage {
            Text(message)
        }
    }

    // MARK: - Recent placements

    @ViewBuilder
    private var recentPlacements: some View {
        if model.records.isEmpty {
            Text("Noch keine Platzierung")
        } else {
            Menu("Letzte Platzierungen") {
                ForEach(model.records.prefix(8)) { record in
                    Text("\(record.applicationName) → \(record.target ?? "—") · \(record.summary)")
                }
                Divider()
                Button("Alle anzeigen …") { showActivityWindow() }
            }
        }
        Button("Letzte Platzierungen …") { showActivityWindow() }
    }

    // MARK: - Windows

    private func showStatusWindow() {
        model.refreshPermission(probe: true)
        PanelPresenter.shared.show(
            id: "status",
            title: "OpenZonr — Status und Berechtigung",
            size: NSSize(width: 620, height: 560)
        ) {
            StatusWindow(model: model)
        }
    }

    private func showActivityWindow() {
        PanelPresenter.shared.show(
            id: "activity",
            title: "OpenZonr — Letzte Platzierungen",
            size: NSSize(width: 720, height: 480)
        ) {
            ActivityWindow(model: model)
        }
    }

    private func showEditorWindow() {
        guard let document = model.editorDocument() else { return }
        PanelPresenter.shared.show(
            id: "editor",
            title: "OpenZonr — Regeln bearbeiten",
            size: NSSize(width: 900, height: 620)
        ) {
            EditorWindow(document: document)
        }
    }
}
