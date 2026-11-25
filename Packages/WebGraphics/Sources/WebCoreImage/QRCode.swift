// QR codes for Core Image (Docs/elements/CoreImage.md): the symbol model that
// `CIQRCodeGenerator` draws and `CIDetector` reads, written from ISO/IEC 18004's description of
// the format. A symbol is a square of modules; the encoder picks the smallest version that holds
// the message at the asked-for error-correction level and the mask with the lowest penalty, and
// the decoder reads a module matrix back into its message, correcting errors with Reed-Solomon.

#if !canImport(CoreGraphics) || os(WASI)
import WebFoundation

enum QRCode {
    /// An error-correction level, in the order the block table lists them.
    enum Level: Int, CaseIterable {
        case low = 0, medium, quartile, high

        /// The level's letter, as `CIQRCodeGenerator`'s `inputCorrectionLevel` names it.
        init?(letter: String) {
            switch letter.uppercased() {
            case "L": self = .low
            case "M": self = .medium
            case "Q": self = .quartile
            case "H": self = .high
            default: return nil
            }
        }

        /// The two bits the format information stores for the level.
        var formatBits: Int { [1, 0, 3, 2][rawValue] }
        /// The letter's ASCII code, as `CIQRCodeDescriptor.ErrorCorrectionLevel` has it.
        var ascii: Int { [76, 77, 81, 72][rawValue] }
    }

    /// A symbol: its version, level, mask and modules (`true` is dark), row by row.
    struct Symbol {
        var version: Int
        var level: Level
        var mask: Int
        var modules: [[Bool]]
        var size: Int { modules.count }
    }

    /// A message read from a symbol.
    struct Decoded {
        var version: Int
        var level: Level
        var mask: Int
        /// The data codewords after error correction.
        var dataCodewords: [UInt8]
        /// The bytes of the message's segments, in order.
        var payload: [UInt8]
        /// The payload as text, each part in the character set its ECI designator names. Bytes
        /// before any designator, or under one not known here, read as UTF-8, or as Latin-1
        /// when they are not valid UTF-8.
        var text: String
    }

    // MARK: - Tables

