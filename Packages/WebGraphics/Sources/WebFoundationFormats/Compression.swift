// The byte formats `NSData.compressed(using:)` writes and `decompressed(using:)` reads, as Apple's
// Compression framework lays them out, so bytes compressed in the page open on an Apple device or
// server and the other way round:
// - zlib: raw DEFLATE (Deflate.swift).
// - lz4: Apple's LZ4 frame, blocks of "bv41", the decoded and encoded sizes and an LZ4 block,
//   ended by "bv4$". Written with matches found by a hash of the next four bytes; read whole.
// - lzfse: LZFSE's container. Written as LZVN blocks ("bvxn"), or stored ("bvx-") when that is
//   smaller; read are both. The FSE blocks ("bvx1", "bvx2") Apple writes for inputs from about
//   4 KB up are not read: decompressing those throws.
// - lzma: xz with one LZMA2 block of stored chunks and a CRC32 check, which every xz reader takes
//   but which does not shrink the bytes. Read are such stored chunks; LZMA-coded chunks, which
//   Apple writes, throw.
// Not limited to wasm, so the host tests check these bytes against Apple's own coders on macOS.

/// Why bytes could not be decompressed.
struct _CompressionError: Error {}

/// The formats, one for each of `NSData.CompressionAlgorithm`'s cases (and the `Compression`
/// shadow's algorithms).
public enum _CompressionFormat: CaseIterable, Sendable {
    case zlib, lz4, lzfse, lzma
}

/// `source` compressed in `format`.
public func _compress(_ source: [UInt8], _ format: _CompressionFormat) -> [UInt8] {
    switch format {
    case .zlib: _deflate(source)
    case .lz4: lz4Frame(source)
    case .lzfse: lzfseFrame(source)
    case .lzma: xzStored(source)
    }
}

/// `source` decompressed from `format`, or throws when it is not a whole stream this reads.
public func _decompress(_ source: [UInt8], _ format: _CompressionFormat) throws -> [UInt8] {
    switch format {
    case .zlib: try _inflate(source)
    case .lz4: try readLZ4Frame(source)
    case .lzfse: try readLZFSEFrame(source)
    case .lzma: try readXZ(source)
    }
}

// MARK: - Shared

private func appendLE32(_ out: inout [UInt8], _ value: some BinaryInteger) {
    for shift in stride(from: 0, to: 32, by: 8) { out.append(UInt8(truncatingIfNeeded: value >> shift)) }
}

private func le32(_ bytes: [UInt8], _ at: Int) throws -> Int {
    guard at >= 0, at + 4 <= bytes.count else { throw _CompressionError() }
    return Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24
}

/// The four bytes at `at` as a 32-bit value, for checksums (an `Int` is 32 bits on wasm).
private func le32u(_ bytes: [UInt8], _ at: Int) throws -> UInt32 {
    UInt32(truncatingIfNeeded: try le32(bytes, at))
}

private func magic(_ text: String) -> Int {
    let bytes = Array(text.utf8)
    return Int(bytes[0]) | Int(bytes[1]) << 8 | Int(bytes[2]) << 16 | Int(bytes[3]) << 24
}

/// Copies `length` bytes from `distance` back, byte by byte, so a copy may overlap what it writes.
private func copyMatch(_ out: inout [UInt8], distance: Int, length: Int) throws {
    guard distance > 0, distance <= out.count else { throw _CompressionError() }
    for _ in 0..<length { out.append(out[out.count - distance]) }
}

/// Repeats of at least four bytes, found greedily with a hash of the next four bytes, for the LZ4
/// and LZVN writers: each match as (start, distance, length), in order.
private func findMatches(_ source: [UInt8], from start: Int, lastStart: Int, lastEnd: Int,
                         maxDistance: Int) -> [(start: Int, distance: Int, length: Int)] {
    var matches: [(start: Int, distance: Int, length: Int)] = []
    var table = [Int](repeating: -1, count: 1 << 14)
    func word(_ i: Int) -> UInt32 {
        UInt32(source[i]) | UInt32(source[i + 1]) << 8 | UInt32(source[i + 2]) << 16 | UInt32(source[i + 3]) << 24
    }
    var i = start
    while i < lastStart {
        let value = word(i)
        let slot = Int((value &* 2_654_435_761) >> 18)
        let candidate = table[slot]
        table[slot] = i
        if candidate >= start, i - candidate <= maxDistance, word(candidate) == value {
            var length = 4
            while i + length < lastEnd, source[candidate + length] == source[i + length] { length += 1 }
            matches.append((i, i - candidate, length))
            i += length
        } else {
            i += 1
        }
    }
    return matches
}

