import OpenZonrCore
import OpenZonrMac
import SwiftUI

/// Die Dry-Run-Zeile aus Issue #19 als eigenes View.
///
/// Zeigt bei jeder ausgewählten Regel eine Vorschau, was passieren würde,
/// wenn die Regel *jetzt* für die zugehörige App feuerte. Für den Fall, dass
/// die App gerade läuft, wird ihr Fenster durch dieselbe Engine geschickt, die
/// später auch die Platzierung ausführt — die Zeile ist dann eine Messung.
/// Läuft die App nicht, ist die Zeile bedingt und benennt jedes Kriterium,
/// das die Regel prüft und das ohne Fenster nicht entschieden werden kann.
///
/// Warum eine eigene View: das Erzeugen der Zeile ist der eine Ort, an dem der
/// Editor `WindowInventory` befragt. Kapselung genügt, damit die restliche
/// Form-Datei so bleibt, wie sie ist — der eigentliche Wert liegt in Core
/// (``DryRunPreview`` + ``DryRunPreviewFormatter``), diese View bindet an.
struct RuleDryRunLine: View {

    let rule: PlacementRule
    let configuration: Configuration
    let snapshots: [DisplaySnapshot]

    var body: some View {
        let line = DryRunPreviewFormatter.line(
            for: computedResult,
            subject: subject,
            configuration: configuration
        )

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: line.isConditional
                      ? "questionmark.circle"
                      : "arrow.right.circle")
                    .foregroundStyle(line.isConditional ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                Text(line.headline)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !line.caveats.isEmpty {
                // Genau die Ausweisung, die den Unterschied zwischen einer
                // Messung und einer Vermutung sichtbar macht.
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nicht geprüft — die Regel prüft es, aber es steht erst am offenen Fenster fest:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(line.caveats, id: \.self) { caveat in
                        Text("• \(caveat)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 22)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Auswertung

    /// Sucht nach einem laufenden Fenster für die Regel und lässt Core
    /// entscheiden, welche der beiden Fassungen der Nutzer sieht.
    ///
    /// `WindowInventory` liest live aus der Accessibility-API. Das ist die
    /// einzige AX-Lesemessung im Editor und passiert nur, während eine Regel
    /// mit gesetzter Bundle-Kennung ausgewählt ist — nicht im Leerlauf.
    private var computedResult: DryRunPreview.Result {
        guard let bundleIdentifier = rule.match.bundleIdentifier, !bundleIdentifier.isEmpty else {
            // Ohne Bundle-Kennung ist die Regel ein Auffangfall. Für den Fall
            // würde die Zeile ohne Fenster nicht mehr sagen als „irgendein
            // Fenster ginge nach …". Das wäre die stumme Vermutung, gegen die
            // dieses Feature gebaut ist — lieber gar keine Zeile.
            return .noMatch
        }

        if let snapshot = firstMatchingSnapshot(for: bundleIdentifier) {
            return DryRunPreview.evaluate(
                window: snapshot,
                configuration: configuration,
                snapshots: snapshots
            )
        }
        return DryRunPreview.evaluate(
            bundleIdentifier: bundleIdentifier,
            configuration: configuration,
            snapshots: snapshots
        )
    }

    private var subject: String {
        rule.match.bundleIdentifier ?? "Ein Fenster"
    }

    /// Das erste laufende Fenster mit der passenden Bundle-Kennung.
    ///
    /// `allWindows` benötigt den MainActor, aber `body` ist bereits eine
    /// SwiftUI-View, die dort läuft. Der Aufruf ist trotzdem so eng wie
    /// möglich gehalten: eine einzelne Bundle-gefilterte Abfrage.
    @MainActor
    private func firstMatchingSnapshot(for bundleIdentifier: String) -> WindowSnapshot? {
        WindowInventory
            .allWindows(bundleIdentifier: bundleIdentifier)
            .first?.snapshot
    }
}
