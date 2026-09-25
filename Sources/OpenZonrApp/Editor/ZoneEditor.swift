import OpenZonrCore
import SwiftUI

/// Zones, drawn on a miniature of the screen and dragged with the mouse.
///
/// Zones are stored as fractions of the visible frame, which is the right model
/// and the wrong thing to type. `0.5 / 0 / 0.5 / 1` is a sentence about the
/// right half that nobody reads as one; a rectangle on a picture of the screen
/// is the same sentence read at a glance.
///
/// Beim Loslassen rastet das Rechteck an Nachbarkanten (``EdgeSnap``) und ans
/// Zwölftelraster; das Raster wird während der Geste eingeblendet, damit der
/// Sprung eine sichtbare Ursache hat. Zwölftel, weil Hälften, Drittel und
/// Viertel darauf liegen — die üblichen Aufteilungen schließen ohne Naht.
/// Die unbedeckte Fläche wird schraffiert (``LayoutCoverage``); Überlappung
/// ist ausdrücklich erlaubt und bleibt still. Vorlagen kommen aus
/// ``LayoutTemplate`` und melden vor der Anwendung, welche Bindungen dadurch
/// ins Leere zeigen würden.
struct ZoneEditor: View {

    @Bindable var document: ConfigurationDocument
    @State private var display: DisplayAlias?
    @State private var profile: ProfileID?
    @State private var selection: ZoneID?
    /// Kennung der Zone, an der gerade gezogen oder gerastet wird.
    ///
    /// Trägt zwei Aufgaben zugleich: das Zwölftel-Raster erscheint genau
    /// dann, und die aktive Zone weiß es nicht selbst — die Rastentscheidung
    /// gehört zum Editor, nicht zur einzelnen Zone.
    @State private var activeGesture: ZoneID?
    /// Welches der beiden Rechtecke einer Zone gerade bearbeitet wird.
    @State private var layer: EditorLayer = .target
    /// Wahr, solange über Zellen gestrichen wird — schaltet das Raster ein.
    @State private var sweeping = false
    /// Vorschau einer Vorlagenanwendung, bevor sie bestätigt wird.
    @State private var pendingTemplate: PendingTemplateApplication?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let display, let profile, let layout = document.configuration.layout(forDisplay: display, inProfile: profile) {
                HSplitView {
                    canvas(layout: layout, display: display)
                        .frame(minWidth: 380)
                    sidebar(layout: layout, display: display)
                        .frame(minWidth: 260, idealWidth: 280)
                }
            } else {
                ContentUnavailableMessage(
                    symbol: "rectangle.3.group",
                    title: localized("zoneEditor.noLayout.title", "No Layout"),
                    message: localized(
                        "zoneEditor.noLayout.message",
                        "No layout is stored for this combination of profile and display. Choose "
                            + "a different profile or add a layout to the display."
                    )
                )
            }
        }
        .onAppear {
            profile = profile ?? document.configuration.profiles.first?.id
            display = display ?? document.configuration.displays.first?.alias
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker(localized("zoneEditor.profilePicker", "Profile"), selection: $profile) {
                ForEach(document.configuration.profiles) { profile in
                    Text(profile.name).tag(ProfileID?.some(profile.id))
                }
            }
            .frame(maxWidth: 240)

            Picker(localized("zoneEditor.displayPicker", "Display"), selection: $display) {
                ForEach(document.configuration.displays) { descriptor in
                    Text(descriptor.displayName).tag(DisplayAlias?.some(descriptor.alias))
                }
            }
            .frame(maxWidth: 280)

            if let display, let profile, let id = document.configuration.layoutID(forDisplay: display, inProfile: profile) {
                Text(localized("zoneEditor.layoutLabel", "Layout: %@", id.rawValue))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                templatesMenu(display: display, layout: id)
            }
            Spacer()

            // The layer switch. Far right, because it decides the state of
            // the whole canvas rather than belonging to a single zone.
            Picker(localized("zoneEditor.layerPicker", "Layer"), selection: $layer) {
                ForEach(EditorLayer.allCases) { value in
                    Text(value.title).tag(value)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 240)
            .help(
                localized(
                    "zoneEditor.layerPicker.help",
                    "Target frame: where the window ends up. Activation area: where you have to "
                        + "release it."
                )
            )
        }
        .padding(10)
        .sheet(item: $pendingTemplate) { pending in
            TemplatePreviewSheet(
                pending: pending,
                onConfirm: {
                    document.apply {
                        $0.applying(template: pending.template, layout: pending.layout, display: pending.display)
                    }
                    pendingTemplate = nil
                },
                onCancel: { pendingTemplate = nil }
            )
        }
    }

    /// Menü mit den Vorlagen. Klicken ersetzt die Zonen des Layouts, zeigt
    /// aber vorher, welche Bindungen dadurch ins Leere zeigen würden.
    private func templatesMenu(display: DisplayAlias, layout: LayoutID) -> some View {
        Menu(localized("zoneEditor.applyTemplateMenu", "Apply Template")) {
            ForEach(LayoutTemplate.allCases, id: \.rawValue) { template in
                Button(template.displayName) {
                    let preview = document.configuration.previewApplying(
                        template: template,
                        layout: layout,
                        display: display
                    )
                    pendingTemplate = PendingTemplateApplication(
                        template: template,
                        layout: layout,
                        display: display,
                        preview: preview
                    )
                }
            }
        }
        .menuStyle(.borderlessButton)
        .frame(maxWidth: 180)
        .help(
            localized(
                "zoneEditor.applyTemplateMenu.help",
                "Replaces this layout's zones. Bindings to zones that disappear are shown before "
                    + "the application."
            )
        )
    }

    // MARK: - Canvas

    private func canvas(layout: OpenZonrCore.Layout, display: DisplayAlias) -> some View {
        let aspect = canvasAspect(for: display)
        return GeometryReader { geometry in
            let side = fittedRect(in: geometry.size, aspectRatio: aspect.ratio)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .underPageBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                    .frame(width: side.width, height: side.height)

                // Schraffur der unbedeckten Fläche. Eine Beobachtung, kein
                // Fehler: die Fläche ist real und heute unsichtbar.
                UncoveredHatch(zones: layout.zones.map(\.frame), canvas: side)
                    .allowsHitTesting(false)

                // Zwölftel-Raster während einer Geste — und dauerhaft, solange
                // gestrichen werden kann: wer über Zellen zieht, muss sehen,
                // welche Zellen es sind.
                if activeGesture != nil || sweeping {
                    TwelfthGrid(canvas: side)
                        .allowsHitTesting(false)
                }

                // Die Ebene, die gerade nicht bearbeitet wird, als blasse
                // gestrichelte Kontur. Ohne sie wäre der Abstand zwischen
                // Zielrahmen und Trefferfläche unsichtbar — und der ist bei
                // Randauslösung das Einzige, worauf es ankommt.
                // Nur zeichnen, wo sie sich vom bearbeiteten Rechteck
                // unterscheidet. Eine gestrichelte Linie genau auf der Kante
                // der Zone trägt nichts bei und macht das Bild unruhig — ohne
                // Trefferflächen wäre das bei *jeder* Zone der Fall.
                GhostRects(
                    rects: layout.zones
                        .map { (ghost: ghostRect(for: $0), edited: editedRect(for: $0)) }
                        .filter { $0.ghost != $0.edited }
                        .map(\.ghost),
                    canvas: side
                )

                // Unter den Griffen: eine Geste auf freier Fläche zieht auf,
                // eine auf einer Zone bewegt diese Zone. `occupied` ist der
                // Grund, warum das zweite wirklich gilt — siehe dort.
                GridSweepSurface(
                    canvas: side,
                    occupied: layout.zones.map { editedRect(for: $0) }
                ) { isSweeping in
                    sweeping = isSweeping
                } onSweep: { rect in
                    applySweep(rect, layout: layout, display: display)
                }

                ForEach(layout.zones) { zone in
                    ZoneHandle(
                        zone: zone,
                        frame: editedRect(for: zone),
                        isPlaceholder: layer == .activation && zone.activationArea == nil,
                        neighbours: layout.zones.filter { $0.id != zone.id }.map { editedRect(for: $0) },
                        canvas: side,
                        isSelected: selection == zone.id,
                        severity: document.findings.severity(under: .zone(zone.id, layout: layout.id, display: display))
                    ) {
                        selection = zone.id
                    } onGestureChanged: { isActive in
                        activeGesture = isActive ? zone.id : (activeGesture == zone.id ? nil : activeGesture)
                    } onChange: { rect in
                        write(rect, zone: zone.id, layout: layout.id, display: display)
                    }
                }

            }
            .frame(width: side.width, height: side.height)
            // Der feste Bezug für alle Gesten darin — siehe ``ZoneCanvas``.
            // Sitzt auf der Zeichenfläche selbst, nicht auf dem umgebenden
            // Bereich: die Rechtecke der Zonen sind relativ zu ihr gerechnet.
            .coordinateSpace(.named(ZoneCanvas.space))
            // Die Herkunftsbeschriftung wandert weiterhin mit der Vorschau und
            // nicht mit dem Fenster — aber **unter** ihr statt darin. In der
            // Zeichnung lag sie auf den Zonen und verdeckte genau das, was man
            // beim Ändern der Größe ablesen will. Ein unbeschrifteter Wert, der
            // aussieht wie eine Messung, ist die Fehlerklasse aus #18; deshalb
            // steht hier immer eine der beiden Auskünfte, nie keine.
            .overlay(alignment: .bottom) {
                aspectBadge(aspect)
                    .fixedSize()
                    .offset(y: 22)
                    .allowsHitTesting(false)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
        .padding(16)
    }

    /// Wahr, wenn es an der gewählten Zone nichts zu entfernen gibt — keine
    /// Auswahl, oder eine Zone, deren Trefferfläche ohnehin der Zielrahmen ist.
    private func selectedZoneHasNoActivationArea(in layout: OpenZonrCore.Layout) -> Bool {
        guard let selection, let zone = layout.zones.first(where: { $0.id == selection }) else { return true }
        return zone.activationArea == nil
    }

    /// Das Rechteck, das auf der aktiven Ebene bearbeitet wird.
    ///
    /// Auf der Trefferflächen-Ebene fällt eine Zone ohne eigene Trefferfläche
    /// auf den Zielrahmen zurück — dieselbe Regel wie im Treffertest, und der
    /// Griff zeichnet sie gestrichelt, damit „geerbt" sichtbar bleibt.
    private func editedRect(for zone: Zone) -> RelativeRect {
        switch layer {
        case .target: return zone.frame
        case .activation: return zone.activationArea ?? zone.frame
        }
    }

    /// Das Rechteck der jeweils **anderen** Ebene, als blasse Kontur.
    private func ghostRect(for zone: Zone) -> RelativeRect {
        switch layer {
        case .target: return zone.activationArea ?? zone.frame
        case .activation: return zone.frame
        }
    }

    /// Schreibt ein bearbeitetes Rechteck in das Feld der aktiven Ebene.
    private func write(_ rect: RelativeRect, zone: ZoneID, layout: LayoutID, display: DisplayAlias) {
        document.apply {
            switch layer {
            case .target:
                return $0.settingZoneFrame(rect, zone: zone, layout: layout, display: display)
            case .activation:
                return $0.settingZoneActivationArea(rect, zone: zone, layout: layout, display: display)
            }
        }
    }

    /// Was eine Streich-Geste bewirkt.
    ///
    /// Ist eine Zone gewählt, wird **sie** neu bestimmt — das ist der schnelle
    /// Weg, einer Zone eine Trefferfläche zu geben. Ist keine gewählt, entsteht
    /// auf der Zielrahmen-Ebene eine neue Zone.
    ///
    /// Auf der Trefferflächen-Ebene ohne Auswahl passiert nichts: eine
    /// Trefferfläche ohne Zone, zu der sie gehört, gibt es nicht.
    private func applySweep(_ rect: RelativeRect, layout: OpenZonrCore.Layout, display: DisplayAlias) {
        if let selected = selection, layout.zones.contains(where: { $0.id == selected }) {
            write(rect, zone: selected, layout: layout.id, display: display)
            return
        }
        guard layer == .target else { return }

        // Same naming as "add zone"; two ways to create a zone must not
        // produce two kinds of identifier.
        let defaultName = localized("zoneEditor.newZone.defaultName", "New Zone")
        let id = document.configuration.availableZoneID(basedOn: defaultName, layout: layout.id, display: display)
        document.apply {
            $0.adding(
                zone: Zone(id: id, name: defaultName, frame: rect),
                layout: layout.id,
                display: display
            )
        }
        selection = id
    }

    /// Wählt das Vorschau-Seitenverhältnis für den gerade sichtbaren Bildschirm.
    ///
    /// Ist der Bildschirm mit dieser Kennung angeschlossen, kommt das echte
    /// Verhältnis aus seinem sichtbaren Rahmen. Ist er es nicht — oder findet
    /// sich in der Konfiguration kein Eintrag zum Alias, was der Editor sonst
    /// nicht zulässt — bleibt es bei der beschrifteten Schätzung.
    private func canvasAspect(for display: DisplayAlias) -> CanvasAspect {
        guard let descriptor = document.configuration.displays.first(where: { $0.alias == display }) else {
            return .fallback
        }
        return OpenZonrCore.canvasAspect(
            for: descriptor,
            snapshots: document.displaySnapshots,
            reconciler: document.displayReconciler
        )
    }

    @ViewBuilder
    private func aspectBadge(_ aspect: CanvasAspect) -> some View {
        HStack(spacing: 4) {
            Image(systemName: aspect.source == .measured ? "checkmark.seal" : "questionmark.circle")
            Text(aspectDescription(aspect))
        }
        .font(.system(.caption2, design: .monospaced))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
        .foregroundStyle(aspect.source == .measured ? Color.secondary : Color.orange)
        .padding(6)
    }

    private func aspectDescription(_ aspect: CanvasAspect) -> String {
        // Verhältnis auf zwei Nachkommastellen — das entspricht der Genauigkeit,
        // mit der man am Bild einen Unterschied überhaupt bemerkt. Bei
        // Messungen sagen die Punktmaße daneben, was gemessen wurde.
        let ratio = String(format: "%.2f:1", aspect.ratio)
        switch aspect.source {
        case .measured:
            if let size = aspect.visibleSize {
                let pts = "\(Int(size.width.rounded())) × \(Int(size.height.rounded())) pt"
                return localized("zoneEditor.aspectBadge.measuredWithSize", "%@ · visible %@ · measured", ratio, pts)
            }
            return localized("zoneEditor.aspectBadge.measured", "%@ · measured", ratio)
        case .estimated:
            return localized(
                "zoneEditor.aspectBadge.estimated", "%@ · display not connected, aspect ratio estimated", ratio
            )
        }
    }

    private func fittedRect(in size: CGSize, aspectRatio: Double) -> CGSize {
        let width = min(size.width, size.height * aspectRatio)
        return CGSize(width: max(width, 1), height: max(width / aspectRatio, 1))
    }

    // MARK: - Sidebar

    private func sidebar(layout: OpenZonrCore.Layout, display: DisplayAlias) -> some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(layout.zones) { zone in
                    HStack {
                        Text(zone.name)
                        Spacer()
                        FindingBadge(
                            path: .zone(zone.id, layout: layout.id, display: display),
                            index: document.findings
                        )
                    }
                    .tag(zone.id)
                }
            }
            Divider()
            HStack(spacing: 6) {
                Button {
                    addZone(layout: layout, display: display)
                } label: { Image(systemName: "plus") }
                    .help(localized("zoneEditor.addZone.help", "Add Zone"))
                Button {
                    if let selection {
                        document.apply { $0.removingZone(selection, layout: layout.id, display: display) }
                    }
                    selection = nil
                } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)
                    .help(
                        localized(
                            "zoneEditor.removeZone.help",
                            "Remove zone — bindings to it stay and are reported"
                        )
                    )

                // Only on the activation-area layer, and only when there is
                // something to remove. Without this, a once-drawn activation
                // area could never be undone — afterwards it is the target
                // frame again.
                if layer == .activation {
                    Button {
                        if let selection {
                            document.apply {
                                $0.settingZoneActivationArea(nil, zone: selection, layout: layout.id, display: display)
                            }
                        }
                    } label: { Image(systemName: "arrow.uturn.backward") }
                        .disabled(selectedZoneHasNoActivationArea(in: layout))
                        .help(
                            localized(
                                "zoneEditor.removeActivationArea.help",
                                "Remove Activation Area — the target frame applies again afterwards"
                            )
                        )
                }
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(8)

            if let selection, let zone = layout.zones.first(where: { $0.id == selection }) {
                Divider()
                ZoneForm(
                    document: document,
                    zone: zone,
                    layout: layout.id,
                    display: display,
                    visibleSize: measuredVisibleSize(for: display)
                )
            }
        }
    }

    /// Punktmaße des sichtbaren Bereichs, wenn sie gemessen sind — sonst `nil`.
    ///
    /// Das Formular schreibt daneben aus `0,25` ein `1280 × 1344 pt`. Bei einer
    /// Schätzung bleibt der Zusatz weg: eine geschätzte Punktzahl neben einer
    /// gespeicherten Zahl behauptet mehr, als sie belegt.
    private func measuredVisibleSize(for display: DisplayAlias) -> WindowSize? {
        let aspect = canvasAspect(for: display)
        guard aspect.source == .measured else { return nil }
        return aspect.visibleSize
    }

    private func addZone(layout: OpenZonrCore.Layout, display: DisplayAlias) {
        let defaultName = localized("zoneEditor.newZone.defaultName", "New Zone")
        let id = document.configuration.availableZoneID(basedOn: defaultName, layout: layout.id, display: display)
        document.apply {
            $0.adding(
                zone: Zone(
                    id: id,
                    name: defaultName,
                    frame: RelativeRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
                ),
                layout: layout.id,
                display: display
            )
        }
        selection = id
    }
}