    /// For each version and level: error-correction codewords per block, then how many blocks of
    /// how many data codewords in the first group and in the second.
    private static let blockTable: [Int] = [
        7, 1, 19, 0, 0, 10, 1, 16, 0, 0, 13, 1, 13, 0, 0, 17, 1, 9, 0, 0, // 1
        10, 1, 34, 0, 0, 16, 1, 28, 0, 0, 22, 1, 22, 0, 0, 28, 1, 16, 0, 0, // 2
        15, 1, 55, 0, 0, 26, 1, 44, 0, 0, 18, 2, 17, 0, 0, 22, 2, 13, 0, 0, // 3
        20, 1, 80, 0, 0, 18, 2, 32, 0, 0, 26, 2, 24, 0, 0, 16, 4, 9, 0, 0, // 4
        26, 1, 108, 0, 0, 24, 2, 43, 0, 0, 18, 2, 15, 2, 16, 22, 2, 11, 2, 12, // 5
        18, 2, 68, 0, 0, 16, 4, 27, 0, 0, 24, 4, 19, 0, 0, 28, 4, 15, 0, 0, // 6
        20, 2, 78, 0, 0, 18, 4, 31, 0, 0, 18, 2, 14, 4, 15, 26, 4, 13, 1, 14, // 7
        24, 2, 97, 0, 0, 22, 2, 38, 2, 39, 22, 4, 18, 2, 19, 26, 4, 14, 2, 15, // 8
        30, 2, 116, 0, 0, 22, 3, 36, 2, 37, 20, 4, 16, 4, 17, 24, 4, 12, 4, 13, // 9
        18, 2, 68, 2, 69, 26, 4, 43, 1, 44, 24, 6, 19, 2, 20, 28, 6, 15, 2, 16, // 10
        20, 4, 81, 0, 0, 30, 1, 50, 4, 51, 28, 4, 22, 4, 23, 24, 3, 12, 8, 13, // 11
        24, 2, 92, 2, 93, 22, 6, 36, 2, 37, 26, 4, 20, 6, 21, 28, 7, 14, 4, 15, // 12
        26, 4, 107, 0, 0, 22, 8, 37, 1, 38, 24, 8, 20, 4, 21, 22, 12, 11, 4, 12, // 13
        30, 3, 115, 1, 116, 24, 4, 40, 5, 41, 20, 11, 16, 5, 17, 24, 11, 12, 5, 13, // 14
        22, 5, 87, 1, 88, 24, 5, 41, 5, 42, 30, 5, 24, 7, 25, 24, 11, 12, 7, 13, // 15
        24, 5, 98, 1, 99, 28, 7, 45, 3, 46, 24, 15, 19, 2, 20, 30, 3, 15, 13, 16, // 16
        28, 1, 107, 5, 108, 28, 10, 46, 1, 47, 28, 1, 22, 15, 23, 28, 2, 14, 17, 15, // 17
        30, 5, 120, 1, 121, 26, 9, 43, 4, 44, 28, 17, 22, 1, 23, 28, 2, 14, 19, 15, // 18
        28, 3, 113, 4, 114, 26, 3, 44, 11, 45, 26, 17, 21, 4, 22, 26, 9, 13, 16, 14, // 19
        28, 3, 107, 5, 108, 26, 3, 41, 13, 42, 30, 15, 24, 5, 25, 28, 15, 15, 10, 16, // 20
        28, 4, 116, 4, 117, 26, 17, 42, 0, 0, 28, 17, 22, 6, 23, 30, 19, 16, 6, 17, // 21
        28, 2, 111, 7, 112, 28, 17, 46, 0, 0, 30, 7, 24, 16, 25, 24, 34, 13, 0, 0, // 22
        30, 4, 121, 5, 122, 28, 4, 47, 14, 48, 30, 11, 24, 14, 25, 30, 16, 15, 14, 16, // 23
        30, 6, 117, 4, 118, 28, 6, 45, 14, 46, 30, 11, 24, 16, 25, 30, 30, 16, 2, 17, // 24
        26, 8, 106, 4, 107, 28, 8, 47, 13, 48, 30, 7, 24, 22, 25, 30, 22, 15, 13, 16, // 25
        28, 10, 114, 2, 115, 28, 19, 46, 4, 47, 28, 28, 22, 6, 23, 30, 33, 16, 4, 17, // 26
        30, 8, 122, 4, 123, 28, 22, 45, 3, 46, 30, 8, 23, 26, 24, 30, 12, 15, 28, 16, // 27
        30, 3, 117, 10, 118, 28, 3, 45, 23, 46, 30, 4, 24, 31, 25, 30, 11, 15, 31, 16, // 28
        30, 7, 116, 7, 117, 28, 21, 45, 7, 46, 30, 1, 23, 37, 24, 30, 19, 15, 26, 16, // 29
        30, 5, 115, 10, 116, 28, 19, 47, 10, 48, 30, 15, 24, 25, 25, 30, 23, 15, 25, 16, // 30
        30, 13, 115, 3, 116, 28, 2, 46, 29, 47, 30, 42, 24, 1, 25, 30, 23, 15, 28, 16, // 31
        30, 17, 115, 0, 0, 28, 10, 46, 23, 47, 30, 10, 24, 35, 25, 30, 19, 15, 35, 16, // 32
        30, 17, 115, 1, 116, 28, 14, 46, 21, 47, 30, 29, 24, 19, 25, 30, 11, 15, 46, 16, // 33
        30, 13, 115, 6, 116, 28, 14, 46, 23, 47, 30, 44, 24, 7, 25, 30, 59, 16, 1, 17, // 34
        30, 12, 121, 7, 122, 28, 12, 47, 26, 48, 30, 39, 24, 14, 25, 30, 22, 15, 41, 16, // 35
        30, 6, 121, 14, 122, 28, 6, 47, 34, 48, 30, 46, 24, 10, 25, 30, 2, 15, 64, 16, // 36
        30, 17, 122, 4, 123, 28, 29, 46, 14, 47, 30, 49, 24, 10, 25, 30, 24, 15, 46, 16, // 37
        30, 4, 122, 18, 123, 28, 13, 46, 32, 47, 30, 48, 24, 14, 25, 30, 42, 15, 32, 16, // 38
        30, 20, 117, 4, 118, 28, 40, 47, 7, 48, 30, 43, 24, 22, 25, 30, 10, 15, 67, 16, // 39
        30, 19, 118, 6, 119, 28, 18, 47, 31, 48, 30, 34, 24, 34, 25, 30, 20, 15, 61, 16, // 40
    ]

