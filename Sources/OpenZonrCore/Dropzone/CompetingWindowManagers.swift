import Foundation

/// Other window managers that react to the same mouse drag.
///
/// ## Why this exists at all
///
/// Magnet (`com.crowdcafe.windowmagnet`) runs on the author's machine and shows
/// its own overlay while a window is dragged to an edge. Two tools listening to
/// the same drag is not a measurement nuisance the way it was in
/// `docs/tracer-bullet.md` — there it distorted numbers. Here it is a design
/// problem: both would draw an overlay, both would move the window on release,
/// and the window would end up wherever the slower one wrote last.
///
/// ## The decision, and what was rejected
///
/// **OpenZonr detects and says so. It does not compete.** Three alternatives
/// were considered and dropped:
///
/// - *Quietly winning* — placing again after the other tool did, or placing
///   later on purpose. This is a race whose outcome depends on scheduling, so it
///   would work most of the time and fail unreproducibly. A window manager that
///   is right nine times out of ten is worse than one that is honest.
/// - *Suppressing the other tool* — killing or unloading it. Not OpenZonr's
///   property, and no user asked for it.
/// - *Saying nothing* — the user then sees two overlays and one of them being
///   ignored, and has no way of knowing which tool did what.
///
/// What is left is naming it: one line in the log and one line in the menu, once
/// per launch. The user can then quit the other tool, or keep both and know why
/// the result is unpredictable. Dropzones are not switched off automatically —
/// deciding that for the user is the same overreach in the other direction.
public enum CompetingWindowManagers {

    /// A tool known to place windows on drag.
    public struct Known: Hashable, Sendable {
        public var bundleIdentifier: String
        public var name: String
        /// `true` when the tool shows its own overlay during a drag, i.e. when it
        /// collides with dropzones rather than merely with placement.
        public var showsDragOverlay: Bool

        public init(bundleIdentifier: String, name: String, showsDragOverlay: Bool) {
            self.bundleIdentifier = bundleIdentifier
            self.name = name
            self.showsDragOverlay = showsDragOverlay
        }
    }

    /// The list is explicit, not a heuristic.
    ///
    /// There is no attribute that says "this app manages windows"; guessing from
    /// names would accuse innocent apps, and guessing from behaviour would mean
    /// watching other processes, which is exactly what this project refuses to
    /// do. Bundle identifiers are stable and checkable, and an unknown tool
    /// simply goes unmentioned — a missing warning is a smaller failure than a
    /// wrong one.
    public static let known: [Known] = [
        Known(bundleIdentifier: "com.crowdcafe.windowmagnet", name: "Magnet", showsDragOverlay: true),
        Known(bundleIdentifier: "com.knollsoft.Rectangle", name: "Rectangle", showsDragOverlay: true),
        Known(bundleIdentifier: "com.knollsoft.Hookshot", name: "Rectangle Pro", showsDragOverlay: true),
        Known(bundleIdentifier: "com.hegenberg.BetterSnapTool", name: "BetterSnapTool", showsDragOverlay: true),
        Known(bundleIdentifier: "com.divisiblebyzero.Spectacle", name: "Spectacle", showsDragOverlay: false),
        Known(bundleIdentifier: "com.lwouis.alt-tab-macos", name: "AltTab", showsDragOverlay: false),
        Known(bundleIdentifier: "com.pablopunk.Dropover", name: "Dropover", showsDragOverlay: false),
        Known(bundleIdentifier: "cc.ffitch.shottr", name: "Shottr", showsDragOverlay: false),
        Known(bundleIdentifier: "com.surteesstudios.Bartender", name: "Bartender", showsDragOverlay: false),
        Known(bundleIdentifier: "com.if.Amphetamine", name: "Amphetamine", showsDragOverlay: false),
        Known(bundleIdentifier: "com.nikolaeu.yabai", name: "yabai", showsDragOverlay: false),
        Known(bundleIdentifier: "com.koekeishiya.yabai", name: "yabai", showsDragOverlay: false),
        Known(bundleIdentifier: "com.raycast.macos", name: "Raycast", showsDragOverlay: false)
    ]

    /// Those of ``known`` that are among `runningBundleIdentifiers`.
    ///
    /// Order follows ``known`` so the warning text is stable, and duplicates —
    /// yabai ships under two identifiers — are reported once by name.
    public static func detected(among runningBundleIdentifiers: some Sequence<String>) -> [Known] {
        let running = Set(runningBundleIdentifiers)
        var seenNames: Set<String> = []
        return known.filter { candidate in
            guard running.contains(candidate.bundleIdentifier) else { return false }
            return seenNames.insert(candidate.name).inserted
        }
    }

    /// The warning to show once, or `nil` when nothing competes.
    ///
    /// Only tools that show an overlay during a drag get the strong sentence.
    /// The rest are named without drama: they can overwrite a placement, which
    /// the retry log already covers, but they do not fight over the drag itself.
    public static func warning(for detected: [Known]) -> String? {
        guard !detected.isEmpty else { return nil }

        let overlays = detected.filter(\.showsDragOverlay)
        let others = detected.filter { !$0.showsDragOverlay }

        var lines: [String] = []
        if !overlays.isEmpty {
            let names = overlays.map(\.name).joined(separator: ", ")
            lines.append("""
            \(names) \(overlays.count == 1 ? "läuft" : "laufen") parallel und \
            \(overlays.count == 1 ? "blendet" : "blenden") beim Ziehen ebenfalls Zonen ein. \
            Beide Werkzeuge reagieren auf dasselbe Loslassen, und wer zuletzt schreibt, \
            entscheidet über die Fensterlage — das ist nicht vorhersagbar.
            """)
            lines.append("""
            OpenZonr streitet sich darum nicht: es meldet den Fall und lässt die \
            Entscheidung beim Nutzer. Für ein eindeutiges Ergebnis entweder \
            \(names) beenden oder die Dropzones von OpenZonr abschalten \
            (defaults.dropzones.enabled = false).
            """)
        }
        if !others.isEmpty {
            lines.append("""
            Außerdem \(others.count == 1 ? "läuft" : "laufen") \
            \(others.map(\.name).joined(separator: ", ")): \
            \(others.count == 1 ? "greift" : "greifen") auf dieselbe Accessibility-API zu und \
            kann eine Platzierung nachträglich überschreiben.
            """)
        }
        return lines.joined(separator: "\n\n")
    }
}
