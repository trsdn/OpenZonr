import AppKit
import OpenZonrCore
import OpenZonrMac

/// Das Rechtsklickmenü am grünen Fensterknopf — Issue #27.
///
/// Ein `NSMenu`, keine `NSAlert` und kein Panel: die Geste ist ein Rechtsklick,
/// die native Antwort darauf ist ein Menü. Es enthält die Zonen des Bildschirms
/// unter dem Fenster, beim Namen. Ein Klick auf einen Eintrag verschiebt das
/// Fenster einmalig in die Zone. Wird die Option-Taste (⌥) gedrückt gehalten,
/// wird zusätzlich eine Regel geschrieben — über denselben ``QuickPin``, den
/// auch der Menüleisten-Eintrag „Aktuelles Fenster hier festhalten“ und die
/// Anheft-Marke beim Ziehen benutzen. Kein zweiter Pfad.
///
/// Zwei Zusicherungen, die auch beim Anhören von Änderungen halten müssen:
///
/// 1. **Kein zweiter Pfad zur Regel.** Der ⌥-Klick geht nicht direkt in die
///    Konfiguration, sondern durch ``AppModel/apply(_:to:)``. Objections und
///    Sichtbarkeit der Fehlermeldung sind damit dieselben wie beim
///    Menüleisten-Weg.
/// 2. **Alle Fenster-Aktionen gehen über die schon vorhandenen Wege.** Das
///    einmalige Platzieren nimmt ``WatchEngine/place(dropped:application:into:)``
///    — dieselbe Funktion, die auch das Ziehen aufruft.
@MainActor
final class ZoomButtonMenu: NSObject, NSMenuDelegate {

    private let model: AppModel
    /// Das gerade offene Menü, damit ein zweiter Rechtsklick nicht zwei
    /// stapelt. `NSMenu` ist modal in seinem Tracking-Loop, aber das schließt
    /// weitere Rückrufe des Taps nicht aus (der Loop läuft, der Tap läuft).
    private var openMenu: NSMenu?

    init(model: AppModel) {
        self.model = model
    }

    /// Öffnet das Menü, wenn am Zeigerpunkt tatsächlich der grüne Knopf sitzt.
    ///
    /// Nimmt das **schon vorliegende** Ergebnis der AX-Abfrage entgegen. Die
    /// Abfrage selbst passiert im ``EventTapDragTracker`` außerhalb des
    /// Tap-Rückrufs (`Task.detached`), damit weder sie noch das anschließende
    /// modale `NSMenu.popUp` den Thread blockieren, der den Tap bedient —
    /// dieselbe Zusicherung wie für den Zug-Pfad in #26/#29.
    ///
    /// Fehlt `kAXZoomButtonAttribute` (gemessen an einem Finder-Fenster) oder
    /// war unter dem Punkt kein Fenster, endet die Aktion **still**. Der
    /// Rechtsklick landet in vielen Fenstern; ein sichtbarer Fehler an dieser
    /// Stelle träfe nicht den Nutzerwunsch „Menü am Knopf", sondern jeden
    /// beiläufigen Rechtsklick — das wäre Lärm.
    func show(atAppKitPoint appKitPoint: ScreenPoint, lookup: ZoomButtonLookup.Result) {
        switch lookup {
        case .noWindow:
            // Rechtsklick irgendwo im Nichts — Alltag.
            return

        case .zoomButtonUnavailable:
            // Attribut fehlt (Finder-Fenster im Messfall). Der Klick war
            // vermutlich gar nicht am Knopf gemeint — das Attribut fehlt für
            // das ganze Fenster, nicht für einen Ort in ihm. Still bleiben:
            // eine Meldung hier würde bei einer App wie dem Finder auf
            // *jeden* Rechtsklick sprechen. Siehe Issue #27, Kommentar zu
            // PR #30.
            return

        case let .found(window, zoomButtonFrame):
            let hit = zoomButtonHitTest(point: appKitPoint, zoomButtonFrame: zoomButtonFrame)
            switch hit {
            case .missed:
                // Ganz normaler Rechtsklick irgendwo im Titelbalken oder Fenster.
                // Kein Menü, kein Protokoll — der Alltagsfall.
                return
            case .buttonUnavailable:
                // Kann hier nicht eintreten (der Rahmen wurde gerade gelesen),
                // aber der Vollständigkeit halber.
                return
            case .hit:
                let arrangement = ScreenArrangement(snapshots: SystemDisplays.snapshots())
                presentMenu(for: window, at: appKitPoint, arrangement: arrangement)
            }
        }
    }

