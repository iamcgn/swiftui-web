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
    public struct SearchPathDomainMask: OptionSet, Hashable, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let userDomainMask = SearchPathDomainMask(rawValue: 1)
        public static let localDomainMask = SearchPathDomainMask(rawValue: 2)
        public static let allDomainsMask = SearchPathDomainMask(rawValue: 0x0ffff)
    }
    public struct DirectoryEnumerationOptions: OptionSet, Hashable, Sendable {
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
    /// The path forms, as SwiftyBeaver rotates its log files.
    public func copyItem(atPath srcPath: String, toPath dstPath: String) throws {
        try copyItem(at: URL(fileURLWithPath: srcPath), to: URL(fileURLWithPath: dstPath))
    }
    public func moveItem(atPath srcPath: String, toPath dstPath: String) throws {
        try moveItem(at: URL(fileURLWithPath: srcPath), to: URL(fileURLWithPath: dstPath))
    }
    /// A link is a copy here: the in-memory files have no links.
    public func linkItem(at srcURL: URL, to dstURL: URL) throws { try copyItem(at: srcURL, to: dstURL) }
    public func linkItem(atPath srcPath: String, toPath dstPath: String) throws { try copyItem(atPath: srcPath, toPath: dstPath) }

    /// The options of `replaceItemAt` (none changes what happens here).
    public struct ItemReplacementOptions: OptionSet, Hashable, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let usingNewMetadataOnly = ItemReplacementOptions(rawValue: 1)
        public static let withoutDeletingBackupItem = ItemReplacementOptions(rawValue: 2)
    }
    /// Puts the new item's bytes at the original's URL and removes the new item; the result is
    /// the original's URL (a safe save: write a temporary file, then replace).
    @discardableResult
    public func replaceItemAt(_ originalItemURL: URL, withItemAt newItemURL: URL, backupItemName: String? = nil,
                              options: ItemReplacementOptions = []) throws -> URL? {
        guard let data = _MemoryFiles.read(newItemURL) else { throw _FileError.noSuchFile(newItemURL) }
        if let backupItemName, options.contains(.withoutDeletingBackupItem), let old = _MemoryFiles.read(originalItemURL) {
            _MemoryFiles.write(old, to: originalItemURL.deletingLastPathComponent().appendingPathComponent(backupItemName))
        }
        _MemoryFiles.write(data, to: originalItemURL)
        _MemoryFiles.remove(newItemURL)
        return originalItemURL
    }

    /// Every file here belongs to the app, so what exists can be read, written and deleted.
    public func isReadableFile(atPath path: String) -> Bool { fileExists(atPath: path) }
    public func isWritableFile(atPath path: String) -> Bool { fileExists(atPath: path) }
    public func isDeletableFile(atPath path: String) -> Bool { fileExists(atPath: path) }
    public func isExecutableFile(atPath path: String) -> Bool { false }
    /// The name to show for the item: its last path component.
    public func displayName(atPath path: String) -> String { URL(fileURLWithPath: path).lastPathComponent }
    /// True when both paths name files with the same bytes, or directories holding the same
    /// names whose contents are equal in turn, as Foundation compares them.
    public func contentsEqual(atPath path1: String, andPath path2: String) -> Bool {
        Self._contentsEqual(URL(fileURLWithPath: path1), URL(fileURLWithPath: path2))
    }
    private static func _contentsEqual(_ first: URL, _ second: URL) -> Bool {
        let firstIsDirectory = _MemoryFiles.isDirectory(first), secondIsDirectory = _MemoryFiles.isDirectory(second)
        guard firstIsDirectory == secondIsDirectory else { return false }
        guard firstIsDirectory else {
            guard let a = _MemoryFiles.read(first), let b = _MemoryFiles.read(second) else { return false }
            return a == b
        }
        let firstChildren = _MemoryFiles.contents(of: first), secondChildren = _MemoryFiles.contents(of: second)
        guard firstChildren.map(\.lastPathComponent) == secondChildren.map(\.lastPathComponent) else { return false }
        return zip(firstChildren, secondChildren).allSatisfy { _contentsEqual($0, $1) }
    }
    /// Every path under the directory, relative to it, depth first.
    public func subpathsOfDirectory(atPath path: String) throws -> [String] {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard _MemoryFiles.isDirectory(url) else { throw _FileError.noSuchFile(url) }
        return enumerator(atPath: path)?.allObjects.compactMap { $0 as? String } ?? []
    }
    public func subpaths(atPath path: String) -> [String]? { try? subpathsOfDirectory(atPath: path) }
    /// The file system's size and free space: the page's storage has no fixed size, so these are
    /// the browser's usual origin quota (a cache or a download checks free space before writing).
    public func attributesOfFileSystem(forPath path: String) throws -> [FileAttributeKey: Any] {
        let used = _MemoryFiles.contents(of: URL(fileURLWithPath: "/", isDirectory: true)).count
        return [.systemSize: NSNumber(value: Int64(1) << 30), .systemFreeSize: NSNumber(value: (Int64(1) << 30) - Int64(used)),
                .systemNodes: NSNumber(value: 1 << 20), .systemFreeNodes: NSNumber(value: (1 << 20) - used), .systemNumber: NSNumber(value: 1)]
    }

    public func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]? = nil, options: DirectoryEnumerationOptions = []) throws -> [URL] {
        _MemoryFiles.contents(of: url)
    }
    public func contentsOfDirectory(atPath path: String) throws -> [String] {
        _MemoryFiles.contents(of: URL(fileURLWithPath: path, isDirectory: true)).map(\.lastPathComponent)
    }
    public func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        let url = URL(fileURLWithPath: path)
        guard let data = _MemoryFiles.read(url) else { throw _FileError.noSuchFile(url) }
        var attributes: [FileAttributeKey: Any] = [.size: data.count, .type: FileAttributeType.typeRegular]
        if let date = _MemoryFiles.modificationDate(url) { attributes[.modificationDate] = date }
        if let date = _MemoryFiles.creationDate(url) { attributes[.creationDate] = date }
        return attributes
    }

    /// Sets a file's creation and modification dates; other attributes are accepted and kept by
    /// nothing (the in-memory files have no owners or permissions).
    public func setAttributes(_ attributes: [FileAttributeKey: Any], ofItemAtPath path: String) throws {
        let url = URL(fileURLWithPath: path)
        guard _MemoryFiles.exists(url) || _MemoryFiles.isDirectory(url) else { throw _FileError.noSuchFile(url) }
        _MemoryFiles.setDates(url, creation: attributes[.creationDate] as? Date, modification: attributes[.modificationDate] as? Date)
    }

    /// Every file and directory under `url`, depth first (the keys are read when asked for).
    public func enumerator(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?,
                           options mask: DirectoryEnumerationOptions = [],
                           errorHandler handler: ((URL, Error) -> Bool)? = nil) -> DirectoryEnumerator? {
        guard _MemoryFiles.isDirectory(url) else { return nil }
        var found: [Any] = []
        func walk(_ directory: URL) {
            for child in _MemoryFiles.contents(of: directory) {
                if mask.contains(.skipsHiddenFiles), child.lastPathComponent.hasPrefix(".") { continue }
                found.append(child)
                if _MemoryFiles.isDirectory(child), !mask.contains(.skipsSubdirectoryDescendants) { walk(child) }
            }
        }
        walk(url)
        return DirectoryEnumerator(found)
    }

    /// The paths under `path`, relative to it, depth first.
    public func enumerator(atPath path: String) -> DirectoryEnumerator? {
        let base = URL(fileURLWithPath: path, isDirectory: true)
        guard let all = enumerator(at: base, includingPropertiesForKeys: nil) else { return nil }
        let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
        return DirectoryEnumerator(all.allObjects.compactMap { ($0 as? URL).map { String($0.path.dropFirst(prefix.count)) } })
    }

    /// The items a directory enumeration found, in order.
    public final class DirectoryEnumerator: Sequence, IteratorProtocol {
        private var items: [Any]
        init(_ items: [Any]) { self.items = items }
        public func nextObject() -> Any? { items.isEmpty ? nil : items.removeFirst() }
        public func next() -> Any? { nextObject() }
        /// The items not yet enumerated.
        public var allObjects: [Any] { let rest = items; items = []; return rest }
        public func skipDescendants() {}
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
    public static let posixPermissions = FileAttributeKey("NSFilePosixPermissions")
    public static let protectionKey = FileAttributeKey("NSFileProtectionKey")
    public static let referenceCount = FileAttributeKey("NSFileReferenceCount")
    public static let ownerAccountName = FileAttributeKey("NSFileOwnerAccountName")
    public static let groupOwnerAccountName = FileAttributeKey("NSFileGroupOwnerAccountName")
    public static let ownerAccountID = FileAttributeKey("NSFileOwnerAccountID")
    public static let groupOwnerAccountID = FileAttributeKey("NSFileGroupOwnerAccountID")
    public static let extensionHidden = FileAttributeKey("NSFileExtensionHidden")
    public static let immutable = FileAttributeKey("NSFileImmutable")
    public static let appendOnly = FileAttributeKey("NSFileAppendOnly")
    public static let systemNumber = FileAttributeKey("NSFileSystemNumber")
    public static let systemFileNumber = FileAttributeKey("NSFileSystemFileNumber")
    public static let systemSize = FileAttributeKey("NSFileSystemSize")
    public static let systemFreeSize = FileAttributeKey("NSFileSystemFreeSize")
    public static let systemNodes = FileAttributeKey("NSFileSystemNodes")
    public static let systemFreeNodes = FileAttributeKey("NSFileSystemFreeNodes")
}

