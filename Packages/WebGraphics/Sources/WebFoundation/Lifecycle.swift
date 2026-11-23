// Stand-ins for the Foundation types SwiftUI's lifecycle API names, which FoundationEssentials
// lacks on wasm: `Timer` (publishing through the frameworks' `Timer.publish`), `RunLoop` and its
// modes (accepted; the browser's loop is the only one), `NotificationCenter` with `Notification`
// and `Notification.Name`, and `NSUserActivity`. Linux also needs NSUserActivity; the other
// declarations remain Foundation's on native platforms.
#if os(WASI)

/// A timer: the frameworks' `Timer.publish(every:tolerance:on:in:)` schedules through tasks; a
/// scheduled timer runs its block on the main actor after its interval.
public final class Timer: _WebObjectBase, @unchecked Sendable {
    public let timeInterval: TimeInterval
    public let repeats: Bool
    private var task: Task<Void, Never>?
    /// What runs after each interval (nil for the frameworks' publishing timers).
    private var action: (@Sendable (Timer) -> Void)?
    private var scheduled = false
    public private(set) var isValid = true

    package init(timeInterval: TimeInterval, repeats: Bool) {
        self.timeInterval = timeInterval
        self.repeats = repeats
    }

    /// A timer that runs `block` after each interval once it is added to a run loop
    /// (`RunLoop.main.add(_:forMode:)`).
    public convenience init(timeInterval interval: TimeInterval, repeats: Bool, block: @escaping @Sendable (Timer) -> Void) {
        self.init(timeInterval: interval, repeats: repeats)
        action = block
    }

    @discardableResult
    public static func scheduledTimer(withTimeInterval interval: TimeInterval, repeats: Bool, block: @escaping @Sendable (Timer) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats, block: block)
        timer._schedule()
        return timer
    }

    /// Starts the timer's intervals, once: a scheduled timer, or one added to a run loop.
    func _schedule() {
        guard !scheduled, isValid, let action else { return }
        scheduled = true
        let interval = timeInterval, repeats = repeats
        task = Task { @MainActor in
            repeat {
                try? await Task.sleep(nanoseconds: UInt64(max(interval, 0.001) * 1_000_000_000))
                guard !Task.isCancelled, self.isValid else { return }
                action(self)
            } while repeats && self.isValid
            self.isValid = false
        }
    }

    /// Runs the timer's action now; a timer that doesn't repeat is then invalidated.
    public func fire() {
        guard isValid, let action else { return }
        action(self)
        if !repeats { invalidate() }
    }

    public func invalidate() {
        isValid = false
        task?.cancel()
        task = nil
    }

    #if canImport(ObjectiveC)
    /// What the timer was made with for its target (`userInfo`).
    public private(set) var userInfo: Any? {
        get { _userInfo?.value }
        set { _userInfo = _Box(newValue) }
    }
    private var _userInfo: _Box<Any?>?

    /// A timer that sends `aSelector` to `target` after each interval once it is added to a run
    /// loop, passing the timer when the selector takes an argument (`tick:`), as Foundation's
    /// target-action timer does. The timer holds the target until it is invalidated, as
    /// Foundation's does.
    public convenience init(timeInterval ti: TimeInterval, target aTarget: Any, selector aSelector: Selector,
                            userInfo: Any?, repeats yesOrNo: Bool) {
        let target = _Box(aTarget as AnyObject)
        self.init(timeInterval: ti, repeats: yesOrNo) { timer in
            _ = (target.value as? NSObject)?._send(aSelector, passing: timer)
        }
        self.userInfo = userInfo
    }

    /// The target-action timer, scheduled at once.
    @discardableResult
    public static func scheduledTimer(timeInterval ti: TimeInterval, target aTarget: Any, selector aSelector: Selector,
                                      userInfo: Any?, repeats yesOrNo: Bool) -> Timer {
        let timer = Timer(timeInterval: ti, target: aTarget, selector: aSelector, userInfo: userInfo, repeats: yesOrNo)
        timer._schedule()
        return timer
    }
    #endif
}

/// The run loop: the browser's event loop stands in for every mode.
public final class RunLoop: _WebObjectBase, @unchecked Sendable {
    public struct Mode: Hashable, Sendable, RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let `default` = Mode(rawValue: "default")
        public static let common = Mode(rawValue: "common")
    }
    public static let main = RunLoop()
    public static var current: RunLoop { main }

    /// Schedules `timer` (one made with an initialiser rather than `scheduledTimer`); every
    /// mode is the browser's loop, and a timer added twice runs once.
    public func add(_ timer: Timer, forMode mode: RunLoop.Mode) { timer._schedule() }
}

/// A notification: its name, an optional sender and user info.
public struct Notification: Hashable, @unchecked Sendable {
    public struct Name: Hashable, Sendable, RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
    }
    public let name: Name
    /// The sender: any value, as Foundation's is (RevenueCat posts a tuple of purchase results).
    public let object: Any?
    public let userInfo: [AnyHashable: Any]?

    public init(name: Name, object: Any? = nil, userInfo: [AnyHashable: Any]? = nil) {
        self.name = name
        self.object = object
        self.userInfo = userInfo
    }

    public static func == (lhs: Notification, rhs: Notification) -> Bool { lhs.name == rhs.name && lhs._sender === rhs._sender }
    /// The sender as an object, to compare by identity as Foundation's centre does.
    var _sender: AnyObject? { object.map { $0 as AnyObject } }
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }
}