    /// The rows and columns of the alignment patterns' centres, by version.
    private static let alignmentTable: [[Int]] = [
        [],
        [6, 18],
        [6, 22],
        [6, 26],
        [6, 30],
        [6, 34],
        [6, 22, 38],
        [6, 24, 42],
        [6, 26, 46],
        [6, 28, 50],
        [6, 30, 54],
        [6, 32, 58],
        [6, 34, 62],
        [6, 26, 46, 66],
        [6, 26, 48, 70],
        [6, 26, 50, 74],
        [6, 30, 54, 78],
        [6, 30, 56, 82],
        [6, 30, 58, 86],
        [6, 34, 62, 90],
        [6, 28, 50, 72, 94],
        [6, 26, 50, 74, 98],
        [6, 30, 54, 78, 102],
        [6, 28, 54, 80, 106],
        [6, 32, 58, 84, 110],
        [6, 30, 58, 86, 114],
        [6, 34, 62, 90, 118],
        [6, 26, 50, 74, 98, 122],
        [6, 30, 54, 78, 102, 126],
        [6, 26, 52, 78, 104, 130],
        [6, 30, 56, 82, 108, 134],
        [6, 34, 60, 86, 112, 138],
        [6, 30, 58, 86, 114, 142],
        [6, 34, 62, 90, 118, 146],
        [6, 30, 54, 78, 102, 126, 150],
        [6, 24, 50, 76, 102, 128, 154],
        [6, 28, 54, 80, 106, 132, 158],
        [6, 32, 58, 84, 110, 136, 162],
        [6, 26, 54, 82, 110, 138, 166],
        [6, 30, 58, 86, 114, 142, 170],
    ]

    static func side(_ version: Int) -> Int { version * 4 + 17 }

    static func alignmentPositions(_ version: Int) -> [Int] { alignmentTable[version - 1] }

    /// Error-correction codewords per block and each block's data codeword count.
    static func blocks(_ version: Int, _ level: Level) -> (ec: Int, data: [Int]) {
        let i = ((version - 1) * 4 + level.rawValue) * 5
        let t = blockTable
        return (t[i], Array(repeating: t[i + 2], count: t[i + 1]) + Array(repeating: t[i + 4], count: t[i + 3]))
    }

    static func dataCapacity(_ version: Int, _ level: Level) -> Int { blocks(version, level).data.reduce(0, +) }

    // MARK: - Galois field and Reed-Solomon

    /// Powers and logarithms of 2 in GF(256) with the polynomial x^8 + x^4 + x^3 + x^2 + 1.
    private static let field: (exp: [UInt8], log: [Int]) = {
        var exp = [UInt8](repeating: 0, count: 512)
        var log = [Int](repeating: 0, count: 256)
        var x = 1
        for i in 0..<255 {
            exp[i] = UInt8(x)
            log[x] = i
            x <<= 1
            if x & 0x100 != 0 { x ^= 0x11D }
        }
        for i in 255..<512 { exp[i] = exp[i - 255] }
        return (exp, log)
    }()

    static func gfMul(_ a: UInt8, _ b: UInt8) -> UInt8 {
        guard a != 0, b != 0 else { return 0 }
        return field.exp[field.log[Int(a)] + field.log[Int(b)]]
    }

    static func gfDiv(_ a: UInt8, _ b: UInt8) -> UInt8 {
        guard a != 0 else { return 0 }
        return field.exp[(field.log[Int(a)] + 255 - field.log[Int(b)]) % 255]
    }

    /// 2 to the power `n`.
    static func gfPow2(_ n: Int) -> UInt8 { field.exp[((n % 255) + 255) % 255] }

    /// The error-correction codewords for `data`, `count` of them.
    static func reedSolomon(_ data: [UInt8], count: Int) -> [UInt8] {
        // The generator (x - 2^0)(x - 2^1)...(x - 2^(count-1)), highest degree first.
        var generator: [UInt8] = [1]
        for i in 0..<count {
            var next = [UInt8](repeating: 0, count: generator.count + 1)
            for (j, c) in generator.enumerated() {
                next[j] ^= c
                next[j + 1] ^= gfMul(c, gfPow2(i))
            }
            generator = next
        }
        var remainder = [UInt8](repeating: 0, count: count)
        for byte in data {
            let factor = byte ^ remainder[0]
            remainder.removeFirst()
            remainder.append(0)
            if factor != 0 {
                for j in 0..<count { remainder[j] ^= gfMul(generator[j + 1], factor) }
            }
        }
        return remainder
    }

