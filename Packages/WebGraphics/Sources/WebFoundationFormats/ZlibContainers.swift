// The containers zlib wraps DEFLATE in: the zlib format (RFC 1950: a two-byte header and an
// Adler-32 trailer) and gzip (RFC 1952: a header, then a CRC-32 and the size), with the checksums,
// for the `zlib` shadow's `inflate` and `deflate` (packages that decode gzip responses the way
// RevenueCat does) and the `Compression` shadow's filters. Raw DEFLATE is Deflate.swift's.
// Not limited to wasm, so the host tests hold these bytes to Apple's zlib.

/// How a DEFLATE stream is wrapped, as zlib's `windowBits` says: negative raw, 8 to 15 zlib,
/// plus 16 gzip, plus 32 either (by the first bytes).
public enum _ZlibWrapper: Sendable, Equatable {
    case raw, zlib, gzip, automatic

    /// The wrapper `windowBits` asks for, or nil for a value zlib refuses.
    public init?(windowBits: Int32) {
        switch windowBits {
        case -15 ... -8: self = .raw
        case 8...15: self = .zlib
        case 24...31: self = .gzip
        case 40...47: self = .automatic
        default: return nil
        }
    }
}

/// Why wrapped DEFLATE could not be decoded.
public enum _ZlibDecodeError: Error, Sendable, Equatable {
    /// The bytes stopped before the stream's end: more may follow.
    case truncated
    /// The bytes are not such a stream, or a checksum does not match.
    case invalid
    /// A zlib stream that needs a preset dictionary.
    case needsDictionary
}

/// What decoding wrapped DEFLATE gave: the bytes, and how many of the input it read (the rest
/// follows the stream).
public struct _ZlibDecoded: Sendable {
    public let output: [UInt8]
    public let consumed: Int
}

/// The CRC-32 of `bytes`, continued from `crc` (0 to start), as zlib's `crc32` computes it.
public func _zlibCRC32<C: Collection>(_ crc: UInt32, _ bytes: C) -> UInt32 where C.Element == UInt8 {
    var value = ~crc
    for byte in bytes { value = crcTable[Int((value ^ UInt32(byte)) & 0xFF)] ^ (value >> 8) }
    return ~value
}

/// The Adler-32 of `bytes`, continued from `adler` (1 to start), as zlib's `adler32` computes it.
public func _zlibAdler32<C: Collection>(_ adler: UInt32, _ bytes: C) -> UInt32 where C.Element == UInt8 {
    var a = adler & 0xFFFF, b = adler >> 16
    var pending = 0
    for byte in bytes {
        a += UInt32(byte)
        b += a
        pending += 1
        // Reduce before the sums can overflow 32 bits (zlib's NMAX).
        if pending == 5552 {
            a %= 65521
            b %= 65521
            pending = 0
        }
    }
    return (b % 65521) << 16 | (a % 65521)
}

private let crcTable: [UInt32] = (0..<256).map { n -> UInt32 in
    var c = UInt32(n)
    for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
    return c
}

/// `source` compressed as DEFLATE in `wrapper` (`.automatic` writes zlib).
public func _zlibEncode(_ source: [UInt8], wrapper: _ZlibWrapper) -> [UInt8] {
    let body = _deflate(source)
    switch wrapper {
    case .raw:
        return body
    case .zlib, .automatic:
        let adler = _zlibAdler32(1, source)
        return [0x78, 0x9C] + body + [UInt8(adler >> 24), UInt8(adler >> 16 & 0xFF), UInt8(adler >> 8 & 0xFF), UInt8(adler & 0xFF)]
    case .gzip:
        let crc = _zlibCRC32(0, source), size = UInt32(truncatingIfNeeded: source.count)
        // No name, no time, the default level, an unknown system.
        let header: [UInt8] = [0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 0xFF]
        return header + body + littleEndian(crc) + littleEndian(size)
    }
}

/// The bytes of the wrapped DEFLATE stream at the start of `source`: throws `.truncated` when
/// `source` stops first, `.invalid` when it is not such a stream or a checksum is wrong.
public func _zlibDecode(_ source: [UInt8], wrapper: _ZlibWrapper) throws(_ZlibDecodeError) -> _ZlibDecoded {
    switch wrapper {
    case .raw:
        let (output, end) = try inflate(source, from: 0)
        return _ZlibDecoded(output: output, consumed: end)
    case .zlib:
        return try decodeZlib(source)
    case .gzip:
        return try decodeGzip(source)
    case .automatic:
        guard !source.isEmpty else { throw .truncated }
        if source[0] == 0x1F { return try decodeGzip(source) }
        return try decodeZlib(source)
    }
}

private func littleEndian(_ value: UInt32) -> [UInt8] {
    [UInt8(value & 0xFF), UInt8(value >> 8 & 0xFF), UInt8(value >> 16 & 0xFF), UInt8(value >> 24)]
}

private func inflate(_ source: [UInt8], from start: Int) throws(_ZlibDecodeError) -> ([UInt8], Int) {
    var end = 0
    do {
        let output = try _inflate(source, from: start, consumed: &end)
        return (output, end)
    } catch let error as _DeflateError {
        throw error.truncated ? .truncated : .invalid
    } catch {
        throw .invalid
    }
}

private func decodeZlib(_ source: [UInt8]) throws(_ZlibDecodeError) -> _ZlibDecoded {
    guard source.count >= 2 else { throw .truncated }
    let cmf = Int(source[0]), flg = Int(source[1])
    guard cmf & 0x0F == 8, cmf >> 4 <= 7, (cmf << 8 | flg) % 31 == 0 else { throw .invalid }
    guard flg & 0x20 == 0 else { throw .needsDictionary }
    let (output, end) = try inflate(source, from: 2)
    guard source.count >= end + 4 else { throw .truncated }
    let stored = UInt32(source[end]) << 24 | UInt32(source[end + 1]) << 16 | UInt32(source[end + 2]) << 8 | UInt32(source[end + 3])
    guard stored == _zlibAdler32(1, output) else { throw .invalid }
    return _ZlibDecoded(output: output, consumed: end + 4)
}

private func decodeGzip(_ source: [UInt8]) throws(_ZlibDecodeError) -> _ZlibDecoded {
    guard source.count >= 10 else { throw .truncated }
    guard source[0] == 0x1F, source[1] == 0x8B, source[2] == 8 else { throw .invalid }
    let flags = source[3]
    guard flags & 0xE0 == 0 else { throw .invalid }
    var p = 10
    if flags & 4 != 0 {   // FEXTRA
        guard source.count >= p + 2 else { throw .truncated }
        p += 2 + (Int(source[p]) | Int(source[p + 1]) << 8)
    }
    for flag in [UInt8(8), 16] where flags & flag != 0 {   // FNAME, FCOMMENT: zero-terminated
        while true {
            guard p < source.count else { throw .truncated }
            p += 1
            if source[p - 1] == 0 { break }
        }
    }
    if flags & 2 != 0 { p += 2 }   // FHCRC
    guard p <= source.count else { throw .truncated }
    let (output, end) = try inflate(source, from: p)
    guard source.count >= end + 8 else { throw .truncated }
    func le32(_ at: Int) -> UInt32 {
        UInt32(source[at]) | UInt32(source[at + 1]) << 8 | UInt32(source[at + 2]) << 16 | UInt32(source[at + 3]) << 24
    }
    guard le32(end) == _zlibCRC32(0, output), le32(end + 4) == UInt32(truncatingIfNeeded: output.count) else {
        throw .invalid
    }
    return _ZlibDecoded(output: output, consumed: end + 8)
}
