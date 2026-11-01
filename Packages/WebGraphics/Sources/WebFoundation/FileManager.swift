// Foundation's `FileManager` on wasm (decision 0021): the page has no file system, so the
// app's files live in memory under `file:` URLs (`_MemoryFiles`, which `Data(contentsOf:)` and
// `write(to:)` already read and write) and the files under the app's document directory go to
// the host after every write (`_hostStore`: the browser host keeps them in localStorage, base64
// under `swiftuiweb.files`), so a saved document is there after a reload. A declaration here
// shadows FoundationEssentials' `FileManager` for every file that imports this module.
#if os(WASI)
public final class FileManager: @unchecked Sendable {
    public static let `default` = FileManager()

    public enum SearchPathDirectory: Int, Sendable {
        case applicationDirectory = 1, libraryDirectory = 5, userDirectory = 7, documentationDirectory = 8, documentDirectory = 9
        case autosavedInformationDirectory = 11, desktopDirectory = 12, cachesDirectory = 13, applicationSupportDirectory = 14
        case downloadsDirectory = 15, moviesDirectory = 17, musicDirectory = 18, picturesDirectory = 19, sharedPublicDirectory = 21
        case itemReplacementDirectory = 99, trashDirectory = 102
    }
    public struct SearchPathDomainMask: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let userDomainMask = SearchPathDomainMask(rawValue: 1)
        public static let localDomainMask = SearchPathDomainMask(rawValue: 2)
        public static let allDomainsMask = SearchPathDomainMask(rawValue: 0x0ffff)
    }
    public struct DirectoryEnumerationOptions: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let skipsHiddenFiles = DirectoryEnumerationOptions(rawValue: 4)
        public static let skipsSubdirectoryDescendants = DirectoryEnumerationOptions(rawValue: 1)
    }

    /// The app's home: `file:///` with Documents, Library and tmp under it.
    public var homeDirectoryForCurrentUser: URL { URL(fileURLWithPath: "/", isDirectory: true) }
    public var temporaryDirectory: URL { URL(fileURLWithPath: "/tmp/", isDirectory: true) }
    public var currentDirectoryPath: String { "/" }

    public func urls(for directory: SearchPathDirectory, in domainMask: SearchPathDomainMask) -> [URL] {
        let path: String
        switch directory {
        case .documentDirectory: path = "/Documents/"
        case .cachesDirectory: path = "/Library/Caches/"
        case .applicationSupportDirectory: path = "/Library/Application Support/"
        case .libraryDirectory: path = "/Library/"
        case .desktopDirectory: path = "/Desktop/"
        case .downloadsDirectory: path = "/Downloads/"
        default: path = "/Library/\(directory)/"
        }
        return [URL(fileURLWithPath: path, isDirectory: true)]
    }
    public func url(for directory: SearchPathDirectory, in domain: SearchPathDomainMask, appropriateFor url: URL?, create: Bool) throws -> URL {
        urls(for: directory, in: domain)[0]
    }

    public func fileExists(atPath path: String) -> Bool { _MemoryFiles.exists(URL(fileURLWithPath: path)) }
    public func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        let url = URL(fileURLWithPath: path)
        let directory = _MemoryFiles.isDirectory(url)
        isDirectory?.pointee = ObjCBool(directory)
        return directory || _MemoryFiles.exists(url)
    }
    public func contents(atPath path: String) -> Data? { _MemoryFiles.read(URL(fileURLWithPath: path)) }
    @discardableResult public func createFile(atPath path: String, contents: Data?, attributes: [FileAttributeKey: Any]? = nil) -> Bool {
        _MemoryFiles.write(contents ?? Data(), to: URL(fileURLWithPath: path))
        return true
    }
    public func createDirectory(at url: URL, withIntermediateDirectories: Bool, attributes: [FileAttributeKey: Any]? = nil) throws {
        _MemoryFiles.createDirectory(url)
    }
    public func createDirectory(atPath path: String, withIntermediateDirectories: Bool, attributes: [FileAttributeKey: Any]? = nil) throws {
        _MemoryFiles.createDirectory(URL(fileURLWithPath: path, isDirectory: true))
    }
    public func removeItem(at url: URL) throws {
        guard _MemoryFiles.exists(url) || _MemoryFiles.isDirectory(url) else { throw _FileError.noSuchFile(url) }
        _MemoryFiles.remove(url)
    }
    public func removeItem(atPath path: String) throws { try removeItem(at: URL(fileURLWithPath: path)) }
    public func copyItem(at source: URL, to destination: URL) throws {
        guard let data = _MemoryFiles.read(source) else { throw _FileError.noSuchFile(source) }
        _MemoryFiles.write(data, to: destination)
    }
    public func moveItem(at source: URL, to destination: URL) throws {
        try copyItem(at: source, to: destination)
        _MemoryFiles.remove(source)
    }
    public func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]? = nil, options: DirectoryEnumerationOptions = []) throws -> [URL] {
        _MemoryFiles.contents(of: url)
    }
    public func contentsOfDirectory(atPath path: String) throws -> [String] {
        _MemoryFiles.contents(of: URL(fileURLWithPath: path, isDirectory: true)).map(\.lastPathComponent)
    }
    public func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        guard let data = _MemoryFiles.read(URL(fileURLWithPath: path)) else { throw _FileError.noSuchFile(URL(fileURLWithPath: path)) }
        return [.size: data.count]
    }

    public enum _FileError: Error, CustomStringConvertible {
        case noSuchFile(URL)
        public var description: String {
            switch self { case .noSuchFile(let url): return "The file “\(url.lastPathComponent)” doesn’t exist." }
        }
    }
}

public struct FileAttributeKey: Hashable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let size = FileAttributeKey("NSFileSize")
    public static let modificationDate = FileAttributeKey("NSFileModificationDate")
    public static let creationDate = FileAttributeKey("NSFileCreationDate")
    public static let type = FileAttributeKey("NSFileType")
}

public struct URLResourceKey: Hashable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let isDirectoryKey = URLResourceKey(rawValue: "NSURLIsDirectoryKey")
    public static let contentModificationDateKey = URLResourceKey(rawValue: "NSURLContentModificationDateKey")
    public static let fileSizeKey = URLResourceKey(rawValue: "NSURLFileSizeKey")
}

public struct ObjCBool: Sendable, ExpressibleByBooleanLiteral {
    public var boolValue: Bool
    public init(_ value: Bool) { boolValue = value }
    public init(booleanLiteral value: Bool) { boolValue = value }
}

/// The path of the temporary directory (`FileManager.default.temporaryDirectory`).
public func NSTemporaryDirectory() -> String { FileManager.default.temporaryDirectory.path + "/" }

#endif
