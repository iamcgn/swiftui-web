// The rest of NSString's everyday members on wasm, which code written against the string object
// calls through `as NSString`: searching and comparing in UTF-16 `NSRange`s, the line and
// paragraph around a range, padding and trimming, and the path forms (StyledTextKit trims an
// attributed string with `rangeOfCharacter(from:options: .backwards)`, apps append file names
// with `appendingPathComponent`). Each answers as Apple's Foundation does for the same string;
// the shared cases run against Foundation on macOS and Linux too
// (Tests/FrameworkTests/NSStringMethodsTests.swift). The locale is not consulted.
#if os(WASI)
extension _WebNSString {
    public typealias CompareOptions = String.CompareOptions

    /// The string range an `NSRange` covers, all of the string when it falls outside.
    private func bounds(_ range: NSRange) -> Range<String.Index> {
        Range(range, in: string) ?? string.startIndex..<string.endIndex
    }

    private func nsRange(_ range: Range<String.Index>?) -> NSRange {
        range.map { NSRange($0, in: string) } ?? .notFound
    }

    // MARK: Searching

    public func range(of searchString: String, options mask: CompareOptions = []) -> NSRange {
        nsRange(string.range(of: searchString, options: mask))
    }

    public func range(of searchString: String, options mask: CompareOptions = [], range rangeOfReceiverToSearch: NSRange) -> NSRange {
        nsRange(string.range(of: searchString, options: mask, range: bounds(rangeOfReceiverToSearch)))
    }

    public func range(of searchString: String, options mask: CompareOptions = [], range rangeOfReceiverToSearch: NSRange,
                      locale: Locale?) -> NSRange {
        range(of: searchString, options: mask, range: rangeOfReceiverToSearch)
    }

    public func rangeOfCharacter(from searchSet: CharacterSet) -> NSRange {
        nsRange(string.rangeOfCharacter(from: searchSet))
    }

    public func rangeOfCharacter(from searchSet: CharacterSet, options mask: CompareOptions = []) -> NSRange {
        nsRange(string.rangeOfCharacter(from: searchSet, options: mask))
    }

    public func rangeOfCharacter(from searchSet: CharacterSet, options mask: CompareOptions = [], range rangeOfReceiverToSearch: NSRange) -> NSRange {
        nsRange(string.rangeOfCharacter(from: searchSet, options: mask, range: bounds(rangeOfReceiverToSearch)))
    }

    public func hasPrefix(_ str: String) -> Bool { string.hasPrefix(str) }
    public func hasSuffix(_ str: String) -> Bool { string.hasSuffix(str) }
    public func contains(_ str: String) -> Bool { !str.isEmpty && string.range(of: str) != nil }
    public func localizedCaseInsensitiveContains(_ str: String) -> Bool { string.localizedCaseInsensitiveContains(str) }
    public func localizedStandardContains(_ str: String) -> Bool { string.localizedStandardContains(str) }

    // MARK: Comparing

    public func compare(_ string: String) -> ComparisonResult { self.string.compare(string) }
    public func compare(_ string: String, options mask: CompareOptions = []) -> ComparisonResult { self.string.compare(string, options: mask) }
    public func compare(_ string: String, options mask: CompareOptions = [], range rangeOfReceiverToCompare: NSRange) -> ComparisonResult {
        self.string.compare(string, options: mask, range: bounds(rangeOfReceiverToCompare))
    }
    public func caseInsensitiveCompare(_ string: String) -> ComparisonResult { self.string.caseInsensitiveCompare(string) }
    public func localizedCompare(_ string: String) -> ComparisonResult { self.string.localizedCompare(string) }
    public func localizedCaseInsensitiveCompare(_ string: String) -> ComparisonResult { self.string.localizedCaseInsensitiveCompare(string) }
    public func localizedStandardCompare(_ string: String) -> ComparisonResult { self.string.localizedStandardCompare(string) }

    // MARK: Pieces and changed copies

