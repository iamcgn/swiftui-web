// `NSAttributedString` and `NSMutableAttributedString` for wasm, where FoundationEssentials has
// neither. Packages that import only Foundation (ATProtoKit's facet parser, SwiftyFORM's form
// items) build attributed strings too, so the stand-in lives here rather than in UIKit; UIKit
// adds the drawing keys (`.font`, `.foregroundColor`) and string drawing on top.
#if os(WASI)

public typealias NSRangePointer = UnsafeMutablePointer<NSRange>

/// A string with attribute dictionaries per range (UTF-16 offsets, as Foundation's).
///
/// As in Foundation, two members are primitive: `string` and `attributes(at:effectiveRange:)`,
/// and the mutable string's `replaceCharacters(in:with:)` (a plain string) and
/// `setAttributes(_:range:)`. Every other member reads and writes through those, so a subclass
/// that keeps its text in a store of its own overrides the four and nothing else: a syntax
/// highlighter's `NSTextStorage` over a backing string (Highlightr's `CodeAttributedString`).
open class NSAttributedString: @unchecked Sendable {
    public struct Key: Hashable, RawRepresentable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
    }
    /// The stand-in's own text and runs, which a subclass with a store of its own leaves empty.
    var storedString: String
    /// The attribute runs covering `storedString` in order (adjacent, non-overlapping).
    var storedRuns: [(range: NSRange, attributes: [Key: Any])]

    public init(string: String, attributes: [Key: Any]? = nil) {
        storedString = string
        storedRuns = string.isEmpty ? [] : [(NSRange(location: 0, length: string.utf16.count), attributes ?? [:])]
    }
    public init(string: String) {
        storedString = string
        storedRuns = string.isEmpty ? [] : [(NSRange(location: 0, length: string.utf16.count), [:])]
    }
    public init(attributedString: NSAttributedString) {
        storedString = attributedString.string
        storedRuns = attributedString.runs
    }
    /// An empty attributed string.
    public convenience init() { self.init(string: "") }
    /// A Swift attributed string's characters and attributes: each attribute under its key's
    /// name (`.link` is "NSLink", UIKit's foreground colour "NSColor"), as Foundation's
    /// conversion keys them.
    public convenience init(_ attrStr: AttributedString) {
        let built = NSMutableAttributedString(string: "")
        for run in attrStr._runs where !run.string.isEmpty {
            var attributes: [Key: Any] = [:]
            for (name, value) in run.attributes.storage { attributes[Key(name)] = value.base.base }
            built.append(NSAttributedString(string: run.string, attributes: attributes))
        }
        self.init(attributedString: built)
    }

    /// The characters (primitive).
    open var string: String { storedString }
    public var length: Int { string.utf16.count }

    /// The attributes of the character at `location`, and the run they cover (primitive).
    open func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [Key: Any] {
        // The runs are in order: the last one starting at or before `location`.
        var low = 0, high = storedRuns.count
        while low < high {
            let middle = (low + high) / 2
            if storedRuns[middle].range.location <= location { low = middle + 1 } else { high = middle }
        }
        guard low > 0 else { return [:] }
        let run = storedRuns[low - 1]
        guard location < run.range.location + run.range.length else { return [:] }
        range?.pointee = run.range
        return run.attributes
    }

    /// The attribute runs covering the string in order, read through the primitives, so a
    /// subclass's own store is read too.
    var runs: [(range: NSRange, attributes: [Key: Any])] {
        attributeRuns(in: NSRange(location: 0, length: length))
    }

    /// The runs inside `range`, each cut to it.
    func attributeRuns(in range: NSRange) -> [(range: NSRange, attributes: [Key: Any])] {
        var result: [(range: NSRange, attributes: [Key: Any])] = []
        let limit = min(length, range.location + range.length)
        var location = max(0, range.location)
        while location < limit {
            var effective = NSRange(location: location, length: 1)
            let attributes = attributes(at: location, effectiveRange: &effective)
            let end = max(location + 1, min(limit, effective.location + effective.length))
            result.append((NSRange(location: location, length: end - location), attributes))
            location = end
        }
        return result
    }

    public func attribute(_ key: Key, at location: Int, effectiveRange range: NSRangePointer?) -> Any? {
        attributes(at: location, effectiveRange: range)[key]
    }

    /// Calls `block` for each run in `range`.
    public func enumerateAttributes(in range: NSRange, options: EnumerationOptions = [], using block: ([Key: Any], NSRange, UnsafeMutablePointer<Bool>) -> Void) {
        var stop = false
        for run in attributeRuns(in: range) {
            block(run.attributes, run.range, &stop)
            if stop { break }
        }
    }

    public func enumerateAttribute(_ key: Key, in range: NSRange, options: EnumerationOptions = [], using block: (Any?, NSRange, UnsafeMutablePointer<Bool>) -> Void) {
        enumerateAttributes(in: range, options: options) { attributes, range, stop in block(attributes[key], range, stop) }
    }

    public struct EnumerationOptions: OptionSet, Hashable, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let reverse = EnumerationOptions(rawValue: 1 << 1)
        public static let longestEffectiveRangeNotRequired = EnumerationOptions(rawValue: 1 << 20)
    }

    public func attributedSubstring(from range: NSRange) -> NSAttributedString {
        let utf16 = Array(string.utf16)
        let piece = String(decoding: utf16[max(0, range.location)..<min(utf16.count, max(range.location, range.location + range.length))], as: UTF16.self)
        let result = NSAttributedString(string: piece)
        result.storedRuns = attributeRuns(in: range).map { (NSRange(location: $0.range.location - range.location, length: $0.range.length), $0.attributes) }
        return result
    }
}

