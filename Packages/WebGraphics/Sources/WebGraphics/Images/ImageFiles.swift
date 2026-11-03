// What an image file says about itself (Docs/elements/UIKit/Drawing.md, "Images from data"):
// its format, its pixel size, its frames and their delays, and the EXIF orientation of a JPEG,
// read from the headers alone. The painters decode the pixels (a data URL in the browser), so
// `UIImage(data:)`, `CGImageSource` and the image types on wasm only need what a header holds.
// `_PNGEncoder` writes a bitmap as a PNG (stored deflate blocks): the bytes a `CGImage` made
// from pixels hands to a painter or to `pngData()`.

/// The header facts of a PNG, JPEG, GIF or WebP file.
public struct _ImageFileInfo: Equatable, Sendable {
    public enum Kind: String, Sendable {
        case png, jpeg, gif, webp

        /// The MIME subtype (`image/png`) and the uniform type identifier (`public.png`).
        public var mimeType: String { "image/\(rawValue)" }
        public var typeIdentifier: String {
            switch self {
            case .png: return "public.png"
            case .jpeg: return "public.jpeg"
            case .gif: return "com.compuserve.gif"
            case .webp: return "org.webmproject.webp"
            }
        }
    }

    public var kind: Kind
    /// Width and height in pixels (of the canvas, for an animated file).
    public var pixelWidth: Int
    public var pixelHeight: Int
    /// The frames of an animated GIF, APNG or WebP (1 for a still image).
    public var frameCount = 1
    /// Each frame's delay in seconds as the file states it (empty for a still image).
    public var frameDelays: [Double] = []
    /// How many times an animation plays (0: forever); nil when the file does not say.
    public var loopCount: Int?
    /// The EXIF orientation of a JPEG (1…8, 1 is upright).
    public var orientation = 1
    /// The pixel size as the image shows: width and height swapped for an orientation that turns
    /// the image a quarter (5…8). Browsers decode files upright, so this is the drawn size.
    public var uprightPixelSize: (width: Int, height: Int) {
        orientation >= 5 ? (pixelHeight, pixelWidth) : (pixelWidth, pixelHeight)
    }

