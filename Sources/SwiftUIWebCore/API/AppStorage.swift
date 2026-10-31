// `@AppStorage` (the everyday API batch; Docs/coverage.md ranks it first, 7 of 32 apps): a
// property that reads and writes one `UserDefaults` key. Reads go to the defaults every time,
// so the value is whatever was last stored, by this property, another one or plain
// `UserDefaults` code; a write through any `@AppStorage` of the same store and key invalidates
// every view that installed one (Apple's observes the defaults by key-value observing, which
// also catches writes made with `UserDefaults.set`; here those show at the view's next update).
// The store is the property's own, else the one `defaultAppStorage(_:)` set above the view,
// else `UserDefaults.standard`: on wasm WebFoundation's, which the browser host keeps in
// localStorage (decision 0021).
import WebFoundation

/// A property wrapper type that reflects a value from `UserDefaults` and invalidates a view on
/// a change in value in that user default.
@propertyWrapper
public struct AppStorage<Value>: DynamicProperty {
    package let key: String
    package let store: UserDefaults?
    package let defaultValue: Value
    private let read: (UserDefaults, String) -> Value?
    private let write: (UserDefaults, String, Value) -> Void
    package var box: _AppStorageBox?

    package init(key: String, store: UserDefaults?, defaultValue: Value,
                 read: @escaping (UserDefaults, String) -> Value?, write: @escaping (UserDefaults, String, Value) -> Void) {
        self.key = key
        self.store = store
        self.defaultValue = defaultValue
        self.read = read
        self.write = write
    }

    /// The defaults this property reads: its own store, the environment's, or the standard ones.
    private var defaults: UserDefaults { store ?? box?.environmentStore ?? .standard }

    /// The value stored under the key, or the default value when nothing is.
    public var wrappedValue: Value {
        get { read(defaults, key) ?? defaultValue }
        nonmutating set {
            let defaults = self.defaults
            write(defaults, key, newValue)
            _AppStorageRegistry.didChange(ObjectIdentifier(defaults), key)
        }
    }

    /// A binding to the stored value.
    public var projectedValue: Binding<Value> {
        let current = self
        return Binding(get: { current.wrappedValue }, set: { current.wrappedValue = $0 })
    }

    @MainActor
    public mutating func _install(in node: ViewNode, slot: inout AnyObject?) {
        let box = (slot as? _AppStorageBox) ?? _AppStorageBox(node: node)
        slot = box
        box.environmentStore = node.environment.defaultAppStorage
        box.watch(ObjectIdentifier(store ?? box.environmentStore ?? .standard), key)
        self.box = box
    }
}

/// One installed `@AppStorage`: the node to invalidate and the store and key it watches.
package final class _AppStorageBox: @unchecked Sendable {
    nonisolated(unsafe) package private(set) weak var node: ViewNode?
    nonisolated(unsafe) package var environmentStore: UserDefaults?
    nonisolated(unsafe) private var watched: _AppStorageRegistry.Entry?

    @MainActor
    package init(node: ViewNode) { self.node = node }

    @MainActor
    package func watch(_ store: ObjectIdentifier, _ key: String) {
        let entry = _AppStorageRegistry.Entry(store: store, key: key)
        guard entry != watched else { return }
        if let watched { _AppStorageRegistry.remove(self, from: watched) }
        watched = entry
        _AppStorageRegistry.add(self, to: entry)
    }

    deinit {
        if let watched { _AppStorageRegistry.remove(self, from: watched) }
    }
}

/// The installed `@AppStorage` boxes by store and key. Views install and write on the main
/// actor (as SwiftUI requires); the table itself is only touched there.
package enum _AppStorageRegistry {
    package struct Entry: Hashable {
        let store: ObjectIdentifier
        let key: String
    }

    private struct Weak { weak var box: _AppStorageBox? }
    nonisolated(unsafe) private static var boxes: [Entry: [ObjectIdentifier: Weak]] = [:]

    static func add(_ box: _AppStorageBox, to entry: Entry) {
        boxes[entry, default: [:]][ObjectIdentifier(box)] = Weak(box: box)
    }

    static func remove(_ box: _AppStorageBox, from entry: Entry) {
        boxes[entry]?[ObjectIdentifier(box)] = nil
        if boxes[entry]?.isEmpty == true { boxes[entry] = nil }
    }

    /// A write through an `@AppStorage`: every view watching the same store and key updates.
    package static func didChange(_ store: ObjectIdentifier, _ key: String) {
        guard let watching = boxes[Entry(store: store, key: key)], !watching.isEmpty else { return }
        let nodes = watching.values.compactMap { $0.box?.node }
        guard !nodes.isEmpty else { return }
        MainActor.assumeIsolated {
            for node in nodes { node.invalidate() }
        }
    }
}

