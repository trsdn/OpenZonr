import AppKit
import OpenZonrCore
import OpenZonrMac

/// Drag a window, see the zones, let go, and it is in one.
///
/// The controller owns the wiring and nothing else. Every decision it needs has
/// been made somewhere testable: ``DropzoneOverlayPlan`` says what to show,
/// ``DropzoneMap`` says which zone a point is in, ``DropRuleOffer`` turns a drop
/// into a ``QuickPin.Request``, and ``WatchEngine/place(dropped:application:into:)``
/// does the placing — the same code the automatic half uses. What is left here
/// is the part that cannot be tested without the Accessibility permission, and
/// it is deliberately thin, because that is the part nobody can check.
@MainActor
final class DropzoneController {

    private let model: AppModel
    private let overlay: any DropzoneOverlaying
    private let offerPanel = DropOfferPanel()
    private lazy var zoomMenu = ZoomButtonMenu(model: model)
    private var tracker: (any WindowDragTracker)?

    /// The drag in progress.
    private var dragged: DraggedWindow?
    private var dragContext: DragContext?
    private var lastPlan: DropzoneOverlayPlan.Plan = .hidden(.disabled)

    /// Set when the tracker could not be started, so the menu can say why
    /// instead of showing a feature that quietly does nothing.
    private(set) var problem: String?

    /// Buchhaltung für das Ergebnis des laufenden Zugs (siehe ``DragOutcome``).
    ///
    /// Gesammelt wird über den ganzen Zug und erst beim Loslassen gemeldet: wer
    /// ⌘ mitten im Zug wieder loslässt, hat die Zonen trotzdem gesehen, und ein
    /// Satz, der nur den letzten Augenblick beschreibt, würde in die Irre führen.
    private var dragSawZones = false
    private var dragHiddenReason: DropzoneActivation?
    private var dragLacksSetup = false

    #if DEBUG
    /// Nur für Tests: `true`, wenn `start()` einen laufenden Tracker
    /// installiert hat. Die App selbst braucht das nicht — der Tracker
    /// spricht durch `onEvent`, und ohne installierten Tap kann er nicht
    /// sprechen. Die Zusicherung „bei Pause installieren wir keinen Tap" ist
    /// aber genau die, an der der Fund aus PR #15 hing.
    var _hasActiveTrackerForTesting: Bool { tracker != nil }

    /// Nur für Tests: speist ein Zugereignis ein, als käme es vom Tracker. Ein
    /// Event-Tap lässt sich in der Testumgebung nicht installieren.
    func _handleForTesting(_ event: WindowDragEvent) { handle(event) }

    /// Nur für Tests: wie oft `start()` / `stop()` gelaufen sind. Ein
    /// Event-Tap lässt sich in der Testumgebung nicht installieren; die Zähler
    /// zeigen stattdessen, ob der Tracker angefasst wurde.
    private(set) var _startCountForTesting = 0
    private(set) var _stopCountForTesting = 0
    #endif

    /// The offer shown after a drop, or `nil` when there is none.
    private(set) var offer: DropOffer?

    /// „Diese App immer hier öffnen?“ — the question and what to do with a yes.
    struct DropOffer: Identifiable {
        let id = UUID()
        let question: String
        let request: QuickPin.Request
    }

    /// What stays fixed for the duration of one drag.
    ///
    /// Screens and zones cannot change while the mouse button is down, so
    /// resolving them once per drag instead of once per pointer move removes
    /// a screen enumeration and a full zone rebuild from every mouse event.
    private struct DragContext {
        var origin: ScreenPoint
        var zones: [Dropzone]
    }

    init(model: AppModel, overlay: any DropzoneOverlaying = DropzoneOverlay()) {
        self.model = model
        self.overlay = overlay
    }

    // MARK: - Lifecycle

