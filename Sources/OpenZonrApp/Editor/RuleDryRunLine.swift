import OpenZonrCore
import OpenZonrMac
import SwiftUI

/// The dry-run line from Issue #19, as its own view.
///
/// Shows, for whichever rule is selected, a preview of what would happen if
/// the rule fired *right now* for its app. If the app happens to be running,
/// its window is sent through the same engine that later performs the
/// placement — the line is then a measurement. If the app is not running,
/// the line is conditional and names every criterion the rule checks that
/// cannot be decided without a window.
///
/// Why its own view: building the line is the one place the editor queries
/// `WindowInventory`. Encapsulation is enough to keep the rest of the form
/// file as it is — the real value lives in Core (``DryRunPreview`` +
/// ``DryRunPreviewFormatter``), this view just binds to it.
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
                // Exactly the disclosure that makes the difference between a
                // measurement and a guess visible.
                VStack(alignment: .leading, spacing: 2) {
                    Text(
                        localized(
                            "ruleDryRunLine.uncheckedHeader",
                            "Not checked — the rule checks this, but it is only decided once the window is open:"
                        )
                    )
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

    // MARK: - Evaluation

    /// Looks for a running window for the rule and lets Core decide which
    /// of the two variants the user sees.
    ///
    /// `WindowInventory` reads live from the Accessibility API. That is the
    /// only AX read measurement in the editor, and it only happens while a
    /// rule with a bundle identifier set is selected — not while idle.
    private var computedResult: DryRunPreview.Result {
        guard let bundleIdentifier = rule.match.bundleIdentifier, !bundleIdentifier.isEmpty else {
            // Without a bundle identifier, the rule is a catch-all. For that
            // case, the line without a window would say no more than "some
            // window would go to …" — the silent guess this feature is built
            // against. Better no line at all.
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
        rule.match.bundleIdentifier ?? localized("ruleDryRunLine.genericSubject", "A window")
    }

    /// The first running window with a matching bundle identifier.
    ///
    /// `allWindows` needs the main actor, but `body` is already a SwiftUI
    /// view, which runs there. The call is still kept as narrow as
    /// possible: a single bundle-filtered query.
    @MainActor
    private func firstMatchingSnapshot(for bundleIdentifier: String) -> WindowSnapshot? {
        WindowInventory
            .allWindows(bundleIdentifier: bundleIdentifier)
            .first?.snapshot
    }
}