/// One draggable rectangle.
private struct ZoneHandle: View {

    let zone: Zone
    /// Das Rechteck, das dieser Griff gerade bewegt — je nach Ebene der
    /// Zielrahmen oder die Trefferfläche. Der Griff weiss nicht, welches; er
    /// bekommt es gesagt und meldet die Änderung über ``onChange`` zurück.
    let frame: RelativeRect
    /// Wahr, wenn die Zone auf dieser Ebene noch **kein** eigenes Rechteck
    /// trägt und hier der Zielrahmen als Platzhalter steht. Wird gestrichelt
    /// gezeichnet, damit „geerbt" und „selbst gezeichnet" nicht gleich
    /// aussehen.
    let isPlaceholder: Bool
    let neighbours: [RelativeRect]
    let canvas: CGSize
    let isSelected: Bool
    let severity: ValidationSeverity?
    let onSelect: () -> Void
    let onGestureChanged: (Bool) -> Void
    let onChange: (RelativeRect) -> Void

    /// The offset of the gesture in progress, kept separate from the stored
    /// frame so that a drag is one edit instead of one edit per mouse event.
    @State private var dragOffset: CGSize = .zero
    @State private var resizeDelta: CGSize = .zero

    var body: some View {
        let rect = CGRect(
            x: frame.x * canvas.width + dragOffset.width,
            y: frame.y * canvas.height + dragOffset.height,
            width: max(frame.width * canvas.width + resizeDelta.width, 12),
            height: max(frame.height * canvas.height + resizeDelta.height, 12)
        )

        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 4)
                .fill(isPlaceholder ? fill.opacity(0.35) : fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            stroke,
                            style: StrokeStyle(
                                lineWidth: isSelected ? 2 : 1,
                                dash: isPlaceholder ? [5, 3] : []
                            )
                        )
                )
                // Nur die gewählte Zone trägt ihren Namen. Bei gestapelten
                // Zonen — dem Fall, für den es die Trefferflächen gibt —
                // liegen sonst mehrere Beschriftungen in derselben Ecke
                // übereinander und keine ist mehr zu lesen. Die Seitenleiste
                // nennt ohnehin alle.
                .overlay(
                    Group {
                        if isSelected {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(zone.name)
                                    .font(.caption)
                                // Während der Geste die Masse, auf die beim
                                // Loslassen gerastet wird — nicht der
                                // gespeicherte Wert. Ohne das zieht man blind:
                                // das Formular rechts zeigt erst nach dem
                                // Loslassen etwas anderes an.
                                if isGesturing {
                                    Text(measurement(of: rect))
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 3))
                            .padding(4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    }
                )

            // The resize grip. A corner rather than eight edge handles: at this
            // size an edge handle is a two-pixel target.
            //
            // Nur an der **gewählten** Zone. Gestapelte Zonen teilen sich ihre
            // untere rechte Ecke — mit einem Griff je Zone liegen dort mehrere
            // übereinander, und welchen man fasst, ist nicht mehr erkennbar.
            // Genau der Fall, für den es die Trefferflächen gibt.
            if isSelected {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 8))
                    .padding(3)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 3))
                    .padding(2)
                    // `highPriorityGesture`, damit der Zug am Griff **nicht**
                    // zusätzlich die Verschiebe-Geste des Elternstapels auslöst.
                    // Vorher änderten sich `dragOffset` und `resizeDelta`
                    // gleichzeitig: die Zone wanderte, während sie wuchs.
                    .highPriorityGesture(
                        DragGesture(coordinateSpace: .named(ZoneCanvas.space))
                            .onChanged { value in
                                onSelect()
                                onGestureChanged(true)
                                resizeDelta = CGSize(width: value.translation.width, height: value.translation.height)
                            }
                            .onEnded { _ in
                                commit(rect: rect)
                                resizeDelta = .zero
                                onGestureChanged(false)
                            }
                    )
            }
        }
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
        .onTapGesture(perform: onSelect)
        .gesture(
            DragGesture(coordinateSpace: .named(ZoneCanvas.space))
                .onChanged { value in
                    onSelect()
                    onGestureChanged(true)
                    dragOffset = value.translation
                }
                .onEnded { _ in
                    commit(rect: rect)
                    dragOffset = .zero
                    onGestureChanged(false)
                }
        )
    }

    /// Wahr, solange an dieser Zone gezogen wird.
    private var isGesturing: Bool {
        dragOffset != .zero || resizeDelta != .zero
    }

    /// Die Masse, auf die beim Loslassen gerastet wird — als Bruchteil und in
    /// Zwölfteln.
    ///
    /// Zwölftel stehen dabei, weil das Raster in Zwölfteln liegt: „4/12" sagt
    /// mehr darüber, ob eine Kante sitzt, als „0,333". Fällt ein Wert nicht auf
    /// ein Zwölftel, steht kein Bruch da statt eines gerundeten — eine Zahl,
    /// die Genauigkeit vortäuscht, ist schlimmer als keine.
    private func measurement(of rect: CGRect) -> String {
        let snapped = snappedRect(from: rect)
        return "\(format(snapped.width)) × \(format(snapped.height))"
    }

    private func format(_ value: Double) -> String {
        let twelfths = value * 12
        let rounded = twelfths.rounded()
        let number = String(format: "%.3f", value)
        guard abs(twelfths - rounded) < 0.001, rounded > 0 else { return number }
        return "\(number) (\(Int(rounded))/12)"
    }

    /// Dasselbe Ergebnis, das ``commit(rect:)`` schreiben würde.
    private func snappedRect(from rect: CGRect) -> RelativeRect {
        let relative = RelativeRect(
            x: rect.minX / canvas.width,
            y: rect.minY / canvas.height,
            width: rect.width / canvas.width,
            height: rect.height / canvas.height
        )
        return EdgeSnap.snap(relative, neighbours: neighbours).clampedToUnitSquare()
    }

    private func commit(rect: CGRect) {
        let relative = RelativeRect(
            x: rect.minX / canvas.width,
            y: rect.minY / canvas.height,
            width: rect.width / canvas.width,
            height: rect.height / canvas.height
        )
        // Zuerst an Nachbarkanten fangen, dann ans Zwölftelraster — sonst
        // rastet ein knapp danebenliegender Zug erst auf das Zwölftel und die
        // Nachbarkante bleibt zwei Pixel daneben. Die zusammengesetzte
        // Rechnung liegt in ``EdgeSnap`` und ist headless bewiesen.
        let snapped = EdgeSnap.snap(relative, neighbours: neighbours)
        onChange(snapped.clampedToUnitSquare())
    }

    private var fill: Color {
        if let severity { return severity.tint.opacity(0.18) }
        return isSelected ? Color.accentColor.opacity(0.25) : Color.accentColor.opacity(0.12)
    }

    private var stroke: Color {
        if let severity { return severity.tint }
        return isSelected ? .accentColor : .secondary
    }
}

