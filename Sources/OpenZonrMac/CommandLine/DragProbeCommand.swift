import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import OpenZonrCore

/// `openzonr dragprobe` — measuring the two ways of noticing a window drag,
/// instead of arguing about them.
///
/// Issue #10 leaves the choice between `kAXMovedNotification` and a
/// `CGEventTap` open and says it belongs measured. This is the instrument. It
/// runs both paths side by side for a fixed time and reports, per path:
///
/// - whether it could be set up at all, and with which error if not,
/// - how many events arrived and at what rate,
/// - delivery latency where the source carries a timestamp,
/// - the largest gap between two events, which is what a lagging overlay is
///   made of,
/// - whether the *release* of the mouse button is an event or a poll.
///
/// `--synthesize` posts mouse events itself, so the numbers exist even with
/// nobody at the desk. They are labelled as synthetic in the report, because a
/// synthetic drag is not a human drag and pretending otherwise would be exactly
/// the kind of claim this project refuses to make.
struct DragProbeCommand {

    var seconds: Double
    var outputPath: String?
    var synthesize: Bool

    @MainActor
    func run() throws -> Never {
        var report = ""
        func emit(_ line: String = "") {
            print(line)
            report += line + "\n"
        }

        emit("OpenZonr — Messung der Zieherkennung")
        emit(String(repeating: "=", count: 42))
        emit()
        emit("Dauer je Weg:        \(format(seconds)) s")
        emit("Ereignisse:          \(synthesize ? "synthetisch erzeugt" : "echte Mausbewegung erwartet")")
        emit("AXIsProcessTrusted:  \(Accessibility.isTrusted())")
        emit("Fensterzugriff:      \(describe(Accessibility.probeWindowAccess()))")
        emit("Bundle:              \(Accessibility.enclosingApplicationBundle()?.path ?? "— kein Bundle —")")
        emit()

        let competing = CompetingWindowManagers.detected(
            among: NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
        )
        if let warning = CompetingWindowManagers.warning(for: competing) {
            emit("Konkurrierende Fenstermanager laufen — die Zahlen unten enthalten sie:")
            emit(warning)
            emit()
        } else {
            emit("Kein bekannter konkurrierender Fenstermanager läuft.")
            emit()
        }

        let arrangement = ScreenArrangement(snapshots: SystemDisplays.snapshots())

        emit(measureEventTap(primaryTopY: arrangement.primaryTopY))
        emit()
        emit(measureAccessibility(primaryTopY: arrangement.primaryTopY))
        emit()
        emit(Self.comparison)

        if let outputPath {
            let url = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
            try? report.write(to: url, atomically: true, encoding: .utf8)
            print("Bericht geschrieben: \(url.path)")
        }
        exit(0)
    }

    // MARK: - Event tap

    @MainActor
    private func measureEventTap(primaryTopY: Double) -> String {
        var text = "CGEventTap\n" + String(repeating: "-", count: 42) + "\n"

        let tracker = EventTapDragTracker(primaryTopY: primaryTopY)
        var measurement = DragMeasurement()
        var releases = 0
        var drags = 0
        let clock = ContinuousClock()
        let started = clock.now

        tracker.onRawEvent = { type, _, latency in
            measurement.add(
                DragMeasurement.Sample(arrival: clock.now - started, latency: latency)
            )
            if type == .leftMouseUp { releases += 1 }
            if type == .leftMouseDragged { drags += 1 }
        }

        do {
            try tracker.start()
        } catch {
            text += "Einrichtung:         fehlgeschlagen\n"
            text += "Grund:               \(error)\n"
            text += "Berechtigung:        wird benötigt (dieselbe Bedienungshilfen-Freigabe)\n"
            return text
        }
        text += "Einrichtung:         gelungen (listen-only, .cgSessionEventTap)\n"
        text += "Berechtigung:        Bedienungshilfen — dieselbe Freigabe, keine zusätzliche\n"

        let driver = synthesize ? scheduleSyntheticDrag() : nil
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        driver?.stop()
        tracker.stop()

        text += render(measurement)
        text += "davon Ziehen:        \(drags)\n"
        text += "Loslassen:           \(releases) als Ereignis empfangen"
        text += releases > 0 ? " — exakt, ohne Polling\n" : " — im Messzeitraum keins\n"
        return text
    }

