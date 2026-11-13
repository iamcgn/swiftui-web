// ActivityKit on the web: a Live Activity lives on the Lock Screen and in the Dynamic Island, and
// a browser has neither, so the page is a device without Live Activities, as an iPad is. The
// person's settings read as activities not enabled, a request throws `unsupported`, and the app's
// list of activities stays empty; the update streams never yield. The attribute and content types
// are values an app declares and fills, so the code that starts, updates and ends an activity
// compiles and runs the path it takes on such a device.
// Apple's frameworks re-export Foundation: a file importing only this module names Date.
@_exported import WebFoundation

// MARK: - Attributes and content

/// The data a Live Activity shows: what stays fixed (the conforming type's properties) and what
/// changes (`ContentState`).
public protocol ActivityAttributes: Decodable, Encodable {
    /// The activity's dynamic data.
    associatedtype ContentState: Decodable, Encodable, Hashable
}

/// An activity's dynamic data and when it goes stale.
public struct ActivityContent<State>: Equatable, Hashable where State: Decodable, State: Encodable, State: Hashable {
    public var state: State
    /// When the system marks the activity as out of date.
    public var staleDate: Date?
    /// Which of an app's activities the system shows first (higher first).
    public var relevanceScore: Double

    public init(state: State, staleDate: Date?, relevanceScore: Double = 0) {
        self.state = state
        self.staleDate = staleDate
        self.relevanceScore = relevanceScore
    }
}

extension ActivityContent: Sendable where State: Sendable {}

/// Where an activity is in its life.
public enum ActivityState: Equatable, Hashable, Codable, Sendable {
    /// Waiting for its start date.
    case pending
    /// Showing and taking updates.
    case active
    /// Ended, still on the Lock Screen until its dismissal policy removes it.
    case ended
    /// Gone from the Lock Screen.
    case dismissed
    /// Past its stale date.
    case stale
}

/// How long an ended activity stays on the Lock Screen.
public struct ActivityUIDismissalPolicy: Hashable, Sendable {
    enum Kind: Hashable, Sendable { case standard, immediate, after(Date) }
    let kind: Kind
    /// Up to four hours after it ends.
    public static let `default` = ActivityUIDismissalPolicy(kind: .standard)
    /// Right away.
    public static let immediate = ActivityUIDismissalPolicy(kind: .immediate)
    /// At a date (no more than four hours after it ends).
    public static func after(_ date: Date) -> ActivityUIDismissalPolicy { ActivityUIDismissalPolicy(kind: .after(date)) }
}

/// How the activity is updated by push notifications.
public struct PushType: Hashable, Sendable {
    enum Kind: Hashable, Sendable { case token, channel(String) }
    let kind: Kind
    /// Through a push token the activity's `pushTokenUpdates` deliver.
    public static let token = PushType(kind: .token)
    /// Through a broadcast channel.
    public static func channel(_ channelId: String) -> PushType { PushType(kind: .channel(channelId)) }
}

/// How an activity presents: until it is ended, or briefly.
public enum ActivityStyle: Hashable, Sendable {
    case standard
    case transient
}

/// An alert that lights up the screen when an activity is updated.
public struct AlertConfiguration {
    /// The sound the alert plays.
    public struct AlertSound: Hashable, Sendable {
        let name: String?
        /// The system's sound.
        public static let `default` = AlertSound(name: nil)
        /// A sound file in the app's bundle.
        public static func named(_ name: String) -> AlertSound { AlertSound(name: name) }
    }
    public var title: LocalizedStringResource
    public var body: LocalizedStringResource
    public var sound: AlertSound

    public init(title: LocalizedStringResource, body: LocalizedStringResource, sound: AlertSound) {
        self.title = title
        self.body = body
        self.sound = sound
    }
}

// MARK: - Authorization

/// Why a request for an activity failed.
public enum ActivityAuthorizationError: Error, Equatable, Hashable, Sendable, LocalizedError {
    case attributesTooLarge
    case denied
    case globalMaximumExceeded
    case malformedActivityIdentifier
    case missingProcessIdentifier
    case persistenceFailure
    case reconnectNotPermitted
    case targetMaximumExceeded
    case unentitled
    case unsupported
    case unsupportedTarget
    case visibility

    public var errorDescription: String? {
        switch self {
        case .attributesTooLarge: "The activity's attributes are too large."
        case .denied: "Live Activities are turned off for this app."
        case .globalMaximumExceeded: "The device has too many activities."
        case .malformedActivityIdentifier: "The activity identifier is malformed."
        case .missingProcessIdentifier: "The process has no identifier."
        case .persistenceFailure: "The activity could not be saved."
        case .reconnectNotPermitted: "The process may not reconnect to the activity."
        case .targetMaximumExceeded: "The app has too many activities."
        case .unentitled: "The app is not entitled to start activities."
        case .unsupported: "This device does not support Live Activities."
        case .unsupportedTarget: "The target does not support Live Activities."
        case .visibility: "The app must be in the foreground to start an activity."
        }
    }
}

/// Whether the person lets the app start Live Activities. A page has nowhere to show one, so
/// neither is enabled and neither changes.
public struct ActivityAuthorizationInfo: Sendable {
    public typealias ActivityEnablementUpdates = AsyncStream<Bool>
    public typealias FrequentPushEnablementUpdates = AsyncStream<Bool>

