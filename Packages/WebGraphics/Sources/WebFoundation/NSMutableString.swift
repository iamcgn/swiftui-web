// `NSMutableString` on wasm, and the NSString members text engines call on it: the composed
// character sequence around a UTF-16 range, and `getBytes(_:maxLength:usedLength:encoding:...)`,
// which copies a range's characters into a buffer in an encoding (Runestone keeps its text in an
// `NSMutableString` and hands tree-sitter its UTF-16 bytes this way). Each answers as Apple's
// Foundation does for the same string (Tests/FrameworkTests/NSStringMethodsTests.swift runs the
// shared cases against Foundation on macOS and Linux too).
#if os(WASI)

/// A string object whose characters change in place, in UTF-16 ranges.
public class NSMutableString: NSString, @unchecked Sendable {
    /// An empty string; the capacity is a hint, as Foundation's is.
    public convenience init(capacity: Int) { self.init(string: "") }

    /// Replaces the characters in `range` with `aString`.
    public func replaceCharacters(in range: NSRange, with aString: String) {
        var units = utf16
        units.replaceSubrange(range.location..<NSMaxRange(range), with: aString.utf16)
        string = String(decoding: units, as: UTF16.self)
    }

    public func insert(_ aString: String, at loc: Int) {
        replaceCharacters(in: NSRange(location: loc, length: 0), with: aString)
    }

    public func deleteCharacters(in range: NSRange) {
        replaceCharacters(in: range, with: "")
    }

    public func append(_ aString: String) {
        string += aString
    }

    public func setString(_ aString: String) {
        string = aString
    }

    /// Replaces each occurrence of `target` in `searchRange`, answering how many it replaced.
    @discardableResult
    public func replaceOccurrences(of target: String, with replacement: String, options: CompareOptions = [], range searchRange: NSRange) -> Int {
        guard !target.isEmpty else { return 0 }
        var count = 0
        var remaining = searchRange
        var edits: [NSRange] = []
        while remaining.length > 0 {
            let found = range(of: target, options: options.subtracting(.backwards), range: remaining)
            guard found.location != NSNotFound, found.length > 0 else { break }
            edits.append(found)
            count += 1
            let next = NSMaxRange(found)
            remaining = NSRange(location: next, length: NSMaxRange(remaining) - next)
            if options.contains(.anchored) { break }
        }
        // From the end, so the earlier ranges stay where they were found.
        for found in edits.reversed() { replaceCharacters(in: found, with: replacement) }
        return count
    }
}

extension _WebNSString {
    /// How `getBytes(_:maxLength:usedLength:encoding:options:range:remaining:)` converts.
    public struct EncodingConversionOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        /// A character the encoding cannot hold is written as a substitute instead of stopping.
        public static let allowLossy = EncodingConversionOptions(rawValue: 1)
        /// A UTF-16 or UTF-32 conversion from the start of the string begins with a byte-order mark.
        public static let externalRepresentation = EncodingConversionOptions(rawValue: 2)
    }

    /// The UTF-16 range of the composed character sequence (the user-perceived character) that
    /// holds the unit at `index`.
    public func rangeOfComposedCharacterSequence(at index: Int) -> NSRange {
        var offset = 0
        for character in string {
            let width = character.utf16.count
            if index < offset + width { return NSRange(location: offset, length: width) }
            offset += width
        }
        return NSRange(location: index, length: 0)
    }

    /// `range` widened to whole composed character sequences at both ends.
    public func rangeOfComposedCharacterSequences(for range: NSRange) -> NSRange {
        let total = utf16.count
        guard range.location < total else { return NSRange(location: range.location, length: 0) }
        let start = rangeOfComposedCharacterSequence(at: range.location).location
        var end = NSMaxRange(range)
        if end > range.location {
            end = NSMaxRange(rangeOfComposedCharacterSequence(at: min(end, total) - 1))
        }
        return NSRange(location: start, length: max(end, start) - start)
    }

    /// Copies the characters of `range`, converted to `encoding`, into `buffer`, as many whole
    /// characters as fit in `maxBufferCount` bytes (all of them when `buffer` is nil, which only
    /// measures). `usedBufferCount` gets the bytes written and `leftover` the characters left;
    /// false when no character could be converted.
    public func getBytes(_ buffer: UnsafeMutableRawPointer?, maxLength maxBufferCount: Int, usedLength usedBufferCount: UnsafeMutablePointer<Int>?,
                         encoding: UInt, options: EncodingConversionOptions = [], range: NSRange, remaining leftover: NSRangePointer?) -> Bool {
        let units = utf16
        let end = min(NSMaxRange(range), units.count)
        var index = max(range.location, 0)
        var used = 0
        let asked = String.Encoding(rawValue: encoding)
        let lossy = options.contains(.allowLossy)
        var withMark = options.contains(.externalRepresentation) && index == 0
        // Every unit after the mark is written in the plain byte order the mark announces.
        let core: _TextEncoding?
        switch asked._core {
        case .utf16?: core = .utf16LittleEndian
        case .utf32?: core = .utf32LittleEndian
        default: core = asked._core; withMark = false
        }
        guard let core else {
            usedBufferCount?.pointee = 0
            leftover?.pointee = NSRange(location: index, length: max(end - index, 0))
            return false
        }
        func write(_ bytes: [UInt8]) -> Bool {
            if buffer != nil, used + bytes.count > maxBufferCount { return false }
            if let buffer {
                bytes.withUnsafeBytes { (buffer + used).copyMemory(from: $0.baseAddress!, byteCount: bytes.count) }
            }
            used += bytes.count
            return true
        }
        var converted = false
        if withMark { _ = write(core == .utf16LittleEndian ? [0xFF, 0xFE] : [0xFF, 0xFE, 0x00, 0x00]) }
        while index < end {
            var width = 1
            if UTF16.isLeadSurrogate(units[index]), index + 1 < end, UTF16.isTrailSurrogate(units[index + 1]) { width = 2 }
            let piece: [UInt8]?
            if core == .utf16LittleEndian || core == .utf16BigEndian {
                // UTF-16 carries each unit as it is, a lone surrogate included.
                piece = units[index..<index + width].flatMap { unit -> [UInt8] in
                    let high = UInt8(unit >> 8), low = UInt8(unit & 0xFF)
                    return core == .utf16LittleEndian ? [low, high] : [high, low]
                }
            } else {
                piece = _TextEncoding.encode(String(decoding: units[index..<index + width], as: UTF16.self), as: core, lossy: lossy)
            }
            guard let piece, write(piece) else { break }
            converted = true
            index += width
        }
        usedBufferCount?.pointee = used
        leftover?.pointee = NSRange(location: index, length: max(end - index, 0))
        return converted
    }
}
#endif
