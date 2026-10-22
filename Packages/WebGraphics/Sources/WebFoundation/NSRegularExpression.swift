// `NSString` and `NSRegularExpression` on wasm (decision 0021, the Ember app's favourites page
// scrape: `html as NSString`, a pattern's matches by `NSRange`). FoundationEssentials has
// neither, and a regular-expression engine of its own would be most of a megabyte of wasm
// (`_StringProcessing`, the size trap of pf-web-foundation-gaps): the pattern runs on the
// browser's `RegExp` instead, through `_RegexHost`, whose strings are UTF-16 as NSString's
// ranges are — an index the host reports is the index the app indexes with. ICU and
// ECMAScript patterns agree on what apps write (`\d`, groups, classes, quantifiers); the
// corners where they differ (possessive quantifiers, `\p{...}` without the `u` flag,
// lookbehind in older engines) are the host's. Without a host the initializer throws.
//
// `NSString` is the stock SDK's: the interop SDK's compiler (decision 0023) takes a type of
// that name in the module named Foundation as Apple's Foundation being present and emits
// `@UIApplicationMain`'s entry against UIKit's Objective-C module, which that SDK has not
// (`emitArtificialTopLevel` asserts). There the bridge waits for the runtime's own `NSString`
// (the SDK's v1.5 direction); `NSRegularExpression` takes a `String` either way.
#if os(WASI)
#if !canImport(ObjectiveC)
/// A static, plain-text Unicode string object, bridged from `String` (`as NSString`).
public final class NSString: Hashable, CustomStringConvertible, @unchecked Sendable {
    public let string: String
    private lazy var utf16: [UInt16] = Array(string.utf16)

    public init(string: String) { self.string = string }
    public init() { string = "" }

    /// The number of UTF-16 code units.
    public var length: Int { string.utf16.count }

    public func substring(with range: NSRange) -> String { string.substring(with: range) }
    public func substring(from index: Int) -> String { string.substring(from: index) }
    public func character(at index: Int) -> UInt16 { utf16[index] }
    public func range(of searchString: String) -> NSRange {
        guard let found = string.range(of: searchString) else { return .notFound }
        return NSRange(found, in: string)
    }
    public func replacingOccurrences(of target: String, with replacement: String) -> String { string.replacingOccurrences(of: target, with: replacement) }
    public var lastPathComponent: String { URL(fileURLWithPath: string).lastPathComponent }
    public var pathExtension: String { URL(fileURLWithPath: string).pathExtension }
    public var lowercased: String { string.lowercased() }
    public var uppercased: String { string.uppercased() }
    public var description: String { string }
    public var hashValue: Int { string.hashValue }
    public func hash(into hasher: inout Hasher) { hasher.combine(string) }
    public static func == (lhs: NSString, rhs: NSString) -> Bool { lhs.string == rhs.string }
    public func isEqual(to aString: String) -> Bool { string == aString }
}

extension String: @retroactive _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSString
    public func _bridgeToObjectiveC() -> NSString { NSString(string: self) }
    public static func _forceBridgeFromObjectiveC(_ source: NSString, result: inout String?) { result = source.string }
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSString, result: inout String?) -> Bool { result = source.string; return true }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSString?) -> String { source?.string ?? "" }
}
#endif

/// What a host provides: a compiled pattern's matches over a string, as UTF-16 ranges.
public enum _RegexHost {
    /// A match: the whole range and each capture group's (location -1 for a group that did not take part).
    public struct Match: Sendable {
        public var ranges: [NSRange]
        public init(ranges: [NSRange]) { self.ranges = ranges }
    }
    /// `compile(pattern, flags)` returns nil for a pattern the engine rejects; `matches(handle, string, from, to)`
    /// every match within the UTF-16 range, in order.
    nonisolated(unsafe) public static var compile: ((_ pattern: String, _ flags: String) -> AnyObject?)?
    nonisolated(unsafe) public static var matches: ((_ handle: AnyObject, _ string: String, _ location: Int, _ length: Int) -> [Match])?
}

