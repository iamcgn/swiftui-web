// Persistent history: the token a coordinator answers, the change request, and the transaction
// and change types an app reads the result as. Core Data records each save's transaction so a
// process can merge what another process (an app's widget or share extension) wrote to the same
// store. A page is one process and its stores have no other writer, so there is never another
// author's transaction to merge: fetching history answers no transactions, and deleting it has
// nothing to delete. A token marks the stores' state when it was asked for (Dime keeps one and
// fetches what its extensions saved after it).

import SwiftData

/// A point in a store's history.
public final class NSPersistentHistoryToken: NSObject, NSSecureCoding, @unchecked Sendable {
    let generation: Int
    init(generation: Int) {
        self.generation = generation
        super.init()
    }

    public static var supportsSecureCoding: Bool { true }
    public func encode(with coder: NSCoder) { coder.encode(generation, forKey: "generation") }
    public init?(coder: NSCoder) {
        generation = coder.decodeInteger(forKey: "generation")
        super.init()
    }

    public override func isEqual(_ object: Any?) -> Bool { (object as? NSPersistentHistoryToken)?.generation == generation }
    public override var hash: Int { generation }
}

/// What a history request answers.
public enum NSPersistentHistoryResultType: Int, Sendable {
    case statusOnly = 0, objectIDs = 1, count = 2, transactionsOnly = 3, changesOnly = 4, transactionsAndChanges = 5
}

/// The kind of change a history entry records.
public enum NSPersistentHistoryChangeType: Int, Sendable {
    case insert = 0, update = 1, delete = 2
}

/// A request for the transactions after a token, date or transaction, or to delete them.
open class NSPersistentHistoryChangeRequest: NSPersistentStoreRequest, @unchecked Sendable {
    public var resultType: NSPersistentHistoryResultType = .transactionsAndChanges
    public private(set) var token: NSPersistentHistoryToken?
    /// Narrows the transactions fetched (`NSPersistentHistoryTransaction.fetchRequest`).
    public var fetchRequest: NSFetchRequest<NSFetchRequestResult>?
    let deletes: Bool

    init(token: NSPersistentHistoryToken?, deletes: Bool) {
        self.token = token
        self.deletes = deletes
        super.init()
    }

    public class func fetchHistory(after date: Date) -> NSPersistentHistoryChangeRequest { NSPersistentHistoryChangeRequest(token: nil, deletes: false) }
    public class func fetchHistory(after token: NSPersistentHistoryToken?) -> NSPersistentHistoryChangeRequest { NSPersistentHistoryChangeRequest(token: token, deletes: false) }
    public class func fetchHistory(after transaction: NSPersistentHistoryTransaction?) -> NSPersistentHistoryChangeRequest {
        NSPersistentHistoryChangeRequest(token: transaction?.token, deletes: false)
    }
    public class func fetchHistory(withFetch fetchRequest: NSFetchRequest<NSFetchRequestResult>) -> NSPersistentHistoryChangeRequest {
        let request = NSPersistentHistoryChangeRequest(token: nil, deletes: false)
        request.fetchRequest = fetchRequest
        return request
    }
    public class func deleteHistory(before date: Date) -> NSPersistentHistoryChangeRequest { NSPersistentHistoryChangeRequest(token: nil, deletes: true) }
    public class func deleteHistory(before token: NSPersistentHistoryToken?) -> NSPersistentHistoryChangeRequest { NSPersistentHistoryChangeRequest(token: token, deletes: true) }
    public class func deleteHistory(before transaction: NSPersistentHistoryTransaction?) -> NSPersistentHistoryChangeRequest {
        NSPersistentHistoryChangeRequest(token: transaction?.token, deletes: true)
    }
}

/// The result of a history request: the transactions, their changes, a count or a status.
open class NSPersistentHistoryResult: NSPersistentStoreResult, @unchecked Sendable {
    public let result: Any?
    init(result: Any?) {
        self.result = result
        super.init()
    }
}