    public init(kind: Kind, pixelWidth: Int, pixelHeight: Int) {
        self.kind = kind
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    /// Reads the header of `bytes`; nil for a file of another format or a truncated header.
    public init?<Bytes: Collection>(_ bytes: Bytes) where Bytes.Element == UInt8 {
        let b = Array(bytes)
        if b.count >= 24, b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 {
            self.init(png: b)
        } else if b.count >= 4, b[0] == 0xFF, b[1] == 0xD8 {
            guard let info = Self.jpeg(b) else { return nil }
            self = info
        } else if b.count >= 10, b[0] == 0x47, b[1] == 0x49, b[2] == 0x46, b[3] == 0x38 {
            guard let info = Self.gif(b) else { return nil }
            self = info
        } else if b.count >= 30, Self.ascii(b, 0, 4) == "RIFF", Self.ascii(b, 8, 4) == "WEBP" {
            guard let info = Self.webp(b) else { return nil }
            self = info
        } else {
            return nil
        }
    }

    /// The format of `bytes` from its signature alone (the first bytes), or nil.
    public static func kind<Bytes: Collection>(of bytes: Bytes) -> Kind? where Bytes.Element == UInt8 {
        let b = Array(bytes.prefix(12))
        if b.count >= 4, b[0] == 0x89, b[1] == 0x50, b[2] == 0x4E, b[3] == 0x47 { return .png }
        if b.count >= 3, b[0] == 0xFF, b[1] == 0xD8, b[2] == 0xFF { return .jpeg }
        if b.count >= 4, b[0] == 0x47, b[1] == 0x49, b[2] == 0x46, b[3] == 0x38 { return .gif }
        if b.count >= 12, ascii(b, 0, 4) == "RIFF", ascii(b, 8, 4) == "WEBP" { return .webp }
        return nil
    }

    // MARK: PNG (and APNG's animation control and frame control chunks)

    private init(png b: [UInt8]) {
        self.init(kind: .png, pixelWidth: Self.be32(b, 16), pixelHeight: Self.be32(b, 20))
        var i = 8
        var delays: [Double] = []
        while i + 12 <= b.count {
            let length = Self.be32(b, i)
            let type = Self.ascii(b, i + 4, 4)
            let body = i + 8
            if type == "acTL", body + 8 <= b.count {
                frameCount = max(1, Self.be32(b, body))
                loopCount = Self.be32(b, body + 4)
            } else if type == "fcTL", body + 24 <= b.count {
                let numerator = Double(Self.be16(b, body + 20))
                let denominator = Double(Self.be16(b, body + 22))
                delays.append(numerator / (denominator == 0 ? 100 : denominator))
            } else if type == "IDAT" || type == "IEND" {
                if frameCount == 1 { break }   // a still PNG: nothing more to read
            }
            i = body + length + 4
        }
        if frameCount > 1 { frameDelays = delays }
    }

    // MARK: JPEG

    private static func jpeg(_ b: [UInt8]) -> _ImageFileInfo? {
        var i = 2
        var orientation = 1
        while i + 9 < b.count {
            guard b[i] == 0xFF else { i += 1; continue }
            let marker = b[i + 1]
            if marker == 0xD8 || (0xD0...0xD7).contains(marker) || marker == 0x01 || marker == 0xFF { i += 2; continue }
            let length = be16(b, i + 2)
            if marker == 0xE1, ascii(b, i + 4, 4) == "Exif" {
                orientation = exifOrientation(b, tiff: i + 10) ?? orientation
            }
            if (0xC0...0xCF).contains(marker), marker != 0xC4, marker != 0xC8, marker != 0xCC {
                var info = _ImageFileInfo(kind: .jpeg, pixelWidth: be16(b, i + 7), pixelHeight: be16(b, i + 5))
                info.orientation = orientation
                return info
            }
            i += 2 + length
        }
        return nil
    }

    /// The orientation tag (0x0112) of the first image file directory of a TIFF block.
    private static func exifOrientation(_ b: [UInt8], tiff: Int) -> Int? {
        guard tiff + 8 <= b.count else { return nil }
        let little = b[tiff] == 0x49
        func u16(_ at: Int) -> Int { little ? Int(b[at]) | Int(b[at + 1]) << 8 : be16(b, at) }
        func u32(_ at: Int) -> Int { little ? u16(at) | u16(at + 2) << 16 : be32(b, at) }
        let directory = tiff + u32(tiff + 4)
        guard directory + 2 <= b.count else { return nil }
        let entries = u16(directory)
        for n in 0..<entries {
            let entry = directory + 2 + n * 12
            guard entry + 12 <= b.count else { return nil }
            if u16(entry) == 0x0112 {
                let value = u16(entry + 8)
                return (1...8).contains(value) ? value : nil
            }
        }
        return nil
    }

    // MARK: GIF

    private static func gif(_ b: [UInt8]) -> _ImageFileInfo? {
        var info = _ImageFileInfo(kind: .gif, pixelWidth: le16(b, 6), pixelHeight: le16(b, 8))
        var i = 13
        if b[10] & 0x80 != 0 { i += 3 << (Int(b[10] & 0x07) + 1) }   // the global colour table
        var frames = 0
        var delays: [Double] = []
        var pendingDelay: Double?
        func skipSubBlocks(_ at: Int) -> Int {
            var j = at
            while j < b.count, b[j] != 0 { j += Int(b[j]) + 1 }
            return j + 1
        }
        while i < b.count {
            switch b[i] {
            case 0x21:   // an extension
                guard i + 2 < b.count else { i = b.count; break }
                let label = b[i + 1]
                if label == 0xF9, i + 6 < b.count {
                    pendingDelay = Double(le16(b, i + 4)) / 100
                } else if label == 0xFF, i + 14 < b.count, ascii(b, i + 3, 11) == "NETSCAPE2.0", i + 18 < b.count {
                    info.loopCount = le16(b, i + 16)
                }
                i = skipSubBlocks(i + 2)
            case 0x2C:   // an image: its descriptor, local colour table and LZW data
                guard i + 10 <= b.count else { i = b.count; break }
                frames += 1
                delays.append(pendingDelay ?? 0)
                pendingDelay = nil
                var j = i + 10
                if b[i + 9] & 0x80 != 0 { j += 3 << (Int(b[i + 9] & 0x07) + 1) }
                i = skipSubBlocks(j + 1)
            default:     // the trailer, or bytes past it
                i = b.count
            }
        }
        info.frameCount = max(1, frames)
        if frames > 1 { info.frameDelays = delays }
        return info
    }

    // MARK: WebP

    private static func webp(_ b: [UInt8]) -> _ImageFileInfo? {
        var info: _ImageFileInfo?
        var delays: [Double] = []
        var i = 12
        while i + 8 <= b.count {
            let type = ascii(b, i, 4)
            let size = le32(b, i + 4)
            let body = i + 8
            switch type {
            case "VP8X" where body + 10 <= b.count:
                info = _ImageFileInfo(kind: .webp, pixelWidth: le24(b, body + 4) + 1, pixelHeight: le24(b, body + 7) + 1)
            case "VP8 " where body + 10 <= b.count && info == nil:
                info = _ImageFileInfo(kind: .webp, pixelWidth: le16(b, body + 6) & 0x3FFF, pixelHeight: le16(b, body + 8) & 0x3FFF)
            case "VP8L" where body + 5 <= b.count && info == nil:
                let bits = le32(b, body + 1)
                info = _ImageFileInfo(kind: .webp, pixelWidth: (bits & 0x3FFF) + 1, pixelHeight: ((bits >> 14) & 0x3FFF) + 1)
            case "ANIM" where body + 6 <= b.count:
                info?.loopCount = le16(b, body + 4)
            case "ANMF" where body + 16 <= b.count:
                delays.append(Double(le24(b, body + 12)) / 1000)
            default:
                break
            }
            i = body + size + (size & 1)
        }
        if delays.count > 1 {
            info?.frameCount = delays.count
            info?.frameDelays = delays
        }
        return info
    }

    // MARK: Bytes

    private static func be16(_ b: [UInt8], _ i: Int) -> Int { i + 1 < b.count ? Int(b[i]) << 8 | Int(b[i + 1]) : 0 }
    private static func be32(_ b: [UInt8], _ i: Int) -> Int { be16(b, i) << 16 | be16(b, i + 2) }
    private static func le16(_ b: [UInt8], _ i: Int) -> Int { i + 1 < b.count ? Int(b[i]) | Int(b[i + 1]) << 8 : 0 }
    private static func le24(_ b: [UInt8], _ i: Int) -> Int { le16(b, i) | (i + 2 < b.count ? Int(b[i + 2]) << 16 : 0) }
    private static func le32(_ b: [UInt8], _ i: Int) -> Int { le16(b, i) | le16(b, i + 2) << 16 }
    private static func ascii(_ b: [UInt8], _ i: Int, _ count: Int) -> String {
        guard i >= 0, i + count <= b.count else { return "" }
        return String(decoding: b[i..<(i + count)], as: UTF8.self)
    }
}

/// Writes RGBA pixels as a PNG file: 8-bit straight-alpha RGBA, unfiltered rows in stored
/// (uncompressed) deflate blocks, so no compressor ships in the bundle.
public enum _PNGEncoder {
    /// A PNG of `width` × `height` pixels from packed RGBA rows; `premultiplied` pixels are
    /// divided by their alpha first, as PNG stores straight alpha.
    public static func encode(width: Int, height: Int, rgba pixels: [UInt8], premultiplied: Bool = true) -> [UInt8] {
        precondition(width > 0 && height > 0 && pixels.count >= width * height * 4, "a PNG needs width × height × 4 bytes")
        var raw: [UInt8] = []
        raw.reserveCapacity(height * (width * 4 + 1))
        for y in 0..<height {
            raw.append(0)   // filter: none
            for x in 0..<width {
                let p = (y * width + x) * 4
                let a = pixels[p + 3]
                if premultiplied, a != 0, a != 255 {
                    for c in 0..<3 { raw.append(UInt8(min(255, (Int(pixels[p + c]) * 255 + Int(a) / 2) / Int(a)))) }
                } else {
                    raw += pixels[p..<(p + 3)]
                }
                raw.append(a)
            }
        }
        var zlib: [UInt8] = [0x78, 0x01]
        var offset = 0
        repeat {
            let count = min(65_535, raw.count - offset)
            let last: UInt8 = offset + count == raw.count ? 1 : 0
            zlib += [last, UInt8(count & 0xFF), UInt8(count >> 8), UInt8(~count & 0xFF), UInt8((~count >> 8) & 0xFF)]
            zlib += raw[offset..<(offset + count)]
            offset += count
        } while offset < raw.count
        zlib += bigEndian(adler32(raw))

        var png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        png += chunk("IHDR", bigEndian(UInt32(width)) + bigEndian(UInt32(height)) + [8, 6, 0, 0, 0])
        png += chunk("IDAT", zlib)
        png += chunk("IEND", [])
        return png
    }

    private static func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
        let typed = Array(type.utf8) + body
        return bigEndian(UInt32(body.count)) + typed + bigEndian(crc32(typed))
    }

    private static func bigEndian(_ value: UInt32) -> [UInt8] {
        [UInt8(value >> 24), UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }

    private static func adler32(_ bytes: [UInt8]) -> UInt32 {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in bytes {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        return b << 16 | a
    }

    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xEDB8_8320 : crc >> 1 }
        }
        return ~crc
    }
}
