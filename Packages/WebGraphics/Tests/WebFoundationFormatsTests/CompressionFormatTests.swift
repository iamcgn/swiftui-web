// The byte formats behind `NSData.compressed(using:)` on wasm (WebFoundationFormats'
// Compression.swift), each written and read back here, and on macOS held to Apple's own
// Compression framework: Apple decompresses what the stand-in writes for every algorithm, and the
// stand-in decompresses what Apple writes for zlib, LZ4 and small LZFSE inputs (LZVN blocks).
import Testing
import Foundation
@testable import WebFoundationFormats

@Suite struct CompressionFormatTests {
    static let text = Array((0..<400).map { "line \($0): the quick brown fox\n" }.joined().utf8)
    static let noise: [UInt8] = {
        var state: UInt32 = 12345
        return (0..<3000).map { _ -> UInt8 in
            state = state &* 1_103_515_245 &+ 12345
            return UInt8(truncatingIfNeeded: state >> 16)
        }
    }()
    /// Nothing, a byte, a few bytes, repeats, bytes that do not repeat, and a run longer than an
    /// LZ4 block and an LZMA2 chunk (64 KB).
    static let samples: [[UInt8]] = [
        [], [7], Array("abcabcabcabcabcabc".utf8), Array(text.prefix(1000)), text, noise,
        [UInt8](repeating: 0x41, count: 70000) + noise,
    ]

    @Test(arguments: _CompressionFormat.allCases) func writesAndReadsBack(_ format: _CompressionFormat) throws {
        for sample in Self.samples {
            #expect(try _decompress(_compress(sample, format), format) == sample)
        }
    }

    @Test func shrinksRepeats() {
        for format in [_CompressionFormat.zlib, .lz4, .lzfse] {
            #expect(_compress(Self.text, format).count < Self.text.count / 3)
        }
    }

    @Test func writesEachAlgorithmsOwnContainer() {
        #expect(Array(_compress(Self.text, .lz4).prefix(4)) == Array("bv41".utf8))
        #expect(Array(_compress(Self.text, .lz4).suffix(4)) == Array("bv4$".utf8))
        #expect(Array(_compress(Self.text, .lzfse).prefix(4)) == Array("bvxn".utf8))
        #expect(Array(_compress(Self.noise, .lzfse).prefix(4)) == Array("bvx-".utf8))
        #expect(Array(_compress(Self.text, .lzma).prefix(6)) == [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00])
    }

    @Test func rejectsAnotherAlgorithmsBytes() {
        let packed = _compress(Self.text, .lz4)
        for format in [_CompressionFormat.lzfse, .lzma, .zlib] {
            #expect(throws: (any Error).self) { try _decompress(packed, format) }
        }
        #expect(throws: (any Error).self) { try _decompress(_compress(Self.text, .lzfse), .lz4) }
        #expect(throws: (any Error).self) { try _decompress(Array(_compress(Self.text, .lzma).dropLast(5)), .lzma) }
        var corrupt = _compress(Self.text, .lzma)
        corrupt[40] ^= 0xFF
        #expect(throws: (any Error).self) { try _decompress(corrupt, .lzma) }
    }

    #if canImport(Darwin)
    static func apple(_ format: _CompressionFormat) -> NSData.CompressionAlgorithm {
        switch format {
        case .zlib: .zlib
        case .lz4: .lz4
        case .lzfse: .lzfse
        case .lzma: .lzma
        }
    }

    @Test(arguments: _CompressionFormat.allCases) func appleReadsWhatThisWrites(_ format: _CompressionFormat) throws {
        for sample in Self.samples where !sample.isEmpty {
            let packed = Data(_compress(sample, format)) as NSData
            let bytes = try packed.decompressed(using: Self.apple(format)) as Data
            #expect(Array(bytes) == sample, "\(format), \(sample.count) bytes")
        }
    }

    @Test(arguments: [_CompressionFormat.zlib, .lz4]) func readsWhatAppleWrote(_ format: _CompressionFormat) throws {
        for sample in Self.samples where !sample.isEmpty {
            let packed = try (Data(sample) as NSData).compressed(using: Self.apple(format)) as Data
            #expect(try _decompress(Array(packed), format) == sample, "\(format), \(sample.count) bytes")
        }
    }

    @Test func readsTheLZVNBlocksAppleWritesForSmallInputs() throws {
        for sample in [Array("abcabcabcabcabcabc".utf8), Array(Self.text.prefix(1000)), Array(Self.text.prefix(3000))] {
            let packed = Array(try (Data(sample) as NSData).compressed(using: .lzfse) as Data)
            #expect(Array(packed.prefix(4)) == Array("bvxn".utf8) || Array(packed.prefix(4)) == Array("bvx-".utf8))
            #expect(try _decompress(packed, .lzfse) == sample, "\(sample.count) bytes")
        }
        let repeats = Array(try (Data(Self.text.prefix(1000)) as NSData).compressed(using: .lzfse) as Data)
        #expect(Array(repeats.prefix(4)) == Array("bvxn".utf8))
    }
    #endif
}