    private func presentMenu(
        for window: DraggedWindow,
        at point: ScreenPoint,
        arrangement: ScreenArrangement
    ) {
        guard let configuration = model.document?.configuration ?? model.configuration else {
            model.reportPinFailure("Es ist keine Konfiguration geladen.")
            return
        }
        guard let profile = model.activeProfile else {
            model.reportPinFailure(
                "Kein Profil ist aktiv — ohne Profil ist nicht bekannt, was „hier“ bedeutet."
            )
            return
        }

        let visibleFrames = arrangement.visibleFrames(for: configuration.displays)
        // Welcher Bildschirm ist gemeint? Der, auf dem das Fenster mehrheitlich
        // liegt — genau die Regel, die auch ``PinTargetResolver`` verwendet.
        guard let displayAlias = PinTargetResolver.display(
            containing: window.frame,
            in: configuration,
            visibleFrames: visibleFrames
        ) else {
            model.reportPinFailure(
                "Das Fenster von „\(window.applicationName)“ liegt auf keinem konfigurierten Bildschirm."
            )
            return
        }

        let zones = DropzoneMap.zones(
            in: configuration,
            profile: profile.id,
            visibleFrames: visibleFrames
        ).filter { $0.display == displayAlias }

        guard !zones.isEmpty else {
            model.reportPinFailure(
                "Für den Bildschirm „\(displayAlias)“ gibt es im Profil „\(profile.name)“ keine Zonen."
            )
            return
        }

        let menu = NSMenu(title: "OpenZonr")
        menu.delegate = self
        menu.autoenablesItems = false

        let header = NSMenuItem(
            title: "\(window.applicationName) → \(displayAlias)",
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        for zone in zones {
            let item = ZoomButtonMenuItem(
                title: zone.name,
                zone: zone,
                window: window,
                bundleIdentifier: window.bundleIdentifier,
                applicationName: window.applicationName,
                profileID: profile.id,
                model: model
            )
            item.target = item
            item.action = #selector(ZoomButtonMenuItem.chosen(_:))
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let hint = NSMenuItem(
            title: "⌥ + Klick: als Regel festhalten",
            action: nil,
            keyEquivalent: ""
        )
        hint.isEnabled = false
        menu.addItem(hint)

        openMenu = menu
        // popUp öffnet das Menü an einer Bildschirmposition. AppKit-Koordinaten,
        // origin unten links — dieselben, die der Tap in `appKitPoint` liefert.
        menu.popUp(positioning: nil, at: NSPoint(x: point.x, y: point.y), in: nil)
    }

    // MARK: - NSMenuDelegate

    func menuDidClose(_ menu: NSMenu) {
        if openMenu === menu { openMenu = nil }
    }
}

/// Ein Menüpunkt weiß, welche Zone er meint und welches Fenster er verschiebt.
///
/// Ein eigener `NSMenuItem`-Untertyp statt einer Closure, weil AppKits Menü-
/// Aktionsselektor keine Closure kennt und Assoziationstabellen an ObjC-Typen
/// hier nur Nebel wären.
@MainActor
private final class ZoomButtonMenuItem: NSMenuItem {

    private let zone: Dropzone
    private let window: DraggedWindow
    private let bundleIdentifier: String?
    private let applicationName: String
    private let profileID: ProfileID
    private weak var model: AppModel?

    init(
        title: String,
        zone: Dropzone,
        window: DraggedWindow,
        bundleIdentifier: String?,
        applicationName: String,
        profileID: ProfileID,
        model: AppModel
    ) {
        self.zone = zone
        self.window = window
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.profileID = profileID
        self.model = model
        super.init(title: title, action: nil, keyEquivalent: "")
    }

    required init(coder: NSCoder) {
        fatalError("Nicht aus dem Interface Builder zu laden.")
    }

    @objc func chosen(_ sender: NSMenuItem) {
        guard let model else { return }

        // Fenster erst einmal in die Zone bringen — derselbe Weg wie beim Drop.
        // Das ist die einmalige Platzierung. Der Regelfall („mit ⌥“) kommt
        // erst danach, damit die Reihenfolge sichtbar richtig ist: der Nutzer
        // sieht das Fenster wandern, und wenn er die Regel wollte, ist sie
        // gleich danach eingetragen.
        if let engine = model.engine,
           let application = NSRunningApplication(processIdentifier: window.processIdentifier) {
            engine.place(dropped: window.element, application: application, into: zone.placement)
        } else {
            model.reportPinFailure(
                "Fenster von „\(applicationName)“ ist nicht mehr erreichbar; nichts wurde platziert."
            )
            return
        }

        // ⌥ hält — daraus wird die Regel. Ohne ⌥ endet die Aktion hier.
        //
        // Der Modifier wird beim *Klick* im aktuellen `NSEvent` gelesen, nicht
        // beim Öffnen des Menüs. Das ist der Punkt: der Nutzer entscheidet erst
        // im letzten Moment, ob die Regel geschrieben wird. Dasselbe Muster
        // wie in AppKits eigenen Menüs (Kopieren-Pfad usw.).
        let wantsRule = NSEvent.modifierFlags.contains(.option)
        guard wantsRule else { return }

        guard let bundleIdentifier, !bundleIdentifier.isEmpty else {
            model.reportPinFailure(
                "„\(applicationName)“ meldet keine Bundle-Kennung; ohne sie lässt sich keine Regel schreiben."
            )
            return
        }
        guard let base = model.document?.configuration ?? model.configuration else {
            model.reportPinFailure("Es ist keine Konfiguration geladen.")
            return
        }

        let request = QuickPin.Request(
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            profile: profileID,
            target: QuickPin.Target(display: zone.display, zone: zone.zone)
        )
        model.apply(request, to: base)
    }
}
