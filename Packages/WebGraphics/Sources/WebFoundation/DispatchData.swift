// Dispatch's `DispatchData` on wasm (decision 0021): the wasm SDK has no Dispatch module, and
// packages that move bytes write against it under `#if canImport(Dispatch)`, which the Dispatch
// shadow makes true (SwiftNIO's NIOCore converts its `ByteBuffer` to and from one). Dispatch
// keeps a data value as regions of memory it may share; here it is one array of bytes, so
// there is one region, `region(location:)` answers the whole value, and the no-copy
// initialisers copy the bytes and release the caller's buffer once no value holds it. The methods are
// Dispatch's (swift-corelibs-libdispatch's Data.swift), deprecated forms included.
#if os(WASI)
import WASILibc

public struct DispatchData: RandomAccessCollection, Sendable {
    public typealias Iterator = DispatchDataIterator
    public typealias Index = Int
    public typealias Indices = DefaultIndices<DispatchData>

    /// The bytes, in order.
    fileprivate var _bytes: [UInt8]
    /// The no-copy buffers these bytes came from, each released once the last value holding it
    /// is gone: a slice or an append holds its source's, as Dispatch's subranges and
    /// concatenations hold the regions they came from.
    private var _releases: [_NoCopyRelease] = []

    fileprivate init(_bytes: [UInt8]) { self._bytes = _bytes }

    public static let empty = DispatchData(_bytes: [])

    /// What releases the buffer handed to a no-copy initialiser.
    public enum Deallocator {
        /// The buffer came from `malloc`: it is freed.
        case free
        /// The buffer came from `mmap`: wasm has no mapped memory to unmap, so it is left as it is.
        case unmap
        /// The block runs once the bytes are no longer needed (here, once they are copied); the
        /// queue is accepted and the block runs in place, as every queue runs on the one thread.
        case custom(DispatchQueue?, () -> Void)
    }

    @available(swift, deprecated: 4, message: "Use init(bytes: UnsafeRawBufferPointer) instead")
    public init(bytes buffer: UnsafeBufferPointer<UInt8>) {
        _bytes = Array(buffer)
    }

    public init(bytes buffer: UnsafeRawBufferPointer) {
        _bytes = Array(buffer)
    }

    @available(swift, deprecated: 4, message: "Use init(bytesNoCopy: UnsafeRawBufferPointer, deallocater: Deallocator) instead")
    public init(bytesNoCopy bytes: UnsafeBufferPointer<UInt8>, deallocator: Deallocator = .free) {
        self.init(bytesNoCopy: UnsafeRawBufferPointer(bytes), deallocator: deallocator)
    }

    /// The bytes are copied in, and the caller's buffer is released as Dispatch releases it: once
    /// the last copy of the value is gone (at once for an empty buffer), with a custom block
    /// submitted to its queue (the default global queue when none is given).
    public init(bytesNoCopy bytes: UnsafeRawBufferPointer, deallocator: Deallocator = .free) {
        _bytes = Array(bytes)
        let release: () -> Void
        switch deallocator {
        case .free:
            guard let base = bytes.baseAddress else { return }
            release = { WASILibc.free(UnsafeMutableRawPointer(mutating: base)) }
        case .unmap:
            return
        case .custom(let queue, let block):
            nonisolated(unsafe) let block = block
            release = { (queue ?? .global()).async { block() } }
        }
        if bytes.isEmpty { release() } else { _releases = [_NoCopyRelease(release)] }
    }

    public var count: Int { _bytes.count }

    public var startIndex: Index { 0 }
    public var endIndex: Index { _bytes.count }
    public func index(before i: Index) -> Index { i - 1 }
    public func index(after i: Index) -> Index { i + 1 }

    public subscript(index: Index) -> UInt8 { _bytes[index] }

    public func makeIterator() -> DispatchData.Iterator { DispatchDataIterator(_bytes: _bytes) }

    /// Calls `body` with a pointer to the bytes, as one contiguous run.
    public func withUnsafeBytes<Result, ContentType>(body: (UnsafePointer<ContentType>) throws -> Result) rethrows -> Result {
        try _bytes.withUnsafeBytes { raw in
            // An empty value still hands over a pointer, as Dispatch's map of empty data does;
            // there is nothing behind it to read.
            let base = raw.baseAddress ?? UnsafeRawPointer(bitPattern: MemoryLayout<ContentType>.alignment)!
            return try body(base.assumingMemoryBound(to: ContentType.self))
        }
    }

    @available(swift, deprecated: 4, message: "Use enumerateBytes(_: (UnsafeBufferPointer<UInt8>, Int, inout Bool) -> Void) instead")
    public func enumerateBytes(block: (_ buffer: UnsafeBufferPointer<UInt8>, _ byteIndex: Int, _ stop: inout Bool) -> Void) {
        enumerateBytes(block)
    }