/// An immutable representation of a compiled regular expression that you apply to Unicode strings.
public final class NSRegularExpression: @unchecked Sendable {
    public struct Options: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let caseInsensitive = Options(rawValue: 1 << 0)
        public static let allowCommentsAndWhitespace = Options(rawValue: 1 << 1)
        public static let ignoreMetacharacters = Options(rawValue: 1 << 2)
        public static let dotMatchesLineSeparators = Options(rawValue: 1 << 3)
        public static let anchorsMatchLines = Options(rawValue: 1 << 4)
        public static let useUnixLineSeparators = Options(rawValue: 1 << 5)
        public static let useUnicodeWordBoundaries = Options(rawValue: 1 << 6)
    }

    public struct MatchingOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let reportProgress = MatchingOptions(rawValue: 1 << 0)
        public static let reportCompletion = MatchingOptions(rawValue: 1 << 1)
        public static let anchored = MatchingOptions(rawValue: 1 << 2)
        public static let withTransparentBounds = MatchingOptions(rawValue: 1 << 3)
        public static let withoutAnchoringBounds = MatchingOptions(rawValue: 1 << 4)
    }

    public struct _Error: Error, CustomStringConvertible {
        public let description: String
    }

    public let pattern: String
    public let options: Options
    public let numberOfCaptureGroups: Int
    private let handle: AnyObject

    /// Compiles the pattern on the host's engine; throws for a pattern it rejects or without a host.
    public init(pattern: String, options: Options = []) throws {
        self.pattern = pattern
        self.options = options
        guard let compile = _RegexHost.compile, _RegexHost.matches != nil else {
            throw _Error(description: "NSRegularExpression: no regular-expression engine in this host")
        }
        var flags = "g"
        if options.contains(.caseInsensitive) { flags += "i" }
        if options.contains(.anchorsMatchLines) { flags += "m" }
        if options.contains(.dotMatchesLineSeparators) { flags += "s" }
        let source = options.contains(.ignoreMetacharacters) ? NSRegularExpression.escapedPattern(for: pattern) : pattern
        guard let handle = compile(source, flags) else {
            throw _Error(description: "NSRegularExpression: the pattern “\(pattern)” is not valid")
        }
        self.handle = handle
        numberOfCaptureGroups = NSRegularExpression.countGroups(in: source)
    }

    /// Returns an array containing all the matches of the regular expression in the string.
    public func matches(in string: String, options: MatchingOptions = [], range: NSRange) -> [NSTextCheckingResult] {
        guard let find = _RegexHost.matches else { return [] }
        var results = find(handle, string, range.location, range.length).map { NSTextCheckingResult(ranges: $0.ranges, expression: self) }
        if options.contains(.anchored) { results = results.filter { $0.range.location == range.location } }
        return results
    }

    public func firstMatch(in string: String, options: MatchingOptions = [], range: NSRange) -> NSTextCheckingResult? {
        matches(in: string, options: options, range: range).first
    }

    public func numberOfMatches(in string: String, options: MatchingOptions = [], range: NSRange) -> Int {
        matches(in: string, options: options, range: range).count
    }

    public func rangeOfFirstMatch(in string: String, options: MatchingOptions = [], range: NSRange) -> NSRange {
        firstMatch(in: string, options: options, range: range)?.range ?? .notFound
    }

    public func enumerateMatches(in string: String, options: MatchingOptions = [], range: NSRange, using block: (NSTextCheckingResult?, MatchingFlags, UnsafeMutablePointer<ObjCBool>) -> Void) {
        var stop = ObjCBool(false)
        for match in matches(in: string, options: options, range: range) {
            block(match, [], &stop)
            if stop.boolValue { break }
        }
    }

    public struct MatchingFlags: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let progress = MatchingFlags(rawValue: 1 << 0)
        public static let completed = MatchingFlags(rawValue: 1 << 1)
        public static let hitEnd = MatchingFlags(rawValue: 1 << 2)
        public static let requiredEnd = MatchingFlags(rawValue: 1 << 3)
        public static let internalError = MatchingFlags(rawValue: 1 << 4)
    }

    /// The string with every match replaced by the template (`$1` for a group, `$0` the match).
    public func stringByReplacingMatches(in string: String, options: MatchingOptions = [], range: NSRange, withTemplate templ: String) -> String {
        let utf16 = Array(string.utf16)
        var out: [UInt16] = []
        var cursor = range.location
        for match in matches(in: string, options: options, range: range) {
            out += utf16[cursor..<match.range.location]
            out += Array(replacement(for: match, in: utf16, template: templ).utf16)
            cursor = match.range.location + match.range.length
        }
        out += utf16[cursor...]
        return String(decoding: out, as: UTF16.self)
    }

    public func replacementString(for result: NSTextCheckingResult, in string: String, offset: Int, template templ: String) -> String {
        replacement(for: result, in: Array(string.utf16), template: templ)
    }

    private func replacement(for match: NSTextCheckingResult, in utf16: [UInt16], template: String) -> String {
        var out = ""
        var iterator = template.makeIterator()
        while let character = iterator.next() {
            if character == "\\", let next = iterator.next() { out.append(next); continue }
            if character == "$", let digit = iterator.next(), let index = Int(String(digit)) {
                let range = match.range(at: index)
                if range.location != NSNotFound { out += String(decoding: utf16[range.location..<range.location + range.length], as: UTF16.self) }
                continue
            }
            out.append(character)
        }
        return out
    }

    /// The string with the characters that have meaning in a pattern escaped.
    public class func escapedPattern(for string: String) -> String {
        var out = ""
        for character in string {
            if "\\^$.|?*+()[]{}".contains(character) { out.append("\\") }
            out.append(character)
        }
        return out
    }

    public class func escapedTemplate(for string: String) -> String {
        var out = ""
        for character in string {
            if "\\$".contains(character) { out.append("\\") }
            out.append(character)
        }
        return out
    }

    /// The capture groups a pattern opens: `(` not escaped, not `(?...` other than a named group.
    private static func countGroups(in pattern: String) -> Int {
        var count = 0
        var characters = Array(pattern)
        var index = 0
        var inClass = false
        while index < characters.count {
            let c = characters[index]
            if c == "\\" { index += 2; continue }
            if inClass { if c == "]" { inClass = false }; index += 1; continue }
            if c == "[" { inClass = true; index += 1; continue }
            if c == "(" {
                let next = index + 1 < characters.count ? characters[index + 1] : " "
                if next != "?" || (index + 2 < characters.count && characters[index + 2] == "<" && index + 3 < characters.count && characters[index + 3] != "=" && characters[index + 3] != "!") { count += 1 }
            }
            index += 1
        }
        characters.removeAll()
        return count
    }
}

/// An occurrence of textual content found during the analysis of a block of text, such as
/// when matching a regular expression.
public final class NSTextCheckingResult: @unchecked Sendable {
    public let regularExpression: NSRegularExpression?
    private let ranges: [NSRange]

    init(ranges: [NSRange], expression: NSRegularExpression?) {
        self.ranges = ranges.isEmpty ? [.notFound] : ranges
        regularExpression = expression
    }

    public var range: NSRange { ranges[0] }
    public var numberOfRanges: Int { ranges.count }
    public func range(at idx: Int) -> NSRange { idx < ranges.count ? ranges[idx] : .notFound }
    public func range(withName name: String) -> NSRange { .notFound }
    public var resultType: CheckingType { .regularExpression }

    public struct CheckingType: OptionSet, Sendable {
        public let rawValue: UInt64
        public init(rawValue: UInt64) { self.rawValue = rawValue }
        public static let regularExpression = CheckingType(rawValue: 1 << 10)
    }
}


#endif