    func start() {
        #if DEBUG
        _startCountForTesting += 1
        #endif
        stop()
        if let suspension = DropzoneActivator.suspension(settings: settings, isPaused: model.isPaused) {
            // Nur die Pause bekommt eine eigene Zeile. „Abgeschaltet" steht
            // schon in der Aufschrift der Zeile darüber — sie lautet dann
            // „Zonen beim Ziehen: aus" (siehe ``DropzoneTrigger/rowTitle(_:)``),
            // und ein zweiter Satz daneben wäre Rauschen.
            problem = suspension == .paused ? suspension.explanation : nil
            return
        }

        let arrangement = ScreenArrangement(snapshots: SystemDisplays.snapshots())
        // The event tap, because the probe measured the one difference that
        // matters: it reports the release as an event, the Accessibility
        // notification does not report it at all. See docs/dropzones.md.
        let tap = EventTapDragTracker(primaryTopY: arrangement.primaryTopY)
        tap.minimumDragDistance = settings.minimumDragDistance
        tap.onEvent = { [weak self] event in self?.handle(event) }
        // Drücke, die es nie bis zu einem `.began` schaffen, sind genau die,
        // über die „die Zonen kommen nicht“ aufzuklären ist. Sie kommen durch
        // einen eigenen Kanal und landen unverändert im Modell.
        tap.onOutcome = { [weak self] outcome in self?.model.recordDragOutcome(outcome) }
        tap.onRightClick = { [weak self] appKitPoint, lookup in
            // Der Rechtsklick geht am Zug vorbei. Der Tracker hat die
            // AX-Abfrage schon im Hintergrund erledigt und liefert das
            // Ergebnis auf dem MainActor. Das Menü prüft dann selbst, ob am
            // Zeigerpunkt tatsächlich der grüne Knopf liegt; passt es nicht
            // (kein Knopf, kein Attribut, kein Fenster), passiert still
            // nichts. Ein sichtbarer Fehler an dieser Stelle würde jeden
            // beiläufigen Rechtsklick beklagen — siehe Issue #27.
            self?.zoomMenu.show(atAppKitPoint: appKitPoint, lookup: lookup)
        }

        do {
            try tap.start()
            tracker = tap
            problem = nil
        } catch {
            problem = "\(error)"
            Log.warn(localized("dropzoneController.notActive", "Dropzones are not active: %@", "\(error)"))
        }
    }

    func stop() {
        #if DEBUG
        _stopCountForTesting += 1
        #endif
        tracker?.stop()
        tracker = nil
        overlay.hide()
        dragged = nil
        dragContext = nil
    }

    /// Restarts after a settings change; also the way the menu switches the
    /// feature on and off.
    func restart() {
        stop()
        start()
    }

    func dismissOffer() {
        offer = nil
        offerPanel.dismiss()
    }

    /// Accepts the pending offer, through the same path as the menu entry.
    func acceptOffer() {
        guard let offer, let base = model.document?.configuration ?? model.configuration else { return }
        model.apply(offer.request, to: base)
        self.offer = nil
    }

    // MARK: - Events

