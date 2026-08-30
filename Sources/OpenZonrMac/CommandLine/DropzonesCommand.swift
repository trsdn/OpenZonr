import AppKit
import OpenZonrCore

/// `openzonr dropzones` — the measurable half of a drag.
///
/// Two things are checked, and they fail independently:
///
/// 1. **The overlay.** Our own windows, so no permission is involved. The
///    command draws the zones of the active profile, reports the panel frame
///    the window server actually gave back, and compares it against the frame
///    the placement path would compute. A mismatch here means the highlight
///    would lie about where a window lands.
/// 2. **The event tap.** Permission-dependent. Reported separately and by its
///    real outcome, so a run without the Accessibility grant produces the
///    honest half-answer rather than nothing.
///
/// This exists because a drag cannot be performed by the tool itself. What can
/// be measured, is.
struct DropzonesCommand {

    var configurationURL: URL
    var seconds: Double

    @MainActor
    func run() throws -> Never {
        let configuration = try ConfigurationLoading.load(from: configurationURL)
        let engine = WatchEngine(configuration: configuration, dryRun: true)

        guard let profile = engine.profileState.profile else {
            if case let .unmatched(explanation) = engine.profileState {
                throw CommandError(explanation)
            }
            throw CommandError("Kein aktives Profil.")
        }
        print("Aktives Profil: \(profile.name) (\(profile.id))")

        // 1 — the event tap, first, because it is the part that can be refused.
        let monitor = DragMonitor()
        do {
            try monitor.start(primaryTopY: { engine.arrangement.primaryTopY }, handler: { _ in })
            print("Ereignis-Tap: erstellt und aktiviert.")
            monitor.stop()
        } catch {
            print("Ereignis-Tap: NICHT erstellt.")
            print(String(describing: error))
        }

        // 2 — the overlay.
        let frames = engine.arrangement.visibleFrames(for: configuration.displays)
        let overlay = DropZoneOverlay()
        var plans: [DropZoneOverlay.Plan] = []

        for descriptor in configuration.displays {
            guard let visibleFrame = frames[descriptor.alias] else {
                print("\(descriptor.alias): kein sichtbarer Frame — übersprungen.")
                continue
            }
            let layoutID = profile.layouts[descriptor.alias] ?? descriptor.defaultLayoutID
            guard let layout = descriptor.layouts.first(where: { $0.id == layoutID }) else {
                print("\(descriptor.alias): Layout \"\(layoutID)\" nicht gefunden — übersprungen.")
                continue
            }
            plans.append(
                DropZoneOverlay.Plan(
                    alias: descriptor.alias,
                    bounds: WindowFrame(
                        x: visibleFrame.x,
                        y: visibleFrame.y,
                        width: visibleFrame.width,
                        height: visibleFrame.height
                    ),
                    zones: layout.zones.map {
                        ($0.id, ZoneGeometry.absoluteFrame(of: $0.frame, in: visibleFrame))
                    },
                    highlighted: layout.zones.first?.id
                )
            )
        }

        guard !plans.isEmpty else { throw CommandError("Keine Displays zum Anzeigen.") }

        // A menu bar app is an accessory; without this the panels never appear.
        NSApplication.shared.setActivationPolicy(.accessory)
        overlay.show(plans)

        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.2, seconds)) {
            for plan in plans {
                let actual = overlay.panelFrame(for: plan.alias)
                let matches = actual.map { frame in
                    abs(frame.x - plan.bounds.x) < 0.5
                        && abs(frame.y - plan.bounds.y) < 0.5
                        && abs(frame.width - plan.bounds.width) < 0.5
                        && abs(frame.height - plan.bounds.height) < 0.5
                } ?? false
                print("""
                \(plan.alias): Soll \(plan.bounds.shortDescription) \
                | Ist \(actual?.shortDescription ?? "kein Panel") \
                | \(matches ? "deckungsgleich" : "ABWEICHUNG")
                """)
                print("  hervorgehoben: \(overlay.highlightedZone(on: plan.alias)?.rawValue ?? "—")")
                for zone in plan.zones {
                    print("  Zone \(zone.id): \(zone.frame.shortDescription)")
                }
            }
            print("sichtbare Panels: \(overlay.visiblePanelCount) von \(plans.count)")
            overlay.tearDown()
            exit(0)
        }

        NSApplication.shared.run()
        exit(0)
    }
}
