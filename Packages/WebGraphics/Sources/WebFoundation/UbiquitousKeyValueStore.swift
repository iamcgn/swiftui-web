// `NSUbiquitousKeyValueStore` where Foundation has none (wasm, and Linux's Foundation): the
// iCloud key-value store apps keep small settings in beside `@AppStorage` (Docs/coverage.md:
// 3 apps). There is no iCloud here, so the store is local: a defaults suite of its own, which
// the browser host keeps in localStorage as it does `UserDefaults.standard`. Nothing ever
// changes it externally, so `didChangeExternallyNotification` is never posted.
#if !canImport(Darwin)
#if !os(WASI)
import Foundation
#endif

/// An iCloud-based container of key-value pairs you use to share data among instances of your
/// app running on a person's connected devices.
open class NSUbiquitousKeyValueStore: @unchecked Sendable {
    /// The shared iCloud key-value store object.
    public static let `default` = NSUbiquitousKeyValueStore()

    /// Posted when the value of one or more keys in the local key-value store changed due to
    /// incoming data pushed from iCloud.
    public static let didChangeExternallyNotification = Notification.Name("NSUbiquitousKeyValueStoreDidChangeExternallyNotification")

    private let defaults: UserDefaults

    public init() {
        defaults = UserDefaults(suiteName: "NSUbiquitousKeyValueStore") ?? .standard
    }

    open func object(forKey aKey: String) -> Any? { defaults.object(forKey: aKey) }
    open func set(_ anObject: Any?, forKey aKey: String) { defaults.set(anObject, forKey: aKey) }
    open func removeObject(forKey aKey: String) { defaults.removeObject(forKey: aKey) }

    open func string(forKey aKey: String) -> String? { defaults.string(forKey: aKey) }
    open func array(forKey aKey: String) -> [Any]? { defaults.array(forKey: aKey) }
    open func dictionary(forKey aKey: String) -> [String: Any]? { defaults.dictionary(forKey: aKey) }
    open func data(forKey aKey: String) -> Data? { defaults.data(forKey: aKey) }
    open func longLong(forKey aKey: String) -> Int64 { Int64(defaults.integer(forKey: aKey)) }
    open func double(forKey aKey: String) -> Double { defaults.double(forKey: aKey) }
    open func bool(forKey aKey: String) -> Bool { defaults.bool(forKey: aKey) }

    open func set(_ aString: String?, forKey aKey: String) { defaults.set(aString, forKey: aKey) }
    open func set(_ aData: Data?, forKey aKey: String) { defaults.set(aData, forKey: aKey) }
    open func set(_ anArray: [Any]?, forKey aKey: String) { defaults.set(anArray, forKey: aKey) }
    open func set(_ aDictionary: [String: Any]?, forKey aKey: String) { defaults.set(aDictionary, forKey: aKey) }
    open func set(_ value: Int64, forKey aKey: String) { defaults.set(Int(value), forKey: aKey) }
    open func set(_ value: Double, forKey aKey: String) { defaults.set(value, forKey: aKey) }
    open func set(_ value: Bool, forKey aKey: String) { defaults.set(value, forKey: aKey) }

    /// Every key and value in the store.
    open var dictionaryRepresentation: [String: Any] {
        var all: [String: Any] = [:]
        for (key, value) in defaults.dictionaryRepresentation() where defaults.object(forKey: key) != nil { all[key] = value }
        return all
    }

    /// Writes in-memory keys and values to disk: they already are, so this answers true.
    @discardableResult
    open func synchronize() -> Bool { true }
}

/// The user-info key whose value says why the store changed externally.
public let NSUbiquitousKeyValueStoreChangeReasonKey = "NSUbiquitousKeyValueStoreChangeReasonKey"
/// The user-info key whose value lists the keys that changed.
public let NSUbiquitousKeyValueStoreChangedKeysKey = "NSUbiquitousKeyValueStoreChangedKeysKey"
/// The value changed on another device.
public let NSUbiquitousKeyValueStoreServerChange = 0
/// The store was first synchronized with iCloud.
public let NSUbiquitousKeyValueStoreInitialSyncChange = 1
/// The app's iCloud quota was exceeded.
public let NSUbiquitousKeyValueStoreQuotaViolationChange = 2
/// The iCloud account changed.
public let NSUbiquitousKeyValueStoreAccountChange = 3
#endif
