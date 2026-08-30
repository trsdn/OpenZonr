import OpenZonrCore
import SwiftUI

/// Die Übersicht „Wohin geht was?" aus Issue #19.
///
/// Ein maßstabsgetreues Bild der Bildschirmanordnung, in den Zonen die Apps
/// (bzw. Regelnamen), die dort landen — quer über Regeln, Rollen und
/// Bindungen. Der Reiter steht **vor** den drei bestehenden, damit er die
/// Folge (wohin geht was) zeigt, bevor die Ursache (Regel/Rolle/Zone)
/// aufgeklappt wird.
///
/// Was hier bewusst *nicht* gebaut ist:
/// - **Ziehen eines App-Etiketts.** Das griffe in die Regelbindung und in den
///   Zoneneditor derselben Datei; eine parallele Sitzung arbeitet dort.
///   Trennlinie gehalten, im PR benannt.
/// - **Nur laufende Apps.** Die Regeln beschreiben, wohin Fenster *landen
///   würden* — ob die App gerade läuft, ist eine Frage des Augenblicks und
///   nichts, was die Übersicht widerspiegeln sollte.
///
/// Was am Bildschirm hin- und hersteht (Font-Metriken, Umbrüche, exakte
/// Zeichnung von Regel-Etiketten in engen Zonen) ist SwiftUI-Verhalten und
/// gehört zur Klasse „nicht gemessen": ohne Hand an der Maus ist nichts davon
/// belegbar. Dieser Aspekt steht in `docs/regel-editor.md`.
struct OverviewEditor: View {

    @Bindable var document: ConfigurationDocument
    @State private var profileID: ProfileID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let profile = activeProfile {
                Canvas(profile: profile, document: document)
            } else {
                ContentUnavailableMessage(
                    symbol: "rectangle.3.group",
                    title: "Kein Profil gewählt",
                    message: "Wähle oben ein Profil aus, um seine Regel-zu-Zone-Übersicht zu sehen."
                )
            }
        }
        .onAppear {
            profileID = profileID ?? document.configuration.profiles.first?.id
        }
    }

    private var activeProfile: Profile? {
        guard let profileID else { return nil }
        return document.configuration.profiles.first { $0.id == profileID }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Picker("Profil", selection: $profileID) {
                ForEach(document.configuration.profiles) { profile in
                    Text(profile.name).tag(ProfileID?.some(profile.id))
                }
            }
            .frame(maxWidth: 260)
            Spacer()
            Text("Was geht in welche Zone?")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
    }
}

// MARK: - Canvas

/// Die eigentliche Zeichnung. Eigenes View, damit die Layout-Rechnungen
/// (Bildschirm-Umschließung, Zonen-Rechteck) einen Platz haben, an dem sie
/// nicht mit der Auswahl-Logik konkurrieren.
private struct Canvas: View {

    let profile: Profile
    @Bindable var document: ConfigurationDocument

    var body: some View {
        let panels = PlacementOverview.build(for: profile, configuration: document.configuration)
        GeometryReader { geometry in
            content(in: geometry.size, panels: panels)
        }
        .padding(12)
    }