/// The numbers behind the rectangle, for the cases where dragging is not precise
/// enough — a zone that has to line up with a zone on another screen, say.
private struct ZoneForm: View {

    @Bindable var document: ConfigurationDocument
    let zone: Zone
    let layout: LayoutID
    let display: DisplayAlias
    /// Punktmaße des sichtbaren Rahmens, nur wenn sie gemessen sind.
    ///
    /// Gesetzt heißt: neben den Brüchen darf ein Punktmaß stehen. `nil` heißt:
    /// die Vorschau selbst ist eine Schätzung, und ein daraus abgeleitetes
    /// Punktmaß wäre es auch — es bleibt bei den Brüchen.
    let visibleSize: WindowSize?

    var body: some View {
        Form {
            TextField(localized("zoneEditor.nameField", "Name"), text: Binding(
                get: { zone.name },
                set: { name in
                    var edited = zone
                    edited.name = name
                    document.apply { $0.updating(zone: edited, layout: layout, display: display) }
                }
            ))
            LabeledContent(localized("zoneEditor.idField", "Identifier")) {
                Text(zone.id.rawValue)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            HStack {
                field("x", \.x, dimension: .width)
                field("y", \.y, dimension: .height)
            }
            HStack {
                field(localized("zoneEditor.widthField", "Width"), \.width, dimension: .width)
                field(localized("zoneEditor.heightField", "Height"), \.height, dimension: .height)
            }
            FieldFindings(
                path: .zoneFrame(zone.id, layout: layout, display: display),
                index: document.findings
            )
            FieldFindings(
                path: .zone(zone.id, layout: layout, display: display),
                index: document.findings
            )
        }
        .formStyle(.columns)
        .padding(10)
    }

    private enum Dimension { case width, height }

    private func field(
        _ title: String,
        _ keyPath: WritableKeyPath<RelativeRect, Double>,
        dimension: Dimension
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField(title, value: Binding(
                    get: { zone.frame[keyPath: keyPath] },
                    set: { value in
                        var edited = zone
                        edited.frame[keyPath: keyPath] = value
                        document.apply { $0.updating(zone: edited, layout: layout, display: display) }
                    }
                ), format: .number.precision(.fractionLength(0...3)))
                .frame(width: 70)
                // `LabeledContent` zeichnet die Beschriftung schon; das
                // `TextField` bekommt denselben Text nur als
                // Bedienungshilfen-Namen, nicht noch einmal sichtbar.
                // Sonst steht dort „Breite Breite 0,3".
                .labelsHidden()

                if let points = pointHint(for: zone.frame[keyPath: keyPath], dimension: dimension) {
                    Text(points)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Rechnet eine gespeicherte Bruchzahl in Punkte um, wenn Punkte gemessen sind.
    ///
    /// Ohne gemessene Maße bleibt der Zusatz weg. Punkte, die aus einem
    /// geschätzten 16:10 abgeleitet wären, sind gerade das, was die
    /// Fehlerklasse aus #18 ausmacht.
    private func pointHint(for fraction: Double, dimension: Dimension) -> String? {
        guard let size = visibleSize else { return nil }
        let base = dimension == .width ? size.width : size.height
        let points = Int((fraction * base).rounded())
        return "≙ \(points) pt"
    }
}

/// Zwölftel-Raster, gezeichnet nur während einer Geste.
///
/// Ein sichtbares Raster erklärt den Sprung beim Loslassen: das Rechteck
/// rastet auf ``RelativeRect/snapped()`` — ohne Anzeige wirkt der Sprung wie
/// eine Willkür des Editors, mit Anzeige wie das, was er ist. Zwölftel, weil
/// Hälften (6/12), Drittel (4/12) und Viertel (3/12) alle darauf liegen.
private struct TwelfthGrid: View {
    let canvas: CGSize

    var body: some View {
        Canvas { context, _ in
            let step = 1.0 / 12.0
            let lineColour = Color.secondary.opacity(0.35)
            for i in 1..<12 {
                let x = Double(i) * step * canvas.width
                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: canvas.height))
                context.stroke(line, with: .color(lineColour), lineWidth: 0.5)
            }
            for i in 1..<12 {
                let y = Double(i) * step * canvas.height
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: canvas.width, y: y))
                context.stroke(line, with: .color(lineColour), lineWidth: 0.5)
            }
        }
        .frame(width: canvas.width, height: canvas.height)
    }
}

