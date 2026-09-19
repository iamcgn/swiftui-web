// The JSON coder behind `CodableRepresentation`: a payload encoded by one view and decoded by a
// drop destination in the same app. Foundation's `JSONEncoder` would extract its scanner,
// writer, `Decimal` and string members into the wasm bundle, 300 KB the app never runs
// (decision 0006, the wasm size log); this coder speaks the JSON that `Codable` needs.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// A JSON value with the boxes the encoder's containers write into.
indirect enum _JSONNode {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array(_JSONArrayBox)
    case object(_JSONObjectBox)
    case deferred(_JSONNodeBox)

    /// The node with every box resolved: what serialization and decoding read.
    var resolved: _JSONNode {
        switch self {
        case .array(let box): return .array(_JSONArrayBox(box.items.map(\.resolved)))
        case .object(let box): return .object(_JSONObjectBox(box.entries.map { ($0.key, $0.value.resolved) }))
        case .deferred(let box): return (box.node ?? .null).resolved
        default: return self
        }
    }
}

final class _JSONArrayBox {
    var items: [_JSONNode]
    init(_ items: [_JSONNode] = []) { self.items = items }
}

final class _JSONObjectBox {
    var entries: [(key: String, value: _JSONNode)]
    init(_ entries: [(key: String, value: _JSONNode)] = []) { self.entries = entries }
    subscript(key: String) -> _JSONNode? {
        get { entries.first { $0.key == key }?.value }
        set {
            if let index = entries.firstIndex(where: { $0.key == key }) {
                if let newValue { entries[index].value = newValue } else { entries.remove(at: index) }
            } else if let newValue {
                entries.append((key, newValue))
            }
        }
    }
}

final class _JSONNodeBox {
    var node: _JSONNode?
}

// MARK: - Encoding

/// Encodes a `Codable` transfer item as JSON.
package struct _TransferJSONEncoder {
    package init() {}

    package func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = _JSONEncoding(codingPath: [])
        try value.encode(to: encoder)
        var text = ""
        try _JSONWriter.write((encoder.box.node ?? .null).resolved, into: &text)
        return Data(text.utf8)
    }
}

final class _JSONEncoding: Encoder {
    let codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any] = [:]
    let box: _JSONNodeBox

    init(codingPath: [CodingKey], box: _JSONNodeBox = _JSONNodeBox()) {
        self.codingPath = codingPath
        self.box = box
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        let object: _JSONObjectBox
        if case .object(let existing)? = box.node { object = existing } else { object = _JSONObjectBox(); box.node = .object(object) }
        return KeyedEncodingContainer(_JSONKeyedEncoding<Key>(object: object, codingPath: codingPath))
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        let array: _JSONArrayBox
        if case .array(let existing)? = box.node { array = existing } else { array = _JSONArrayBox(); box.node = .array(array) }
        return _JSONUnkeyedEncoding(array: array, codingPath: codingPath)
    }

    func singleValueContainer() -> SingleValueEncodingContainer { _JSONSingleValueEncoding(box: box, codingPath: codingPath) }

    /// The node for a nested value, encoded with its own coding path.
    static func node<T: Encodable>(for value: T, codingPath: [CodingKey]) throws -> _JSONNode {
        let nested = _JSONEncoding(codingPath: codingPath)
        try value.encode(to: nested)
        return nested.box.node ?? .null
    }
}

/// A key on an encoder's path (`Int` keys for unkeyed containers, `super` for super encoders).
struct _JSONKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(stringValue: String) { self.stringValue = stringValue }
    init(intValue: Int) { self.stringValue = "Index \(intValue)"; self.intValue = intValue }
    static let superKey = _JSONKey(stringValue: "super")
}