/// The kind of a file (`FileAttributeKey.type`'s value).
public struct FileAttributeType: Hashable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let typeRegular = FileAttributeType(rawValue: "NSFileTypeRegular")
    public static let typeDirectory = FileAttributeType(rawValue: "NSFileTypeDirectory")
}

public struct URLResourceKey: Hashable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let isDirectoryKey = URLResourceKey(rawValue: "NSURLIsDirectoryKey")
    public static let contentModificationDateKey = URLResourceKey(rawValue: "NSURLContentModificationDateKey")
    public static let fileSizeKey = URLResourceKey(rawValue: "NSURLFileSizeKey")
    public static let creationDateKey = URLResourceKey(rawValue: "NSURLCreationDateKey")
    public static let contentAccessDateKey = URLResourceKey(rawValue: "NSURLContentAccessDateKey")
    public static let isRegularFileKey = URLResourceKey(rawValue: "NSURLIsRegularFileKey")
    public static let nameKey = URLResourceKey(rawValue: "NSURLNameKey")
    public static let totalFileAllocatedSizeKey = URLResourceKey(rawValue: "NSURLTotalFileAllocatedSizeKey")
    public static let fileAllocatedSizeKey = URLResourceKey(rawValue: "NSURLFileAllocatedSizeKey")
}

