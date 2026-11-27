// The NSString comparisons and normalizations on wasm, where FoundationEssentials keeps them
// internal: `compare(_:options:range:locale:)`, the case-insensitive and localized forms,
// `folding(options:locale:)`, `replacingCharacters(in:with:)`, `components(separatedBy:)` with a
// character set, and the
// canonical normalization forms (`precomposedStringWithCanonicalMapping`, NFC, and
// `decomposedStringWithCanonicalMapping`, NFD) through the standard library's own tables.
// Case folding is Unicode's full folding ("ß" matches "SS"), as Foundation's. The localized
// forms order as the root collation does for the scripts apps sort: letters before their
// accented forms, and lowercase before uppercase only when nothing else differs ("a" < "A" <
// "b"); there is no per-language tailoring.
#if os(WASI)
@_spi(_Unicode) import Swift
import FoundationEssentials

public enum _StringCompare {
    /// Foundation's `compare(_:options:)`: literal or canonical, with case and diacritic
    /// folding and numeric runs as the options ask.
    public static func compare(_ lhs: String, _ rhs: String, options: String.CompareOptions = []) -> ComparisonResult {
        let left = keys(lhs, options: options)
        let right = keys(rhs, options: options)
        return order(left, right, numeric: options.contains(.numeric))
    }

    /// The root collation's order: letters first (case and accents folded), then accents,
    /// then case, lowercase first.
    public static func localizedCompare(_ lhs: String, _ rhs: String, options: String.CompareOptions = []) -> ComparisonResult {
        let numeric = options.contains(.numeric)
        let primary = order(keys(lhs, options: [.caseInsensitive, .diacriticInsensitive]),
                            keys(rhs, options: [.caseInsensitive, .diacriticInsensitive]), numeric: numeric)
        if primary != .orderedSame || options.contains(.diacriticInsensitive) && options.contains(.caseInsensitive) { return primary }
        if !options.contains(.diacriticInsensitive) {
            let secondary = order(keys(lhs, options: .caseInsensitive), keys(rhs, options: .caseInsensitive), numeric: numeric)
            if secondary != .orderedSame { return secondary }
        }
        if options.contains(.caseInsensitive) { return .orderedSame }
        // Lowercase sorts first: compare with the cases swapped.
        return order(keys(swappedCase(lhs), options: []), keys(swappedCase(rhs), options: []), numeric: numeric)
    }

    /// The scalars a comparison runs over.
    static func keys(_ input: String, options: String.CompareOptions, turkic: Bool = false) -> [Unicode.Scalar] {
        var string = options.contains(.widthInsensitive) ? widthFolded(input) : input
        // Turkish and Azeri fold dotless "I" to "ı" and dotted "İ" to "i".
        if turkic && options.contains(.caseInsensitive) {
            string = String(String.UnicodeScalarView(string.unicodeScalars.map { $0 == "I" ? "\u{131}" : $0 == "\u{130}" ? "i" : $0 }))
        }
        var scalars: [Unicode.Scalar] = []
        let decomposes = options.contains(.diacriticInsensitive)
        if options.contains(.literal) && !decomposes {
            scalars = Array(string.unicodeScalars)
        } else if decomposes {
            for scalar in string._nfd where scalar.properties.generalCategory != .nonspacingMark { scalars.append(scalar) }
        } else {
            scalars = Array(string._nfc)
        }
        guard options.contains(.caseInsensitive) else { return scalars }
        var folded: [Unicode.Scalar] = []
        for scalar in scalars { folded += scalar.properties._caseFolded.unicodeScalars }
        // A folded scalar can compose with its neighbours again.
        return decomposes ? folded : Array(String(String.UnicodeScalarView(folded))._nfc)
    }

