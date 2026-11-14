// Apple's `zlib` module for wasm: the stream functions packages call to decode a gzip or zlib
// response body and to write one (RevenueCat's container elements, `inflateInit2_` with
// `MAX_WBITS + 16`), and the one-shot `compress`, `uncompress`, `crc32` and `adler32`, over
// WebFoundationFormats' DEFLATE. A stream gathers its input and decodes once the whole stream has
// arrived, then hands the bytes out as `next_out` has room, so `inflate` called again and again
// with `Z_NO_FLUSH` ends with `Z_STREAM_END` as zlib's does; `deflate` writes everything at
// `Z_FINISH`. Not here: preset dictionaries, `inflateBack`, `gzopen` and the other file functions.
#if os(WASI)
import WebFoundationFormats

public typealias Bytef = UInt8
public typealias uInt = UInt32
public typealias uLong = UInt
public typealias uLongf = uLong
public typealias voidpf = UnsafeMutableRawPointer
public typealias alloc_func = @convention(c) (voidpf?, uInt, uInt) -> voidpf?
public typealias free_func = @convention(c) (voidpf?, voidpf?) -> Void
public typealias z_streamp = UnsafeMutablePointer<z_stream>

public var ZLIB_VERSION: String { "1.2.12" }
public var ZLIB_VERNUM: Int32 { 0x12c0 }

public var Z_OK: Int32 { 0 }
public var Z_STREAM_END: Int32 { 1 }
public var Z_NEED_DICT: Int32 { 2 }
public var Z_ERRNO: Int32 { -1 }
public var Z_STREAM_ERROR: Int32 { -2 }
public var Z_DATA_ERROR: Int32 { -3 }
public var Z_MEM_ERROR: Int32 { -4 }
public var Z_BUF_ERROR: Int32 { -5 }
public var Z_VERSION_ERROR: Int32 { -6 }

public var Z_NO_FLUSH: Int32 { 0 }
public var Z_PARTIAL_FLUSH: Int32 { 1 }
public var Z_SYNC_FLUSH: Int32 { 2 }
public var Z_FULL_FLUSH: Int32 { 3 }
public var Z_FINISH: Int32 { 4 }
public var Z_BLOCK: Int32 { 5 }
public var Z_TREES: Int32 { 6 }

public var Z_NO_COMPRESSION: Int32 { 0 }
public var Z_BEST_SPEED: Int32 { 1 }
public var Z_BEST_COMPRESSION: Int32 { 9 }
public var Z_DEFAULT_COMPRESSION: Int32 { -1 }
public var Z_FILTERED: Int32 { 1 }
public var Z_HUFFMAN_ONLY: Int32 { 2 }
public var Z_RLE: Int32 { 3 }
public var Z_FIXED: Int32 { 4 }
public var Z_DEFAULT_STRATEGY: Int32 { 0 }
public var Z_BINARY: Int32 { 0 }
public var Z_TEXT: Int32 { 1 }
public var Z_UNKNOWN: Int32 { 2 }
public var Z_DEFLATED: Int32 { 8 }
public var Z_NULL: Int32 { 0 }
public var MAX_WBITS: Int32 { 15 }
public var MAX_MEM_LEVEL: Int32 { 9 }

/// The state a stream carries between calls, as zlib's `z_stream`.
public struct z_stream {
    public var next_in: UnsafeMutablePointer<Bytef>!
    public var avail_in: uInt
    public var total_in: uLong
    public var next_out: UnsafeMutablePointer<Bytef>!
    public var avail_out: uInt
    public var total_out: uLong
    public var msg: UnsafeMutablePointer<CChar>!
    public var state: OpaquePointer!
    public var zalloc: alloc_func!
    public var zfree: free_func!
    public var opaque: voidpf!
    public var data_type: Int32
    public var adler: uLong
    public var reserved: uLong

    public init() {
        next_in = nil; avail_in = 0; total_in = 0
        next_out = nil; avail_out = 0; total_out = 0
        msg = nil; state = nil; zalloc = nil; zfree = nil; opaque = nil
        data_type = 0; adler = 0; reserved = 0
    }
}

/// What a stream holds: its input so far, and its output not yet handed out.
private final class _Stream {
    let inflating: Bool
    let wrapper: _ZlibWrapper
    var input: [UInt8] = []
    var pending: [UInt8] = []
    var sent = 0
    var done = false

    init(inflating: Bool, wrapper: _ZlibWrapper) {
        self.inflating = inflating
        self.wrapper = wrapper
    }

    static func of(_ strm: z_streamp?) -> _Stream? {
        guard let pointer = strm?.pointee.state else { return nil }
        return Unmanaged<_Stream>.fromOpaque(UnsafeRawPointer(pointer)).takeUnretainedValue()
    }
}

