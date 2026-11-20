// Key-value observing for wasm, where there is no Objective-C runtime to swap an object's setters
// for notifying ones. `observe(_:options:changeHandler:)` reports a change two ways:
//   - an observable object (`@Observable`, as wasm's `Progress` is) reports its own sets through
//     Observation; the handler runs on the next turn of the main actor, once the new value is in
//     place (Foundation's runs inside the setter);
//   - any object can report one by hand with `willChangeValue(for:)` / `didChangeValue(for:)`,
//     or `…(forKey:)`, which reaches every observation of that object, as a key can't be matched
//     to a key path without the runtime.
// A plain stored property of a plain class reports nothing: `@objc dynamic` has no meaning here.
// `.initial` reports at once, `.prior` before the change, `.old` and `.new` fill the change.
#if os(WASI)
import Observation

public struct NSKeyValueObservingOptions: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let new = NSKeyValueObservingOptions(rawValue: 1 << 0)
    public static let old = NSKeyValueObservingOptions(rawValue: 1 << 1)
    public static let initial = NSKeyValueObservingOptions(rawValue: 1 << 2)
    public static let prior = NSKeyValueObservingOptions(rawValue: 1 << 3)
}

public enum NSKeyValueChange: UInt, Sendable {
    case setting = 1, insertion, removal, replacement
}

public enum NSKeyValueSetMutationKind: UInt, Sendable {
    case union = 1, minus, intersect, set
}

#if canImport(ObjectiveC)
// Without the runtime it is SwiftFoundation's, beside NSObject, whose `observeValue` takes it.
public struct NSKeyValueChangeKey: Hashable, RawRepresentable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public static let kindKey = NSKeyValueChangeKey("kind")
    public static let newKey = NSKeyValueChangeKey("new")
    public static let oldKey = NSKeyValueChangeKey("old")
    public static let indexesKey = NSKeyValueChangeKey("indexes")
    public static let notificationIsPriorKey = NSKeyValueChangeKey("notificationIsPrior")
}
#endif

/// One change an observation reports.
public struct NSKeyValueObservedChange<Value> {
    public typealias Kind = NSKeyValueChange
    public let kind: Kind
    /// The value after the change, when the observation asked for `.new` (nil on a prior report).
    public let newValue: Value?
    /// The value before the change, when the observation asked for `.old`.
    public let oldValue: Value?
    /// The indexes inserted, removed or replaced in a to-many property; nil for a setting.
    public let indexes: IndexSet?
    /// Whether this is the report before the change (`.prior`).
    public let isPrior: Bool
}

/// An observation `observe(_:options:changeHandler:)` returns. It reports until it's invalidated
/// or released, as Foundation's does.
public final class NSKeyValueObservation: Hashable, @unchecked Sendable {
    fileprivate let object: ObjectIdentifier
    fileprivate let keyPath: AnyKeyPath
    /// Reports a change: before it (`true`) or after it (`false`).
    fileprivate var report: ((_ prior: Bool) -> Void)?
    /// Re-reads the key path inside Observation's tracking, so the next set reports.
    fileprivate var track: (() -> Void)?
    fileprivate var awaitingSet = false

    fileprivate init(object: ObjectIdentifier, keyPath: AnyKeyPath) {
        self.object = object
        self.keyPath = keyPath
    }

    public func invalidate() {
        report = nil
        track = nil
        _KeyValueObservers.remove(self)
    }

    deinit { invalidate() }

    // Hashable by identity, as Foundation's (an NSObject) is: packages keep them in sets.
    public static func == (lhs: NSKeyValueObservation, rhs: NSKeyValueObservation) -> Bool { lhs === rhs }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

    /// Observation's report of a set: the prior report now, the change once the set is done.
    fileprivate func observedWillSet() {
        guard report != nil, !awaitingSet else { return }
        awaitingSet = true
        report?(true)
        let handle = _WeakObservation(self)
        Task { @MainActor in
            guard let observation = handle.value else { return }
            observation.awaitingSet = false
            observation.report?(false)
            observation.track?()
        }
    }
}

/// A weak hold on an observation that can cross into Observation's and a task's closures.
private final class _WeakObservation: @unchecked Sendable {
    weak var value: NSKeyValueObservation?
    init(_ value: NSKeyValueObservation) { self.value = value }
}

/// The live observations of each object, for the hand-made reports.
enum _KeyValueObservers {
    nonisolated(unsafe) private static var byObject: [ObjectIdentifier: [_WeakObservation]] = [:]

    fileprivate static func add(_ observation: NSKeyValueObservation) {
        byObject[observation.object, default: []].append(_WeakObservation(observation))
    }

    fileprivate static func remove(_ observation: NSKeyValueObservation) {
        guard var list = byObject[observation.object] else { return }
        list.removeAll { $0.value == nil || $0.value === observation }
        byObject[observation.object] = list.isEmpty ? nil : list
    }

