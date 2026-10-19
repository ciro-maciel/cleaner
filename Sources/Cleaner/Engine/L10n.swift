import Foundation

/// The interface language. Cleaner follows the Mac: Brazilian Portuguese when the first of the
/// person's preferred languages is Portuguese, English for anything else. There is no switch
/// inside the app.
///
/// The key of every string is its English text, so the code reads in English. The tables are
/// `Resources/en.lproj/Localizable.strings` and `Resources/pt-BR.lproj/Localizable.strings`.
/// A key missing from the chosen table falls back to the English table, then to the key itself;
/// a key that needs a context to tell two Portuguese words apart carries it in brackets at the
/// end ("On [menu bar]"), and the bracket never reaches the screen.
enum L10n {
    static let isPortuguese = (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("pt")
    static let language = isPortuguese ? "pt-BR" : "en"

    /// Numbers and dates: pt_BR in Portuguese; in English, English with the Mac's region.
    static let locale: Locale = isPortuguese
        ? Locale(identifier: "pt_BR")
        : Locale(identifier: "en_" + (Locale.current.region?.identifier ?? "US"))

    private static let table = bundle(language)
    private static let english = bundle("en")
    private static let missing = "\u{1}missing\u{1}"

    private static func bundle(_ name: String) -> Bundle? {
        Bundle.main.path(forResource: name, ofType: "lproj").flatMap(Bundle.init(path:))
    }

    static func string(_ key: String) -> String {
        if let v = table?.localizedString(forKey: key, value: missing, table: nil), v != missing { return v }
        if let v = english?.localizedString(forKey: key, value: missing, table: nil), v != missing { return v }
        return plain(key)
    }

    /// The key without its "[context]" tail.
    static func plain(_ key: String) -> String {
        guard key.hasSuffix("]"), let open = key.range(of: " [", options: .backwards) else { return key }
        return String(key[..<open.lowerBound])
    }
}

/// The interface text for an English key, in the Mac's language.
func L(_ key: String) -> String { L10n.string(key) }

/// The same, with %@ placeholders filled in (positional %1$@ when the languages order them apart).
func L(_ key: String, _ args: CVarArg...) -> String {
    String(format: L10n.string(key), locale: L10n.locale, arguments: args)
}
