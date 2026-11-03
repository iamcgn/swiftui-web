// `FileHandle` for wasm, where FoundationEssentials has none. Logging packages (SwiftyBeaver's
// file destination) and caches open files for appending, seek, truncate and read back. Files
// here are the in-memory store `FileManager` uses, so a handle reads the file's bytes when it
// opens and writes them back after each change. The standard output and error handles print
// to the console. The class is final (Foundation's is open): a class's vtable keeps every method
// it lists in the bundle, used or not, and apps don't subclass file handles.
#if os(WASI)

public final class FileHandle: @unchecked Sendable {
    private enum Target { case file(URL), standardOutput, standardError, standardInput, null }
    private let target: Target
    private var buffer: Data
    private var position = 0
    private var closed = false
    public let fileDescriptor: Int32

    private init(target: Target, descriptor: Int32) {
        self.target = target
        fileDescriptor = descriptor
        if case .file(let url) = target { buffer = _MemoryFiles.read(url) ?? Data() } else { buffer = Data() }
    }

    nonisolated(unsafe) private static var nextDescriptor: Int32 = 3

    private convenience init(file url: URL) {
        let descriptor = FileHandle.nextDescriptor
        FileHandle.nextDescriptor += 1
        self.init(target: .file(url), descriptor: descriptor)
    }

    /// Wraps a descriptor: 0, 1 and 2 are the standard streams; any other reads and writes nothing.
    public convenience init(fileDescriptor: Int32) {
        switch fileDescriptor {
        case 0: self.init(target: .standardInput, descriptor: 0)
        case 1: self.init(target: .standardOutput, descriptor: 1)
        case 2: self.init(target: .standardError, descriptor: 2)
        default: self.init(target: .null, descriptor: fileDescriptor)
        }
    }
    public convenience init(fileDescriptor: Int32, closeOnDealloc: Bool) { self.init(fileDescriptor: fileDescriptor) }

    public static var standardInput: FileHandle { FileHandle(target: .standardInput, descriptor: 0) }
    public static var standardOutput: FileHandle { FileHandle(target: .standardOutput, descriptor: 1) }
    public static var standardError: FileHandle { FileHandle(target: .standardError, descriptor: 2) }
    public static var nullDevice: FileHandle { FileHandle(target: .null, descriptor: -1) }

    // Opening. The path forms return nil when the file is missing, as Foundation's do; the URL
    // forms throw. Opening for writing doesn't truncate.
    public convenience init?(forReadingAtPath path: String) {
        let url = URL(fileURLWithPath: path)
        guard _MemoryFiles.exists(url) else { return nil }
        self.init(file: url)
    }
    public convenience init?(forWritingAtPath path: String) { self.init(forReadingAtPath: path) }
    public convenience init?(forUpdatingAtPath path: String) { self.init(forReadingAtPath: path) }

    public convenience init(forReadingFrom url: URL) throws {
        guard _MemoryFiles.exists(url) else { throw FileManager._FileError.noSuchFile(url) }
        self.init(file: url)
    }
    public convenience init(forWritingTo url: URL) throws { try self.init(forReadingFrom: url) }
    public convenience init(forUpdating url: URL) throws { try self.init(forReadingFrom: url) }

    // Reading.
    public var availableData: Data { readDataToEndOfFile() }

    public func readDataToEndOfFile() -> Data { readData(ofLength: Int.max) }

    public func readData(ofLength length: Int) -> Data {
        guard !closed, position < buffer.count else { return Data() }
        let end = position + min(length, buffer.count - position)
        let chunk = Data(buffer[position..<end])
        position = end
        return chunk
    }

    public func read(upToCount count: Int) throws -> Data? {
        let chunk = readData(ofLength: count)
        return chunk.isEmpty ? nil : chunk
    }

    public func readToEnd() throws -> Data? {
        let chunk = readDataToEndOfFile()
        return chunk.isEmpty ? nil : chunk
    }

    // Writing: overwrites from the current offset and grows the file past its end.
    public func write(_ data: Data) {
        guard !closed else { return }
        switch target {
        case .standardOutput, .standardError:
            print(String(decoding: data, as: UTF8.self), terminator: "")
        case .file(let url):
            let end = position + data.count
            if end > buffer.count { buffer.append(Data(repeating: 0, count: end - buffer.count)) }
            buffer.replaceSubrange(position..<end, with: data)
            position = end
            _MemoryFiles.write(buffer, to: url)
        case .standardInput, .null:
            break
        }
    }