// MARK: - Reading and writing by type

/// How each stored type goes in and out of the defaults: absent keys read as nil, so the
/// property's default value answers for them as SwiftUI's does.
private enum _Defaults {
    static func has(_ defaults: UserDefaults, _ key: String) -> Bool { defaults.object(forKey: key) != nil }

    static func bool(_ d: UserDefaults, _ k: String) -> Bool? { has(d, k) ? d.bool(forKey: k) : nil }
    static func int(_ d: UserDefaults, _ k: String) -> Int? { has(d, k) ? d.integer(forKey: k) : nil }
    static func double(_ d: UserDefaults, _ k: String) -> Double? { has(d, k) ? d.double(forKey: k) : nil }
    static func string(_ d: UserDefaults, _ k: String) -> String? { d.string(forKey: k) }
    static func url(_ d: UserDefaults, _ k: String) -> URL? { d.url(forKey: k) }
    static func data(_ d: UserDefaults, _ k: String) -> Data? { d.data(forKey: k) }
    static func date(_ d: UserDefaults, _ k: String) -> Date? { d.object(forKey: k) as? Date }

    static func set(_ d: UserDefaults, _ k: String, _ value: Bool) { d.set(value, forKey: k) }
    static func set(_ d: UserDefaults, _ k: String, _ value: Int) { d.set(value, forKey: k) }
    static func set(_ d: UserDefaults, _ k: String, _ value: Double) { d.set(value, forKey: k) }
    static func set(_ d: UserDefaults, _ k: String, _ value: String) { d.set(value as Any, forKey: k) }
    static func set(_ d: UserDefaults, _ k: String, _ value: URL) { d.set(value, forKey: k) }
    static func set(_ d: UserDefaults, _ k: String, _ value: Data) { d.set(value as Any, forKey: k) }
    static func set(_ d: UserDefaults, _ k: String, _ value: Date) { d.set(value as Any, forKey: k) }
    static func remove(_ d: UserDefaults, _ k: String) { d.removeObject(forKey: k) }
}

extension AppStorage {
    /// Creates a property that can read and write to a boolean user default.
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Bool {
        self.init(key: key, store: store, defaultValue: wrappedValue, read: _Defaults.bool, write: { _Defaults.set($0, $1, $2) })
    }

    /// Creates a property that can read and write to an integer user default.
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Int {
        self.init(key: key, store: store, defaultValue: wrappedValue, read: _Defaults.int, write: { _Defaults.set($0, $1, $2) })
    }

    /// Creates a property that can read and write to a double user default.
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Double {
        self.init(key: key, store: store, defaultValue: wrappedValue, read: _Defaults.double, write: { _Defaults.set($0, $1, $2) })
    }

    /// Creates a property that can read and write to a string user default.
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == String {
        self.init(key: key, store: store, defaultValue: wrappedValue, read: _Defaults.string, write: { _Defaults.set($0, $1, $2) })
    }

    /// Creates a property that can read and write to a URL user default.
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == URL {
        self.init(key: key, store: store, defaultValue: wrappedValue, read: _Defaults.url, write: { _Defaults.set($0, $1, $2) })
    }

    /// Creates a property that can read and write to a user default as data.
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Data {
        self.init(key: key, store: store, defaultValue: wrappedValue, read: _Defaults.data, write: { _Defaults.set($0, $1, $2) })
    }

    /// Creates a property that can read and write to a date user default.
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value == Date {
        self.init(key: key, store: store, defaultValue: wrappedValue, read: _Defaults.date, write: { _Defaults.set($0, $1, $2) })
    }

    /// Creates a property that can read and write to an integer user default, transforming
    /// that to a `RawRepresentable` data type.
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value: RawRepresentable, Value.RawValue == Int {
        self.init(key: key, store: store, defaultValue: wrappedValue,
                  read: { _Defaults.int($0, $1).flatMap(Value.init(rawValue:)) },
                  write: { _Defaults.set($0, $1, $2.rawValue) })
    }

    /// Creates a property that can read and write to a string user default, transforming
    /// that to a `RawRepresentable` data type.
    public init(wrappedValue: Value, _ key: String, store: UserDefaults? = nil) where Value: RawRepresentable, Value.RawValue == String {
        self.init(key: key, store: store, defaultValue: wrappedValue,
                  read: { _Defaults.string($0, $1).flatMap(Value.init(rawValue:)) },
                  write: { _Defaults.set($0, $1, $2.rawValue) })
    }
}

