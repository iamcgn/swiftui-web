// `NSAttributedString` and `NSMutableAttributedString` for wasm, where FoundationEssentials has
// neither. Packages that import only Foundation (ATProtoKit's facet parser, SwiftyFORM's form
// items) build attributed strings too, so the stand-in lives here rather than in UIKit; UIKit
// adds the drawing keys (`.font`, `.foregroundColor`) and string drawing on top.
#if os(WASI)

public typealias NSRangePointer = UnsafeMutablePointer<NSRange>

/// A string with attribute dictionaries per range (UTF-16 offsets, as Foundation's).
open class NSAttributedString: @unchecked Sendable {
    public struct Key: Hashable, RawRepresentable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
    }
    public internal(set) var string: String
    /// The attribute runs covering the string in order (adjacent, non-overlapping).
    var runs: [(range: NSRange, attributes: [Key: Any])]

    public init(string: String, attributes: [Key: Any]? = nil) {
        self.string = string
        runs = string.isEmpty ? [] : [(NSRange(location: 0, length: string.utf16.count), attributes ?? [:])]
    }
    public init(string: String) {
        self.string = string
        runs = string.isEmpty ? [] : [(NSRange(location: 0, length: string.utf16.count), [:])]
    }
    public init(attributedString: NSAttributedString) {
        string = attributedString.string
        runs = attributedString.runs
    }
    /// The characters of a Swift attributed string (its attributes, keyed by scope there, have
    /// no `Key` counterparts here).
    public convenience init(_ attrStr: AttributedString) {
        self.init(string: String(attrStr.characters))
    }
    public var length: Int { string.utf16.count }

    public func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [Key: Any] {
        guard let run = runs.first(where: { location >= $0.range.location && location < $0.range.location + $0.range.length }) else { return [:] }
        range?.pointee = run.range
        return run.attributes
    }

    public func attribute(_ key: Key, at location: Int, effectiveRange range: NSRangePointer?) -> Any? {
        attributes(at: location, effectiveRange: range)[key]
    }

    /// Calls `block` for each run in `range` (the stand-in's runs are already maximal).
    public func enumerateAttributes(in range: NSRange, options: EnumerationOptions = [], using block: ([Key: Any], NSRange, UnsafeMutablePointer<Bool>) -> Void) {
        var stop = false
        for run in runs where run.range.location < range.location + range.length && run.range.location + run.range.length > range.location {
            let start = max(run.range.location, range.location)
            let end = min(run.range.location + run.range.length, range.location + range.length)
            block(run.attributes, NSRange(location: start, length: end - start), &stop)
            if stop { break }
        }
    }

    public func enumerateAttribute(_ key: Key, in range: NSRange, options: EnumerationOptions = [], using block: (Any?, NSRange, UnsafeMutablePointer<Bool>) -> Void) {
        enumerateAttributes(in: range, options: options) { attributes, range, stop in block(attributes[key], range, stop) }
    }

    public struct EnumerationOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let reverse = EnumerationOptions(rawValue: 1 << 1)
        public static let longestEffectiveRangeNotRequired = EnumerationOptions(rawValue: 1 << 20)
    }

    public func attributedSubstring(from range: NSRange) -> NSAttributedString {
        let utf16 = Array(string.utf16)
        let piece = String(decoding: utf16[max(0, range.location)..<min(utf16.count, range.location + range.length)], as: UTF16.self)
        let result = NSMutableAttributedString(string: "")
        result.string = piece
        result.runs = []
        enumerateAttributes(in: range) { attributes, sub, _ in
            result.runs.append((NSRange(location: sub.location - range.location, length: sub.length), attributes))
        }
        return result
    }
}

/// An attributed string whose text and attributes can change.
open class NSMutableAttributedString: NSAttributedString, @unchecked Sendable {
    public func append(_ attributedString: NSAttributedString) {
        let offset = length
        string += attributedString.string
        runs += attributedString.runs.map { (NSRange(location: $0.range.location + offset, length: $0.range.length), $0.attributes) }
    }

    public func addAttribute(_ key: Key, value: Any, range: NSRange) { addAttributes([key: value], range: range) }

    public func addAttributes(_ attributes: [Key: Any], range: NSRange) {
        apply(range) { $0.merging(attributes) { _, new in new } }
    }

    public func setAttributes(_ attributes: [Key: Any]?, range: NSRange) {
        apply(range) { _ in attributes ?? [:] }
    }

    public func removeAttribute(_ key: Key, range: NSRange) {
        apply(range) { var copy = $0; copy[key] = nil; return copy }
    }

