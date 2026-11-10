// Property lists on wasm, where FoundationEssentials' `PropertyListEncoder` would bring its
// scanner and CF-style writers into the bundle: `PropertyListSerialization` reads and writes the
// XML and binary (`bplist00`) formats Apple's does, and reads none of the old OpenStep text
// form; `PropertyListEncoder` and `PropertyListDecoder` carry `Codable` values through the
// project's coder (JSONCoder.swift), with dates and data as the plist's own `<date>` and
// `<data>`. A value reads back as Swift's own types: `String`, `Int`, `Double`, `Bool`, `Date`,
// `Data`, `[Any]` and `[String: Any]`.
#if os(WASI)

/// Converts between property lists and their XML or binary representation.
open class PropertyListSerialization {
    /// Whether the containers read back are mutable: every value read here is a Swift value, so
    /// the options only exist for the calls that pass them.
    public struct MutabilityOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let mutableContainers = MutabilityOptions(rawValue: 1)
        public static let mutableContainersAndLeaves = MutabilityOptions(rawValue: 2)
    }
    public typealias ReadOptions = MutabilityOptions
    public typealias WriteOptions = Int

    /// A property list's representation, with Apple's raw values.
    public enum PropertyListFormat: UInt, Sendable {
        case openStep = 1
        case xml = 100
        case binary = 200
    }

    /// Whether the object is a property list the format can write: dictionaries keyed by
    /// strings, arrays, strings, numbers, booleans, dates and data. Nothing writes OpenStep.
    open class func propertyList(_ plist: Any, isValidFor format: PropertyListFormat) -> Bool {
        format != .openStep && (try? _PlistValue(plist)) != nil
    }

    /// The property list written in the format.
    open class func data(fromPropertyList plist: Any, format: PropertyListFormat, options opt: WriteOptions) throws -> Data {
        let value = try _PlistValue(plist)
        switch format {
        case .xml: return Data(_PlistXML.write(value).utf8)
        case .binary: return Data(_PlistBinary.write(value))
        case .openStep: throw _plistError(3851, "The OpenStep format is unsupported for writing")
        }
    }

    /// The property list the data holds, in the format it was written in.
    open class func propertyList(from data: Data, options opt: ReadOptions = [], format: UnsafeMutablePointer<PropertyListFormat>?) throws -> Any {
        let (value, found) = try _PlistValue.read(Array(data))
        format?.pointee = found
        return value.object
    }
}

/// An error in NSCocoaErrorDomain with a property-list code (3840 corrupt input, 3851 a value
/// the format can't write).
func _plistError(_ code: Int, _ message: String) -> NSError {
    NSError(domain: NSCocoaErrorDomain, code: code, userInfo: [NSDebugDescriptionErrorKey: message])
}

/// Encodes `Codable` values as property lists.
open class PropertyListEncoder: @unchecked Sendable {
    /// The format written: binary, as Apple's encoder writes by default.
    open var outputFormat: PropertyListSerialization.PropertyListFormat = .binary
    open var userInfo: [CodingUserInfoKey: Any] = [:]

    public init() {}

    open func encode<Value: Encodable>(_ value: Value) throws -> Data {
        var options = _JSONEncodingOptions()
        options.dateStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(_PlistValue.dateMark + String(date.timeIntervalSinceReferenceDate))
        }
        options.dataStrategy = .custom { data, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(_PlistValue.dataMark + data.base64EncodedString())
        }
        options.urlsAsStrings = true
        options.userInfo = userInfo
        let node = try options.node(for: value, codingPath: []).resolved
        return try PropertyListSerialization.data(fromPropertyList: _PlistValue(node: node).object, format: outputFormat, options: 0)
    }
}

/// Decodes `Codable` values from property lists, in either format.
open class PropertyListDecoder: @unchecked Sendable {
    open var userInfo: [CodingUserInfoKey: Any] = [:]

    public init() {}

