import Foundation

/// The state of one drag, from mouse-down to mouse-up.
///
/// Pure state: it is handed points, a suppression flag and the candidates under
/// the pointer, and answers what the overlay should show. Nothing here touches
/// AppKit, so every rule below is testable without a window server — which
/// matters, because these rules are the difference between a dropzone that
/// feels calm and one that flickers.
///
/// Three rules earn their place:
///
/// - **Activation distance.** A drag only counts once the pointer has moved a
///   little. Without it, every click on a title bar would flash an overlay and
///   every click would place a window.
/// - **Hysteresis.** Near a shared edge, the most specific zone flips back and
///   forth with a one-point tremor. The highlight only follows once the pointer
///   is decisively inside the new zone.
/// - **Cycling.** Layouts may stack a large zone over small ones, so the
///   pointer is often inside several at once. The most specific is preselected;
///   cycling reaches the rest and then sticks, because a user who has chosen
///   explicitly should not be overruled by the next mouse tremor.
public struct DropZoneSession: Sendable {

    public struct Settings: Hashable, Sendable {
        /// How far the pointer must travel before the overlay appears, in points.
        public var activationDistance: Double
        /// How far inside a new zone the pointer must be to move the highlight.
        public var switchMargin: Double

        public init(activationDistance: Double = 12, switchMargin: Double = 16) {
            self.activationDistance = activationDistance
            self.switchMargin = switchMargin
        }

        public static let standard = Settings()
    }

    public var settings: Settings

    /// Whether a drag is in progress at all.
    public private(set) var isTracking = false
    /// Whether the drag has travelled far enough to be treated as a drag.
    public private(set) var isActive = false
    /// The zone the overlay should highlight, if any.
    public private(set) var highlighted: DropCandidate?

    private var origin: ScreenPoint?
    /// Set once the user cycles, and honoured for as long as it stays reachable.
    private var pinned: DropCandidate?

    public init(settings: Settings = .standard) {
        self.settings = settings
    }

    public mutating func begin(at point: ScreenPoint) {
        origin = point
        isTracking = true
        isActive = false
        highlighted = nil
        pinned = nil
    }

    /// Advances the drag.
    ///
    /// `suppressed` reflects the modifier that means "leave this drag alone".
    /// It clears the highlight but keeps tracking, so releasing the key mid-drag
    /// brings the overlay back rather than requiring a new drag. The explicit
    /// cycle choice is dropped along with the highlight: having asked not to be
    /// helped, the user should not find an old selection waiting.
    public mutating func update(
        at point: ScreenPoint,
        suppressed: Bool,
        candidates: [DropCandidate]
    ) {
        guard isTracking else { return }

        if !isActive, let origin, distance(from: origin, to: point) >= settings.activationDistance {
            isActive = true
        }

        guard !suppressed else {
            highlighted = nil
            pinned = nil
            return
        }
        guard isActive else { return }

        highlighted = choose(from: candidates, at: point)
    }

    /// Moves the highlight to the next zone under the pointer.
    ///
    /// Wraps around, and does nothing while suppressed or before activation —
    /// there is nothing to cycle through yet.
    public mutating func cycle(candidates: [DropCandidate]) {
        guard isActive, !candidates.isEmpty else { return }
        guard let current = highlighted,
              let index = candidates.firstIndex(of: current)
        else {
            highlighted = candidates.first
            pinned = candidates.first
            return
        }
        let next = candidates[(index + 1) % candidates.count]
        highlighted = next
        pinned = next
    }

    /// Ends the drag and reports where the window should go.
    ///
    /// Returns `nil` for a drag that never activated, so a plain click cannot
    /// move a window.
    public mutating func end() -> DropCandidate? {
        let target = isActive ? highlighted : nil
        reset()
        return target
    }

    /// Ends the drag without placing anything.
    public mutating func cancel() {
        reset()
    }

    private mutating func reset() {
        origin = nil
        isTracking = false
        isActive = false
        highlighted = nil
        pinned = nil
    }

    private func choose(from candidates: [DropCandidate], at point: ScreenPoint) -> DropCandidate? {
        if let pinned, candidates.contains(pinned) { return pinned }
        guard let best = candidates.first else { return nil }
        guard let current = highlighted, current != best else { return best }

        // Deliberately not conditioned on `current` still containing the
        // pointer. Crossing a boundary is precisely when it stops containing
        // it, so requiring that would disable hysteresis in the only case it
        // exists for — a one-point overshoot would change the highlight, which
        // is the flicker this is meant to prevent.
        return ZoneGeometry.contains(best.frame, point, margin: settings.switchMargin)
            ? best
            : current
    }

    private func distance(from origin: ScreenPoint, to point: ScreenPoint) -> Double {
        let dx = point.x - origin.x
        let dy = point.y - origin.y
        return (dx * dx + dy * dy).squareRoot()
    }
}
