import OpenZonrCore
import OpenZonrMac
import SwiftUI

/// The last placements, and the log behind them.
///
/// Until now the `watch` log in a terminal was the only feedback the tool gave.
/// The window keeps that log — it is genuinely useful and hard-won — but puts
/// the answer most people want in front of it: which windows were moved, where
/// to, and how it went.
struct ActivityWindow: View {

    @Bindable var model: AppModel
    @State private var showsLog = false

    var body: some View {
        VStack(spacing: 0) {
            records
            Divider()
            footer
            if showsLog {
                Divider()
                log
            }
        }
        .frame(minWidth: 640, minHeight: 420)
    }

    @ViewBuilder
    private var records: some View {
        if model.records.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "rectangle.dashed")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("Noch keine Platzierung")
                    .font(.headline)
                Text("""
                Hier steht jedes Fenster, für das eine Regel gegriffen hat. Starte eine \
                App, für die eine Regel existiert — Fenster, die kein Kandidat waren, \
                werden bewusst nicht aufgeführt.
                """)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 420)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.records) { record in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: symbol(for: record))
                        .foregroundStyle(colour(for: record))
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(record.applicationName).bold()
                            if let target = record.target {
                                Text(target)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(record.summary).font(.callout).foregroundStyle(.secondary)
                        if let title = record.windowTitle, !title.isEmpty {
                            Text("„\(title)“").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(record.date, style: .time)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        if let rule = record.ruleID {
                            Text(rule.rawValue).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var footer: some View {
        HStack {
            Toggle("Protokoll anzeigen", isOn: $showsLog)
                .toggleStyle(.switch)
                .controlSize(.small)
            Spacer()
            Text("\(model.records.count) Einträge")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Leeren") { model.clearRecords() }
                .disabled(model.records.isEmpty)
        }
        .padding(10)
    }

    private var log: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(model.logEntries) { entry in
                        HStack(alignment: .top, spacing: 6) {
                            Text(entry.level.marker)
                                .frame(width: 10)
                                .foregroundStyle(colour(for: entry.level))
                            Text(entry.message)
                                .textSelection(.enabled)
                                .foregroundStyle(entry.level == .detail ? .secondary : .primary)
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .id(entry.id)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 220)
            .onChange(of: model.logEntries.count) {
                if let last = model.logEntries.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func symbol(for record: PlacementRecord) -> String {
        if record.isSuccess { return "checkmark.circle.fill" }
        if record.isFailure { return "exclamationmark.triangle.fill" }
        return "minus.circle"
    }

    private func colour(for record: PlacementRecord) -> Color {
        if record.isSuccess { return .green }
        if record.isFailure { return .orange }
        return .secondary
    }

    private func colour(for level: Log.Level) -> Color {
        switch level {
        case .success: return .green
        case .warn: return .orange
        case .event: return .accentColor
        case .info, .detail: return .secondary
        }
    }
}