    /// The block with its errors corrected, or nil when it has more than its error-correction
    /// codewords can fix. `ecCount` of the codewords at the end are error correction.
    static func correct(_ block: [UInt8], ecCount: Int) -> [UInt8]? {
        let n = block.count
        func evaluate(_ x: UInt8) -> UInt8 {
            var y: UInt8 = 0
            for c in block { y = gfMul(y, x) ^ c }
            return y
        }
        let syndromes = (0..<ecCount).map { evaluate(gfPow2($0)) }
        guard syndromes.contains(where: { $0 != 0 }) else { return block }

        // Berlekamp-Massey: the error locator, lowest degree first.
        var locator: [UInt8] = [1]
        var previous: [UInt8] = [1]
        var errors = 0
        var shift = 1
        var lastDiscrepancy: UInt8 = 1
        for k in 0..<ecCount {
            var d = syndromes[k]
            if errors >= 1 {
                for i in 1...errors where i < locator.count { d ^= gfMul(locator[i], syndromes[k - i]) }
            }
            if d == 0 {
                shift += 1
                continue
            }
            let coefficient = gfDiv(d, lastDiscrepancy)
            let saved = locator
            if locator.count < previous.count + shift {
                locator += [UInt8](repeating: 0, count: previous.count + shift - locator.count)
            }
            for (i, b) in previous.enumerated() { locator[i + shift] ^= gfMul(coefficient, b) }
            if 2 * errors <= k {
                errors = k + 1 - errors
                previous = saved
                lastDiscrepancy = d
                shift = 1
            } else {
                shift += 1
            }
        }
        guard 2 * errors <= ecCount else { return nil }

        func evaluateLow(_ p: [UInt8], _ x: UInt8) -> UInt8 {
            var y: UInt8 = 0
            for c in p.reversed() { y = gfMul(y, x) ^ c }
            return y
        }
        // The evaluator S(x)L(x) mod x^ecCount, and L's formal derivative.
        var evaluator = [UInt8](repeating: 0, count: ecCount)
        for i in 0..<ecCount {
            for j in 0..<locator.count where i + j < ecCount { evaluator[i + j] ^= gfMul(syndromes[i], locator[j]) }
        }
        var derivative = [UInt8](repeating: 0, count: max(1, locator.count - 1))
        for i in stride(from: 1, to: locator.count, by: 2) { derivative[i - 1] = locator[i] }

        // Chien search for the error positions, and Forney for their values.
        var corrected = block
        var found = 0
        for k in 0..<n {
            let x = gfPow2(n - 1 - k)
            let xInverse = gfDiv(1, x)
            guard evaluateLow(locator, xInverse) == 0 else { continue }
            found += 1
            let denominator = evaluateLow(derivative, xInverse)
            guard denominator != 0 else { return nil }
            corrected[k] ^= gfMul(x, gfDiv(evaluateLow(evaluator, xInverse), denominator))
        }
        guard found == errors else { return nil }
        return corrected
    }

    // MARK: - Format and version information

    /// `value` followed by its BCH remainder for the generator `poly` of degree `degree`.
    private static func bch(_ value: Int, poly: Int, degree: Int) -> Int {
        var r = value << degree
        var bit = 31
        while bit >= degree {
            if r >> bit & 1 == 1 { r ^= poly << (bit - degree) }
            bit -= 1
        }
        return value << degree | r
    }

    static func formatBits(_ level: Level, mask: Int) -> Int {
        bch(level.formatBits << 3 | mask, poly: 0x537, degree: 10) ^ 0x5412
    }

    static func versionBits(_ version: Int) -> Int { bch(version, poly: 0x1F25, degree: 12) }

    /// Where the 15 format bits go, bit 0 first, as (column, row): the copy around the top-left
    /// finder, and the copy split between the other two.
    static func formatPositions(size: Int) -> [[(Int, Int)]] {
        var first: [(Int, Int)] = (0..<6).map { (8, $0) }
        first += [(8, 7), (8, 8), (7, 8)]
        first += (9..<15).map { (14 - $0, 8) }
        var second: [(Int, Int)] = (0..<8).map { (size - 1 - $0, 8) }
        second += (8..<15).map { (8, size - 15 + $0) }
        return [first, second]
    }

    // MARK: - Layout

    /// Which modules are finder, timing, alignment, format or version modules.
    static func functionModules(_ version: Int) -> [[Bool]] {
        let size = side(version)
        var f = Array(repeating: Array(repeating: false, count: size), count: size)
        func mark(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
            for row in max(0, y)..<min(size, y + h) {
                for col in max(0, x)..<min(size, x + w) { f[row][col] = true }
            }
        }
        mark(0, 0, 9, 9)
        mark(size - 8, 0, 8, 9)
        mark(0, size - 8, 9, 8)
        mark(6, 0, 1, size)
        mark(0, 6, size, 1)
        for (x, y) in alignmentCentres(version) { mark(x - 2, y - 2, 5, 5) }
        if version >= 7 {
            mark(size - 11, 0, 3, 6)
            mark(0, size - 11, 6, 3)
        }
        return f
    }

