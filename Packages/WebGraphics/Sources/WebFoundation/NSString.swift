// The NSString-era members apps reach for on String, and `NSRange` (decision 0021: Scrumdinger
// and the Speech stand-in). FoundationEssentials on wasm has neither; Apple's Foundation has both.
#if os(WASI)

/// A structure used to describe a portion of a series, such as characters in a string.
public struct NSRange: Hashable, Sendable, CustomStringConvertible {
    public var location: Int
    public var length: Int

    public init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }

    public init<R: RangeExpression>(_ range: R) where R.Bound == Int {
        let r = range.relative(to: Int.min..<Int.max)
        location = r.lowerBound
        length = r.upperBound - r.lowerBound
    }

    /// The range of `range` in `string`, counted in UTF-16 units as NSString counts.
    public init<R: RangeExpression, S: StringProtocol>(_ range: R, in string: S) where R.Bound == String.Index {
        let r = range.relative(to: string)
        let utf16 = string.utf16
        location = utf16.distance(from: utf16.startIndex, to: r.lowerBound)
        length = utf16.distance(from: r.lowerBound, to: r.upperBound)
    }

    public static let notFound = NSRange(location: NSNotFound, length: 0)
    public var lowerBound: Int { location }
    public var upperBound: Int { location + length }
    public var isEmpty: Bool { length == 0 }
    public func contains(_ index: Int) -> Bool { index >= location && index < location + length }
    public var description: String { "{\(location), \(length)}" }
}

public let NSNotFound = Int.max

extension Range where Bound == String.Index {
    /// The string range an `NSRange` of UTF-16 units covers, nil when it falls outside or splits a character.
    public init?<S: StringProtocol>(_ range: NSRange, in string: S) {
        guard range.location != NSNotFound else { return nil }
        let whole = String(string)
        let utf16 = whole.utf16
        guard let lower = utf16.index(utf16.startIndex, offsetBy: range.location, limitedBy: utf16.endIndex),
              let upper = utf16.index(lower, offsetBy: range.length, limitedBy: utf16.endIndex),
              let low = lower.samePosition(in: whole), let high = upper.samePosition(in: whole) else { return nil }
        self = low..<high
    }
}

extension Range where Bound == Int {
    public init?(_ range: NSRange) {
        guard range.location != NSNotFound else { return nil }
        self = range.location..<(range.location + range.length)
    }
}

public func NSMakeRange(_ location: Int, _ length: Int) -> NSRange { NSRange(location: location, length: length) }
public func NSMaxRange(_ range: NSRange) -> Int { range.location + range.length }
public func NSLocationInRange(_ location: Int, _ range: NSRange) -> Bool { range.contains(location) }

extension StringProtocol {
    /// The first occurrence of `needle` at or after `from`, scanning with `hasPrefix` (not
    /// `firstRange(of:)`, which is the Regex engine's: 1.4 MB of wasm, decision 0017).
    fileprivate func _find(_ needle: String, from: String.Index) -> Range<String.Index>? {
        var index = from
        while index < endIndex {
            if self[index...].hasPrefix(needle) { return index..<self.index(index, offsetBy: needle.count) }
            index = self.index(after: index)
        }
        return nil
    }

    /// A new string in which all occurrences of a target string are replaced by another.
    public func replacingOccurrences<Target: StringProtocol, Replacement: StringProtocol>(of target: Target, with replacement: Replacement) -> String {
        replacingOccurrences(of: target, with: replacement, options: [])
    }

    /// The case-insensitive form (`.caseInsensitive`); other options are taken as the plain search.
    public func replacingOccurrences<Target: StringProtocol, Replacement: StringProtocol>(of target: Target, with replacement: Replacement, options: String.CompareOptions) -> String {
        let needle = String(target)
        guard !needle.isEmpty else { return String(self) }
        let insensitive = options.contains(.caseInsensitive)
        let haystack = insensitive ? String(self).lowercased() : String(self)
        let pattern = insensitive ? needle.lowercased() : needle
        // Case mapping can change the count for a few letters; the positions are mapped by
        // character offset, which is what the letters apps replace keep.
        var result = ""
        var cursor = startIndex
        var searchFrom = haystack.startIndex
        while let found = haystack._find(pattern, from: searchFrom) {
            let start = index(cursor, offsetBy: haystack.distance(from: searchFrom, to: found.lowerBound))
            let end = index(start, offsetBy: needle.count, limitedBy: endIndex) ?? endIndex
            result += self[cursor..<start]
            result += replacement
            cursor = end
            searchFrom = found.upperBound
        }
        result += self[cursor...]
        return result
    }

