// The wasm stand-ins image caches lean on (Kingfisher's disk and memory storage): file dates
// set through `setAttributes` and read back as resource values, directory enumeration,
// discardable content, request and task fields, and the current operation queue.
#if os(WASI)
import Testing
import WebFoundation

@Suite(.serialized) struct WasmFileCacheTests {
    @Test func fileDatesAndEnumeration() throws {
        let manager = FileManager.default
        let root = URL(fileURLWithPath: "/tmp/cache-test/", isDirectory: true)
        try manager.createDirectory(at: root.appendingPathComponent("nested"), withIntermediateDirectories: true)
        let file = root.appendingPathComponent("a.png")
        let deep = root.appendingPathComponent("nested/b.png")
        let hidden = root.appendingPathComponent(".hidden")
        for url in [file, deep, hidden] { try Data([1, 2, 3]).write(to: url) }

        let expiry = Date(timeIntervalSince1970: 2_000_000_000)
        let access = Date(timeIntervalSince1970: 1_900_000_000)
        try manager.setAttributes([.creationDate: access, .modificationDate: expiry], ofItemAtPath: file.path)
        let values = try file.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        #expect(values.creationDate == access && values.contentModificationDate == expiry)
        let attributes = try manager.attributesOfItem(atPath: file.path)
        #expect(attributes[.creationDate] as? Date == access && attributes[.size] as? Int == 3)
        #expect(throws: (any Error).self) { try manager.setAttributes([:], ofItemAtPath: "/tmp/cache-test/missing") }

        let all = try #require(manager.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles))
        var names: [String] = []
        for case let url as URL in all { names.append(url.lastPathComponent) }
        #expect(names.sorted() == ["a.png", "b.png", "nested"])
        let shallow = try #require(manager.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]))
        #expect(shallow.allObjects.count == 2)
        let paths = try #require(manager.enumerator(atPath: root.path))
        #expect((paths.allObjects as? [String])?.sorted() == [".hidden", "a.png", "nested", "nested/b.png"])
        #expect(manager.enumerator(at: file, includingPropertiesForKeys: nil) == nil)
        for url in [file, deep, hidden] { try manager.removeItem(at: url) }
    }

    @Test func requestTaskAndQueueFields() {
        var request = URLRequest(url: URL(string: "https://example.com/a.png")!)
        #expect(!request.httpShouldUsePipelining && request.allowsConstrainedNetworkAccess && request.allowsExpensiveNetworkAccess)
        request.allowsConstrainedNetworkAccess = false
        #expect(!request.allowsConstrainedNetworkAccess)
        #expect(URLSessionTask.lowPriority < URLSessionTask.defaultPriority && URLSessionTask.defaultPriority < URLSessionTask.highPriority)
        #expect(OperationQueue.current === OperationQueue.main && OperationQueue.current?.underlyingQueue != nil)
        #expect(NSPOSIXErrorDomain == "NSPOSIXErrorDomain")
    }

    @Test func discardableContentConforms() {
        final class Entry: NSDiscardableContent {
            var value: Int? = 1
            func beginContentAccess() -> Bool { value != nil }
            func endContentAccess() {}
            func discardContentIfPossible() { value = nil }
            func isContentDiscarded() -> Bool { value == nil }
        }
        let entry: any NSDiscardableContent = Entry()
        #expect(entry.beginContentAccess())
        entry.discardContentIfPossible()
        #expect(entry.isContentDiscarded() && !entry.beginContentAccess())
    }
}
#endif
