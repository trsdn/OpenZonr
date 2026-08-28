import Foundation
import Security

/// What this process's own code signature looks like.
///
/// This is not decoration. The single hardest failure in this project was a
/// binary that TCC accepted in the settings list and then did not recognise
/// again after the next build, because an unsigned Mach-O gets a new hash every
/// time. The symptom is silent: `AXIsProcessTrusted()` says `true`, every
/// application answers `AXWindows` with a stub, and nothing is ever placed.
///
/// A tool that can detect that state should say so rather than let the user
/// re-tick a checkbox for an hour. See `docs/tracer-bullet.md`.
public enum CodeSigningStatus: Sendable, Hashable {
    /// Signed with a Developer ID certificate. The designated requirement binds
    /// to identifier and team, so the Accessibility grant survives rebuilds.
    case developerID(identifier: String, team: String?)
    /// Signed, but not with a Developer ID — typically ad-hoc. The grant is
    /// bound to the hash and is lost on the next build.
    case otherSignature(identifier: String?)
    /// No usable signature at all.
    case unsigned
    /// The signature could not be inspected.
    case unknown

    /// `true` when the signature is the kind that survives a rebuild.
    public var survivesRebuild: Bool {
        if case .developerID = self { return true }
        return false
    }

    /// One sentence for the status window.
    public var summary: String {
        switch self {
        case let .developerID(identifier, team):
            let teamText = team.map { ", Team \($0)" } ?? ""
            return "Developer ID — \(identifier)\(teamText)"
        case let .otherSignature(identifier):
            return "signiert, aber ohne Developer ID\(identifier.map { " — \($0)" } ?? "")"
        case .unsigned:
            return "nicht signiert"
        case .unknown:
            return "Signatur nicht lesbar"
        }
    }

    /// Why this matters, when it does. `nil` when everything is in order.
    public var warning: String? {
        switch self {
        case .developerID:
            return nil
        case .otherSignature, .unsigned:
            return """
            Ohne Developer-ID-Signatur bindet die Bedienungshilfen-Freigabe an die
            Prüfsumme der Binärdatei. Die ändert sich bei jedem Neubau, und macOS
            erkennt das Programm nicht wieder: der Haken bleibt gesetzt, meint aber
            ein anderes Programm. Sichtbare Folge ist kein Fehler, sondern Stille —
            jede App liefert auf AXWindows nur Platzhalter.

            Abhilfe: Scripts/bundle.sh baut, packt und signiert das Bundle.
            """
        case .unknown:
            return """
            Die eigene Signatur ließ sich nicht lesen. Falls Fenster nicht platziert
            werden, ist ein signiertes Bundle (Scripts/bundle.sh) der erste
            Verdacht — siehe docs/tracer-bullet.md.
            """
        }
    }

    /// Inspects the running process.
    public static func current() -> CodeSigningStatus {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return .unknown }

        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            unsafeBitCast(code, to: SecStaticCode.self),
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &information
        ) == errSecSuccess,
            let details = information as? [String: Any]
        else { return .unknown }

        let identifier = details[kSecCodeInfoIdentifier as String] as? String
        let team = details[kSecCodeInfoTeamIdentifier as String] as? String

        guard identifier != nil else { return .unsigned }

        // The leaf OID 1.2.840.113635.100.6.1.13 is what makes a certificate a
        // Developer ID Application certificate. Asking the system to check the
        // requirement is more reliable than picking the chain apart by hand.
        var requirement: SecRequirement?
        let text = "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let requirement
        else { return .otherSignature(identifier: identifier) }

        if SecCodeCheckValidity(code, [], requirement) == errSecSuccess {
            return .developerID(identifier: identifier ?? "?", team: team)
        }
        return .otherSignature(identifier: identifier)
    }
}