    /// Calls `block` with each region of bytes and its offset; here, the one region.
    public func enumerateBytes(_ block: (_ buffer: UnsafeBufferPointer<UInt8>, _ byteIndex: Int, _ stop: inout Bool) -> Void) {
        guard !_bytes.isEmpty else { return }
        var stop = false
        _bytes.withUnsafeBufferPointer { block($0, 0, &stop) }
    }

    @available(swift, deprecated: 4, message: "Use append(_: UnsafeRawBufferPointer) instead")
    public mutating func append(_ bytes: UnsafePointer<UInt8>, count: Int) {
        _bytes.append(contentsOf: UnsafeBufferPointer(start: bytes, count: count))
    }

    public mutating func append(_ bytes: UnsafeRawBufferPointer) {
        _bytes.append(contentsOf: bytes)
    }

    public mutating func append(_ other: DispatchData) {
        guard !other._bytes.isEmpty else { return }
        _bytes.append(contentsOf: other._bytes)
        _releases.append(contentsOf: other._releases)
    }

    public mutating func append<SourceType>(_ buffer: UnsafeBufferPointer<SourceType>) {
        _bytes.append(contentsOf: UnsafeRawBufferPointer(buffer))
    }

    private func _copyBytesHelper(to pointer: UnsafeMutableRawPointer, from range: Range<Index>) {
        precondition(range.lowerBound >= 0 && range.upperBound <= _bytes.count, "range out of bounds")
        guard !range.isEmpty else { return }
        _bytes.withUnsafeBytes { raw in
            pointer.copyMemory(from: raw.baseAddress! + range.lowerBound, byteCount: range.count)
        }
    }

    @available(swift, deprecated: 4, message: "Use copyBytes(to: UnsafeMutableRawBufferPointer, count: Int) instead")
    public func copyBytes(to pointer: UnsafeMutablePointer<UInt8>, count: Int) {
        _copyBytesHelper(to: pointer, from: 0..<count)
    }

    /// Copies the first `count` bytes into `pointer`.
    public func copyBytes(to pointer: UnsafeMutableRawBufferPointer, count: Int) {
        precondition(count <= pointer.count, "Buffer too small to copy \(count) bytes")
        guard pointer.count > 0, let base = pointer.baseAddress else { return }
        _copyBytesHelper(to: base, from: 0..<count)
    }

    @available(swift, deprecated: 4, message: "Use copyBytes(to: UnsafeMutableRawBufferPointer, from: Range<Index>) instead")
    public func copyBytes(to pointer: UnsafeMutablePointer<UInt8>, from range: Range<Index>) {
        _copyBytesHelper(to: pointer, from: range)
    }

    /// Copies the bytes in `range` into `pointer`.
    public func copyBytes(to pointer: UnsafeMutableRawBufferPointer, from range: Range<Index>) {
        precondition(range.count <= pointer.count, "Buffer too small to copy \(range.count) bytes")
        guard pointer.count > 0, let base = pointer.baseAddress else { return }
        _copyBytesHelper(to: base, from: range)
    }

    /// Copies as many bytes as `buffer` holds, from the start or from `range`, and answers how
    /// many it copied.
    public func copyBytes<DestinationType>(to buffer: UnsafeMutableBufferPointer<DestinationType>, from range: Range<Index>? = nil) -> Int {
        let capacity = buffer.count * MemoryLayout<DestinationType>.stride
        guard !_bytes.isEmpty, capacity > 0, let base = buffer.baseAddress else { return 0 }
        let copyRange: Range<Index>
        if let range {
            guard !range.isEmpty else { return 0 }
            copyRange = range.lowerBound..<(range.lowerBound + Swift.min(capacity, range.count))
        } else {
            copyRange = 0..<Swift.min(capacity, _bytes.count)
        }
        _copyBytesHelper(to: UnsafeMutableRawPointer(base), from: copyRange)
        return copyRange.count
    }

    /// The bytes in `range`, as a value of their own.
    public func subdata(in range: Range<Index>) -> DispatchData {
        var slice = DispatchData(_bytes: Array(_bytes[range]))
        if !range.isEmpty { slice._releases = _releases }
        return slice
    }

    /// The region holding the byte at `location`, and that region's offset: here the whole value.
    public func region(location: Int) -> (data: DispatchData, offset: Int) {
        (self, 0)
    }
}

public struct DispatchDataIterator: IteratorProtocol, Sequence {
    public typealias Element = UInt8
    private let _bytes: [UInt8]
    private var _position = 0

    fileprivate init(_bytes: [UInt8]) { self._bytes = _bytes }

    public mutating func next() -> DispatchData.Element? {
        guard _position < _bytes.count else { return nil }
        defer { _position += 1 }
        return _bytes[_position]
    }
}
/// Runs a no-copy buffer's release when the last value holding the buffer goes away
/// (`DispatchData` and `Data` keep one when made with `bytesNoCopy`).
final class _NoCopyRelease: @unchecked Sendable {
    private let release: () -> Void
    init(_ release: @escaping () -> Void) { self.release = release }
    deinit { release() }
}
#endif
