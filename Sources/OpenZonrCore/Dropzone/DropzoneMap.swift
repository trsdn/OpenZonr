import Foundation

/// One zone of the active profile, as a place a window can be dropped into.
///
/// Everything the overlay needs to draw it and everything the placement needs to
/// use it, in one value: the drag path never looks anything up a second time
/// while the mouse is moving.
public struct Dropzone: Hashable, Sendable, Identifiable {

    public var display: DisplayAlias
    public var zone: ZoneID
    /// Label shown in the overlay, e.g. "rechts oben".
    public var name: String
    /// The zone as it stands in the layout, for diagnostics and tests.
    public var relativeFrame: RelativeRect
    /// The zone in absolute **AppKit** coordinates, origin bottom-left.
    public var frame: WindowFrame
    /// The usable area of the display this zone belongs to.
    ///
    /// Carried along so that "which display is the pointer over" never depends
    /// on the pointer being inside a zone. Zones need not cover their screen —
    /// a layout may leave gaps, and the menu bar is outside every zone — and an
    /// overlay that vanished whenever the pointer crossed a gap would flicker
    /// through every drag.
    public var visibleFrame: VisibleFrame
    /// ``Layout/margin`` of the zone's layout, as a fraction of the display.
    ///
    /// Not applied to ``frame``: the hit test stays gap-free. Applied only by
    /// ``placement``, through ``ZoneGeometry/placementFrame(for:margin:in:)``,
    /// so a dropped window lands where automatic placement would put it.
    public var margin: Double
    /// Wo losgelassen werden muss, absolut, im selben Raum wie ``frame``.
    ///
    /// Gleich ``frame``, solange die Zone keine eigene Trefferfläche trägt.
    /// Getrennt mitgeführt, weil ein Stapel überlappender Zielrahmen sonst
    /// nicht auflösbar ist: erst disjunkte Trefferflächen machen jede Ebene
    /// einzeln erreichbar.
    ///
    /// Der ``margin`` wirkt hierauf **nicht**. Er ist ein Platzierungsrand;
    /// eine Fläche zu schrumpfen, die der Nutzer selbst gezeichnet hat, wäre
    /// Bevormundung.
    public var activationFrame: WindowFrame

    public init(
        display: DisplayAlias,
        zone: ZoneID,
        name: String,
        relativeFrame: RelativeRect,
        frame: WindowFrame,
        visibleFrame: VisibleFrame,
        margin: Double = 0,
        activationFrame: WindowFrame? = nil
    ) {
        self.display = display
        self.zone = zone
        self.name = name
        self.relativeFrame = relativeFrame
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.margin = margin
        // Vorgabe statt eigenem Feldtyp: jede bestehende Konstruktionsstelle —
        // auch jeder von Hand gebauter Testfall — bleibt gültig.
        self.activationFrame = activationFrame ?? frame
    }

    public var id: String { "\(display)/\(zone)" }

    /// The zone as a placement target.
    ///
    /// Deliberately the same type the rule path produces, so that a dropped
    /// window and an automatically placed one go through
    /// ``RetryingWindowPlacer`` in exactly the same way. `usedFallback` is
    /// `false` because nothing fell back: the user pointed at this zone.
    public var placement: ResolvedPlacement {
        // Margin 0 keeps the exact zone frame (also for hand-built test zones).
        let placed = margin > 0
            ? ZoneGeometry.placementFrame(for: relativeFrame, margin: margin, in: visibleFrame)
            : frame
        return ResolvedPlacement(frame: placed, display: display, zone: zone, usedFallback: false)
    }
}

/// The zones of the active profile, and which one a pointer is over.
///
/// Pure on purpose. Everything that decides *where* a dragged window will land
/// is computable from a point, a configuration and the visible frames — none of
/// which needs an event, a screen or the Accessibility permission. That is what
/// makes the interesting half of this feature testable at all: observing a drag
/// requires a grant that only the user can give by hand.
public enum DropzoneMap {

