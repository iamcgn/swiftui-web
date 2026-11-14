// CloudKit's operations. Added to a database or container, an operation runs at once and, with
// no iCloud account in the browser, ends with `CKError.notAuthenticated`: its result block and
// its older completion block get that error, and no per-item block runs.
@_exported import WebFoundation

/// A request to CloudKit, run by adding it to a container or a database.
open class CKOperation: Operation, @unchecked Sendable {
    public typealias ID = String

    /// How an operation runs: its container, service level and timeouts.
    open class Configuration: @unchecked Sendable {
        open var container: CKContainer?
        open var qualityOfService: QualityOfService = .default
        open var allowsCellularAccess = true
        open var isLongLived = false
        open var timeoutIntervalForRequest: TimeInterval = 60
        open var timeoutIntervalForResource: TimeInterval = 7 * 24 * 60 * 60
        public init() {}
    }

    open var configuration = Configuration()
    /// A unique identifier of the operation.
    public let operationID: ID = UUID().uuidString

    public required override init() { super.init() }

    open override func main() { _finish(with: CKError._signedOut) }

    /// Runs the operation's result and completion blocks with `error`.
    func _finish(with error: CKError) {}
}

/// An operation against one database.
open class CKDatabaseOperation: CKOperation, @unchecked Sendable {
    /// The database the operation runs against (the container's private one when unset).
    open var database: CKDatabase?
    public required init() { super.init() }
}

// MARK: - Queries

/// Finds the records that match a query.
open class CKQueryOperation: CKDatabaseOperation, @unchecked Sendable {
    /// Asks for every matching record, in batches the server picks.
    public static let maximumResults = 0

    /// Where a query's results continue.
    public final class Cursor: Hashable, @unchecked Sendable {
        let query: CKQuery?
        init(query: CKQuery?) { self.query = query }
        public static func == (lhs: Cursor, rhs: Cursor) -> Bool { lhs === rhs }
        public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
    }

    open var query: CKQuery?
    open var cursor: Cursor?
    open var zoneID: CKRecordZone.ID?
    open var desiredKeys: [CKRecord.FieldKey]?
    open var resultsLimit = CKQueryOperation.maximumResults
    open var recordMatchedBlock: (@Sendable (CKRecord.ID, Result<CKRecord, any Error>) -> Void)?
    open var queryResultBlock: (@Sendable (Result<Cursor?, any Error>) -> Void)?
    open var recordFetchedBlock: (@Sendable (CKRecord) -> Void)?
    open var queryCompletionBlock: (@Sendable (Cursor?, (any Error)?) -> Void)?

    public required init() { super.init() }
    public convenience init(query: CKQuery) {
        self.init()
        self.query = query
    }
    public convenience init(cursor: Cursor) {
        self.init()
        self.cursor = cursor
    }

    override func _finish(with error: CKError) {
        queryResultBlock?(.failure(error))
        queryCompletionBlock?(nil, error)
    }
}

// MARK: - Records

/// Fetches records by ID.
open class CKFetchRecordsOperation: CKDatabaseOperation, @unchecked Sendable {
    open var recordIDs: [CKRecord.ID]?
    open var desiredKeys: [CKRecord.FieldKey]?
    open var perRecordProgressBlock: (@Sendable (CKRecord.ID, Double) -> Void)?
    open var perRecordResultBlock: (@Sendable (CKRecord.ID, Result<CKRecord, any Error>) -> Void)?
    open var fetchRecordsResultBlock: (@Sendable (Result<Void, any Error>) -> Void)?
    open var perRecordCompletionBlock: (@Sendable (CKRecord?, CKRecord.ID?, (any Error)?) -> Void)?
    open var fetchRecordsCompletionBlock: (@Sendable ([CKRecord.ID: CKRecord]?, (any Error)?) -> Void)?

    public required init() { super.init() }
    public convenience init(recordIDs: [CKRecord.ID]) {
        self.init()
        self.recordIDs = recordIDs
    }

    /// Fetches the current user's record.
    open class func fetchCurrentUserRecordOperation() -> Self {
        let operation = Self()
        operation.recordIDs = [CKRecord.ID(recordName: CKCurrentUserDefaultName)]
        return operation
    }

    override func _finish(with error: CKError) {
        fetchRecordsResultBlock?(.failure(error))
        fetchRecordsCompletionBlock?(nil, error)
    }
}

/// Saves and deletes records.
open class CKModifyRecordsOperation: CKDatabaseOperation, @unchecked Sendable {
    /// Which fields a save sends, and whether it may overwrite newer changes on the server.
    public enum RecordSavePolicy: Int, Sendable, Hashable {
        case ifServerRecordUnchanged = 0
        case changedKeys = 1
        case allKeys = 2
    }

