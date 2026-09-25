import AppKit
import OpenZonrCore
import OpenZonrMac
import SwiftUI

/// What drops out of the menu bar icon.
///
/// Deliberately a plain `.menu`-style menu rather than a custom panel: a menu is
/// keyboard navigable and legible at every text size without any work.
///
/// ## Der Umbau
///
/// Die erste Fassung war nach dem Programm sortiert, nicht nach dem Nutzer: sie
/// zeigte Zustandsnamen („Kein Profil passt — 2 Profile in der Konfiguration“),
/// stellte den Ein/Aus-Schalter fürs Ziehen neben eine Aktivierungsregel, die
/// nirgends sichtbar war, und mischte Seltenes (Konfiguration neu laden,
/// Update-Schalter) unter Alltägliches. Jetzt gilt eine Reihenfolge:
///
/// 1. **Kopfzeile** — Name und Fassung, in jedem Zustand als Erstes (Issue #56).
/// 2. **Eine Zustandszeile** in Alltagssprache, mit höchstens einem Knopf.
/// 3. **Was Aufmerksamkeit verlangt** — ein bereitliegendes Update, ein zweiter
///    Fenstermanager. Beides bleibt oben, weil beides eine Entscheidung will.
/// 4. **Die zwei Schalter**, die man wirklich umlegt.
/// 5. **Der letzte Zug** als grauer Satz: Diagnose für einen offenen Fehler.
/// 6. **Zwei Handlungen**: festhalten, bearbeiten.
/// 7. **„Mehr“** für alles Technische und Seltene.
/// 8. **Beenden**.
///
/// Nichts ist weggefallen; alles Seltene ist einen Schritt tiefer gerutscht.
struct MenuContent: View {

    @Bindable var model: AppModel

    private var statusLine: MenuStatus.Line {
        MenuStatus.line(
            status: model.status,
            profileName: model.activeProfile?.name,
            isPaused: model.isPaused,
            hasProblem: model.configurationProblem != nil
        )
    }

    /// Ohne Zugriff oder ohne Einstellungen ist jeder Schalter eine Lüge.
    private var isBlocked: Bool {
        model.status == .needsPermission || model.configuration == nil
    }