    /// Every zone the active profile shows, across all configured displays.
    ///
    /// Order is the configuration's: displays in file order, zones in layout
    /// order. The overlay draws in this order and the hit test breaks ties with
    /// it, so a layout that is ambiguous is at least consistently ambiguous.
    ///
    /// Displays without a visible frame are skipped — they are described but not
    /// attached, and a zone on a monitor that is not there cannot be dropped
    /// into.
    ///
    /// Der Rand wirkt nicht auf ``Dropzone/frame`` (Treffertest bleibt lückenlos),
    /// sondern nur auf ``Dropzone/placement``.
    public static func zones(
        in configuration: Configuration,
        profile: ProfileID,
        visibleFrames: VisibleFrames
    ) -> [Dropzone] {
        var result: [Dropzone] = []
        for descriptor in configuration.displays {
            guard let visibleFrame = visibleFrames[descriptor.alias],
                  let layout = configuration.layout(forDisplay: descriptor.alias, inProfile: profile)
            else { continue }

            for zone in layout.zones {
                result.append(
                    Dropzone(
                        display: descriptor.alias,
                        zone: zone.id,
                        name: zone.name,
                        relativeFrame: zone.frame,
                        frame: ZoneGeometry.absoluteFrame(for: zone.frame, in: visibleFrame),
                        visibleFrame: visibleFrame,
                        margin: layout.margin,
                        activationFrame: zone.activationArea.map {
                            ZoneGeometry.absoluteFrame(for: $0, in: visibleFrame)
                        }
                    )
                )
            }
        }
        return result
    }

    /// The zone under `point`, or `nil` when the pointer is over none.
    ///
    /// - Parameter point: the pointer in **AppKit** coordinates, origin
    ///   bottom-left, the same space the zone frames are in.
    ///
    /// Geprüft wird die **Trefferfläche**, nicht der Zielrahmen. Ohne eigene
    /// Trefferfläche sind beide gleich, und dann entscheidet wie bisher die
    /// kleinste Fläche: ein Fokusfenster über zwei Hälften enthält jeden Punkt
    /// der Hälften, und gewänne es, wären die Hälften unerreichbar.
    ///
    /// Diese Regel allein reicht aber nicht, und das war der Fehler, den dieses
    /// Feld behebt: sie kippt das Problem nur auf die andere Seite. Deckt ein
    /// Stapel kleinerer Zonen eine grössere lückenlos ab, ist die **grosse**
    /// unerreichbar — gemessen an der Ebene des Autors, in der „Rechts außen"
    /// von „Rechts oben" und „Rechts unten" vollständig überdeckt wurde. Mit
    /// einem Rechteck für beides ist das nicht lösbar; mit getrennten
    /// Trefferflächen schon, weil die disjunkt sein dürfen, auch wenn die
    /// Zielrahmen es nicht sind.
    ///
    /// Equal areas are decided by display alias and then zone identifier, never
    /// by array order, so the same pointer always produces the same answer.
    public static func zone(at point: ScreenPoint, in zones: [Dropzone]) -> Dropzone? {
        var best: Dropzone?
        for candidate in zones where candidate.activationFrame.contains(point) {
            guard let current = best else {
                best = candidate
                continue
            }
            if candidate.activationFrame.area < current.activationFrame.area {
                best = candidate
            } else if candidate.activationFrame.area == current.activationFrame.area,
                      isOrderedBefore(candidate, current) {
                best = candidate
            }
        }
        return best
    }

    /// The zones that lie on the display under `point`.
    ///
    /// What the overlay shows: the zones of the screen the pointer is on, not of
    /// every screen. Lighting up four monitors because a window is being nudged
    /// on one of them is noise, and on the author's desk it is a lot of noise.
    public static func zones(onDisplayUnder point: ScreenPoint, in zones: [Dropzone]) -> [Dropzone] {
        // By the display's own area, not by which zone was hit: a pointer in a
        // gap between zones, or over the menu bar, is still on that display and
        // the zones must stay on screen.
        if let display = zones.first(where: { $0.visibleFrame.contains(point) })?.display {
            return zones.filter { $0.display == display }
        }
        guard let hit = zone(at: point, in: zones) else { return [] }
        return zones.filter { $0.display == hit.display }
    }

