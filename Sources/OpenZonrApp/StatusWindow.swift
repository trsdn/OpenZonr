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

    /// Kept as state so the picker reflects the click immediately, even though
    /// the change only takes effect on the next launch.
    @State private var presence = PresenceSettings().presence

    /// Where the app shows itself.
    ///
    /// This section lives in the status window and not only in the menu,
    /// because in ``AppPresence/background`` there is no menu. Re-launching the
    /// app opens this window (see `applicationShouldHandleReopen`), which makes
    /// this the one place the setting can always be undone.
    private var presenceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localized("statusWindow.presence.title", "Presence"))
                .font(.headline)

            Picker(localized("statusWindow.presence.title", "Presence"), selection: $presence) {
                ForEach(AppPresence.allCases, id: \.self) { value in
                    Text(value.title).tag(value)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .onChange(of: presence) { _, value in
                PresenceSettings().presence = value
            }

            Text(
                localized(
                    "statusWindow.presence.explanation",
                    "Takes effect after the app restarts. The Accessibility permission is bound to "
                        + "the bundle and its path; switching it at runtime is unmeasured, and a lost "
                        + "grant could not be restored from here."
                )
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            if presence == .background {
                Text(
                    localized(
                        "statusWindow.presence.backgroundWarning",
                        "With no icon and no Dock presence, no click leads back here anymore. "
                            + "Opening the app again brings this window back — that is the way back."
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

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
                Divider()
                presenceSection
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
                    Text(
                        localized(
                            "statusWindow.observedApplications", "%lld observed apps", model.observedApplications
                        )
                    )
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
            Label(localized("statusWindow.accessibility.title", "Accessibility"), systemImage: "lock.shield")
                .font(.headline)

            switch model.windowAccess {
            case .granted:
                Text(
                    localized(
                        "statusWindow.accessibility.granted",
                        "Access works: at least one app delivers a real window with a readable "
                            + "position. That is the check that counts — AXIsProcessTrusted() alone "
                            + "does not predict it."
                    )
                )
                .foregroundStyle(.secondary)

            case .notTrusted:
                Text(
                    localized(
                        "statusWindow.accessibility.notTrusted",
                        "OpenZonr is not on the list of programs allowed to use Accessibility. "
                            + "Without that entry, no tool can read or move a window."
                    )
                )
                steps([
                    localized(
                        "statusWindow.accessibility.notTrusted.step1",
                        "Click “Request Permission” — macOS then shows the system dialog once."
                    ),
                    localized(
                        "statusWindow.accessibility.notTrusted.step2",
                        "If no dialog appears: open System Settings → Privacy & Security → "
                            + "Accessibility."
                    ),
                    localized(
                        "statusWindow.accessibility.notTrusted.step3",
                        "Click “+” there and add exactly this bundle — the path is below under "
                            + "“Code Signature”. “Show in Finder” has it ready to drag in."
                    ),
                    localized(
                        "statusWindow.accessibility.notTrusted.step4",
                        "Turn the switch on. OpenZonr then checks again on its own."
                    )
                ])

            case .degraded:
                Text(
                    localized(
                        "statusWindow.accessibility.degraded",
                        "This is the insidious case: macOS reports trust but delivers no real "
                            + "windows. Every app answers AXWindows with only a stand-in of role "
                            + "AXApplication. Relying on AXIsProcessTrusted() silently does nothing "
                            + "in this situation."
                    )
                )
                .foregroundStyle(.secondary)
                steps([
                    localized(
                        "statusWindow.accessibility.degraded.step1",
                        "Open System Settings → Privacy & Security → Accessibility."
                    ),
                    localized(
                        "statusWindow.accessibility.degraded.step2",
                        "Remove the existing entry for OpenZonr — merely re-checking the box is "
                            + "not enough."
                    ),
                    localized(
                        "statusWindow.accessibility.degraded.step3",
                        "Add the same bundle again and enable it — the path is below under "
                            + "“Code Signature”; a second copy elsewhere does not help."
                    ),
                    localized(
                        "statusWindow.accessibility.degraded.step4",
                        "If the state reappears afterwards, the signature is almost always the "
                            + "cause — see below."
                    )
                ])

            case .inconclusive:
                Text(
                    localized(
                        "statusWindow.accessibility.inconclusive",
                        "No ordinary app was reachable to check access against. Open any program "
                            + "with a window and check again."
                    )
                )
                .foregroundStyle(.secondary)
            }

            HStack {
                Button(localized("statusWindow.requestPermissionButton", "Request Permission")) {
                    model.requestPermission()
                }
                Button(localized("statusWindow.openSystemSettingsButton", "Open System Settings")) {
                    model.openAccessibilitySettings()
                }
                Button(localized("statusWindow.revealInFinderButton", "Show in Finder")) {
                    model.revealInFinder()
                }
                Button(localized("statusWindow.recheckButton", "Check Again")) {
                    model.refreshPermission(probe: true)
                }
            }
        }
    }

    // MARK: - Signature

    private var signatureSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(localized("statusWindow.signature.title", "Code Signature"), systemImage: "signature")
                .font(.headline)
            Text(model.signing.summary)
                .font(.system(.body, design: .monospaced))
            if let warning = model.signing.warning {
                Text(warning)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            } else {
                Text(
                    localized(
                        "statusWindow.signature.explanation",
                        "The signature binds to the bundle identifier and team rather than to the "
                            + "checksum. The grant therefore applies to this bundle at this path and "
                            + "usually survives a rebuild there — but not a move. If it does become "
                            + "invalid after a rebuild, the only fix is: remove the entry and add it "
                            + "again."
                    )
                )
                .foregroundStyle(.secondary)
            }

            if let bundle = model.bundlePath {
                Text(bundle)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
            }
        }
    }

    // MARK: - Configuration

    private var configurationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(localized("statusWindow.configuration.title", "Configuration"), systemImage: "doc.text")
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
                Text(
                    localized(
                        "statusWindow.activeProfile", "Active profile: %@ (%@)", profile.name, profile.id.rawValue
                    )
                )
                .foregroundStyle(.secondary)
            }

            if let problem = model.loginItemProblem {
                Text(problem)
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }

            HStack {
                Button(localized("statusWindow.reloadButton", "Reload")) { model.reloadConfiguration() }
                Button(localized("statusWindow.revealInFinderButton", "Show in Finder")) {
                    model.revealConfiguration()
                }
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
