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

    /// The range of the first occurrence of `string`, as NSString counts (`NSNotFound` when absent).
    public func range(of string: some StringProtocol, options: String.CompareOptions = []) -> NSRange {
        let haystack = options.contains(.caseInsensitive) ? String(self).lowercased() : String(self)
        let needle = options.contains(.caseInsensitive) ? String(string).lowercased() : String(string)
        guard !needle.isEmpty, let found = haystack._find(needle, from: haystack.startIndex) else { return .notFound }
        return NSRange(found, in: haystack)
    }
}

#endif
