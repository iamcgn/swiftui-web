// `NSNumber` on wasm, where FoundationEssentials has none (Docs/coverage.md: 3 apps name it, in
// chart data and formatter calls). It was UIKitWeb's, for the keyboard notifications' user
// info; here every module that imports Foundation sees it. An integer keeps its exact value, a
// floating-point number its double, a boolean its truth; the accessors convert as Foundation's
// do (truncating toward zero), and numbers compare by value whatever they hold.
// Final, unlike Apple's, so a wasm build drops the methods an app never calls (the size gate);
// open only with the Objective-C runtime, for `NSDecimalNumber` (below).
#if os(WASI)

#if canImport(ObjectiveC)
/// An object wrapper for primitive scalar numeric values. Open with the runtime, so that
/// `NSDecimalNumber` is a kind of it, as Foundation's is: the compiler treats a bridge to
/// `NSNumber` itself as a checked cast, so `price as Decimal` needs the subclass (RevenueCat).
/// Members past the stored value and the initializers are in an extension, statically called.
open class NSNumber: _WebObjectBase, Comparable, @unchecked Sendable,
                     ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral {
    fileprivate enum Storage: Sendable { case int(Int64), uint(UInt64), double(Double), bool(Bool) }
    fileprivate let storage: Storage

    public init(value: Int) { storage = .int(Int64(value)) }
    public init(value: Int8) { storage = .int(Int64(value)) }
    public init(value: Int16) { storage = .int(Int64(value)) }
    public init(value: Int32) { storage = .int(Int64(value)) }
    public init(value: Int64) { storage = .int(value) }
    public init(value: UInt) { storage = .uint(UInt64(value)) }
    public init(value: UInt8) { storage = .uint(UInt64(value)) }
    public init(value: UInt16) { storage = .uint(UInt64(value)) }
    public init(value: UInt32) { storage = .uint(UInt64(value)) }
    public init(value: UInt64) { storage = .uint(value) }
    public init(value: Double) { storage = .double(value) }
    public init(value: Float) { storage = .double(Double(value)) }
    public init(value: Bool) { storage = .bool(value) }

    public required convenience init(integerLiteral value: Int) { self.init(value: value) }
    public required convenience init(floatLiteral value: Double) { self.init(value: value) }
    public required convenience init(booleanLiteral value: Bool) { self.init(value: value) }

    // An `NSObject` (ObjectBase.swift), so `@objc` members take `NSNumber` and `NSDecimalNumber`
    // (RevenueCat's `pricePerDay`) and `Decimal`, which bridges to it, is representable too.
    public override var description: String { _description }
    /// Equal to another number of the same value, as Foundation's are.
    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? NSNumber else { return false }
        return self == other
    }
    public override var hash: Int { doubleValue.hashValue }
}
#else
/// An object wrapper for primitive scalar numeric values.
public final class NSNumber: _WebObjectBase, Comparable, @unchecked Sendable,
                     ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral {
    fileprivate enum Storage: Sendable { case int(Int64), uint(UInt64), double(Double), bool(Bool) }
    fileprivate let storage: Storage

    public init(value: Int) { storage = .int(Int64(value)) }
    public init(value: Int8) { storage = .int(Int64(value)) }
    public init(value: Int16) { storage = .int(Int64(value)) }
    public init(value: Int32) { storage = .int(Int64(value)) }
    public init(value: Int64) { storage = .int(value) }
    public init(value: UInt) { storage = .uint(UInt64(value)) }
    public init(value: UInt8) { storage = .uint(UInt64(value)) }
    public init(value: UInt16) { storage = .uint(UInt64(value)) }
    public init(value: UInt32) { storage = .uint(UInt64(value)) }
    public init(value: UInt64) { storage = .uint(value) }
    public init(value: Double) { storage = .double(value) }
    public init(value: Float) { storage = .double(Double(value)) }
    public init(value: Bool) { storage = .bool(value) }

    public convenience init(integerLiteral value: Int) { self.init(value: value) }
    public convenience init(floatLiteral value: Double) { self.init(value: value) }
    public convenience init(booleanLiteral value: Bool) { self.init(value: value) }

    public var description: String { _description }
}
#endif

