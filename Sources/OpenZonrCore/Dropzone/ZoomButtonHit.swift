import Foundation

/// „Liegt der Zeiger auf dem grünen Fensterknopf?" — als reine Funktion.
///
/// Die Frage klingt trivial, ist es aber nicht: sie hat drei Ausgänge, und jeder
/// einzelne ist eine Zusicherung an den Aufrufer. Die Prüfung sitzt hier in
/// Core, damit sie ohne Bedienungshilfen-Freigabe testbar ist — die AX-Abfrage
/// nach dem Rahmen des `AXZoomButton` gehört nach ``OpenZonrMac``, aber sobald
/// der Rahmen da ist (oder nicht da ist), ist das eine geometrische Frage.
///
/// Warum das eine Aufzählung ist statt einem `Bool`: das Attribut fehlt bei
/// manchen Fenstern (beim Messen zu Issue #27 lieferte ein Finder-Fenster
/// keinen). Ein `false` würde diesen Fall mit „nicht getroffen" verwechseln,
/// und das ist der Unterschied zwischen einem stummen „nichts passiert" und
/// einem sichtbaren „hier ist gerade kein Knopf zu treffen". Das Issue verlangt
/// **erkennbar nichts**, nicht stumm.
public enum ZoomButtonHit: Equatable, Sendable {
    /// Der Punkt liegt im gemeldeten Knopfrahmen.
    case hit
    /// Ein Knopfrahmen ist bekannt, der Punkt liegt aber daneben.
    ///
    /// Das ist der Alltagsfall bei jedem Rechtsklick auf ein Fenster, das
    /// **nicht** auf dem grünen Knopf ist — also praktisch bei fast jedem
    /// Rechtsklick. Nichts weiter zu tun, kein Protokoll, kein Fenster.
    case missed
    /// Das Fenster meldet keinen ``kAXZoomButtonAttribute``.
    ///
    /// Der Rahmen ist unbekannt, also lässt sich nicht sagen, ob der Punkt
    /// darauf lag. Der Aufrufer darf **nicht** stumm bleiben — der Nutzer hat
    /// erkennbar rechtsgeklickt, es passiert aber nichts, und ohne Meldung
    /// bleibt offen warum. Der sichtbare Kanal dafür existiert
    /// (``AppModel.reportPinFailure`` in der App-Schicht), er ist hier
    /// natürlich nicht erreichbar; die Aufzählung reicht ihn nur eindeutig
    /// weiter.
    case buttonUnavailable
}

/// Die geometrische Antwort auf „Liegt der Punkt auf dem Zoom-Knopf?".
///
/// - Parameters:
///   - point: Zeigerposition in **AppKit**-Koordinaten (origin unten links).
///     Denselben Raum benutzt das Ergebnis der AX-Abfrage nach Spiegelung
///     durch ``ScreenArrangement/flipVertically(_:primaryTopY:)``.
///   - zoomButtonFrame: Rahmen des grünen Knopfes in denselben Koordinaten,
///     oder `nil`, wenn das Fenster kein ``kAXZoomButtonAttribute`` liefert.
///
/// Die Kantenregel ist die gleiche wie in ``WindowFrame/contains(_:)`` — linke
/// und untere Kante gehören zum Rahmen, rechte und obere nicht. Damit ist der
/// Übergang zum Nachbarpixel eindeutig, ohne dass Anordnungen entscheiden.
public func zoomButtonHitTest(
    point: ScreenPoint,
    zoomButtonFrame: WindowFrame?
) -> ZoomButtonHit {
    guard let frame = zoomButtonFrame else { return .buttonUnavailable }
    return frame.contains(point) ? .hit : .missed
}
