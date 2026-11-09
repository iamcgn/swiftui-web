// EventKit on the web: a page cannot reach the person's calendars, so the event store answers
// every access request as a person who declined it would (not granted, no error) and reports the
// access as denied. The entity types are values an app fills and hands to the store, so the code
// that writes an event compiles and runs; saving without access throws, as it does on a device.
// Apple's frameworks re-export Foundation: a file importing only this module names Date.
@_exported import WebFoundation

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

/// A calendar: a named collection of events.
public final class EKCalendar: @unchecked Sendable {
    public var title: String
    public let calendarIdentifier: String
    public var allowsContentModifications: Bool { false }
    init(title: String) { self.title = title; calendarIdentifier = UUID().uuidString }
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
}
