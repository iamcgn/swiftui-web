// Foundation's string encodings on wasm (pf-web-foundation-gaps): FoundationEssentials'
// `String.Encoding` with the conversions between strings and WebFoundation's `Data` that apps
// write through `String(data:encoding:)` and `data(using:)`.
// `_TextEncoding` is the platform-neutral core, held to Foundation on macOS: UTF-8, ASCII,
// ISO Latin 1, Windows-1252, UTF-16 and UTF-32 in both byte orders and with a byte-order
// mark. The other legacy encodings (Shift JIS, EUC, the ISO 2022 and Mac encodings) are not
// carried; converting through them gives nil, as Foundation gives nil for text an encoding
// cannot hold.

package enum _TextEncoding: Hashable, Sendable {
    case utf8, ascii, isoLatin1, windows1252, utf16, utf16BigEndian, utf16LittleEndian, utf32, utf32BigEndian, utf32LittleEndian

    /// The bytes of `text`, nil when a character has no code in the encoding. `utf16` and
    /// `utf32` write a byte-order mark and little-endian units, as Foundation writes them.
    package static func encode(_ text: String, as encoding: _TextEncoding, lossy: Bool = false) -> [UInt8]? {
        switch encoding {
        case .utf8: return Array(text.utf8)
        case .ascii:
            var bytes: [UInt8] = []
            for scalar in text.unicodeScalars {
                if scalar.value < 0x80 { bytes.append(UInt8(scalar.value)) } else if lossy { bytes.append(0x3F) } else { return nil }
            }
            return bytes
        case .isoLatin1:
            var bytes: [UInt8] = []
            for scalar in text.unicodeScalars {
                if scalar.value < 0x100 { bytes.append(UInt8(scalar.value)) } else if lossy { bytes += questionMarks(scalar) } else { return nil }
            }
            return bytes
        case .windows1252:
            var bytes: [UInt8] = []
            for scalar in text.unicodeScalars {
                if scalar.value < 0x80 || (scalar.value >= 0xA0 && scalar.value < 0x100) {
                    bytes.append(UInt8(scalar.value))
                } else if let index = windows1252High.firstIndex(of: scalar.value), windows1252High[index] != 0xFFFD {
                    bytes.append(UInt8(0x80 + index))
                } else if lossy { bytes += questionMarks(scalar) } else { return nil }
            }
            return bytes
        case .utf16, .utf16LittleEndian, .utf16BigEndian:
            var bytes: [UInt8] = encoding == .utf16 ? [0xFF, 0xFE] : []
            let little = encoding != .utf16BigEndian
            for unit in text.utf16 {
                let high = UInt8(unit >> 8), low = UInt8(unit & 0xFF)
                bytes += little ? [low, high] : [high, low]
            }
            return bytes
        case .utf32, .utf32LittleEndian, .utf32BigEndian:
            var bytes: [UInt8] = encoding == .utf32 ? [0xFF, 0xFE, 0x00, 0x00] : []
            let little = encoding != .utf32BigEndian
            for scalar in text.unicodeScalars {
                let v = scalar.value
                let parts = [UInt8(v >> 24), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)]
                bytes += little ? parts.reversed() : parts
            }
            return bytes
        }
    }

    /// A lossy stand-in: one question mark per UTF-16 unit, as Foundation writes for a
    /// character outside Latin 1 or Windows-1252 (ASCII gets one per character; Foundation also
    /// strips Latin diacritics there, a table not carried).
    private static func questionMarks(_ scalar: Unicode.Scalar) -> [UInt8] { Array(repeating: 0x3F, count: scalar.utf16.count) }

    /// The text of `bytes`, nil when they are not valid in the encoding. `utf16` and `utf32`
    /// read a byte-order mark and default to big-endian without one, as Foundation reads them.
    package static func decode(_ bytes: [UInt8], as encoding: _TextEncoding) -> String? {
        switch encoding {
        case .utf8:
            var decoder = UTF8()
            var iterator = bytes.makeIterator()
            var scalars = String.UnicodeScalarView()
            loop: while true {
                switch decoder.decode(&iterator) {
                case .scalarValue(let scalar): scalars.append(scalar)
                case .emptyInput: break loop
                case .error: return nil
                }
            }
            return String(scalars)
        case .ascii:
            guard bytes.allSatisfy({ $0 < 0x80 }) else { return nil }
            return String(decoding: bytes, as: UTF8.self)
        case .isoLatin1:
            var scalars = String.UnicodeScalarView()
            for byte in bytes { scalars.append(Unicode.Scalar(byte)) }
            return String(scalars)
        case .windows1252:
            var scalars = String.UnicodeScalarView()
            for byte in bytes {
                if byte >= 0x80, byte < 0xA0 {
                    let value = windows1252High[Int(byte - 0x80)]
                    guard value != 0xFFFD, let scalar = Unicode.Scalar(value) else { return nil }
                    scalars.append(scalar)
                } else {
                    scalars.append(Unicode.Scalar(byte))
                }
            }
            return String(scalars)
        case .utf16, .utf16LittleEndian, .utf16BigEndian:
            var little = encoding == .utf16LittleEndian
            var start = 0
            if encoding == .utf16, bytes.count >= 2 {
                if bytes[0] == 0xFF, bytes[1] == 0xFE { little = true; start = 2 } else if bytes[0] == 0xFE, bytes[1] == 0xFF { start = 2 }
            }
            guard (bytes.count - start) % 2 == 0 else { return nil }
            var units: [UInt16] = []
            units.reserveCapacity((bytes.count - start) / 2)
            var index = start
            while index < bytes.count {
                let a = UInt16(bytes[index]), b = UInt16(bytes[index + 1])
                units.append(little ? b << 8 | a : a << 8 | b)
                index += 2
            }
            var decoder = UTF16()
            var iterator = units.makeIterator()
            var scalars = String.UnicodeScalarView()
            loop: while true {
                switch decoder.decode(&iterator) {
                case .scalarValue(let scalar): scalars.append(scalar)
                case .emptyInput: break loop
                case .error: return nil
                }
            }
            return String(scalars)
        case .utf32, .utf32LittleEndian, .utf32BigEndian:
            var little = encoding == .utf32LittleEndian
            var start = 0
            if encoding == .utf32, bytes.count >= 4 {
                if bytes[0] == 0xFF, bytes[1] == 0xFE, bytes[2] == 0, bytes[3] == 0 { little = true; start = 4 }
                else if bytes[0] == 0, bytes[1] == 0, bytes[2] == 0xFE, bytes[3] == 0xFF { start = 4 }
            }
            guard (bytes.count - start) % 4 == 0 else { return nil }
            var scalars = String.UnicodeScalarView()
            var index = start
            while index < bytes.count {
                let b = bytes[index..<(index + 4)].map(UInt32.init)
                let value = little ? b[3] << 24 | b[2] << 16 | b[1] << 8 | b[0] : b[0] << 24 | b[1] << 16 | b[2] << 8 | b[3]
                guard let scalar = Unicode.Scalar(value) else { return nil }
                scalars.append(scalar)
                index += 4
            }
            return String(scalars)
        }
    }

    /// Windows-1252's 0x80–0x9F (0xFFFD where the code is unassigned).
    private static let windows1252High: [UInt32] = [
        0x20AC, 0xFFFD, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0xFFFD, 0x017D, 0xFFFD,
        0xFFFD, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0xFFFD, 0x017E, 0x0178,
    ]
}