    static func report(_ object: AnyObject, keyPath: AnyKeyPath?, prior: Bool) {
        for entry in byObject[ObjectIdentifier(object)] ?? [] {
            guard let observation = entry.value, keyPath == nil || observation.keyPath == keyPath else { continue }
            observation.report?(prior)
        }
    }
}

/// Foundation's protocol for objects that can be observed by key path; `NSObject` and wasm's
/// `Progress` conform.
public protocol _KeyValueCodingAndObserving: AnyObject {}

extension _KeyValueCodingAndObserving {
    /// Calls `changeHandler` when the value at `keyPath` changes (see the file's notes for what
    /// reports a change here).
    public func observe<Value>(
        _ keyPath: KeyPath<Self, Value>,
        options: NSKeyValueObservingOptions = [],
        changeHandler: @escaping (Self, NSKeyValueObservedChange<Value>) -> Void
    ) -> NSKeyValueObservation {
        let observation = NSKeyValueObservation(object: ObjectIdentifier(self), keyPath: keyPath)
        var old: Value?
        observation.report = { [weak self] prior in
            guard let self else { return }
            let current = self[keyPath: keyPath]
            if prior {
                old = options.contains(.old) ? current : nil
                if options.contains(.prior) {
                    changeHandler(self, NSKeyValueObservedChange(kind: .setting, newValue: nil, oldValue: old, indexes: nil, isPrior: true))
                }
            } else {
                changeHandler(self, NSKeyValueObservedChange(kind: .setting, newValue: options.contains(.new) ? current : nil,
                                                             oldValue: old, indexes: nil, isPrior: false))
                old = nil
            }
        }
        let handle = _WeakObservation(observation)
        observation.track = { [weak self] in
            guard let self else { return }
            withObservationTracking {
                _ = self[keyPath: keyPath]
            } onChange: {
                handle.value?.observedWillSet()
            }
        }
        _KeyValueObservers.add(observation)
        if options.contains(.initial) {
            changeHandler(self, NSKeyValueObservedChange(kind: .setting, newValue: options.contains(.new) ? self[keyPath: keyPath] : nil,
                                                         oldValue: nil, indexes: nil, isPrior: false))
        }
        observation.track?()
        return observation
    }

    /// Reports to this object's observations of `keyPath` that its value is about to change.
    public func willChangeValue<Value>(for keyPath: KeyPath<Self, Value>) {
        _KeyValueObservers.report(self, keyPath: keyPath, prior: true)
    }

    /// Reports to this object's observations of `keyPath` that its value changed.
    public func didChangeValue<Value>(for keyPath: KeyPath<Self, Value>) {
        _KeyValueObservers.report(self, keyPath: keyPath, prior: false)
    }

    /// Reports to every observation of this object that the value for `key` is about to change,
    /// and to the observers added for `key`.
    public func willChangeValue(forKey key: String) {
        _KeyValueObservers.report(self, keyPath: nil, prior: true)
        _KeyPathObservers.report(self, key: key, prior: true)
    }

    /// Reports to every observation of this object that the value for `key` changed, and to the
    /// observers added for `key`.
    public func didChangeValue(forKey key: String) {
        _KeyValueObservers.report(self, keyPath: nil, prior: false)
        _KeyPathObservers.report(self, key: key, prior: false)
    }

    /// Has `observer` sent `observeValue(forKeyPath:of:change:context:)` when this object's value
    /// for `keyPath` changes: a change reported with `willChangeValue(forKey:)` and
    /// `didChangeValue(forKey:)`, or one of `UserDefaults`' sets. The observer is held weakly,
    /// and `context` is handed back as it was given.
    public func addObserver(_ observer: NSObject, forKeyPath keyPath: String,
                            options: NSKeyValueObservingOptions = [], context: UnsafeMutableRawPointer?) {
        _KeyPathObservers.add(self, observer: observer, key: keyPath, options: options, context: context)
        if options.contains(.initial) {
            _KeyPathObservers.send(to: observer, key: keyPath, of: self, options: options, context: context,
                                   old: nil, new: _KeyPathObservers.value(of: self, forKey: keyPath), prior: false)
        }
    }

    /// Stops sending `observer` changes to `keyPath`, every registration of it.
    public func removeObserver(_ observer: NSObject, forKeyPath keyPath: String) {
        _KeyPathObservers.remove(self, observer: observer, key: keyPath, context: nil, anyContext: true)
    }

    /// Stops sending `observer` changes to `keyPath` for the registration with `context`.
    public func removeObserver(_ observer: NSObject, forKeyPath keyPath: String, context: UnsafeMutableRawPointer?) {
        _KeyPathObservers.remove(self, observer: observer, key: keyPath, context: context, anyContext: false)
    }
}

extension NSObject: _KeyValueCodingAndObserving {}

// MARK: - Observers by key (`addObserver(_:forKeyPath:options:context:)`)

/// An object that can give its value for a key, for a change's `.old` and `.new` entries
/// (`UserDefaults`, its stored values). Any other object's change carries neither.
protocol _KeyValueReading: AnyObject {
    func _observedValue(forKey key: String) -> Any?
}