    /// The alignment patterns' centres, leaving out the three under the finders.
    static func alignmentCentres(_ version: Int) -> [(Int, Int)] {
        let p = alignmentPositions(version)
        guard let last = p.last else { return [] }
        var centres: [(Int, Int)] = []
        for x in p {
            for y in p where !((x == 6 && y == 6) || (x == 6 && y == last) || (x == last && y == 6)) {
                centres.append((x, y))
            }
        }
        return centres
    }

    /// The data modules in the order codeword bits fill them: two columns at a time from the
    /// right, up and then down, stepping over the vertical timing pattern.
    static func dataOrder(_ version: Int) -> [(Int, Int)] {
        let size = side(version)
        let function = functionModules(version)
        var order: [(Int, Int)] = []
        var right = size - 1
        while right >= 1 {
            if right == 6 { right = 5 }
            let upward = (right + 1) & 2 == 0
            for step in 0..<size {
                let y = upward ? size - 1 - step : step
                for j in 0..<2 {
                    let x = right - j
                    if !function[y][x] { order.append((x, y)) }
                }
            }
            right -= 2
        }
        return order
    }

    static func masked(_ mask: Int, _ x: Int, _ y: Int) -> Bool {
        switch mask {
        case 0: return (x + y) % 2 == 0
        case 1: return y % 2 == 0
        case 2: return x % 3 == 0
        case 3: return (x + y) % 3 == 0
        case 4: return (x / 3 + y / 2) % 2 == 0
        case 5: return x * y % 2 + x * y % 3 == 0
        case 6: return (x * y % 2 + x * y % 3) % 2 == 0
        default: return ((x + y) % 2 + x * y % 3) % 2 == 0
        }
    }

    private static func drawFunctionPatterns(_ version: Int, _ level: Level, mask: Int, into m: inout [[Bool]]) {
        let size = side(version)
        func finder(_ cx: Int, _ cy: Int) {
            for dy in -4...4 {
                for dx in -4...4 {
                    let (x, y) = (cx + dx, cy + dy)
                    guard x >= 0, x < size, y >= 0, y < size else { continue }
                    let ring = max(abs(dx), abs(dy))
                    m[y][x] = ring != 2 && ring != 4
                }
            }
        }
        finder(3, 3)
        finder(size - 4, 3)
        finder(3, size - 4)
        for i in 8..<(size - 8) {
            m[6][i] = i % 2 == 0
            m[i][6] = i % 2 == 0
        }
        for (cx, cy) in alignmentCentres(version) {
            for dy in -2...2 {
                for dx in -2...2 { m[cy + dy][cx + dx] = max(abs(dx), abs(dy)) != 1 }
            }
        }
        let format = formatBits(level, mask: mask)
        for copy in formatPositions(size: size) {
            for (i, (x, y)) in copy.enumerated() { m[y][x] = format >> i & 1 == 1 }
        }
        m[size - 8][8] = true
        if version >= 7 {
            let bits = versionBits(version)
            for i in 0..<18 {
                let (a, b) = (size - 11 + i % 3, i / 3)
                m[b][a] = bits >> i & 1 == 1
                m[a][b] = bits >> i & 1 == 1
            }
        }
    }

    // MARK: - Encoding

    private enum Mode: Int {
        case numeric = 1, alphanumeric = 2, byte = 4, kanji = 8

        func countBits(_ version: Int) -> Int {
            let band = version <= 9 ? 0 : version <= 26 ? 1 : 2
            switch self {
            case .numeric: return [10, 12, 14][band]
            case .alphanumeric: return [9, 11, 13][band]
            case .byte: return [8, 16, 16][band]
            case .kanji: return [8, 10, 12][band]
            }
        }
    }

    private static let alphanumerics = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:".utf8)

    private struct BitWriter {
        var bits: [Bool] = []
        mutating func put(_ value: Int, _ count: Int) {
            for i in stride(from: count - 1, through: 0, by: -1) { bits.append(value >> i & 1 == 1) }
        }
    }

