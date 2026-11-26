// CGFont read from a font file's bytes: a hand-built TrueType file with the tables CGFont reads.
#if !canImport(CoreGraphics) || os(WASI)
import Testing
import WebFoundation
import WebGraphics

private func be16(_ value: Int) -> [UInt8] { [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)] }
private func be32(_ value: Int) -> [UInt8] { be16(value >> 16) + be16(value & 0xFFFF) }

/// A TrueType file with head, hhea, maxp, OS/2 and name tables (Windows names, UTF-16BE).
private func fontFile(postScript: String, family: String) -> [UInt8] {
    var head = [UInt8](repeating: 0, count: 54)
    head.replaceSubrange(18..<20, with: be16(1000))
    var hhea = [UInt8](repeating: 0, count: 36)
    hhea.replaceSubrange(4..<6, with: be16(800))
    hhea.replaceSubrange(6..<8, with: be16(0x10000 - 200))
    hhea.replaceSubrange(8..<10, with: be16(90))
    var maxp = [UInt8](repeating: 0, count: 6)
    maxp.replaceSubrange(4..<6, with: be16(42))
    var os2 = [UInt8](repeating: 0, count: 96)
    os2.replaceSubrange(0..<2, with: be16(2))
    os2.replaceSubrange(86..<88, with: be16(500))
    os2.replaceSubrange(88..<90, with: be16(700))
    let strings = [(1, family), (6, postScript)].map { ($0.0, Array($0.1.utf16).flatMap { be16(Int($0)) }) }
    var name = be16(0) + be16(strings.count) + be16(6 + strings.count * 12)
    var storage: [UInt8] = []
    for (id, bytes) in strings {
        name += be16(3) + be16(1) + be16(0x409) + be16(id) + be16(bytes.count) + be16(storage.count)
        storage += bytes
    }
    name += storage
    let tables: [(String, [UInt8])] = [("OS/2", os2), ("head", head), ("hhea", hhea), ("maxp", maxp), ("name", name)]
    var file = be32(0x0001_0000) + be16(tables.count) + be16(0) + be16(0) + be16(0)
    var offset = 12 + tables.count * 16
    var body: [UInt8] = []
    for (tag, bytes) in tables {
        file += Array(tag.utf8) + be32(0) + be32(offset) + be32(bytes.count)
        body += bytes
        offset += bytes.count
    }
    return file + body
}

@Suite struct CGFontTests {
    @Test func readsNamesAndMetrics() throws {
        let provider = try #require(CGDataProvider(data: Data(fontFile(postScript: ".PhoneKeyCaps", family: "Phone Key Caps"))))
        let font = try #require(CGFont(provider))
        #expect(font.postScriptName == ".PhoneKeyCaps")
        #expect(font.familyName == "Phone Key Caps")
        #expect(font.unitsPerEm == 1000 && font.ascent == 800 && font.descent == -200 && font.leading == 90)
        #expect(font.xHeight == 500 && font.capHeight == 700 && font.numberOfGlyphs == 42)
    }

    @Test func rejectsWhatIsNotAFont() {
        #expect(CGFont(CGDataProvider(data: Data([1, 2, 3, 4]))!) == nil)
        #expect(CGFont(CGDataProvider(data: Data())!) == nil)
    }
}
#endif