extension NSNumber {
    public var doubleValue: Double {
        switch storage {
        case .int(let v): return Double(v)
        case .uint(let v): return Double(v)
        case .double(let v): return v
        case .bool(let v): return v ? 1 : 0
        }
    }
    public var int64Value: Int64 {
        switch storage {
        case .int(let v): return v
        case .uint(let v): return Int64(truncatingIfNeeded: v)
        case .double(let v): return !v.isFinite ? 0 : abs(v) < 9.2e18 ? Int64(v) : (v < 0 ? .min : .max)
        case .bool(let v): return v ? 1 : 0
        }
    }
    public var uint64Value: UInt64 {
        switch storage {
        case .uint(let v): return v
        default: return UInt64(truncatingIfNeeded: int64Value)
        }
    }
    public var floatValue: Float { Float(doubleValue) }
    /// The Objective-C type code of the stored value: "q" for a signed integer, "Q" for an
    /// unsigned one, "d" for a floating-point number and "c" for a boolean.
    public var objCType: UnsafePointer<CChar> {
        let code: StaticString
        switch storage {
        case .int: code = "q"
        case .uint: code = "Q"
        case .double: code = "d"
        case .bool: code = "c"
        }
        return UnsafeRawPointer(code.utf8Start).assumingMemoryBound(to: CChar.self)
    }
    public var intValue: Int { Int(truncatingIfNeeded: int64Value) }
    public var int8Value: Int8 { Int8(truncatingIfNeeded: int64Value) }
    public var int16Value: Int16 { Int16(truncatingIfNeeded: int64Value) }
    public var int32Value: Int32 { Int32(truncatingIfNeeded: int64Value) }
    public var uintValue: UInt { UInt(truncatingIfNeeded: uint64Value) }
    public var uint8Value: UInt8 { UInt8(truncatingIfNeeded: uint64Value) }
    public var uint16Value: UInt16 { UInt16(truncatingIfNeeded: uint64Value) }
    public var uint32Value: UInt32 { UInt32(truncatingIfNeeded: uint64Value) }
    public var boolValue: Bool {
        switch storage {
        case .bool(let v): return v
        default: return doubleValue != 0
        }
    }
    public var stringValue: String { description }
    /// The number as an address (Foundation's NSValue reading, used on return-address lists).
    public var pointerValue: UnsafeMutableRawPointer? { UnsafeMutableRawPointer(bitPattern: uintValue) }

    private var _description: String {
        switch storage {
        case .int(let v): return String(v)
        case .uint(let v): return String(v)
        case .double(let v): return v == v.rounded() && abs(v) < 1e15 ? String(Int64(v)) : String(v)
        case .bool(let v): return v ? "1" : "0"
        }
    }

    /// Orders this number against another by value.
    public func compare(_ otherNumber: NSNumber) -> ComparisonResult {
        if self < otherNumber { return .orderedAscending }
        if otherNumber < self { return .orderedDescending }
        return .orderedSame
    }

    public func isEqual(to number: NSNumber) -> Bool { self == number }

    public static func == (lhs: NSNumber, rhs: NSNumber) -> Bool {
        switch (lhs.storage, rhs.storage) {
        case (.int(let a), .int(let b)): return a == b
        case (.uint(let a), .uint(let b)): return a == b
        default: return lhs.doubleValue == rhs.doubleValue
        }
    }

    public static func < (lhs: NSNumber, rhs: NSNumber) -> Bool {
        switch (lhs.storage, rhs.storage) {
        case (.int(let a), .int(let b)): return a < b
        case (.uint(let a), .uint(let b)): return a < b
        default: return lhs.doubleValue < rhs.doubleValue
        }
    }
}

#if !canImport(ObjectiveC)
extension NSNumber: Hashable, CustomStringConvertible {
    public func hash(into hasher: inout Hasher) { hasher.combine(doubleValue) }
}
#endif

extension Int {
    /// The number's value, truncated toward zero when it has a fractional part.
    public init(truncating number: NSNumber) { self = number.intValue }
}

/// Foundation's decimal number class, holding a double, which is exact for prices and the amounts
/// apps show (StoreKit's `SKProduct.price`); its arithmetic is in NSDecimalNumber.swift, and its
/// bridge to `Decimal` in WebDecimalFormats, where `Decimal` is linked. Without the runtime it is
/// `NSNumber` itself. With it, a subclass: the compiler reads a bridge to `NSNumber` as a checked
/// cast, so `Decimal`'s bridge is to this class and `price as Decimal` converts, as on Apple's.
#if canImport(ObjectiveC)
open class NSDecimalNumber: NSNumber, @unchecked Sendable {}
#else
public typealias NSDecimalNumber = NSNumber
#endif