struct _JSONKeyedEncoding<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let object: _JSONObjectBox
    let codingPath: [CodingKey]

    private func path(_ key: Key) -> [CodingKey] { codingPath + [key] }
    mutating func encodeNil(forKey key: Key) throws { object[key.stringValue] = .null }
    mutating func encode(_ value: Bool, forKey key: Key) throws { object[key.stringValue] = .bool(value) }
    mutating func encode(_ value: String, forKey key: Key) throws { object[key.stringValue] = .string(value) }
    mutating func encode(_ value: Double, forKey key: Key) throws { object[key.stringValue] = try _JSONWriter.number(value, codingPath: path(key)) }
    mutating func encode(_ value: Float, forKey key: Key) throws { object[key.stringValue] = try _JSONWriter.number(Double(value), codingPath: path(key)) }
    mutating func encode(_ value: Int, forKey key: Key) throws { object[key.stringValue] = .integer(Int64(value)) }
    mutating func encode(_ value: Int8, forKey key: Key) throws { object[key.stringValue] = .integer(Int64(value)) }
    mutating func encode(_ value: Int16, forKey key: Key) throws { object[key.stringValue] = .integer(Int64(value)) }
    mutating func encode(_ value: Int32, forKey key: Key) throws { object[key.stringValue] = .integer(Int64(value)) }
    mutating func encode(_ value: Int64, forKey key: Key) throws { object[key.stringValue] = .integer(value) }
    mutating func encode(_ value: UInt, forKey key: Key) throws { object[key.stringValue] = try _JSONWriter.unsigned(UInt64(value), codingPath: path(key)) }
    mutating func encode(_ value: UInt8, forKey key: Key) throws { object[key.stringValue] = .integer(Int64(value)) }
    mutating func encode(_ value: UInt16, forKey key: Key) throws { object[key.stringValue] = .integer(Int64(value)) }
    mutating func encode(_ value: UInt32, forKey key: Key) throws { object[key.stringValue] = .integer(Int64(value)) }
    mutating func encode(_ value: UInt64, forKey key: Key) throws { object[key.stringValue] = try _JSONWriter.unsigned(value, codingPath: path(key)) }
    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws { object[key.stringValue] = try _JSONEncoding.node(for: value, codingPath: path(key)) }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
        let nested: _JSONObjectBox
        if case .object(let existing)? = object[key.stringValue] { nested = existing } else { nested = _JSONObjectBox(); object[key.stringValue] = .object(nested) }
        return KeyedEncodingContainer(_JSONKeyedEncoding<NestedKey>(object: nested, codingPath: path(key)))
    }

    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        let nested: _JSONArrayBox
        if case .array(let existing)? = object[key.stringValue] { nested = existing } else { nested = _JSONArrayBox(); object[key.stringValue] = .array(nested) }
        return _JSONUnkeyedEncoding(array: nested, codingPath: path(key))
    }

    mutating func superEncoder() -> Encoder { superEncoder(named: _JSONKey.superKey.stringValue, path: codingPath + [_JSONKey.superKey]) }
    mutating func superEncoder(forKey key: Key) -> Encoder { superEncoder(named: key.stringValue, path: path(key)) }

    private func superEncoder(named name: String, path: [CodingKey]) -> Encoder {
        let box = _JSONNodeBox()
        object[name] = .deferred(box)
        return _JSONEncoding(codingPath: path, box: box)
    }
}

struct _JSONUnkeyedEncoding: UnkeyedEncodingContainer {
    let array: _JSONArrayBox
    let codingPath: [CodingKey]
    var count: Int { array.items.count }

