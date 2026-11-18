// Watching a file for changes: `DispatchSource.makeFileSystemObjectSource`, over a descriptor
// opened with Darwin's `O_EVTONLY`, as swift-sharing's file storage watches its files. Files here
// are the in-memory store (`_MemoryFiles`, Data.swift), which no descriptor of the system's
// reaches, so `open` with `O_EVTONLY` gives a watch descriptor of this module for a file or
// directory in the store (and -1 for a missing one, as Darwin's does), and a source made from it
// reports the store's writes, removals and moves of the file. Like a descriptor, a watch follows
// its file when it moves and ends when it's deleted. Any other `open` is the system's.
#if os(WASI)
import WASILibc

/// Darwin's flag for a descriptor opened only to watch a file. Its value is a bit WASI's flags
/// don't use (Darwin's own, 0x8000, is WASI's `O_TRUNC`).
public let O_EVTONLY: Int32 = 0x4000_0000

/// Opens `path`: with `O_EVTONLY`, a watch descriptor for the store's file or directory at the
/// path; otherwise the system's `open`.
public func open(_ path: String, _ oflag: Int32) -> Int32 {
    if oflag & O_EVTONLY != 0 { return _FileWatches.descriptor(forPath: path) }
    return path.withCString { WASILibc.open($0, oflag) }
}

extension DispatchSource {
    /// The changes a file system source reports.
    public struct FileSystemEvent: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let delete = FileSystemEvent(rawValue: 0x1)
        public static let write = FileSystemEvent(rawValue: 0x2)
        public static let extend = FileSystemEvent(rawValue: 0x4)
        public static let attrib = FileSystemEvent(rawValue: 0x8)
        public static let link = FileSystemEvent(rawValue: 0x10)
        public static let rename = FileSystemEvent(rawValue: 0x20)
        public static let revoke = FileSystemEvent(rawValue: 0x40)
        public static let funlock = FileSystemEvent(rawValue: 0x100)
        public static let all: FileSystemEvent = [.delete, .write, .extend, .attrib, .link, .rename, .revoke]
    }

    /// A source for the changes in `eventMask` to the file `fileDescriptor` was opened for (with
    /// `O_EVTONLY`). Its handler runs on `queue` (the main queue when nil). It starts suspended,
    /// as Apple's does: `resume()` or `activate()` starts it.
    public static func makeFileSystemObjectSource(fileDescriptor: Int32, eventMask: FileSystemEvent,
                                                  queue: DispatchQueue? = nil) -> any DispatchSourceFileSystemObject {
        let source = _DispatchFileSystemSource(handle: fileDescriptor, mask: eventMask, queue: queue ?? .main)
        _FileWatches.add(source)
        return source
    }
}

/// A source that reports changes to a file.
public protocol DispatchSourceFileSystemObject: DispatchSourceProtocol {
    /// The descriptor the source watches.
    var handle: Int32 { get }
    /// The changes seen since the handler last ran.
    var data: DispatchSource.FileSystemEvent { get }
    /// The changes the source was made to watch.
    var mask: DispatchSource.FileSystemEvent { get }
}

final class _DispatchFileSystemSource: DispatchSourceFileSystemObject, @unchecked Sendable {
    let handle: Int32
    let mask: DispatchSource.FileSystemEvent
    private let queue: DispatchQueue
    private var handler: (@Sendable () -> Void)?
    private var cancelHandler: (@Sendable () -> Void)?
    private var pending: DispatchSource.FileSystemEvent = []
    private var scheduled = false
    private var suspended = true
    private(set) var data: DispatchSource.FileSystemEvent = []
    private(set) var isCancelled = false

    init(handle: Int32, mask: DispatchSource.FileSystemEvent, queue: DispatchQueue) {
        self.handle = handle
        self.mask = mask
        self.queue = queue
    }