    /// Halfwidth katakana, each as its fullwidth form (U+FF61 to U+FF9F); the two halfwidth
    /// sound marks become the combining ones, which compose with the kana before them.
    private static let halfwidthKatakana: [UInt16] = [
        0x3002, 0x300C, 0x300D, 0x3001, 0x30FB, 0x30F2, 0x30A1, 0x30A3, 0x30A5, 0x30A7, 0x30A9, 0x30E3, 0x30E5,
        0x30E7, 0x30C3, 0x30FC, 0x30A2, 0x30A4, 0x30A6, 0x30A8, 0x30AA, 0x30AB, 0x30AD, 0x30AF, 0x30B1, 0x30B3,
        0x30B5, 0x30B7, 0x30B9, 0x30BB, 0x30BD, 0x30BF, 0x30C1, 0x30C4, 0x30C6, 0x30C8, 0x30CA, 0x30CB, 0x30CC,
        0x30CD, 0x30CE, 0x30CF, 0x30D2, 0x30D5, 0x30D8, 0x30DB, 0x30DE, 0x30DF, 0x30E0, 0x30E1, 0x30E2, 0x30E4,
        0x30E6, 0x30E8, 0x30E9, 0x30EA, 0x30EB, 0x30EC, 0x30ED, 0x30EF, 0x30F3, 0x3099, 0x309A,
    ]
    /// The fullwidth signs U+FFE0 to U+FFE6 as their ordinary forms.
    private static let fullwidthSigns: [UInt16] = [0xA2, 0xA3, 0xAC, 0xAF, 0xA6, 0xA5, 0x20A9]

    /// The string with its width variants as their ordinary forms, as `.widthInsensitive`
    /// compares them: fullwidth ASCII and signs and the ideographic space narrowed, halfwidth
    /// katakana widened ("ｶﾞ" to "ガ").
    static func widthFolded(_ string: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in string.unicodeScalars {
            let value = scalar.value
            let mapped: UInt32
            switch value {
            case 0xFF01...0xFF5E: mapped = value - 0xFEE0
            case 0x3000: mapped = 0x20
            case 0xFF61...0xFF9F: mapped = UInt32(halfwidthKatakana[Int(value - 0xFF61)])
            case 0xFFE0...0xFFE6: mapped = UInt32(fullwidthSigns[Int(value - 0xFFE0)])
            default: mapped = value
            }
            result.append(Unicode.Scalar(mapped) ?? scalar)
        }
        return String(result)
    }

    static func swappedCase(_ string: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in string.unicodeScalars {
            let properties = scalar.properties
            let swapped = properties.isLowercase ? properties.uppercaseMapping : properties.isUppercase ? properties.lowercaseMapping : String(scalar)
            result.append(contentsOf: swapped.unicodeScalars)
        }
        return String(result)
    }

    /// Scalar by scalar, with runs of ASCII digits compared by value when `numeric`.
    static func order(_ left: [Unicode.Scalar], _ right: [Unicode.Scalar], numeric: Bool) -> ComparisonResult {
        var i = 0, j = 0
        func isDigit(_ scalar: Unicode.Scalar) -> Bool { ("0"..."9").contains(scalar) }
        while i < left.count && j < right.count {
            if numeric && isDigit(left[i]) && isDigit(right[j]) {
                var iEnd = i, jEnd = j
                while iEnd < left.count && isDigit(left[iEnd]) { iEnd += 1 }
                while jEnd < right.count && isDigit(right[jEnd]) { jEnd += 1 }
                var a = left[i..<iEnd].drop { $0 == "0" }, b = right[j..<jEnd].drop { $0 == "0" }
                if a.isEmpty { a = left[(iEnd - 1)..<iEnd] }
                if b.isEmpty { b = right[(jEnd - 1)..<jEnd] }
                if a.count != b.count { return a.count < b.count ? .orderedAscending : .orderedDescending }
                for (x, y) in zip(a, b) where x != y { return x.value < y.value ? .orderedAscending : .orderedDescending }
                i = iEnd
                j = jEnd
                continue
            }
            if left[i] != right[j] { return left[i].value < right[j].value ? .orderedAscending : .orderedDescending }
            i += 1
            j += 1
        }
        let leftDone = i >= left.count, rightDone = j >= right.count
        return leftDone && rightDone ? .orderedSame : leftDone ? .orderedAscending : .orderedDescending
    }

    /// Canonical composition (NFC).
    public static func precomposed(_ string: String) -> String { String(String.UnicodeScalarView(Array(string._nfc))) }
    /// Canonical decomposition (NFD).
    public static func decomposed(_ string: String) -> String { String(String.UnicodeScalarView(Array(string._nfd))) }
}

