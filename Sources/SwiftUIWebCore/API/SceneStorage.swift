// `@SceneStorage` (SwiftNavigation binds one; FoodTruck and Hipstapaper keep a selected tab or
// sidebar item in one): a value a scene restores when it comes back. Here it is `@AppStorage`
// in a suite of its own, so a value survives a reload as Apple's survives a relaunch; a page
// cannot tell its windows' scenes apart, so tabs of one app share each key, where Apple keeps one
// value per scene.
import WebFoundation

/// A property wrapper type that reads and writes to persisted, per-scene storage.
@propertyWrapper
public struct SceneStorage<Value>: DynamicProperty {
    package var storage: AppStorage<Value>

    package init(_ storage: AppStorage<Value>) { self.storage = storage }

    /// The scene's stored value, or the default when the scene stored none.
    public var wrappedValue: Value {
        get { storage.wrappedValue }
        nonmutating set { storage.wrappedValue = newValue }
    }

    /// A binding to the stored value.
    public var projectedValue: Binding<Value> { storage.projectedValue }

    @MainActor
    public mutating func _install(in node: ViewNode, slot: inout AnyObject?) {
        storage._install(in: node, slot: &slot)
    }
}

/// The suite scene storage keeps its values in.
/// The wasm stand-in's `UserDefaults` is `Sendable`; Foundation's on macOS and Linux is not, so
/// there the shared suite needs unsafe isolation (a view's storage is read on the main actor).
package enum _SceneStore {
    #if os(WASI)
    package static let defaults: UserDefaults = UserDefaults(suiteName: "SwiftUIWeb.SceneStorage") ?? .standard
    #else
    package nonisolated(unsafe) static let defaults: UserDefaults = UserDefaults(suiteName: "SwiftUIWeb.SceneStorage") ?? .standard
    #endif
}

extension SceneStorage {
    public init(wrappedValue: Value, _ key: String) where Value == Bool {
        self.init(AppStorage(wrappedValue: wrappedValue, key, store: _SceneStore.defaults))
    }
    public init(wrappedValue: Value, _ key: String) where Value == Int {
        self.init(AppStorage(wrappedValue: wrappedValue, key, store: _SceneStore.defaults))
    }
    public init(wrappedValue: Value, _ key: String) where Value == Double {
        self.init(AppStorage(wrappedValue: wrappedValue, key, store: _SceneStore.defaults))
    }
    public init(wrappedValue: Value, _ key: String) where Value == String {
        self.init(AppStorage(wrappedValue: wrappedValue, key, store: _SceneStore.defaults))
    }
    public init(wrappedValue: Value, _ key: String) where Value == URL {
        self.init(AppStorage(wrappedValue: wrappedValue, key, store: _SceneStore.defaults))
    }
    public init(wrappedValue: Value, _ key: String) where Value == Data {
        self.init(AppStorage(wrappedValue: wrappedValue, key, store: _SceneStore.defaults))
    }
    public init(wrappedValue: Value, _ key: String) where Value: RawRepresentable, Value.RawValue == Int {
        self.init(AppStorage(wrappedValue: wrappedValue, key, store: _SceneStore.defaults))
    }
    public init(wrappedValue: Value, _ key: String) where Value: RawRepresentable, Value.RawValue == String {
        self.init(AppStorage(wrappedValue: wrappedValue, key, store: _SceneStore.defaults))
    }
}

extension SceneStorage where Value: ExpressibleByNilLiteral {
    public init(_ key: String) where Value == Bool? { self.init(AppStorage(key, store: _SceneStore.defaults)) }
    public init(_ key: String) where Value == Int? { self.init(AppStorage(key, store: _SceneStore.defaults)) }
    public init(_ key: String) where Value == Double? { self.init(AppStorage(key, store: _SceneStore.defaults)) }
    public init(_ key: String) where Value == String? { self.init(AppStorage(key, store: _SceneStore.defaults)) }
    public init(_ key: String) where Value == URL? { self.init(AppStorage(key, store: _SceneStore.defaults)) }
    public init(_ key: String) where Value == Data? { self.init(AppStorage(key, store: _SceneStore.defaults)) }
    public init<R>(_ key: String) where Value == R?, R: RawRepresentable, R.RawValue == Int {
        self.init(AppStorage(key, store: _SceneStore.defaults))
    }
    public init<R>(_ key: String) where Value == R?, R: RawRepresentable, R.RawValue == String {
        self.init(AppStorage(key, store: _SceneStore.defaults))
    }
}
