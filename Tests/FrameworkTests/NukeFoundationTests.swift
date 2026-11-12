// The Foundation and Dispatch members Nuke's pipeline and Kingfisher reach for: raw DEFLATE
// through `NSData.compressed(using:)` (Nuke's disk cache), the memory pressure source its memory
// cache trims on, and `autoreleasepool`. They run against Apple's Foundation on macOS, so the
// stand-in's bytes are checked against the real decoder; Linux's Foundation has neither the
// compression nor the memory pressure source.
#if os(WASI) || canImport(Darwin)
import Testing
import WebFoundation
import WebFoundationFormats

@Suite struct NukeFoundationTests {
    /// 40 numbered lines as zlib wrote them at level 9: one block with its own (dynamic) Huffman
    /// codes, the kind a server or another device writes.
    static let text = Data(Array((0..<40).map { "line \($0): the quick brown fox\n" }.joined().utf8))
    static let zlibDynamic = "fdPNDYIAEEThu1VsCc6M4k85GAxEAtFApHxjAbzzO+2X2XGYujrea+m7eq/D41XtZ/5O9Zy3w/hvgmZogXaCdobWQLtAu0K70e0IQzIiGpGNCEekI+IR+YiAREImIeN2SMgkZBIyCZmETEImIZNQSCgkFHwvEgoJhYRCQiGhkFB2hH4="

    @Test func decompressesWhatZlibWrote() throws {
        let compressed = try #require(Data(base64Encoded: Self.zlibDynamic))
        let data = try (compressed as NSData).decompressed(using: .zlib) as Data
        #expect(data == Self.text)
    }

    @Test func compressesAndDecompressesAgain() throws {
        let compressed = try (Self.text as NSData).compressed(using: .zlib) as Data
        #expect(compressed.count < Self.text.count / 3)
        #expect(try (compressed as NSData).decompressed(using: .zlib) as Data == Self.text)

        // Bytes that do not repeat, and nothing at all.
        var state: UInt32 = 12345
        let noise = Data((0..<3000).map { _ -> UInt8 in
            state = state &* 1_103_515_245 &+ 12345
            return UInt8(truncatingIfNeeded: state >> 16)
        })
        for bytes in [noise, Data(), Data([7])] {
            let packed = try (bytes as NSData).compressed(using: .zlib) as Data
            #expect(try (packed as NSData).decompressed(using: .zlib) as Data == bytes)
        }
    }

    @Test func mutableDataCompressesInPlace() throws {
        let data = NSMutableData(data: Self.text)
        try data.compress(using: .zlib)
        #expect(data.length < Self.text.count)
        try data.decompress(using: .zlib)
        #expect(data as Data == Self.text)
    }

    @Test func rejectsBytesThatAreNotDeflate() {
        #expect(throws: (any Error).self) { try (Data([0xFF, 0xFF, 0xFF]) as NSData).decompressed(using: .zlib) }
    }

    @Test func memoryPressureSourceCancels() {
        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler {}
        source.resume()
        #expect(!source.isCancelled)
        source.cancel()
        #expect(source.isCancelled)
        #expect(DispatchSource.MemoryPressureEvent.all.contains(.critical))
    }

    @Test func autoreleasePoolReturnsTheBodysValue() {
        #expect(autoreleasepool { 41 + 1 } == 42)
    }
}
#endif