private func begin(_ strm: z_streamp?, inflating: Bool, windowBits: Int32, version: UnsafePointer<CChar>?) -> Int32 {
    guard let strm else { return Z_STREAM_ERROR }
    guard let version, version.pointee == CChar(UInt8(ascii: "1")) else { return Z_VERSION_ERROR }
    guard let wrapper = _ZlibWrapper(windowBits: windowBits), inflating || wrapper != .automatic else { return Z_STREAM_ERROR }
    let stream = _Stream(inflating: inflating, wrapper: wrapper)
    strm.pointee.state = OpaquePointer(Unmanaged.passRetained(stream).toOpaque())
    strm.pointee.total_in = 0
    strm.pointee.total_out = 0
    strm.pointee.msg = nil
    strm.pointee.adler = wrapper == .gzip ? 0 : 1
    return Z_OK
}

private func end(_ strm: z_streamp?) -> Int32 {
    guard let strm, let pointer = strm.pointee.state else { return Z_STREAM_ERROR }
    Unmanaged<_Stream>.fromOpaque(UnsafeRawPointer(pointer)).release()
    strm.pointee.state = nil
    return Z_OK
}

/// Takes all of `avail_in`; returns how many bytes that was.
private func gather(_ strm: z_streamp, into stream: _Stream) -> Int {
    let count = Int(strm.pointee.avail_in)
    guard count > 0, let next = strm.pointee.next_in else { return 0 }
    stream.input += UnsafeBufferPointer(start: next, count: count)
    strm.pointee.next_in = next + count
    strm.pointee.avail_in = 0
    strm.pointee.total_in += uLong(count)
    return count
}

/// Hands out as much of the pending output as `avail_out` takes; returns how much.
private func emit(_ strm: z_streamp, from stream: _Stream) -> Int {
    let count = min(Int(strm.pointee.avail_out), stream.pending.count - stream.sent)
    guard count > 0, let next = strm.pointee.next_out else { return 0 }
    stream.pending.withUnsafeBufferPointer { source in
        next.update(from: source.baseAddress! + stream.sent, count: count)
    }
    stream.sent += count
    strm.pointee.next_out = next + count
    strm.pointee.avail_out -= uInt(count)
    strm.pointee.total_out += uLong(count)
    return count
}

public func inflateInit_(_ strm: z_streamp!, _ version: UnsafePointer<CChar>!, _ stream_size: Int32) -> Int32 {
    begin(strm, inflating: true, windowBits: MAX_WBITS, version: version)
}

public func inflateInit2_(_ strm: z_streamp!, _ windowBits: Int32, _ version: UnsafePointer<CChar>!, _ stream_size: Int32) -> Int32 {
    begin(strm, inflating: true, windowBits: windowBits, version: version)
}

/// Decodes what has arrived once it holds the whole stream; hands the bytes out as there is room.
public func inflate(_ strm: z_streamp!, _ flush: Int32) -> Int32 {
    guard let strm, let stream = _Stream.of(strm), stream.inflating else { return Z_STREAM_ERROR }
    if !stream.done {
        let added = gather(strm, into: stream)
        do {
            let decoded = try _zlibDecode(stream.input, wrapper: stream.wrapper)
            stream.done = true
            stream.pending = decoded.output
            // Bytes after the stream stay unread, as zlib leaves them in `avail_in`.
            let unread = stream.input.count - decoded.consumed
            if unread > 0, unread <= added, let next = strm.pointee.next_in {
                strm.pointee.next_in = next - unread
                strm.pointee.avail_in = uInt(unread)
                strm.pointee.total_in -= uLong(unread)
            }
            let check = stream.wrapper == .gzip ? _zlibCRC32(0, decoded.output) : _zlibAdler32(1, decoded.output)
            strm.pointee.adler = uLong(check)
        } catch .truncated {
            // More input is needed; with none given, or none to come, no progress is possible.
            return added > 0 && flush != Z_FINISH ? Z_OK : Z_BUF_ERROR
        } catch .needsDictionary {
            return Z_NEED_DICT
        } catch {
            return Z_DATA_ERROR
        }
    }
    let sent = emit(strm, from: stream)
    if stream.sent == stream.pending.count { return Z_STREAM_END }
    return sent > 0 ? Z_OK : Z_BUF_ERROR
}

public func inflateEnd(_ strm: z_streamp!) -> Int32 { end(strm) }

public func inflateReset(_ strm: z_streamp!) -> Int32 {
    guard let strm, let stream = _Stream.of(strm) else { return Z_STREAM_ERROR }
    stream.input = []; stream.pending = []; stream.sent = 0; stream.done = false
    strm.pointee.total_in = 0
    strm.pointee.total_out = 0
    return Z_OK
}

public func deflateInit_(_ strm: z_streamp!, _ level: Int32, _ version: UnsafePointer<CChar>!, _ stream_size: Int32) -> Int32 {
    guard (-1...9).contains(level) else { return Z_STREAM_ERROR }
    return begin(strm, inflating: false, windowBits: MAX_WBITS, version: version)
}

public func deflateInit2_(_ strm: z_streamp!, _ level: Int32, _ method: Int32, _ windowBits: Int32, _ memLevel: Int32,
                          _ strategy: Int32, _ version: UnsafePointer<CChar>!, _ stream_size: Int32) -> Int32 {
    guard (-1...9).contains(level), method == Z_DEFLATED, (1...9).contains(memLevel) else { return Z_STREAM_ERROR }
    return begin(strm, inflating: false, windowBits: windowBits, version: version)
}