#if os(WASI)
import FoundationEssentials

extension String.Encoding {
    /// The core's encoding, nil for the legacy ones the bundle does not carry.
    var _core: _TextEncoding? {
        switch self {
        case .utf8: return .utf8
        case .ascii, .nonLossyASCII: return .ascii
        case .isoLatin1: return .isoLatin1
        case .windowsCP1252: return .windows1252
        case .utf16: return .utf16
        case .utf16BigEndian: return .utf16BigEndian
        case .utf16LittleEndian: return .utf16LittleEndian
        case .utf32: return .utf32
        case .utf32BigEndian: return .utf32BigEndian
        case .utf32LittleEndian: return .utf32LittleEndian
        default: return nil
        }
    }

    /// Foundation's names for the encodings.
    public var _name: String {
        switch self {
        case .utf8: return "Unicode (UTF-8)"
        case .ascii: return "Western (ASCII)"
        case .isoLatin1: return "Western (ISO Latin 1)"
        case .windowsCP1252: return "Western (Windows Latin 1)"
        case .utf16: return "Unicode (UTF-16)"
        case .utf16BigEndian: return "Unicode (UTF-16BE)"
        case .utf16LittleEndian: return "Unicode (UTF-16LE)"
        case .utf32: return "Unicode (UTF-32)"
        case .utf32BigEndian: return "Unicode (UTF-32BE)"
        case .utf32LittleEndian: return "Unicode (UTF-32LE)"
        default: return "String.Encoding(rawValue: \(rawValue))"
        }
    }
}