    private var nextPath: [CodingKey] { codingPath + [_JSONKey(intValue: array.items.count)] }
    mutating func encodeNil() throws { array.items.append(.null) }
    mutating func encode(_ value: Bool) throws { array.items.append(.bool(value)) }
    mutating func encode(_ value: String) throws { array.items.append(.string(value)) }
    mutating func encode(_ value: Double) throws { array.items.append(try _JSONWriter.number(value, codingPath: nextPath)) }
    mutating func encode(_ value: Float) throws { array.items.append(try _JSONWriter.number(Double(value), codingPath: nextPath)) }
    mutating func encode(_ value: Int) throws { array.items.append(.integer(Int64(value))) }
    mutating func encode(_ value: Int8) throws { array.items.append(.integer(Int64(value))) }
    mutating func encode(_ value: Int16) throws { array.items.append(.integer(Int64(value))) }
    mutating func encode(_ value: Int32) throws { array.items.append(.integer(Int64(value))) }
    mutating func encode(_ value: Int64) throws { array.items.append(.integer(value)) }
    mutating func encode(_ value: UInt) throws { array.items.append(try _JSONWriter.unsigned(UInt64(value), codingPath: nextPath)) }
    mutating func encode(_ value: UInt8) throws { array.items.append(.integer(Int64(value))) }
    mutating func encode(_ value: UInt16) throws { array.items.append(.integer(Int64(value))) }
    mutating func encode(_ value: UInt32) throws { array.items.append(.integer(Int64(value))) }
    mutating func encode(_ value: UInt64) throws { array.items.append(try _JSONWriter.unsigned(value, codingPath: nextPath)) }
    mutating func encode<T: Encodable>(_ value: T) throws { array.items.append(try _JSONEncoding.node(for: value, codingPath: nextPath)) }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
        let nested = _JSONObjectBox()
        let path = nextPath
        array.items.append(.object(nested))
        return KeyedEncodingContainer(_JSONKeyedEncoding<NestedKey>(object: nested, codingPath: path))
    }

    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let nested = _JSONArrayBox()
        let path = nextPath
        array.items.append(.array(nested))
        return _JSONUnkeyedEncoding(array: nested, codingPath: path)
    }

    mutating func superEncoder() -> Encoder {
        let box = _JSONNodeBox()
        let path = nextPath
        array.items.append(.deferred(box))
        return _JSONEncoding(codingPath: path, box: box)
    }
}

struct _JSONSingleValueEncoding: SingleValueEncodingContainer {
    let box: _JSONNodeBox
    let codingPath: [CodingKey]

    mutating func encodeNil() throws { box.node = .null }
    mutating func encode(_ value: Bool) throws { box.node = .bool(value) }
    mutating func encode(_ value: String) throws { box.node = .string(value) }
    mutating func encode(_ value: Double) throws { box.node = try _JSONWriter.number(value, codingPath: codingPath) }
    mutating func encode(_ value: Float) throws { box.node = try _JSONWriter.number(Double(value), codingPath: codingPath) }
    mutating func encode(_ value: Int) throws { box.node = .integer(Int64(value)) }
    mutating func encode(_ value: Int8) throws { box.node = .integer(Int64(value)) }
    mutating func encode(_ value: Int16) throws { box.node = .integer(Int64(value)) }
    mutating func encode(_ value: Int32) throws { box.node = .integer(Int64(value)) }
    mutating func encode(_ value: Int64) throws { box.node = .integer(value) }
    mutating func encode(_ value: UInt) throws { box.node = try _JSONWriter.unsigned(UInt64(value), codingPath: codingPath) }
    mutating func encode(_ value: UInt8) throws { box.node = .integer(Int64(value)) }
    mutating func encode(_ value: UInt16) throws { box.node = .integer(Int64(value)) }
    mutating func encode(_ value: UInt32) throws { box.node = .integer(Int64(value)) }
    mutating func encode(_ value: UInt64) throws { box.node = try _JSONWriter.unsigned(value, codingPath: codingPath) }
    mutating func encode<T: Encodable>(_ value: T) throws { box.node = try _JSONEncoding.node(for: value, codingPath: codingPath) }
}

