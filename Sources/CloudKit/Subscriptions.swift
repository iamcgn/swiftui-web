// Subscriptions and the notifications they send. Saving a subscription fails like any other
// request (no iCloud account in the browser), and no push from CloudKit reaches a page, so a
// notification is never made from a remote notification's payload.
@_exported import WebFoundation
#if os(WASI)
import class WebCoreData.NSPredicate
#endif

/// A request for a push when records change.
open class CKSubscription: @unchecked Sendable {
    public typealias ID = String

    /// What a subscription watches.
    public enum SubscriptionType: Int, Sendable, Hashable {
        case query = 1
        case recordZone = 2
        case database = 3
    }

    /// What the push a subscription sends shows and carries.
    open class NotificationInfo: @unchecked Sendable {
        open var alertBody: String?
        open var alertLocalizationKey: String?
        open var alertLocalizationArgs: [CKRecord.FieldKey]?
        open var title: String?
        open var titleLocalizationKey: String?
        open var titleLocalizationArgs: [CKRecord.FieldKey]?
        open var subtitle: String?
        open var subtitleLocalizationKey: String?
        open var subtitleLocalizationArgs: [CKRecord.FieldKey]?
        open var alertActionLocalizationKey: String?
        open var alertLaunchImage: String?
        open var soundName: String?
        open var desiredKeys: [CKRecord.FieldKey]?
        open var shouldBadge = false
        open var shouldSendContentAvailable = false
        open var shouldSendMutableContent = false
        open var category: String?
        open var collapseIDKey: String?
        public init() {}
        public convenience init(alertBody: String? = nil, title: String? = nil, subtitle: String? = nil, soundName: String? = nil,
                                desiredKeys: [CKRecord.FieldKey]? = nil, shouldBadge: Bool = false,
                                shouldSendContentAvailable: Bool = false, shouldSendMutableContent: Bool = false, category: String? = nil) {
            self.init()
            self.alertBody = alertBody
            self.title = title
            self.subtitle = subtitle
            self.soundName = soundName
            self.desiredKeys = desiredKeys
            self.shouldBadge = shouldBadge
            self.shouldSendContentAvailable = shouldSendContentAvailable
            self.shouldSendMutableContent = shouldSendMutableContent
            self.category = category
        }
    }

    public let subscriptionID: ID
    public let subscriptionType: SubscriptionType
    open var notificationInfo: NotificationInfo?

    init(subscriptionID: ID, type: SubscriptionType) {
        self.subscriptionID = subscriptionID
        subscriptionType = type
    }
}

/// A subscription to the records that match a predicate.
open class CKQuerySubscription: CKSubscription, @unchecked Sendable {
    /// Which changes send a push.
    public struct Options: OptionSet, Hashable, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let firesOnRecordCreation = Options(rawValue: 1 << 0)
        public static let firesOnRecordUpdate = Options(rawValue: 1 << 1)
        public static let firesOnRecordDeletion = Options(rawValue: 1 << 2)
        public static let firesOnce = Options(rawValue: 1 << 3)
    }

    public let recordType: CKRecord.RecordType
    public let predicate: NSPredicate
    public let querySubscriptionOptions: Options
    open var zoneID: CKRecordZone.ID?

    public init(recordType: CKRecord.RecordType, predicate: NSPredicate, subscriptionID: CKSubscription.ID = UUID().uuidString, options: Options = []) {
        self.recordType = recordType
        self.predicate = predicate
        querySubscriptionOptions = options
        super.init(subscriptionID: subscriptionID, type: .query)
    }
}

/// A subscription to the changes in one zone.
open class CKRecordZoneSubscription: CKSubscription, @unchecked Sendable {
    public let zoneID: CKRecordZone.ID
    open var recordType: CKRecord.RecordType?

    public init(zoneID: CKRecordZone.ID, subscriptionID: CKSubscription.ID = UUID().uuidString) {
        self.zoneID = zoneID
        super.init(subscriptionID: subscriptionID, type: .recordZone)
    }
}

/// A subscription to the changes in a whole database.
open class CKDatabaseSubscription: CKSubscription, @unchecked Sendable {
    open var recordType: CKRecord.RecordType?

    public init(subscriptionID: CKSubscription.ID = UUID().uuidString) {
        super.init(subscriptionID: subscriptionID, type: .database)
    }
}

// MARK: - Notifications

/// A push a subscription sent.
open class CKNotification: @unchecked Sendable {
    public typealias ID = String

    /// What kind of subscription sent a push.
    public enum NotificationType: Int, Sendable, Hashable {
        case query = 1
        case recordZone = 2
        case readNotification = 3
        case database = 4
    }

    public let notificationType: NotificationType
    public let notificationID: ID?
    public let subscriptionID: CKSubscription.ID?
    public let containerIdentifier: String?
    public let isPruned: Bool
    public let alertBody: String?
    public let title: String?
    public let subtitle: String?
    public let badge: NSNumber?
    public let soundName: String?
    public let category: String?

    init(type: NotificationType) {
        notificationType = type
        notificationID = nil; subscriptionID = nil; containerIdentifier = nil; isPruned = false
        alertBody = nil; title = nil; subtitle = nil; badge = nil; soundName = nil; category = nil
    }

    /// The CloudKit notification a remote notification carries: none reach a page, so there is
    /// never one.
    public convenience init?(fromRemoteNotificationDictionary notificationDictionary: [AnyHashable: Any]) {
        return nil
    }
}

/// A push about the records a query subscription watches.
open class CKQueryNotification: CKNotification, @unchecked Sendable {
    /// What happened to the record.
    public enum Reason: Int, Sendable, Hashable {
        case recordCreated = 1
        case recordUpdated = 2
        case recordDeleted = 3
    }
    public let queryNotificationReason: Reason = .recordCreated
    public let recordFields: [CKRecord.FieldKey: Any]? = nil
    public let recordID: CKRecord.ID? = nil
    public let databaseScope: CKDatabase.Scope = .private
}

/// A push about the changes in a zone.
open class CKRecordZoneNotification: CKNotification, @unchecked Sendable {
    public let recordZoneID: CKRecordZone.ID? = nil
    public let databaseScope: CKDatabase.Scope = .private
}

/// A push about the changes in a database.
open class CKDatabaseNotification: CKNotification, @unchecked Sendable {
    public let databaseScope: CKDatabase.Scope = .private
}