// MARK: - LZ4

private let lz4Block = magic("bv41"), lz4Stored = magic("bv4-"), lz4End = magic("bv4$")

private func lz4Frame(_ source: [UInt8]) -> [UInt8] {
    var out: [UInt8] = []
    var start = 0
    while start < source.count {
        let end = min(source.count, start + 65536)
        let block = lz4Encode(source, start, end)
        appendLE32(&out, lz4Block)
        appendLE32(&out, end - start)
        appendLE32(&out, block.count)
        out += block
        start = end
    }
    appendLE32(&out, lz4End)
    return out
}

/// One LZ4 block: a match starts at least 12 bytes before the end, and the last 5 bytes are
/// literals, as LZ4's format asks.
private func lz4Encode(_ source: [UInt8], _ start: Int, _ end: Int) -> [UInt8] {
    var out: [UInt8] = []
    func count(_ value: Int) {
        var rest = value - 15
        while rest >= 255 { out.append(255); rest -= 255 }
        out.append(UInt8(rest))
    }
    func sequence(_ literals: Range<Int>, _ match: (distance: Int, length: Int)?) {
        let literalCount = literals.count, matchCode = (match?.length ?? 4) - 4
        out.append(UInt8(min(literalCount, 15) << 4 | (match == nil ? 0 : min(matchCode, 15))))
        if literalCount >= 15 { count(literalCount) }
        out += source[literals]
        guard let match else { return }
        out.append(UInt8(match.distance & 0xFF))
        out.append(UInt8(match.distance >> 8))
        if matchCode >= 15 { count(matchCode) }
    }
    var anchor = start
    for match in findMatches(source, from: start, lastStart: end - 12, lastEnd: end - 5, maxDistance: 65535) {
        sequence(anchor..<match.start, (match.distance, match.length))
        anchor = match.start + match.length
    }
    sequence(anchor..<end, nil)
    return out
}

private func readLZ4Frame(_ source: [UInt8]) throws -> [UInt8] {
    var out: [UInt8] = []
    var p = 0
    while true {
        let tag = try le32(source, p)
        switch tag {
        case lz4End:
            return out
        case lz4Stored:
            let size = try le32(source, p + 4)
            p += 8
            guard p + size <= source.count else { throw _CompressionError() }
            out += source[p..<(p + size)]
            p += size
        case lz4Block:
            let size = try le32(source, p + 4), payload = try le32(source, p + 8)
            p += 12
            guard p + payload <= source.count else { throw _CompressionError() }
            let before = out.count
            try lz4Decode(source, p, p + payload, &out)
            guard out.count - before == size else { throw _CompressionError() }
            p += payload
        default:
            throw _CompressionError()
        }
    }
}

private func lz4Decode(_ source: [UInt8], _ start: Int, _ end: Int, _ out: inout [UInt8]) throws {
    var p = start
    func byte() throws -> Int {
        guard p < end else { throw _CompressionError() }
        p += 1
        return Int(source[p - 1])
    }
    func count(_ nibble: Int) throws -> Int {
        guard nibble == 15 else { return nibble }
        var total = 15, next = 255
        while next == 255 { next = try byte(); total += next }
        return total
    }
    while p < end {
        let token = try byte()
        let literals = try count(token >> 4)
        guard p + literals <= end else { throw _CompressionError() }
        out += source[p..<(p + literals)]
        p += literals
        if p == end { return }
        let distance = try byte() | (try byte()) << 8
        let length = try count(token & 15) + 4
        try copyMatch(&out, distance: distance, length: length)
    }
}

// MARK: - LZFSE

private let lzfseStored = magic("bvx-"), lzfseLZVN = magic("bvxn"), lzfseEnd = magic("bvx$")

private func lzfseFrame(_ source: [UInt8]) -> [UInt8] {
    var out: [UInt8] = []
    if !source.isEmpty {
        let payload = lzvnEncode(source)
        if payload.count + 12 < source.count + 8 {
            appendLE32(&out, lzfseLZVN)
            appendLE32(&out, source.count)
            appendLE32(&out, payload.count)
            out += payload
        } else {
            appendLE32(&out, lzfseStored)
            appendLE32(&out, source.count)
            out += source
        }
    }
    appendLE32(&out, lzfseEnd)
    return out
}

