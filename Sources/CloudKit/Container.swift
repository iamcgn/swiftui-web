// Containers and their databases. The browser has no iCloud account, so a container reports
// `.noAccount` and every request to its databases fails with `CKError.notAuthenticated`: the
// completion handlers and result blocks run with that error before the call that starts them
// returns, and the async forms throw it.
@_exported import WebFoundation

/// An app's iCloud container: its databases and the user's account status.
open class CKContainer: @unchecked Sendable {
    /// The app's default container.
    nonisolated(unsafe) private static var _default: CKContainer?

    /// The identifier of the container (`iCloud.` and the bundle identifier for the default one).
    public let containerIdentifier: String?
    /// The user's own records.
    public private(set) lazy var privateCloudDatabase = CKDatabase(container: self, scope: .private)
    /// Records every user of the app can read.
    public private(set) lazy var publicCloudDatabase = CKDatabase(container: self, scope: .public)
    /// Records other users shared with this one.
    public private(set) lazy var sharedCloudDatabase = CKDatabase(container: self, scope: .shared)

    public init(identifier containerIdentifier: String) {
        self.containerIdentifier = containerIdentifier
    }
    private init(defaultIdentifier: String?) {
        containerIdentifier = defaultIdentifier
    }

    /// The app's default container.
    open class func `default`() -> CKContainer {
        if let container = _default { return container }
        let container = CKContainer(defaultIdentifier: Bundle.main.bundleIdentifier.map { "iCloud.\($0)" })
        _default = container
        return container
    }

    /// The database of a scope.
    open func database(with databaseScope: CKDatabase.Scope) -> CKDatabase {
        switch databaseScope {
        case .public: return publicCloudDatabase
        case .private: return privateCloudDatabase
        case .shared: return sharedCloudDatabase
        }
    }

    /// The user's iCloud account status: there is no account in the browser.
    open func accountStatus(completionHandler: @escaping @Sendable (CKAccountStatus, (any Error)?) -> Void) {
        completionHandler(.noAccount, nil)
    }
    /// The user's iCloud account status: there is no account in the browser.
    open func accountStatus() async throws -> CKAccountStatus { .noAccount }

    /// The current user's record ID: with no account, the request fails.
    open func fetchUserRecordID(completionHandler: @escaping @Sendable (CKRecord.ID?, (any Error)?) -> Void) {
        completionHandler(nil, CKError._signedOut)
    }
    /// The current user's record ID: with no account, the request throws.
    open func userRecordID() async throws -> CKRecord.ID { throw CKError._signedOut }

    /// Runs an operation against the container (its database operations run against the
    /// private database).
    open func add(_ operation: CKOperation) {
        if operation.configuration.container == nil { operation.configuration.container = self }
        if let operation = operation as? CKDatabaseOperation, operation.database == nil { operation.database = privateCloudDatabase }
        operation.start()
    }
}

/// One of a container's databases.
open class CKDatabase: @unchecked Sendable {
    /// Which of the container's databases.
    public enum Scope: Int, Sendable, Hashable, CustomStringConvertible {
        case `public` = 1
        case `private` = 2
        case shared = 3
        public var description: String {
            switch self {
            case .public: "public"
            case .private: "private"
            case .shared: "shared"
            }
        }
    }

    public let container: CKContainer
    public let databaseScope: Scope

    init(container: CKContainer, scope: Scope) {
        self.container = container
        databaseScope = scope
    }

    /// Runs an operation against this database.
    open func add(_ operation: CKDatabaseOperation) {
        operation.database = self
        if operation.configuration.container == nil { operation.configuration.container = container }
        operation.start()
    }

    // MARK: Records

