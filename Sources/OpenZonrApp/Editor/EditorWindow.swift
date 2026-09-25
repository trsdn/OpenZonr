import OpenZonrCore
import SwiftUI

/// The editor window.
///
/// Three tabs, one save bar. The save bar is the only place that writes, and it
/// says what it is about to write to — a configuration editor that hides the
/// path of the file it edits invites the user to wonder whether it edited the
/// right one.
struct EditorWindow: View {

    @Bindable var document: ConfigurationDocument
    @State private var tab: Tab = .overview

    enum Tab: Hashable {
        case overview, rules, roles, zones
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $tab) {
                OverviewEditor(document: document)
                    .tabItem {
                        Label {
                            Text(localized("editorWindow.tab.overview", "Overview"))
                        } icon: {
                            Image(systemName: "square.grid.3x3.topleft.filled")
                        }
                    }
                    .tag(Tab.overview)

                RuleEditor(document: document)
                    .tabItem {
                        Label {
                            Text(localized("editorWindow.tab.rules", "Rules"))
                        } icon: {
                            Image(systemName: "list.number")
                        }
                    }
                    .tag(Tab.rules)

                RoleEditor(document: document)
                    .tabItem {
                        Label {
                            Text(localized("editorWindow.tab.roles", "Roles & Profiles"))
                        } icon: {
                            Image(systemName: "square.grid.2x2")
                        }
                    }
                    .tag(Tab.roles)

                ZoneEditor(document: document)
                    .tabItem {
                        Label {
                            Text(localized("editorWindow.tab.zones", "Zones"))
                        } icon: {
                            Image(systemName: "rectangle.split.2x2")
                        }
                    }
                    .tag(Tab.zones)
            }
            .padding(.top, 8)

            Divider()
            unassigned
            saveBar
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    /// Findings that no field claims — duplicate identifiers, mostly.
    ///
    /// Deliberately not the general error list the issue argues against: it only
    /// ever holds what field-level display structurally cannot show, and it
    /// disappears when there is nothing.
    @ViewBuilder
    private var unassigned: some View {
        let findings = document.unassignedFindings
        if !findings.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(findings, id: \.self) { finding in
                    Label {
                        Text("\(finding.message)  ")
                            + Text(finding.path.description)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                    } icon: {
                        Image(systemName: finding.severity.symbolName)
                            .foregroundStyle(finding.severity.tint)
                    }
                    .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.4))
            Divider()
        }
    }

    private var saveBar: some View {
        HStack(spacing: 10) {
            status
            Spacer()
            Button {
                document.revert()
            } label: {
                Text(localized("editorWindow.discardButton", "Discard"))
            }
            .disabled(!document.hasUnsavedChanges)
            Button {
                document.save()
            } label: {
                Text(localized("editorWindow.saveButton", "Save"))
            }
            .keyboardShortcut("s")
            .disabled(!document.hasUnsavedChanges || !document.isUsable)
            .help(
                Text(
                    document.isUsable
                        ? localized(
                            "editorWindow.saveButton.help.usable",
                            "Writes the configuration atomically through ConfigurationStore"
                        )
                        : localized(
                            "editorWindow.saveButton.help.unusable",
                            "There are errors the configuration cannot work with"
                        )
                )
            )
            if document.hasExternalChange {
                Button {
                    document.save(overwritingExternalChanges: true)
                } label: {
                    Text(localized("editorWindow.saveAnywayButton", "Save Anyway"))
                }
                .disabled(!document.isUsable)
                .help(
                    Text(
                        localized(
                            "editorWindow.saveAnywayButton.help",
                            "Overwrites the externally changed file with this editor's state"
                        )
                    )
                )
            }
        }
        .padding(10)
    }

    @ViewBuilder
    private var status: some View {
        switch document.saveState {
        case .unchanged:
            Text(document.fileURL.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
        case .modified:
            Label {
                Text(localized("editorWindow.status.unsavedChanges", "Unsaved Changes"))
            } icon: {
                Image(systemName: "pencil")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case let .saved(date):
            Label {
                Text(
                    localized(
                        "editorWindow.status.savedAt",
                        "Saved at %@",
                        date.formatted(date: .omitted, time: .standard)
                    )
                )
            } icon: {
                Image(systemName: "checkmark.circle")
            }
            .font(.caption)
            .foregroundStyle(.green)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.octagon.fill")
                .font(.caption)
                .foregroundStyle(.red)
        }
    }
}