enum _JSONWriter {
    static func number(_ value: Double, codingPath: [CodingKey]) throws -> _JSONNode {
        guard value.isFinite else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "JSON has no representation for \(value)"))
        }
        if value == value.rounded(), abs(value) < 9_007_199_254_740_992 { return .integer(Int64(value)) }
        return .number(value)
    }

    static func unsigned(_ value: UInt64, codingPath: [CodingKey]) throws -> _JSONNode {
        guard let signed = Int64(exactly: value) else {
            throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: codingPath, debugDescription: "\(value) exceeds the JSON integer range"))
        }
        return .integer(signed)
    }

    static func write(_ node: _JSONNode, into text: inout String) throws {
        switch node {
        case .null: text += "null"
        case .bool(let value): text += value ? "true" : "false"
        case .integer(let value): text += String(value)
        case .number(let value): text += String(value)
        case .string(let value): writeString(value, into: &text)
        case .array(let box):
            text += "["
            for (index, item) in box.items.enumerated() {
                if index > 0 { text += "," }
                try write(item, into: &text)
            }
            text += "]"
        case .object(let box):
            text += "{"
            for (index, entry) in box.entries.enumerated() {
                if index > 0 { text += "," }
                writeString(entry.key, into: &text)
                text += ":"
                try write(entry.value, into: &text)
            }
            text += "}"
        case .deferred(let box): try write(box.node ?? .null, into: &text)
        }
    }

    static func writeString(_ value: String, into text: inout String) {
        text += "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": text += "\\\""
            case "\\": text += "\\\\"
            case "\n": text += "\\n"
            case "\r": text += "\\r"
            case "\t": text += "\\t"
            case "\u{08}": text += "\\b"
            case "\u{0C}": text += "\\f"
            case "\u{00}"..."\u{1F}":
                let hex = String(scalar.value, radix: 16)
                text += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
            default: text.unicodeScalars.append(scalar)
            }
        }
        text += "\""
    }
}

// MARK: - Decoding

/// Decodes a `Codable` transfer item from JSON.
package struct _TransferJSONDecoder {
    package init() {}

    package func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        var parser = _JSONParser(bytes: Array(data))
        let node = try parser.parseDocument()
        return try T(from: _JSONDecoding(node: node, codingPath: []))
    }
}

struct _JSONParser {
    let bytes: [UInt8]
    var index = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func parseDocument() throws -> _JSONNode {
        let node = try parseValue()
        skipWhitespace()
        guard index == bytes.count else { throw error("Unexpected text after the JSON value") }
        return node
    }

