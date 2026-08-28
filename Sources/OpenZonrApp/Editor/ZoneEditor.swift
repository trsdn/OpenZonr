import OpenZonrCore
import SwiftUI

/// Zones, drawn on a miniature of the screen and dragged with the mouse.
///
/// Zones are stored as fractions of the visible frame, which is the right model
/// and the wrong thing to type. `0.5 / 0 / 0.5 / 1` is a sentence about the
/// right half that nobody reads as one; a rectangle on a picture of the screen
/// is the same sentence read at a glance.
///
/// On release the rectangle is snapped to a twelfth of the screen and clamped
/// to the unit square. Twelfths because halves, thirds and quarters all land on
/// them, so the common layouts close without a gap — a two-pixel seam between
/// two zones is invisible in the editor and very visible on the screen.
struct ZoneEditor: View {

    @Bindable var document: ConfigurationDocument
    @State private var display: DisplayAlias?
    @State private var profile: ProfileID?
    @State private var selection: ZoneID?

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
            }
            Spacer()
        }
        .padding(10)
    }

    // MARK: - Canvas

    private func canvas(layout: OpenZonrCore.Layout, display: DisplayAlias) -> some View {
        GeometryReader { geometry in
            // 16:10 is a stand-in, not a measurement: the real aspect ratio of a
            // display is only known while it is connected, and the editor has to
            // work for a screen that is currently unplugged.
            let side = fittedRect(in: geometry.size, aspectRatio: 16.0 / 10.0)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(nsColor: .underPageBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator))
                    .frame(width: side.width, height: side.height)

                ForEach(layout.zones) { zone in
                    ZoneHandle(
                        zone: zone,
                        canvas: side,
                        isSelected: selection == zone.id,
                        severity: document.findings.severity(under: .zone(zone.id, layout: layout.id, display: display))
                    ) {
                        selection = zone.id
                    } onChange: { frame in
                        document.apply {
                            $0.settingZoneFrame(frame, zone: zone.id, layout: layout.id, display: display)
                        }
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
        }
        .padding(16)
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
                ZoneForm(document: document, zone: zone, layout: layout.id, display: display)
            }
        }
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
    let canvas: CGSize
    let isSelected: Bool
    let severity: ValidationSeverity?
    let onSelect: () -> Void
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
                            resizeDelta = CGSize(width: value.translation.width, height: value.translation.height)
                        }
                        .onEnded { _ in
                            commit(rect: rect)
                            resizeDelta = .zero
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
                    dragOffset = value.translation
                }
                .onEnded { _ in
                    commit(rect: rect)
                    dragOffset = .zero
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
        onChange(relative.snapped().clampedToUnitSquare())
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
                field("x", \.x)
                field("y", \.y)
            }
            HStack {
                field("Breite", \.width)
                field("Höhe", \.height)
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

    private func field(_ title: String, _ keyPath: WritableKeyPath<RelativeRect, Double>) -> some View {
        LabeledContent(title) {
            TextField(title, value: Binding(
                get: { zone.frame[keyPath: keyPath] },
                set: { value in
                    var edited = zone
                    edited.frame[keyPath: keyPath] = value
                    document.apply { $0.updating(zone: edited, layout: layout, display: display) }
                }
            ), format: .number.precision(.fractionLength(0...3)))
            .frame(width: 70)
        }
    }
}