extension StringProtocol {
    /// The order of this string and `aString` (within `range` of this one) under `mask`'s
    /// options; with a `locale`, as `localizedCompare` orders.
    public func compare<T: StringProtocol>(_ aString: T, options mask: String.CompareOptions = [], range: Range<String.Index>? = nil, locale: Locale? = nil) -> ComparisonResult {
        let subject = range.map { String(self[$0]) } ?? String(self)
        if locale != nil { return _StringCompare.localizedCompare(subject, String(aString), options: mask) }
        return _StringCompare.compare(subject, String(aString), options: mask)
    }
    public func caseInsensitiveCompare<T: StringProtocol>(_ aString: T) -> ComparisonResult {
        _StringCompare.compare(String(self), String(aString), options: .caseInsensitive)
    }
    public func localizedCompare<T: StringProtocol>(_ aString: T) -> ComparisonResult {
        _StringCompare.localizedCompare(String(self), String(aString))
    }
    public func localizedCaseInsensitiveCompare<T: StringProtocol>(_ aString: T) -> ComparisonResult {
        _StringCompare.localizedCompare(String(self), String(aString), options: .caseInsensitive)
    }
    /// The Finder's order: localized, with numbers compared by value ("File 2" < "File 10").
    public func localizedStandardCompare<T: StringProtocol>(_ string: T) -> ComparisonResult {
        _StringCompare.localizedCompare(String(self), String(string), options: .numeric)
    }

    /// The string with the distinctions `options` ignores taken out, as comparisons with those
    /// options see it: case folded with `.caseInsensitive` (in Turkish and Azeri, "I" to "ı"),
    /// accents and other combining marks dropped with `.diacriticInsensitive` ("Él" to "El"),
    /// and width variants made ordinary with `.widthInsensitive` ("ａ" to "a"). The result is
    /// precomposed.
    public func folding(options: String.CompareOptions = [], locale: Locale?) -> String {
        let text = String(self)
        let folds: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]
        guard !options.isDisjoint(with: folds) else { return text }
        let language = locale?.identifier.split(whereSeparator: { $0 == "_" || $0 == "-" }).first
        let turkic = language == "tr" || language == "az"
        if options.isDisjoint(with: [.caseInsensitive, .diacriticInsensitive]) { return _StringCompare.precomposed(_StringCompare.widthFolded(text)) }
        return _StringCompare.precomposed(String(String.UnicodeScalarView(_StringCompare.keys(text, options: options, turkic: turkic))))
    }

    /// The longest start this string shares with `aString`, taken from this string; characters
    /// match as `compare(_:options:)` with `mask` matches them (`.caseInsensitive` lets "Ab"
    /// and "aB" share both).
    public func commonPrefix<T: StringProtocol>(with aString: T, options mask: String.CompareOptions = []) -> String {
        var result = ""
        var other = String(aString).makeIterator()
        for character in String(self) {
            guard let next = other.next() else { break }
            let same = mask.isEmpty ? character == next
                : _StringCompare.compare(String(character), String(next), options: mask) == .orderedSame
            guard same else { break }
            result.append(character)
        }
        return result
    }

    /// The string with the characters in `range` replaced.
    public func replacingCharacters<T: StringProtocol, R: RangeExpression>(in range: R, with replacement: T) -> String where R.Bound == String.Index {
        let bounds = range.relative(to: self)
        return String(self[startIndex..<bounds.lowerBound]) + String(replacement) + String(self[bounds.upperBound...])
    }

    /// The pieces between the scalars in `separator` (empty ones included, as Foundation's).
    public func components(separatedBy separator: CharacterSet) -> [String] {
        var pieces: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in String(self).unicodeScalars {
            if separator.contains(scalar) {
                pieces.append(String(current))
                current = String.UnicodeScalarView()
            } else {
                current.append(scalar)
            }
        }
        pieces.append(String(current))
        return pieces
    }

    /// Each word's first letter in uppercase and the rest in lowercase, in the root locale's
    /// case mapping (no per-language rules, such as Turkish dotted i).
    public var localizedCapitalized: String {
        var result = ""
        var startsWord = true
        for character in String(self) {
            result += startsWord ? character.uppercased() : character.lowercased()
            startsWord = !(character.isLetter || character.isNumber || character == "'" || character == "’")
        }
        return result
    }
    public var localizedLowercase: String { String(self).lowercased() }
    public var localizedUppercase: String { String(self).uppercased() }

    public var precomposedStringWithCanonicalMapping: String { _StringCompare.precomposed(String(self)) }
    public var decomposedStringWithCanonicalMapping: String { _StringCompare.decomposed(String(self)) }
}
#endif