    public func replaceCharacters(in range: NSRange, with str: String) {
        let utf16 = Array(string.utf16)
        let head = String(decoding: utf16[0..<min(range.location, utf16.count)], as: UTF16.self)
        let tail = String(decoding: utf16[min(utf16.count, range.location + range.length)...], as: UTF16.self)
        let attributes = attributes(at: max(0, min(range.location, length - 1)), effectiveRange: nil)
        string = head + str + tail
        let delta = str.utf16.count - range.length
        var updated: [(range: NSRange, attributes: [Key: Any])] = []
        for run in runs {
            let start = run.range.location, end = start + run.range.length
            if end <= range.location { updated.append(run); continue }
            if start >= range.location + range.length { updated.append((NSRange(location: start + delta, length: run.range.length), run.attributes)); continue }
            // The run overlaps the replaced range: keep the parts outside it.
            if start < range.location { updated.append((NSRange(location: start, length: range.location - start), run.attributes)) }
            if end > range.location + range.length { updated.append((NSRange(location: range.location + str.utf16.count, length: end - (range.location + range.length)), run.attributes)) }
        }
        if !str.isEmpty { updated.append((NSRange(location: range.location, length: str.utf16.count), attributes)) }
        runs = updated.sorted { $0.range.location < $1.range.location }
    }

    /// Splits the runs at `range`'s ends and transforms the attributes inside it.
    private func apply(_ range: NSRange, _ transform: ([Key: Any]) -> [Key: Any]) {
        var updated: [(range: NSRange, attributes: [Key: Any])] = []
        let rangeEnd = range.location + range.length
        for run in runs {
            let start = run.range.location, end = start + run.range.length
            if end <= range.location || start >= rangeEnd { updated.append(run); continue }
            if start < range.location { updated.append((NSRange(location: start, length: range.location - start), run.attributes)) }
            let innerStart = max(start, range.location), innerEnd = min(end, rangeEnd)
            updated.append((NSRange(location: innerStart, length: innerEnd - innerStart), transform(run.attributes)))
            if end > rangeEnd { updated.append((NSRange(location: rangeEnd, length: end - rangeEnd), run.attributes)) }
        }
        runs = updated
    }
}

extension NSAttributedString: Equatable {
    /// Two attributed strings are equal when their text matches and each run carries the same
    /// keys with values that compare equal (values that aren't `Equatable` compare by identity
    /// when they are objects).
    public static func == (lhs: NSAttributedString, rhs: NSAttributedString) -> Bool {
        lhs.isEqual(to: rhs)
    }

    public func isEqual(to other: NSAttributedString) -> Bool {
        guard string == other.string else { return false }
        var equal = true
        var location = 0
        while location < length, equal {
            var mine = NSRange(location: 0, length: 0), theirs = NSRange(location: 0, length: 0)
            let a = attributes(at: location, effectiveRange: &mine)
            let b = other.attributes(at: location, effectiveRange: &theirs)
            equal = Self.sameAttributes(a, b)
            location = max(location + 1, min(mine.location + mine.length, theirs.location + theirs.length))
        }
        return equal
    }

    static func sameAttributes(_ a: [Key: Any], _ b: [Key: Any]) -> Bool {
        guard a.count == b.count else { return false }
        for (key, value) in a {
            guard let other = b[key] else { return false }
            if let x = value as? AnyHashable, let y = other as? AnyHashable {
                if x != y { return false }
            } else if type(of: value) is AnyClass, type(of: other) is AnyClass {
                if (value as AnyObject) !== (other as AnyObject) { return false }
            } else {
                return false
            }
        }
        return true
    }
}

extension NSAttributedString {
    public func copy() -> Any { NSAttributedString(attributedString: self) }
    public func mutableCopy() -> Any { NSMutableAttributedString(attributedString: self) }

    /// The longest range around `location` over which the attributes stay the same.
    public func attributes(at location: Int, longestEffectiveRange range: NSRangePointer?, in rangeLimit: NSRange) -> [Key: Any] {
        let found = attributes(at: location, effectiveRange: range)
        if let range {
            let limitEnd = rangeLimit.location + rangeLimit.length
            let start = max(range.pointee.location, rangeLimit.location)
            let end = min(range.pointee.location + range.pointee.length, limitEnd)
            range.pointee = NSRange(location: start, length: max(0, end - start))
        }
        return found
    }

    public func attribute(_ key: Key, at location: Int, longestEffectiveRange range: NSRangePointer?, in rangeLimit: NSRange) -> Any? {
        attributes(at: location, longestEffectiveRange: range, in: rangeLimit)[key]
    }
}

extension NSMutableAttributedString {
    public func insert(_ attributedString: NSAttributedString, at location: Int) {
        let tail = attributedSubstring(from: NSRange(location: location, length: length - location))
        let head = attributedSubstring(from: NSRange(location: 0, length: location))
        let result = NSMutableAttributedString(attributedString: head)
        result.append(attributedString)
        result.append(tail)
        setAttributedString(result)
    }

    public func replaceCharacters(in range: NSRange, with attributedString: NSAttributedString) {
        let tail = attributedSubstring(from: NSRange(location: range.location + range.length, length: length - range.location - range.length))
        let head = attributedSubstring(from: NSRange(location: 0, length: range.location))
        let result = NSMutableAttributedString(attributedString: head)
        result.append(attributedString)
        result.append(tail)
        setAttributedString(result)
    }

    public func deleteCharacters(in range: NSRange) { replaceCharacters(in: range, with: "") }

    public func setAttributedString(_ attributedString: NSAttributedString) {
        string = attributedString.string
        runs = attributedString.runs
    }

    /// Batching hints: edits here apply at once, so both are no-ops.
    public func beginEditing() {}
    public func endEditing() {}
}
#endif
