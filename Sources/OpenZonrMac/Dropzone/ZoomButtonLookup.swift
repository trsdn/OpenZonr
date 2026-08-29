import AppKit
import ApplicationServices
import Foundation
import OpenZonrCore

/// Der grüne Fensterknopf als AX-Objekt, für Issue #27.
///
/// Das Systemfenster hat drei Knöpfe im Titelbalken; der grüne ist der
/// „Zoom"-Knopf und über ``kAXZoomButtonAttribute`` am Fensterelement
/// erreichbar. Für die Rechtsklickerkennung braucht es zwei Dinge, die beide
/// hier sitzen: den Rahmen des Knopfes (damit die Trefferprüfung in Core
/// entscheiden kann), und die Referenz auf das Fenster, damit ein späteres
/// „Fenster in Zone platzieren" denselben Weg gehen kann wie beim Ziehen.
public enum ZoomButtonLookup {

    /// Was der Aufrufer am Zeigerpunkt vorfindet.
    ///
    /// Der Fall „Attribut fehlt" ist absichtlich vom Fall „kein Fenster" und
    /// vom Fall „kein Rahmen" getrennt: nur der erste ist ein Signal an den
    /// Nutzer wert (siehe Issue #27, Falle 2 — Finder-Fenster ohne
    /// `AXZoomButton`). Die anderen beiden bedeuten schlicht „hier ist nichts
    /// zu tun", und die dürfen stumm bleiben.
    @MainActor
    public enum Result {
        /// Es gibt ein Fenster mit einem lesbaren Zoom-Knopf-Rahmen.
        ///
        /// Der Rahmen ist in **AppKit**-Koordinaten (unten links), damit er
        /// sich mit dem AppKit-Punkt aus dem Ereignis-Tap vergleichen lässt.
        case found(window: DraggedWindow, zoomButtonFrame: WindowFrame)
        /// Ein Fenster ist da, meldet aber kein ``kAXZoomButtonAttribute``.
        ///
        /// Der Nutzer soll das erkennen können — nichts zu tun ist hier eine
        /// Aussage, nicht ein Aussetzer.
        case zoomButtonUnavailable(window: DraggedWindow)
        /// Unter dem Punkt sitzt gar kein AX-Fenster (Schreibtisch, Menüleiste,
        /// eine App ohne AX-Freigabe). Alltagsfall, still zu behandeln.
        case noWindow
    }

    /// Ermittelt Fenster und Zoom-Knopf-Rahmen am Zeigerpunkt.
    ///
    /// - Parameters:
    ///   - accessibilityPoint: Zeigerposition in **Accessibility**-Koordinaten
    ///     (origin oben links). Genau die, die der Ereignis-Tap liefert.
    ///   - primaryTopY: Achse für die Spiegelung zwischen Accessibility- und
    ///     AppKit-Raum. Falscher Pivot verlegt den Rahmen nicht ein bisschen,
    ///     er verlegt ihn auf den falschen Bildschirm.
    @MainActor
    public static func read(
        atAccessibilityPoint accessibilityPoint: ScreenPoint,
        primaryTopY: Double
    ) -> Result {
        guard let window = EventTapDragTracker.window(
            atAccessibilityPoint: accessibilityPoint,
            primaryTopY: primaryTopY
        ) else {
            return .noWindow
        }

        guard let zoomButton = Accessibility.copyAttribute(
            window.element, kAXZoomButtonAttribute as String
        ) else {
            return .zoomButtonUnavailable(window: window)
        }
        let button = unsafeDowncast(zoomButton, to: AXUIElement.self)

        guard let axFrame = Accessibility.frame(of: button) else {
            // Attribut da, aber keine Position/Size lesbar. Aus Nutzersicht
            // dasselbe wie fehlendes Attribut — es gibt keinen Anker.
            return .zoomButtonUnavailable(window: window)
        }

        let appKitFrame = ScreenArrangement.flipVertically(axFrame, primaryTopY: primaryTopY)
        return .found(window: window, zoomButtonFrame: appKitFrame)
    }
}