    open var recordsToSave: [CKRecord]?
    open var recordIDsToDelete: [CKRecord.ID]?
    open var savePolicy: RecordSavePolicy = .ifServerRecordUnchanged
    open var isAtomic = true
    open var clientChangeTokenData: Data?
    open var perRecordProgressBlock: (@Sendable (CKRecord, Double) -> Void)?
    open var perRecordSaveBlock: (@Sendable (CKRecord.ID, Result<CKRecord, any Error>) -> Void)?
    open var perRecordDeleteBlock: (@Sendable (CKRecord.ID, Result<Void, any Error>) -> Void)?
    open var modifyRecordsResultBlock: (@Sendable (Result<Void, any Error>) -> Void)?
    open var perRecordCompletionBlock: (@Sendable (CKRecord, (any Error)?) -> Void)?
    open var modifyRecordsCompletionBlock: (@Sendable ([CKRecord]?, [CKRecord.ID]?, (any Error)?) -> Void)?

    public required init() { super.init() }
    public convenience init(recordsToSave: [CKRecord]?, recordIDsToDelete: [CKRecord.ID]?) {
        self.init()
        self.recordsToSave = recordsToSave
        self.recordIDsToDelete = recordIDsToDelete
    }

    override func _finish(with error: CKError) {
        modifyRecordsResultBlock?(.failure(error))
        modifyRecordsCompletionBlock?(nil, nil, error)
    }
}

// MARK: - Zones

/// Fetches record zones by ID.
open class CKFetchRecordZonesOperation: CKDatabaseOperation, @unchecked Sendable {
    open var recordZoneIDs: [CKRecordZone.ID]?
    open var perRecordZoneResultBlock: (@Sendable (CKRecordZone.ID, Result<CKRecordZone, any Error>) -> Void)?
    open var fetchRecordZonesResultBlock: (@Sendable (Result<Void, any Error>) -> Void)?
    open var fetchRecordZonesCompletionBlock: (@Sendable ([CKRecordZone.ID: CKRecordZone]?, (any Error)?) -> Void)?

    public required init() { super.init() }
    public convenience init(recordZoneIDs zoneIDs: [CKRecordZone.ID]) {
        self.init()
        recordZoneIDs = zoneIDs
    }
    /// Fetches every zone of the database.
    open class func fetchAllRecordZonesOperation() -> Self { Self() }

    override func _finish(with error: CKError) {
        fetchRecordZonesResultBlock?(.failure(error))
        fetchRecordZonesCompletionBlock?(nil, error)
    }
}

/// Saves and deletes record zones.
open class CKModifyRecordZonesOperation: CKDatabaseOperation, @unchecked Sendable {
    open var recordZonesToSave: [CKRecordZone]?
    open var recordZoneIDsToDelete: [CKRecordZone.ID]?
    open var perRecordZoneSaveBlock: (@Sendable (CKRecordZone.ID, Result<CKRecordZone, any Error>) -> Void)?
    open var perRecordZoneDeleteBlock: (@Sendable (CKRecordZone.ID, Result<Void, any Error>) -> Void)?
    open var modifyRecordZonesResultBlock: (@Sendable (Result<Void, any Error>) -> Void)?
    open var modifyRecordZonesCompletionBlock: (@Sendable ([CKRecordZone]?, [CKRecordZone.ID]?, (any Error)?) -> Void)?

    public required init() { super.init() }
    public convenience init(recordZonesToSave: [CKRecordZone]?, recordZoneIDsToDelete: [CKRecordZone.ID]?) {
        self.init()
        self.recordZonesToSave = recordZonesToSave
        self.recordZoneIDsToDelete = recordZoneIDsToDelete
    }

    override func _finish(with error: CKError) {
        modifyRecordZonesResultBlock?(.failure(error))
        modifyRecordZonesCompletionBlock?(nil, nil, error)
    }
}

// MARK: - Changes

/// Fetches the zones of a database that changed since a token.
open class CKFetchDatabaseChangesOperation: CKDatabaseOperation, @unchecked Sendable {
    open var previousServerChangeToken: CKServerChangeToken?
    open var resultsLimit = 0
    open var fetchAllChanges = true
    open var recordZoneWithIDChangedBlock: (@Sendable (CKRecordZone.ID) -> Void)?
    open var recordZoneWithIDWasDeletedBlock: (@Sendable (CKRecordZone.ID) -> Void)?
    open var recordZoneWithIDWasPurgedBlock: (@Sendable (CKRecordZone.ID) -> Void)?
    open var changeTokenUpdatedBlock: (@Sendable (CKServerChangeToken) -> Void)?
    open var fetchDatabaseChangesResultBlock: (@Sendable (Result<(serverChangeToken: CKServerChangeToken, moreComing: Bool), any Error>) -> Void)?
    open var fetchDatabaseChangesCompletionBlock: (@Sendable (CKServerChangeToken?, Bool, (any Error)?) -> Void)?

    public required init() { super.init() }
    public convenience init(previousServerChangeToken: CKServerChangeToken?) {
        self.init()
        self.previousServerChangeToken = previousServerChangeToken
    }

    override func _finish(with error: CKError) {
        fetchDatabaseChangesResultBlock?(.failure(error))
        fetchDatabaseChangesCompletionBlock?(nil, false, error)
    }
}

