// Foundation's `Data` on wasm (decision 0017, pf-web-foundation-gaps): a byte array with the
// surface the frameworks and ordinary apps use. A slice keeps its indices, as Foundation's
// does (`data[2..<4].startIndex` is 2; `Data(slice)` starts a fresh value at zero);
// `String.Encoding` lives in StringEncoding.swift.
#if os(WASI)
public struct Data: Hashable, Sendable, Codable, CustomStringConvertible, CustomDebugStringConvertible,
                    RandomAccessCollection, MutableCollection, RangeReplaceableCollection {
    public typealias Index = Int
    public typealias Element = UInt8
    public typealias SubSequence = Data

    /// The bytes, as an array (a slice's own bytes, from its `startIndex`).
    public var bytes: [UInt8]
    /// The index of the first byte: zero, or where a slice began in its source.
    public private(set) var startIndex: Int = 0

    public init() { bytes = [] }
    public init(_ bytes: [UInt8]) { self.bytes = bytes }
    private init(bytes: [UInt8], startIndex: Int) {
        self.bytes = bytes
        self.startIndex = startIndex
    }
    public init<S: Sequence>(_ elements: S) where S.Element == UInt8 { bytes = Array(elements) }
    public init(repeating value: UInt8, count: Int) { bytes = Array(repeating: value, count: count) }
    public init(capacity: Int) { bytes = []; bytes.reserveCapacity(capacity) }
    public init(bytes pointer: UnsafeRawPointer, count: Int) {
        self.bytes = Array(UnsafeRawBufferPointer(start: pointer, count: count))
    }
    public init(buffer: UnsafeBufferPointer<UInt8>) { bytes = Array(buffer) }
    public init(buffer: UnsafeMutableBufferPointer<UInt8>) { bytes = Array(buffer) }
    public init(_ buffer: UnsafeRawBufferPointer) { bytes = Array(buffer) }

    public var endIndex: Int { startIndex + bytes.count }
    public var count: Int { bytes.count }
    public func index(after i: Int) -> Int { i + 1 }
    public func index(before i: Int) -> Int { i - 1 }

    public subscript(position: Int) -> UInt8 {
        get { bytes[position - startIndex] }
        set { bytes[position - startIndex] = newValue }
    }
    /// A slice sharing this value's indices.
    public subscript(bounds: Range<Int>) -> Data {
        get { Data(bytes: Array(bytes[(bounds.lowerBound - startIndex)..<(bounds.upperBound - startIndex)]), startIndex: bounds.lowerBound) }
        set { bytes.replaceSubrange((bounds.lowerBound - startIndex)..<(bounds.upperBound - startIndex), with: newValue.bytes) }
    }

    public mutating func replaceSubrange<C: Collection>(_ subrange: Range<Int>, with newElements: C) where C.Element == UInt8 {
        bytes.replaceSubrange((subrange.lowerBound - startIndex)..<(subrange.upperBound - startIndex), with: newElements)
    }
    public mutating func append(_ other: Data) { bytes.append(contentsOf: other.bytes) }
    public mutating func append(_ byte: UInt8) { bytes.append(byte) }
    public mutating func append<S: Sequence>(contentsOf elements: S) where S.Element == UInt8 { bytes.append(contentsOf: elements) }
    public mutating func append(_ pointer: UnsafePointer<UInt8>, count: Int) {
        bytes.append(contentsOf: UnsafeBufferPointer(start: pointer, count: count))
    }
    public mutating func reserveCapacity(_ minimumCapacity: Int) { bytes.reserveCapacity(minimumCapacity) }
    public mutating func resetBytes(in range: Range<Int>) {
        for i in range { bytes[i - startIndex] = 0 }
    }
    /// The bytes in `range` (this value's indices) as a fresh value indexed from zero.
    public func subdata(in range: Range<Int>) -> Data { Data(bytes[(range.lowerBound - startIndex)..<(range.upperBound - startIndex)]) }
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
        for (offset, i) in range.enumerated() { pointer[offset] = bytes[i - startIndex] }
    }
    /// Foundation's `firstRange(of:)`: where `other` first occurs, in this value's indices.
    public func range(of other: Data, options: SearchOptions = [], in range: Range<Int>? = nil) -> Range<Int>? {
        let bounds = range ?? startIndex..<endIndex
        let needle = other.bytes
        guard !needle.isEmpty, bounds.count >= needle.count else { return nil }
        let indices = Array(bounds.lowerBound...(bounds.upperBound - needle.count))
        for start in options.contains(.backwards) ? indices.reversed() : indices {
            if bytes[(start - startIndex)..<(start - startIndex + needle.count)].elementsEqual(needle) { return start..<(start + needle.count) }
        }
        return nil
    }
    public struct SearchOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let backwards = SearchOptions(rawValue: 1)
        public static let anchored = SearchOptions(rawValue: 2)
    }

    // Foundation compares and hashes the bytes alone, whatever a slice's indices.
    public static func == (lhs: Data, rhs: Data) -> Bool { lhs.bytes == rhs.bytes }
    public func hash(into hasher: inout Hasher) { hasher.combine(bytes) }
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
