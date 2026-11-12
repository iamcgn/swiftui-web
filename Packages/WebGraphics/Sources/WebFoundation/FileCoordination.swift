// `NSFileCoordinator` and `NSFilePresenter` for wasm (SwiftyBeaver's file destination). The page
// is the only process touching its file system, so there is nothing to coordinate with: each
// `coordinate` call runs its accessor at once with the URL it was given, and never fails.
#if os(WASI)

/// An object that presents a file and is told when others change it (never, here).
public protocol NSFilePresenter: AnyObject {
    var presentedItemURL: URL? { get }
    var presentedItemOperationQueue: OperationQueue { get }
}

/// Reading or writing one item, for `coordinate(with:queue:byAccessor:)`.
open class NSFileAccessIntent: NSObject, @unchecked Sendable {
    public let url: URL
    private init(url: URL) {
        self.url = url
        super.init()
    }
    open class func readingIntent(with url: URL, options: NSFileCoordinator.ReadingOptions = []) -> NSFileAccessIntent {
        NSFileAccessIntent(url: url)
    }
    open class func writingIntent(with url: URL, options: NSFileCoordinator.WritingOptions = []) -> NSFileAccessIntent {
        NSFileAccessIntent(url: url)
    }
}

open class NSFileCoordinator: NSObject, @unchecked Sendable {
    public struct ReadingOptions: OptionSet, Hashable, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let withoutChanges = ReadingOptions(rawValue: 1 << 0)
        public static let resolvesSymbolicLink = ReadingOptions(rawValue: 1 << 1)
        public static let immediatelyAvailableMetadataOnly = ReadingOptions(rawValue: 1 << 2)
        public static let forUploading = ReadingOptions(rawValue: 1 << 3)
    }

    public struct WritingOptions: OptionSet, Hashable, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let forDeleting = WritingOptions(rawValue: 1 << 0)
        public static let forMoving = WritingOptions(rawValue: 1 << 1)
        public static let forMerging = WritingOptions(rawValue: 1 << 2)
        public static let forReplacing = WritingOptions(rawValue: 1 << 3)
        public static let contentIndependentMetadataOnly = WritingOptions(rawValue: 1 << 4)
    }

    nonisolated(unsafe) private static var presenters: [any NSFilePresenter] = []
    open class var filePresenters: [any NSFilePresenter] { presenters }
    open class func addFilePresenter(_ filePresenter: any NSFilePresenter) { presenters.append(filePresenter) }
    open class func removeFilePresenter(_ filePresenter: any NSFilePresenter) { presenters.removeAll { $0 === filePresenter } }

    open var purposeIdentifier = ""

    public init(filePresenter filePresenterOrNil: (any NSFilePresenter)? = nil) { super.init() }
    public convenience override init() { self.init(filePresenter: nil) }

    open func coordinate(readingItemAt url: URL, options: ReadingOptions = [], error outError: UnsafeMutablePointer<NSError?>?,
                         byAccessor reader: (URL) -> Void) {
        reader(url)
    }

    open func coordinate(writingItemAt url: URL, options: WritingOptions = [], error outError: UnsafeMutablePointer<NSError?>?,
                         byAccessor writer: (URL) -> Void) {
        writer(url)
    }

    open func coordinate(readingItemAt readingURL: URL, options readingOptions: ReadingOptions = [],
                         writingItemAt writingURL: URL, options writingOptions: WritingOptions = [],
                         error outError: UnsafeMutablePointer<NSError?>?, byAccessor readerWriter: (URL, URL) -> Void) {
        readerWriter(readingURL, writingURL)
    }

    open func coordinate(writingItemAt url1: URL, options options1: WritingOptions = [],
                         writingItemAt url2: URL, options options2: WritingOptions = [],
                         error outError: UnsafeMutablePointer<NSError?>?, byAccessor writer: (URL, URL) -> Void) {
        writer(url1, url2)
    }

    /// Runs the accessor on `queue` once every intent's item is free, which is at once here.
    open func coordinate(with intents: [NSFileAccessIntent], queue: OperationQueue,
                         byAccessor accessor: @escaping @Sendable ((any Error)?) -> Void) {
        queue.addOperation { accessor(nil) }
    }

    open func item(at oldURL: URL, willMoveTo newURL: URL) {}
    open func item(at oldURL: URL, didMoveTo newURL: URL) {}
    open func cancel() {}
}

#endif