    private func handle(_ event: WindowDragEvent) {
        switch event {
        case let .began(window, point):
            dragged = window
            dragSawZones = false
            dragHiddenReason = nil
            dragLacksSetup = false
            dragContext = makeDragContext(origin: point)
            // A new drag retires the previous offer: answering it now would
            // pin the app to the zone of a drop two gestures ago.
            dismissOffer()

        case let .moved(point, modifiers):
            update(pointer: point, modifiers: modifiers)

        case let .ended(point, modifiers):
            // Der letzte Plan wird nur noch *errechnet* (das Ablegen braucht die
            // hervorgehobene Zone), nicht mehr gezeichnet. Ein Neuzeichnen
            // beim Loslassen ließ die blaue Zone stehen, sobald ⌘ noch gehalten
            // war — der Normalfall bei `showsWhile(.command)`.
            update(pointer: point, modifiers: modifiers, render: false)
            // Erst ablegen, dann den Satz festhalten. Ein Ablegen auf der
            // Anheft-Marke schreibt eine Regel, das Sichern lädt neu, und ein
            // Neuladen vergisst den letzten Zug — in der anderen Reihenfolge
            // wäre der Satz weg, kaum dass er dastand.
            drop(at: point)
            model.recordDragOutcome(finishedDragOutcome())
            // Nach dem Loslassen steht kein Overlay mehr, egal was der Plan war.
            overlay.hide()
            dragged = nil
            dragContext = nil

        case let .cancelled(reason):
            model.recordDragOutcome(.cancelled(reason: reason))
            // A cancellation hits the user mid-gesture, visibly: the overlay
            // disappears, and without a hint it stays unclear why. So the
            // message goes through the same channel as this path's other
            // visible errors (`AppModel.lastPinMessage`), not just the log.
            // See Issue #26 (Error C).
            //
            // `reason` comes from EventTapDragTracker in OpenZonrMac, not yet
            // migrated (deferred, see #83) — it is still German today, so
            // this sentence can currently read as English glued to a German
            // clause until that follow-up lands.
            Log.detail(localized("dropzoneController.dragCancelled.log", "Drag cancelled: %@", reason))
            model.reportPinFailure(
                localized("dropzoneController.dragCancelled.message", "The drag was cancelled: %@", reason)
            )
            overlay.hide()
            dragged = nil
            dragContext = nil
        }
    }

    /// Das Urteil über den gerade beendeten Zug.
    ///
    /// „Zonen gesehen" schlägt alles andere: es ist das, was der Nutzer erlebt
    /// hat. Erst danach zählt der Grund, aus dem sie zuletzt ausblieben.
    ///
    /// Ohne aufgezeichneten Grund wird keiner behauptet. Ein Rückfall auf
    /// ``DropzoneActivation/disabled`` wäre bequem und falsch: er nennte eine
    /// Ursache, die niemand gemessen hat — in einer Zeile, deren ganzer Zweck
    /// die Ursachensuche ist.
    private func finishedDragOutcome() -> DragOutcome {
        if dragSawZones { return .zonesShown }
        if dragLacksSetup { return .noSetupActive }
        guard let reason = dragHiddenReason else { return .zonesHiddenWithoutReason }
        return .zonesHidden(reason)
    }

    /// - Parameter render: `false` beim Loslassen — dann wird nur der Plan
    ///   nachgeführt, das Overlay aber weder gezeigt noch angefasst.
    private func update(pointer: ScreenPoint, modifiers: ModifierState, render: Bool = true) {
        // The zones come from the drag context, resolved once at `.began`.
        // Screens and zones cannot change while the button is down, so
        // rebuilding them per pointer move bought nothing and cost a screen
        // enumeration plus a full zone rebuild on every event.
        guard let dragContext else {
            // Ohne Setup gibt es keine Zonen — ein eigener Grund, der sonst als
            // „abgeschaltet" gemeldet würde und niemanden weiterbrächte.
            if model.activeProfile == nil { dragLacksSetup = true }
            if render { overlay.hide() }
            return
        }
        let plan = DropzoneOverlayPlan.plan(
            pointer: pointer,
            origin: dragContext.origin,
            zones: dragContext.zones,
            settings: settings,
            modifiers: modifiers
        )
        lastPlan = plan
        if case let .hidden(activation) = plan {
            dragHiddenReason = activation
        } else {
            dragSawZones = true
        }
        if render { overlay.show(plan) }
    }

    private func makeDragContext(origin: ScreenPoint) -> DragContext? {
        guard let configuration = model.configuration, let profile = model.activeProfile else {
            return nil
        }

        let snapshots = SystemDisplays.snapshots()
        let arrangement = ScreenArrangement(snapshots: snapshots)
        // The same reconciliation the profile choice uses: a display without a
        // serial number whose port index has drifted must still get its zones,
        // or the profile matches and the overlay stays empty. This moved here
        // with the zones — resolving them once per drag must not silently drop
        // the matching that resolving them per move did.
        let reconciler = configuration.displayReconciler(observing: snapshots)
        let zones = DropzoneMap.zones(
            in: configuration,
            profile: profile.id,
            visibleFrames: arrangement.visibleFrames(for: configuration.displays, reconciler: reconciler)
        )
        return DragContext(origin: origin, zones: zones)
    }

