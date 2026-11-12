// Raw DEFLATE (RFC 1951), what `NSData.compressed(using: .zlib)` writes and reads on Apple's
// platforms (no zlib header or checksum). The compressor finds repeats with a hash of the next
// three bytes over a 32 KB window and writes them with the fixed Huffman codes, falling back to
// stored blocks when that would be larger (bytes that do not repeat); the decompressor reads all
// three block types, so it takes what zlib, Apple's Compression framework or a server wrote.
// Not limited to wasm, so the host tests check it against Apple's decoder (Compression.swift).

private let lengthBase: [Int] = [3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115,
                                 131, 163, 195, 227, 258]
private let lengthExtra: [Int] = [0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0]
private let distanceBase: [Int] = [1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537,
                                   2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577]
private let distanceExtra: [Int] = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13]

/// Why bytes could not be inflated.
struct _DeflateError: Error {}

/// Compresses `source` as raw DEFLATE.
func _deflate(_ source: [UInt8]) -> [UInt8] {
    var writer = BitWriter()
    writer.put(1, 1)   // the final block
    writer.put(1, 2)   // fixed Huffman codes
    let count = source.count
    var head = [Int: Int]()
    func key(_ i: Int) -> Int { Int(source[i]) | Int(source[i + 1]) << 8 | Int(source[i + 2]) << 16 }
    var i = 0
    while i < count {
        var best = 0, distance = 0
        if i + 2 < count {
            let k = key(i)
            if let candidate = head[k], i - candidate <= 32768 {
                var length = 0
                while length < 258, i + length < count, source[candidate + length] == source[i + length] { length += 1 }
                if length >= 3 { best = length; distance = i - candidate }
            }
            head[k] = i
        }
        if best > 0 {
            var code = 0
            while code < 28, lengthBase[code + 1] <= best { code += 1 }
            writer.symbol(257 + code)
            writer.put(best - lengthBase[code], lengthExtra[code])
            var d = 0
            while d < 29, distanceBase[d + 1] <= distance { d += 1 }
            writer.put(bitReversed(d, 5), 5)
            writer.put(distance - distanceBase[d], distanceExtra[d])
            var j = i + 1
            while j < min(i + best, count - 2) { head[key(j)] = j; j += 1 }
            i += best
        } else {
            writer.symbol(Int(source[i]))
            i += 1
        }
    }
    writer.symbol(256)
    let coded = writer.finish()
    let blocks = max(1, (count + 65534) / 65535)
    return coded.count <= count + 5 * blocks ? coded : stored(source)
}

/// The bytes as stored blocks of at most 65,535 bytes each.
private func stored(_ source: [UInt8]) -> [UInt8] {
    var out: [UInt8] = []
    out.reserveCapacity(source.count + 5 * (source.count / 65535 + 1))
    var start = 0
    repeat {
        let length = min(65535, source.count - start)
        out.append(start + length == source.count ? 1 : 0)
        out.append(UInt8(length & 0xFF)); out.append(UInt8(length >> 8))
        out.append(UInt8(~length & 0xFF)); out.append(UInt8((~length >> 8) & 0xFF))
        out.append(contentsOf: source[start..<(start + length)])
        start += length
    } while start < source.count
    return out
}

private func bitReversed(_ code: Int, _ length: Int) -> Int {
    var code = code, result = 0
    for _ in 0..<length { result = result << 1 | code & 1; code >>= 1 }
    return result
}

private struct BitWriter {
    var out: [UInt8] = []
    var buffer = 0
    var bits = 0

    mutating func put(_ value: Int, _ count: Int) {
        guard count > 0 else { return }
        buffer |= value << bits
        bits += count
        while bits >= 8 {
            out.append(UInt8(buffer & 0xFF))
            buffer >>= 8
            bits -= 8
        }
    }

    /// A literal, the end of the block or a length code, in the fixed Huffman code.
    mutating func symbol(_ s: Int) {
        switch s {
        case ..<144: put(bitReversed(0x30 + s, 8), 8)
        case ..<256: put(bitReversed(0x190 + s - 144, 9), 9)
        case ..<280: put(bitReversed(s - 256, 7), 7)
        default: put(bitReversed(0xC0 + s - 280, 8), 8)
        }
    }

    mutating func finish() -> [UInt8] {
        if bits > 0 { out.append(UInt8(buffer & 0xFF)) }
        return out
    }
}

