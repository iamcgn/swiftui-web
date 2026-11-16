// Foundation's locale-taking case changes on wasm, where FoundationEssentials has only the
// standard library's: `lowercased(with:)`, `uppercased(with:)`, `capitalized(with:)` and
// `capitalized`, on strings and on NSString. They map case as the root locale does, with
// Turkish and Azerbaijani's dotted and dotless i ("I" lowercases to "ı", "i" uppercases to "İ"),
// the one tailoring apps meet in practice; other languages' special rules (Lithuanian's
// retained dot) are not kept. Words for `capitalized` are as `localizedCapitalized` finds them.
#if os(WASI)
import FoundationEssentials

/// The case mapping a locale asks for.
enum _CaseMapping {
    /// Whether `locale` maps i with Turkish rules.
    static func dottedI(_ locale: Locale?) -> Bool {
        guard let identifier = locale?.identifier else { return false }
        let language = identifier.split(whereSeparator: { $0 == "_" || $0 == "-" || $0 == "@" }).first.map(String.init) ?? identifier
        return language == "tr" || language == "az"
    }

    static func lowercased(_ string: String, dottedI: Bool) -> String {
        guard dottedI else { return string.lowercased() }
        var result = ""
        for character in string {
            switch character {
            case "I": result += "ı"
            case "İ": result += "i"
            default: result += character.lowercased()
            }
        }
        return result
    }

    static func uppercased(_ string: String, dottedI: Bool) -> String {
        guard dottedI else { return string.uppercased() }
        var result = ""
        for character in string {
            result += character == "i" ? "İ" : character.uppercased()
        }
        return result
    }

    /// Each word's first letter in uppercase and the rest in lowercase.
    static func capitalized(_ string: String, dottedI: Bool) -> String {
        var result = ""
        var startsWord = true
        for character in string {
            let piece = String(character)
            result += startsWord ? uppercased(piece, dottedI: dottedI) : lowercased(piece, dottedI: dottedI)
            startsWord = !(character.isLetter || character.isNumber || character == "'" || character == "’")
        }
        return result
    }
}

extension StringProtocol {
    /// Each word's first letter in uppercase and the rest in lowercase, in the root locale.
    public var capitalized: String { _CaseMapping.capitalized(String(self), dottedI: false) }

    /// The string in lowercase as `locale` maps case (the root locale's when nil).
    public func lowercased(with locale: Locale?) -> String {
        _CaseMapping.lowercased(String(self), dottedI: _CaseMapping.dottedI(locale))
    }

    /// The string in uppercase as `locale` maps case (the root locale's when nil).
    public func uppercased(with locale: Locale?) -> String {
        _CaseMapping.uppercased(String(self), dottedI: _CaseMapping.dottedI(locale))
    }

    /// Each word capitalized as `locale` maps case (the root locale's when nil).
    public func capitalized(with locale: Locale?) -> String {
        _CaseMapping.capitalized(String(self), dottedI: _CaseMapping.dottedI(locale))
    }
}

extension _WebNSString {
    public func lowercased(with locale: Locale?) -> String { string.lowercased(with: locale) }
    public func uppercased(with locale: Locale?) -> String { string.uppercased(with: locale) }
    public func capitalized(with locale: Locale?) -> String { string.capitalized(with: locale) }
}
#endif
