// `NSNumber` on wasm, where FoundationEssentials has none (Docs/coverage.md: 3 apps name it, in
// chart data and formatter calls). It was UIKitWeb's, for the keyboard notifications' user
// info; here every module that imports Foundation sees it. An integer keeps its exact value, a
// floating-point number its double, a boolean its truth; the accessors convert as Foundation's
// do (truncating toward zero), and numbers compare by value whatever they hold.
// Final, unlike Apple's, so a wasm build drops the methods an app never calls (the size gate).
#if os(WASI)

/// An object wrapper for primitive scalar numeric values.
public final class NSNumber: Hashable, Comparable, @unchecked Sendable, CustomStringConvertible,
                     ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral {
    private enum Storage: Sendable { case int(Int64), uint(UInt64), double(Double), bool(Bool) }
    private let storage: Storage

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

    public var description: String {
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

    public func hash(into hasher: inout Hasher) { hasher.combine(doubleValue) }
}

extension Int {
    /// The number's value, truncated toward zero when it has a fractional part.
    public init(truncating number: NSNumber) { self = number.intValue }
}

/// Foundation's decimal number class. Here it is `NSNumber` itself, holding a double, which is
/// exact for prices and the amounts apps show (StoreKit's `SKProduct.price`). There is no bridge
/// to `Decimal`: parsing one links FoundationEssentials' locale machinery, megabytes an app pays
/// for even when it never calls it.
public typealias NSDecimalNumber = NSNumber

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
#endif