    public func components(separatedBy separator: String) -> [String] {
        guard !separator.isEmpty else { return [string] }
        var pieces: [String] = []
        var rest = string[...]
        while let found = rest.range(of: separator) {
            pieces.append(String(rest[..<found.lowerBound]))
            rest = rest[found.upperBound...]
        }
        pieces.append(String(rest))
        return pieces
    }

    public func components(separatedBy separator: CharacterSet) -> [String] { string.components(separatedBy: separator) }
    public func trimmingCharacters(in set: CharacterSet) -> String { string.trimmingCharacters(in: set) }
    public func appending(_ aString: String) -> String { string + aString }

    public func replacingOccurrences(of target: String, with replacement: String, options: CompareOptions = [], range searchRange: NSRange) -> String {
        string.replacingOccurrences(of: target, with: replacement, options: options, range: bounds(searchRange))
    }

    /// The string cut or padded to `newLength` UTF-16 units, the padding taken from `padString`
    /// from `padIndex` on, round again as often as it takes.
    public func padding(toLength newLength: Int, withPad padString: String, startingAt padIndex: Int) -> String {
        var units = Array(string.utf16)
        if newLength <= units.count { return String(decoding: units[..<max(newLength, 0)], as: UTF16.self) }
        let pad = Array(padString.utf16)
        guard !pad.isEmpty else { return string }
        var index = padIndex % pad.count
        while units.count < newLength {
            units.append(pad[index])
            index = (index + 1) % pad.count
        }
        return String(decoding: units, as: UTF16.self)
    }

    public var capitalized: String { string.localizedCapitalized }
    public var localizedCapitalized: String { string.localizedCapitalized }
    public var localizedLowercase: String { string.lowercased() }
    public var localizedUppercase: String { string.uppercased() }

    // MARK: Lines and paragraphs

    /// The whole lines `range` touches, with the terminator of the last (a line ends at a line
    /// feed, a carriage return or the pair, NEL, the line separator or the paragraph separator).
    public func lineRange(for range: NSRange) -> NSRange { enclosing(range, breaks: [0x0A, 0x0D, 0x85, 0x2028, 0x2029]) }

    /// The whole paragraphs `range` touches, with the terminator of the last (as lines, but a
    /// line separator does not end a paragraph).
    public func paragraphRange(for range: NSRange) -> NSRange { enclosing(range, breaks: [0x0A, 0x0D, 0x85, 0x2029]) }

    public func getLineStart(_ startPtr: UnsafeMutablePointer<Int>?, end lineEndPtr: UnsafeMutablePointer<Int>?,
                             contentsEnd contentsEndPtr: UnsafeMutablePointer<Int>?, for range: NSRange) {
        let line = lineRange(for: range)
        startPtr?.pointee = line.location
        lineEndPtr?.pointee = NSMaxRange(line)
        contentsEndPtr?.pointee = contentsEnd(of: line, breaks: [0x0A, 0x0D, 0x85, 0x2028, 0x2029])
    }

    public func getParagraphStart(_ startPtr: UnsafeMutablePointer<Int>?, end parEndPtr: UnsafeMutablePointer<Int>?,
                                  contentsEnd contentsEndPtr: UnsafeMutablePointer<Int>?, for range: NSRange) {
        let paragraph = paragraphRange(for: range)
        startPtr?.pointee = paragraph.location
        parEndPtr?.pointee = NSMaxRange(paragraph)
        contentsEndPtr?.pointee = contentsEnd(of: paragraph, breaks: [0x0A, 0x0D, 0x85, 0x2029])
    }

    private func enclosing(_ range: NSRange, breaks: Set<UInt16>) -> NSRange {
        let units = Array(string.utf16)
        var start = min(max(range.location, 0), units.count)
        while start > 0, !breaks.contains(units[start - 1]) { start -= 1 }
        var index = max(start, min(range.length > 0 ? NSMaxRange(range) - 1 : range.location, units.count))
        while index < units.count, !breaks.contains(units[index]) { index += 1 }
        var end = min(index + 1, units.count)
        if index < units.count, units[index] == 0x0D, end < units.count, units[end] == 0x0A { end += 1 }
        return NSRange(location: start, length: end - start)
    }