extension Int64 {
    public init(truncating number: NSNumber) { self = number.int64Value }
}

extension Double {
    public init(truncating number: NSNumber) { self = number.doubleValue }
}

extension Float {
    public init(truncating number: NSNumber) { self = number.floatValue }
}

extension Bool {
    public init(truncating number: NSNumber) { self = number.boolValue }
}

#if canImport(ObjectiveC)
// With the Objective-C runtime the number types bridge to `NSNumber`, as Foundation's do:
// `count as NSNumber` converts (RevenueCat's promotional offer signature), `number as? Int`
// succeeds when the number holds that value exactly, and `as!` takes the value truncated.

/// A number type that converts to and from `NSNumber` across the bridge.
public protocol _WebNumberBridged: _ObjectiveCBridgeable where _ObjectiveCType == NSNumber {
    /// The number's value when this type holds it exactly, else nil.
    static func _webExactly(_ number: NSNumber) -> Self?
    /// The number's value, converted as `init(truncating:)` does.
    static func _webTruncating(_ number: NSNumber) -> Self
    var _webNumber: NSNumber { get }
}

extension _WebNumberBridged {
    public func _bridgeToObjectiveC() -> NSNumber { _webNumber }
    public static func _forceBridgeFromObjectiveC(_ source: NSNumber, result: inout Self?) {
        result = _webExactly(source) ?? _webTruncating(source)
    }
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSNumber, result: inout Self?) -> Bool {
        result = _webExactly(source)
        return result != nil
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSNumber?) -> Self {
        guard let source else { return _webTruncating(NSNumber(value: 0)) }
        return _webExactly(source) ?? _webTruncating(source)
    }
}

extension NSNumber {
    fileprivate func _webExactInteger<T: BinaryInteger>(_ type: T.Type) -> T? {
        switch storage {
        case .int(let v): return T(exactly: v)
        case .uint(let v): return T(exactly: v)
        case .double(let v): return T(exactly: v)
        case .bool(let v): return v ? 1 : 0
        }
    }
    fileprivate var _webExactDouble: Double? {
        switch storage {
        case .int(let v): return Double(exactly: v)
        case .uint(let v): return Double(exactly: v)
        case .double(let v): return v
        case .bool(let v): return v ? 1 : 0
        }
    }
    /// True or false for a boolean, or for a number that is exactly 1 or 0.
    fileprivate var _webExactBool: Bool? {
        switch storage {
        case .bool(let v): return v
        default:
            let value = doubleValue
            return value == 0 ? false : value == 1 ? true : nil
        }
    }
}