/// LZVN: literals as `sml_l` and `lrg_l` opcodes, each match as `lrg_d` (a 16-bit distance and up
/// to 10 bytes) and the rest of it as `sml_m` and `lrg_m` (the same distance again), then `eos`
/// and its seven bytes of padding.
private func lzvnEncode(_ source: [UInt8]) -> [UInt8] {
    var out: [UInt8] = []
    func literals(_ range: Range<Int>) {
        var start = range.lowerBound
        while start < range.upperBound {
            let n = min(range.upperBound - start, 271)
            if n < 16 { out.append(0xE0 | UInt8(n)) } else { out.append(0xE0); out.append(UInt8(n - 16)) }
            out += source[start..<(start + n)]
            start += n
        }
    }
    var anchor = 0
    for match in findMatches(source, from: 0, lastStart: source.count - 3, lastEnd: source.count, maxDistance: 65535) {
        literals(anchor..<match.start)
        let first = min(match.length, 10)
        out.append(UInt8((first - 3) << 3 | 7))
        out.append(UInt8(match.distance & 0xFF))
        out.append(UInt8(match.distance >> 8))
        var rest = match.length - first
        while rest > 0 {
            let n = min(rest, 271)
            if n < 16 { out.append(0xF0 | UInt8(n)) } else { out.append(0xF0); out.append(UInt8(n - 16)) }
            rest -= n
        }
        anchor = match.start + match.length
    }
    literals(anchor..<source.count)
    out += [0x06, 0, 0, 0, 0, 0, 0, 0]
    return out
}

private func readLZFSEFrame(_ source: [UInt8]) throws -> [UInt8] {
    var out: [UInt8] = []
    var p = 0
    while true {
        let tag = try le32(source, p)
        switch tag {
        case lzfseEnd:
            return out
        case lzfseStored:
            let size = try le32(source, p + 4)
            p += 8
            guard p + size <= source.count else { throw _CompressionError() }
            out += source[p..<(p + size)]
            p += size
        case lzfseLZVN:
            let size = try le32(source, p + 4), payload = try le32(source, p + 8)
            p += 12
            guard p + payload <= source.count else { throw _CompressionError() }
            let before = out.count
            try lzvnDecode(source, p, p + payload, &out)
            guard out.count - before == size else { throw _CompressionError() }
            p += payload
        default:
            // "bvx1" and "bvx2", FSE-coded, and anything else.
            throw _CompressionError()
        }
    }
}

/// Decodes LZVN opcodes up to `eos`. A match's distance is kept for the opcodes that reuse it.
private func lzvnDecode(_ source: [UInt8], _ start: Int, _ end: Int, _ out: inout [UInt8]) throws {
    var p = start, distance = 0
    func at(_ offset: Int) throws -> Int {
        guard p + offset < end else { throw _CompressionError() }
        return Int(source[p + offset])
    }
    while true {
        let op = try at(0)
        var literals = 0, match = 0, size = 1
        switch op {
        case 0x06:
            return
        case 0x0E, 0x16:
            p += 1
            continue
        case 0x1E, 0x26, 0x2E, 0x36, 0x3E, 0x70...0x7F, 0xD0...0xDF:
            throw _CompressionError()
        case 0xA0...0xBF:   // med_d
            let word = try at(1) | (try at(2)) << 8
            literals = (op >> 3) & 3
            match = ((op & 7) << 2 | (word & 3)) + 3
            distance = word >> 2
            size = 3
        case 0xE0:          // lrg_l
            literals = try at(1) + 16
            size = 2
        case 0xE1...0xEF:   // sml_l
            literals = op & 15
        case 0xF0:          // lrg_m
            match = try at(1) + 16
            size = 2
        case 0xF1...0xFF:   // sml_m
            match = op & 15
        default:
            literals = op >> 6
            match = ((op >> 3) & 7) + 3
            switch op & 7 {
            case 6:         // pre_d
                break
            case 7:         // lrg_d
                distance = try at(1) | (try at(2)) << 8
                size = 3
            default:        // sml_d
                distance = (op & 7) << 8 | (try at(1))
                size = 2
            }
        }
        p += size
        guard p + literals <= end else { throw _CompressionError() }
        out += source[p..<(p + literals)]
        p += literals
        if match > 0 { try copyMatch(&out, distance: distance, length: match) }
    }
}

// MARK: - xz (LZMA2)

private let xzMagic: [UInt8] = [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]

