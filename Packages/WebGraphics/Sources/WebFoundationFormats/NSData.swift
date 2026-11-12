// Foundation's `NSData` and `NSMutableData` on wasm, over WebFoundation's `Data`: IceCubes
// builds a multipart body in an `NSMutableData` and sends it as `body as Data`. `Data` bridges
// to `NSData` as it does on Apple platforms, so `as`, `as?` and `as!` convert either way (a
// mutable one too). Equal when the bytes are; a copy is a new object with the same bytes.
// In this module rather than WebFoundation, as the bridge keeps both classes in every bundle
// that links the module that declares it (decision 0006).
#if os(WASI)
import WebFoundation

/// A static byte buffer: the object form of `Data`.
open class NSData: _WebNSValue, NSCopying, NSMutableCopying, @unchecked Sendable {
    var _bytes: [UInt8]

    public override init() {
        _bytes = []
        super.init()
    }
    public init(data: Data) {
        _bytes = data.bytes
        super.init()
    }
    public init(bytes: UnsafeRawPointer?, length: Int) {
        _bytes = bytes.map { Array(UnsafeRawBufferPointer(start: $0, count: length)) } ?? []
        super.init()
    }
    public convenience init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url) else { return nil }
        self.init(data: data)
    }
    public convenience init?(base64Encoded base64String: String, options: Data.Base64DecodingOptions = []) {
        guard let data = Data(base64Encoded: base64String, options: options) else { return nil }
        self.init(data: data)
    }

    /// The number of bytes.
    open var length: Int { _bytes.count }

    /// The bytes as a value.
    var _data: Data { Data(_bytes) }
    /// The bytes, as the runtime's value box holds them (`nsData as Data` with the runtime).
    open override var value: Any { _data }

    public func isEqual(to other: Data) -> Bool { _bytes == other.bytes }
    open override func isEqual(_ object: Any?) -> Bool {
        switch object {
        case let other as NSData: return other._bytes == _bytes
        case let other as Data: return other.bytes == _bytes
        default: return false
        }
    }
    open override var hash: Int { _bytes.hashValue }
    /// Foundation's form: "{length = 3, bytes = 0x616263}".
    open override var description: String {
        "{length = \(_bytes.count), bytes = 0x" + _bytes.map { ($0 < 16 ? "0" : "") + String($0, radix: 16) }.joined() + "}"
    }

    public func subdata(with range: NSRange) -> Data { Data(_bytes[range.location..<(range.location + range.length)]) }
    public func getBytes(_ buffer: UnsafeMutableRawPointer, length: Int) {
        let count = Swift.min(length, _bytes.count)
        _bytes.withUnsafeBytes { buffer.copyMemory(from: $0.baseAddress!, byteCount: count) }
    }
    public func base64EncodedString(options: Data.Base64EncodingOptions = []) -> String { _data.base64EncodedString(options: options) }
    public func write(to url: URL, atomically: Bool) -> Bool { (try? _data.write(to: url)) != nil }

    open func copy(with zone: NSZone? = nil) -> Any { NSData(data: _data) }
    open func mutableCopy(with zone: NSZone? = nil) -> Any { NSMutableData(data: _data) }
}

/// A byte buffer that can grow, shrink and change.
open class NSMutableData: NSData, @unchecked Sendable {
    public convenience init?(capacity: Int) {
        self.init()
        _bytes.reserveCapacity(capacity)
    }
    public convenience init?(length: Int) {
        self.init(data: Data(count: length))
    }

    /// The number of bytes; setting it truncates or pads with zeros.
    open override var length: Int {
        get { _bytes.count }
        set {
            if newValue < _bytes.count { _bytes.removeLast(_bytes.count - newValue) } else { _bytes += Array(repeating: 0, count: newValue - _bytes.count) }
        }
    }

    open func append(_ other: Data) { _bytes += other.bytes }
    open func append(_ bytes: UnsafeRawPointer, length: Int) { _bytes += Array(UnsafeRawBufferPointer(start: bytes, count: length)) }
    open func setData(_ data: Data) { _bytes = data.bytes }
    open func increaseLength(by extraLength: Int) { _bytes += Array(repeating: 0, count: extraLength) }
    open func resetBytes(in range: NSRange) {
        for index in range.location..<(range.location + range.length) { _bytes[index] = 0 }
    }
    open func replaceBytes(in range: NSRange, withBytes bytes: UnsafeRawPointer, length replacementLength: Int) {
        _bytes.replaceSubrange(range.location..<(range.location + range.length), with: UnsafeRawBufferPointer(start: bytes, count: replacementLength))
    }

    open override func copy(with zone: NSZone? = nil) -> Any { NSData(data: _data) }
}

// With the Objective-C runtime too, so `data as NSData` converts there as well.
extension Data: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSData
    public func _bridgeToObjectiveC() -> NSData { NSData(data: self) }
    public static func _forceBridgeFromObjectiveC(_ source: NSData, result: inout Data?) { result = source._data }
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSData, result: inout Data?) -> Bool {
        result = source._data
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSData?) -> Data { source?._data ?? Data() }
}

// MARK: Compression

extension NSData {
    /// The algorithms `compressed(using:)` and `decompressed(using:)` take.
    public enum CompressionAlgorithm: Int, Sendable {
        case lzfse = 0, lz4 = 1, lzma = 2, zlib = 3
    }

    /// The bytes compressed with `algorithm`. `zlib` is raw DEFLATE, as Apple's is. The page
    /// has no LZFSE, LZ4 or LZMA encoder, so those write raw DEFLATE too: what this runtime
    /// compressed it decompresses again, whichever algorithm both calls name.
    open func compressed(using algorithm: CompressionAlgorithm) throws -> NSData {
        NSData(data: Data(_deflate(_bytes)))
    }

    /// The bytes decompressed. Throws when they are not a DEFLATE stream, which includes LZFSE,
    /// LZ4 and LZMA bytes another device wrote.
    open func decompressed(using algorithm: CompressionAlgorithm) throws -> NSData {
        guard let bytes = try? _inflate(_bytes) else { throw CocoaError(.fileReadCorruptFile) }
        return NSData(data: Data(bytes))
    }
}

extension NSMutableData {
    /// Compresses the bytes in place.
    open func compress(using algorithm: CompressionAlgorithm) throws { _bytes = _deflate(_bytes) }

    /// Decompresses the bytes in place, or throws and leaves them as they were.
    open func decompress(using algorithm: CompressionAlgorithm) throws {
        guard let bytes = try? _inflate(_bytes) else { throw CocoaError(.fileReadCorruptFile) }
        _bytes = bytes
    }
}

// MARK: Core Foundation's mutable data

/// Core Foundation's mutable data, which is `NSMutableData` toll-free (`NSMutableData() as
/// CFMutableData`).
public typealias CFMutableData = NSMutableData

/// An empty mutable data object (the capacity is a hint).
public func CFDataCreateMutable(_ allocator: CFAllocator?, _ capacity: CFIndex) -> CFMutableData! {
    NSMutableData(capacity: capacity)
}
#endif
