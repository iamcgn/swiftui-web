// EventKit on the web: a page cannot reach the person's calendars, so the event store answers
// every access request as a person who declined it would (not granted, no error) and reports the
// access as denied. The entity types are values an app fills and hands to the store, so the code
// that writes an event compiles and runs; saving without access throws, as it does on a device.
// Apple's frameworks re-export Foundation: a file importing only this module names Date.
@_exported import WebFoundation
#if os(WASI)
import WebCoreData   // NSPredicate, which Apple's Foundation declares
#endif
#if canImport(CoreGraphics) && !os(WASI)
import CoreGraphics
#else
import WebGraphics   // CGColor, a calendar's colour
#endif

/// The kinds of entity an event store holds.
public enum EKEntityType: UInt, Sendable {
    case event = 0
    case reminder = 1
}

/// Whether the app may reach the store's entities of a type.
public enum EKAuthorizationStatus: Int, Sendable {
    case notDetermined = 0
    case restricted = 1
    case denied = 2
    case fullAccess = 3
    case writeOnly = 4
    @available(*, deprecated, renamed: "fullAccess")
    public static var authorized: EKAuthorizationStatus { .fullAccess }
}

/// Which occurrences of a recurring event a change applies to.
public enum EKSpan: Int, Sendable {
    case thisEvent = 0
    case futureEvents = 1
}

/// The completion an access request calls: whether access was granted, and an error.
public typealias EKEventStoreRequestAccessCompletionHandler = @Sendable (Bool, (any Error)?) -> Void

/// The errors an event store throws.
public struct EKError: Error, Sendable, Equatable {
    public enum Code: Int, Sendable {
        case eventStoreNotAuthorized = 29
        case noCalendar = 1
    }
    public let code: Code
    public init(_ code: Code) { self.code = code }
    public static var eventStoreNotAuthorized: Code { .eventStoreNotAuthorized }
    public static var noCalendar: Code { .noCalendar }
}

/// The kinds of account a calendar lives in.
public enum EKSourceType: Int, Sendable {
    case local = 0, exchange, calDAV, mobileMe, subscribed, birthdays
}

/// The kinds of calendar.
public enum EKCalendarType: Int, Sendable {
    case local = 0, calDAV, exchange, subscription, birthday
}

/// An account that holds calendars (iCloud, Exchange, the device). A page reaches none, so the
/// store lists no sources; an app reads the source of a calendar it was given.
public final class EKSource: @unchecked Sendable {
    public let sourceIdentifier: String
    public let title: String
    public let sourceType: EKSourceType
    public var isDelegate: Bool { false }
    init(title: String, sourceType: EKSourceType) {
        self.title = title
        self.sourceType = sourceType
        sourceIdentifier = UUID().uuidString
    }
    /// The source's calendars of a type: none a page can reach.
    public func calendars(for entityType: EKEntityType) -> Set<EKCalendar> { [] }
}

/// A calendar: a named collection of events.
public final class EKCalendar: @unchecked Sendable, Hashable {
    public var title: String
    public let calendarIdentifier: String
    /// The entity type the calendar holds.
    public let allowedEntityTypes: EKEntityType
    /// The account the calendar lives in; a new calendar needs one before it can be saved.
    public var source: EKSource!
    /// The colour the calendar's events are drawn in.
    public var cgColor: CGColor!
    public var type: EKCalendarType { .local }
    public var allowsContentModifications: Bool { false }
    public var isSubscribed: Bool { false }
    public var isImmutable: Bool { false }

    init(title: String, entityType: EKEntityType = .event) {
        self.title = title
        allowedEntityTypes = entityType
        calendarIdentifier = UUID().uuidString
    }

    /// A new calendar for entities of a type in `eventStore`, in no source until one is set.
    public convenience init(for entityType: EKEntityType, eventStore: EKEventStore) {
        self.init(title: "", entityType: entityType)
    }

    public static func == (lhs: EKCalendar, rhs: EKCalendar) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// The base of events and reminders: what they have in common.
open class EKCalendarItem: @unchecked Sendable {
    public var calendar: EKCalendar!
    public var title: String! = ""
    public var location: String?
    public var notes: String?
    public var url: URL?
    public var calendarItemIdentifier: String { identifier }
    public var hasNotes: Bool { notes?.isEmpty == false }
    let identifier = UUID().uuidString
    init() {}
}

/// An event in a calendar.
public final class EKEvent: EKCalendarItem, @unchecked Sendable {
    public var startDate: Date!
    public var endDate: Date!
    public var isAllDay = false
    public var eventIdentifier: String! { identifier }
    public var timeZone: TimeZone?