    public init() {}
    /// Whether the app may start activities: never in a browser.
    public var areActivitiesEnabled: Bool { false }
    /// Whether the activities may be updated often: never in a browser.
    public var frequentPushesEnabled: Bool { false }
    /// The changes of `areActivitiesEnabled` (none).
    public var activityEnablementUpdates: ActivityEnablementUpdates { _quietStream() }
    /// The changes of `frequentPushesEnabled` (none).
    public var frequentPushEnablementUpdates: FrequentPushEnablementUpdates { _quietStream() }
}

/// A stream with nothing to deliver: a loop over it waits, as it does on a device where nothing
/// changes, until its task is cancelled.
func _quietStream<Element>() -> AsyncStream<Element> { AsyncStream { _ in } }

// MARK: - Activity

/// A Live Activity an app started. A page cannot start one (`request` throws `unsupported`), so an
/// app never holds one; the members read as an ended activity's would.
public final class Activity<Attributes: ActivityAttributes>: Identifiable, @unchecked Sendable {
    public typealias ContentUpdates = AsyncStream<ActivityContent<Attributes.ContentState>>
    public typealias ActivityStateUpdates = AsyncStream<ActivityState>
    public typealias PushTokenUpdates = AsyncStream<Data>
    public typealias ActivityUpdates = AsyncStream<Activity<Attributes>>
    public typealias PushToStartTokenUpdates = AsyncStream<Data>

    public let id: String
    public let attributes: Attributes
    public private(set) var content: ActivityContent<Attributes.ContentState>
    public private(set) var activityState: ActivityState
    /// The token the activity's pushes are addressed to (never issued: a page receives no pushes).
    public var pushToken: Data? { nil }
    public var activityStyle: ActivityStyle { .standard }

    init(attributes: Attributes, content: ActivityContent<Attributes.ContentState>) {
        id = UUID().uuidString
        self.attributes = attributes
        self.content = content
        activityState = .ended
    }

    @available(*, deprecated, message: "Use content.state instead.")
    public var contentState: Attributes.ContentState { content.state }

    public var contentUpdates: ContentUpdates { _quietStream() }
    public var activityStateUpdates: ActivityStateUpdates { _quietStream() }
    public var pushTokenUpdates: PushTokenUpdates { _quietStream() }

    /// The app's activities of this type: none.
    public static var activities: [Activity<Attributes>] { [] }
    /// Activities started for the app by push (none).
    public static var activityUpdates: ActivityUpdates { _quietStream() }
    public static var pushToStartToken: Data? { nil }
    public static var pushToStartTokenUpdates: PushToStartTokenUpdates { _quietStream() }

    /// Starts an activity: throws `unsupported`, as on a device without Live Activities.
    public static func request(attributes: Attributes, content: ActivityContent<Attributes.ContentState>, pushType: PushType? = nil) throws -> Activity<Attributes> {
        throw ActivityAuthorizationError.unsupported
    }
    public static func request(attributes: Attributes, content: ActivityContent<Attributes.ContentState>, pushType: PushType? = nil, style: ActivityStyle) throws -> Activity<Attributes> {
        throw ActivityAuthorizationError.unsupported
    }
    @available(*, deprecated, message: "Use request(attributes:content:pushType:) instead.")
    public static func request(attributes: Attributes, contentState: Attributes.ContentState, pushType: PushType? = nil) throws -> Activity<Attributes> {
        throw ActivityAuthorizationError.unsupported
    }

    public func update(_ content: ActivityContent<Attributes.ContentState>) async {
        guard activityState == .active || activityState == .stale else { return }
        self.content = content
    }
    public func update(_ content: ActivityContent<Attributes.ContentState>, alertConfiguration: AlertConfiguration?) async {
        await update(content)
    }
    public func update(_ content: ActivityContent<Attributes.ContentState>, alertConfiguration: AlertConfiguration?, timestamp: Date) async {
        await update(content)
    }
    @available(*, deprecated, message: "Use update(_:) instead.")
    public func update(using contentState: Attributes.ContentState) async {
        await update(ActivityContent(state: contentState, staleDate: nil))
    }
    @available(*, deprecated, message: "Use update(_:alertConfiguration:) instead.")
    public func update(using contentState: Attributes.ContentState, alertConfiguration: AlertConfiguration?) async {
        await update(ActivityContent(state: contentState, staleDate: nil))
    }

    public func end(_ content: ActivityContent<Attributes.ContentState>?, dismissalPolicy: ActivityUIDismissalPolicy = .default) async {
        if let content { self.content = content }
        activityState = dismissalPolicy == .immediate ? .dismissed : .ended
    }
    public func end(_ content: ActivityContent<Attributes.ContentState>?, dismissalPolicy: ActivityUIDismissalPolicy = .default, timestamp: Date) async {
        await end(content, dismissalPolicy: dismissalPolicy)
    }
    @available(*, deprecated, message: "Use end(_:dismissalPolicy:) instead.")
    public func end(using contentState: Attributes.ContentState? = nil, dismissalPolicy: ActivityUIDismissalPolicy = .default) async {
        await end(contentState.map { ActivityContent(state: $0, staleDate: nil) }, dismissalPolicy: dismissalPolicy)
    }
}