/// One save's changes, by the context and author that made them.
open class NSPersistentHistoryTransaction: NSObject, @unchecked Sendable {
    public let timestamp: Date
    public let changes: [NSPersistentHistoryChange]?
    public let storeID: String
    public let bundleID: String
    public let processID: String
    public let contextName: String?
    public let author: String?
    public let token: NSPersistentHistoryToken
    public let transactionNumber: Int64

    init(timestamp: Date, changes: [NSPersistentHistoryChange]?, storeID: String, contextName: String?, author: String?,
         token: NSPersistentHistoryToken, transactionNumber: Int64) {
        self.timestamp = timestamp
        self.changes = changes
        self.storeID = storeID
        bundleID = ""
        processID = ""
        self.contextName = contextName
        self.author = author
        self.token = token
        self.transactionNumber = transactionNumber
        super.init()
    }

    /// The notification a context merges the transaction's changes from.
    open func objectIDNotification() -> Notification {
        Notification(name: .NSManagedObjectContextDidSave, object: nil, userInfo: [:])
    }

    /// A fetch request whose predicate narrows the transactions a history request answers.
    open class var fetchRequest: NSFetchRequest<NSFetchRequestResult>? { NSFetchRequest(entityName: "Transaction") }
    open class func entityDescription(with context: NSManagedObjectContext) -> NSEntityDescription? { nil }
    open class var entityDescription: NSEntityDescription? { nil }
}

/// One object's change within a transaction.
open class NSPersistentHistoryChange: NSObject, @unchecked Sendable {
    public let changeID: Int64
    public let changedObjectID: NSManagedObjectID
    public let changeType: NSPersistentHistoryChangeType
    public let tombstone: [AnyHashable: Any]?
    public let transaction: NSPersistentHistoryTransaction?
    public let updatedProperties: Set<NSPropertyDescription>?

    init(changeID: Int64, changedObjectID: NSManagedObjectID, changeType: NSPersistentHistoryChangeType) {
        self.changeID = changeID
        self.changedObjectID = changedObjectID
        self.changeType = changeType
        tombstone = nil
        transaction = nil
        updatedProperties = nil
        super.init()
    }

    open class var fetchRequest: NSFetchRequest<NSFetchRequestResult>? { NSFetchRequest(entityName: "Change") }
    open class func entityDescription(with context: NSManagedObjectContext) -> NSEntityDescription? { nil }
    open class var entityDescription: NSEntityDescription? { nil }
}

extension NSPersistentStoreCoordinator {
    /// A token for the stores' present state.
    public func currentPersistentHistoryToken(fromStores stores: [Any]?) -> NSPersistentHistoryToken? {
        NSPersistentHistoryToken(generation: _generation)
    }

    /// The metadata of the store at the URL: its type, and the identifier of the store there
    /// that a coordinator has open (stores here keep no other metadata).
    public class func metadataForPersistentStore(ofType storeType: String, at url: URL, options: [AnyHashable: Any]? = nil) throws -> [String: Any] {
        [NSStoreTypeKey: storeType]
    }

    /// Recorded: a store's metadata is its type and identifier.
    public class func setMetadata(_ metadata: [String: Any]?, forPersistentStoreOfType storeType: String, at url: URL,
                                  options: [AnyHashable: Any]? = nil) throws {}
}

extension NSManagedObjectContext {
    func _executeHistory(_ request: NSPersistentHistoryChangeRequest) -> NSPersistentHistoryResult {
        switch request.resultType {
        case .statusOnly: return NSPersistentHistoryResult(result: true)
        case .count: return NSPersistentHistoryResult(result: 0)
        case .objectIDs: return NSPersistentHistoryResult(result: [NSManagedObjectID]())
        case .changesOnly: return NSPersistentHistoryResult(result: [NSPersistentHistoryChange]())
        case .transactionsOnly, .transactionsAndChanges:
            return NSPersistentHistoryResult(result: request.deletes ? true as Any : [NSPersistentHistoryTransaction]())
        }
    }
}