public typealias NSNotification = Notification

#if canImport(ObjectiveC)
// With an Objective-C runtime (decision 0023) a notification bridges as itself in a value object
// (ObjectiveCBridging.swift), as Foundation's bridges to `NSNotification`, so the observer method
// a selector names can take it (`@objc func keyboardWillShow(_ notification: Notification)`).
extension Notification: _ObjectiveCBridgeable, _WebValueBridged { public typealias _ObjectiveCType = _WebNSValue }
#endif

/// A notification centre: observers keyed by name (and optionally sender), called on post.
public final class NotificationCenter: _WebObjectBase, @unchecked Sendable {
    public static let `default` = NotificationCenter()

    private struct Observer {
        let name: Notification.Name?
        weak var object: AnyObject?
        let filtersObject: Bool
        let block: @Sendable (Notification) -> Void
        /// The object a selector observer sends to (nil for a block observer).
        var owner: ObjectIdentifier? = nil
    }
    private var observers: [Int: Observer] = [:]
    private var nextID = 0

    public override init() {}

    /// Adds an observer (the queue is accepted; blocks run where `post` runs, which is the main
    /// thread, the only one here). Returns a token for `removeObserver`.
    @discardableResult
    public func addObserver(forName name: Notification.Name?, object: Any? = nil, queue: OperationQueue? = nil, using block: @escaping @Sendable (Notification) -> Void) -> any NSObjectProtocol {
        nextID += 1
        let id = nextID
        observers[id] = Observer(name: name, object: object.map { $0 as AnyObject }, filtersObject: object != nil, block: block)
        return NotificationToken(id: id)
    }

    public func removeObserver(_ token: Any) {
        if let token = token as? NotificationToken { observers[token.id] = nil; return }
        let owner = ObjectIdentifier(token as AnyObject)
        observers = observers.filter { $0.value.owner != owner }
    }

    /// Removes `observer`'s selector observations of `name` (every name when nil).
    public func removeObserver(_ observer: Any, name: Notification.Name?, object: Any?) {
        let owner = ObjectIdentifier(observer as AnyObject)
        observers = observers.filter { $0.value.owner != owner || (name != nil && $0.value.name != name) }
    }

    #if canImport(ObjectiveC)
    /// Sends `selector` to `observer` for each matching post while the observer lives. A
    /// selector with no argument (`synchronize`, `refresh`) is sent with none, one with an
    /// argument (`keyboardWillShow:`) with the notification, which bridges to Objective-C as
    /// Foundation's does (`_send(_:passing:)`).
    public func addObserver(_ observer: Any, selector: Selector, name: Notification.Name?, object: Any?) {
        let target = _WeakTarget(observer as AnyObject)
        nextID += 1
        observers[nextID] = Observer(name: name, object: object.map { $0 as AnyObject }, filtersObject: object != nil,
                                     block: { notification in
                                         _ = (target.object as? NSObject)?._send(selector, passing: notification._bridgeToObjectiveC())
                                     },
                                     owner: ObjectIdentifier(observer as AnyObject))
    }
    #endif

    public func post(_ notification: Notification) {
        for observer in observers.values {
            if let name = observer.name, name != notification.name { continue }
            if observer.filtersObject, observer.object !== notification._sender { continue }
            observer.block(notification)
        }
    }

    public func post(name: Notification.Name, object: Any? = nil, userInfo: [AnyHashable: Any]? = nil) {
        post(Notification(name: name, object: object, userInfo: userInfo))
    }
}

extension NotificationCenter {
    /// The notifications of one name posted after the sequence was made, in order, as an async
    /// sequence. The observation ends when iteration ends or the task is cancelled.
    public func notifications(named name: Notification.Name, object: AnyObject? = nil) -> Notifications {
        let (stream, continuation) = AsyncStream<Notification>.makeStream()
        let observation = _NotificationObservation(center: self)
        observation.token = addObserver(forName: name, object: object) { continuation.yield($0) }
        continuation.onTermination = { _ in observation.end() }
        return Notifications(stream: stream, observation: observation)
    }

    /// The notifications of one name, as an async sequence.
    public struct Notifications: AsyncSequence, Sendable {
        public typealias Element = Notification
        public typealias Failure = Never
        let stream: AsyncStream<Notification>
        let observation: _NotificationObservation

        /// Foundation's iterator steps without being mutated (`let iterator` works), so this one
        /// keeps the stream's iterator in a box.
        public struct AsyncIterator: AsyncIteratorProtocol {
            public typealias Element = Notification
            public typealias Failure = Never
            final class Box: @unchecked Sendable {
                var base: AsyncStream<Notification>.Iterator
                init(_ base: AsyncStream<Notification>.Iterator) { self.base = base }
            }
            let box: Box
            public func next() async -> Notification? { await box.base.next() }
            public func next(isolation actor: isolated (any Actor)?) async -> Notification? {
                await box.base.next(isolation: actor)
            }
        }
        public func makeAsyncIterator() -> AsyncIterator { AsyncIterator(box: .init(stream.makeAsyncIterator())) }
    }
}

