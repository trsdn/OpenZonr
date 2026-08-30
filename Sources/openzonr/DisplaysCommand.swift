import Foundation
import OpenZonrCore

/// `openzonr displays` — the command that turns a physical desk into
/// configuration.
///
/// The example configuration ships with invented EDID numbers, and it has to:
/// nobody else's monitors are known at authoring time. This subcommand is the
/// supported way to replace them, which is why it can emit a ready-made
/// `displays` fragment instead of only printing a table.
struct DisplaysCommand {

    var emitFragment: Bool

    @MainActor
    func run() throws {
        let snapshots = SystemDisplays.snapshots()
        guard !snapshots.isEmpty else {
            throw CommandError("Keine aktiven Displays gefunden.")
        }

        if emitFragment {
            printFragment(snapshots)
        } else {
            printReport(snapshots)
        }
    }

    // MARK: - Human readable report

    private func printReport(_ snapshots: [DisplaySnapshot]) {
        print("Aktive Displays: \(snapshots.count)\n")

        for snapshot in snapshots {
            let markers = [
                snapshot.isPrimary ? "Hauptdisplay" : nil,
                snapshot.isLikelyVirtual ? "vermutlich Software-Display" : nil
            ].compactMap { $0 }

            let suffix = markers.isEmpty ? "" : "  [\(markers.joined(separator: ", "))]"
            print("• \(snapshot.localizedName)\(suffix)")
            print("    CGDirectDisplayID   \(snapshot.displayID) (nur diese Sitzung gültig)")
            print("    Identität           \(describe(snapshot.identity))")
            print("    Auflösung           \(snapshot.pixelWidth)×\(snapshot.pixelHeight) Pixel, Scale \(format(snapshot.backingScaleFactor))")
            print("    frame               \(snapshot.frame.shortDescription)   (AppKit, Ursprung unten links)")
            print("    visibleFrame        \(snapshot.visibleFrame.shortDescription)   (ohne Menüleiste und Dock)")
            print("    physische Größe     \(format(snapshot.physicalSizeMillimeters.width))×\(format(snapshot.physicalSizeMillimeters.height)) mm")

            if snapshot.usesSerialFallback {
                print("""
                    ⚠️  Seriennummer 0 — es greift die Fallback-Identität aus
                        Vendor + Modell + Auflösung + Port-Index. Das ist stabil,
                        solange nicht zwei baugleiche Monitore die Anschlüsse tauschen.
                """)
            }
            if snapshot.isLikelyVirtual {
                print("""
                    ⚠️  Unplausible EDID-Kennung — vermutlich ein Software-Display
                        (Bildschirmfreigabe, OBS, Teleprompter). Solche Displays kommen und
                        gehen, ohne dass sich am Schreibtisch etwas ändert. Trage sie unter
                        "ignoredDisplays" ein, sonst wechselt das Profil bei jedem Start.
                        Das ist eine Vermutung, keine Feststellung — bitte prüfen.
                """)
            }
            print("")
        }

        let fingerprint = SetupFingerprint(snapshots: snapshots)
        print("Setup-Fingerprint (alle \(fingerprint.displays.count) Displays):")
        for identity in fingerprint.displays.sorted(by: { describe($0) < describe($1) }) {
            print("    \(describe(identity))")
        }

        let physical = snapshots.filter { !$0.isLikelyVirtual }
        if physical.count != snapshots.count {
            let reduced = SetupFingerprint(snapshots: physical)
            print("\nOhne die vermutlichen Software-Displays (\(reduced.displays.count)):")
            for identity in reduced.displays.sorted(by: { describe($0) < describe($1) }) {
                print("    \(describe(identity))")
            }
            print("""

            Genau dieser reduzierte Fingerprint ist der, den ein Profil treffen sollte.
            Erzeuge die passenden Einträge mit:  openzonr displays --config-fragment
            """)
        }
    }

    // MARK: - Configuration fragment