extension String {
    public static var defaultCStringEncoding: Encoding { .utf8 }
    public static var availableStringEncodings: [Encoding] { [.utf8, .ascii, .isoLatin1, .windowsCP1252, .utf16, .utf16BigEndian, .utf16LittleEndian, .utf32, .utf32BigEndian, .utf32LittleEndian] }

    /// The string the bytes spell in `encoding`, nil when they are not valid in it.
    public init?(data: Data, encoding: Encoding) {
        guard let core = encoding._core, let text = _TextEncoding.decode(data.bytes, as: core) else { return nil }
        self = text
    }
    public init?<S: Sequence>(bytes: S, encoding: Encoding) where S.Element == UInt8 {
        guard let core = encoding._core, let text = _TextEncoding.decode(Array(bytes), as: core) else { return nil }
        self = text
    }
    public init?(cString bytes: [UInt8], encoding: Encoding) {
        guard let core = encoding._core, let text = _TextEncoding.decode(Array(bytes.prefix { $0 != 0 }), as: core) else { return nil }
        self = text
    }

    /// The core's bytes for this string (the public forms are ambiguous inside the module).
    private func _bytes(_ encoding: Encoding) -> [UInt8]? {
        encoding._core.flatMap { _TextEncoding.encode(self, as: $0) }
    }

    /// The bytes of the string in `encoding`, nil when a character has no code in it (a
    /// question mark with `allowLossyConversion`).
    public func data(using encoding: Encoding, allowLossyConversion: Bool = false) -> Data? {
        guard let core = encoding._core, let bytes = _TextEncoding.encode(self, as: core, lossy: allowLossyConversion) else { return nil }
        return Data(bytes)
    }
    public func lengthOfBytes(using encoding: Encoding) -> Int { _bytes(encoding)?.count ?? 0 }
    public func maximumLengthOfBytes(using encoding: Encoding) -> Int {
        switch encoding._core {
        case .utf8: return utf8.count
        case .utf16, .utf16BigEndian, .utf16LittleEndian: return utf16.count * 2 + 2
        case .utf32, .utf32BigEndian, .utf32LittleEndian: return unicodeScalars.count * 4 + 4
        case .ascii, .isoLatin1, .windows1252: return unicodeScalars.count
        case nil: return 0
        }
    }
    public func canBeConverted(to encoding: Encoding) -> Bool { _bytes(encoding) != nil }
    public func cString(using encoding: Encoding) -> [CChar]? {
        _bytes(encoding).map { $0.map { CChar(bitPattern: $0) } + [0] }
    }
    public var fastestEncoding: Encoding { .utf8 }
    public var smallestEncoding: Encoding { unicodeScalars.allSatisfy { $0.value < 0x80 } ? .ascii : .utf8 }
}
#endif