/// The observer behind a `Notifications` sequence, removed when the sequence ends.
final class _NotificationObservation: @unchecked Sendable {
    weak var center: NotificationCenter?
    var token: (any NSObjectProtocol)?
    init(center: NotificationCenter) { self.center = center }
    func end() {
        if let token { center?.removeObserver(token) }
        token = nil
    }
}

/// A selector observer's target, held weakly.
final class _WeakTarget: @unchecked Sendable {
    weak var object: AnyObject?
    init(_ object: AnyObject) { self.object = object }
}

/// An observer token (`addObserver(forName:...)`'s return value), an `NSObjectProtocol` as
/// Foundation's is, so an app keeps it in an `(any NSObjectProtocol)?` (TCA's storage keys).
#if canImport(ObjectiveC)
public final class NotificationToken: NSObject {
    package let id: Int
    package init(id: Int) { self.id = id; super.init() }
}
#else
public final class NotificationToken: NSObjectProtocol {
    package let id: Int
    package init(id: Int) { self.id = id }
    public func isEqual(_ object: Any?) -> Bool { (object as? NotificationToken) === self }
    public var hash: Int { ObjectIdentifier(self).hashValue }
    public var description: String { "<NotificationToken: \(id)>" }
}
#endif

#endif

#if !canImport(Darwin)

/// The identifier an activity's saved copies are deleted by.
public typealias NSUserActivityPersistentIdentifier = String

/// A user activity: the type, title, user info and web page URL the app would continue, with
/// what it says about itself to search, Handoff and Siri. A page has none of those: the activity
/// keeps what the app sets, and a scene continues it when the app hands it back.
public final class NSUserActivity: @unchecked Sendable {
    public let activityType: String
    public var title: String?
    public var userInfo: [AnyHashable: Any]?
    public var webpageURL: URL?
    public var referrerURL: URL?
    public var expirationDate: Date?
    /// The search keywords.
    public var keywords: Set<String> = []
    /// The `userInfo` keys the activity needs to be continued.
    public var requiredUserInfoKeys: Set<String>?
    /// The identifier the app deletes the activity's saved copies by.
    public var persistentIdentifier: NSUserActivityPersistentIdentifier?
    /// The identifier that picks the scene that continues the activity.
    public var targetContentIdentifier: String?
    public var needsSave = false
    public var supportsContinuationStreams = false
    public var isEligibleForHandoff = true
    public var isEligibleForSearch = false
    public var isEligibleForPublicIndexing = false
    public var isEligibleForPrediction = false
    /// What other frameworks attach to the activity (CoreSpotlight's `contentAttributeSet`).
    public var _attached: [String: Any] = [:]

    public init(activityType: String) { self.activityType = activityType }
    public func becomeCurrent() {}
    public func resignCurrent() {}
    public func invalidate() {}

    /// Adds the entries to `userInfo`, replacing those with the same keys.
    public func addUserInfoEntries(from otherDictionary: [AnyHashable: Any]) {
        var info = userInfo ?? [:]
        for (key, value) in otherDictionary { info[key] = value }
        userInfo = info
    }

    /// Writes the payload's encoded keys into `userInfo`, as Apple's does, so
    /// `requiredUserInfoKeys` can name them and `typedPayload(_:)` reads them back.
    public func setTypedPayload<T: Encodable>(_ payload: T) throws {
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload))
        guard let entries = object as? [String: Any] else {
            throw EncodingError.invalidValue(payload, EncodingError.Context(codingPath: [],
                debugDescription: "A typed payload encodes as keyed values."))
        }
        var info: [AnyHashable: Any] = [:]
        for (key, value) in entries { info[key] = value }
        addUserInfoEntries(from: info)
    }

    /// Decodes the payload `setTypedPayload(_:)` wrote from `userInfo`'s string-keyed entries.
    public func typedPayload<T: Decodable>(_ type: T.Type) throws -> T {
        var entries: [String: Any] = [:]
        for (key, value) in userInfo ?? [:] {
            if let key = key as? String, JSONSerialization.isValidJSONObject([value]) { entries[key] = value }
        }
        return try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: entries))
    }

    /// Deletes the saved activities with these persistent identifiers (a page saves none).
    public class func deleteSavedUserActivities(withPersistentIdentifiers persistentIdentifiers: [NSUserActivityPersistentIdentifier],
                                                completionHandler handler: @escaping @Sendable () -> Void) { handler() }
    public class func deleteSavedUserActivities(withPersistentIdentifiers persistentIdentifiers: [NSUserActivityPersistentIdentifier]) async {}
    public class func deleteAllSavedUserActivities(completionHandler handler: @escaping @Sendable () -> Void) { handler() }
    public class func deleteAllSavedUserActivities() async {}
}

extension NSUserActivity: Hashable {
    public static func == (lhs: NSUserActivity, rhs: NSUserActivity) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
#endif