/// The observers added to each object by key, and the old values held between a change's two
/// reports.
enum _KeyPathObservers {
    private struct Entry {
        weak var observer: NSObject?
        let key: String
        let options: NSKeyValueObservingOptions
        let context: UnsafeMutableRawPointer?
    }
    nonisolated(unsafe) private static var byObject: [ObjectIdentifier: [Entry]] = [:]
    /// A value held between a change's two reports (a box, as the value itself may be nil).
    private struct OldValue { let value: Any? }
    nonisolated(unsafe) private static var oldValues: [ObjectIdentifier: [String: OldValue]] = [:]

    static func add(_ object: AnyObject, observer: NSObject, key: String,
                    options: NSKeyValueObservingOptions, context: UnsafeMutableRawPointer?) {
        byObject[ObjectIdentifier(object), default: []].append(Entry(observer: observer, key: key, options: options, context: context))
    }

    static func remove(_ object: AnyObject, observer: NSObject, key: String,
                       context: UnsafeMutableRawPointer?, anyContext: Bool) {
        let id = ObjectIdentifier(object)
        guard var list = byObject[id] else { return }
        list.removeAll { entry in
            entry.observer == nil || (entry.observer === observer && entry.key == key && (anyContext || entry.context == context))
        }
        byObject[id] = list.isEmpty ? nil : list
    }

    /// Whether any live observer watches `key` of `object`.
    static func isObserved(_ object: AnyObject, key: String) -> Bool {
        byObject[ObjectIdentifier(object)]?.contains { $0.key == key && $0.observer != nil } ?? false
    }

    static func value(of object: AnyObject, forKey key: String) -> Any? {
        (object as? any _KeyValueReading)?._observedValue(forKey: key)
    }

    /// Sends the change to every observer of `key`: before it (`prior`), to those that asked for
    /// `.prior`, keeping the old value; after it, to all, with the old and new values they asked for.
    static func report(_ object: AnyObject, key: String, prior: Bool) {
        let id = ObjectIdentifier(object)
        guard let list = byObject[id], list.contains(where: { $0.key == key }) else { return }
        let entries = list.filter { $0.key == key && $0.observer != nil }
        if prior {
            let old = value(of: object, forKey: key)
            oldValues[id, default: [:]][key] = OldValue(value: old)
            for entry in entries where entry.options.contains(.prior) {
                guard let observer = entry.observer else { continue }
                send(to: observer, key: key, of: object, options: entry.options, context: entry.context, old: old, new: nil, prior: true)
            }
        } else {
            let old = oldValues[id]?.removeValue(forKey: key)?.value
            if oldValues[id]?.isEmpty == true { oldValues[id] = nil }
            let new = value(of: object, forKey: key)
            for entry in entries {
                guard let observer = entry.observer else { continue }
                send(to: observer, key: key, of: object, options: entry.options, context: entry.context, old: old, new: new, prior: false)
            }
        }
    }

    /// The change dictionary as Foundation's: the kind, `.old` and `.new` when asked for (`NSNull`
    /// for a missing value), and the prior flag on the report before the change.
    static func send(to observer: NSObject, key: String, of object: AnyObject, options: NSKeyValueObservingOptions,
                     context: UnsafeMutableRawPointer?, old: Any?, new: Any?, prior: Bool) {
        var change: [NSKeyValueChangeKey: Any] = [.kindKey: NSKeyValueChange.setting.rawValue]
        if options.contains(.old) { change[.oldKey] = old ?? NSNull() }
        if options.contains(.new) && !prior { change[.newKey] = new ?? NSNull() }
        if prior { change[.notificationIsPriorKey] = true }
        observer.observeValue(forKeyPath: key, of: object, change: change, context: context)
    }
}

#if canImport(ObjectiveC)
extension NSObject {
    /// Called when a value this object observes by key changes (`addObserver(_:forKeyPath:…)`);
    /// subclasses override it. It does nothing here, as Foundation's raises for an observer that
    /// doesn't.
    @objc open func observeValue(forKeyPath keyPath: String?, of object: Any?,
                                 change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {}
}

/// The change keys cross an `@objc` member as strings, as Foundation's string-backed keys do.
extension NSKeyValueChangeKey: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSString
    public func _bridgeToObjectiveC() -> NSString { NSString(string: rawValue) }
    public static func _forceBridgeFromObjectiveC(_ source: NSString, result: inout NSKeyValueChangeKey?) {
        result = NSKeyValueChangeKey(source.string)
    }
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSString, result: inout NSKeyValueChangeKey?) -> Bool {
        result = NSKeyValueChangeKey(source.string)
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSString?) -> NSKeyValueChangeKey {
        NSKeyValueChangeKey(source?.string ?? "")
    }
}
#else
extension UserDefaults: _KeyValueCodingAndObserving {}
#endif

extension UserDefaults: _KeyValueReading {
    func _observedValue(forKey key: String) -> Any? { object(forKey: key) }
}
#endif