    open func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        var format = PropertyListSerialization.PropertyListFormat.binary
        return try decode(type, from: data, format: &format)
    }

    open func decode<T: Decodable>(_ type: T.Type, from data: Data, format: inout PropertyListSerialization.PropertyListFormat) throws -> T {
        let value: _PlistValue
        do {
            let read = try _PlistValue.read(Array(data))
            value = read.0
            format = read.1
        } catch {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "The given data was not a valid property list.", underlyingError: error))
        }
        var options = _JSONDecodingOptions()
        options.dateStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard text.hasPrefix(_PlistValue.dateMark), let seconds = Double(text.dropFirst(_PlistValue.dateMark.count)) else {
                throw DecodingError.typeMismatch(Date.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected a date"))
            }
            return Date(timeIntervalSinceReferenceDate: seconds)
        }
        options.dataStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard text.hasPrefix(_PlistValue.dataMark), let data = Data(base64Encoded: String(text.dropFirst(_PlistValue.dataMark.count))) else {
                throw DecodingError.typeMismatch(Data.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected data"))
            }
            return data
        }
        options.userInfo = userInfo
        let node = value.node
        if let special = try _JSONDecoding.special(type, from: node, codingPath: [], options: options) { return special }
        return try T(from: _JSONDecoding(node: node, codingPath: [], options: options))
    }
}

// MARK: - Values

