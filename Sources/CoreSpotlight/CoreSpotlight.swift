// Core Spotlight on the web: a page has no system search to put an app's items in, so an index
// keeps what the app indexes and deletes, by identifier and by domain, and answers each call as
// the device's would once indexing finished. Items never surface in a search, so no continuation
// arrives from one; the activity types and user info keys an app matches continuations against
// are Apple's own strings. Apple's framework re-exports Foundation and UniformTypeIdentifiers: a
// file importing only this module names `Date` and `UTType`.
@_exported import WebFoundation
@_exported import struct WebGraphics.UTType

/// The activity type of a continuation from a searchable item the user picked.
public let CSSearchableItemActionType = "com.apple.corespotlightitem"
/// The `userInfo` key of the picked item's unique identifier.
public let CSSearchableItemActivityIdentifier = "kCSSearchableItemActivityIdentifier"
/// The activity type of a search that continues in the app.
public let CSQueryContinuationActionType = "com.apple.corespotlightquerycontinuation"
/// The `userInfo` key of the query a search continues with.
public let CSSearchQueryString = "kCSSearchQueryString"

/// What search shows of an item: its type, names, description, keywords and links.
open class CSSearchableItemAttributeSet: @unchecked Sendable {
    /// The content type's identifier.
    open var contentType: String?
    open var contentTypeTree: [String]?
    open var identifier: String?
    open var domainIdentifier: String?
    open var relatedUniqueIdentifier: String?
    open var weakRelatedUniqueIdentifier: String?
    open var title: String?
    open var displayName: String?
    open var alternateNames: [String]?
    open var contentDescription: String?
    open var keywords: [String]?
    open var subject: String?
    open var theme: String?
    open var version: String?
    open var path: String?
    open var url: URL?
    open var contentURL: URL?
    open var thumbnailURL: URL?
    open var darkThumbnailURL: URL?
    open var thumbnailData: Data?
    open var contentCreationDate: Date?
    open var contentModificationDate: Date?
    open var addedDate: Date?
    open var lastUsedDate: Date?
    open var dueDate: Date?
    open var completionDate: Date?
    open var startDate: Date?
    open var endDate: Date?
    open var phoneNumbers: [String]?
    open var emailAddresses: [String]?
    open var authorNames: [String]?
    open var actionIdentifiers: [String] = []
    open var sharedItemContentType: UTType?
    open var textContent: String?
    open var userCreated: Bool?
    open var userOwned: Bool?
    open var userCurated: Bool?
    open var supportsPhoneCall: Bool?
    open var supportsNavigation: Bool?
    open var latitude: Double?
    open var longitude: Double?
    open var namedLocation: String?
    open var rating: Double?
    open var ratingDescription: String?

    public init() {}
    /// A set for content of the type.
    public init(contentType: UTType) { self.contentType = contentType.identifier }
    @available(*, deprecated, renamed: "init(contentType:)")
    public init(itemContentType: String) { self.contentType = itemContentType }
}

/// An item an app puts in the index: its identifiers, its attributes and when it expires.
open class CSSearchableItem: @unchecked Sendable {
    /// The item's identifier in the app: a new UUID when the app gives none.
    open var uniqueIdentifier: String
    open var domainIdentifier: String?
    open var attributeSet: CSSearchableItemAttributeSet
    /// When the index drops the item: a month after it was made unless the app sets another date.
    open var expirationDate: Date!
    /// Whether indexing updates the item's attributes rather than replacing it.
    open var isUpdate = false

    public init(uniqueIdentifier: String?, domainIdentifier: String?, attributeSet: CSSearchableItemAttributeSet) {
        self.uniqueIdentifier = uniqueIdentifier ?? UUID().uuidString
        self.domainIdentifier = domainIdentifier
        self.attributeSet = attributeSet
        self.expirationDate = Date().addingTimeInterval(30 * 24 * 60 * 60)
    }
}

/// The errors an index reports.
public struct CSIndexError: Error, Hashable, Sendable {
    public enum Code: Int, Sendable {
        case unknownError = -1
        case indexUnavailableError = -1000
        case invalidItemError = -1001
        case invalidClientStateError = -1002
        case remoteConnectionError = -1003
        case quotaExceeded = -1004
        case indexingUnsupported = -1005
    }
    public let code: Code
    public init(_ code: Code) { self.code = code }
}