/// Schraffur der unbedeckten Fläche.
///
/// Die Rechnung liegt in ``LayoutCoverage``; hier wird nur gezeichnet. Ist
/// nichts unbedeckt, verschwindet die Ansicht ohne Zeichnen — Überlappungen
/// sind ausdrücklich erlaubt und dürfen nicht als Fehler erscheinen.
private struct UncoveredHatch: View {
    let zones: [RelativeRect]
    let canvas: CGSize

    var body: some View {
        Canvas { context, _ in
            let uncovered = LayoutCoverage.uncovered(zones: zones)
            guard !uncovered.isEmpty else { return }
            let hatchColour = Color.orange.opacity(0.45)
            let spacing: CGFloat = 6

            for rect in uncovered {
                let x = rect.x * canvas.width
                let y = rect.y * canvas.height
                let w = rect.width * canvas.width
                let h = rect.height * canvas.height
                let cgRect = CGRect(x: x, y: y, width: w, height: h)
                // Jedes Rechteck bekommt seine eigene Ebene, damit der Clip
                // beim nächsten Rechteck nicht mehr wirkt. ``GraphicsContext``
                // kennt kein Clip-Reset; die Ebene ist der vorgesehene Weg.
                context.drawLayer { layer in
                    layer.clip(to: Path(cgRect))
                    let extent = w + h
                    var stripe = -h
                    while stripe < extent {
                        var line = Path()
                        line.move(to: CGPoint(x: x + stripe, y: y))
                        line.addLine(to: CGPoint(x: x + stripe + h, y: y + h))
                        layer.stroke(line, with: .color(hatchColour), lineWidth: 0.75)
                        stripe += spacing
                    }
                }
            }
        }
        .frame(width: canvas.width, height: canvas.height)
    }
}