    private func printFragment(_ snapshots: [DisplaySnapshot]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let physical = snapshots.filter { !$0.isLikelyVirtual }
        let virtual = snapshots.filter(\.isLikelyVirtual)

        let descriptors = physical.map { snapshot -> DisplayDescriptor in
            let alias = DisplayAlias(rawValue: Self.alias(for: snapshot))
            return DisplayDescriptor(
                alias: alias,
                displayName: snapshot.localizedName,
                identity: snapshot.identity,
                layouts: [Self.suggestedLayout(for: snapshot)],
                defaultLayoutID: Self.suggestedLayout(for: snapshot).id
            )
        }

        print("// Von \"openzonr displays --config-fragment\" erzeugt.")
        print("// Die Layouts sind ein Vorschlag auf Basis des Seitenverhältnisses —")
        print("// Zonen gehören angepasst, Identitäten nicht.")
        emit(descriptors, as: "displays", encoder: encoder)

        if !virtual.isEmpty {
            print("")
            print("// Vermutlich virtuelle Displays. Sie stehen hier, damit sie den")
            print("// Setup-Fingerprint nicht verändern, wenn sie auftauchen.")
            emit(virtual.map(\.identity), as: "ignoredDisplays", encoder: encoder)
        }
    }

    private func emit(_ value: some Encodable, as key: String, encoder: JSONEncoder) {
        guard
            let data = try? encoder.encode(value),
            let json = String(data: data, encoding: .utf8)
        else { return }

        let indented = json
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "  " + $0 }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespaces)

        print("  \"\(key)\": \(indented),")
    }

    /// A readable, stable alias derived from the monitor name.
    static func alias(for snapshot: DisplaySnapshot) -> String {
        if case .builtin = snapshot.identity { return "builtin" }

        let slug = snapshot.localizedName
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { partial, character in
                if character == "-", partial.hasSuffix("-") { return }
                partial.append(character)
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return slug.isEmpty ? "display-\(snapshot.displayID)" : slug
    }

    /// A starting layout chosen from the aspect ratio.
    ///
    /// A 32:9 ultrawide with two half-width zones gives 2560 pt columns, which
    /// nobody wants; three columns give a usable 1706 pt each. The suggestion is
    /// a convenience, not a claim to be right.
    static func suggestedLayout(for snapshot: DisplaySnapshot) -> Layout {
        let ratio = snapshot.visibleFrame.height > 0
            ? snapshot.visibleFrame.width / snapshot.visibleFrame.height
            : 1

        if ratio >= 3.0 {
            return Layout(
                id: LayoutID(rawValue: "\(alias(for: snapshot))-three-columns"),
                name: "Drei Spalten (25 / 50 / 25)",
                zones: [
                    Zone(id: "left-quarter", name: "Links außen", frame: RelativeRect(x: 0, y: 0, width: 0.25, height: 1)),
                    Zone(id: "center-half", name: "Mitte", frame: RelativeRect(x: 0.25, y: 0, width: 0.5, height: 1)),
                    Zone(id: "right-quarter", name: "Rechts außen", frame: RelativeRect(x: 0.75, y: 0, width: 0.25, height: 1))
                ]
            )
        }

        if ratio >= 1.9 {
            return Layout(
                id: LayoutID(rawValue: "\(alias(for: snapshot))-two-columns"),
                name: "Zwei Spalten",
                zones: [
                    Zone(id: "left-half", name: "Links", frame: RelativeRect(x: 0, y: 0, width: 0.5, height: 1)),
                    Zone(id: "right-half", name: "Rechts", frame: RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1))
                ]
            )
        }

        return Layout(
            id: LayoutID(rawValue: "\(alias(for: snapshot))-full"),
            name: "Vollbild",
            zones: [
                Zone(id: "full", name: "Vollbild", frame: .full)
            ]
        )
    }
}

/// Human readable rendering of a display identity, used in every subcommand.
func describe(_ identity: DisplayIdentity) -> String {
    switch identity {
    case .builtin:
        return "builtin (integriertes Display)"
    case let .edid(vendor, model, serial):
        return "edid vendor=\(vendor) model=\(model) serial=\(serial)"
    case let .fallback(vendor, model, width, height, port):
        return "fallback vendor=\(vendor) model=\(model) \(width)×\(height) port=\(port)"
    }
}

func format(_ value: Double) -> String {
    value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
}
