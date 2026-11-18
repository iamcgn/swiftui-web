// Watching a file in the in-memory store: `open` with `O_EVTONLY` and a file system source, as
// swift-sharing's file storage watches its files. The source hears the store's writes, moves
// and removals of the file, after the turn that made them, until it's cancelled.
#if os(WASI)
import Testing
import WASILibc
import WebFoundation

/// The events a source's handler saw (the handler is `@Sendable`; the page has one thread).
private final class Events: @unchecked Sendable {
    var seen: [DispatchSource.FileSystemEvent] = []
}

@Suite(.serialized) @MainActor struct WasmFileWatchTests {
    // Waits by yielding: under Node a sleeping task asks WASI for timers it doesn't have.
    private func settle(until done: () -> Bool) async {
        for _ in 0..<50 where !done() { await Task.yield() }
    }

    @Test func aSourceHearsWritesToItsFileUntilCancelled() async throws {
        let url = URL(fileURLWithPath: "/tmp/watch-\(Int.random(in: 0..<1_000_000)).json")
        #expect(open(url.path, O_EVTONLY) == -1)
        try Data("a".utf8).write(to: url, options: .atomic)
        let descriptor = open(url.path, O_EVTONLY)
        #expect(descriptor >= 0)

        let events = Events()
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename], queue: .main)
        source.setEventHandler { events.seen.append(source.data) }
        #expect(source.handle == descriptor && source.mask == [.write, .rename])
        source.resume()
        try Data("b".utf8).write(to: url, options: .atomic)
        await settle { !events.seen.isEmpty }
        #expect(events.seen == [.write])

        source.cancel()
        try Data("c".utf8).write(to: url)
        for _ in 0..<20 { await Task.yield() }
        #expect(events.seen == [.write] && source.isCancelled)
    }

    @Test func aMoveIsARenameAndARemovalADelete() async throws {
        let name = "watch-\(Int.random(in: 0..<1_000_000))"
        let url = URL(fileURLWithPath: "/tmp/\(name).json")
        try Data("a".utf8).write(to: url)
        let renames = Events(), deletes = Events()
        let renameSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: open(url.path, O_EVTONLY), eventMask: [.rename], queue: .main)
        let deleteSource = DispatchSource.makeFileSystemObjectSource(fileDescriptor: open(url.path, O_EVTONLY), eventMask: [.delete], queue: .main)
        renameSource.setEventHandler { renames.seen.append(renameSource.data) }
        deleteSource.setEventHandler { deletes.seen.append(deleteSource.data) }
        renameSource.resume()
        deleteSource.resume()

        let moved = URL(fileURLWithPath: "/tmp/\(name)-moved.json")
        try FileManager.default.moveItem(at: url, to: moved)
        await settle { !renames.seen.isEmpty }
        #expect(renames.seen == [.rename] && deletes.seen.isEmpty)

        try Data("b".utf8).write(to: url)
        try FileManager.default.removeItem(at: url)
        await settle { !deletes.seen.isEmpty }
        #expect(deletes.seen == [.delete] && renames.seen == [.rename])
        renameSource.cancel()
        deleteSource.cancel()
        try FileManager.default.removeItem(at: moved)
    }

    @Test func aQueueIsEqualToItselfAlone() {
        let queue = DispatchQueue(label: "watch")
        #expect(queue == queue && queue != DispatchQueue.main)
        #expect(Set([queue, queue, .main]).count == 2)
    }
}
#endif
