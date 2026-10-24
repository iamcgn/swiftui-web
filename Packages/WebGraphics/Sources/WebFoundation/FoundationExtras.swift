// Foundation members apps reach for that FoundationEssentials lacks on wasm (decision 0021,
// the Ember app): `JSONSerialization` over the JSON parser and writer the coders use,
// `trimmingCharacters(in:)` over the `CharacterSet` stand-in, the byte-count format style
// (`.byteCount(style:)`, as ICU's en_US: "1.2 MB", "Zero KB"), the compact-name notation on
// integers ("1.2K", "3.4M", as ICU's short compact form), and a file URL's resource values
// (size, modification date, directory) from the in-memory file system.
#if os(WASI)

// MARK: - The keychain's host

/// What a host provides the Security module's keychain (Packages/Shadows): durable storage
/// for items, keyed by the item's identity — `load(key)`, `save(key, value)` (nil removes).
public enum _SecurityHost {
    nonisolated(unsafe) public static var store: (load: (String) -> String?, save: (String, String?) -> Void)?
}

// MARK: - JSONSerialization

/// An object that converts between JSON and the equivalent Foundation objects: arrays,
/// dictionaries keyed by strings, strings, numbers, booleans and `NSNull`.
public final class JSONSerialization {
    public struct ReadingOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let mutableContainers = ReadingOptions(rawValue: 1 << 0)
        public static let mutableLeaves = ReadingOptions(rawValue: 1 << 1)
        public static let fragmentsAllowed = ReadingOptions(rawValue: 1 << 2)
        public static let json5Allowed = ReadingOptions(rawValue: 1 << 3)
        public static let topLevelDictionaryAssumed = ReadingOptions(rawValue: 1 << 4)
    }

    public struct WritingOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let prettyPrinted = WritingOptions(rawValue: 1 << 0)
        public static let sortedKeys = WritingOptions(rawValue: 1 << 1)
        public static let fragmentsAllowed = WritingOptions(rawValue: 1 << 2)
        public static let withoutEscapingSlashes = WritingOptions(rawValue: 1 << 3)
    }

    public struct _Error: Error, CustomStringConvertible {
        public let description: String
    }

    /// Whether the object can be written: containers of strings, numbers, booleans and null.
    public class func isValidJSONObject(_ obj: Any) -> Bool {
        (try? node(from: obj, top: true)) != nil
    }

    /// Returns JSON data from a Foundation object.
    public class func data(withJSONObject obj: Any, options opt: WritingOptions = []) throws -> Data {
        let root = try node(from: obj, top: !opt.contains(.fragmentsAllowed))
        var text = ""
        try _JSONWriter.write(opt.contains(.sortedKeys) ? sorted(root) : root, into: &text)
        return Data(text.utf8)
    }

    /// Returns a Foundation object from the JSON data.
    public class func jsonObject(with data: Data, options opt: ReadingOptions = []) throws -> Any {
        var parser = _JSONParser(bytes: Array(data))
        let root = try parser.parseDocument()
        switch root {
        case .array, .object: break
        default: if !opt.contains(.fragmentsAllowed) { throw _Error(description: "JSON text did not start with array or object and option to allow fragments not set.") }
        }
        return value(from: root)
    }

    private static func node(from object: Any, top: Bool) throws -> _JSONNode {
        switch object {
        case let array as [Any]: return .array(_JSONArrayBox(try array.map { try node(from: $0, top: false) }))
        case let dictionary as [String: Any]:
            return .object(_JSONObjectBox(try dictionary.map { ($0.key, try node(from: $0.value, top: false)) }))
        case _ where top: throw _Error(description: "Top-level object is not an array or dictionary.")
        case let string as String: return .string(string)
        case let flag as Bool: return .bool(flag)
        case let integer as Int: return .integer(Int64(integer))
        case let integer as Int64: return .integer(integer)
        case let integer as UInt: return .integer(Int64(integer))
        case let number as Double: return try _JSONWriter.number(number, codingPath: [])
        case let number as Float: return try _JSONWriter.number(Double(number), codingPath: [])
        case is NSNull: return .null
        case Optional<Any>.none: return .null
        default: throw _Error(description: "Invalid type in JSON write (\(type(of: object)))")
        }
    }

    private static func sorted(_ node: _JSONNode) -> _JSONNode {
        switch node {
        case .array(let box): return .array(_JSONArrayBox(box.items.map(sorted)))
        case .object(let box): return .object(_JSONObjectBox(box.entries.map { ($0.key, sorted($0.value)) }.sorted { $0.0 < $1.0 }))
        default: return node
        }
    }

    private static func value(from node: _JSONNode) -> Any {
        switch node.resolved {
        case .null: return NSNull()
        case .bool(let flag): return flag
        case .integer(let integer): return Int(integer)
        case .number(let number): return number
        case .string(let string): return string
        case .array(let box): return box.items.map(value(from:))
        case .object(let box): return Dictionary(box.entries.map { ($0.key, value(from: $0.value)) }, uniquingKeysWith: { _, last in last })
        case .deferred: return NSNull()
        }
    }
}

