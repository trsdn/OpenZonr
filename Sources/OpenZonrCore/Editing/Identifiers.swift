import Foundation

/// Derives readable, collision-free identifiers from text a user typed.
///
/// The configuration is meant to stay hand-editable, so an identifier generated
/// by the editor has to look like one a person would have written:
/// `outlook-mitte`, not a UUID. Two properties matter and are both tested —
/// the result is stable for the same input, and it never collides with an
/// identifier already in the document.
public enum IdentifierFactory {

    /// Turns arbitrary text into a lowercase, hyphenated ASCII slug.
    ///
    /// German umlauts are transliterated rather than stripped: a rule named
    /// "Büro" must not become `bro`. Everything that is neither an ASCII letter
    /// nor a digit collapses into a single hyphen.
    public static func slug(_ text: String) -> String {
        var folded = ""
        for character in text.lowercased() {
            switch character {
            case "ä": folded += "ae"
            case "ö": folded += "oe"
            case "ü": folded += "ue"
            case "ß": folded += "ss"
            default: folded.append(character)
            }
        }

        let transliterated = folded.applyingTransform(.stripDiacritics, reverse: false) ?? folded

        var slug = ""
        var pendingSeparator = false
        for scalar in transliterated.unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                if pendingSeparator, !slug.isEmpty { slug.append("-") }
                pendingSeparator = false
                slug.unicodeScalars.append(scalar)
            } else {
                pendingSeparator = true
            }
        }
        return slug
    }

    /// Returns `base` as a slug, suffixed with a number when that slug is taken.
    ///
    /// The suffix starts at `2` because `zone`, `zone-2`, `zone-3` is how people
    /// number things; a `zone-1` next to a plain `zone` reads like a mistake.
    public static func uniqueSlug(_ base: String, taken: Set<String>, fallback: String = "eintrag") -> String {
        let slugged = slug(base)
        let root = slugged.isEmpty ? fallback : slugged
        guard taken.contains(root) else { return root }

        var counter = 2
        while taken.contains("\(root)-\(counter)") {
            counter += 1
        }
        return "\(root)-\(counter)"
    }

    /// Typed convenience over ``uniqueSlug(_:taken:fallback:)``.
    public static func unique<ID: StringIdentifier>(
        _ base: String,
        taken: some Sequence<ID>,
        fallback: String = "eintrag"
    ) -> ID {
        ID(rawValue: uniqueSlug(base, taken: Set(taken.map(\.rawValue)), fallback: fallback))
    }
}
