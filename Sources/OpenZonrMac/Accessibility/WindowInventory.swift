import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import OpenZonrCore

/// Window server metadata that the Accessibility API does not expose.
///
/// Accessibility knows nothing about `kCGWindowLayer`, yet the layer is the most
/// reliable way to tell a real application window from system furniture. The
/// index is built from `CGWindowListCopyWindowInfo` and joined to Accessibility
/// windows over process id plus bounds — both APIs report bounds in the same
/// top-left based global space, so the join is exact rather than fuzzy.
public struct CoreGraphicsWindowIndex {

    public struct Entry {
        public var layer: Int
        public var bounds: CGRect
        public var title: String?
        public var ownerName: String?
        public var ownerPID: pid_t
    }

    public private(set) var entries: [Entry] = []
    private var byPID: [pid_t: [Entry]] = [:]

    public init(onScreenOnly: Bool = true) {
        let options: CGWindowListOption = onScreenOnly
            ? [.optionOnScreenOnly, .excludeDesktopElements]
            : [.optionAll]
        guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return
        }

        entries = raw.compactMap { info in
            guard
                let layer = info[kCGWindowLayer as String] as? Int,
                let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { return nil }

            return Entry(
                layer: layer,
                bounds: bounds,
                title: info[kCGWindowName as String] as? String,
                ownerName: info[kCGWindowOwnerName as String] as? String,
                ownerPID: pid
            )
        }

        byPID = Dictionary(grouping: entries, by: \.ownerPID)
    }

    /// PID der App, der das vorderste **gewöhnliche** Fenster am Punkt gehört —
    /// oder `nil`, wenn dort keines liegt, es uns selbst gehört oder oben
    /// Systemmöbel steht.
    ///
    /// Gebraucht wird das vor jedem Treffertest der Bedienungshilfen, und zwar
    /// aus einem Grund, der nichts mit Geometrie zu tun hat (Issue #69):
    /// `AXUIElementCopyElementAtPosition` auf dem **systemweiten** Element ist
    /// nur dann der dokumentiert threadsichere Aufruf über Prozessgrenzen, den
    /// der Kommentar in ``EventTapDragTracker`` unterstellt hat. Liegt der Punkt
    /// auf einem **eigenen** Element — dem eigenen Menüleisten-Symbol —, bedient
    /// AppKit die Abfrage im eigenen Prozess und führt seinen hauptthread-
    /// gebundenen Bedienungshilfen-Code auf dem **aufrufenden** Thread aus.
    /// Läuft die Abfrage dort im Hintergrund, während der Hauptthread denselben
    /// Code für dasselbe Statuselement durchläuft, werden AppKits Attributlisten
    /// von zwei Threads zugleich verändert. Genau diese zwei Threads stehen in
    /// allen vier Absturzberichten.
    ///
    /// Der Fenster-Server beantwortet dieselbe Frage, ohne AppKit überhaupt zu
    /// betreten. Mit der PID in der Hand wird der AX-Aufruf auf
    /// `AXUIElementCreateApplication(pid)` eingegrenzt — ein Ziel, das
    /// **garantiert** ein fremder Prozess ist, womit die Threadsicherheit wieder
    /// gilt, auf die sich der Pfad beruft.
    ///
    /// Die Schichtgrenze ist keine neue Regel: ``DefaultWindowFilter`` lässt
    /// ohnehin nur ``DefaultWindowFilter/applicationLayer`` durch. Was hier
    /// abgewiesen wird, hätte die Kette weiter unten also ohnehin verworfen —
    /// die Abfrage wird enger, das Ergebnis nicht ärmer.
    ///
    /// - Parameters:
    ///   - point: Punkt in globalen Koordinaten mit Ursprung oben links
    ///     (derselbe Raum wie `CGEvent.location`; siehe ``ScreenArrangement``).
    ///   - entries: Fenster von **vorne nach hinten**, wie
    ///     `CGWindowListCopyWindowInfo` sie liefert.
    ///   - ownPID: der eigene Prozess.
    public static func ownerOfOrdinaryWindow(
        at point: CGPoint,
        in entries: [Entry],
        excluding ownPID: pid_t
    ) -> pid_t? {
        // Gesucht ist das vorderste **gewöhnliche** Fenster, nicht das vorderste
        // Fenster überhaupt. Der Unterschied ist nicht akademisch: der Dock-
        // Prozess hält ein Fenster auf Ebene 20, dessen Bounds den **ganzen**
        // Hauptbildschirm abdecken (gemessen: 0,0 5120x1440). Wer zuerst das
        // vorderste Fenster nimmt und dann die Ebene prüft, weist damit jeden
        // Punkt des Hauptbildschirms ab und bricht das Ziehen vollständig.
        // Genau das ist passiert, als dieser Torwächter eingeführt wurde.
        //
        // Systemmöbel wird also übersehen, nicht als Sperre gelesen. Das ist
        // auch für die Sicherheitszusage unerheblich: die verlangt nur, dass
        // kein AX-Aufruf gegen den **eigenen** Prozess läuft (#69). Das eigene
        // Menüleisten-Symbol liegt auf Ebene 25 und kann hier deshalb gar nicht
        // gewinnen; ein eigenes gewöhnliches Fenster schon — und genau das
        // fängt die PID-Prüfung ab.
        guard let top = entries.first(where: {
            $0.layer == DefaultWindowFilter.applicationLayer && $0.bounds.contains(point)
        }), top.ownerPID != ownPID
        else { return nil }
        return top.ownerPID
    }

    /// Wie oben, über den eigenen Index.
    public func ownerOfOrdinaryWindow(at point: CGPoint, excluding ownPID: pid_t) -> pid_t? {
        Self.ownerOfOrdinaryWindow(at: point, in: entries, excluding: ownPID)
    }

    /// The layer of the window of `pid` whose bounds match `frame`.
    ///
    /// Falls back to the process's lowest observed layer when no exact match is
    /// found: a window may have been resized between the two API calls, and
    /// guessing "the app's usual layer" is far better than treating an unmatched
    /// window as system furniture.
    public func layer(forPID pid: pid_t, frame: WindowFrame) -> Int? {
        guard let candidates = byPID[pid], !candidates.isEmpty else { return nil }

        let target = frame.cgRect
        if let exact = candidates.first(where: { $0.bounds.integral == target.integral }) {
            return exact.layer
        }
        return candidates.map(\.layer).min()
    }
}

