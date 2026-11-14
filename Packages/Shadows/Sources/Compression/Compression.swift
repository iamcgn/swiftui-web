// Apple's `Compression` module for wasm: the algorithms, the Swift filters (`InputFilter`,
// `OutputFilter`) and the buffer functions (`compression_encode_buffer`), over the formats
// WebFoundationFormats writes and reads for `NSData.compressed(using:)`: zlib (raw DEFLATE), LZ4,
// LZFSE and LZMA, byte-compatible with Apple's as far as those go (Compression.swift there).
// Brotli and LZBITMAP have no coder here: their constants make no `Algorithm`
// (`Algorithm(rawValue: COMPRESSION_BROTLI)` is nil, as on a runtime without them, so RevenueCat
// asks its server for gzip), and a filter or buffer call naming them fails. A filter gathers its
// input and codes it whole at the end, then hands out the result in the lengths asked for; the
// `compression_stream` functions are not here.
#if os(WASI)
import WebFoundation
import WebFoundationFormats

/// An algorithm's C constant.
public struct compression_algorithm: RawRepresentable, Hashable, Sendable {
    public var rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public init(_ rawValue: UInt32) { self.rawValue = rawValue }
}

public var COMPRESSION_LZ4: compression_algorithm { compression_algorithm(0x100) }
public var COMPRESSION_LZ4_RAW: compression_algorithm { compression_algorithm(0x101) }
public var COMPRESSION_ZLIB: compression_algorithm { compression_algorithm(0x205) }
public var COMPRESSION_LZMA: compression_algorithm { compression_algorithm(0x306) }
public var COMPRESSION_LZBITMAP: compression_algorithm { compression_algorithm(0x702) }
public var COMPRESSION_LZFSE: compression_algorithm { compression_algorithm(0x801) }
public var COMPRESSION_BROTLI: compression_algorithm { compression_algorithm(0xB02) }

/// The algorithms the filters code with.
public enum Algorithm: CaseIterable, RawRepresentable, Sendable {
    case lz4, zlib, lzma, lzfse, brotli, lzbitmap

    /// The algorithm for a C constant; nil for one with no coder here (Brotli, LZBITMAP).
    public init?(rawValue: compression_algorithm) {
        switch rawValue.rawValue {
        case 0x100: self = .lz4
        case 0x205: self = .zlib
        case 0x306: self = .lzma
        case 0x801: self = .lzfse
        default: return nil
        }
    }

    public var rawValue: compression_algorithm {
        switch self {
        case .lz4: COMPRESSION_LZ4
        case .zlib: COMPRESSION_ZLIB
        case .lzma: COMPRESSION_LZMA
        case .lzfse: COMPRESSION_LZFSE
        case .brotli: COMPRESSION_BROTLI
        case .lzbitmap: COMPRESSION_LZBITMAP
        }
    }

    public static var allCases: [Algorithm] { [.lz4, .zlib, .lzma, .lzfse] }

    var format: _CompressionFormat? {
        switch self {
        case .lz4: .lz4
        case .zlib: .zlib
        case .lzma: .lzma
        case .lzfse: .lzfse
        case .brotli, .lzbitmap: nil
        }
    }
}

public enum FilterOperation: Sendable {
    case compress, decompress
}

public enum FilterError: Error, Sendable {
    /// The filter cannot work: an algorithm with no coder here, or a call after the end.
    case invalidState
    /// The bytes are not what the algorithm writes.
    case invalidData
}

/// `bytes` compressed or decompressed with `format`.
private func code(_ bytes: [UInt8], _ operation: FilterOperation, _ format: _CompressionFormat) throws -> [UInt8] {
    switch operation {
    case .compress:
        return _compress(bytes, format)
    case .decompress:
        do { return try _decompress(bytes, format) } catch { throw FilterError.invalidData }
    }
}

/// Reads bytes through an algorithm: what `readingFrom` supplies, compressed or decompressed.
/// `D` is any collection of bytes (`Data`, `[UInt8]`, a slice), as Apple's `DataProtocol` is.
public class InputFilter<D: Collection> where D.Element == UInt8 {
    private let operation: FilterOperation
    private let algorithm: _CompressionFormat
    private let read: (Int) throws -> D?
    private let bufferCapacity: Int
    private var output: [UInt8]?
    private var offset = 0