/// A property-list value.
indirect enum _PlistValue {
    case string(String)
    case integer(Int64)
    case unsigned(UInt64)
    case real(Double)
    case bool(Bool)
    case date(Date)
    case data([UInt8])
    case array([_PlistValue])
    case dictionary([(key: String, value: _PlistValue)])

    /// How the coders carry a date or data through the JSON nodes, as a string no app writes.
    static let dateMark = "\u{0}\u{1}plist-date:"
    static let dataMark = "\u{0}\u{1}plist-data:"
    /// What a `nil` encodes as, as Apple's encoder writes it.
    static let null = "$null"

    /// The value of an object, or an error naming the first thing a property list can't hold.
    init(_ object: Any) throws {
        switch object {
        case let value as _PlistValue: self = value
        case let string as String: self = .string(string)
        case let string as Substring: self = .string(String(string))
        case let flag as Bool: self = .bool(flag)
        case let number as NSNumber:
            switch number.objCType.pointee {
            case 0x63: self = .bool(number.boolValue)
            case 0x64: self = .real(number.doubleValue)
            case 0x51: self = .unsigned(number.uint64Value)
            default: self = .integer(number.int64Value)
            }
        case let integer as Int: self = .integer(Int64(integer))
        case let integer as Int8: self = .integer(Int64(integer))
        case let integer as Int16: self = .integer(Int64(integer))
        case let integer as Int32: self = .integer(Int64(integer))
        case let integer as Int64: self = .integer(integer)
        case let integer as UInt: self = .unsigned(UInt64(integer))
        case let integer as UInt8: self = .integer(Int64(integer))
        case let integer as UInt16: self = .integer(Int64(integer))
        case let integer as UInt32: self = .integer(Int64(integer))
        case let integer as UInt64: self = .unsigned(integer)
        case let number as Double: self = .real(number)
        case let number as Float: self = .real(Double(number))
        case let date as Date: self = .date(date)
        case let data as Data: self = .data(Array(data))
        case let bytes as [UInt8]: self = .data(bytes)
        case let dictionary as [String: Any]: self = .dictionary(try dictionary.map { ($0.key, try _PlistValue($0.value)) })
        case let dictionary as [AnyHashable: Any]:
            self = .dictionary(try dictionary.map { entry in
                guard let key = entry.key.base as? String else { throw _plistError(3851, "Property list dictionary keys must be strings") }
                return (key, try _PlistValue(entry.value))
            })
        case let array as [Any]: self = .array(try array.map(_PlistValue.init))
        default: throw _plistError(3851, "Property list invalid for format (\(type(of: object)))")
        }
    }

    /// The value as the objects `PropertyListSerialization` hands back.
    var object: Any {
        switch self {
        case .string(let string): return string
        case .integer(let integer): return Int(exactly: integer).map { $0 as Any } ?? integer
        case .unsigned(let integer): return Int(exactly: integer).map { $0 as Any } ?? integer
        case .real(let number): return number
        case .bool(let flag): return flag
        case .date(let date): return date
        case .data(let bytes): return Data(bytes)
        case .array(let items): return items.map(\.object)
        case .dictionary(let entries): return Dictionary(entries.map { ($0.key, $0.value.object) }, uniquingKeysWith: { _, last in last })
        }
    }

    /// The value of an encoded node, with the coders' marked strings as dates and data and a
    /// `nil` as "$null".
    init(node: _JSONNode) throws {
        switch node {
        case .null: self = .string(Self.null)
        case .bool(let flag): self = .bool(flag)
        case .integer(let integer): self = .integer(integer)
        case .number(let number): self = .real(number)
        case .string(let text):
            if text.hasPrefix(Self.dateMark), let seconds = Double(text.dropFirst(Self.dateMark.count)) {
                self = .date(Date(timeIntervalSinceReferenceDate: seconds))
            } else if text.hasPrefix(Self.dataMark), let data = Data(base64Encoded: String(text.dropFirst(Self.dataMark.count))) {
                self = .data(Array(data))
            } else {
                self = .string(text)
            }
        case .array(let box): self = .array(try box.items.map(_PlistValue.init(node:)))
        case .object(let box): self = .dictionary(try box.entries.map { ($0.key, try _PlistValue(node: $0.value)) })
        case .deferred(let box): self = try _PlistValue(node: box.node ?? .null)
        }
    }

    /// The node the decoder reads: dates and data as the marked strings its strategies take,
    /// and "$null" as `nil`.
    var node: _JSONNode {
        switch self {
        case .string(let text): return text == Self.null ? .null : .string(text)
        case .integer(let integer): return .integer(integer)
        case .unsigned(let integer): return Int64(exactly: integer).map(_JSONNode.integer) ?? .number(Double(integer))
        case .real(let number): return .number(number)
        case .bool(let flag): return .bool(flag)
        case .date(let date): return .string(Self.dateMark + String(date.timeIntervalSinceReferenceDate))
        case .data(let bytes): return .string(Self.dataMark + Data(bytes).base64EncodedString())
        case .array(let items): return .array(_JSONArrayBox(items.map(\.node)))
        case .dictionary(let entries): return .object(_JSONObjectBox(entries.map { ($0.key, $0.value.node) }))
        }
    }

    /// The value the bytes hold, and the format they hold it in.
    static func read(_ bytes: [UInt8]) throws -> (_PlistValue, PropertyListSerialization.PropertyListFormat) {
        if bytes.starts(with: Array("bplist00".utf8)) { return (try _PlistBinary.read(bytes), .binary) }
        var start = 0
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { start = 3 }
        guard let text = String(validating: bytes[start...], as: UTF8.self) else { throw _plistError(3840, "The data couldn't be read because it isn't UTF-8 or binary") }
        guard text.drop(while: \.isWhitespace).first == "<" else {
            throw _plistError(3840, "Old-style (OpenStep) property lists are unsupported")
        }
        var parser = _PlistXML(text)
        return (try parser.document(), .xml)
    }
}

// MARK: - XML

struct _PlistXML {
    private let scalars: [Unicode.Scalar]
    private var index = 0

    init(_ text: String) { scalars = Array(text.unicodeScalars) }

    // MARK: Writing