    public func write<T: Sequence>(contentsOf data: T) throws where T.Element == UInt8 { write(Data(data)) }

    // Offsets.
    public var offsetInFile: UInt64 { UInt64(position) }
    public func offset() throws -> UInt64 { offsetInFile }

    @discardableResult public func seekToEndOfFile() -> UInt64 {
        position = buffer.count
        return UInt64(position)
    }
    @discardableResult public func seekToEnd() throws -> UInt64 { seekToEndOfFile() }

    public func seek(toFileOffset offset: UInt64) { position = Int(offset) }
    public func seek(toOffset offset: UInt64) throws { seek(toFileOffset: offset) }

    public func truncateFile(atOffset offset: UInt64) {
        let size = Int(offset)
        if size < buffer.count { buffer = Data(buffer[0..<size]) } else if size > buffer.count { buffer.append(Data(repeating: 0, count: size - buffer.count)) }
        position = size
        if case .file(let url) = target { _MemoryFiles.write(buffer, to: url) }
    }
    public func truncate(atOffset offset: UInt64) throws { truncateFile(atOffset: offset) }

    /// Writes reach the store at once, so syncing has nothing left to do.
    public func synchronizeFile() {}
    public func synchronize() throws {}

    public func closeFile() { closed = true }
    public func close() throws { closed = true }

    /// The bytes from the current offset to the end, one at a time.
    public var bytes: AsyncBytes { AsyncBytes(data: readDataToEndOfFile()) }

    public struct AsyncBytes: AsyncSequence, Sendable {
        public typealias Element = UInt8
        let data: Data
        public struct AsyncIterator: AsyncIteratorProtocol {
            var data: Data
            var index = 0
            public mutating func next() async throws -> UInt8? {
                guard index < data.count else { return nil }
                defer { index += 1 }
                return data[data.startIndex + index]
            }
        }
        public func makeAsyncIterator() -> AsyncIterator { AsyncIterator(data: data) }

        /// The bytes split at newlines, as strings.
        public var lines: AsyncLineSequence<AsyncBytes> { AsyncLineSequence(base: self) }
    }
}

/// Lines from a sequence of UTF-8 bytes, split at `\n` (a trailing `\r` is dropped).
public struct AsyncLineSequence<Base: AsyncSequence & Sendable>: AsyncSequence, Sendable where Base.Element == UInt8 {
    public typealias Element = String
    let base: Base
    public struct AsyncIterator: AsyncIteratorProtocol {
        var base: Base.AsyncIterator
        var finished = false
        public mutating func next() async throws -> String? {
            guard !finished else { return nil }
            var bytes: [UInt8] = []
            while let byte = try await base.next() {
                if byte == 0x0A {
                    if bytes.last == 0x0D { bytes.removeLast() }
                    return String(decoding: bytes, as: UTF8.self)
                }
                bytes.append(byte)
            }
            finished = true
            return bytes.isEmpty ? nil : String(decoding: bytes, as: UTF8.self)
        }
    }
    public func makeAsyncIterator() -> AsyncIterator { AsyncIterator(base: base.makeAsyncIterator()) }
}

/// Logs a message to the console, as Foundation's `NSLog` does to the system log. Each `%…`
/// specifier (`%@`, `%d`, `%.2f`) takes the next argument's description; `%%` is a percent sign.
/// The arguments are `Any` because strings aren't `CVarArg` without Objective-C bridging.
public func NSLog(_ format: String, _ args: Any...) {
    print(_logFormat(format, args))
}

public func _logFormat(_ format: String, _ args: [Any]) -> String {
    var out = ""
    var remaining = args[...]
    var index = format.startIndex
    while index < format.endIndex {
        let character = format[index]
        index = format.index(after: index)
        guard character == "%", index < format.endIndex else { out.append(character); continue }
        if format[index] == "%" { out.append("%"); index = format.index(after: index); continue }
        // Skip flags, width, precision and length, up to the conversion letter.
        while index < format.endIndex {
            let c = format[index]
            index = format.index(after: index)
            if c == "@" || c.isLetter && !"hlqLjzt".contains(c) { break }
        }
        if let next = remaining.popFirst() { out += String(describing: next) }
    }
    return out
}
#endif