    // MARK: - Accessibility

    @MainActor
    private func measureAccessibility(primaryTopY: Double) -> String {
        var text = "kAXMovedNotification\n" + String(repeating: "-", count: 42) + "\n"

        let tracker = AXMovedDragTracker(primaryTopY: primaryTopY)
        var measurement = DragMeasurement()
        var ends = 0
        let clock = ContinuousClock()
        let started = clock.now

        tracker.onRawMove = { _ in
            // No latency: an Accessibility notification carries no timestamp of
            // its own, so there is nothing to subtract. Reporting a number here
            // would mean inventing one.
            measurement.add(DragMeasurement.Sample(arrival: clock.now - started, latency: nil))
        }
        tracker.onEvent = { event in
            if case .ended = event { ends += 1 }
        }

        do {
            try tracker.start()
        } catch {
            text += "Einrichtung:         fehlgeschlagen\n"
            text += "Grund:               \(String(describing: error).prefix(200))…\n"
            return text
        }
        text += "Einrichtung:         gelungen (Beobachter auf dem Fenster der vordersten App)\n"
        text += "Berechtigung:        Bedienungshilfen — dieselbe Freigabe, keine zusätzliche\n"

        let synthetic = synthesize ? scheduleSyntheticWindowMove() : nil
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        synthetic?.driver.stop()
        tracker.stop()

        if let name = synthetic?.name {
            text += "Bewegtes Fenster:    \(name) (danach zurückgesetzt)\n"
        } else if synthesize {
            text += "Bewegtes Fenster:    keines erreichbar — deshalb null Ereignisse unten\n"
        }

        text += render(measurement, includeLatency: false)
        text += "Latenz:              grundsätzlich nicht messbar — eine Accessibility-\n"
        text += "                     Benachrichtigung trägt keinen Zeitstempel, es gibt nichts\n"
        text += "                     abzuziehen. Das gilt auch für echte Züge.\n"
        text += "Loslassen:           \(ends) erkannt, ausschließlich über Polling "
        text += "(NSEvent.pressedMouseButtons, 60 Hz während des Zugs)\n"
        return text
    }

    // MARK: - Helpers

    private func render(_ measurement: DragMeasurement, includeLatency: Bool = true) -> String {
        var text = "Ereignisse:          \(measurement.count)\n"
        if let rate = measurement.eventsPerSecond {
            text += "Rate:                \(String(format: "%.1f", rate)) pro Sekunde\n"
        } else {
            text += "Rate:                nicht bestimmbar (weniger als zwei Ereignisse)\n"
        }
        if let gap = measurement.largestGap {
            text += "Größte Lücke:        \(gap.millisecondsText)\n"
        }
        guard includeLatency else { return text }
        if let median = measurement.medianLatency, let worst = measurement.worstLatency {
            text += "Latenz Median:       \(median.millisecondsText)\n"
            text += "Latenz Maximum:      \(worst.millisecondsText)\n"
        } else if measurement.count > 0 {
            text += "Latenz:              nicht messbar — kein Ereignis trug einen brauchbaren\n"
            text += "                     Zeitstempel. Selbst gepostete Ereignisse werden erst\n"
            text += "                     bei der Zustellung gestempelt; nur echte Hardware-\n"
            text += "                     ereignisse tragen einen früheren Stempel.\n"
        }
        return text
    }