    private func error(_ message: String) -> DecodingError {
        .dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "\(message) at byte \(index)"))
    }

    private mutating func skipWhitespace() {
        while index < bytes.count, bytes[index] == 0x20 || bytes[index] == 0x0A || bytes[index] == 0x0D || bytes[index] == 0x09 { index += 1 }
    }

    private mutating func consume(_ literal: String) throws {
        for byte in literal.utf8 {
            guard index < bytes.count, bytes[index] == byte else { throw error("Malformed literal") }
            index += 1
        }
    }

    private mutating func parseValue() throws -> _JSONNode {
        skipWhitespace()
        guard index < bytes.count else { throw error("Unexpected end of JSON") }
        switch bytes[index] {
        case UInt8(ascii: "{"): return try parseObject()
        case UInt8(ascii: "["): return try parseArray()
        case UInt8(ascii: "\""): return .string(try parseString())
        case UInt8(ascii: "t"): try consume("true"); return .bool(true)
        case UInt8(ascii: "f"): try consume("false"); return .bool(false)
        case UInt8(ascii: "n"): try consume("null"); return .null
        default: return try parseNumber()
        }
    }

    private mutating func parseObject() throws -> _JSONNode {
        index += 1
        let object = _JSONObjectBox()
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .object(object) }
        while true {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw error("Expected an object key") }
            let key = try parseString()
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw error("Expected ':'") }
            index += 1
            object.entries.append((key, try parseValue()))
            skipWhitespace()
            guard index < bytes.count else { throw error("Unterminated object") }
            if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
            if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(object) }
            throw error("Expected ',' or '}'")
        }
    }

    private mutating func parseArray() throws -> _JSONNode {
        index += 1
        let array = _JSONArrayBox()
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .array(array) }
        while true {
            array.items.append(try parseValue())
            skipWhitespace()
            guard index < bytes.count else { throw error("Unterminated array") }
            if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
            if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(array) }
            throw error("Expected ',' or ']'")
        }
    }

    private mutating func parseString() throws -> String {
        index += 1
        var scalars = String.UnicodeScalarView()
        var utf8Run: [UInt8] = []
        func flushRun() {
            if !utf8Run.isEmpty { scalars.append(contentsOf: String(decoding: utf8Run, as: UTF8.self).unicodeScalars); utf8Run.removeAll() }
        }
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            switch byte {
            case UInt8(ascii: "\""):
                flushRun()
                return String(scalars)
            case UInt8(ascii: "\\"):
                flushRun()
                guard index < bytes.count else { throw error("Unterminated escape") }
                let escape = bytes[index]
                index += 1
                switch escape {
                case UInt8(ascii: "\""): scalars.append("\"")
                case UInt8(ascii: "\\"): scalars.append("\\")
                case UInt8(ascii: "/"): scalars.append("/")
                case UInt8(ascii: "b"): scalars.append("\u{08}")
                case UInt8(ascii: "f"): scalars.append("\u{0C}")
                case UInt8(ascii: "n"): scalars.append("\n")
                case UInt8(ascii: "r"): scalars.append("\r")
                case UInt8(ascii: "t"): scalars.append("\t")
                case UInt8(ascii: "u"):
                    var code = try parseHex4()
                    if code >= 0xD800, code < 0xDC00 {
                        try consume("\\u")
                        let low = try parseHex4()
                        guard low >= 0xDC00, low < 0xE000 else { throw error("Invalid surrogate pair") }
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                    }
                    guard let scalar = Unicode.Scalar(code) else { throw error("Invalid unicode escape") }
                    scalars.append(scalar)
                default: throw error("Unknown escape")
                }
            default:
                utf8Run.append(byte)
            }
        }
        throw error("Unterminated string")
    }

    private mutating func parseHex4() throws -> UInt32 {
        guard index + 4 <= bytes.count else { throw error("Short unicode escape") }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let byte = bytes[index]
            index += 1
            let digit: UInt32
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = UInt32(byte - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = UInt32(byte - UInt8(ascii: "a")) + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = UInt32(byte - UInt8(ascii: "A")) + 10
            default: throw error("Invalid hex digit")
            }
            value = value * 16 + digit
        }
        return value
    }

    private mutating func parseNumber() throws -> _JSONNode {
        let start = index
        var isInteger = true
        while index < bytes.count {
            let byte = bytes[index]
            if byte == UInt8(ascii: ".") || byte == UInt8(ascii: "e") || byte == UInt8(ascii: "E") { isInteger = false }
            else if !(byte == UInt8(ascii: "-") || byte == UInt8(ascii: "+") || (byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9"))) { break }
            index += 1
        }
        let text = String(decoding: bytes[start..<index], as: UTF8.self)
        if isInteger, let value = Int64(text) { return .integer(value) }
        guard let value = Double(text) else { throw error("Malformed number '\(text)'") }
        return .number(value)
    }
}

final class _JSONDecoding: Decoder {
    let node: _JSONNode
    let codingPath: [CodingKey]
    let userInfo: [CodingUserInfoKey: Any] = [:]

    init(node: _JSONNode, codingPath: [CodingKey]) {
        self.node = node
        self.codingPath = codingPath
    }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case .object(let object) = node else { throw _JSONDecoding.mismatch([String: Any].self, node, codingPath) }
        return KeyedDecodingContainer(_JSONKeyedDecoding<Key>(object: object, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        guard case .array(let array) = node else { throw _JSONDecoding.mismatch([Any].self, node, codingPath) }
        return _JSONUnkeyedDecoding(array: array, codingPath: codingPath)
    }

    func singleValueContainer() throws -> SingleValueDecodingContainer { _JSONSingleValueDecoding(node: node, codingPath: codingPath) }

    static func mismatch(_ type: Any.Type, _ node: _JSONNode, _ codingPath: [CodingKey]) -> DecodingError {
        if case .null = node {
            return .valueNotFound(type, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected \(type) but found null"))
        }
        return .typeMismatch(type, DecodingError.Context(codingPath: codingPath, debugDescription: "Expected \(type)"))
    }

    /// The primitive a node holds as `T`, or a type mismatch.
    static func primitive<T>(_ type: T.Type, from node: _JSONNode, codingPath: [CodingKey]) throws -> T {
        let value: Any?
        switch (type, node) {
        case (is Bool.Type, .bool(let bool)): value = bool
        case (is String.Type, .string(let string)): value = string
        case (is Double.Type, .integer(let whole)): value = Double(whole)
        case (is Double.Type, .number(let number)): value = number
        case (is Float.Type, .integer(let whole)): value = Float(whole)
        case (is Float.Type, .number(let number)): value = Float(number)
        case (_, .integer(let whole)): value = integer(type, whole)
        case (_, .number(let number)) where number == number.rounded() && abs(number) < 9.2e18: value = integer(type, Int64(number))
        default: value = nil
        }
        guard let value = value as? T else { throw mismatch(type, node, codingPath) }
        return value
    }

    private static func integer<T>(_ type: T.Type, _ value: Int64) -> Any? {
        switch type {
        case is Int.Type: return Int(exactly: value)
        case is Int8.Type: return Int8(exactly: value)
        case is Int16.Type: return Int16(exactly: value)
        case is Int32.Type: return Int32(exactly: value)
        case is Int64.Type: return value
        case is UInt.Type: return UInt(exactly: value)
        case is UInt8.Type: return UInt8(exactly: value)
        case is UInt16.Type: return UInt16(exactly: value)
        case is UInt32.Type: return UInt32(exactly: value)
        case is UInt64.Type: return UInt64(exactly: value)
        default: return nil
        }
    }
}

struct _JSONKeyedDecoding<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let object: _JSONObjectBox
    let codingPath: [CodingKey]

    var allKeys: [Key] { object.entries.compactMap { Key(stringValue: $0.key) } }
    func contains(_ key: Key) -> Bool { object[key.stringValue] != nil }

    private func node(_ key: Key) throws -> _JSONNode {
        guard let node = object[key.stringValue] else {
            throw DecodingError.keyNotFound(key, DecodingError.Context(codingPath: codingPath, debugDescription: "No value for '\(key.stringValue)'"))
        }
        return node
    }
    private func path(_ key: Key) -> [CodingKey] { codingPath + [key] }
    private func primitive<T>(_ type: T.Type, _ key: Key) throws -> T { try _JSONDecoding.primitive(type, from: try node(key), codingPath: path(key)) }

    func decodeNil(forKey key: Key) throws -> Bool { if case .null = try node(key) { return true } else { return false } }
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try primitive(type, key) }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { try primitive(type, key) }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try primitive(type, key) }
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try primitive(type, key) }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try primitive(type, key) }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try primitive(type, key) }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try primitive(type, key) }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try primitive(type, key) }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try primitive(type, key) }
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try primitive(type, key) }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try primitive(type, key) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try primitive(type, key) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try primitive(type, key) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try primitive(type, key) }
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T { try T(from: _JSONDecoding(node: try node(key), codingPath: path(key))) }

    func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        try _JSONDecoding(node: try node(key), codingPath: path(key)).container(keyedBy: type)
    }
    func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
        try _JSONDecoding(node: try node(key), codingPath: path(key)).unkeyedContainer()
    }
    func superDecoder() throws -> Decoder {
        _JSONDecoding(node: object[_JSONKey.superKey.stringValue] ?? .null, codingPath: codingPath + [_JSONKey.superKey])
    }
    func superDecoder(forKey key: Key) throws -> Decoder { _JSONDecoding(node: try node(key), codingPath: path(key)) }
}

