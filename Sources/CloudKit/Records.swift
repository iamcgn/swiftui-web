// Records, their IDs, zones, references and assets: the values an app builds to save and reads
// back. They are plain values here, kept in memory: nothing reaches a server.
@_exported import WebFoundation
#if os(WASI)
// Foundation declares predicates and sort descriptors on Apple's platforms; here Core Data does,
// so a query sees them as an app that imports only CloudKit expects.
@_exported import class WebCoreData.NSPredicate
@_exported import class WebCoreData.NSCompoundPredicate
@_exported import class WebCoreData.NSSortDescriptor
#endif

/// The name of the current user's default owner of a zone.
public let CKCurrentUserDefaultName = "__defaultOwner__"
/// The name of the current user's default owner, as older code names it.
public let CKOwnerDefaultName = "__defaultOwner__"

/// A value a record can hold in a field.
public protocol CKRecordValueProtocol {}
/// A value a record can hold in a field (the name Objective-C code uses).
public typealias CKRecordValue = CKRecordValueProtocol

extension String: CKRecordValueProtocol {}
extension Int: CKRecordValueProtocol {}
extension Int8: CKRecordValueProtocol {}
extension Int16: CKRecordValueProtocol {}
extension Int32: CKRecordValueProtocol {}
extension Int64: CKRecordValueProtocol {}
extension UInt: CKRecordValueProtocol {}
extension UInt8: CKRecordValueProtocol {}
extension UInt16: CKRecordValueProtocol {}
extension UInt32: CKRecordValueProtocol {}
extension UInt64: CKRecordValueProtocol {}
extension Double: CKRecordValueProtocol {}
extension Float: CKRecordValueProtocol {}
extension Bool: CKRecordValueProtocol {}
extension Date: CKRecordValueProtocol {}
extension Data: CKRecordValueProtocol {}
extension Array: CKRecordValueProtocol where Element: CKRecordValueProtocol {}

// MARK: - Zones

/// A zone of a database, where records live.
open class CKRecordZone: CustomStringConvertible, @unchecked Sendable {
    /// A zone's identity: its name and owner.
    public struct ID: Hashable, Sendable, CustomStringConvertible {
        /// The name of the zone every database has.
        public static let defaultZoneName = "_defaultZone"
        /// The default zone of the current user.
        public static let `default` = ID()

        public let zoneName: String
        public let ownerName: String

        public init(zoneName: String = ID.defaultZoneName, ownerName: String = CKCurrentUserDefaultName) {
            self.zoneName = zoneName
            self.ownerName = ownerName
        }
        public var description: String { "<CKRecordZoneID: zoneName=\(zoneName), ownerName=\(ownerName)>" }
    }

    /// What a zone can do.
    public struct Capabilities: OptionSet, Hashable, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let fetchChanges = Capabilities(rawValue: 1 << 0)
        public static let atomic = Capabilities(rawValue: 1 << 1)
        public static let sharing = Capabilities(rawValue: 1 << 2)
        public static let zoneWideSharing = Capabilities(rawValue: 1 << 3)
    }

    public let zoneID: ID
    open var capabilities: Capabilities
    /// The share of the whole zone, when it is shared.
    open var share: CKRecord.Reference?

    public init(zoneName: String) {
        zoneID = ID(zoneName: zoneName)
        capabilities = zoneName == ID.defaultZoneName ? [] : [.fetchChanges, .atomic, .sharing, .zoneWideSharing]
    }
    public init(zoneID: ID) {
        self.zoneID = zoneID
        capabilities = zoneID.zoneName == ID.defaultZoneName ? [] : [.fetchChanges, .atomic, .sharing, .zoneWideSharing]
    }

    /// The default zone of a database.
    open class func `default`() -> CKRecordZone { CKRecordZone(zoneID: .default) }

    open var description: String { "<CKRecordZone: \(zoneID.zoneName)>" }
}

// MARK: - Records

/// A record: a type, an identity and named fields.
open class CKRecord: CustomStringConvertible, @unchecked Sendable {
    public typealias RecordType = String
    public typealias FieldKey = String

    /// A record's identity: its name and the zone it lives in.
    public struct ID: Hashable, Sendable, CustomStringConvertible {
        public let recordName: String
        public let zoneID: CKRecordZone.ID