    /// The message as one segment in the most compact of numeric, alphanumeric and byte modes.
    private static func segment(_ message: [UInt8], version: Int) -> [Bool] {
        let mode: Mode
        if !message.isEmpty, message.allSatisfy({ $0 >= 48 && $0 <= 57 }) {
            mode = .numeric
        } else if !message.isEmpty, message.allSatisfy({ alphanumerics.contains($0) }) {
            mode = .alphanumeric
        } else {
            mode = .byte
        }
        var w = BitWriter()
        w.put(mode.rawValue, 4)
        w.put(message.count, mode.countBits(version))
        switch mode {
        case .numeric:
            var i = 0
            while i < message.count {
                let chunk = message[i..<min(i + 3, message.count)]
                let value = chunk.reduce(0) { $0 * 10 + Int($1 - 48) }
                w.put(value, [0, 4, 7, 10][chunk.count])
                i += 3
            }
        case .alphanumeric:
            let index = message.map { alphanumerics.firstIndex(of: $0) ?? 0 }
            var i = 0
            while i < index.count {
                if i + 1 < index.count {
                    w.put(index[i] * 45 + index[i + 1], 11)
                } else {
                    w.put(index[i], 6)
                }
                i += 2
            }
        case .byte, .kanji:
            for byte in message { w.put(Int(byte), 8) }
        }
        return w.bits
    }

    /// The symbol for `message`, or nil when it is too long for version 40 at `level`.
    static func encode(_ message: [UInt8], level: Level, mask forcedMask: Int? = nil) -> Symbol? {
        var chosen: (version: Int, bits: [Bool])?
        for version in 1...40 {
            let bits = segment(message, version: version)
            if bits.count <= dataCapacity(version, level) * 8 {
                chosen = (version, bits)
                break
            }
        }
        guard let chosen else { return nil }
        let (version, segmentBits) = chosen
        let capacity = dataCapacity(version, level) * 8
        var bits = segmentBits
        bits += Array(repeating: false, count: min(4, capacity - bits.count))
        bits += Array(repeating: false, count: (8 - bits.count % 8) % 8)
        var data: [UInt8] = stride(from: 0, to: bits.count, by: 8).map { start in
            (0..<8).reduce(UInt8(0)) { $0 << 1 | (bits[start + $1] ? 1 : 0) }
        }
        var pad: UInt8 = 0xEC
        while data.count < capacity / 8 {
            data.append(pad)
            pad = pad == 0xEC ? 0x11 : 0xEC
        }

        // Split into blocks, add each block's error correction, and interleave.
        let (ecCount, sizes) = blocks(version, level)
        var dataBlocks: [[UInt8]] = []
        var start = 0
        for count in sizes {
            dataBlocks.append(Array(data[start..<start + count]))
            start += count
        }
        let ecBlocks = dataBlocks.map { reedSolomon($0, count: ecCount) }
        var codewords: [UInt8] = []
        for i in 0..<(sizes.max() ?? 0) {
            for block in dataBlocks where i < block.count { codewords.append(block[i]) }
        }
        for i in 0..<ecCount {
            for block in ecBlocks { codewords.append(block[i]) }
        }

        let size = side(version)
        let order = dataOrder(version)
        var best: (penalty: Int, symbol: Symbol)?
        for mask in forcedMask.map({ [$0] }) ?? Array(0..<8) {
            var m = Array(repeating: Array(repeating: false, count: size), count: size)
            for (k, (x, y)) in order.enumerated() {
                var dark = k < codewords.count * 8 && codewords[k / 8] >> (7 - k % 8) & 1 == 1
                if masked(mask, x, y) { dark.toggle() }
                m[y][x] = dark
            }
            drawFunctionPatterns(version, level, mask: mask, into: &m)
            let score = penalty(m)
            if best == nil || score < best!.penalty {
                best = (score, Symbol(version: version, level: level, mask: mask, modules: m))
            }
        }
        return best?.symbol
    }

    /// The masking penalty: long runs, 2 by 2 blocks, finder-like patterns and imbalance.
    static func penalty(_ m: [[Bool]]) -> Int {
        let size = m.count
        var score = 0
        let finderLike: [[Bool]] = [
            [true, false, true, true, true, false, true, false, false, false, false],
            [false, false, false, false, true, false, true, true, true, false, true],
        ]
        for vertical in [false, true] {
            for line in 0..<size {
                let row: [Bool] = (0..<size).map { vertical ? m[$0][line] : m[line][$0] }
                var run = 1
                for i in 1..<size {
                    if row[i] == row[i - 1] {
                        run += 1
                    } else {
                        if run >= 5 { score += run - 2 }
                        run = 1
                    }
                }
                if run >= 5 { score += run - 2 }
                if size >= 11 {
                    for i in 0...(size - 11) where finderLike.contains(where: { Array(row[i..<i + 11]) == $0 }) { score += 40 }
                }
            }
        }
        for y in 0..<(size - 1) {
            for x in 0..<(size - 1) where m[y][x] == m[y][x + 1] && m[y][x] == m[y + 1][x] && m[y][x] == m[y + 1][x + 1] {
                score += 3
            }
        }
        let dark = m.reduce(0) { total, row in total + row.filter { $0 }.count }
        let total = size * size
        let k = abs(dark * 20 - total * 10)
        if k > 0 { score += 10 * ((k + total - 1) / total - 1) }
        return score
    }