    /// Puts the window in the zone under the pointer.
    ///
    /// The **release point decides whether a rule is written.** Anywhere in the
    /// zone: one-off placement, nothing else. On the zone's pin badge: same
    /// placement, and ``QuickPin`` writes the rule. The user made both
    /// decisions with the mouse, in the same gesture, so nothing pops up
    /// afterwards to ask again. The old *„immer hier öffnen?"* panel remains
    /// as a switch (`defaults.dropzones.offerRule`) but is off by default —
    /// see the type's own note.
    private func drop(at point: ScreenPoint) {
        guard let window = dragged, let zone = lastPlan.highlighted else { return }
        guard let application = NSRunningApplication(processIdentifier: window.processIdentifier) else { return }
        guard let engine = model.engine else { return }

        engine.place(dropped: window.element, application: application, into: zone.placement)

        if DropzoneMap.isOnPinBadge(point, of: zone) {
            pin(window: window, into: zone)
        } else {
            prepareOffer(for: window, zone: zone, at: point)
        }
    }

    /// Writes the rule the badge stands for.
    ///
    /// The same request the panel would build, through the same ``QuickPin``,
    /// so a badge-pinned rule and a panel-pinned rule are the same kind of
    /// rule and cannot drift apart. What is skipped is the panel itself: the
    /// user already answered with the release point.
    ///
    /// **Ablehnungen sind hier nicht still.** Anders als das Angebotspanel,
    /// dessen Ausbleiben nichts weiter heißt, wurde die Marke ausdrücklich
    /// getroffen — ihr einziger Zweck ist die Regel. Bleibt die Regel aus,
    /// muss das Fenster gesagt bekommen, warum. Wir gehen deshalb durch
    /// dieselbe ``AppModel/lastPinMessage`` wie der Menüweg „Aktuelles Fenster
    /// hier festhalten"; das Fenster wird trotzdem platziert, weil das schon
    /// oben geschehen ist.
    private func pin(window: DraggedWindow, into zone: Dropzone) {
        guard let base = model.document?.configuration ?? model.configuration else {
            model.reportPinFailure(AppModel.GuardSentence.noConfigurationLoaded)
            return
        }
        guard let profile = model.activeProfile else {
            model.reportPinFailure(AppModel.GuardSentence.noActiveProfile)
            return
        }
        switch DropRuleOffer.pin(
            for: window.dropped,
            droppedInto: zone,
            profile: profile.id,
            configuration: base
        ) {
        case let .success(request):
            model.apply(request, to: base)
        case let .failure(refusal):
            // Same voice as the menu path: a rule that cannot be written has
            // to be explained to the user visibly — not just into the log.
            model.reportPinFailure(
                localized("dropzoneController.pinBadgeHadNoEffect", "Pin badge had no effect: %@", "\(refusal)")
            )
        }
    }

    private func prepareOffer(for window: DraggedWindow, zone: Dropzone, at point: ScreenPoint) {
        guard let profile = model.activeProfile else { return }
        guard let configuration = model.document?.configuration ?? model.configuration else { return }
        switch DropRuleOffer.request(
            for: window.dropped,
            droppedInto: zone,
            profile: profile.id,
            settings: settings,
            configuration: configuration
        ) {
        case let .success(request):
            let question = DropRuleOffer.question(for: window.dropped, zone: zone)
            offer = DropOffer(question: question, request: request)
            offerPanel.show(question: question, near: point) { [weak self] in self?.acceptOffer() }
        case let .failure(refusal):
            Log.detail(localized("dropzoneController.noRuleOffer", "No rule offer: %@", "\(refusal)"))
        }
    }

    private var settings: DropzoneSettings {
        model.configuration?.defaults.dropzones ?? DropzoneSettings()
    }
}
