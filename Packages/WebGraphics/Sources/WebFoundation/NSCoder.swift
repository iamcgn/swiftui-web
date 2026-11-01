// NSCoder on wasm: the type UIKit's `required init?(coder:)` names. Apps subclass a view or a
// controller and write that initializer because UIKit requires it, nearly always with a
// `fatalError` or a call to `super.init(coder:)`; the web has no storyboards or nibs, so no
// coder ever reaches it. The class holds nothing: every decode finds no value, as an empty
// archive would give, and encoding is accepted and dropped.
#if os(WASI)

/// An abstract class that serves as the basis for objects that archive and unarchive values.
open class NSCoder {
    public init() {}

    /// Whether the coder reads and writes values by key (keyed archivers do).
    open var allowsKeyedCoding: Bool { true }

    /// Whether the archive holds a value for `key`: never here.
    open func containsValue(forKey key: String) -> Bool { false }

    /// Records `object` under `key`.
    open func encode(_ object: Any?, forKey key: String) {}
    open func encode(_ value: Bool, forKey key: String) {}
    open func encode(_ value: Int, forKey key: String) {}
    open func encode(_ value: Double, forKey key: String) {}
    open func encode(_ value: Float, forKey key: String) {}

    /// The object stored under `key`, or nil.
    open func decodeObject(forKey key: String) -> Any? { nil }
    open func decodeBool(forKey key: String) -> Bool { false }
    open func decodeInteger(forKey key: String) -> Int { 0 }
    open func decodeDouble(forKey key: String) -> Double { 0 }
    open func decodeFloat(forKey key: String) -> Float { 0 }

    /// The object of class `cls` stored under `key` (secure coding), or nil.
    public func decodeObject<DecodedObjectType>(of cls: DecodedObjectType.Type, forKey key: String) -> DecodedObjectType? {
        decodeObject(forKey: key) as? DecodedObjectType
    }
}

/// A protocol that enables an object to be encoded and decoded for archiving.
public protocol NSCoding {
    func encode(with coder: NSCoder)
    init?(coder: NSCoder)
}

/// A protocol for objects that decode themselves only as the classes they expect.
public protocol NSSecureCoding: NSCoding {
    static var supportsSecureCoding: Bool { get }
}

#endif