        /// An identity with a new unique name.
        public init(zoneID: CKRecordZone.ID = .default) {
            self.init(recordName: UUID().uuidString, zoneID: zoneID)
        }
        public init(recordName: String, zoneID: CKRecordZone.ID = .default) {
            self.recordName = recordName
            self.zoneID = zoneID
        }
        public var description: String { "<CKRecordID: \(recordName):(\(zoneID.zoneName):\(zoneID.ownerName))>" }
    }

    /// A link from one record to another.
    public final class Reference: CKRecordValueProtocol, Hashable, CustomStringConvertible, @unchecked Sendable {
        /// What happens to the record holding a reference when the target is deleted.
        public enum Action: UInt, Sendable, Hashable {
            case none = 0
            case deleteSelf = 1
        }
        public let recordID: CKRecord.ID
        public let action: Action

        public init(recordID: CKRecord.ID, action: Action) {
            self.recordID = recordID
            self.action = action
        }
        public convenience init(record: CKRecord, action: Action) {
            self.init(recordID: record.recordID, action: action)
        }
        public static func == (lhs: Reference, rhs: Reference) -> Bool { lhs.recordID == rhs.recordID && lhs.action == rhs.action }
        public func hash(into hasher: inout Hasher) { hasher.combine(recordID) }
        public var description: String { "<CKReference: \(recordID.recordName)>" }
    }

    /// The fields CloudKit sets itself, by the names queries and sort descriptors use.
    public enum SystemFieldKey {
        public static let creationDate = "creationDate"
        public static let creatorUserRecordID = "creatorUserRecordID"
        public static let modificationDate = "modificationDate"
        public static let lastModifiedUserRecordID = "lastModifiedUserRecordID"
        public static let recordID = "recordID"
        public static let share = "share"
        public static let parent = "parent"
    }

    public let recordType: RecordType
    public let recordID: ID
    /// When the record was first saved (nil until it is: nothing saves here).
    open internal(set) var creationDate: Date?
    open internal(set) var modificationDate: Date?
    open internal(set) var creatorUserRecordID: ID?
    open internal(set) var lastModifiedUserRecordID: ID?
    /// The server's version of the record (nil until it is saved).
    open internal(set) var recordChangeTag: String?
    /// The record this one belongs to, for sharing.
    open var parent: Reference?
    /// The share the record belongs to.
    open internal(set) var share: Reference?

    private var fields: [FieldKey: any CKRecordValueProtocol] = [:]
    private var order: [FieldKey] = []
    private var changed: [FieldKey] = []

    public init(recordType: RecordType, recordID: ID = ID()) {
        self.recordType = recordType
        self.recordID = recordID
    }
    public convenience init(recordType: RecordType, zoneID: CKRecordZone.ID) {
        self.init(recordType: recordType, recordID: ID(zoneID: zoneID))
    }

    /// A field's value.
    open subscript(key: FieldKey) -> (any CKRecordValueProtocol)? {
        get { fields[key] }
        set { _set(newValue, forKey: key) }
    }

    /// A field's value as a type (`let title: String? = record["title"]`).
    public subscript<T: CKRecordValueProtocol>(key: FieldKey) -> T? { fields[key] as? T }

    open func object(forKey key: FieldKey) -> (any CKRecordValueProtocol)? { fields[key] }
    open func setObject(_ object: (any CKRecordValueProtocol)?, forKey key: FieldKey) { _set(object, forKey: key) }
    open func value(forKey key: String) -> Any? { fields[key] }
    open func setValue(_ value: Any?, forKey key: String) { _set(value as? any CKRecordValueProtocol, forKey: key) }
    /// The names of the fields that hold a value.
    open func allKeys() -> [FieldKey] { order }
    /// The fields set since the record was made or fetched.
    open func changedKeys() -> [FieldKey] { changed }
    /// The share of a record is set by saving the share with the record as its root.
    open func setParent(_ parentRecord: CKRecord?) {
        parent = parentRecord.map { Reference(record: $0, action: .none) }
    }
    open func setParent(_ parentRecordID: ID?) {
        parent = parentRecordID.map { Reference(recordID: $0, action: .none) }
    }