    /// The occurrences inside `searchRange` only (all of the string when it is nil).
    public func replacingOccurrences<Target: StringProtocol, Replacement: StringProtocol>(of target: Target, with replacement: Replacement, options: String.CompareOptions = [], range searchRange: Range<Index>?) -> String {
        guard let searchRange else { return replacingOccurrences(of: target, with: replacement, options: options) }
        return String(self[..<searchRange.lowerBound]) + self[searchRange].replacingOccurrences(of: target, with: replacement, options: options) + self[searchRange.upperBound...]
    }

    /// The substring in the NSString range.
    public func substring(with range: NSRange) -> String {
        guard let r = Range(range, in: self) else { return "" }
        return String(self[r])
    }

    public func substring(from index: Int) -> String {
        let whole = String(self)
        let utf16 = whole.utf16
        guard let start = utf16.index(utf16.startIndex, offsetBy: index, limitedBy: utf16.endIndex), let low = start.samePosition(in: whole) else { return "" }
        return String(whole[low...])
    }

    public func substring(to index: Int) -> String {
        let whole = String(self)
        let utf16 = whole.utf16
        guard let end = utf16.index(utf16.startIndex, offsetBy: index, limitedBy: utf16.endIndex), let high = end.samePosition(in: whole) else { return whole }
        return String(whole[..<high])
    }

    /// The range of the first occurrence of `aString` (Foundation's `StringProtocol.range(of:)`),
    /// nil when absent: within `searchRange` when given, the last occurrence with `.backwards`,
    /// only at the start (the end, backwards) with `.anchored`, ignoring case with
    /// `.caseInsensitive`. The range is in this string's own indices, so a substring's range
    /// indexes its base string, as Foundation's does. The locale is not consulted.
    ///
    /// Shorter overloads come first: a module that sees Foundation's as well (a test target on
    /// wasm, which XCTest links it into) picks the overload with fewer defaulted arguments, ours,
    /// unless the call names a locale.
    public func range<T: StringProtocol>(of aString: T, options mask: String.CompareOptions = []) -> Range<Index>? {
        _range(of: aString, options: mask, range: nil)
    }

    public func range<T: StringProtocol>(of aString: T, options mask: String.CompareOptions = [],
                                         range searchRange: Range<Index>?) -> Range<Index>? {
        _range(of: aString, options: mask, range: searchRange)
    }

    public func range<T: StringProtocol>(of aString: T, options mask: String.CompareOptions = [],
                                         range searchRange: Range<Index>? = nil, locale: Locale?) -> Range<Index>? {
        _range(of: aString, options: mask, range: searchRange)
    }

    func _range<T: StringProtocol>(of aString: T, options mask: String.CompareOptions,
                                   range searchRange: Range<Index>?) -> Range<Index>? {
        let insensitive = mask.contains(.caseInsensitive)
        let needle = insensitive ? String(aString).lowercased() : String(aString)
        guard !needle.isEmpty else { return nil }
        let bounds = searchRange ?? startIndex..<endIndex
        /// Where a match starting at `start` ends, comparing a character at a time.
        func end(ofMatchAt start: Index) -> Index? {
            var position = start
            var rest = needle[...]
            while !rest.isEmpty {
                guard position < bounds.upperBound else { return nil }
                let character = insensitive ? self[position].lowercased() : String(self[position])
                guard rest.hasPrefix(character) else { return nil }
                rest = rest.dropFirst(character.count)
                position = index(after: position)
            }
            return position
        }
        if mask.contains(.backwards) {
            var start = bounds.upperBound
            while start > bounds.lowerBound {
                start = index(before: start)
                if let upper = end(ofMatchAt: start), !mask.contains(.anchored) || upper == bounds.upperBound {
                    return start..<upper
                }
            }
            return nil
        }
        var start = bounds.lowerBound
        while start < bounds.upperBound {
            if let upper = end(ofMatchAt: start) { return start..<upper }
            if mask.contains(.anchored) { return nil }
            start = index(after: start)
        }
        return nil
    }
}