    /// Posts a synthetic drag *through the run loop*, one event per timer tick.
    ///
    /// The first version of this posted all forty events in a tight loop with
    /// `usleep`. The tap then reported 753 events per second and a 51.5 ms gap
    /// — both artefacts of a queue draining after the loop finished, not of the
    /// delivery path. Anything that blocks the main thread here measures the
    /// blocking, not the tap. Hence a timer.
    ///
    /// The pointer stays in a four-point corner of the display and moves 40
    /// points sideways: far enough to produce events, too small to pick up a
    /// window and move it.
    @MainActor
    private func scheduleSyntheticDrag() -> SyntheticDriver {
        let driver = SyntheticDriver(motion: .pointer(CGPoint(x: 4, y: 4)), steps: 40)
        driver.start()
        return driver
    }

    /// Moves a real window a few points, repeatedly, so the Accessibility path
    /// has something to notify about — and puts it back afterwards.
    ///
    /// A synthetic *mouse* drag produces no `kAXMovedNotification` at all: the
    /// notification follows the window, not the pointer. Feeding the tap with
    /// synthetic clicks and the observer with nothing would compare a
    /// measurement against a blank. So the window is nudged directly, which is
    /// exactly the event the observer exists for.
    ///
    /// Returns `nil` when no window was reachable — in which case zero events
    /// means "nothing to observe", not "this path is slow".
    @MainActor
    private func scheduleSyntheticWindowMove() -> (driver: SyntheticDriver, name: String)? {
        // The frontmost application first, and only then anything else: the
        // observer attaches to the frontmost window, so moving some other
        // application's window would measure nothing and look like a slow path.
        let own = ProcessInfo.processInfo.processIdentifier
        var candidates = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != own
        }
        if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost.processIdentifier != own {
            candidates.removeAll { $0.processIdentifier == frontmost.processIdentifier }
            candidates.insert(frontmost, at: 0)
        }
        for application in candidates {
            let element = AXUIElementCreateApplication(application.processIdentifier)
            guard
                let window = copyAttribute(element, kAXFocusedWindowAttribute),
                CFGetTypeID(window) == AXUIElementGetTypeID()
            else { continue }
            let windowElement = window as! AXUIElement
            guard let origin = position(of: windowElement) else { continue }
            let driver = SyntheticDriver(motion: .window(windowElement, origin), steps: 40)
            driver.start()
            return (driver, application.localizedName ?? "unbekannt")
        }
        return nil
    }

    private func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private func position(of element: AXUIElement) -> CGPoint? {
        guard let value = copyAttribute(element, kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
        return point
    }

    private func describe(_ access: Accessibility.WindowAccess) -> String {
        switch access {
        case .granted: return "granted"
        case .degraded: return "degraded — Vertrauen gemeldet, aber nur Stellvertreter"
        case .notTrusted: return "notTrusted — keine Freigabe für dieses Bundle"
        case .inconclusive: return "inconclusive — keine App zum Prüfen erreichbar"
        }
    }

    /// The conclusion the numbers support, spelled out so a reader of the report
    /// does not have to derive it — and so a later run that contradicts it is
    /// visibly a contradiction.
    static let comparison = """
    Bewertung
    ------------------------------------------
    Entscheidend ist das Loslassen. Der Tap meldet es als Ereignis, die
    Accessibility-Benachrichtigung meldet es gar nicht — dort muss der
    Mausknopf abgefragt werden, solange der Zug dauert. Für eine Funktion,
    deren ganzer Zweck der Moment des Ablegens ist, ist das der Unterschied
    zwischen messen und schätzen.

    Beide Wege brauchen dieselbe Bedienungshilfen-Freigabe und keinen
    zusätzlichen Dialog. Der Tap kostet dafür Ereignisse, die nichts mit
    Fenstern zu tun haben; die Benachrichtigung kostet einen 60-Hz-Timer und
    kann eine Bewegung nicht von einer fremden Platzierung unterscheiden,
    ohne denselben Mausknopf abzufragen.

    OpenZonr benutzt deshalb den Tap und behält den zweiten Weg als
    Vergleichsmaßstab. Steht in diesem Bericht bei beiden Wegen null
    Ereignisse, ist nichts gemessen worden — dann fehlt die Freigabe oder es
    wurde nicht gezogen, und keine Zahl oben trägt eine Aussage.
    """
}
