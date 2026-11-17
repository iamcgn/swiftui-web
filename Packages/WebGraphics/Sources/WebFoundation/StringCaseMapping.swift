// Foundation's locale-taking case changes on wasm, where FoundationEssentials has only the
// standard library's: `lowercased(with:)`, `uppercased(with:)`, `capitalized(with:)` and
// `capitalized`, on strings and on NSString. They map each scalar by its full Unicode mapping, as
// ICU does: Greek capital sigma lowercases to final ς at the end of a word, and a word's first
// letter takes its titlecase form ("ßeta" → "Sseta"). Foundation titles words two ways:
// `capitalized(with:)` titles the first letter or digit of each word, as ICU does, so "123hello"
// stays as it is, while the `capitalized` property titles every letter that follows an uncased
// one, as Core Foundation does ("123hello" → "123Hello"). Turkish and
// Azerbaijani map the dotted and dotless i ("I" lowercases to "ı", "i" uppercases to "İ", with or
// without accents after it), the one tailoring apps meet in practice; other languages' special
// rules (Lithuanian's retained dot, Greek's dropped accents in uppercase) are not kept.
// `_CaseMapping` is platform-neutral so WebFoundationTests hold it to Foundation on macOS; the
// extensions are wasm's alone.
#if os(WASI)
import FoundationEssentials
#else
import Foundation
#endif

/// The case mapping a locale asks for.
enum _CaseMapping {
    /// Whether `locale` maps i with Turkish rules.
    static func dottedI(_ locale: Locale?) -> Bool {
        guard let identifier = locale?.identifier else { return false }
        let language = identifier.split(whereSeparator: { $0 == "_" || $0 == "-" || $0 == "@" }).first.map(String.init) ?? identifier
        return language == "tr" || language == "az"
    }

    static func lowercased(_ string: String, dottedI: Bool) -> String {
        let scalars = Array(string.unicodeScalars)
        var result = ""
        var index = 0
        while index < scalars.count {
            let (piece, used) = lower(scalars, index, dottedI: dottedI)
            result += piece
            index += used
        }
        return result
    }

    static func uppercased(_ string: String, dottedI: Bool) -> String {
        var result = ""
        for scalar in string.unicodeScalars {
            result += dottedI && scalar == "i" ? "\u{0130}" : scalar.properties.uppercaseMapping
        }
        return result
    }

    /// `capitalized(with:)`'s form: each word's first letter or digit in titlecase and the rest in
    /// lowercase. A word runs over letters, marks, numbers and apostrophes, so "'hello" titles its
    /// h and "123hello" titles only its 1, which has no case.
    static func capitalized(_ string: String, dottedI: Bool) -> String {
        let scalars = Array(string.unicodeScalars)
        var result = ""
        var titled = false
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if !isWordPart(scalar) {
                titled = false
                result.unicodeScalars.append(scalar)
                index += 1
            } else if !titled && isLetterOrNumber(scalar) {
                titled = true
                result += dottedI && scalar == "i" ? "\u{0130}" : scalar.properties.titlecaseMapping
                index += 1
            } else {
                let (piece, used) = lower(scalars, index, dottedI: dottedI)
                result += piece
                index += used
            }
        }
        return result
    }

    /// The `capitalized` property's form, Core Foundation's: a letter after an uncased scalar
    /// (skipping case-ignorable ones such as apostrophes) in titlecase, the rest in lowercase, so
    /// "123hello" becomes "123Hello" and "don't" stays "Don't". Root rules only.
    static func capitalizedAfterUncased(_ string: String) -> String {
        let scalars = Array(string.unicodeScalars)
        var result = ""
        var lastCased = false
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            let properties = scalar.properties
            if lastCased {
                let (piece, used) = lower(scalars, index, dottedI: false)
                result += piece
                index += used
            } else {
                result += properties.titlecaseMapping
                index += 1
            }
            lastCased = properties.isCased || (properties.isCaseIgnorable && lastCased)
        }
        return result
    }

    /// The lowercase form of the scalar at `index`, and how many scalars it stands for (Turkish
    /// "I" with a combining dot above is one "i").
    private static func lower(_ scalars: [Unicode.Scalar], _ index: Int, dottedI: Bool) -> (String, Int) {
        let scalar = scalars[index]
        if dottedI {
            if scalar == "I" {
                return index + 1 < scalars.count && scalars[index + 1] == "\u{0307}" ? ("i", 2) : ("\u{0131}", 1)
            }
            if scalar == "\u{0130}" { return ("i", 1) }
        }
        if scalar == "\u{03A3}" { return (finalSigma(scalars, index) ? "\u{03C2}" : "\u{03C3}", 1) }
        return (scalar.properties.lowercaseMapping, 1)
    }

    /// Unicode's Final_Sigma: a cased letter before it and none after it, skipping case-ignorable
    /// scalars (marks, apostrophes) either way.
    private static func finalSigma(_ scalars: [Unicode.Scalar], _ index: Int) -> Bool {
        var before = index - 1
        while before >= 0, scalars[before].properties.isCaseIgnorable { before -= 1 }
        guard before >= 0, scalars[before].properties.isCased else { return false }
        var after = index + 1
        while after < scalars.count, scalars[after].properties.isCaseIgnorable { after += 1 }
        return !(after < scalars.count && scalars[after].properties.isCased)
    }

    private static func isLetterOrNumber(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    private static func isWordPart(_ scalar: Unicode.Scalar) -> Bool {
        if scalar == "'" || scalar == "\u{2019}" { return true }
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .spacingMark, .enclosingMark, .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }
}

#if os(WASI)
extension StringProtocol {
    /// Each word's first letter in uppercase and the rest in lowercase, in the root locale, a
    /// letter after a digit starting a word ("123hello" → "123Hello").
    public var capitalized: String { _CaseMapping.capitalizedAfterUncased(String(self)) }

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
