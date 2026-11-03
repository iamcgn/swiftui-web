// `Stream`, `InputStream` and `OutputStream` for wasm, where FoundationEssentials has none.
// Networking packages pass upload bodies as input streams (Alamofire's multipart uploads), and
// parsers read documents from one (FeedKit's XML feeds). Streams here read from data or a file
// in the in-memory store and write to memory or a file, synchronously. The input and output
// streams are final (Foundation's are open), so the bundle drops the methods an app never calls.
#if os(WASI)

public protocol StreamDelegate: AnyObject {
    func stream(_ aStream: Stream, handle eventCode: Stream.Event)
}

extension StreamDelegate {
    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {}
}

open class Stream: @unchecked Sendable {
    public enum Status: UInt, Sendable {
        case notOpen, opening, open, reading, writing, atEnd, closed, error
    }

    public struct Event: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let openCompleted = Event(rawValue: 1 << 0)
        public static let hasBytesAvailable = Event(rawValue: 1 << 1)
        public static let hasSpaceAvailable = Event(rawValue: 1 << 2)
        public static let errorOccurred = Event(rawValue: 1 << 3)
        public static let endEncountered = Event(rawValue: 1 << 4)
    }

    public struct PropertyKey: Hashable, RawRepresentable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
        public static let dataWrittenToMemoryStreamKey = PropertyKey("kCFStreamPropertyDataWritten")
        public static let fileCurrentOffsetKey = PropertyKey("kCFStreamPropertyFileCurrentOffset")
    }

    public weak var delegate: (any StreamDelegate)?
    public internal(set) var streamStatus: Status = .notOpen
    public internal(set) var streamError: (any Error)?
    var properties: [PropertyKey: Any] = [:]

    public init() {}

    open func open() {
        guard streamStatus == .notOpen else { return }
        streamStatus = .open
        delegate?.stream(self, handle: .openCompleted)
    }

    open func close() { streamStatus = .closed }

    open func property(forKey key: PropertyKey) -> Any? { properties[key] }

    @discardableResult open func setProperty(_ property: Any?, forKey key: PropertyKey) -> Bool {
        properties[key] = property
        return true
    }

    /// Streams here are synchronous, so there's no run loop to deliver events on.
    open func schedule(in aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {}
    open func remove(from aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {}
}

public final class InputStream: Stream, @unchecked Sendable {
    private var data: Data
    private var position = 0

    public init(data: Data) {
        self.data = data
        super.init()
    }

    /// Fails when `url` names no file in the store.
    public init?(url: URL) {
        guard let contents = _MemoryFiles.read(url) else { return nil }
        data = contents
        super.init()
    }

    public convenience init?(fileAtPath path: String) { self.init(url: URL(fileURLWithPath: path)) }

    public var hasBytesAvailable: Bool { streamStatus == .open && position < data.count }

    /// Copies up to `len` bytes into `buffer`; returns how many, 0 at the end, -1 if not open.
    public func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        guard streamStatus == .open || streamStatus == .atEnd else { return -1 }
        let count = min(len, data.count - position)
        for offset in 0..<max(0, count) { buffer[offset] = data[data.startIndex + position + offset] }
        position += max(0, count)
        if position >= data.count {
            streamStatus = .atEnd
            delegate?.stream(self, handle: .endEncountered)
        }
        return max(0, count)
    }

    /// No direct buffer access: callers fall back to `read(_:maxLength:)`.
    public func getBuffer(_ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>, length len: UnsafeMutablePointer<Int>) -> Bool { false }
}

public final class OutputStream: Stream, @unchecked Sendable {
    private enum Target { case memory, file(URL), buffer(UnsafeMutablePointer<UInt8>, Int) }
    private let target: Target
    private var written = Data()

    public init(toMemory: ()) {
        target = .memory
        super.init()
    }

    public init(toBuffer buffer: UnsafeMutablePointer<UInt8>, capacity: Int) {
        target = .buffer(buffer, capacity)
        super.init()
    }

    /// Writes to the file at `url`, after its current contents when `shouldAppend`.
    public init?(url: URL, append shouldAppend: Bool) {
        target = .file(url)
        if shouldAppend, let existing = _MemoryFiles.read(url) { written = existing }
        super.init()
    }

    public convenience init?(toFileAtPath path: String, append shouldAppend: Bool) {
        self.init(url: URL(fileURLWithPath: path), append: shouldAppend)
    }

    public static func toMemory() -> OutputStream { OutputStream(toMemory: ()) }

    public var hasSpaceAvailable: Bool {
        guard streamStatus == .open else { return false }
        if case .buffer(_, let capacity) = target { return written.count < capacity }
        return true
    }

    /// Appends up to `len` bytes; returns how many, or -1 if not open.
    public func write(_ buffer: UnsafePointer<UInt8>, maxLength len: Int) -> Int {
        guard streamStatus == .open else { return -1 }
        var count = len
        if case .buffer(let destination, let capacity) = target {
            count = min(len, capacity - written.count)
            for offset in 0..<max(0, count) { destination[written.count + offset] = buffer[offset] }
        }
        written.append(contentsOf: UnsafeBufferPointer(start: buffer, count: max(0, count)))
        switch target {
        case .memory: properties[.dataWrittenToMemoryStreamKey] = written
        case .file(let url): _MemoryFiles.write(written, to: url)
        case .buffer: break
        }
        return max(0, count)
    }

    public override func open() {
        super.open()
        if case .file(let url) = target { _MemoryFiles.write(written, to: url) }
        if case .memory = target { properties[.dataWrittenToMemoryStreamKey] = written }
    }
}
#endif