    var body: some View {
        Section {
            Text(MenuStatus.header(version: model.appVersion))
        }

        Text(statusLine.title)
        if let action = statusLine.action {
            Button(action.title) { perform(action) }
        }

        updateBanner
        competingManagers

        Divider()

        Toggle(localized("menuContent.autoPlaceToggle", "Place Windows Automatically"), isOn: Binding(
            get: { !model.isPaused },
            set: { model.isPaused = !$0 }
        ))
        .disabled(model.status == .needsPermission || model.status == .needsConfiguration)

        dropzoneTriggerMenu

        if let sentence = DragOutcomeWording.sentence(for: model.lastDragOutcome) {
            Text(sentence)
        }
        if let problem = model.dropzones.problem {
            Text(localized("menuContent.dropzonesNotActive", "Dragging is not active: %@", problem))
        }

        Divider()

        pinEntry

        Button(localized("menuContent.editZonesAndRulesButton", "Edit Zones and Rules …")) { showEditorWindow() }
            .disabled(model.configuration == nil)

        Divider()

        moreMenu

        Divider()

        Button(localized("menuContent.quitButton", "Quit OpenZonr")) { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func perform(_ action: MenuStatus.Action) {
        switch action {
        case .grantAccess, .explain:
            // Beide Wege enden im selben Fenster — es ist das einzige, das den
            // konkreten Zustand erklärt und die Wege dorthin anbietet. Die
            // Titel versprechen trotzdem Verschiedenes, weil die Lagen
            // verschieden sind.
            showStatusWindow()
        }
    }

    // MARK: - Ziehen

    /// Die eine Frage, die ein Nutzer zum Ziehen hat: **wann** kommen die Zonen?
    ///
    /// Drei Zeilen, die die Antwort jeweils aussprechen, statt eines Schalters
    /// plus einer unsichtbaren Regel in der Datei. Der Haken steht am wirksamen
    /// Zustand, gelesen aus der geladenen Konfiguration — nicht an dem, was
    /// zuletzt angeklickt wurde.
    @ViewBuilder
    private var dropzoneTriggerMenu: some View {
        let settings = model.configuration?.defaults.dropzones
        let current = model.dropzoneTrigger
        // Der Zustand steht in der Aufschrift der Elternzeile („Zonen beim
        // Ziehen: nur mit ⌘"). Beim alten Schalter war er auf der obersten
        // Ebene zu sehen; eine Ebene tiefer wäre ein Rückschritt.
        Menu(DropzoneTrigger.rowTitle(settings)) {
            ForEach(DropzoneTrigger.allCases) { trigger in
                Button {
                    model.setDropzoneTrigger(trigger)
                } label: {
                    Text(marker(active: current == trigger) + trigger.label)
                }
            }
            // Eine Regel aus der Datei, die keine der drei Zeilen ausdrückt —
            // auch dann, wenn gerade „Aus" gilt. Sonst verschwände sie beim
            // Ausschalten aus dem Menü und käme nie wieder zum Vorschein: der
            // Editor zeigt `activation` nicht, und jede der drei Wahlen
            // überschreibt sie.
            if let row = model.dropzoneCustomRow {
                Divider()
                if row.isActive {
                    Text(marker(active: true) + row.label)
                } else {
                    // Der Weg zurück: einschalten, ohne die Regel anzutasten.
                    Button {
                        model.enableDropzonesKeepingRule()
                    } label: {
                        Text(marker(active: false) + row.label)
                    }
                }
            }
        }
        .disabled(isBlocked)
    }

    // MARK: - Setup

    /// `Section`, nicht `Menu`: ein zweites `Menu` hier wäre die zweite Ebene
    /// verschachtelter Untermenüs innerhalb von „Mehr" — und genau das lässt das
    /// native `NSMenu`, das `MenuBarExtra` im `.menu`-Stil daraus baut, beim
    /// Übergang zwischen den Ebenen verlässlich den Hover-Zustand verlieren und
    /// sich schließen, bevor sich etwas auswählen lässt (Issue #66, vom Nutzer
    /// als reproduzierbar bestätigt). Eine `Section` gruppiert mit Titel und
    /// Trennlinie auf **derselben** Ebene, ohne ein weiteres hover-gesteuertes
    /// Menü zu öffnen — das behebt die Ursache, statt sie zu umgehen.
    @ViewBuilder
    private var setupMenu: some View {
        if model.availableProfiles.isEmpty {
            Text(localized("menuContent.noSetupsConfigured", "No Setups Configured"))
        } else {
            Section(localized("menuContent.setupSection", "Setup")) {
                Button {
                    model.selectProfile(nil)
                } label: {
                    // A checkmark is not available on a plain menu Button, so the
                    // marker is part of the title. Ugly in code, unambiguous on
                    // screen — and unlike a disabled item it stays clickable, so
                    // "back to automatic" is always one click away.
                    Text(marker(active: model.profileState?.isPinned == false)
                        + localized("menuContent.automaticSetup", "Automatic"))
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

    /// Der 90-%-Fall: „diese App immer hier öffnen“.
    ///
    /// Seit Issue #27 gibt es zwei Wege: der Menüleisten-Eintrag hier und ein
    /// Rechtsklick auf den grünen Fensterknopf (siehe ``ZoomButtonMenu``).
    /// Beide gehen durch denselben ``QuickPin``, keine zweite Buchhaltung.
    /// Der Menüleisten-Weg bleibt, weil er tastaturbedienbar ist und ohne
    /// Zeiger auskommt.
    @ViewBuilder
    private var pinEntry: some View {
        Button(localized("menuContent.pinFrontmostWindowButton", "Pin Frontmost Window Here")) {
            model.pinFrontmostWindow()
        }
        .disabled(isBlocked)

        if let message = model.lastPinMessage {
            Text(message)
        }
    }

    /// Says out loud that another window manager is running.
    ///
    /// OpenZonr does not try to win against it. Two tools that both show an
    /// overlay while dragging produce a result the user cannot predict, and the
    /// honest move is to say so once rather than to fight silently — see
    /// docs/dropzones.md. Bleibt auf der obersten Ebene: es erklärt genau das,
    /// was sonst als „OpenZonr tut nichts“ ankommt.
    @ViewBuilder
    private var competingManagers: some View {
        let running = model.competingWindowManagers
        if !running.isEmpty {
            Text(CompetingWindowManagers.warning(for: running) ?? "")
        }
    }

    // MARK: - Mehr

    /// Alles, was selten gebraucht wird oder technisch ist.
    ///
    /// Es ist nichts gestrichen — es ist einen Schritt tiefer. Die Trennlinie
    /// verläuft entlang „brauche ich das im Alltag?“: das Setup von Hand
    /// wählen, neu laden, den Zugriff nachsehen, Autostart und die
    /// Update-Einstellungen sind Dinge, die man einmal tut und dann nie wieder.
    @ViewBuilder
    private var moreMenu: some View {
        Menu(localized("menuContent.moreMenu", "More")) {
            setupMenu

            Divider()

            recentPlacements

            Divider()

            Button(localized("menuContent.reloadConfigButton", "Reload Configuration")) {
                model.reloadConfiguration()
            }
            Button(localized("menuContent.statusAndPermissionButton", "Status and Permission …")) {
                showStatusWindow()
            }

            Divider()

            Toggle(localized("menuContent.launchAtLoginToggle", "Start at Login"), isOn: Binding(
                get: { model.launchesAtLogin },
                set: { model.launchesAtLogin = $0 }
            ))

            Divider()

            Button(localized("menuContent.checkForUpdatesButton", "Check for Updates …")) { checkForUpdates() }
                .disabled(model.updates.isBusy || model.updates.hasPreparedUpdate)

            Toggle(localized("menuContent.autoCheckForUpdatesToggle", "Automatically Check for Updates"), isOn: Binding(
                get: { model.updates.automaticChecksEnabled },
                set: { model.updates.automaticChecksEnabled = $0 }
            ))
        }
    }

    // MARK: - Updates

    /// Das Einzige am Update, das oben bleibt: ein Stand, der eine Entscheidung
    /// verlangt.
    ///
    /// Die Zustandszeile steht dabei und ist sichtbar, sobald es etwas zu sagen
    /// gibt. Das ist der Unterschied zu einem Knopf, der nur nach dem Klick
    /// antwortet: ein Update, das im Hintergrund gefunden und geladen wurde,
    /// muss sich zeigen, ohne dass jemand danach sucht. Suchen und der
    /// Automatik-Schalter sind dagegen Einstellungen und liegen unter „Mehr“.
    @ViewBuilder
    private var updateBanner: some View {
        let updates = model.updates
        let banner = MenuStatus.updateBanner(for: updates.state)
        // Die **Zeile** ist die äussere Bedingung, nicht der Knopf. Andersherum
        // hätten „wird geladen", „wird installiert" und ein im Hintergrund
        // gescheiterter Versuch überhaupt keine Oberfläche.
        if let line = banner.line {
            Divider()
            Text(line)
            if let title = banner.installTitle {
                Button(title) { installUpdate() }
                Button(localized("menuContent.laterButton", "Later")) { Task { await updates.dismiss() } }
            }
        }
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
                present(
                    title: localized("menuContent.upToDate.title", "OpenZonr Is Up to Date"),
                    message: localized("menuContent.upToDate.message", "The newest version is running.")
                )
            case let .failed(message):
                present(title: localized("menuContent.checkFailed.title", "Update Check Failed"), message: message)
            case let .readyToInstall(version):
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = localized("menuContent.readyToInstall.title", "OpenZonr %@ Is Ready", version)
                alert.informativeText = localized(
                    "menuContent.readyToInstall.message",
                    "OpenZonr pauses window observation, swaps itself out and relaunches. No window "
                        + "will be placed for a few seconds."
                )
                alert.addButton(withTitle: localized("menuContent.installAndRelaunchButton", "Install and Relaunch"))
                alert.addButton(withTitle: localized("menuContent.laterButton", "Later"))
                if alert.runModal() == .alertFirstButtonReturn { installUpdate() }
            case .idle, .checking, .downloading, .installing:
                break
            }
        }
    }

    /// Pause, then swap — the order lives in ``AppModel/installUpdate()``, so
    /// it is testable.
    private func installUpdate() {
        Task {
            if await model.installUpdate() { return }
            if case let .failed(message) = model.updates.state {
                present(
                    title: localized("menuContent.installFailed.title", "Update Could Not Be Installed"),
                    message: message
                )
            }
        }
    }

    private func present(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: localized("menuContent.okButton", "OK"))
        alert.runModal()
    }

    // MARK: - Recent placements

    /// `Section`, nicht `Menu` — aus demselben Grund wie bei ``setupMenu``:
    /// ein zweites verschachteltes Menü innerhalb von „Mehr" ist die Ursache
    /// von Issue #66, nicht nur eine seiner Erscheinungen.
    @ViewBuilder
    private var recentPlacements: some View {
        if model.records.isEmpty {
            Text(localized("menuContent.noPlacementsYet", "No Placements Yet"))
        } else {
            Section(localized("menuContent.recentlyPlacedSection", "Recently Placed")) {
                ForEach(model.records.prefix(8)) { record in
                    Text("\(record.applicationName) → \(record.target ?? "—") · \(record.summary)")
                }
                Divider()
                Button(localized("menuContent.showAllButton", "Show All …")) { showActivityWindow() }
            }
        }
        Button(localized("menuContent.recentPlacementsButton", "Recent Placements …")) { showActivityWindow() }
    }

    // MARK: - Windows

    private func showStatusWindow() {
        model.refreshPermission(probe: true)
        PanelPresenter.shared.show(
            id: "status",
            title: localized("statusWindow.panelTitle", "OpenZonr — Status and Permission"),
            size: NSSize(width: 620, height: 560)
        ) {
            StatusWindow(model: model)
        }
    }

    private func showActivityWindow() {
        PanelPresenter.shared.show(
            id: "activity",
            title: localized("menuContent.activityWindowTitle", "OpenZonr — Recent Placements"),
            size: NSSize(width: 720, height: 480)
        ) {
            ActivityWindow(model: model)
        }
    }

    private func showEditorWindow() {
        guard let document = model.editorDocument() else { return }
        PanelPresenter.shared.show(
            id: "editor",
            title: localized("menuContent.editorWindowTitle", "OpenZonr — Zones and Rules"),
            size: NSSize(width: 900, height: 620)
        ) {
            EditorWindow(document: document)
        }
    }
}
