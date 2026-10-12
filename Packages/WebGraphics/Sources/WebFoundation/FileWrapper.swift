// Foundation's `FileWrapper` on wasm (decision 0017): FoundationEssentials has none. The surface
// `FileDocument` uses: a regular file's contents, a directory's children, a preferred name.
#if os(WASI)
public final class FileWrapper {
    public private(set) var regularFileContents: Data?
    public private(set) var fileWrappers: [String: FileWrapper]?
    public var preferredFilename: String?
    public var filename: String?

    public init(regularFileWithContents contents: Data) { regularFileContents = contents }
    public init(directoryWithFileWrappers childrenByPreferredName: [String: FileWrapper]) { fileWrappers = childrenByPreferredName }

    public var isRegularFile: Bool { regularFileContents != nil }
    public var isDirectory: Bool { fileWrappers != nil }

    /// Adds a child to a directory wrapper; returns the name it took.
    @discardableResult
    public func addFileWrapper(_ child: FileWrapper) -> String {
        let name = child.preferredFilename ?? "file"
        fileWrappers?[name] = child
        return name
    }

    public func removeFileWrapper(_ child: FileWrapper) {
        fileWrappers = fileWrappers?.filter { $0.value !== child }
    }
}
#endif
