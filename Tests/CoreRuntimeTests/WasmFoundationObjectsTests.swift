// The wasm stand-ins for Foundation objects that packages importing only Foundation reach for:
// attributed strings (ATProtoKit, SwiftyFORM), file handles and NSLog (SwiftyBeaver's file
// destination).
#if os(WASI)
import Testing
import WebFoundation

@Suite(.serialized) struct WasmFoundationObjectsTests {
    @Test func attributedStringsEditAndCompare() {
        let bold = NSAttributedString.Key("Bold")
        let text = NSMutableAttributedString(string: "hello world")
        text.beginEditing()
        text.addAttribute(bold, value: true, range: NSRange(location: 0, length: 5))
        text.insert(NSAttributedString(string: ">> "), at: 0)
        text.endEditing()
        #expect(text.string == ">> hello world")
        var range = NSRange(location: 0, length: 0)
        let boldValue = text.attribute(bold, at: 4, effectiveRange: &range) as? Bool
        #expect(boldValue == true && range == NSRange(location: 3, length: 5))
        #expect(text.attribute(bold, at: 0, effectiveRange: nil) == nil)

        text.replaceCharacters(in: NSRange(location: 9, length: 5), with: NSAttributedString(string: "there", attributes: [bold: true]))
        text.deleteCharacters(in: NSRange(location: 0, length: 3))
        #expect(text.string == "hello there")

        let copy = text.mutableCopy() as! NSMutableAttributedString
        #expect(copy == text && copy !== text)
        copy.removeAttribute(bold, range: NSRange(location: 0, length: copy.length))
        #expect(copy != text && copy == NSAttributedString(string: "hello there"))

        var longest = NSRange(location: 0, length: 0)
        _ = text.attributes(at: 1, longestEffectiveRange: &longest, in: NSRange(location: 1, length: 3))
        #expect(longest == NSRange(location: 1, length: 3))
    }

    @Test func fileHandlesAppendSeekAndTruncate() throws {
        let url = URL(fileURLWithPath: "/tmp/handle-test.log")
        try Data("one\n".utf8).write(to: url)
        #expect(FileHandle(forReadingAtPath: "/tmp/missing.log") == nil)
        #expect(throws: (any Error).self) { try FileHandle(forWritingTo: URL(fileURLWithPath: "/tmp/missing.log")) }

        let writer = try FileHandle(forWritingTo: url)
        #expect(try writer.seekToEnd() == 4)
        writer.write(Data("two\n".utf8))
        try writer.write(contentsOf: Array("three\n".utf8))
        try writer.synchronize()
        try writer.close()
        #expect(try Data(contentsOf: url) == Data("one\ntwo\nthree\n".utf8))

        let reader = try #require(FileHandle(forReadingAtPath: url.path))
        #expect(reader.readData(ofLength: 4) == Data("one\n".utf8) && reader.offsetInFile == 4)
        reader.seek(toFileOffset: 8)
        #expect(try reader.readToEnd() == Data("three\n".utf8))
        #expect(try reader.read(upToCount: 1) == nil)

        let updater = try FileHandle(forUpdating: url)
        try updater.truncate(atOffset: 3)
        #expect(try Data(contentsOf: url) == Data("one".utf8))
        try FileManager.default.removeItem(at: url)
    }

    @Test func fileHandleBytesAndLines() async throws {
        let url = URL(fileURLWithPath: "/tmp/lines-test.txt")
        try Data("a\r\nbb\nccc".utf8).write(to: url)
        let handle = try FileHandle(forReadingFrom: url)
        var lines: [String] = []
        for try await line in handle.bytes.lines { lines.append(line) }
        #expect(lines == ["a", "bb", "ccc"])
        try FileManager.default.removeItem(at: url)
    }

    @Test func logFormatFillsSpecifiers() {
        #expect(_logFormat("%@ has %d items (%.1f%%)", ["cart", 3, 42.5]) == "cart has 3 items (42.5%)")
        #expect(FileHandle.standardError.fileDescriptor == 2 && FileHandle(fileDescriptor: 1).fileDescriptor == 1)
    }

    @Test func streamsReadAndWrite() throws {
        let input = InputStream(data: Data("abcdef".utf8))
        var bytes = [UInt8](repeating: 0, count: 4)
        let unopened = input.read(&bytes, maxLength: 1)
        #expect(unopened == -1)
        input.open()
        #expect(input.hasBytesAvailable && input.streamStatus == .open)
        let first = input.read(&bytes, maxLength: 4)
        #expect(first == 4 && bytes == Array("abcd".utf8))
        let second = input.read(&bytes, maxLength: 4)
        #expect(second == 2 && Array(bytes[0..<2]) == Array("ef".utf8))
        #expect(!input.hasBytesAvailable && input.streamStatus == .atEnd)
        input.close()
        #expect(InputStream(fileAtPath: "/tmp/missing-stream") == nil)

        let memory = OutputStream.toMemory()
        memory.open()
        let payload = Array("hello".utf8)
        #expect(memory.write(payload, maxLength: payload.count) == 5)
        #expect(memory.property(forKey: .dataWrittenToMemoryStreamKey) as? Data == Data("hello".utf8))

        let url = URL(fileURLWithPath: "/tmp/stream-out.txt")
        try Data("a".utf8).write(to: url)
        let file = try #require(OutputStream(url: url, append: true))
        file.open()
        _ = file.write(payload, maxLength: 2)
        file.close()
        #expect(try Data(contentsOf: url) == Data("ahe".utf8))
        try FileManager.default.removeItem(at: url)
    }
}
#endif
