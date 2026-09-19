// Foundation's `Data` on wasm (decision 0017): a byte array with the surface the frameworks
// and ordinary apps use. Differences from Foundation: a slice is a fresh `Data` indexed from
// zero, and there is no `String.Encoding` (`String(decoding:as:)` and `Data(text.utf8)` are
// the conversions).
#if os(WASI)
public struct Data: Hashable, Sendable, Codable, CustomStringConvertible, CustomDebugStringConvertible,
                    RandomAccessCollection, MutableCollection, RangeReplaceableCollection {
    public typealias Index = Int
    public typealias Element = UInt8
    public typealias SubSequence = Data

    /// The bytes, as an array.
    public var bytes: [UInt8]

    public init() { bytes = [] }
    public init(_ bytes: [UInt8]) { self.bytes = bytes }
    public init<S: Sequence>(_ elements: S) where S.Element == UInt8 { bytes = Array(elements) }
    public init(repeating value: UInt8, count: Int) { bytes = Array(repeating: value, count: count) }
    public init(capacity: Int) { bytes = []; bytes.reserveCapacity(capacity) }
    public init(bytes pointer: UnsafeRawPointer, count: Int) {
        self.bytes = Array(UnsafeRawBufferPointer(start: pointer, count: count))
    }
    public init(buffer: UnsafeBufferPointer<UInt8>) { bytes = Array(buffer) }
    public init(buffer: UnsafeMutableBufferPointer<UInt8>) { bytes = Array(buffer) }
    public init(_ buffer: UnsafeRawBufferPointer) { bytes = Array(buffer) }

    public var startIndex: Int { 0 }
    public var endIndex: Int { bytes.count }
    public var count: Int { bytes.count }
    public func index(after i: Int) -> Int { i + 1 }
    public func index(before i: Int) -> Int { i - 1 }

    public subscript(position: Int) -> UInt8 {
        get { bytes[position] }
        set { bytes[position] = newValue }
    }
    public subscript(bounds: Range<Int>) -> Data {
        get { Data(bytes[bounds]) }
        set { bytes.replaceSubrange(bounds, with: newValue.bytes) }
    }

    public mutating func replaceSubrange<C: Collection>(_ subrange: Range<Int>, with newElements: C) where C.Element == UInt8 {
        bytes.replaceSubrange(subrange, with: newElements)
    }
    public mutating func append(_ other: Data) { bytes.append(contentsOf: other.bytes) }
    public mutating func append(_ byte: UInt8) { bytes.append(byte) }
    public mutating func append<S: Sequence>(contentsOf elements: S) where S.Element == UInt8 { bytes.append(contentsOf: elements) }
    public mutating func append(_ pointer: UnsafePointer<UInt8>, count: Int) {
        bytes.append(contentsOf: UnsafeBufferPointer(start: pointer, count: count))
    }
    public mutating func reserveCapacity(_ minimumCapacity: Int) { bytes.reserveCapacity(minimumCapacity) }
    public mutating func resetBytes(in range: Range<Int>) {
        for i in range { bytes[i] = 0 }
    }
    public func subdata(in range: Range<Int>) -> Data { Data(bytes[range]) }
    public static func += (lhs: inout Data, rhs: Data) { lhs.append(rhs) }

    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try bytes.withUnsafeBytes(body)
    }
    public mutating func withUnsafeMutableBytes<R>(_ body: (UnsafeMutableRawBufferPointer) throws -> R) rethrows -> R {
        try bytes.withUnsafeMutableBytes(body)
    }
    public func copyBytes(to pointer: UnsafeMutablePointer<UInt8>, count: Int) {
        for i in 0..<Swift.min(count, bytes.count) { pointer[i] = bytes[i] }
    }
    public func copyBytes(to pointer: UnsafeMutablePointer<UInt8>, from range: Range<Int>) {
        for (offset, i) in range.enumerated() { pointer[offset] = bytes[i] }
    }
    @discardableResult
    public func copyBytes(to buffer: UnsafeMutableBufferPointer<UInt8>) -> Int {
        let count = Swift.min(buffer.count, bytes.count)
        guard let base = buffer.baseAddress else { return 0 }
        copyBytes(to: base, count: count)
        return count
    }

    /// Options Foundation's base64 methods take; `lineLength64Characters` and
    /// `lineLength76Characters` wrap the output, the line-ending options are accepted.
    public struct Base64EncodingOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let lineLength64Characters = Base64EncodingOptions(rawValue: 1)
        public static let lineLength76Characters = Base64EncodingOptions(rawValue: 2)
        public static let endLineWithCarriageReturn = Base64EncodingOptions(rawValue: 16)
        public static let endLineWithLineFeed = Base64EncodingOptions(rawValue: 32)
    }
    public struct Base64DecodingOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let ignoreUnknownCharacters = Base64DecodingOptions(rawValue: 1)
    }

    public func base64EncodedString(options: Base64EncodingOptions = []) -> String {
        let line = options.contains(.lineLength64Characters) ? 64 : options.contains(.lineLength76Characters) ? 76 : nil
        return _Base64.encode(bytes, lineLength: line)
    }
    public func base64EncodedData(options: Base64EncodingOptions = []) -> Data { Data(base64EncodedString(options: options).utf8) }
    public init?(base64Encoded string: String, options: Base64DecodingOptions = []) {
        guard let bytes = _Base64.decode(string.utf8, ignoreUnknown: options.contains(.ignoreUnknownCharacters)) else { return nil }
        self.bytes = bytes
    }
    public init?(base64Encoded data: Data, options: Base64DecodingOptions = []) {
        guard let bytes = _Base64.decode(data.bytes, ignoreUnknown: options.contains(.ignoreUnknownCharacters)) else { return nil }
        self.bytes = bytes
    }

    public var description: String { "\(bytes.count) bytes" }
    public var debugDescription: String { description }

    // Foundation encodes `Data` as an unkeyed container of bytes.
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var bytes: [UInt8] = []
        if let count = container.count { bytes.reserveCapacity(count) }
        while !container.isAtEnd { bytes.append(try container.decode(UInt8.self)) }
        self.bytes = bytes
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(contentsOf: bytes)
    }
}
#endif