/// Eine gerade angeforderte Vorlagenanwendung, die auf Bestätigung wartet.
private struct PendingTemplateApplication: Identifiable {
    let id = UUID()
    let template: LayoutTemplate
    let layout: LayoutID
    let display: DisplayAlias
    let preview: LayoutTemplatePreview
}

/// Zeigt vor der Vorlagenanwendung, welche Bindungen ins Leere zeigen würden.
///
/// Der Editor meldet hängende Bindungen sonst erst *nach* der Anwendung als
/// Befund. Für eine Vorlage ist das zu spät — sie ersetzt ein Layout in einem
/// Schritt. Hier steht die Liste vorher, benannt, mit einem klaren Abbruch.
private struct TemplatePreviewSheet: View {
    let pending: PendingTemplateApplication
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized("zoneEditor.templateSheet.title", "Apply Template %@", pending.template.displayName))
                .font(.headline)

            Text(
                localized(
                    "zoneEditor.templateSheet.subtitle",
                    "Replaces layout %@'s zones on %@.",
                    pending.layout.rawValue, pending.display.rawValue
                )
            )
            .font(.callout)
            .foregroundStyle(.secondary)

            if pending.preview.danglingBindings.isEmpty {
                Text(localized("zoneEditor.templateSheet.noDanglingBindings", "No bindings will point at nothing afterwards."))
                    .foregroundStyle(.secondary)
            } else {
                Text(localized("zoneEditor.templateSheet.danglingBindingsHeader", "Bindings that would dangle afterwards:"))
                    .font(.subheadline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(pending.preview.danglingBindings.enumerated()), id: \.offset) { _, binding in
                            HStack {
                                Text(
                                    localized(
                                        "zoneEditor.templateSheet.danglingBinding",
                                        "Profile %@ · Role %@ → Zone %@",
                                        binding.profile.rawValue, binding.role.rawValue, binding.zone.rawValue
                                    )
                                )
                                .font(.system(.caption, design: .monospaced))
                                Spacer()
                            }
                        }
                    }
                }
                .frame(maxHeight: 160)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator))
            }

            HStack {
                Spacer()
                Button(localized("zoneEditor.templateSheet.cancelButton", "Cancel"), role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(localized("zoneEditor.templateSheet.applyButton", "Apply"), action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }
}
