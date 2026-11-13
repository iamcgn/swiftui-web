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
    public private(set) var isValid = true

    package init(timeInterval: TimeInterval, repeats: Bool) {
        self.timeInterval = timeInterval
        self.repeats = repeats
    }

    @discardableResult
    public static func scheduledTimer(withTimeInterval interval: TimeInterval, repeats: Bool, block: @escaping @Sendable (Timer) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats)
        timer.task = Task { @MainActor in
            repeat {
                try? await Task.sleep(nanoseconds: UInt64(max(interval, 0.001) * 1_000_000_000))
                guard !Task.isCancelled, timer.isValid else { return }
                block(timer)
            } while repeats && timer.isValid
            timer.isValid = false
        }
        return timer
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

    /// Sends `aSelector` to `target` after each interval, passing the timer when the selector
    /// takes an argument (`tick:`), as Foundation's target-action timer does. The timer holds
    /// the target until it is invalidated, as Foundation's does.
    @discardableResult
    public static func scheduledTimer(timeInterval ti: TimeInterval, target aTarget: Any, selector aSelector: Selector,
                                      userInfo: Any?, repeats yesOrNo: Bool) -> Timer {
        let target = _Box(aTarget as AnyObject)
        let timer = scheduledTimer(withTimeInterval: ti, repeats: yesOrNo) { timer in
            _ = (target.value as? NSObject)?._send(aSelector, passing: timer)
        }
        timer.userInfo = userInfo
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
}

/// A notification: its name, an optional sender and user info.
public struct Notification: Hashable, @unchecked Sendable {
    public struct Name: Hashable, Sendable, RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public init(_ rawValue: String) { self.rawValue = rawValue }
    }
    public let name: Name
    public let object: AnyObject?
    public let userInfo: [AnyHashable: Any]?

    public init(name: Name, object: AnyObject? = nil, userInfo: [AnyHashable: Any]? = nil) {
        self.name = name
        self.object = object
        self.userInfo = userInfo
    }

    public static func == (lhs: Notification, rhs: Notification) -> Bool { lhs.name == rhs.name && lhs.object === rhs.object }
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
    public func addObserver(forName name: Notification.Name?, object: AnyObject? = nil, queue: OperationQueue? = nil, using block: @escaping @Sendable (Notification) -> Void) -> any NSObjectProtocolToken {
        nextID += 1
        let id = nextID
        observers[id] = Observer(name: name, object: object, filtersObject: object != nil, block: block)
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
            if observer.filtersObject, observer.object !== notification.object { continue }
            observer.block(notification)
        }
    }

    public func post(name: Notification.Name, object: AnyObject? = nil, userInfo: [AnyHashable: Any]? = nil) {
        post(Notification(name: name, object: object, userInfo: userInfo))
    }
}

/// A selector observer's target, held weakly.
final class _WeakTarget: @unchecked Sendable {
    weak var object: AnyObject?
    init(_ object: AnyObject) { self.object = object }
}

/// An observer token (`addObserver(forName:...)`'s return value).
public protocol NSObjectProtocolToken: AnyObject {}
public final class NotificationToken: NSObjectProtocolToken {
    package let id: Int
    package init(id: Int) { self.id = id }
}

#endif

#if !canImport(Darwin)

/// A user activity: the type, title, user info and web page URL the app would continue.
public final class NSUserActivity: @unchecked Sendable {
    public let activityType: String
    public var title: String?
    public var userInfo: [AnyHashable: Any]?
    public var webpageURL: URL?
    public var isEligibleForHandoff = true

    public init(activityType: String) { self.activityType = activityType }
    public func becomeCurrent() {}
    public func resignCurrent() {}
    public func invalidate() {}
}
#endif
