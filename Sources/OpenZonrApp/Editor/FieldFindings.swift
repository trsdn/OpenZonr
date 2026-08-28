import OpenZonrCore
import SwiftUI

/// Shows the findings that belong to one field, underneath that field.
///
/// The issue is explicit about this: `ConfigurationValidator` reports with a
/// path and a severity, so the interface can put the sentence where the problem
/// is instead of collecting a list at the edge of the window that the user then
/// has to match back to fields by hand.
struct FieldFindings: View {

    let path: ConfigurationPath
    let index: FindingIndex

    var body: some View {
        let findings = index.findings(at: path)
        if !findings.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(findings, id: \.self) { finding in
                    Label {
                        Text(finding.message)
                    } icon: {
                        Image(systemName: finding.severity.symbolName)
                    }
                    .font(.caption)
                    .foregroundStyle(finding.severity.tint)
                }
            }
        }
    }
}

/// A badge for a whole subtree — a row in the rule list, a tab.
///
/// Without it a problem inside a collapsed rule would only be visible after
/// opening the rule, which is the same as not being visible.
struct FindingBadge: View {

    let path: ConfigurationPath
    let index: FindingIndex

    var body: some View {
        if let severity = index.severity(under: path) {
            Image(systemName: severity.symbolName)
                .foregroundStyle(severity.tint)
                .help(index.findings(under: path).map(\.message).joined(separator: "\n"))
        }
    }
}

extension ValidationSeverity {

    var symbolName: String {
        switch self {
        case .error: return "exclamationmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .error: return .red
        case .warning: return .orange
        }
    }

    var label: String {
        switch self {
        case .error: return "Fehler"
        case .warning: return "Warnung"
        }
    }
}

/// A text field that reports its own problems and stays empty rather than
/// storing an empty string.
///
/// `nil` and `""` mean different things in ``WindowMatch``: a `nil` title
/// pattern is "no title criterion", an empty one is a pattern that matches
/// everything. A form that cannot express the difference would quietly change
/// what a rule does.
struct OptionalTextField: View {

    let title: String
    let prompt: String
    let path: ConfigurationPath
    let index: FindingIndex
    @Binding var value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(
                title,
                text: Binding(
                    get: { value ?? "" },
                    set: { newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                        value = trimmed.isEmpty ? nil : newValue
                    }
                ),
                prompt: Text(prompt)
            )
            FieldFindings(path: path, index: index)
        }
    }
}