/// Fetches the records of zones that changed since each zone's token.
open class CKFetchRecordZoneChangesOperation: CKDatabaseOperation, @unchecked Sendable {
    /// What to fetch from one zone.
    open class ZoneConfiguration: @unchecked Sendable {
        open var previousServerChangeToken: CKServerChangeToken?
        open var resultsLimit = 0
        open var desiredKeys: [CKRecord.FieldKey]?
        public init() {}
        public convenience init(previousServerChangeToken: CKServerChangeToken? = nil, resultsLimit: Int? = nil, desiredKeys: [CKRecord.FieldKey]? = nil) {
            self.init()
            self.previousServerChangeToken = previousServerChangeToken
            self.resultsLimit = resultsLimit ?? 0
            self.desiredKeys = desiredKeys
        }
    }

    open var recordZoneIDs: [CKRecordZone.ID]?
    open var configurationsByRecordZoneID: [CKRecordZone.ID: ZoneConfiguration]?
    open var fetchAllChanges = true
    open var recordWasChangedBlock: (@Sendable (CKRecord.ID, Result<CKRecord, any Error>) -> Void)?
    open var recordChangedBlock: (@Sendable (CKRecord) -> Void)?
    open var recordWithIDWasDeletedBlock: (@Sendable (CKRecord.ID, CKRecord.RecordType) -> Void)?
    open var recordZoneChangeTokensUpdatedBlock: (@Sendable (CKRecordZone.ID, CKServerChangeToken?, Data?) -> Void)?
    open var recordZoneFetchResultBlock: (@Sendable (CKRecordZone.ID, Result<(serverChangeToken: CKServerChangeToken, clientChangeTokenData: Data?, moreComing: Bool), any Error>) -> Void)?
    open var recordZoneFetchCompletionBlock: (@Sendable (CKRecordZone.ID, CKServerChangeToken?, Data?, Bool, (any Error)?) -> Void)?
    open var fetchRecordZoneChangesResultBlock: (@Sendable (Result<Void, any Error>) -> Void)?
    open var fetchRecordZoneChangesCompletionBlock: (@Sendable ((any Error)?) -> Void)?

    public required init() { super.init() }
    public convenience init(recordZoneIDs: [CKRecordZone.ID], configurationsByRecordZoneID: [CKRecordZone.ID: ZoneConfiguration]? = nil) {
        self.init()
        self.recordZoneIDs = recordZoneIDs
        self.configurationsByRecordZoneID = configurationsByRecordZoneID
    }

    override func _finish(with error: CKError) {
        fetchRecordZoneChangesResultBlock?(.failure(error))
        fetchRecordZoneChangesCompletionBlock?(error)
    }
}

// MARK: - Subscriptions

/// Saves and deletes subscriptions.
open class CKModifySubscriptionsOperation: CKDatabaseOperation, @unchecked Sendable {
    open var subscriptionsToSave: [CKSubscription]?
    open var subscriptionIDsToDelete: [CKSubscription.ID]?
    open var perSubscriptionSaveBlock: (@Sendable (CKSubscription.ID, Result<CKSubscription, any Error>) -> Void)?
    open var perSubscriptionDeleteBlock: (@Sendable (CKSubscription.ID, Result<Void, any Error>) -> Void)?
    open var modifySubscriptionsResultBlock: (@Sendable (Result<Void, any Error>) -> Void)?
    open var modifySubscriptionsCompletionBlock: (@Sendable ([CKSubscription]?, [CKSubscription.ID]?, (any Error)?) -> Void)?

    public required init() { super.init() }
    public convenience init(subscriptionsToSave: [CKSubscription]?, subscriptionIDsToDelete: [CKSubscription.ID]?) {
        self.init()
        self.subscriptionsToSave = subscriptionsToSave
        self.subscriptionIDsToDelete = subscriptionIDsToDelete
    }

    override func _finish(with error: CKError) {
        modifySubscriptionsResultBlock?(.failure(error))
        modifySubscriptionsCompletionBlock?(nil, nil, error)
    }
}

/// Fetches subscriptions by ID.
open class CKFetchSubscriptionsOperation: CKDatabaseOperation, @unchecked Sendable {
    open var subscriptionIDs: [CKSubscription.ID]?
    open var perSubscriptionResultBlock: (@Sendable (CKSubscription.ID, Result<CKSubscription, any Error>) -> Void)?
    open var fetchSubscriptionsResultBlock: (@Sendable (Result<Void, any Error>) -> Void)?
    open var fetchSubscriptionCompletionBlock: (@Sendable ([CKSubscription.ID: CKSubscription]?, (any Error)?) -> Void)?

    public required init() { super.init() }
    public convenience init(subscriptionIDs: [CKSubscription.ID]) {
        self.init()
        self.subscriptionIDs = subscriptionIDs
    }
    /// Fetches every subscription of the database.
    open class func fetchAllSubscriptionsOperation() -> Self { Self() }

    override func _finish(with error: CKError) {
        fetchSubscriptionsResultBlock?(.failure(error))
        fetchSubscriptionCompletionBlock?(nil, error)
    }
}