    // MARK: - Decoding

    /// The message in a module matrix (`true` is dark), or nil when it is not a readable symbol.
    static func decode(_ m: [[Bool]]) -> Decoded? {
        let size = m.count
        guard size >= 21, size <= 177, (size - 17) % 4 == 0, m.allSatisfy({ $0.count == size }) else { return nil }
        let version = (size - 17) / 4

        // The format: the valid code nearest to either copy, within three bits.
        var nearest: (distance: Int, level: Level, mask: Int)?
        for copy in formatPositions(size: size) {
            var read = 0
            for (i, (x, y)) in copy.enumerated() where m[y][x] { read |= 1 << i }
            for level in Level.allCases {
                for mask in 0..<8 {
                    let distance = (read ^ formatBits(level, mask: mask)).nonzeroBitCount
                    if nearest == nil || distance < nearest!.distance { nearest = (distance, level, mask) }
                }
            }
        }
        guard let format = nearest, format.distance <= 3 else { return nil }
        if version >= 7 {
            // A version block that reads as another version means the size was misjudged.
            var closest: (distance: Int, version: Int)?
            for transposed in [false, true] {
                var read = 0
                for i in 0..<18 {
                    let (a, b) = (size - 11 + i % 3, i / 3)
                    if transposed ? m[a][b] : m[b][a] { read |= 1 << i }
                }
                for candidate in 7...40 {
                    let distance = (read ^ versionBits(candidate)).nonzeroBitCount
                    if closest == nil || distance < closest!.distance { closest = (distance, candidate) }
                }
            }
            if let closest, closest.distance <= 3, closest.version != version { return nil }
        }

        let (ecCount, sizes) = blocks(version, format.level)
        let total = sizes.reduce(0, +) + ecCount * sizes.count
        var codewords = [UInt8](repeating: 0, count: total)
        for (k, (x, y)) in dataOrder(version).prefix(total * 8).enumerated() {
            var dark = m[y][x]
            if masked(format.mask, x, y) { dark.toggle() }
            if dark { codewords[k / 8] |= 1 << (7 - k % 8) }
        }

        // De-interleave, correct each block, and join the data.
        var received: [[UInt8]] = sizes.map { _ in [] }
        var next = 0
        for i in 0..<(sizes.max() ?? 0) {
            for (j, count) in sizes.enumerated() where i < count {
                received[j].append(codewords[next])
                next += 1
            }
        }
        for _ in 0..<ecCount {
            for j in sizes.indices {
                received[j].append(codewords[next])
                next += 1
            }
        }
        var data: [UInt8] = []
        for (j, block) in received.enumerated() {
            guard let fixed = correct(block, ecCount: ecCount) else { return nil }
            data += fixed.prefix(sizes[j])
        }
        guard let runs = segments(data, version: version) else { return nil }
        let payload = runs.flatMap(\.bytes)
        let text = runs.map { string($0.bytes, eci: $0.eci) }.joined()
        return Decoded(version: version, level: format.level, mask: format.mask, dataCodewords: data, payload: payload, text: text)
    }

    /// Bytes read under one ECI assignment: nil before the first designator.
    private struct Run {
        var eci: Int?
        var bytes: [UInt8] = []
    }

