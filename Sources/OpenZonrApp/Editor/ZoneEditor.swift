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
                    title: "Kein Layout",
                    message: """
                    Für diese Kombination aus Profil und Bildschirm ist kein Layout \
                    hinterlegt. Wähle ein anderes Profil oder lege im Bildschirm ein \
                    Layout an.
                    """
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
            Picker("Profil", selection: $profile) {
                ForEach(document.configuration.profiles) { profile in
                    Text(profile.name).tag(ProfileID?.some(profile.id))
                }
            }
            .frame(maxWidth: 240)

            Picker("Bildschirm", selection: $display) {
                ForEach(document.configuration.displays) { descriptor in
                    Text(descriptor.displayName).tag(DisplayAlias?.some(descriptor.alias))
                }
            }
            .frame(maxWidth: 280)

            if let display, let profile, let id = document.configuration.layoutID(forDisplay: display, inProfile: profile) {
                Text("Layout: \(id.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                templatesMenu(display: display, layout: id)
            }
            Spacer()
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
        Menu("Vorlage anwenden") {
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
        .help("Ersetzt die Zonen dieses Layouts. Bindungen auf verschwundene Zonen werden vor der Anwendung ausgewiesen.")
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

                // Zwölftel-Raster nur während einer Geste. Erklärt den Sprung
                // beim Loslassen und stört sonst nicht.
                if activeGesture != nil {
                    TwelfthGrid(canvas: side)
                        .allowsHitTesting(false)
                }

                ForEach(layout.zones) { zone in
                    ZoneHandle(
                        zone: zone,
                        neighbours: layout.zones.filter { $0.id != zone.id }.map(\.frame),
                        canvas: side,
                        isSelected: selection == zone.id,
                        severity: document.findings.severity(under: .zone(zone.id, layout: layout.id, display: display))
                    ) {
                        selection = zone.id
                    } onGestureChanged: { isActive in
                        activeGesture = isActive ? zone.id : (activeGesture == zone.id ? nil : activeGesture)
                    } onChange: { frame in
                        document.apply {
                            $0.settingZoneFrame(frame, zone: zone.id, layout: layout.id, display: display)
                        }
                    }
                }

                // Die Herkunftsbeschriftung sitzt in derselben Ebene wie die
                // Vorschau, damit sie mit ihr wandert und nicht mit dem
                // umgebenden Fenster. Ein unbeschrifteter Wert, der aussieht
                // wie eine Messung, ist die Fehlerklasse aus #18 — hier steht
                // deshalb immer eine der beiden Auskünfte, nie keine.
                aspectBadge(aspect)
                    .frame(width: side.width, height: side.height, alignment: .bottomLeading)
                    .allowsHitTesting(false)
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
        .padding(16)
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
        return OpenZonrCore.canvasAspect(for: descriptor, snapshots: document.displaySnapshots)
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
                return "\(ratio) · sichtbar \(pts) · gemessen"
            }
            return "\(ratio) · gemessen"
        case .estimated:
            return "\(ratio) · Bildschirm nicht angeschlossen, Seitenverhältnis geschätzt"
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
                    .help("Zone hinzufügen")
                Button {
                    if let selection {
                        document.apply { $0.removingZone(selection, layout: layout.id, display: display) }
                    }
                    selection = nil
                } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)
                    .help("Zone entfernen — Bindungen darauf bleiben stehen und werden gemeldet")
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
        let id = document.configuration.availableZoneID(basedOn: "Neue Zone", layout: layout.id, display: display)
        document.apply {
            $0.adding(
                zone: Zone(
                    id: id,
                    name: "Neue Zone",
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
        let frame = zone.frame
        let rect = CGRect(
            x: frame.x * canvas.width + dragOffset.width,
            y: frame.y * canvas.height + dragOffset.height,
            width: max(frame.width * canvas.width + resizeDelta.width, 12),
            height: max(frame.height * canvas.height + resizeDelta.height, 12)
        )

        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 4)
                .fill(fill)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(stroke, lineWidth: isSelected ? 2 : 1)
                )
                .overlay(
                    Text(zone.name)
                        .font(.caption)
                        .padding(4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                )

            // The resize grip. A corner rather than eight edge handles: at this
            // size an edge handle is a two-pixel target.
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 8))
                .padding(3)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 3))
                .padding(2)
                .gesture(
                    DragGesture()
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
        .frame(width: rect.width, height: rect.height)
        .offset(x: rect.minX, y: rect.minY)
        .onTapGesture(perform: onSelect)
        .gesture(
            DragGesture()
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
            TextField("Name", text: Binding(
                get: { zone.name },
                set: { name in
                    var edited = zone
                    edited.name = name
                    document.apply { $0.updating(zone: edited, layout: layout, display: display) }
                }
            ))
            LabeledContent("Kennung") {
                Text(zone.id.rawValue)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            HStack {
                field("x", \.x, dimension: .width)
                field("y", \.y, dimension: .height)
            }
            HStack {
                field("Breite", \.width, dimension: .width)
                field("Höhe", \.height, dimension: .height)
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
            Text("Vorlage \(pending.template.displayName) anwenden")
                .font(.headline)

            Text("Ersetzt die Zonen des Layouts \(pending.layout.rawValue) auf \(pending.display.rawValue).")
                .font(.callout)
                .foregroundStyle(.secondary)

            if pending.preview.danglingBindings.isEmpty {
                Text("Keine Bindungen zeigen danach ins Leere.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Danach hängende Bindungen:")
                    .font(.subheadline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(pending.preview.danglingBindings.enumerated()), id: \.offset) { _, binding in
                            HStack {
                                Text("Profil \(binding.profile.rawValue) · Rolle \(binding.role.rawValue) → Zone \(binding.zone.rawValue)")
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
                Button("Abbrechen", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Anwenden", action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
    }
}