/// A singleton object used to represent null values in collection objects that don’t allow nil.
public final class NSNull: Hashable, CustomStringConvertible, @unchecked Sendable {
    public init() {}
    public static func == (lhs: NSNull, rhs: NSNull) -> Bool { true }
    public func hash(into hasher: inout Hasher) {}
    public var description: String { "<null>" }
}

// MARK: - Trimming

extension StringProtocol {
    /// The string without the leading and trailing scalars in the set.
    public func trimmingCharacters(in set: CharacterSet) -> String {
        var scalars = Substring(self).unicodeScalars
        while let first = scalars.first, set.contains(first) { scalars.removeFirst() }
        while let last = scalars.last, set.contains(last) { scalars.removeLast() }
        return String(scalars)
    }
}

// MARK: - Byte counts

/// A format style that converts between byte counts and their textual representations.
public struct ByteCountFormatStyle: FormatStyle, Hashable, Sendable {
    public enum Style: Int, Sendable { case file = 0, memory, decimal, binary }
    public struct Units: OptionSet, Hashable, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let bytes = Units(rawValue: 1 << 0)
        public static let kb = Units(rawValue: 1 << 1)
        public static let mb = Units(rawValue: 1 << 2)
        public static let gb = Units(rawValue: 1 << 3)
        public static let tb = Units(rawValue: 1 << 4)
        public static let pb = Units(rawValue: 1 << 5)
        public static let all = Units(rawValue: 0x3F)
        public static let `default` = Units.all
    }

    public var style: Style
    public var allowedUnits: Units
    public var spellsOutZero: Bool
    public var includesActualByteCount: Bool

    public init(style: Style = .file, allowedUnits: Units = .all, spellsOutZero: Bool = true, includesActualByteCount: Bool = false, locale: Locale = .current) {
        self.style = style
        self.allowedUnits = allowedUnits
        self.spellsOutZero = spellsOutZero
        self.includesActualByteCount = includesActualByteCount
    }

    public func format(_ value: Int64) -> String {
        if value == 0 && spellsOutZero { return "Zero KB" }
        let base: Double = style == .binary || style == .memory ? 1024 : 1000
        let names = ["bytes", "KB", "MB", "GB", "TB", "PB"]
        let magnitude = Double(abs(value))
        var unit = 0
        var amount = magnitude
        while amount >= base && unit < names.count - 1 && allowedUnits.contains(Units(rawValue: 1 << UInt(unit + 1))) {
            amount /= base
            unit += 1
        }
        let text: String
        if unit == 0 { text = "\(value) \(abs(value) == 1 ? "byte" : "bytes")" }
        else {
            // ICU's file style: no fraction under the KB, one digit otherwise, trailing zero dropped.
            var formatting = _NumberFormatting()
            formatting.maximumFractionDigits = unit == 1 && style == .file ? 0 : (amount < 10 ? 2 : amount < 100 ? 1 : 0)
            text = (value < 0 ? "-" : "") + formatting.format(amount) + " " + names[unit]
        }
        return includesActualByteCount && unit > 0 ? "\(text) (\(_NumberFormatting().format(Double(value))) bytes)" : text
    }
}

extension FormatStyle where Self == ByteCountFormatStyle {
    public static func byteCount(style: ByteCountFormatStyle.Style, allowedUnits: ByteCountFormatStyle.Units = .all, spellsOutZero: Bool = true, includesActualByteCount: Bool = false) -> ByteCountFormatStyle {
        ByteCountFormatStyle(style: style, allowedUnits: allowedUnits, spellsOutZero: spellsOutZero, includesActualByteCount: includesActualByteCount)
    }
}

extension BinaryInteger {
    /// The integer formatted as a byte count.
    public func formatted(_ style: ByteCountFormatStyle) -> String { style.format(Int64(self)) }
}

// MARK: - Compact notation

extension NumberFormatStyleConfiguration {
    /// How large numbers are written.
    public struct Notation: Hashable, Sendable {
        package enum Kind: Hashable, Sendable { case automatic, compactName, scientific }
        package let kind: Kind
        public static let automatic = Notation(kind: .automatic)
        public static let compactName = Notation(kind: .compactName)
        public static let scientific = Notation(kind: .scientific)
    }
}

