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

        Toggle("Fenster in Zonen ziehen", isOn: Binding(
            get: { model.dropzonesEnabled },
            set: { model.dropzonesEnabled = $0 }
        ))
        .disabled(model.status == .needsPermission || model.configuration == nil)

        if let problem = model.dropzones.problem {
            Text("Ziehen ist nicht aktiv: \(problem)")
        }

        competingManagers

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

        updateEntries

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
    /// Seit Issue #27 gibt es zwei Wege: der Menüleisten-Eintrag hier und ein
    /// Rechtsklick auf den grünen Fensterknopf (siehe ``ZoomButtonMenu``).
    /// Beide gehen durch denselben ``QuickPin``, keine zweite Buchhaltung.
    /// Der Menüleisten-Weg bleibt, weil er tastaturbedienbar ist und ohne
    /// Zeiger auskommt — bei einem Fenster, das gerade wo anders hin will,
    /// aber die App-Zuordnung schon steht, ist er kürzer als „raus zum
    /// grünen Knopf".
    /// Says out loud that another window manager is running.
    ///
    /// OpenZonr does not try to win against it. Two tools that both show an
    /// overlay while dragging produce a result the user cannot predict, and the
    /// honest move is to say so once rather than to fight silently — see
    /// docs/dropzones.md.
    @ViewBuilder
    private var competingManagers: some View {
        let running = model.competingWindowManagers
        if !running.isEmpty {
            Text(CompetingWindowManagers.warning(for: running) ?? "")
        }
    }

    @ViewBuilder
    private var pinEntry: some View {
        Button("Aktuelles Fenster hier festhalten") { model.pinFrontmostWindow() }
            .disabled(model.status == .needsPermission || model.configuration == nil)

        if let message = model.lastPinMessage {
            Text(message)
        }
    }

    // MARK: - Updates

    /// Suchen, der Zustand und der Schalter — in dieser Reihenfolge.
    ///
    /// Die Zustandszeile steht oben und ist sichtbar, sobald es etwas zu sagen
    /// gibt. Das ist der Unterschied zu einem Knopf, der nur nach dem Klick
    /// antwortet: ein Update, das im Hintergrund gefunden und geladen wurde,
    /// muss sich zeigen, ohne dass jemand danach sucht.
    @ViewBuilder
    private var updateEntries: some View {
        let updates = model.updates

        if let line = UpdatePolicy.statusLine(for: updates.state) {
            Text(line)
        }

        if let title = UpdatePolicy.installTitle(for: updates.state) {
            Button(title) { installUpdate() }
            Button("Später") { Task { await updates.dismiss() } }
        }

        Button("Nach Updates suchen …") { checkForUpdates() }
            .disabled(updates.isBusy || updates.hasPreparedUpdate)

        Toggle("Automatisch nach Updates suchen", isOn: Binding(
            get: { updates.automaticChecksEnabled },
            set: { updates.automaticChecksEnabled = $0 }
        ))
    }

    /// Das Menü schliesst sich beim Klick. Die Antwort auf eine Suche, die der
    /// Nutzer angestossen hat, kommt deshalb als Hinweisfenster — eine Zeile in
    /// einem Menü, das niemand wieder aufklappt, wäre keine Antwort.
    private func checkForUpdates() {
        Task {
            let updates = model.updates
            await updates.check(userInitiated: true)
            switch updates.state {
            case .upToDate:
                present(title: "OpenZonr ist aktuell", message: "Es läuft die neueste Fassung.")
            case let .failed(message):
                present(title: "Update-Suche fehlgeschlagen", message: message)
            case let .readyToInstall(version):
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = "OpenZonr \(version) liegt bereit"
                alert.informativeText = """
                    OpenZonr hält die Fensterbeobachtung an, tauscht sich aus und startet neu. \
                    Für ein paar Sekunden wird kein Fenster platziert.
                    """
                alert.addButton(withTitle: "Installieren und neu starten")
                alert.addButton(withTitle: "Später")
                if alert.runModal() == .alertFirstButtonReturn { installUpdate() }
            case .idle, .checking, .downloading, .installing:
                break
            }
        }
    }

    /// Anhalten und tauschen — die Reihenfolge steckt in
    /// ``AppModel/installUpdate()``, damit sie prüfbar ist.
    private func installUpdate() {
        Task {
            if await model.installUpdate() { return }
            if case let .failed(message) = model.updates.state {
                present(title: "Update konnte nicht installiert werden", message: message)
            }
        }
    }

    private func present(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
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