private func crc32<C: Collection>(_ bytes: C) -> UInt32 where C.Element == UInt8 {
    var table = [UInt32](repeating: 0, count: 256)
    for n in 0..<256 {
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        table[n] = c
    }
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in bytes { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
    return ~crc
}

private func varint(_ out: inout [UInt8], _ value: Int) {
    var value = value
    while value >= 0x80 { out.append(UInt8(value & 0x7F) | 0x80); value >>= 7 }
    out.append(UInt8(value))
}

private func xzStored(_ source: [UInt8]) -> [UInt8] {
    let flags: [UInt8] = [0x00, 0x01]   // a CRC32 check
    var out = xzMagic + flags
    appendLE32(&out, crc32(flags))
    var index: [UInt8] = [0x00]
    if source.isEmpty {
        varint(&index, 0)
    } else {
        // One filter, LZMA2, with a 1 MB dictionary; no sizes in the header.
        let header: [UInt8] = [0x02, 0x00, 0x21, 0x01, 0x10, 0x00, 0x00, 0x00]
        out += header
        appendLE32(&out, crc32(header))
        var data: [UInt8] = []
        var start = 0
        while start < source.count {
            let n = min(65536, source.count - start)
            data.append(start == 0 ? 0x01 : 0x02)
            data.append(UInt8((n - 1) >> 8))
            data.append(UInt8((n - 1) & 0xFF))
            data += source[start..<(start + n)]
            start += n
        }
        data.append(0x00)
        out += data
        out += [UInt8](repeating: 0, count: (4 - data.count % 4) % 4)
        appendLE32(&out, crc32(source))
        varint(&index, 1)
        varint(&index, header.count + 4 + data.count + 4)
        varint(&index, source.count)
    }
    index += [UInt8](repeating: 0, count: (4 - index.count % 4) % 4)
    appendLE32(&index, crc32(index))
    out += index
    var footer: [UInt8] = []
    appendLE32(&footer, index.count / 4 - 1)
    footer += flags
    appendLE32(&out, crc32(footer))
    out += footer + [0x59, 0x5A]
    return out
}

private func readXZ(_ source: [UInt8]) throws -> [UInt8] {
    guard source.count >= 24, Array(source[0..<6]) == xzMagic, source[6] == 0,
          try le32u(source, 8) == crc32(source[6..<8]) else { throw _CompressionError() }
    let checkSizes = [0, 4, 4, 4, 8, 8, 8, 16, 16, 16, 32, 32, 32, 64, 64, 64]
    let check = Int(source[7] & 0x0F)
    var out: [UInt8] = []
    var p = 12
    while true {
        guard p < source.count else { throw _CompressionError() }
        if source[p] == 0 {
            // The index: no more blocks. The stream ends with its footer.
            let footer = source.count - 12
            guard footer >= p, source[source.count - 2] == 0x59, source[source.count - 1] == 0x5A,
                  try le32u(source, footer) == crc32(source[(footer + 4)..<(footer + 10)]) else {
                throw _CompressionError()
            }
            return out
        }
        let headerSize = (Int(source[p]) + 1) * 4
        guard p + headerSize <= source.count,
              try le32u(source, p + headerSize - 4) == crc32(source[p..<(p + headerSize - 4)]) else {
            throw _CompressionError()
        }
        var q = p + 2
        func readVarint() throws -> Int {
            var value = 0, shift = 0
            while true {
                guard q < p + headerSize - 4, shift < 63 else { throw _CompressionError() }
                let byte = Int(source[q])
                q += 1
                value |= (byte & 0x7F) << shift
                if byte < 0x80 { return value }
                shift += 7
            }
        }
        let blockFlags = source[p + 1]
        guard blockFlags & 0x3F == 0 else { throw _CompressionError() }   // one filter only
        if blockFlags & 0x40 != 0 { _ = try readVarint() }
        if blockFlags & 0x80 != 0 { _ = try readVarint() }
        guard try readVarint() == 0x21, try readVarint() == 1 else { throw _CompressionError() }
        p += headerSize
        let dataStart = p, outStart = out.count
        chunks: while true {
            guard p < source.count else { throw _CompressionError() }
            let control = source[p]
            p += 1
            switch control {
            case 0x00:
                break chunks
            case 0x01, 0x02:
                guard p + 2 <= source.count else { throw _CompressionError() }
                let n = (Int(source[p]) << 8 | Int(source[p + 1])) + 1
                p += 2
                guard p + n <= source.count else { throw _CompressionError() }
                out += source[p..<(p + n)]
                p += n
            default:
                // An LZMA-coded chunk.
                throw _CompressionError()
            }
        }
        while (p - dataStart) % 4 != 0 {
            guard p < source.count, source[p] == 0 else { throw _CompressionError() }
            p += 1
        }
        if check == 1 {
            guard try le32u(source, p) == crc32(out[outStart...]) else { throw _CompressionError() }
        }
        p += checkSizes[check]
    }
}
