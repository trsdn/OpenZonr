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
        guard settings.enabled else { return }

        let arrangement = ScreenArrangement(snapshots: SystemDisplays.snapshots())
        // The event tap, because the probe measured the one difference that
        // matters: it reports the release as an event, the Accessibility
        // notification does not report it at all. See docs/dropzones.md.
        let tap = EventTapDragTracker(primaryTopY: arrangement.primaryTopY)
        tap.minimumDragDistance = settings.minimumDragDistance
        tap.onEvent = { [weak self] event in self?.handle(event) }

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
            Log.detail("Zug abgebrochen: \(reason)")
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
    private func drop(at point: ScreenPoint) {
        guard let window = dragged, let zone = lastPlan.highlighted else { return }
        guard let application = NSRunningApplication(processIdentifier: window.processIdentifier) else { return }
        guard let engine = model.engine else { return }

        engine.place(dropped: window.element, application: application, into: zone.placement)
        prepareOffer(for: window, zone: zone, at: point)
    }

    private func prepareOffer(for window: DraggedWindow, zone: Dropzone, at point: ScreenPoint) {
        guard let profile = model.activeProfile else { return }
        switch DropRuleOffer.request(
            for: window.dropped,
            droppedInto: zone,
            profile: profile.id,
            settings: settings
        ) {
        case let .success(request):
            // The offer is only worth making when it would change something.
            // QuickPin knows whether it would; asking it here keeps this from
            // becoming a second opinion about rules.
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