    /// A new event for `eventStore`, in no calendar until one is set.
    public init(eventStore: EKEventStore) { super.init() }
}

/// The store of the person's calendars, which a page cannot reach.
open class EKEventStore: @unchecked Sendable {
    public init() {}

    /// The access the app has: denied, the answer the requests give.
    open class func authorizationStatus(for entityType: EKEntityType) -> EKAuthorizationStatus { .denied }

    /// Asks for access to read and write events: not granted.
    open func requestFullAccessToEvents(completion: @escaping EKEventStoreRequestAccessCompletionHandler) { completion(false, nil) }
    /// Asks for access to add events: not granted.
    open func requestWriteOnlyAccessToEvents(completion: @escaping EKEventStoreRequestAccessCompletionHandler) { completion(false, nil) }
    /// Asks for access to reminders: not granted.
    open func requestFullAccessToReminders(completion: @escaping EKEventStoreRequestAccessCompletionHandler) { completion(false, nil) }
    /// Asks for access to the entities of a type: not granted.
    open func requestAccess(to entityType: EKEntityType, completion: @escaping EKEventStoreRequestAccessCompletionHandler) { completion(false, nil) }

    open func requestFullAccessToEvents() async throws -> Bool { false }
    open func requestWriteOnlyAccessToEvents() async throws -> Bool { false }
    open func requestFullAccessToReminders() async throws -> Bool { false }
    open func requestAccess(to entityType: EKEntityType) async throws -> Bool { false }

    /// The calendar new events go to: none without access.
    open var defaultCalendarForNewEvents: EKCalendar? { nil }
    /// The calendars holding entities of a type: none without access.
    open func calendars(for entityType: EKEntityType) -> [EKCalendar] { [] }
    /// The calendar with this identifier: none without access.
    open func calendar(withIdentifier identifier: String) -> EKCalendar? { nil }
    /// The accounts holding calendars: none a page can reach.
    open var sources: [EKSource] { [] }
    /// The source with this identifier: none.
    open func source(withIdentifier identifier: String) -> EKSource? { nil }

    /// Saves a calendar: without access it throws, as the store does on a device.
    open func saveCalendar(_ calendar: EKCalendar, commit: Bool) throws { throw EKError(.eventStoreNotAuthorized) }
    /// Removes a calendar: without access it throws.
    open func removeCalendar(_ calendar: EKCalendar, commit: Bool) throws { throw EKError(.eventStoreNotAuthorized) }

    /// Saves an event: without access it throws, as the store does on a device.
    open func save(_ event: EKEvent, span: EKSpan) throws { throw EKError(.eventStoreNotAuthorized) }
    open func save(_ event: EKEvent, span: EKSpan, commit: Bool) throws { throw EKError(.eventStoreNotAuthorized) }
    /// Removes an event: without access it throws.
    open func remove(_ event: EKEvent, span: EKSpan) throws { throw EKError(.eventStoreNotAuthorized) }
    open func remove(_ event: EKEvent, span: EKSpan, commit: Bool) throws { throw EKError(.eventStoreNotAuthorized) }
    /// Writes pending changes: there are none.
    open func commit() throws {}

    /// The event with this identifier: none without access.
    open func event(withIdentifier identifier: String) -> EKEvent? { nil }

    /// A query for the events between two dates in some calendars (all of them when nil). The
    /// store holds none without access, so the query matches nothing.
    open func predicateForEvents(withStart startDate: Date, end endDate: Date, calendars: [EKCalendar]?) -> NSPredicate {
        NSPredicate(value: false)
    }
    /// The events a query matches: none without access, as a device answers a denied app.
    open func events(matching predicate: NSPredicate) -> [EKEvent] { [] }
    /// Calls `block` for each event a query matches: never without access.
    open func enumerateEvents(matching predicate: NSPredicate, using block: (EKEvent, UnsafeMutablePointer<ObjCBool>) -> Void) {}
}