/// Gathers the input; at `Z_FINISH` writes the whole stream and hands it out as there is room.
public func deflate(_ strm: z_streamp!, _ flush: Int32) -> Int32 {
    guard let strm, let stream = _Stream.of(strm), !stream.inflating else { return Z_STREAM_ERROR }
    let added = gather(strm, into: stream)
    if !stream.done {
        guard flush == Z_FINISH else { return added > 0 || flush != Z_NO_FLUSH ? Z_OK : Z_BUF_ERROR }
        stream.pending = _zlibEncode(stream.input, wrapper: stream.wrapper)
        stream.done = true
        strm.pointee.adler = uLong(stream.wrapper == .gzip ? _zlibCRC32(0, stream.input) : _zlibAdler32(1, stream.input))
    }
    let sent = emit(strm, from: stream)
    if stream.sent == stream.pending.count { return Z_STREAM_END }
    return sent > 0 ? Z_OK : Z_BUF_ERROR
}

public func deflateEnd(_ strm: z_streamp!) -> Int32 { end(strm) }

public func deflateReset(_ strm: z_streamp!) -> Int32 {
    guard let strm, let stream = _Stream.of(strm) else { return Z_STREAM_ERROR }
    stream.input = []; stream.pending = []; stream.sent = 0; stream.done = false
    strm.pointee.total_in = 0
    strm.pointee.total_out = 0
    return Z_OK
}

/// The most bytes `compress` can write for `sourceLen` bytes.
public func compressBound(_ sourceLen: uLong) -> uLong {
    sourceLen + sourceLen / 8 + 64
}

public func deflateBound(_ strm: z_streamp!, _ sourceLen: uLong) -> uLong {
    compressBound(sourceLen) + 18
}

public func compress2(_ dest: UnsafeMutablePointer<Bytef>!, _ destLen: UnsafeMutablePointer<uLongf>!, _ source: UnsafePointer<Bytef>!,
                      _ sourceLen: uLong, _ level: Int32) -> Int32 {
    guard let dest, let destLen else { return Z_STREAM_ERROR }
    let input = source.map { Array(UnsafeBufferPointer(start: $0, count: Int(sourceLen))) } ?? []
    let output = _zlibEncode(input, wrapper: .zlib)
    guard output.count <= Int(destLen.pointee) else { return Z_BUF_ERROR }
    output.withUnsafeBufferPointer { dest.update(from: $0.baseAddress!, count: output.count) }
    destLen.pointee = uLongf(output.count)
    return Z_OK
}

public func compress(_ dest: UnsafeMutablePointer<Bytef>!, _ destLen: UnsafeMutablePointer<uLongf>!, _ source: UnsafePointer<Bytef>!,
                     _ sourceLen: uLong) -> Int32 {
    compress2(dest, destLen, source, sourceLen, Z_DEFAULT_COMPRESSION)
}

public func uncompress(_ dest: UnsafeMutablePointer<Bytef>!, _ destLen: UnsafeMutablePointer<uLongf>!, _ source: UnsafePointer<Bytef>!,
                       _ sourceLen: uLong) -> Int32 {
    guard let dest, let destLen else { return Z_STREAM_ERROR }
    let input = source.map { Array(UnsafeBufferPointer(start: $0, count: Int(sourceLen))) } ?? []
    let output: [UInt8]
    do {
        output = try _zlibDecode(input, wrapper: .zlib).output
    } catch .truncated {
        return Z_BUF_ERROR
    } catch .needsDictionary {
        return Z_NEED_DICT
    } catch {
        return Z_DATA_ERROR
    }
    guard output.count <= Int(destLen.pointee) else { return Z_BUF_ERROR }
    output.withUnsafeBufferPointer { if let base = $0.baseAddress { dest.update(from: base, count: output.count) } }
    destLen.pointee = uLongf(output.count)
    return Z_OK
}

public func crc32(_ crc: uLong, _ buf: UnsafePointer<Bytef>!, _ len: uInt) -> uLong {
    guard let buf else { return 0 }
    return uLong(_zlibCRC32(UInt32(truncatingIfNeeded: crc), UnsafeBufferPointer(start: buf, count: Int(len))))
}

public func adler32(_ adler: uLong, _ buf: UnsafePointer<Bytef>!, _ len: uInt) -> uLong {
    guard let buf else { return 1 }
    return uLong(_zlibAdler32(UInt32(truncatingIfNeeded: adler), UnsafeBufferPointer(start: buf, count: Int(len))))
}

public func zlibVersion() -> UnsafePointer<CChar>! {
    UnsafePointer(_version)
}

nonisolated(unsafe) private let _version: UnsafeMutablePointer<CChar> = {
    let bytes = Array("1.2.12".utf8CString)
    let pointer = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count)
    pointer.initialize(from: bytes, count: bytes.count)
    return pointer
}()
#endif
