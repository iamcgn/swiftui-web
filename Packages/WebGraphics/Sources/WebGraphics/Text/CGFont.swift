// CoreGraphics's `CGFont` where there is no CoreGraphics (wasm and Linux; Apple platforms keep
// Apple's): a font file read from a data provider. The page draws text with the fonts the
// browser has loaded (the canvas host loads the app's bundled fonts under their PostScript and
// family names), so a `CGFont` doesn't draw: it reads the file's `name`, `head`, `hhea`,
// `OS/2` and `maxp` tables for the names and metrics apps ask for, and Core Text's
// `CTFontCreateWithGraphicsFont` turns it into a font by its PostScript name.

#if !canImport(CoreGraphics) || os(WASI)
#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif

public final class CGFont: @unchecked Sendable {
    /// The PostScript name (name ID 6), or nil when the file has none.
    public let postScriptName: String?
    /// The full name (name ID 4).
    public let fullName: String?
    /// The family name (name ID 1).
    public let familyName: String?
    public let unitsPerEm: Int32
    public let ascent: Int32
    /// Negative, as Apple's is.
    public let descent: Int32
    public let leading: Int32
    public let capHeight: Int32
    public let xHeight: Int32
    public let numberOfGlyphs: Int

    /// The first font in a TrueType, OpenType or TrueType collection file; nil when the bytes
    /// aren't one.
    public convenience init?(_ provider: CGDataProvider) {
        guard let data = provider.data else { return nil }
        self.init(bytes: [UInt8](data))
    }

    /// A font by name: one the app registered or bundled. Nothing is read, so the metrics are
    /// a 2048-unit em's.
    public init?(_ name: String) {
        guard !name.isEmpty else { return nil }
        postScriptName = name; fullName = name; familyName = name
        unitsPerEm = 2048; ascent = 1900; descent = -500; leading = 0; capHeight = 1456; xHeight = 1062; numberOfGlyphs = 0
    }

    init?(bytes: [UInt8]) {
        let reader = SFNTReader(bytes: bytes)
        guard let offset = reader.fontOffset(), let tables = reader.tables(at: offset) else { return nil }
        guard let head = tables["head"], let unitsPerEm = reader.u16(head + 18), unitsPerEm > 0 else { return nil }
        self.unitsPerEm = Int32(unitsPerEm)
        let hhea = tables["hhea"]
        ascent = Int32(hhea.flatMap { reader.i16($0 + 4) } ?? 0)
        descent = Int32(hhea.flatMap { reader.i16($0 + 6) } ?? 0)
        leading = Int32(hhea.flatMap { reader.i16($0 + 8) } ?? 0)
        let os2 = tables["OS/2"]
        let version = os2.flatMap { reader.u16($0) } ?? 0
        xHeight = version >= 2 ? Int32(os2.flatMap { reader.i16($0 + 86) } ?? 0) : 0
        capHeight = version >= 2 ? Int32(os2.flatMap { reader.i16($0 + 88) } ?? 0) : 0
        numberOfGlyphs = Int(tables["maxp"].flatMap { reader.u16($0 + 4) } ?? 0)
        let names = tables["name"].map { reader.names(at: $0) } ?? [:]
        postScriptName = names[6]
        fullName = names[4] ?? names[6]
        familyName = names[1]
    }

    public var fontBBox: CGRect {
        CGRect(x: 0, y: CGFloat(descent), width: CGFloat(unitsPerEm), height: CGFloat(ascent - descent))
    }
    public var italicAngle: CGFloat { 0 }
    public var stemV: CGFloat { 0 }
}

/// Big-endian reads over a font file's bytes.
private struct SFNTReader {
    let bytes: [UInt8]

    func u16(_ at: Int) -> UInt16? {
        guard at >= 0, at + 2 <= bytes.count else { return nil }
        return UInt16(bytes[at]) << 8 | UInt16(bytes[at + 1])
    }
    func i16(_ at: Int) -> Int16? { u16(at).map { Int16(bitPattern: $0) } }
    func u32(_ at: Int) -> UInt32? {
        guard let hi = u16(at), let lo = u16(at + 2) else { return nil }
        return UInt32(hi) << 16 | UInt32(lo)
    }

    /// Where the first font's table directory starts: 0 for a single font, the first entry of
    /// a collection's offset table for `ttcf`.
    func fontOffset() -> Int? {
        guard let tag = u32(0) else { return nil }
        if tag == 0x7474_6366 {   // 'ttcf'
            guard let count = u32(8), count > 0, let first = u32(12) else { return nil }
            return Int(first)
        }
        return 0
    }

    /// The table directory at `offset`: each table's offset by its tag.
    func tables(at offset: Int) -> [String: Int]? {
        guard let version = u32(offset),
              version == 0x0001_0000 || version == 0x4F54_544F || version == 0x7472_7565,   // 1.0, 'OTTO', 'true'
              let count = u16(offset + 4) else { return nil }
        var tables: [String: Int] = [:]
        for index in 0..<Int(count) {
            let record = offset + 12 + index * 16
            guard record + 16 <= bytes.count, let tableOffset = u32(record + 8) else { return nil }
            let tag = String(decoding: bytes[record..<record + 4], as: UTF8.self)
            tables[tag] = Int(tableOffset)
        }
        return tables
    }

    /// The `name` table's strings by name ID, preferring Windows (UTF-16BE) and Unicode
    /// records, then Macintosh Roman ones read as Latin-1.
    func names(at table: Int) -> [Int: String] {
        guard let count = u16(table + 2), let storage = u16(table + 4) else { return [:] }
        var unicode: [Int: String] = [:]
        var mac: [Int: String] = [:]
        for index in 0..<Int(count) {
            let record = table + 6 + index * 12
            guard let platform = u16(record), let id = u16(record + 6), let length = u16(record + 8),
                  let offset = u16(record + 10) else { break }
            let start = table + Int(storage) + Int(offset)
            let end = start + Int(length)
            guard start >= 0, end <= bytes.count else { continue }
            let slice = Array(bytes[start..<end])
            switch platform {
            case 0, 3:
                guard unicode[Int(id)] == nil else { continue }
                var units: [UInt16] = []
                var i = 0
                while i + 1 < slice.count { units.append(UInt16(slice[i]) << 8 | UInt16(slice[i + 1])); i += 2 }
                unicode[Int(id)] = String(decoding: units, as: UTF16.self)
            case 1:
                guard mac[Int(id)] == nil else { continue }
                mac[Int(id)] = String(slice.map { Character(Unicode.Scalar($0)) })
            default:
                continue
            }
        }
        return unicode.merging(mac) { first, _ in first }
    }
}
#endif