/// Builds ``WindowSnapshot`` values from live Accessibility elements.
public enum WindowInventory {

    /// One window, paired with the element it came from.
    public struct Item {
        public var application: NSRunningApplication
        public var element: AXUIElement
        public var snapshot: WindowSnapshot
    }

    /// Every window of every running application, optionally filtered.
    ///
    /// - Parameters:
    ///   - bundleIdentifier: restricts the listing to one application.
    ///   - includeAccessoryApps: menu bar agents and background apps are hidden
    ///     by default; their windows are exactly the layer noise that the filter
    ///     rejects anyway.
    @MainActor
    public static func allWindows(
        bundleIdentifier: String? = nil,
        includeAccessoryApps: Bool = false
    ) -> [Item] {
        let index = CoreGraphicsWindowIndex()

        return NSWorkspace.shared.runningApplications
            .filter { app in
                guard includeAccessoryApps || app.activationPolicy == .regular else { return false }
                guard let bundleIdentifier else { return true }
                return app.bundleIdentifier == bundleIdentifier
            }
            .sorted { ($0.bundleIdentifier ?? "") < ($1.bundleIdentifier ?? "") }
            .flatMap { app in
                items(for: app, index: index)
            }
    }

    @MainActor
    public static func items(
        for application: NSRunningApplication,
        index: CoreGraphicsWindowIndex,
        isFirstWindowAfterLaunch: Bool = false
    ) -> [Item] {
        let pid = application.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)

        return Accessibility.windows(of: appElement).enumerated().compactMap { offset, window in
            guard let frame = Accessibility.frame(of: window) else { return nil }
            return Item(
                application: application,
                element: window,
                snapshot: snapshot(
                    of: window,
                    application: application,
                    frame: frame,
                    layer: index.layer(forPID: pid, frame: frame) ?? 0,
                    // Position in the app's window list is the best available
                    // proxy when the tool did not observe the launch itself.
                    isFirstWindowAfterLaunch: isFirstWindowAfterLaunch || offset == 0
                )
            )
        }
    }

    @MainActor
    public static func snapshot(
        of window: AXUIElement,
        application: NSRunningApplication,
        frame: WindowFrame,
        layer: Int,
        isFirstWindowAfterLaunch: Bool
    ) -> WindowSnapshot {
        WindowSnapshot(
            bundleIdentifier: application.bundleIdentifier,
            processIdentifier: application.processIdentifier,
            title: Accessibility.string(window, kAXTitleAttribute as String),
            role: Accessibility.string(window, kAXRoleAttribute as String),
            subrole: Accessibility.string(window, kAXSubroleAttribute as String),
            frame: frame,
            isFirstWindowAfterLaunch: isFirstWindowAfterLaunch,
            observedAt: Date(),
            windowLayer: layer
        )
    }
}