/// An index of an app's searchable items. The default index and each named one keep their items
/// for as long as the page runs.
open class CSSearchableIndex: @unchecked Sendable {
    private static let shared = CSSearchableIndex(name: "default")
    public let name: String
    private var items: [String: CSSearchableItem] = [:]
    private var clientState: Data?
    private var inBatch = false
    private let lock = NSLock()

    /// Whether the device can index: a page keeps its index, so it can.
    open class func isIndexingAvailable() -> Bool { true }
    /// The app's default index.
    open class func `default`() -> CSSearchableIndex { shared }

    public init(name: String) { self.name = name }
    public convenience init(name: String, protectionClass: String?) { self.init(name: name) }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// The items the index holds now, by unique identifier.
    public var _items: [String: CSSearchableItem] { locked { items } }

    // MARK: Indexing

    /// Adds the items, replacing those with the same unique identifiers (or, for an update,
    /// taking the attributes the update sets).
    open func indexSearchableItems(_ items: [CSSearchableItem], completionHandler: (((any Error)?) -> Void)? = nil) {
        locked {
            for item in items {
                if item.isUpdate, let old = self.items[item.uniqueIdentifier] {
                    old.attributeSet = item.attributeSet
                    old.domainIdentifier = item.domainIdentifier ?? old.domainIdentifier
                    old.expirationDate = item.expirationDate
                } else {
                    self.items[item.uniqueIdentifier] = item
                }
            }
        }
        completionHandler?(nil)
    }

    open func indexSearchableItems(_ items: [CSSearchableItem]) async throws {
        indexSearchableItems(items, completionHandler: nil)
    }

    open func deleteSearchableItems(withIdentifiers identifiers: [String], completionHandler: (((any Error)?) -> Void)? = nil) {
        locked { for id in identifiers { items[id] = nil } }
        completionHandler?(nil)
    }

    open func deleteSearchableItems(withIdentifiers identifiers: [String]) async throws {
        deleteSearchableItems(withIdentifiers: identifiers, completionHandler: nil)
    }

    /// Deletes the items in the domains and in their subdomains (`a.b` is in `a`).
    open func deleteSearchableItems(withDomainIdentifiers domainIdentifiers: [String], completionHandler: (((any Error)?) -> Void)? = nil) {
        locked {
            items = items.filter { _, item in
                guard let domain = item.domainIdentifier else { return true }
                return !domainIdentifiers.contains { domain == $0 || domain.hasPrefix($0 + ".") }
            }
        }
        completionHandler?(nil)
    }

    open func deleteSearchableItems(withDomainIdentifiers domainIdentifiers: [String]) async throws {
        deleteSearchableItems(withDomainIdentifiers: domainIdentifiers, completionHandler: nil)
    }

    open func deleteAllSearchableItems(completionHandler: (((any Error)?) -> Void)? = nil) {
        locked { items = [:] }
        completionHandler?(nil)
    }

    open func deleteAllSearchableItems() async throws {
        deleteAllSearchableItems(completionHandler: nil)
    }

    // MARK: Batches

    /// Starts a batch whose end records the app's client state.
    open func beginBatch() { locked { inBatch = true } }

    open func endBatch(withClientState clientState: Data, completionHandler: (((any Error)?) -> Void)? = nil) {
        let error: (any Error)? = locked {
            guard inBatch else { return CSIndexError(.invalidClientStateError) }
            self.clientState = clientState
            inBatch = false
            return nil
        }
        completionHandler?(error)
    }

    open func endBatch(withClientState clientState: Data) async throws {
        let ended = locked { () -> Bool in
            guard inBatch else { return false }
            self.clientState = clientState
            inBatch = false
            return true
        }
        if !ended { throw CSIndexError(.invalidClientStateError) }
    }

    /// The client state the last batch recorded (nil before any).
    open func fetchLastClientState(completionHandler: @escaping (Data?, (any Error)?) -> Void) {
        completionHandler(locked { clientState }, nil)
    }

    open func fetchLastClientState() async throws -> Data? { locked { clientState } }
}

#if !canImport(Darwin)
extension NSUserActivity {
    /// What search shows of the activity.
    public var contentAttributeSet: CSSearchableItemAttributeSet? {
        get { _attached["CoreSpotlight.contentAttributeSet"] as? CSSearchableItemAttributeSet }
        set { _attached["CoreSpotlight.contentAttributeSet"] = newValue }
    }
}
#endif