#endif

#if os(WASI)
extension StringProtocol {
    /// Whether `other` occurs in the string, ignoring case and diacritics (Foundation's
    /// locale-aware contains, as a search over folded scalars: Latin letters stripped of
    /// their marks, then lowercased).
    public func localizedStandardContains<T: StringProtocol>(_ other: T) -> Bool {
        let needle = _foldedForSearch(String(other))
        guard !needle.isEmpty else { return false }
        return _foldedForSearch(String(self))._find(needle, from: nil) != nil
    }

    public func localizedCaseInsensitiveContains<T: StringProtocol>(_ other: T) -> Bool {
        let needle = String(other).lowercased()
        guard !needle.isEmpty else { return false }
        return String(self).lowercased()._find(needle, from: nil) != nil
    }

    /// The range of the first scalar in `aSet`, or the last with `.backwards`; `.anchored` looks
    /// only at the first scalar (the last, backwards). Within `aRange` when given.
    public func rangeOfCharacter(from aSet: CharacterSet, options mask: String.CompareOptions = [], range aRange: Range<String.Index>? = nil) -> Range<String.Index>? {
        let scalars = unicodeScalars
        let bounds = aRange ?? startIndex..<endIndex
        let backwards = mask.contains(.backwards)
        var found: Range<String.Index>?
        var index = bounds.lowerBound
        while index < bounds.upperBound {
            let next = scalars.index(after: index)
            if aSet.contains(scalars[index]) {
                if !backwards { return index..<next }
                if !mask.contains(.anchored) || next >= bounds.upperBound { found = index..<next }
            } else if !backwards && mask.contains(.anchored) {
                return nil
            }
            index = next
        }
        return found
    }
}

/// Lowercased with the common Latin diacritics dropped: "Côte d'Ivoire" → "cote d'ivoire"
/// (a table of the precomposed letters apps' data holds; FoundationEssentials on wasm has no
/// Unicode decomposition to lean on).
func _foldedForSearch(_ string: String) -> String {
    var result = ""
    for character in string.lowercased() {
        if let plain = _latinFolding[character] { result += plain } else { result.append(character) }
    }
    return result
}

private let _latinFolding: [Character: String] = {
    var table: [Character: String] = [:]
    for (plain, accented) in [("a", "àáâãäåāăą"), ("c", "çćĉċč"), ("d", "ďđ"), ("e", "èéêëēĕėęě"), ("g", "ĝğġģ"), ("h", "ĥħ"), ("i", "ìíîïĩīĭįı"),
                              ("j", "ĵ"), ("k", "ķ"), ("l", "ĺļľŀł"), ("n", "ñńņňŉ"), ("o", "òóôõöøōŏő"), ("r", "ŕŗř"), ("s", "śŝşšș"),
                              ("t", "ţťŧț"), ("u", "ùúûüũūŭůűų"), ("w", "ŵ"), ("y", "ýÿŷ"), ("z", "źżž"), ("ae", "æ"), ("oe", "œ"), ("ss", "ß")] {
        for accentedCharacter in accented { table[accentedCharacter] = plain }
    }
    return table
}()

extension StringProtocol {
    fileprivate func _find(_ needle: String, from: String.Index?) -> Range<String.Index>? {
        var index = from ?? startIndex
        while index < endIndex {
            if self[index...].hasPrefix(needle) { return index..<self.index(index, offsetBy: needle.count) }
            index = self.index(after: index)
        }
        return nil
    }
}
#endif

// The string object from bytes, and Foundation's guess at the bytes' encoding (OpenGraph reads a
// page's charset this way, TelemetryDeck prints JSON through `NSString(data:encoding:)`). The
// encodings are `String.Encoding`'s raw values, as Foundation's `NSString` takes them.
#if os(WASI)
import FoundationEssentials

