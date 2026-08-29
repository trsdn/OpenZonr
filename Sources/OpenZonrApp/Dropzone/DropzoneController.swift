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
    private let overlay = DropzoneOverlay()
    private let offerPanel = DropOfferPanel()
    private lazy var zoomMenu = ZoomButtonMenu(model: model)
    private var tracker: (any WindowDragTracker)?

    /// The drag in progress.
    private var origin: ScreenPoint?
    private var dragged: DraggedWindow?
    private var lastPlan: DropzoneOverlayPlan.Plan = .hidden(.disabled)

    /// Set when the tracker could not be started, so the menu can say why
    /// instead of showing a feature that quietly does nothing.
    private(set) var problem: String?

    /// The offer shown after a drop, or `nil` when there is none.
    private(set) var offer: DropOffer?

    /// „Diese App immer hier öffnen?“ — the question and what to do with a yes.
    struct DropOffer: Identifiable {
        let id = UUID()
        let question: String
        let request: QuickPin.Request
    }

    init(model: AppModel) {
        self.model = model
    }

    // MARK: - Lifecycle

    func start() {
        stop()
        if let suspension = DropzoneActivator.suspension(settings: settings, isPaused: model.isPaused) {
            // Only the pause gets a line in the menu. "Switched off" is what the
            // toggle right above it already says; repeating it would be noise.
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
        tap.onRightClick = { [weak self] appKitPoint, accessibilityPoint in
            // Der Rechtsklick geht am Zug vorbei. Das Menü prüft selbst, ob am
            // Zeigerpunkt tatsächlich der grüne Knopf liegt; passt es nicht,
            // passiert stumm nichts (oder erkennbar nichts, wenn das Fenster
            // keinen Zoom-Knopf-Rahmen liefert — siehe Issue #27).
            self?.zoomMenu.show(atAppKitPoint: appKitPoint, accessibilityPoint: accessibilityPoint)
        }

        do {
            try tap.start()
            tracker = tap
            problem = nil
        } catch {
            problem = "\(error)"
            Log.warn("Dropzones sind nicht aktiv: \(error)")
        }
    }

    func stop() {
        tracker?.stop()
        tracker = nil
        overlay.hide()
        origin = nil
        dragged = nil
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
            origin = point
            dragged = window
            // A new drag retires the previous offer: answering it now would
            // pin the app to the zone of a drop two gestures ago.
            dismissOffer()

        case let .moved(point, modifiers):
            update(pointer: point, modifiers: modifiers)

        case let .ended(point, modifiers):
            update(pointer: point, modifiers: modifiers)
            drop(at: point)
            overlay.hide()
            origin = nil
            dragged = nil

        case let .cancelled(reason):
            // Ein Abbruch trifft den Nutzer mitten in einer sichtbaren Geste:
            // das Overlay verschwindet, und ohne Hinweis bleibt unklar warum.
            // Deshalb geht die Meldung durch denselben Kanal wie andere
            // sichtbare Fehler dieses Wegs (`AppModel.lastPinMessage`), nicht
            // nur ins Protokoll. Siehe Issue #26 (Fehler C).
            Log.detail("Zug abgebrochen: \(reason)")
            model.reportPinFailure("Der Zug wurde abgebrochen: \(reason)")
            overlay.hide()
            origin = nil
            dragged = nil
        }
    }

    private func update(pointer: ScreenPoint, modifiers: ModifierState) {
        guard let origin, let configuration = model.configuration, let profile = model.activeProfile else {
            overlay.hide()
            return
        }
        let arrangement = ScreenArrangement(snapshots: SystemDisplays.snapshots())
        let plan = DropzoneOverlayPlan.plan(
            pointer: pointer,
            origin: origin,
            configuration: configuration,
            profile: profile.id,
            visibleFrames: arrangement.visibleFrames(for: configuration.displays),
            settings: settings,
            modifiers: modifiers
        )
        lastPlan = plan
        overlay.show(plan)
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
            model.reportPinFailure("Es ist keine Konfiguration geladen.")
            return
        }
        guard let profile = model.activeProfile else {
            model.reportPinFailure("Kein Profil ist aktiv — ohne Profil ist nicht bekannt, was „hier“ bedeutet.")
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
            // Dieselbe Stimme wie der Menüweg: eine Regel, die nicht
            // geschrieben werden kann, muss dem Nutzer sichtbar erklärt
            // werden — nicht nur ins Protokoll.
            model.reportPinFailure("Anheft-Marke ohne Wirkung: \(refusal)")
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
            Log.detail("Kein Regelangebot: \(refusal)")
        }
    }

    private var settings: DropzoneSettings {
        model.configuration?.defaults.dropzones ?? DropzoneSettings()
    }
}
