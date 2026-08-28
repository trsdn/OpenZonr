import AppKit
import OpenZonrCore
import OpenZonrMac
import SwiftUI

/// The status and permission window.
///
/// The Accessibility permission is the one hurdle every user of this tool hits,
/// and it fails in two different ways that look identical from the outside:
/// never granted, and granted to a binary macOS no longer recognises. The
/// window therefore does not say "permission denied". It states which of the
/// two it is, what the code signature looks like, and what to do next — with
/// the buttons that actually shorten the path.
struct StatusWindow: View {

    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()
                permissionSection
                Divider()
                signatureSection
                Divider()
                configurationSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 560, minHeight: 480)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: model.status.symbolName)
                .font(.system(size: 28))
                .foregroundStyle(tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(model.status.headline).font(.title2).bold()
                Text(model.statusDetail).foregroundStyle(.secondary)
                if model.status == .active || model.status == .paused {
                    Text("\(model.observedApplications) beobachtete Apps")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }

    private var tint: Color {
        switch model.status {
        case .active: return .green
        case .paused: return .secondary
        case .needsPermission: return .orange
        case .needsConfiguration, .noProfile: return .yellow
        }
    }

    // MARK: - Permission

    @ViewBuilder
    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Bedienungshilfen", systemImage: "lock.shield")
                .font(.headline)

            switch model.windowAccess {
            case .granted:
                Text("""
                Der Zugriff funktioniert: mindestens eine App liefert ein echtes \
                Fenster mit lesbarer Position. Das ist die Prüfung, die zählt — \
                AXIsProcessTrusted() allein sagt sie nicht voraus.
                """)
                .foregroundStyle(.secondary)

            case .notTrusted:
                Text("""
                OpenZonr steht nicht in der Liste der Programme, die die \
                Bedienungshilfen verwenden dürfen. Ohne diesen Eintrag kann kein \
                Werkzeug ein Fenster lesen oder bewegen.
                """)
                steps([
                    "Auf „Berechtigung anfragen“ klicken — macOS zeigt dann einmalig den Systemdialog.",
                    "Falls kein Dialog erscheint: Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen öffnen.",
                    "Dort auf „+“ klicken und OpenZonr.app hinzufügen. „Im Finder zeigen“ legt die App bereit, damit sie sich hineinziehen lässt.",
                    "Schalter aktivieren. Danach prüft OpenZonr von selbst wieder nach."
                ])

            case .degraded:
                Text("""
                Das ist der heimtückische Fall: macOS meldet Vertrauen, liefert aber \
                keine echten Fenster. Jede App antwortet auf AXWindows nur mit einem \
                Stellvertreter der Rolle AXApplication. Wer sich auf \
                AXIsProcessTrusted() verlässt, tut in dieser Lage stumm gar nichts.
                """)
                .foregroundStyle(.secondary)
                steps([
                    "Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen öffnen.",
                    "Den vorhandenen Eintrag für OpenZonr entfernen — den Haken nur neu zu setzen genügt nicht.",
                    "OpenZonr.app neu hinzufügen und aktivieren.",
                    "Erscheint der Zustand danach erneut, ist fast immer die Signatur die Ursache — siehe unten."
                ])

            case .inconclusive:
                Text("""
                Es war keine gewöhnliche App erreichbar, an der sich der Zugriff prüfen \
                ließe. Öffne irgendein Programm mit einem Fenster und prüfe erneut.
                """)
                .foregroundStyle(.secondary)
            }

            HStack {
                Button("Berechtigung anfragen") { model.requestPermission() }
                Button("Systemeinstellungen öffnen") { model.openAccessibilitySettings() }
                Button("Im Finder zeigen") { model.revealInFinder() }
                Button("Erneut prüfen") { model.refreshPermission(probe: true) }
            }
        }
    }

    // MARK: - Signature

    private var signatureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Code-Signatur", systemImage: "signature")
                .font(.headline)
            Text(model.signing.summary)
                .font(.system(.body, design: .monospaced))
            if let warning = model.signing.warning {
                Text(warning)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            } else {
                Text("""
                Die Freigabe bindet damit an Bundle-Identifier und Team statt an die \
                Prüfsumme und übersteht jeden Neubau.
                """)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Configuration

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Konfiguration", systemImage: "doc.text")
                .font(.headline)
            Text(model.configurationURL.path)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)

            if let problem = model.configurationProblem {
                Text(problem)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            } else if let explanation = model.missingProfileExplanation {
                Text(explanation)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            } else if let profile = model.activeProfile {
                Text("Aktives Profil: \(profile.name) (\(profile.id.rawValue))")
                    .foregroundStyle(.secondary)
            }

            if let problem = model.loginItemProblem {
                Text(problem)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }

            HStack {
                Button("Neu laden") { model.reloadConfiguration() }
                Button("Im Finder zeigen") { model.revealConfiguration() }
            }
        }
    }

    private func steps(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, text in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(index + 1).")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(text)
                }
            }
        }
        .padding(.leading, 4)
    }
}
