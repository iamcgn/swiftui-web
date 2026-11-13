// The zlib and gzip containers (WebFoundationFormats' ZlibContainers.swift) the `zlib` shadow
// decodes and writes: streams Python's zlib and gzip wrote decode to their bytes, what this
// writes reads back, a stream cut short says so, bytes after a stream are left unread, and the
// checksums match zlib's.
import Testing
import Foundation
@testable import WebFoundationFormats

@Suite struct ZlibContainerTests {
    static let text = Array(String(repeating: "hello hello hello gzip world\n", count: 3).utf8)
    // gzip.compress(text, mtime=0), zlib.compress(text) and a raw deflate of it, from Python.
    static let gzip: [UInt8] = [0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0xFF, 0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0x57,
                                0xC8, 0x40, 0x22, 0xD3, 0xAB, 0x32, 0x0B, 0x14, 0xCA, 0xF3, 0x8B, 0x72, 0x52, 0xB8, 0x32, 0xC8,
                                0x96, 0x04, 0x00, 0x73, 0xEB, 0xBE, 0x17, 0x57, 0x00, 0x00, 0x00]
    static let zlib: [UInt8] = [0x78, 0x9C, 0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0x57, 0xC8, 0x40, 0x22, 0xD3, 0xAB, 0x32, 0x0B, 0x14,
                                0xCA, 0xF3, 0x8B, 0x72, 0x52, 0xB8, 0x32, 0xC8, 0x96, 0x04, 0x00, 0x8A, 0x40, 0x1F, 0xF9]
    static let raw: [UInt8] = Array(zlib[2..<(zlib.count - 4)])
    // A gzip member naming its file ("notes.txt").
    static let gzipNamed: [UInt8] = [0x1F, 0x8B, 0x08, 0x08, 0x00, 0x00, 0x00, 0x00, 0x02, 0xFF]
        + Array("notes.txt".utf8) + [0] + Array(gzip[10...])

    @Test func decodesWhatZlibWrote() throws {
        #expect(try _zlibDecode(Self.gzip, wrapper: .gzip).output == Self.text)
        #expect(try _zlibDecode(Self.gzipNamed, wrapper: .gzip).output == Self.text)
        #expect(try _zlibDecode(Self.zlib, wrapper: .zlib).output == Self.text)
        #expect(try _zlibDecode(Self.raw, wrapper: .raw).output == Self.text)
        #expect(try _zlibDecode(Self.gzip, wrapper: .automatic).output == Self.text)
        #expect(try _zlibDecode(Self.zlib, wrapper: .automatic).output == Self.text)
        #expect(try _zlibDecode(Self.gzip, wrapper: .gzip).consumed == Self.gzip.count)
    }

    @Test(arguments: [_ZlibWrapper.raw, .zlib, .gzip])
    func writesAndReadsBack(_ wrapper: _ZlibWrapper) throws {
        let long = (0..<300).flatMap { Array("line \($0) of a longer body\n".utf8) }
        for sample in [[], [7], Self.text, long] as [[UInt8]] {
            let encoded = _zlibEncode(sample, wrapper: wrapper)
            let decoded = try _zlibDecode(encoded, wrapper: wrapper)
            #expect(decoded.output == sample && decoded.consumed == encoded.count)
        }
        #expect(Array(_zlibEncode(Self.text, wrapper: .gzip).prefix(3)) == [0x1F, 0x8B, 8])
        #expect(Array(_zlibEncode(Self.text, wrapper: .zlib).prefix(2)) == [0x78, 0x9C])
    }

    @Test func aStreamCutShortIsTruncatedAndABadOneInvalid() {
        #expect(throws: _ZlibDecodeError.truncated) { try _zlibDecode(Array(Self.gzip.prefix(20)), wrapper: .gzip) }
        #expect(throws: _ZlibDecodeError.truncated) { try _zlibDecode(Array(Self.gzip.dropLast(3)), wrapper: .gzip) }
        #expect(throws: _ZlibDecodeError.truncated) { try _zlibDecode(Array(Self.zlib.prefix(1)), wrapper: .zlib) }
        var corrupt = Self.gzip
        corrupt[corrupt.count - 6] ^= 0xFF   // the CRC
        #expect(throws: _ZlibDecodeError.invalid) { try _zlibDecode(corrupt, wrapper: .gzip) }
        #expect(throws: _ZlibDecodeError.invalid) { try _zlibDecode(Self.zlib, wrapper: .gzip) }
        #expect(throws: _ZlibDecodeError.invalid) { try _zlibDecode([0x78, 0x9D, 0], wrapper: .zlib) }
    }

    @Test func bytesAfterTheStreamAreLeftUnread() throws {
        let decoded = try _zlibDecode(Self.zlib + [1, 2, 3], wrapper: .zlib)
        #expect(decoded.output == Self.text && decoded.consumed == Self.zlib.count)
    }

    @Test func windowBitsPickTheWrapper() {
        #expect(_ZlibWrapper(windowBits: -15) == .raw)
        #expect(_ZlibWrapper(windowBits: 15) == .zlib)
        #expect(_ZlibWrapper(windowBits: 15 + 16) == .gzip)
        #expect(_ZlibWrapper(windowBits: 15 + 32) == .automatic)
        #expect(_ZlibWrapper(windowBits: 7) == nil)
    }

    @Test func checksumsMatchZlibs() {
        #expect(_zlibCRC32(0, Array("123456789".utf8)) == 0xCBF4_3926)
        #expect(_zlibAdler32(1, Array("Wikipedia".utf8)) == 0x11E6_0398)
        #expect(_zlibAdler32(1, [UInt8](repeating: 0x61, count: 100_000)) == 0x7966_0B4D)
        // Continued in pieces, as a stream computes them.
        let all = Array("123456789".utf8)
        #expect(_zlibCRC32(_zlibCRC32(0, all[..<4]), all[4...]) == 0xCBF4_3926)
    }
}