    open func fetch(withRecordID recordID: CKRecord.ID, completionHandler: @escaping @Sendable (CKRecord?, (any Error)?) -> Void) {
        completionHandler(nil, CKError._signedOut)
    }
    open func save(_ record: CKRecord, completionHandler: @escaping @Sendable (CKRecord?, (any Error)?) -> Void) {
        completionHandler(nil, CKError._signedOut)
    }
    open func delete(withRecordID recordID: CKRecord.ID, completionHandler: @escaping @Sendable (CKRecord.ID?, (any Error)?) -> Void) {
        completionHandler(nil, CKError._signedOut)
    }
    open func perform(_ query: CKQuery, inZoneWith zoneID: CKRecordZone.ID?, completionHandler: @escaping @Sendable ([CKRecord]?, (any Error)?) -> Void) {
        completionHandler(nil, CKError._signedOut)
    }
    open func fetch(withRecordIDs recordIDs: [CKRecord.ID], desiredKeys: [CKRecord.FieldKey]? = nil,
                    completionHandler: @escaping @Sendable (Result<[CKRecord.ID: Result<CKRecord, any Error>], any Error>) -> Void) {
        completionHandler(.failure(CKError._signedOut))
    }
    open func fetch(withQuery query: CKQuery, inZoneWith zoneID: CKRecordZone.ID? = nil, desiredKeys: [CKRecord.FieldKey]? = nil,
                    resultsLimit: Int = CKQueryOperation.maximumResults,
                    completionHandler: @escaping @Sendable (Result<(matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)], queryCursor: CKQueryOperation.Cursor?), any Error>) -> Void) {
        completionHandler(.failure(CKError._signedOut))
    }
    open func modifyRecords(saving recordsToSave: [CKRecord], deleting recordIDsToDelete: [CKRecord.ID],
                            savePolicy: CKModifyRecordsOperation.RecordSavePolicy = .ifServerRecordUnchanged, atomically: Bool = true,
                            completionHandler: @escaping @Sendable (Result<(saveResults: [CKRecord.ID: Result<CKRecord, any Error>], deleteResults: [CKRecord.ID: Result<Void, any Error>]), any Error>) -> Void) {
        completionHandler(.failure(CKError._signedOut))
    }

    open func record(for recordID: CKRecord.ID) async throws -> CKRecord { throw CKError._signedOut }
    open func records(for ids: [CKRecord.ID], desiredKeys: [CKRecord.FieldKey]? = nil) async throws -> [CKRecord.ID: Result<CKRecord, any Error>] {
        throw CKError._signedOut
    }
    open func save(_ record: CKRecord) async throws -> CKRecord { throw CKError._signedOut }
    open func deleteRecord(withID recordID: CKRecord.ID) async throws -> CKRecord.ID { throw CKError._signedOut }
    open func modifyRecords(saving recordsToSave: [CKRecord], deleting recordIDsToDelete: [CKRecord.ID],
                            savePolicy: CKModifyRecordsOperation.RecordSavePolicy = .ifServerRecordUnchanged,
                            atomically: Bool = true) async throws -> (saveResults: [CKRecord.ID: Result<CKRecord, any Error>], deleteResults: [CKRecord.ID: Result<Void, any Error>]) {
        throw CKError._signedOut
    }
    open func records(matching query: CKQuery, inZoneWith zoneID: CKRecordZone.ID? = nil, desiredKeys: [CKRecord.FieldKey]? = nil,
                      resultsLimit: Int = CKQueryOperation.maximumResults) async throws -> (matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)], queryCursor: CKQueryOperation.Cursor?) {
        throw CKError._signedOut
    }
    open func records(continuingMatchFrom queryCursor: CKQueryOperation.Cursor, desiredKeys: [CKRecord.FieldKey]? = nil,
                      resultsLimit: Int = CKQueryOperation.maximumResults) async throws -> (matchResults: [(CKRecord.ID, Result<CKRecord, any Error>)], queryCursor: CKQueryOperation.Cursor?) {
        throw CKError._signedOut
    }

    // MARK: Zones

    open func fetchAllRecordZones(completionHandler: @escaping @Sendable ([CKRecordZone]?, (any Error)?) -> Void) {
        completionHandler(nil, CKError._signedOut)
    }
    open func fetch(withRecordZoneID zoneID: CKRecordZone.ID, completionHandler: @escaping @Sendable (CKRecordZone?, (any Error)?) -> Void) {
        completionHandler(nil, CKError._signedOut)
    }
    open func save(_ zone: CKRecordZone, completionHandler: @escaping @Sendable (CKRecordZone?, (any Error)?) -> Void) {
        completionHandler(nil, CKError._signedOut)
    }
    open func delete(withRecordZoneID zoneID: CKRecordZone.ID, completionHandler: @escaping @Sendable (CKRecordZone.ID?, (any Error)?) -> Void) {
        completionHandler(nil, CKError._signedOut)
    }

    open func allRecordZones() async throws -> [CKRecordZone] { throw CKError._signedOut }
    open func recordZone(for zoneID: CKRecordZone.ID) async throws -> CKRecordZone { throw CKError._signedOut }
    open func save(_ zone: CKRecordZone) async throws -> CKRecordZone { throw CKError._signedOut }
    open func deleteRecordZone(withID zoneID: CKRecordZone.ID) async throws -> CKRecordZone.ID { throw CKError._signedOut }
    open func modifyRecordZones(saving recordZonesToSave: [CKRecordZone], deleting recordZoneIDsToDelete: [CKRecordZone.ID]) async throws
        -> (saveResults: [CKRecordZone.ID: Result<CKRecordZone, any Error>], deleteResults: [CKRecordZone.ID: Result<Void, any Error>]) {
        throw CKError._signedOut
    }

    // MARK: Subscriptions

    open func fetchAllSubscriptions(completionHandler: @escaping @Sendable ([CKSubscription]?, (any Error)?) -> Void) {
        completionHandler(nil, CKError._signedOut)
    }
    open func save(_ subscription: CKSubscription, completionHandler: @escaping @Sendable (CKSubscription?, (any Error)?) -> Void) {
        completionHandler(nil, CKError._signedOut)
    }
    open func delete(withSubscriptionID subscriptionID: CKSubscription.ID, completionHandler: @escaping @Sendable (CKSubscription.ID?, (any Error)?) -> Void) {
        completionHandler(nil, CKError._signedOut)
    }

    open func allSubscriptions() async throws -> [CKSubscription] { throw CKError._signedOut }
    open func subscription(for subscriptionID: CKSubscription.ID) async throws -> CKSubscription { throw CKError._signedOut }
    open func save(_ subscription: CKSubscription) async throws -> CKSubscription { throw CKError._signedOut }
    open func deleteSubscription(withID subscriptionID: CKSubscription.ID) async throws -> CKSubscription.ID { throw CKError._signedOut }
}
