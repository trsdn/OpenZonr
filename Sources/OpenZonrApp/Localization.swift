import SwiftUI

extension Text {
    /// A localized string looked up in this app's own String Catalog
    /// (`Resources/Localizable.xcstrings`, compiled into
    /// `OpenZonr_OpenZonrApp.bundle`).
    ///
    /// `Text.init(_:tableName:bundle:comment:)`'s `bundle` parameter defaults
    /// to `nil`, which searches `Bundle.main` — the running `.app`'s own
    /// `Contents/Resources`. This app's compiled catalog lives one level
    /// deeper, inside its own SwiftPM resource bundle, because a SwiftPM
    /// resource bundle is scoped to the target that declares it: `Bundle.main`
    /// never sees it, and the default falls back to the English key in every
    /// locale — silently, no crash, no warning. Every localized `Text` in this
    /// app goes through this initializer instead, or it goes unlocalized —
    /// verified by a real build and lookup against the compiled `de.lproj`
    /// table (`LocalizationTests`), not assumed.
    ///
    /// `Button` and `Label`'s own literal-string convenience initializers
    /// (`Button("...") { }`, `Label("...", systemImage:)`) carry no `bundle`
    /// parameter at all — confirmed by reading SwiftUICore's own interface,
    /// not guessed — so neither can be localized directly. Both route through
    /// this initializer instead, in their closure-based form:
    ///
    ///     Button { action() } label: { Text(localized: "Save") }
    ///     Label { Text(localized: "Zones") } icon: { Image(systemName: "folder") }
    ///
    /// `.help(_:)` does have a `Text`-based overload, so
    /// `.help(Text(localized: "…"))` works directly.
    init(localized key: LocalizedStringKey, comment: StaticString? = nil) {
        self.init(key, bundle: .module, comment: comment)
    }
}

/// A plain-`String` counterpart to `Text(localized:)`, for the places that are
/// not SwiftUI: AppKit's `NSAlert.messageText`, `NSMenuItem(title:)`,
/// `NSButton(title:)`, and any Swift value (`AppModel`'s guard sentences,
/// status text) that ends up displayed rather than passed straight into a
/// `Text`.
///
/// Free functions rather than a same-named type, on purpose:
/// `OpenZonrCore` — which this target imports — declares its **own**
/// `L.string(...)`, scoped to `OpenZonrCore`'s own resource bundle. A second
/// `enum L` in this module would technically resolve correctly (an
/// unqualified reference inside a module prefers that module's own
/// declaration over an imported one), but relying on that shadowing rule at
/// every call site is exactly the kind of thing that is only obviously
/// correct until someone reorganizes an import. Two different names cannot
/// be confused for each other.
///
/// A message with no interpolation.
func localized(_ key: String, _ value: String, comment: StaticString = "") -> String {
    NSLocalizedString(key, bundle: .module, value: value, comment: String(describing: comment))
}

/// A message with one or more interpolated values, using `%@` / `%lld` /
/// `%1$@`-style placeholders in `value` — see the matching function in
/// `OpenZonrCore/Localization.swift` for why, at length.
func localized(
    _ key: String,
    _ value: String,
    comment: StaticString = "",
    _ arguments: CVarArg...
) -> String {
    String(format: localized(key, value, comment: comment), arguments: arguments)
}
