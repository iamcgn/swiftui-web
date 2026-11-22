// The root class without the Objective-C runtime, in a module named as the compiler expects an
// `NSObject` to come from (Foundation, ObjectiveC or SwiftFoundation): only such an `NSObject` may
// be the superclass of a `Sendable` class, so an app's `final class Delegate: NSObject,
// URLSessionTaskDelegate, Sendable` compiles as on iOS (IceCubes' upload progress delegate,
// swift-sharing's user defaults observer). WebFoundation re-exports this module, so `import
// Foundation` names these as before. The two types the class's members take, `Selector` and
// `NSKeyValueChangeKey`, live here with it. With the runtime, NSObject is the ObjectiveC module's.
#if os(WASI) && !canImport(ObjectiveC)

/// A command name (`onCommand`); `#selector` needs an Objective-C runtime, so commands are
/// named by their selector string ("copy:", "selectAll:").
public struct Selector: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let name: String
    public init(_ name: String) { self.name = name }
    public init(stringLiteral value: String) { self.name = value }
    public var description: String { name }
}

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

// MARK: - NSObject (decision 0021: the Countries app subclasses it for its notification
// delegate; `super.init()`, identity equality, a hash and a description). With the
// Objective-C runtime (decision 0023) the real NSObject comes from the ObjectiveC module.

/// The protocol the root class conforms to.
public protocol NSObjectProtocol: AnyObject {
    func isEqual(_ object: Any?) -> Bool
    var hash: Int { get }
    var description: String { get }
}

/// The root class of most Objective-C class hierarchies, without the runtime: identity
/// equality and hashing, overridable, as apps subclass it for delegates.
open class NSObject: NSObjectProtocol, Hashable, CustomStringConvertible {
    public init() {}
    open func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? NSObject else { return false }
        return other === self
    }
    open var hash: Int { ObjectIdentifier(self).hashValue }
    open var description: String { "<\(type(of: self))>" }
    open var debugDescription: String { description }
    public static func == (lhs: NSObject, rhs: NSObject) -> Bool { lhs.isEqual(rhs) }
    public func hash(into hasher: inout Hasher) { hasher.combine(hash) }
    open class var description: String { "\(self)" }
    /// The class an archive records for objects of this class: the class itself
    /// (`UITableViewCell.classForCoder()`, which apps register cells with).
    open class func classForCoder() -> AnyClass { self }
    public func isKind(of aClass: AnyClass) -> Bool { type(of: self) == aClass }
    public func isMember(of aClass: AnyClass) -> Bool { type(of: self) == aClass }

    // Sending a message by selector. Without the runtime no method is registered under a
    // selector, so an object responds to none and a send returns nothing: code that checks
    // first (`responds(to:)`, then `perform`), as Kingfisher does for `sharedApplication`,
    // takes its branch for a missing method. A class overrides these to answer for itself.
    open func responds(to aSelector: Selector!) -> Bool { false }
    open class func responds(to aSelector: Selector!) -> Bool { false }
    open class func instancesRespond(to aSelector: Selector!) -> Bool { false }
    open func perform(_ aSelector: Selector!) -> Unmanaged<AnyObject>! { nil }
    open func perform(_ aSelector: Selector!, with object: Any!) -> Unmanaged<AnyObject>! { nil }
    open func perform(_ aSelector: Selector!, with object1: Any!, with object2: Any!) -> Unmanaged<AnyObject>! { nil }
    open class func perform(_ aSelector: Selector!) -> Unmanaged<AnyObject>! { nil }
    open class func perform(_ aSelector: Selector!, with object: Any!) -> Unmanaged<AnyObject>! { nil }
    open class func perform(_ aSelector: Selector!, with object1: Any!, with object2: Any!) -> Unmanaged<AnyObject>! { nil }

    /// Called when a value this object observes by key changes (`addObserver(_:forKeyPath:…)`,
    /// KeyValueObserving.swift); subclasses override it.
    open func observeValue(forKeyPath keyPath: String?, of object: Any?,
                           change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {}
}
#endif