extension AppStorage {
    /// Creates a property that can read and write an optional boolean user default.
    public init(_ key: String, store: UserDefaults? = nil) where Value == Bool? {
        self.init(key: key, store: store, defaultValue: nil, read: { _Defaults.bool($0, $1).map(Optional.some) },
                  write: { if let value = $2 { _Defaults.set($0, $1, value) } else { _Defaults.remove($0, $1) } })
    }

    /// Creates a property that can read and write an optional integer user default.
    public init(_ key: String, store: UserDefaults? = nil) where Value == Int? {
        self.init(key: key, store: store, defaultValue: nil, read: { _Defaults.int($0, $1).map(Optional.some) },
                  write: { if let value = $2 { _Defaults.set($0, $1, value) } else { _Defaults.remove($0, $1) } })
    }

    /// Creates a property that can read and write an optional double user default.
    public init(_ key: String, store: UserDefaults? = nil) where Value == Double? {
        self.init(key: key, store: store, defaultValue: nil, read: { _Defaults.double($0, $1).map(Optional.some) },
                  write: { if let value = $2 { _Defaults.set($0, $1, value) } else { _Defaults.remove($0, $1) } })
    }

    /// Creates a property that can read and write an optional string user default.
    public init(_ key: String, store: UserDefaults? = nil) where Value == String? {
        self.init(key: key, store: store, defaultValue: nil, read: { _Defaults.string($0, $1).map(Optional.some) },
                  write: { if let value = $2 { _Defaults.set($0, $1, value) } else { _Defaults.remove($0, $1) } })
    }

    /// Creates a property that can read and write an optional URL user default.
    public init(_ key: String, store: UserDefaults? = nil) where Value == URL? {
        self.init(key: key, store: store, defaultValue: nil, read: { _Defaults.url($0, $1).map(Optional.some) },
                  write: { if let value = $2 { _Defaults.set($0, $1, value) } else { _Defaults.remove($0, $1) } })
    }

    /// Creates a property that can read and write an optional data user default.
    public init(_ key: String, store: UserDefaults? = nil) where Value == Data? {
        self.init(key: key, store: store, defaultValue: nil, read: { _Defaults.data($0, $1).map(Optional.some) },
                  write: { if let value = $2 { _Defaults.set($0, $1, value) } else { _Defaults.remove($0, $1) } })
    }

    /// Creates a property that can read and write an optional date user default.
    public init(_ key: String, store: UserDefaults? = nil) where Value == Date? {
        self.init(key: key, store: store, defaultValue: nil, read: { _Defaults.date($0, $1).map(Optional.some) },
                  write: { if let value = $2 { _Defaults.set($0, $1, value) } else { _Defaults.remove($0, $1) } })
    }

    /// Creates a property that can save and restore an optional integer, transforming it to an
    /// optional `RawRepresentable` data type.
    public init<R>(_ key: String, store: UserDefaults? = nil) where Value == R?, R: RawRepresentable, R.RawValue == Int {
        self.init(key: key, store: store, defaultValue: nil, read: { _Defaults.int($0, $1).flatMap(R.init(rawValue:)).map(Optional.some) },
                  write: { if let value = $2 { _Defaults.set($0, $1, value.rawValue) } else { _Defaults.remove($0, $1) } })
    }

    /// Creates a property that can save and restore an optional string, transforming it to an
    /// optional `RawRepresentable` data type.
    public init<R>(_ key: String, store: UserDefaults? = nil) where Value == R?, R: RawRepresentable, R.RawValue == String {
        self.init(key: key, store: store, defaultValue: nil, read: { _Defaults.string($0, $1).flatMap(R.init(rawValue:)).map(Optional.some) },
                  write: { if let value = $2 { _Defaults.set($0, $1, value.rawValue) } else { _Defaults.remove($0, $1) } })
    }
}

// MARK: - The default store

package struct DefaultAppStorageKey: EnvironmentKey {
    // Computed, since `UserDefaults` is Sendable on Apple's SDKs and not everywhere else; the
    // default is nil (the standard defaults).
    package static var defaultValue: UserDefaults? { nil }
}

extension EnvironmentValues {
    /// The store `@AppStorage` properties without one of their own use (`defaultAppStorage`).
    package var defaultAppStorage: UserDefaults? {
        get { self[DefaultAppStorageKey.self] }
        set { self[DefaultAppStorageKey.self] = newValue }
    }
}

extension View {
    /// The default store used by `AppStorage` contained within the view.
    nonisolated public func defaultAppStorage(_ store: UserDefaults) -> some View {
        environment(\.defaultAppStorage, store)
    }
}