/// Decompresses raw DEFLATE, or throws when the bytes are not a whole, valid stream.
func _inflate(_ source: [UInt8]) throws -> [UInt8] {
    var reader = BitReader(source: source)
    var out: [UInt8] = []
    out.reserveCapacity(source.count * 3)
    var fixed: (Huffman, Huffman)?
    while true {
        let last = try reader.bits(1)
        switch try reader.bits(2) {
        case 0:
            reader.alignToByte()
            let length = try reader.byte() | (try reader.byte()) << 8
            let complement = try reader.byte() | (try reader.byte()) << 8
            guard length == ~complement & 0xFFFF else { throw _DeflateError() }
            for _ in 0..<length { out.append(UInt8(try reader.byte())) }
        case 1:
            if fixed == nil {
                let lengths = [Int](repeating: 8, count: 144) + [Int](repeating: 9, count: 112)
                    + [Int](repeating: 7, count: 24) + [Int](repeating: 8, count: 8)
                fixed = (Huffman(lengths), Huffman([Int](repeating: 5, count: 30)))
            }
            try codes(&reader, &out, fixed!.0, fixed!.1)
        case 2:
            let literalCount = try reader.bits(5) + 257, distanceCount = try reader.bits(5) + 1
            let codeCount = try reader.bits(4) + 4
            let order = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]
            var codeLengths = [Int](repeating: 0, count: 19)
            for k in 0..<codeCount { codeLengths[order[k]] = try reader.bits(3) }
            let lengthCode = Huffman(codeLengths)
            var lengths: [Int] = []
            while lengths.count < literalCount + distanceCount {
                let s = try lengthCode.decode(&reader)
                switch s {
                case ..<16: lengths.append(s)
                case 16:
                    guard let previous = lengths.last else { throw _DeflateError() }
                    lengths += [Int](repeating: previous, count: 3 + (try reader.bits(2)))
                case 17: lengths += [Int](repeating: 0, count: 3 + (try reader.bits(3)))
                default: lengths += [Int](repeating: 0, count: 11 + (try reader.bits(7)))
                }
            }
            guard lengths.count == literalCount + distanceCount else { throw _DeflateError() }
            try codes(&reader, &out, Huffman(Array(lengths[..<literalCount])), Huffman(Array(lengths[literalCount...])))
        default:
            throw _DeflateError()
        }
        if last == 1 { return out }
    }
}

private func codes(_ reader: inout BitReader, _ out: inout [UInt8], _ literals: Huffman, _ distances: Huffman) throws {
    while true {
        var s = try literals.decode(&reader)
        if s < 256 {
            out.append(UInt8(s))
        } else if s == 256 {
            return
        } else {
            s -= 257
            guard s < 29 else { throw _DeflateError() }
            let length = lengthBase[s] + (try reader.bits(lengthExtra[s]))
            let d = try distances.decode(&reader)
            guard d < 30 else { throw _DeflateError() }
            let distance = distanceBase[d] + (try reader.bits(distanceExtra[d]))
            guard distance <= out.count else { throw _DeflateError() }
            for _ in 0..<length { out.append(out[out.count - distance]) }
        }
    }
}

/// A canonical Huffman code from its code lengths, decoded a bit at a time.
private struct Huffman {
    var counts = [Int](repeating: 0, count: 16)
    var symbols: [Int]

    init(_ lengths: [Int]) {
        for length in lengths { counts[length] += 1 }
        counts[0] = 0
        var offsets = [Int](repeating: 0, count: 16)
        for length in 1..<15 { offsets[length + 1] = offsets[length] + counts[length] }
        symbols = [Int](repeating: 0, count: lengths.count)
        for (symbol, length) in lengths.enumerated() where length != 0 {
            symbols[offsets[length]] = symbol
            offsets[length] += 1
        }
    }

    func decode(_ reader: inout BitReader) throws -> Int {
        var code = 0, first = 0, index = 0
        for length in 1..<16 {
            code |= try reader.bits(1)
            let count = counts[length]
            if code - count < first { return symbols[index + (code - first)] }
            index += count
            first = (first + count) << 1
            code <<= 1
        }
        throw _DeflateError()
    }
}

private struct BitReader {
    let source: [UInt8]
    var position = 0
    var buffer = 0
    var count = 0

    mutating func bits(_ n: Int) throws -> Int {
        while count < n {
            guard position < source.count else { throw _DeflateError() }
            buffer |= Int(source[position]) << count
            position += 1
            count += 8
        }
        let value = buffer & ((1 << n) - 1)
        buffer >>= n
        count -= n
        return value
    }

    mutating func alignToByte() {
        buffer = 0
        count = 0
    }

    mutating func byte() throws -> Int {
        guard position < source.count else { throw _DeflateError() }
        position += 1
        return Int(source[position - 1])
    }
}
