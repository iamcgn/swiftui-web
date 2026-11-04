// Collections and Foundation values crossing into Objective-C (decision 0023, v1.5 bridging).
//
// With the interop SDK an `@objc` member may only take and return types the compiler can
// represent in Objective-C: classes rooted at `NSObject`, and value types that conform to
// `_ObjectiveCBridgeable`. Apple's Foundation conforms `Array`, `Dictionary`, `Set`, `Date`,
// `URL`, `Data` and `UUID` to it, over `NSArray`, `NSDictionary` and the rest; there is no such
// Foundation here, so each type bridges to a small object of this module that holds the Swift
// value (`String` bridges in NSRegularExpression.swift). Objective-C code cannot read these
// objects as Foundation's classes; they carry values between Swift `@objc` members, whose
// caller bridges an argument in and whose body bridges it straight back out.
//
// The objects are named with an underscore: `NSSet` and `NSDate` are Core Data's spellings of
// `Set` and `Date` here (WebCoreData, Values.swift), and the compiler reads some Foundation
// class names in the module named Foundation as Apple's Foundation being present (`NSString`,
// NSRegularExpression.swift).
#if os(WASI) && canImport(ObjectiveC)

/// The object an array becomes in Objective-C: its elements, each as `Any`.
public final class _WebNSArray: NSObject, @unchecked Sendable {
    public let elements: [Any]
    public init(elements: [Any]) {
        self.elements = elements
        super.init()
    }
    public var count: Int { elements.count }
}

/// The object a dictionary becomes in Objective-C: its keys as `AnyHashable`, values as `Any`.
public final class _WebNSDictionary: NSObject, @unchecked Sendable {
    public let entries: [AnyHashable: Any]
    public init(entries: [AnyHashable: Any]) {
        self.entries = entries
        super.init()
    }
    public var count: Int { entries.count }
}

/// The object a set becomes in Objective-C: its members as `AnyHashable`.
public final class _WebNSSet: NSObject, @unchecked Sendable {
    public let members: [AnyHashable]
    public init(members: [AnyHashable]) {
        self.members = members
        super.init()
    }
    public var count: Int { members.count }
}

/// The object a value type becomes in Objective-C (`Date`, `URL`, `Data`, `UUID`): the value
/// itself, as Foundation's `NSNumber` stands for every number type.
public final class _WebNSValue: NSObject, @unchecked Sendable {
    public let value: Any
    public init(_ value: Any) {
        self.value = value
        super.init()
    }
}

/// A key back to the dictionary's or set's own key type: the boxed value, else the hashable itself.
@inline(__always)
func _webUnbox<Key>(_ key: AnyHashable, as type: Key.Type) -> Key? {
    if let unboxed = key.base as? Key { return unboxed }
    return key as? Key
}

extension Array: @retroactive _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = _WebNSArray
    public func _bridgeToObjectiveC() -> _WebNSArray { _WebNSArray(elements: map { $0 as Any }) }
    public static func _forceBridgeFromObjectiveC(_ source: _WebNSArray, result: inout [Element]?) {
        result = source.elements.map { $0 as! Element }
    }
    public static func _conditionallyBridgeFromObjectiveC(_ source: _WebNSArray, result: inout [Element]?) -> Bool {
        var converted: [Element] = []
        converted.reserveCapacity(source.elements.count)
        for element in source.elements {
            guard let typed = element as? Element else { result = nil; return false }
            converted.append(typed)
        }
        result = converted
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: _WebNSArray?) -> [Element] {
        source?.elements.map { $0 as! Element } ?? []
    }
}

extension Dictionary: @retroactive _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = _WebNSDictionary
    public func _bridgeToObjectiveC() -> _WebNSDictionary {
        var entries: [AnyHashable: Any] = [:]
        entries.reserveCapacity(count)
        for (key, value) in self { entries[AnyHashable(key)] = value }
        return _WebNSDictionary(entries: entries)
    }
    public static func _forceBridgeFromObjectiveC(_ source: _WebNSDictionary, result: inout [Key: Value]?) {
        guard _conditionallyBridgeFromObjectiveC(source, result: &result) else {
            fatalError("an Objective-C dictionary's entries are not \(Key.self): \(Value.self)")
        }
    }
    public static func _conditionallyBridgeFromObjectiveC(_ source: _WebNSDictionary, result: inout [Key: Value]?) -> Bool {
        var converted: [Key: Value] = [:]
        converted.reserveCapacity(source.entries.count)
        for (key, value) in source.entries {
            guard let typedKey = _webUnbox(key, as: Key.self), let typedValue = value as? Value else { result = nil; return false }
            converted[typedKey] = typedValue
        }
        result = converted
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: _WebNSDictionary?) -> [Key: Value] {
        guard let source else { return [:] }
        var result: [Key: Value]?
        _forceBridgeFromObjectiveC(source, result: &result)
        return result ?? [:]
    }
}

extension Set: @retroactive _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = _WebNSSet
    public func _bridgeToObjectiveC() -> _WebNSSet { _WebNSSet(members: map { AnyHashable($0) }) }
    public static func _forceBridgeFromObjectiveC(_ source: _WebNSSet, result: inout Set<Element>?) {
        guard _conditionallyBridgeFromObjectiveC(source, result: &result) else {
            fatalError("an Objective-C set's members are not \(Element.self)")
        }
    }
    public static func _conditionallyBridgeFromObjectiveC(_ source: _WebNSSet, result: inout Set<Element>?) -> Bool {
        var converted = Set<Element>(minimumCapacity: source.members.count)
        for member in source.members {
            guard let typed = _webUnbox(member, as: Element.self) else { result = nil; return false }
            converted.insert(typed)
        }
        result = converted
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: _WebNSSet?) -> Set<Element> {
        guard let source else { return [] }
        var result: Set<Element>?
        _forceBridgeFromObjectiveC(source, result: &result)
        return result ?? []
    }
}

/// A value type that bridges as itself in a `_WebNSValue`.
public protocol _WebValueBridged: _ObjectiveCBridgeable where _ObjectiveCType == _WebNSValue {}

extension _WebValueBridged {
    public func _bridgeToObjectiveC() -> _WebNSValue { _WebNSValue(self) }
    public static func _forceBridgeFromObjectiveC(_ source: _WebNSValue, result: inout Self?) { result = (source.value as! Self) }
    public static func _conditionallyBridgeFromObjectiveC(_ source: _WebNSValue, result: inout Self?) -> Bool {
        result = source.value as? Self
        return result != nil
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: _WebNSValue?) -> Self { source!.value as! Self }
}

extension Date: @retroactive _ObjectiveCBridgeable, _WebValueBridged { public typealias _ObjectiveCType = _WebNSValue }
extension UUID: @retroactive _ObjectiveCBridgeable, _WebValueBridged { public typealias _ObjectiveCType = _WebNSValue }
extension URL: _ObjectiveCBridgeable, _WebValueBridged { public typealias _ObjectiveCType = _WebNSValue }
extension Data: _ObjectiveCBridgeable, _WebValueBridged { public typealias _ObjectiveCType = _WebNSValue }

#endif