/// The options `NSString.stringEncoding(for:…)` takes (the suggested encodings, lossy reading).
public struct StringEncodingDetectionOptionsKey: Hashable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let suggestedEncodingsKey = StringEncodingDetectionOptionsKey(rawValue: "NSStringEncodingDetectionSuggestedEncodingsKey")
    public static let disallowedEncodingsKey = StringEncodingDetectionOptionsKey(rawValue: "NSStringEncodingDetectionDisallowedEncodingsKey")
    public static let useOnlySuggestedEncodingsKey = StringEncodingDetectionOptionsKey(rawValue: "NSStringEncodingDetectionUseOnlySuggestedEncodingsKey")
    public static let allowLossyKey = StringEncodingDetectionOptionsKey(rawValue: "NSStringEncodingDetectionAllowLossyKey")
    public static let lossySubstitutionKey = StringEncodingDetectionOptionsKey(rawValue: "NSStringEncodingDetectionLossySubstitutionKey")
}

extension _WebNSString {
    /// The string the bytes spell in the encoding (`String.Encoding.utf8.rawValue`); nil when they
    /// are not valid in it.
    public convenience init?(data: Data, encoding: UInt) {
        guard let text = String(data: data, encoding: String.Encoding(rawValue: encoding)) else { return nil }
        self.init(string: text)
    }
    public convenience init?(bytes: UnsafeRawPointer, length: Int, encoding: UInt) {
        let buffer = UnsafeRawBufferPointer(start: bytes, count: length)
        guard let text = String(bytes: Array(buffer), encoding: String.Encoding(rawValue: encoding)) else { return nil }
        self.init(string: text)
    }
    public convenience init(format: String, _ arguments: Any...) {
        self.init(string: _PrintfFormat.format(format, arguments))
    }
    /// The string's bytes in the encoding, nil when a character has no code in it.
    public func data(using encoding: UInt, allowLossyConversion lossy: Bool = false) -> Data? {
        string.data(using: String.Encoding(rawValue: encoding), allowLossyConversion: lossy)
    }

    /// The encoding the bytes are most likely in, as a raw value (0 when none reads them), with
    /// the string they spell in it. A byte-order mark names its Unicode encoding; otherwise the
    /// suggested encodings are tried first, then UTF-8, then Windows Latin 1, which reads any bytes
    /// but five, then ISO Latin 1, which reads them all.
    public static func stringEncoding(for data: Data, encodingOptions opts: [StringEncodingDetectionOptionsKey: Any]? = nil,
                                      convertedString string: UnsafeMutablePointer<NSString?>?,
                                      usedLossyConversion: UnsafeMutablePointer<ObjCBool>?) -> UInt {
        usedLossyConversion?.pointee = ObjCBool(false)
        let bytes = data.bytes
        var candidates: [String.Encoding] = []
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            candidates = [.utf8]
        } else if bytes.starts(with: [0xFF, 0xFE, 0, 0]) || bytes.starts(with: [0, 0, 0xFE, 0xFF]) {
            candidates = [.utf32]
        } else if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) {
            candidates = [.utf16]
        } else {
            let suggested = (opts?[.suggestedEncodingsKey] as? [UInt] ?? (opts?[.suggestedEncodingsKey] as? [NSNumber])?.map(\.uintValue) ?? [])
                .map { String.Encoding(rawValue: $0) }
            let onlySuggested = (opts?[.useOnlySuggestedEncodingsKey] as? Bool) ?? false
            candidates = suggested + (onlySuggested ? [] : [.utf8, .windowsCP1252, .isoLatin1])
            let disallowed = Set(((opts?[.disallowedEncodingsKey] as? [UInt]) ?? []))
            candidates.removeAll { disallowed.contains($0.rawValue) }
        }
        for encoding in candidates {
            guard var text = String(data: data, encoding: encoding) else { continue }
            if text.first == "\u{FEFF}" { text.removeFirst() }
            string?.pointee = NSString(string: text)
            return encoding.rawValue
        }
        return 0
    }
}
#endif