    func setEventHandler(qos: DispatchQoS, flags: DispatchWorkItemFlags, handler: (@Sendable () -> Void)?) { self.handler = handler }
    func setCancelHandler(qos: DispatchQoS, flags: DispatchWorkItemFlags, handler: (@Sendable () -> Void)?) { cancelHandler = handler }
    func activate() { resume() }
    func resume() {
        guard suspended, !isCancelled else { return }
        suspended = false
        deliver()
    }
    func suspend() { suspended = true }
    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        handler = nil
        _FileWatches.remove(self)
        if let cancelHandler { queue.async(execute: cancelHandler) }
    }

    /// Notes a change, and runs the handler for it (with any others since) after this turn.
    func record(_ event: DispatchSource.FileSystemEvent) {
        let event = event.intersection(mask)
        guard !event.isEmpty, !isCancelled else { return }
        pending.formUnion(event)
        deliver()
    }

    private func deliver() {
        guard !suspended, !scheduled, !pending.isEmpty else { return }
        scheduled = true
        queue.async { [self] in
            scheduled = false
            guard !suspended, !isCancelled, !pending.isEmpty else { return }
            data = pending
            pending = []
            handler?()
        }
    }
}

/// The watch descriptors and the sources watching through them.
enum _FileWatches {
    /// The store's key (a URL's absolute string) for each watch descriptor. Watch descriptors
    /// count down from the top of the range, away from the system's.
    nonisolated(unsafe) private static var paths: [Int32: String] = [:]
    nonisolated(unsafe) private static var nextDescriptor: Int32 = Int32.max
    nonisolated(unsafe) private static var sources: [ObjectIdentifier: _DispatchFileSystemSource] = [:]

    static func descriptor(forPath path: String) -> Int32 {
        let url = URL(fileURLWithPath: path)
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let key: String
        if _MemoryFiles.exists(url) {
            key = url.absoluteString
        } else if _MemoryFiles.isDirectory(directory) {
            key = directory.absoluteString
        } else {
            return -1
        }
        let descriptor = nextDescriptor
        nextDescriptor -= 1
        paths[descriptor] = key
        return descriptor
    }

    /// Keeps a source until it's cancelled, as a resumed dispatch source is kept.
    static func add(_ source: _DispatchFileSystemSource) {
        guard paths[source.handle] != nil else { return }
        sources[ObjectIdentifier(source)] = source
    }

    static func remove(_ source: _DispatchFileSystemSource) {
        sources[ObjectIdentifier(source)] = nil
    }

    /// Reports a change to the file at `url` (and a change inside a directory to the directory).
    /// The file's own watchers hear `event`, or nothing when it is nil.
    static func report(_ url: URL, _ event: DispatchSource.FileSystemEvent?) {
        guard !sources.isEmpty else { return }
        let key = url.absoluteString
        let parent = url.deletingLastPathComponent().absoluteString
        for source in Array(sources.values) {
            guard let watched = paths[source.handle] else { continue }
            if watched == key {
                if let event { source.record(event) }
            } else if watched == parent || watched == key + "/" {
                source.record(.write)
            }
        }
    }

    /// A watch descriptor follows its file, not its path, as a descriptor follows the file it
    /// was opened on: after a move the descriptors of the moved file watch it at `destination`,
    /// and those of the file the move replaced there hear it deleted and watch nothing more.
    static func move(_ source: URL, to destination: URL) {
        let from = source.absoluteString, to = destination.absoluteString
        guard from != to else { return }
        let replaced = paths.filter { $0.value == to }.map(\.key)
        for descriptor in replaced {
            for watcher in sources.values where watcher.handle == descriptor { watcher.record(.delete) }
            paths[descriptor] = nil
        }
        for (descriptor, path) in paths where path == from { paths[descriptor] = to }
    }

    /// The descriptors of a deleted file watch nothing more: a file later written at its path
    /// is another file.
    static func deleted(_ url: URL) {
        let key = url.absoluteString
        for (descriptor, path) in paths where path == key { paths[descriptor] = nil }
    }
}
#endif