public struct ObjCBool: Sendable, ExpressibleByBooleanLiteral {
    public var boolValue: Bool
    public init(_ value: Bool) { boolValue = value }
    public init(booleanLiteral value: Bool) { boolValue = value }
}

/// The path of the temporary directory (`FileManager.default.temporaryDirectory`).
public func NSTemporaryDirectory() -> String { FileManager.default.temporaryDirectory.path + "/" }

extension URL {
    private static func _directory(_ directory: FileManager.SearchPathDirectory) -> URL {
        FileManager.default.urls(for: directory, in: .userDomainMask)[0]
    }
    /// The app's directories, as `FileManager` gives them.
    public static var documentsDirectory: URL { _directory(.documentDirectory) }
    public static var cachesDirectory: URL { _directory(.cachesDirectory) }
    public static var applicationSupportDirectory: URL { _directory(.applicationSupportDirectory) }
    public static var libraryDirectory: URL { _directory(.libraryDirectory) }
    public static var downloadsDirectory: URL { _directory(.downloadsDirectory) }
    public static var desktopDirectory: URL { _directory(.desktopDirectory) }
    public static var temporaryDirectory: URL { FileManager.default.temporaryDirectory }
    public static var homeDirectory: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// True when the file is in the store; throws the no-such-file error otherwise, as
    /// Foundation does (a URL that names no file is never reachable).
    public func checkResourceIsReachable() throws -> Bool {
        guard isFileURL, _MemoryFiles.exists(self) || _MemoryFiles.isDirectory(self) else { throw FileManager._FileError.noSuchFile(self) }
        return true
    }

    /// The same check: no file here is promised by another process.
    public func checkPromisedItemIsReachable() throws -> Bool { try checkResourceIsReachable() }
}

#endif