extension _NumberFormatting {
    /// The number in ICU's short compact form: 1200 → "1.2K", 3_400_000 → "3.4M", 999 unchanged;
    /// two significant digits under ten of a unit, otherwise whole units.
    public func formatCompact(_ value: Double) -> String {
        let magnitude = abs(value)
        guard magnitude >= 1000 else { return format(value) }
        let units: [(Double, String)] = [(1e12, "T"), (1e9, "B"), (1e6, "M"), (1e3, "K")]
        for (scale, suffix) in units where magnitude >= scale {
            var scaled = magnitude / scale
            var formatting = _NumberFormatting()
            formatting.maximumFractionDigits = scaled < 10 ? 1 : 0
            formatting.usesGrouping = false
            var text = formatting.format(scaled)
            // Rounding up to the next unit (999.6K → "1M").
            if let rounded = Double(text), rounded >= 1000, let next = units.first(where: { $0.0 == scale * 1000 }) {
                scaled = rounded / 1000
                text = formatting.format(scaled)
                return (value < 0 ? "-" : "") + text + next.1
            }
            return (value < 0 ? "-" : "") + text + suffix
        }
        return format(value)
    }
}

extension IntegerFormatStyle {
    public func notation(_ notation: NumberFormatStyleConfiguration.Notation) -> _CompactIntegerFormatStyle<Value> {
        _CompactIntegerFormatStyle(core: core, notation: notation)
    }
}

/// An integer style with a notation chosen (`.number.notation(.compactName)`).
public struct _CompactIntegerFormatStyle<Value: BinaryInteger>: FormatStyle, Hashable, Sendable {
    public var core: _NumberFormatting
    public var notation: NumberFormatStyleConfiguration.Notation
    public func format(_ value: Value) -> String {
        switch notation.kind {
        case .compactName: return core.formatCompact(Double(value))
        case .scientific:
            let magnitude = Double(value)
            guard magnitude != 0 else { return "0E0" }
            let exponent = Int(magnitude.magnitude.log10().rounded(.down))
            var formatting = core
            formatting.maximumFractionDigits = 3
            formatting.usesGrouping = false
            return formatting.format(magnitude / Double(exponent).pow10) + "E" + String(exponent)
        case .automatic: return core.format(value)
        }
    }
    public func precision(_ precision: NumberFormatStyleConfiguration.Precision) -> Self { var copy = self; copy.core = core.precision(precision); return copy }
    public func grouping(_ grouping: NumberFormatStyleConfiguration.Grouping) -> Self { var copy = self; copy.core = core.grouping(grouping); return copy }
}

extension Double {
    fileprivate func log10() -> Double {
        var value = self, count = 0.0
        while value >= 10 { value /= 10; count += 1 }
        while value < 1 && value > 0 { value *= 10; count -= 1 }
        return count
    }
    fileprivate var pow10: Double {
        var result = 1.0
        if self >= 0 { for _ in 0..<Int(self) { result *= 10 } } else { for _ in 0..<Int(-self) { result /= 10 } }
        return result
    }
}

// MARK: - Resource values

/// The properties of a file system resource.
public struct URLResourceValues: Sendable {
    public var fileSize: Int?
    public var contentModificationDate: Date?
    public var creationDate: Date?
    public var isDirectory: Bool?
    public var isRegularFile: Bool?
    public var name: String?
    public var allValues: [URLResourceKey: Any] {
        var values: [URLResourceKey: Any] = [:]
        if let fileSize { values[.fileSizeKey] = fileSize }
        if let contentModificationDate { values[.contentModificationDateKey] = contentModificationDate }
        if let isDirectory { values[.isDirectoryKey] = isDirectory }
        return values
    }
    public init() {}
}

extension URL {
    /// The resource values of a file URL from the in-memory file system; a missing file throws.
    public func resourceValues(forKeys keys: Set<URLResourceKey>) throws -> URLResourceValues {
        var values = URLResourceValues()
        values.name = lastPathComponent
        if _MemoryFiles.isDirectory(self) {
            values.isDirectory = true
            values.isRegularFile = false
            return values
        }
        guard let data = _MemoryFiles.read(self) else { throw FileManager._FileError.noSuchFile(self) }
        values.isDirectory = false
        values.isRegularFile = true
        values.fileSize = data.count
        values.contentModificationDate = _MemoryFiles.modificationDate(self)
        values.creationDate = values.contentModificationDate
        return values
    }
}

#endif