    public init(_ operation: FilterOperation, using algorithm: Algorithm, bufferCapacity: Int = 65536,
                readingFrom readFunc: @escaping (Int) throws -> D?) throws {
        guard let format = algorithm.format, bufferCapacity > 0 else { throw FilterError.invalidState }
        self.operation = operation
        self.algorithm = format
        self.read = readFunc
        self.bufferCapacity = bufferCapacity
    }

    /// Up to `count` bytes of the result, or nil once it has all been read.
    public func readData(ofLength count: Int) throws -> Data? {
        if output == nil {
            var input: [UInt8] = []
            while let chunk = try read(bufferCapacity), !chunk.isEmpty { input += chunk }
            output = try code(input, operation, algorithm)
        }
        guard let output, offset < output.count, count > 0 else { return nil }
        let end = min(offset + count, output.count)
        defer { offset = end }
        return Data(output[offset..<end])
    }
}

/// Writes bytes through an algorithm: what is written goes to `writingTo` compressed or
/// decompressed, then nil once the filter is finalized.
public class OutputFilter {
    private let operation: FilterOperation
    private let algorithm: _CompressionFormat
    private let write: (Data?) throws -> Void
    private let bufferCapacity: Int
    private var input: [UInt8] = []
    private var finished = false

    public init(_ operation: FilterOperation, using algorithm: Algorithm, bufferCapacity: Int = 65536,
                writingTo writeFunc: @escaping (Data?) throws -> Void) throws {
        guard let format = algorithm.format, bufferCapacity > 0 else { throw FilterError.invalidState }
        self.operation = operation
        self.algorithm = format
        self.write = writeFunc
        self.bufferCapacity = bufferCapacity
    }

    /// Adds `data`; nil, or empty data, finalizes the filter.
    public func write<D: Collection>(_ data: D?) throws where D.Element == UInt8 {
        guard !finished else { throw FilterError.invalidState }
        guard let data, !data.isEmpty else { return try finalize() }
        input += data
    }

    /// Codes what was written and hands it on, in pieces of at most the buffer's capacity.
    public func finalize() throws {
        guard !finished else { return }
        finished = true
        let output = try code(input, operation, algorithm)
        var start = 0
        while start < output.count {
            let end = min(start + bufferCapacity, output.count)
            try write(Data(output[start..<end]))
            start = end
        }
        try write(nil)
    }
}

// MARK: - Buffer functions

/// Compresses `src_size` bytes into `dst_buffer`; returns the size written, or 0 when it does
/// not fit or the algorithm has no coder here.
public func compression_encode_buffer(_ dst_buffer: UnsafeMutablePointer<UInt8>, _ dst_size: Int,
                                      _ src_buffer: UnsafePointer<UInt8>, _ src_size: Int,
                                      _ scratch_buffer: UnsafeMutableRawPointer?, _ algorithm: compression_algorithm) -> Int {
    transfer(dst_buffer, dst_size, src_buffer, src_size, .compress, algorithm)
}

/// Decompresses `src_size` bytes into `dst_buffer`; returns the size written (at most
/// `dst_size`: a longer result is cut there, as Apple's is), or 0 when the bytes do not decode.
public func compression_decode_buffer(_ dst_buffer: UnsafeMutablePointer<UInt8>, _ dst_size: Int,
                                      _ src_buffer: UnsafePointer<UInt8>, _ src_size: Int,
                                      _ scratch_buffer: UnsafeMutableRawPointer?, _ algorithm: compression_algorithm) -> Int {
    transfer(dst_buffer, dst_size, src_buffer, src_size, .decompress, algorithm)
}

public func compression_encode_scratch_buffer_size(_ algorithm: compression_algorithm) -> Int { 0 }
public func compression_decode_scratch_buffer_size(_ algorithm: compression_algorithm) -> Int { 0 }

private func transfer(_ dst: UnsafeMutablePointer<UInt8>, _ dstSize: Int, _ src: UnsafePointer<UInt8>, _ srcSize: Int,
                      _ operation: FilterOperation, _ algorithm: compression_algorithm) -> Int {
    guard let format = Algorithm(rawValue: algorithm)?.format, dstSize > 0, srcSize >= 0,
          let output = try? code(Array(UnsafeBufferPointer(start: src, count: srcSize)), operation, format) else { return 0 }
    // A compressed result that does not fit is a failure; a decompressed one is cut to fit.
    if operation == .compress, output.count > dstSize { return 0 }
    let count = min(output.count, dstSize)
    output.withUnsafeBufferPointer { if let base = $0.baseAddress { dst.update(from: base, count: count) } }
    return count
}
#endif