struct _JSONUnkeyedDecoding: UnkeyedDecodingContainer {
    let array: _JSONArrayBox
    let codingPath: [CodingKey]
    var currentIndex = 0

    var count: Int? { array.items.count }
    var isAtEnd: Bool { currentIndex >= array.items.count }

    private var path: [CodingKey] { codingPath + [_JSONKey(intValue: currentIndex)] }
    private mutating func next() throws -> _JSONNode {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(Any.self, DecodingError.Context(codingPath: path, debugDescription: "Unkeyed container is at end"))
        }
        defer { currentIndex += 1 }
        return array.items[currentIndex]
    }
    private mutating func primitive<T>(_ type: T.Type) throws -> T {
        let path = path
        return try _JSONDecoding.primitive(type, from: try next(), codingPath: path)
    }

    mutating func decodeNil() throws -> Bool {
        guard !isAtEnd else { return false }
        if case .null = array.items[currentIndex] { currentIndex += 1; return true }
        return false
    }
    mutating func decode(_ type: Bool.Type) throws -> Bool { try primitive(type) }
    mutating func decode(_ type: String.Type) throws -> String { try primitive(type) }
    mutating func decode(_ type: Double.Type) throws -> Double { try primitive(type) }
    mutating func decode(_ type: Float.Type) throws -> Float { try primitive(type) }
    mutating func decode(_ type: Int.Type) throws -> Int { try primitive(type) }
    mutating func decode(_ type: Int8.Type) throws -> Int8 { try primitive(type) }
    mutating func decode(_ type: Int16.Type) throws -> Int16 { try primitive(type) }
    mutating func decode(_ type: Int32.Type) throws -> Int32 { try primitive(type) }
    mutating func decode(_ type: Int64.Type) throws -> Int64 { try primitive(type) }
    mutating func decode(_ type: UInt.Type) throws -> UInt { try primitive(type) }
    mutating func decode(_ type: UInt8.Type) throws -> UInt8 { try primitive(type) }
    mutating func decode(_ type: UInt16.Type) throws -> UInt16 { try primitive(type) }
    mutating func decode(_ type: UInt32.Type) throws -> UInt32 { try primitive(type) }
    mutating func decode(_ type: UInt64.Type) throws -> UInt64 { try primitive(type) }
    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let path = path
        return try T(from: _JSONDecoding(node: try next(), codingPath: path))
    }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        let path = path
        return try _JSONDecoding(node: try next(), codingPath: path).container(keyedBy: type)
    }
    mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
        let path = path
        return try _JSONDecoding(node: try next(), codingPath: path).unkeyedContainer()
    }
    mutating func superDecoder() throws -> Decoder {
        let path = path
        return _JSONDecoding(node: try next(), codingPath: path)
    }
}