/// An attributed string whose text and attributes can change. Every change goes through
/// `replaceCharacters(in:with:)` with a plain string and `setAttributes(_:range:)`, the two
/// primitives a subclass with its own store overrides; a change of several steps is one edit
/// between `beginEditing()` and `endEditing()`.
open class NSMutableAttributedString: NSAttributedString, @unchecked Sendable {
    /// Called after every change to the stand-in's own store: whether the characters changed,
    /// the changed range in the new text, and how much longer the text got. A text storage
    /// overrides it to tell its layout managers (UIKit's `NSTextStorage`).
    open func _didChange(characters: Bool, range: NSRange, changeInLength: Int) {}

    /// Batching hints: edits here apply at once (a text storage holds its notifications until
    /// the last `endEditing`).
    open func beginEditing() {}
    open func endEditing() {}

    /// Replaces the characters in `range`, which take the attributes of the first character
    /// replaced (or of the one before, at the end) (primitive).
    open func replaceCharacters(in range: NSRange, with str: String) {
        let utf16 = Array(storedString.utf16)
        let head = String(decoding: utf16[0..<min(range.location, utf16.count)], as: UTF16.self)
        let tail = String(decoding: utf16[min(utf16.count, range.location + range.length)...], as: UTF16.self)
        let attributes = attributes(at: max(0, min(range.location, utf16.count - 1)), effectiveRange: nil)
        storedString = head + str + tail
        let delta = str.utf16.count - range.length
        var updated: [(range: NSRange, attributes: [Key: Any])] = []
        for run in storedRuns {
            let start = run.range.location, end = start + run.range.length
            if end <= range.location { updated.append(run); continue }
            if start >= range.location + range.length { updated.append((NSRange(location: start + delta, length: run.range.length), run.attributes)); continue }
            // The run overlaps the replaced range: keep the parts outside it.
            if start < range.location { updated.append((NSRange(location: start, length: range.location - start), run.attributes)) }
            if end > range.location + range.length { updated.append((NSRange(location: range.location + str.utf16.count, length: end - (range.location + range.length)), run.attributes)) }
        }
        if !str.isEmpty { updated.append((NSRange(location: range.location, length: str.utf16.count), attributes)) }
        storedRuns = updated.sorted { $0.range.location < $1.range.location }
        _didChange(characters: true, range: NSRange(location: range.location, length: str.utf16.count), changeInLength: delta)
    }

    /// Sets the attributes of the characters in `range`, replacing what they had (primitive).
    open func setAttributes(_ attributes: [Key: Any]?, range: NSRange) {
        var updated: [(range: NSRange, attributes: [Key: Any])] = []
        let rangeEnd = range.location + range.length
        for run in storedRuns {
            let start = run.range.location, end = start + run.range.length
            if end <= range.location || start >= rangeEnd { updated.append(run); continue }
            if start < range.location { updated.append((NSRange(location: start, length: range.location - start), run.attributes)) }
            let innerStart = max(start, range.location), innerEnd = min(end, rangeEnd)
            updated.append((NSRange(location: innerStart, length: innerEnd - innerStart), attributes ?? [:]))
            if end > rangeEnd { updated.append((NSRange(location: rangeEnd, length: end - rangeEnd), run.attributes)) }
        }
        storedRuns = updated
        _didChange(characters: false, range: range, changeInLength: 0)
    }

    /// Sets each run's attributes in `range` to `transform` of what it had, as one edit.
    private func transformAttributes(in range: NSRange, _ transform: ([Key: Any]) -> [Key: Any]) {
        let pieces = attributeRuns(in: range)
        guard !pieces.isEmpty else { return }
        beginEditing()
        for piece in pieces { setAttributes(transform(piece.attributes), range: piece.range) }
        endEditing()
    }

    open func addAttribute(_ key: Key, value: Any, range: NSRange) { addAttributes([key: value], range: range) }

    open func addAttributes(_ attributes: [Key: Any], range: NSRange) {
        transformAttributes(in: range) { $0.merging(attributes) { _, new in new } }
    }

    open func removeAttribute(_ key: Key, range: NSRange) {
        transformAttributes(in: range) { var copy = $0; copy[key] = nil; return copy }
    }

    /// Replaces the characters in `range` with `attributedString`'s, attributes and all.
    open func replaceCharacters(in range: NSRange, with attributedString: NSAttributedString) {
        // Read first: the string may be this one.
        let text = attributedString.string
        let pieces = attributedString.runs
        beginEditing()
        replaceCharacters(in: range, with: text)
        for piece in pieces {
            setAttributes(piece.attributes, range: NSRange(location: range.location + piece.range.location, length: piece.range.length))
        }
        endEditing()
    }

    open func append(_ attributedString: NSAttributedString) {
        replaceCharacters(in: NSRange(location: length, length: 0), with: attributedString)
    }

    open func insert(_ attributedString: NSAttributedString, at location: Int) {
        replaceCharacters(in: NSRange(location: location, length: 0), with: attributedString)
    }

    open func deleteCharacters(in range: NSRange) { replaceCharacters(in: range, with: "") }

    open func setAttributedString(_ attributedString: NSAttributedString) {
        replaceCharacters(in: NSRange(location: 0, length: length), with: attributedString)
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

/// Hashable, as Foundation's is (an `NSObject`): a struct that stores one synthesizes `Hashable`
/// (WhatsNewKit's `WhatsNew.Text`). Equal strings have equal text, so the text is the hash.
extension NSAttributedString: Hashable {
    public func hash(into hasher: inout Hasher) { hasher.combine(string) }
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

#endif
