import Foundation
import Observation
import OpenZonrCore

/// One editing session on the configuration file.
///
/// Three responsibilities, and deliberately no more:
///
/// - it holds the working copy every edit is applied to,
/// - it revalidates after **every** edit and keeps the findings addressable by
///   path, so a field can show its own error instead of a list at the edge,
/// - it writes through ``ConfigurationStore`` and nowhere else. The store is
///   atomic and migrating; a second write path would be a second chance to
///   truncate the user's file.
///
/// What it does not do is refuse edits. An invalid intermediate state is normal
/// while typing, and an editor that rejects those is an editor nobody can use —
/// the same reason ``ConfigurationStore/save(_:to:)`` does not validate either.
@Observable
@MainActor
final class ConfigurationDocument {

    /// The state the file is in, as far as this session knows.
    enum SaveState: Equatable {
        case unchanged
        case modified
        case saved(Date)
        case failed(String)
    }

    private(set) var configuration: Configuration
    private(set) var report: ValidationReport
    private(set) var findings: FindingIndex
    private(set) var saveState: SaveState = .unchanged

    /// The configuration as it was when the session started, for ``revert()``.
    private var original: Configuration

    private let url: URL
    private let store: ConfigurationStore

    /// Called after a successful write, so the app can reload the engine with
    /// the configuration that is now on disk.
    var onSave: ((Configuration) -> Void)?

    init(configuration: Configuration, url: URL, store: ConfigurationStore = ConfigurationStore()) {
        let report = store.validate(configuration)
        self.configuration = configuration
        self.original = configuration
        self.url = url
        self.store = store
        self.report = report
        self.findings = FindingIndex(report)
    }

    var fileURL: URL { url }

    var hasUnsavedChanges: Bool {
        if case .modified = saveState { return true }
        if case .failed = saveState { return true }
        return false
    }

    /// `true` when the working copy could be written and still work.
    var isUsable: Bool { report.isUsable }

    // MARK: - Editing

    /// Applies one edit and revalidates.
    ///
    /// Every change goes through here — the rule list, the zone editor, the
    /// quick pin — so that "validated after every change" is a property of the
    /// document rather than something each view has to remember.
    func apply(_ edit: (Configuration) -> Configuration) {
        update(edit(configuration))
    }

    /// Replaces the working copy wholesale, for edits computed elsewhere such
    /// as ``QuickPin``.
    func replace(with configuration: Configuration) {
        update(configuration)
    }

    private func update(_ configuration: Configuration) {
        guard configuration != self.configuration else { return }
        self.configuration = configuration
        report = store.validate(configuration)
        findings = FindingIndex(report)
        saveState = configuration == original ? .unchanged : .modified
    }

    /// Throws away every change of this session.
    func revert() {
        configuration = original
        report = store.validate(configuration)
        findings = FindingIndex(report)
        saveState = .unchanged
    }

    // MARK: - Saving

    /// Writes the working copy through ``ConfigurationStore``.
    ///
    /// Errors are kept rather than thrown: the save button lives in a window
    /// whose only sensible reaction is to show what went wrong, right there.
    @discardableResult
    func save() -> Bool {
        do {
            try store.save(configuration, to: url)
            original = configuration
            saveState = .saved(Date())
            onSave?(configuration)
            return true
        } catch let error as ConfigurationStoreError {
            saveState = .failed(error.description)
            return false
        } catch {
            saveState = .failed("Speichern fehlgeschlagen: \(error)")
            return false
        }
    }

    // MARK: - Findings

    /// Findings that no field in the editor claims.
    ///
    /// Kept visible on purpose. The uniqueness checks report by position
    /// (`rules[2].id`) because with two identical identifiers the identifier is
    /// exactly what cannot address them — and a duplicate identifier is a
    /// problem the editor's own field-level display would otherwise hide.
    var unassignedFindings: [ValidationFinding] {
        var covered: [ConfigurationPath] = [ConfigurationPath().field("defaults")]
        covered += configuration.rules.map { ConfigurationPath.rule($0.id) }
        covered += configuration.roles.map { ConfigurationPath.role($0.id) }
        covered += configuration.profiles.map { ConfigurationPath.profile($0.id) }
        covered += configuration.displays.map { ConfigurationPath.display($0.alias) }
        return findings.findings(notUnder: covered)
    }
}