    static func write(_ value: _PlistValue) -> String {
        var text = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">

        """
        write(value, depth: 0, into: &text)
        text += "</plist>\n"
        return text
    }

    private static func write(_ value: _PlistValue, depth: Int, into text: inout String) {
        let indent = String(repeating: "\t", count: depth)
        switch value {
        case .string(let string): text += "\(indent)<string>\(escaped(string))</string>\n"
        case .integer(let integer): text += "\(indent)<integer>\(integer)</integer>\n"
        case .unsigned(let integer): text += "\(indent)<integer>\(integer)</integer>\n"
        case .real(let number): text += "\(indent)<real>\(real(number))</real>\n"
        case .bool(let flag): text += "\(indent)<\(flag ? "true" : "false")/>\n"
        case .date(let date): text += "\(indent)<date>\(_formatISO8601(date))</date>\n"
        case .data(let bytes):
            let base64 = Data(bytes).base64EncodedString()
            text += "\(indent)<data>\n"
            var line = base64[...]
            while !line.isEmpty {
                text += "\(indent)\(line.prefix(68))\n"
                line = line.dropFirst(68)
            }
            text += "\(indent)</data>\n"
        case .array(let items):
            guard !items.isEmpty else { text += "\(indent)<array/>\n"; return }
            text += "\(indent)<array>\n"
            for item in items { write(item, depth: depth + 1, into: &text) }
            text += "\(indent)</array>\n"
        case .dictionary(let entries):
            guard !entries.isEmpty else { text += "\(indent)<dict/>\n"; return }
            text += "\(indent)<dict>\n"
            for entry in entries.sorted(by: { $0.key < $1.key }) {
                text += "\(indent)\t<key>\(escaped(entry.key))</key>\n"
                write(entry.value, depth: depth + 1, into: &text)
            }
            text += "\(indent)</dict>\n"
        }
    }

    /// A real as CF writes one: the shortest digits, a whole number without ".0".
    private static func real(_ number: Double) -> String {
        if number.isNaN { return "nan" }
        if number.isInfinite { return number > 0 ? "+infinity" : "-infinity" }
        let text = "\(number)"
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    private static func escaped(_ text: String) -> String {
        var out = ""
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default: out.append(character)
            }
        }
        return out
    }

    // MARK: Reading

    /// The one value inside `<plist>`.
    mutating func document() throws -> _PlistValue {
        while true {
            skipSpace()
            guard index < scalars.count else { throw corrupt("Unexpected end of the property list") }
            if starts("<?") { try skip(past: "?>") } else if starts("<!--") { try skip(past: "-->") } else if starts("<!") { try skip(past: ">") } else { break }
        }
        let open = try tag()
        if open.name == "plist" {
            if open.empty { throw corrupt("Encountered empty plist tag") }
            let value = try element(try nextTag())
            let close = try nextTag()
            guard close.closing, close.name == "plist" else { throw corrupt("Expected </plist>") }
            return value
        }
        return try element(open)
    }

    private struct Tag {
        var name: String
        var closing = false
        var empty = false
    }

    private mutating func element(_ open: Tag) throws -> _PlistValue {
        guard !open.closing else { throw corrupt("Unexpected </\(open.name)>") }
        switch open.name {
        case "true", "false":
            if !open.empty { try close(open.name) }
            return .bool(open.name == "true")
        case "dict":
            var entries: [(key: String, value: _PlistValue)] = []
            if open.empty { return .dictionary(entries) }
            while true {
                let next = try nextTag()
                if next.closing, next.name == "dict" { return .dictionary(entries) }
                guard next.name == "key", !next.closing else { throw corrupt("Expected a key in a dictionary, found <\(next.name)>") }
                let key = next.empty ? "" : try text(until: "key")
                entries.append((key, try element(try nextTag())))
            }
        case "array":
            var items: [_PlistValue] = []
            if open.empty { return .array(items) }
            while true {
                let next = try nextTag()
                if next.closing, next.name == "array" { return .array(items) }
                items.append(try element(next))
            }
        case "string", "integer", "real", "date", "data", "key":
            let content = open.empty ? "" : try text(until: open.name)
            switch open.name {
            case "string", "key": return .string(content)
            case "integer":
                let trimmed = content.filter { !$0.isWhitespace }
                if let integer = Int64(trimmed) { return .integer(integer) }
                if let integer = UInt64(trimmed) { return .unsigned(integer) }
                if trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X"), let integer = Int64(trimmed.dropFirst(2), radix: 16) { return .integer(integer) }
                throw corrupt("Encountered misformatted integer \(content)")
            case "real":
                let trimmed = content.filter { !$0.isWhitespace }.lowercased()
                switch trimmed {
                case "nan": return .real(.nan)
                case "+infinity", "infinity", "inf", "+inf": return .real(.infinity)
                case "-infinity", "-inf": return .real(-.infinity)
                default:
                    guard let number = Double(trimmed) else { throw corrupt("Encountered misformatted real \(content)") }
                    return .real(number)
                }
            case "date":
                guard let date = _parseISO8601(content.filter { !$0.isWhitespace }) else { throw corrupt("Could not interpret <date> \(content)") }
                return .date(date)
            default:
                guard let data = Data(base64Encoded: content.filter { !$0.isWhitespace }) else { throw corrupt("Could not interpret <data>") }
                return .data(Array(data))
            }
        default:
            throw corrupt("Encountered unknown tag \(open.name)")
        }
    }

    /// The next tag, past whitespace and comments.
    private mutating func nextTag() throws -> Tag {
        while true {
            skipSpace()
            guard index < scalars.count else { throw corrupt("Unexpected end of the property list") }
            if starts("<!--") { try skip(past: "-->"); continue }
            return try tag()
        }
    }

    private mutating func tag() throws -> Tag {
        guard index < scalars.count, scalars[index] == "<" else { throw corrupt("Expected a tag") }
        index += 1
        var tag = Tag(name: "")
        if index < scalars.count, scalars[index] == "/" { tag.closing = true; index += 1 }
        var name = String.UnicodeScalarView()
        while index < scalars.count, scalars[index] != ">", scalars[index] != "/", !scalars[index].properties.isWhitespace {
            name.append(scalars[index]); index += 1
        }
        tag.name = String(name)
        // Attributes (`version="1.0"`) are skipped.
        while index < scalars.count, scalars[index] != ">" {
            if scalars[index] == "/" { tag.empty = true }
            index += 1
        }
        guard index < scalars.count else { throw corrupt("Unterminated tag <\(tag.name)") }
        index += 1
        return tag
    }

    private mutating func close(_ name: String) throws {
        let tag = try nextTag()
        guard tag.closing, tag.name == name else { throw corrupt("Expected </\(name)>") }
    }

    /// The text up to `</name>`, with entities and CDATA resolved.
    private mutating func text(until name: String) throws -> String {
        var out = String.UnicodeScalarView()
        while index < scalars.count {
            if starts("<![CDATA[") {
                index += 9
                while index < scalars.count, !starts("]]>") { out.append(scalars[index]); index += 1 }
                index += 3
            } else if starts("<!--") {
                try skip(past: "-->")
            } else if scalars[index] == "<" {
                try close(name)
                return String(out)
            } else if scalars[index] == "&" {
                guard let end = scalars[index...].firstIndex(of: ";") else { throw corrupt("Unterminated entity") }
                let entity = String(String.UnicodeScalarView(scalars[(index + 1)..<end]))
                switch entity {
                case "amp": out.append("&")
                case "lt": out.append("<")
                case "gt": out.append(">")
                case "quot": out.append("\"")
                case "apos": out.append("'")
                default:
                    let code = entity.hasPrefix("#x") ? UInt32(entity.dropFirst(2), radix: 16) : entity.hasPrefix("#") ? UInt32(entity.dropFirst()) : nil
                    guard let code, let scalar = Unicode.Scalar(code) else { throw corrupt("Encountered unknown entity &\(entity);") }
                    out.append(scalar)
                }
                index = end + 1
            } else {
                out.append(scalars[index]); index += 1
            }
        }
        throw corrupt("Unterminated <\(name)>")
    }

    private func starts(_ prefix: String) -> Bool {
        var at = index
        for scalar in prefix.unicodeScalars {
            guard at < scalars.count, scalars[at] == scalar else { return false }
            at += 1
        }
        return true
    }

    private mutating func skip(past end: String) throws {
        while index < scalars.count, !starts(end) { index += 1 }
        guard index < scalars.count else { throw corrupt("Unterminated markup") }
        index += end.unicodeScalars.count
    }

    private mutating func skipSpace() {
        while index < scalars.count, scalars[index].properties.isWhitespace { index += 1 }
    }

    private func corrupt(_ message: String) -> NSError { _plistError(3840, message) }
}

// MARK: - Binary

/// The `bplist00` format: the objects, a table of their offsets and a 32-byte trailer.
enum _PlistBinary {
    static func write(_ root: _PlistValue) -> [UInt8] {
        // Objects in the order they're numbered: each container before its contents.
        var objects: [_PlistValue] = []
        var references: [[Int]] = []
        func add(_ value: _PlistValue) -> Int {
            let number = objects.count
            objects.append(value)
            references.append([])
            switch value {
            case .array(let items):
                let children = items.map(add)
                references[number] = children
            case .dictionary(let entries):
                let sorted = entries.sorted { $0.key < $1.key }
                let keys = sorted.map { add(.string($0.key)) }
                let values = sorted.map { add($0.value) }
                references[number] = keys + values
            default: break
            }
            return number
        }
        _ = add(root)
        let referenceSize = byteCount(UInt64(objects.count))
        var out = Array("bplist00".utf8)
        var offsets: [Int] = []
        func append(_ value: UInt64, size: Int) {
            for shift in stride(from: (size - 1) * 8, through: 0, by: -8) { out.append(UInt8(truncatingIfNeeded: value >> UInt64(shift))) }
        }
        func writeInteger(_ value: UInt64, signed: Bool = false) {
            let size = signed && Int64(bitPattern: value) < 0 ? 8 : byteCount(value)
            let exponent: UInt8 = size == 1 ? 0 : size == 2 ? 1 : size <= 4 ? 2 : 3
            out.append(0x10 | exponent)
            append(value, size: 1 << Int(exponent))
        }
        func marker(_ type: UInt8, _ count: Int) {
            if count < 15 {
                out.append(type << 4 | UInt8(count))
            } else {
                out.append(type << 4 | 0x0F)
                writeInteger(UInt64(count))
            }
        }
        for (number, value) in objects.enumerated() {
            offsets.append(out.count)
            switch value {
            case .bool(let flag): out.append(flag ? 0x09 : 0x08)
            case .integer(let integer): writeInteger(UInt64(bitPattern: integer), signed: true)
            case .unsigned(let integer):
                if integer <= UInt64(Int64.max) {
                    writeInteger(integer)
                } else {
                    out.append(0x14)
                    append(0, size: 8)
                    append(integer, size: 8)
                }
            case .real(let number):
                out.append(0x23)
                append(number.bitPattern, size: 8)
            case .date(let date):
                out.append(0x33)
                append(date.timeIntervalSinceReferenceDate.bitPattern, size: 8)
            case .data(let bytes):
                marker(0x4, bytes.count)
                out += bytes
            case .string(let string):
                if string.utf8.allSatisfy({ $0 < 0x80 }) {
                    marker(0x5, string.utf8.count)
                    out += string.utf8
                } else {
                    let units = Array(string.utf16)
                    marker(0x6, units.count)
                    for unit in units { append(UInt64(unit), size: 2) }
                }
            case .array(let items):
                marker(0xA, items.count)
                for reference in references[number] { append(UInt64(reference), size: referenceSize) }
            case .dictionary(let entries):
                marker(0xD, entries.count)
                for reference in references[number] { append(UInt64(reference), size: referenceSize) }
            }
        }
        let tableOffset = out.count
        let offsetSize = byteCount(UInt64(tableOffset))
        for offset in offsets { append(UInt64(offset), size: offsetSize) }
        out += [0, 0, 0, 0, 0, 0, UInt8(offsetSize), UInt8(referenceSize)]
        append(UInt64(objects.count), size: 8)
        append(0, size: 8)
        append(UInt64(tableOffset), size: 8)
        return out
    }

    /// The fewest of 1, 2, 4 or 8 bytes that hold the value.
    private static func byteCount(_ value: UInt64) -> Int {
        value <= 0xFF ? 1 : value <= 0xFFFF ? 2 : value <= 0xFFFF_FFFF ? 4 : 8
    }

    static func read(_ bytes: [UInt8]) throws -> _PlistValue {
        func corrupt(_ message: String = "The binary property list is corrupt") -> NSError { _plistError(3840, message) }
        guard bytes.count >= 40 else { throw corrupt() }
        func number(at offset: Int, size: Int) throws -> UInt64 {
            guard size >= 1, size <= 8, offset >= 0, offset + size <= bytes.count else { throw corrupt() }
            var value: UInt64 = 0
            for index in offset..<(offset + size) { value = value << 8 | UInt64(bytes[index]) }
            return value
        }
        let trailer = bytes.count - 32
        let offsetSize = Int(bytes[trailer + 6])
        let referenceSize = Int(bytes[trailer + 7])
        let count = Int(try number(at: trailer + 8, size: 8))
        let top = Int(try number(at: trailer + 16, size: 8))
        let tableOffset = Int(try number(at: trailer + 24, size: 8))
        guard count > 0, top < count, tableOffset + count * offsetSize <= trailer else { throw corrupt() }

        func object(_ reference: Int, depth: Int) throws -> _PlistValue {
            guard reference < count, depth < 512 else { throw corrupt() }
            let offset = Int(try number(at: tableOffset + reference * offsetSize, size: offsetSize))
            guard offset < trailer else { throw corrupt() }
            let marker = bytes[offset]
            let low = Int(marker & 0x0F)
            // A length of 15 or more follows the marker as an integer object.
            func length() throws -> (count: Int, start: Int) {
                guard low == 0x0F else { return (low, offset + 1) }
                guard offset + 1 < trailer, bytes[offset + 1] >> 4 == 0x1 else { throw corrupt() }
                let size = 1 << Int(bytes[offset + 1] & 0x0F)
                return (Int(try number(at: offset + 2, size: size)), offset + 2 + size)
            }
            func references(_ amount: Int, from start: Int) throws -> [Int] {
                try (0..<amount).map { Int(try number(at: start + $0 * referenceSize, size: referenceSize)) }
            }
            switch marker >> 4 {
            case 0x0:
                switch marker {
                case 0x08: return .bool(false)
                case 0x09: return .bool(true)
                default: throw corrupt()
                }
            case 0x1:
                let size = 1 << low
                if size == 16 { return .unsigned(try number(at: offset + 9, size: 8)) }
                let value = try number(at: offset + 1, size: size)
                return size == 8 ? .integer(Int64(bitPattern: value)) : .integer(Int64(value))
            case 0x2:
                let size = 1 << low
                let value = try number(at: offset + 1, size: size)
                return .real(size == 4 ? Double(Float(bitPattern: UInt32(value))) : Double(bitPattern: value))
            case 0x3:
                return .date(Date(timeIntervalSinceReferenceDate: Double(bitPattern: try number(at: offset + 1, size: 8))))
            case 0x4:
                let (amount, start) = try length()
                guard start + amount <= trailer else { throw corrupt() }
                return .data(Array(bytes[start..<(start + amount)]))
            case 0x5:
                let (amount, start) = try length()
                guard start + amount <= trailer else { throw corrupt() }
                return .string(String(decoding: bytes[start..<(start + amount)], as: UTF8.self))
            case 0x6:
                let (amount, start) = try length()
                guard start + amount * 2 <= trailer else { throw corrupt() }
                let units = try (0..<amount).map { UInt16(try number(at: start + $0 * 2, size: 2)) }
                return .string(String(decoding: units, as: UTF16.self))
            case 0x8:
                // A keyed archive's UID, read as Foundation's coders see it: a dictionary.
                return .dictionary([("CF$UID", .integer(Int64(try number(at: offset + 1, size: low + 1))))])
            case 0xA:
                let (amount, start) = try length()
                return .array(try references(amount, from: start).map { try object($0, depth: depth + 1) })
            case 0xD:
                let (amount, start) = try length()
                let keys = try references(amount, from: start)
                let values = try references(amount, from: start + amount * referenceSize)
                return .dictionary(try zip(keys, values).map { key, value in
                    guard case .string(let name) = try object(key, depth: depth + 1) else { throw corrupt("Dictionary keys must be strings") }
                    return (name, try object(value, depth: depth + 1))
                })
            default:
                throw corrupt()
            }
        }
        return try object(top, depth: 0)
    }
}
#endif