    /// Where the range's text ends without its terminator.
    private func contentsEnd(of range: NSRange, breaks: Set<UInt16>) -> Int {
        let units = Array(string.utf16)
        var end = NSMaxRange(range)
        while end > range.location, breaks.contains(units[end - 1]) { end -= 1 }
        return end
    }

    // MARK: Paths

    /// The path with repeated slashes made one and the trailing slash dropped (but "/" kept).
    private static func tidy(_ path: String) -> String {
        var result = ""
        for character in path where !(character == "/" && result.hasSuffix("/")) { result.append(character) }
        if result.count > 1, result.hasSuffix("/") { result.removeLast() }
        return result
    }

    public var isAbsolutePath: Bool { string.hasPrefix("/") || string.hasPrefix("~") }

    /// The path's components; an absolute path's first is "/".
    public var pathComponents: [String] {
        let path = Self.tidy(string)
        guard !path.isEmpty else { return [] }
        let names = path.split(separator: "/").map(String.init)
        return path.hasPrefix("/") ? ["/"] + names : names
    }

    public func appendingPathComponent(_ str: String) -> String {
        guard !string.isEmpty else { return Self.tidy(str) }
        guard !str.isEmpty else { return Self.tidy(string) }
        return Self.tidy(string + "/" + str)
    }

    /// The path with `ext` after a "." on its last component, nil for an empty path, the root,
    /// or an extension holding a slash.
    public func appendingPathExtension(_ ext: String) -> String? {
        let path = Self.tidy(string)
        guard !path.isEmpty, path != "/", !ext.contains(Character("/")) else { return nil }
        return ext.isEmpty ? path : path + "." + ext
    }

    public var deletingLastPathComponent: String {
        let path = Self.tidy(string)
        guard path != "/" else { return path }
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return slash == path.startIndex ? "/" : String(path[..<slash])
    }

    public var deletingPathExtension: String {
        let path = Self.tidy(string)
        let nameStart = path.lastIndex(of: "/").map { path.index(after: $0) } ?? path.startIndex
        guard let dot = path[nameStart...].lastIndex(of: "."), dot > nameStart else { return path }
        return String(path[..<dot])
    }

    public func strings(byAppendingPaths paths: [String]) -> [String] { paths.map { appendingPathComponent($0) } }

    public static func path(withComponents components: [String]) -> String {
        guard let first = components.first else { return "" }
        return components.dropFirst().reduce(NSString(string: first)) { NSString(string: $0.appendingPathComponent($1)) }.string
    }

    /// "~" at the start stands for the home directory ("/" on the web).
    public var expandingTildeInPath: String {
        guard string == "~" || string.hasPrefix("~/") else { return string }
        return NSString(string: NSHomeDirectory()).appendingPathComponent(String(string.dropFirst()))
    }

    public var abbreviatingWithTildeInPath: String {
        let home = Self.tidy(NSHomeDirectory())
        guard home != "/" else { return string }
        if string == home { return "~" }
        return string.hasPrefix(home + "/") ? "~" + string.dropFirst(home.count) : string
    }

    /// The tilde expanded, "." components dropped, and ".." taking off the component before it
    /// in an absolute path.
    public var standardizingPath: String {
        let expanded = expandingTildeInPath
        let absolute = expanded.hasPrefix("/")
        var names: [String] = []
        for name in Self.tidy(expanded).split(separator: "/").map(String.init) where name != "." {
            if name == "..", absolute { if !names.isEmpty { names.removeLast() } } else { names.append(name) }
        }
        let joined = names.joined(separator: "/")
        return absolute ? "/" + joined : joined
    }

    public var resolvingSymlinksInPath: String { standardizingPath }
}

/// The user's home directory ("/" on the web, which has no user folders).
public func NSHomeDirectory() -> String { FileManager.default.homeDirectoryForCurrentUser.path }
#endif