struct _JSONSingleValueDecoding: SingleValueDecodingContainer {
    let node: _JSONNode
    let codingPath: [CodingKey]

    private func primitive<T>(_ type: T.Type) throws -> T { try _JSONDecoding.primitive(type, from: node, codingPath: codingPath) }
    func decodeNil() -> Bool { if case .null = node { return true } else { return false } }
    func decode(_ type: Bool.Type) throws -> Bool { try primitive(type) }
    func decode(_ type: String.Type) throws -> String { try primitive(type) }
    func decode(_ type: Double.Type) throws -> Double { try primitive(type) }
    func decode(_ type: Float.Type) throws -> Float { try primitive(type) }
    func decode(_ type: Int.Type) throws -> Int { try primitive(type) }
    func decode(_ type: Int8.Type) throws -> Int8 { try primitive(type) }
    func decode(_ type: Int16.Type) throws -> Int16 { try primitive(type) }
    func decode(_ type: Int32.Type) throws -> Int32 { try primitive(type) }
    func decode(_ type: Int64.Type) throws -> Int64 { try primitive(type) }
    func decode(_ type: UInt.Type) throws -> UInt { try primitive(type) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try primitive(type) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try primitive(type) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try primitive(type) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try primitive(type) }
    func decode<T: Decodable>(_ type: T.Type) throws -> T { try T(from: _JSONDecoding(node: node, codingPath: codingPath)) }
}