    /// Zeichnet die Bildschirme so, dass sie zueinander im richtigen
    /// Größenverhältnis stehen.
    ///
    /// Die Verhältnisse kommen aus ``canvasAspect(for:snapshots:)`` in Core —
    /// dasselbe Werkzeug, das seit Issue #18 der Zoneneditor verwendet. Ein
    /// zweites Seitenverhältnis wäre der Fehler, den #18 behoben hat, und ist
    /// hier deshalb bewusst *nicht* gebaut.
    private func content(in size: CGSize, panels: [PlacementOverview.DisplayPanel]) -> some View {
        let items = panels.map { panel -> Item in
            let aspect = canvasAspect(for: panel.descriptor, snapshots: document.displaySnapshots)
            return Item(panel: panel, aspect: aspect)
        }

        // Bildschirme nebeneinander stellen, jeder in seinem Verhältnis. Das
        // ist nicht die *echte* geometrische Anordnung — die käme aus den
        // AppKit-Rahmen der Snapshots. Der ehrliche Kompromiss: die Übersicht
        // zeigt, welche Zonen welchen Regel-Verkehr bekommen, und in welchem
        // Größenverhältnis die Bildschirme zueinander stehen. Die tatsächliche
        // Anordnung (links/rechts/oben/unten) ist als „nicht gemessen"
        // markiert und lässt sich später ergänzen, ohne diese Datei
        // umzukrempeln.
        //
        // Warum das eine ehrliche und keine faule Trennung ist: die AppKit-
        // Rahmen der Snapshots sind **relative Punktkoordinaten**, die die
        // Übersicht für eine echte Anordnung erst auf ein Bild abbilden
        // müsste. Diese Abbildung selbst ist Geometrie und lebt in
        // `Sources/OpenZonrCore/Geometry/` — dessen Verantwortung liegt bei
        // der parallelen Sitzung (Issue #21). Für dieses PR gilt der Zettel
        // in der Ecke ehrlicher als eine Zeichnung, die nicht angeschlossen
        // ist.
        let totalRatio = items.map(\.aspect.ratio).reduce(0, +)
        let spacing: CGFloat = 12
        let usableWidth = max(size.width - spacing * CGFloat(max(items.count - 1, 0)), 0)
        let heightByWidth = totalRatio > 0 ? usableWidth / totalRatio : 0
        let displayHeight = max(min(heightByWidth, size.height * 0.85), 0)

        return VStack(alignment: .leading, spacing: 8) {
            notMeasuredNote
            if items.isEmpty || displayHeight <= 0 {
                Text("Für dieses Profil ist kein Layout beschrieben.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(items) { item in
                        DisplayCard(
                            item: item,
                            height: displayHeight,
                            width: CGFloat(item.aspect.ratio) * displayHeight
                        )
                    }
                }
            }
            Spacer()
        }
    }

    @ViewBuilder
    private var notMeasuredNote: some View {
        Text("Nicht gemessen: die räumliche Anordnung (links/rechts/oben/unten). Gezeigt ist das Größenverhältnis, so wie es der Zoneneditor seit #18 verwendet. Regel-zu-Zone-Zuordnung ist gerechnet, nicht geraten.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    struct Item: Identifiable {
        let panel: PlacementOverview.DisplayPanel
        let aspect: CanvasAspect
        var id: DisplayAlias { panel.descriptor.alias }
    }
}

// MARK: - One display

/// Zeichnet einen Bildschirm samt seinen Zonen und den Regel-Etiketten.
private struct DisplayCard: View {

    let item: Canvas.Item
    let height: CGFloat
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            header
            board
        }
        .frame(width: width)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(item.panel.descriptor.displayName)
                .font(.headline)
            HStack(spacing: 6) {
                Text(item.panel.layout.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                switch item.aspect.source {
                case .measured:
                    if let size = item.aspect.visibleSize {
                        Text(String(format: "· %.0f × %.0f pt (gemessen)", size.width, size.height))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                case .estimated:
                    Text("· Bildschirm nicht angeschlossen — 16:10 geschätzt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var board: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(.secondary.opacity(0.6), lineWidth: 1)

            GeometryReader { geometry in
                ForEach(item.panel.zones, id: \.zone.id) { zone in
                    ZoneCell(
                        zone: zone,
                        isFallback: zone.zone.id == item.panel.fallbackZone,
                        boardSize: geometry.size
                    )
                }
            }
            .padding(4)
        }
        .frame(width: width, height: height)
    }
}

/// Eine Zone in der Zeichnung. Rechteck aus `RelativeRect`, darüber die
/// Etiketten der Regeln, die dort landen.
private struct ZoneCell: View {

    let zone: PlacementOverview.ZoneOccupancy
    let isFallback: Bool
    let boardSize: CGSize

    var body: some View {
        let rect = CGRect(
            x: zone.zone.frame.x * boardSize.width,
            y: zone.zone.frame.y * boardSize.height,
            width: zone.zone.frame.width * boardSize.width,
            height: zone.zone.frame.height * boardSize.height
        )
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(background)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: zone.isEmpty ? [3, 3] : []))
            )
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(zone.zone.name)
                            .font(.caption.weight(.semibold))
                        if isFallback {
                            Text("(Auffang)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if zone.isEmpty {
                        Text("keine Regel zeigt hierher")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .italic()
                    } else {
                        ForEach(zone.rules, id: \.ruleID) { label in
                            Text(labelText(for: label))
                                .font(.caption2)
                                .foregroundStyle(label.enabled ? .primary : .secondary)
                                .strikethrough(!label.enabled)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(6)
            }
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }

    private var background: Color {
        if zone.isEmpty {
            return Color.secondary.opacity(0.08)
        }
        return Color.accentColor.opacity(0.14)
    }

    private func labelText(for label: PlacementOverview.RuleLabel) -> String {
        if let bundle = label.bundleIdentifier {
            return "\(label.name) — \(bundle)"
        }
        return "\(label.name) (jede App)"
    }
}