    private func _set(_ value: (any CKRecordValueProtocol)?, forKey key: FieldKey) {
        if let value {
            if fields[key] == nil { order.append(key) }
            fields[key] = value
        } else if fields[key] != nil {
            fields[key] = nil
            order.removeAll { $0 == key }
        }
        if !changed.contains(key) { changed.append(key) }
    }

    open var description: String { "<CKRecord: \(recordType) \(recordID.recordName)>" }
}

// MARK: - Assets

/// A file stored with a record.
public final class CKAsset: CKRecordValueProtocol, @unchecked Sendable {
    public let fileURL: URL?
    public init(fileURL: URL) { self.fileURL = fileURL }
}

// MARK: - Change tokens

/// Where an app's last fetch of changes stopped.
public final class CKServerChangeToken: Hashable, @unchecked Sendable {
    let value: String
    init(_ value: String) { self.value = value }
    public static func == (lhs: CKServerChangeToken, rhs: CKServerChangeToken) -> Bool { lhs.value == rhs.value }
    public func hash(into hasher: inout Hasher) { hasher.combine(value) }
}

// MARK: - Queries

/// A search for records of one type that match a predicate.
open class CKQuery: CustomStringConvertible, @unchecked Sendable {
    public let recordType: CKRecord.RecordType
    public let predicate: NSPredicate
    open var sortDescriptors: [NSSortDescriptor]?

    public init(recordType: CKRecord.RecordType, predicate: NSPredicate) {
        self.recordType = recordType
        self.predicate = predicate
    }
    open var description: String { "<CKQuery: recordType=\(recordType), predicate=\(predicate)>" }
}

// MARK: - Sharing

/// A record that shares another record (or a whole zone) with other people.
open class CKShare: CKRecord, @unchecked Sendable {
    /// The fields of a share that the system shows.
    public enum SystemFieldKey {
        public static let title = "cloudkit.title"
        public static let thumbnailImageData = "cloudkit.thumbnailImageData"
        public static let shareType = "cloudkit.type"
    }
    /// The record type of shares.
    public enum SystemType {
        public static let share = "cloudkit.share"
    }

    /// What a participant may do with the shared records.
    public enum ParticipantPermission: Int, Sendable, Hashable {
        case unknown = 0, none = 1, readOnly = 2, readWrite = 3
    }
    /// A participant's place in the share.
    public enum ParticipantRole: Int, Sendable, Hashable {
        case unknown = 0, owner = 1, privateUser = 3, publicUser = 4, administrator = 2
    }
    /// Whether a participant has accepted the share.
    public enum ParticipantAcceptanceStatus: Int, Sendable, Hashable {
        case unknown = 0, pending = 1, accepted = 2, removed = 3
    }

    /// Someone the share is for.
    open class Participant: @unchecked Sendable {
        open var permission: ParticipantPermission = .unknown
        open var role: ParticipantRole = .unknown
        open internal(set) var acceptanceStatus: ParticipantAcceptanceStatus = .unknown
        init() {}
    }

    /// What anyone with the link may do.
    open var publicPermission: ParticipantPermission = .none
    /// The link to the share (nil until it is saved: nothing saves here).
    open internal(set) var url: URL?
    open internal(set) var participants: [Participant] = []
    open internal(set) var owner: Participant = {
        let owner = Participant()
        owner.role = .owner
        owner.permission = .readWrite
        owner.acceptanceStatus = .accepted
        return owner
    }()
    open internal(set) var currentUserParticipant: Participant?

    /// A share of `rootRecord` and the records that name it as their parent.
    public init(rootRecord: CKRecord) {
        super.init(recordType: SystemType.share, recordID: CKRecord.ID(zoneID: rootRecord.recordID.zoneID))
    }
    public init(rootRecord: CKRecord, shareID: CKRecord.ID) {
        super.init(recordType: SystemType.share, recordID: shareID)
    }
    /// A share of every record in a zone.
    public init(recordZoneID: CKRecordZone.ID) {
        super.init(recordType: SystemType.share, recordID: CKRecord.ID(recordName: "cloudkit.zoneshare", zoneID: recordZoneID))
    }

    open func addParticipant(_ participant: Participant) { participants.append(participant) }
    open func removeParticipant(_ participant: Participant) { participants.removeAll { $0 === participant } }
}