extension Int: @retroactive _ObjectiveCBridgeable, _WebNumberBridged {
    public typealias _ObjectiveCType = NSNumber
    public static func _webExactly(_ number: NSNumber) -> Int? { number._webExactInteger(Int.self) }
    public static func _webTruncating(_ number: NSNumber) -> Int { number.intValue }
    public var _webNumber: NSNumber { NSNumber(value: self) }
}
extension Int8: @retroactive _ObjectiveCBridgeable, _WebNumberBridged {
    public typealias _ObjectiveCType = NSNumber
    public static func _webExactly(_ number: NSNumber) -> Int8? { number._webExactInteger(Int8.self) }
    public static func _webTruncating(_ number: NSNumber) -> Int8 { number.int8Value }
    public var _webNumber: NSNumber { NSNumber(value: self) }
}
extension Int16: @retroactive _ObjectiveCBridgeable, _WebNumberBridged {
    public typealias _ObjectiveCType = NSNumber
    public static func _webExactly(_ number: NSNumber) -> Int16? { number._webExactInteger(Int16.self) }
    public static func _webTruncating(_ number: NSNumber) -> Int16 { number.int16Value }
    public var _webNumber: NSNumber { NSNumber(value: self) }
}
extension Int32: @retroactive _ObjectiveCBridgeable, _WebNumberBridged {
    public typealias _ObjectiveCType = NSNumber
    public static func _webExactly(_ number: NSNumber) -> Int32? { number._webExactInteger(Int32.self) }
    public static func _webTruncating(_ number: NSNumber) -> Int32 { number.int32Value }
    public var _webNumber: NSNumber { NSNumber(value: self) }
}
extension Int64: @retroactive _ObjectiveCBridgeable, _WebNumberBridged {
    public typealias _ObjectiveCType = NSNumber
    public static func _webExactly(_ number: NSNumber) -> Int64? { number._webExactInteger(Int64.self) }
    public static func _webTruncating(_ number: NSNumber) -> Int64 { number.int64Value }
    public var _webNumber: NSNumber { NSNumber(value: self) }
}
extension UInt: @retroactive _ObjectiveCBridgeable, _WebNumberBridged {
    public typealias _ObjectiveCType = NSNumber
    public static func _webExactly(_ number: NSNumber) -> UInt? { number._webExactInteger(UInt.self) }
    public static func _webTruncating(_ number: NSNumber) -> UInt { number.uintValue }
    public var _webNumber: NSNumber { NSNumber(value: self) }
}
extension UInt8: @retroactive _ObjectiveCBridgeable, _WebNumberBridged {
    public typealias _ObjectiveCType = NSNumber
    public static func _webExactly(_ number: NSNumber) -> UInt8? { number._webExactInteger(UInt8.self) }
    public static func _webTruncating(_ number: NSNumber) -> UInt8 { number.uint8Value }
    public var _webNumber: NSNumber { NSNumber(value: self) }
}
extension UInt16: @retroactive _ObjectiveCBridgeable, _WebNumberBridged {
    public typealias _ObjectiveCType = NSNumber
    public static func _webExactly(_ number: NSNumber) -> UInt16? { number._webExactInteger(UInt16.self) }
    public static func _webTruncating(_ number: NSNumber) -> UInt16 { number.uint16Value }
    public var _webNumber: NSNumber { NSNumber(value: self) }
}
extension UInt32: @retroactive _ObjectiveCBridgeable, _WebNumberBridged {
    public typealias _ObjectiveCType = NSNumber
    public static func _webExactly(_ number: NSNumber) -> UInt32? { number._webExactInteger(UInt32.self) }
    public static func _webTruncating(_ number: NSNumber) -> UInt32 { number.uint32Value }
    public var _webNumber: NSNumber { NSNumber(value: self) }
}
extension UInt64: @retroactive _ObjectiveCBridgeable, _WebNumberBridged {
    public typealias _ObjectiveCType = NSNumber
    public static func _webExactly(_ number: NSNumber) -> UInt64? { number._webExactInteger(UInt64.self) }
    public static func _webTruncating(_ number: NSNumber) -> UInt64 { number.uint64Value }
    public var _webNumber: NSNumber { NSNumber(value: self) }
}
extension Double: @retroactive _ObjectiveCBridgeable, _WebNumberBridged {
    public typealias _ObjectiveCType = NSNumber
    public static func _webExactly(_ number: NSNumber) -> Double? { number._webExactDouble }
    public static func _webTruncating(_ number: NSNumber) -> Double { number.doubleValue }
    public var _webNumber: NSNumber { NSNumber(value: self) }
}
extension Float: @retroactive _ObjectiveCBridgeable, _WebNumberBridged {
    public typealias _ObjectiveCType = NSNumber
    /// A double the float holds to within its precision, as Foundation lets `0.1` read as a float.
    public static func _webExactly(_ number: NSNumber) -> Float? {
        guard let value = number._webExactDouble else { return nil }
        if value.isNaN { return .nan }
        guard value.isInfinite || abs(value) <= Double(Float.greatestFiniteMagnitude) else { return nil }
        return Float(value)
    }
    public static func _webTruncating(_ number: NSNumber) -> Float { number.floatValue }
    public var _webNumber: NSNumber { NSNumber(value: self) }
}
extension Bool: @retroactive _ObjectiveCBridgeable, _WebNumberBridged {
    public typealias _ObjectiveCType = NSNumber
    public static func _webExactly(_ number: NSNumber) -> Bool? { number._webExactBool }
    public static func _webTruncating(_ number: NSNumber) -> Bool { number.boolValue }
    public var _webNumber: NSNumber { NSNumber(value: self) }
}
#endif
#endif