    /// The small pin badge each zone carries while the overlay is up.
    ///
    /// A **pure function** of the zone's activation frame, deliberately. Dropping *and
    /// pinning* used to be two moments — drop, then answer a question — with a
    /// gesture wedged between them. Moving the decision into the drag itself
    /// means the drop and the pin land in one motion: release on the zone for a
    /// one-off placement, release on the badge for the same placement plus the
    /// rule via ``QuickPin``. The badge is the second target the mouse can hit;
    /// it is not a menu, a button or a hover state, and it does not depend on
    /// the Accessibility permission to be true — so the hit test lives here and
    /// is tested headlessly.
    ///
    /// The badge is placed in the **top-right corner** of the inset the overlay
    /// draws (see ``DropzoneOverlayView`` in `OpenZonrApp`). Choosing a corner
    /// rather than the centre is not decoration: the centre of a small zone
    /// covers the whole zone, so every drop would be a pin, and the *drop
    /// without pinning* case would be unreachable. A corner keeps most of the
    /// zone free for the plain drop.
    ///
    /// - Returns: The badge frame in the same AppKit coordinates as
    ///   ``Dropzone/frame``, or `nil` when the zone is too small to place a
    ///   badge without swallowing the whole zone. The overlay must not draw a
    ///   badge whose hit test would answer *yes* for every point of the zone —
    ///   that would remove the plain-drop path from the layouts that need it
    ///   most.
    ///
    ///   Eine Trefferfläche unter `4·2 + 8·2 + 24 + 24 = 72` Punkten in der
    ///   kürzeren Kante trägt deshalb **keine** Marke. Das Platzieren
    ///   funktioniert dort weiter; nur die Regel muss dann über das Menü
    ///   entstehen.
    public static func pinBadgeFrame(for zone: Dropzone) -> WindowFrame? {
        // An der Trefferfläche, nicht am Zielrahmen: die Marke ist das zweite
        // Ziel derselben Mausbewegung. Bei Randauslösung läge sie sonst am
        // anderen Ende des Bildschirms und wäre unbenutzbar. Ohne eigene
        // Trefferfläche sind beide gleich und nichts ändert sich.
        let frame = zone.activationFrame
        // Same values as the on-screen badge; kept here as constants so the
        // hit test and the drawing agree without one importing the other.
        let inset: Double = 4
        let padding: Double = 8
        let size: Double = 24

        // A zone must have room for the drawing inset the overlay applies to
        // every zone, plus the badge and its padding, and still leave a strip
        // for the plain drop. Twice the badge's smallest side is the strip.
        let required = inset * 2 + padding * 2 + size + size
        guard frame.width >= required, frame.height >= required else { return nil }

        // Top-right, in AppKit coordinates (origin at the bottom-left).
        let x = frame.x + frame.width - inset - padding - size
        let y = frame.y + frame.height - inset - padding - size
        return WindowFrame(x: x, y: y, width: size, height: size)
    }

    /// Whether `point` is on the badge of `zone`.
    ///
    /// A drop that lands here writes a rule; anywhere else in the zone is a
    /// one-off. Both are decisions the user makes with the mouse, in the same
    /// gesture, and neither asks a question afterwards.
    ///
    /// - Returns: `false` when the zone has no badge — a zone too small to
    ///   carry one has no *drop and pin* target, only the plain drop. The
    ///   caller can therefore treat every drop on such a zone as a one-off
    ///   without a second code path.
    public static func isOnPinBadge(_ point: ScreenPoint, of zone: Dropzone) -> Bool {
        guard let badge = pinBadgeFrame(for: zone) else { return false }
        return badge.contains(point)
    }

    private static func isOrderedBefore(_ lhs: Dropzone, _ rhs: Dropzone) -> Bool {
        lhs.display == rhs.display ? lhs.zone < rhs.zone : lhs.display < rhs.display
    }
}
