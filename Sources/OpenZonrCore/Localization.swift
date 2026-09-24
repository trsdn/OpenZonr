import Foundation

/// User-facing text produced by this target, looked up in its own String
/// Catalog.
///
/// `NSLocalizedString`'s `bundle:` parameter defaults to `Bundle.main` — the
/// running app's own bundle. This target's compiled catalog
/// (`Resources/Localizable.xcstrings`, compiled by SwiftPM into
/// `<locale>.lproj/Localizable.strings`) lives one level deeper, inside its
/// own resource bundle (`OpenZonr_OpenZonrCore.bundle`): a SwiftPM resource
/// bundle is scoped to the target that declares it, not shared package-wide,
/// so `Bundle.main` never sees it and the lookup would silently return the
/// English `value` in every locale — not an error, just wrong. Every
/// user-facing string this target produces must go through here, verified by
/// a real build and a real lookup against the compiled `de.lproj` table
/// (`LocalizationTests`), not by assuming the plumbing is right.
///
/// Two entry points, not one, for a reason: `NSLocalizedString` with `%@`
/// placeholders and `String(format:)` is the established, unambiguous way to
/// localize an interpolated sentence, deliberately not the newer
/// `String(localized:defaultValue:)` machinery. That machinery derives its
/// catalog key from the Swift interpolation itself, which this project does
/// not want — see `key` below — and a hand-authored catalog entry for it
/// would have to reproduce the compiler's own key-generation format exactly.
/// Getting that wrong fails exactly as silently as a wrong bundle does; a
/// literal `%@` I write and can read back carries no such risk.
public enum L {

    /// A message with no interpolation.
    ///
    /// - Parameters:
    ///   - key: A stable identifier, independent of the English wording so
    ///     rewording the English text later does not silently orphan the
    ///     German translation — the catalog entry is found by `key`, never by
    ///     matching `value`.
    ///   - value: The English text. Shown as-is whenever nothing better is
    ///     available: no catalog, no matching key, or the English locale
    ///     itself, which the catalog carries no separate entry for.
    public static func string(_ key: String, _ value: String, comment: StaticString = "") -> String {
        NSLocalizedString(key, bundle: .module, value: value, comment: String(describing: comment))
    }

    /// A message with one or more interpolated values.
    ///
    /// `value` carries `%@` / `%lld` / `%1$@` placeholders. Numbered
    /// placeholders (`%1$@`, `%2$lld`, …) let a translation reorder the
    /// arguments — German word order does not always match English — without
    /// touching the call site.
    public static func string(
        _ key: String,
        _ value: String,
        comment: StaticString = "",
        _ arguments: CVarArg...
    ) -> String {
        String(format: string(key, value, comment: comment), arguments: arguments)
    }
}