    /// The bytes of the segments in the data codewords, split where an ECI designator changes
    /// the character set, or nil when they are malformed.
    private static func segments(_ data: [UInt8], version: Int) -> [Run]? {
        var position = 0
        let bitCount = data.count * 8
        func read(_ n: Int) -> Int? {
            guard position + n <= bitCount else { return nil }
            var value = 0
            for _ in 0..<n {
                value = value << 1 | Int(data[position / 8] >> (7 - position % 8) & 1)
                position += 1
            }
            return value
        }
        var runs: [Run] = []
        var eci: Int?
        var out: [UInt8] = []
        while bitCount - position >= 4 {
            guard let indicator = read(4) else { return nil }
            switch indicator {
            case 0:
                return runs + [Run(eci: eci, bytes: out)]
            case 7:
                // An ECI designator: an assignment number in one, two or three bytes, whose
                // leading bits say how many.
                guard let first = read(8) else { return nil }
                let assignment: Int
                if first & 0x80 == 0 {
                    assignment = first
                } else if first & 0x40 == 0 {
                    guard let rest = read(8) else { return nil }
                    assignment = (first & 0x3F) << 8 | rest
                } else if first & 0x20 == 0 {
                    guard let rest = read(16) else { return nil }
                    assignment = (first & 0x1F) << 16 | rest
                } else {
                    return nil
                }
                if !out.isEmpty {
                    runs.append(Run(eci: eci, bytes: out))
                    out = []
                }
                eci = assignment
            case 5:
                continue
            case 9:
                guard read(8) != nil else { return nil }
            case 3:
                guard read(16) != nil else { return nil }
            default:
                guard let mode = Mode(rawValue: indicator), var count = read(mode.countBits(version)) else { return nil }
                switch mode {
                case .numeric:
                    while count >= 3 {
                        guard let v = read(10), v < 1000 else { return nil }
                        out += Array(String(v).leftPadded(3).utf8)
                        count -= 3
                    }
                    if count > 0 {
                        guard let v = read(count == 2 ? 7 : 4), v < (count == 2 ? 100 : 10) else { return nil }
                        out += Array(String(v).leftPadded(count).utf8)
                    }
                case .alphanumeric:
                    while count >= 2 {
                        guard let v = read(11), v < 45 * 45 else { return nil }
                        out += [alphanumerics[v / 45], alphanumerics[v % 45]]
                        count -= 2
                    }
                    if count == 1 {
                        guard let v = read(6), v < 45 else { return nil }
                        out.append(alphanumerics[v])
                    }
                case .byte:
                    for _ in 0..<count {
                        guard let v = read(8) else { return nil }
                        out.append(UInt8(v))
                    }
                case .kanji:
                    // Shift JIS double bytes, kept as they are.
                    for _ in 0..<count {
                        guard let v = read(13) else { return nil }
                        var code = (v / 0xC0) << 8 | v % 0xC0
                        code += code < 0x1F00 ? 0x8140 : 0xC140
                        out += [UInt8(code >> 8), UInt8(code & 0xFF)]
                    }
                }
            }
        }
        return runs + [Run(eci: eci, bytes: out)]
    }

    // MARK: - Character sets

    /// The bytes read in the character set of ECI assignment `eci`.
    private static func string(_ bytes: [UInt8], eci: Int?) -> String {
        switch eci {
        case 1, 3, 27, 170:
            // ISO 8859-1, and ASCII, which is a part of it.
            return String(String.UnicodeScalarView(bytes.map { Unicode.Scalar($0) }))
        case 17:
            // ISO 8859-15: Latin-1 with eight places changed.
            return String(String.UnicodeScalarView(bytes.map { Unicode.Scalar(latin9[$0] ?? UInt32($0))! }))
        case 23:
            // Windows-1252: Latin-1 with printable characters where Latin-1 has C1 controls.
            return String(String.UnicodeScalarView(bytes.map { byte in
                let code = (0x80...0x9F).contains(byte) ? windows1252[Int(byte) - 0x80] : UInt32(byte)
                return Unicode.Scalar(code)!
            }))
        case 25, 33:
            // UTF-16, big-endian and little-endian.
            let units = stride(from: 0, to: bytes.count - 1, by: 2).map { i -> UInt16 in
                let (high, low) = eci == 25 ? (bytes[i], bytes[i + 1]) : (bytes[i + 1], bytes[i])
                return UInt16(high) << 8 | UInt16(low)
            }
            return String(decoding: units, as: UTF16.self)
        case 26:
            return String(decoding: bytes, as: UTF8.self)
        default:
            return String(validating: bytes, as: UTF8.self) ?? String(String.UnicodeScalarView(bytes.map { Unicode.Scalar($0) }))
        }
    }

    /// Windows-1252 from 0x80 to 0x9F. The five places it leaves unassigned keep the byte's own value.
    private static let windows1252: [UInt32] = [
        0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
        0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F,
        0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
        0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178,
    ]

    /// The places where ISO 8859-15 differs from Latin-1.
    private static let latin9: [UInt8: UInt32] = [
        0xA4: 0x20AC, 0xA6: 0x0160, 0xA8: 0x0161, 0xB4: 0x017D,
        0xB8: 0x017E, 0xBC: 0x0152, 0xBD: 0x0153, 0xBE: 0x0178,
    ]
}

private extension String {
    func leftPadded(_ width: Int) -> String { String(repeating: "0", count: max(0, width - count)) + self }
}
#endif
