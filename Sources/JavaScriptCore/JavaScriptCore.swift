// JavaScriptCore on the web: `JSContext` and `JSValue` over the browser's own JavaScript engine
// (Engine.swift), so an app that runs a script library through JavaScriptCore (Highlightr and
// HighlightSwift run highlight.js; others run Markdown or template engines) runs it in the page.
// A context evaluates scripts in a realm of its own; values convert between Swift and script as
// Apple's do (strings, numbers, booleans, dates, arrays and dictionaries; any other Swift value
// travels as an opaque object that converts back to itself), and an exception a script throws goes
// to the context's exception handler, which by default keeps it as `exception`. Not done: Swift
// blocks as script functions and `JSExport` (both need the Objective-C runtime's blocks and
// protocols), and the context's current callee, this and arguments (no Swift function is ever
// called from script). Without a browser (the native builds) there is no engine, and making a
// context gives nil.
#if os(WASI)
import WebFoundation
import JavaScriptKit
#else
import Foundation
#endif

// MARK: - Virtual machines

/// A JavaScript heap that contexts share. Each context here is a realm of the page's one engine,
/// so the machine only groups them.
open class JSVirtualMachine: NSObject, @unchecked Sendable {
    public override init() { super.init() }
    /// Keeps `object` alive while `owner` is (the engine's garbage collector sees every value here).
    open func addManagedReference(_ object: Any!, withOwner owner: Any!) {}
    open func removeManagedReference(_ object: Any!, withOwner owner: Any!) {}
}

// MARK: - Contexts

/// A JavaScript execution environment: a global object and the scripts evaluated in it.
///
/// Not an `NSObject` here: making a context can fail (no engine), and Swift lets no failable
/// initializer override `NSObject`'s `init()`.
open class JSContext: @unchecked Sendable {
    /// The machine the context belongs to.
    public let virtualMachine: JSVirtualMachine!
    /// A name for the context (Web Inspector's, on Apple's platforms).
    open var name: String!
    /// Whether Web Inspector may inspect the context (the page's own developer tools always can).
    open var isInspectable = false
    /// The exception the last script threw, when the handler keeps it (the default handler does).
    open var exception: JSValue!
    /// Called with each exception a script throws; by default keeps it as `exception`.
    open var exceptionHandler: ((JSContext?, JSValue?) -> Void)! = { context, exception in context?.exception = exception }

    #if os(WASI)
    let global: JSObject
    private let realm: JSObject
    #endif

    public convenience init!() {
        self.init(virtualMachine: JSVirtualMachine())
    }

    public init!(virtualMachine: JSVirtualMachine!) {
        #if os(WASI)
        guard let made = _JSEngine.makeRealm() else { return nil }
        global = made.global
        realm = made.realm
        self.virtualMachine = virtualMachine ?? JSVirtualMachine()
        #else
        return nil
        #endif
    }

    #if os(WASI)
    deinit { _JSEngine.dropRealm(realm) }
    #endif

    /// The context's global object (the realm's window).
    open var globalObject: JSValue! {
        #if os(WASI)
        return JSValue(handle: .object(global), in: self)
        #else
        return nil
        #endif
    }

    /// Evaluates `script`, giving its completion value (undefined when it throws).
    @discardableResult
    open func evaluateScript(_ script: String!) -> JSValue! {
        evaluateScript(script, withSourceURL: nil)
    }

    /// Evaluates `script`, naming it `sourceURL` in stack traces.
    @discardableResult
    open func evaluateScript(_ script: String!, withSourceURL sourceURL: URL!) -> JSValue! {
        #if os(WASI)
        var source = script ?? ""
        if let sourceURL { source += "\n//# sourceURL=\(sourceURL.absoluteString)" }
        return settle(_JSEngine.evaluate(source, in: global))
        #else
        return nil
        #endif
    }

    /// The global object's property named `key`.
    open func objectForKeyedSubscript(_ key: Any!) -> JSValue! {
        globalObject?.objectForKeyedSubscript(key)
    }

    /// Sets the global object's property named `key` to `object`, converted.
    open func setObject(_ object: Any!, forKeyedSubscript key: Any!) {
        globalObject?.setObject(object, forKeyedSubscript: key)
    }

    /// The context of the script function calling Swift (none: script never calls Swift here).
    open class func current() -> JSContext! { nil }
    open class func currentCallee() -> JSValue! { nil }
    open class func currentThis() -> JSValue! { nil }
    open class func currentArguments() -> [Any]! { nil }

    #if os(WASI)
    /// The value of an operation that may throw: an exception goes to the handler, and the
    /// operation gives undefined.
    func settle(_ outcome: _JSEngine.Outcome) -> JSValue {
        switch outcome {
        case .value(let value):
            return JSValue(handle: value, in: self)
        case .exception(let thrown):
            notify(JSValue(handle: thrown, in: self))
            return JSValue(handle: .undefined, in: self)
        }
    }

    func notify(_ exception: JSValue) {
        if let handler = exceptionHandler { handler(self, exception) } else { self.exception = exception }
    }

    // MARK: Converting Swift values

    /// `value` as a value of this context, as JavaScriptCore converts it: nil is undefined,
    /// `NSNull` null, strings, numbers and booleans their script forms, a date a `Date`, an
    /// array an `Array` and a dictionary an object of its entries (both converted through),
    /// a `JSValue` itself, and any other value an opaque object that converts back to it.
    func handle(for value: Any?, depth: Int = 0) -> _JSHandle {
        guard let value = Self.flatten(value) else { return .undefined }
        switch value {
        case let value as JSValue: return value.handle
        case is NSNull: return .null
        case let value as String: return _JSEngine.string(value)
        case let value as NSString: return _JSEngine.string(value.string)
        case let value as Substring: return _JSEngine.string(String(value))
        case let value as Character: return _JSEngine.string(String(value))
        case let value as Bool: return .boolean(value)
        case let value as NSNumber:
            return value.objCType.pointee == CChar(UInt8(ascii: "c")) ? .boolean(value.boolValue) : .number(value.doubleValue)
        case let value as Date: return _JSEngine.date(value.timeIntervalSince1970 * 1000, in: global)
        case let value as any BinaryInteger: return .number(Double(value))
        case let value as any BinaryFloatingPoint: return .number(Double(value))
        default: break
        }
        guard depth < 64 else { return .undefined }
        if let list = value as? [Any] {
            let array = _JSEngine.array(in: global)
            for (index, element) in list.enumerated() {
                _ = _JSEngine.set(array, .number(Double(index)), handle(for: element, depth: depth + 1))
            }
            return array
        }
        if let entries = value as? [AnyHashable: Any] {
            let object = _JSEngine.object(in: global)
            for (key, element) in entries {
                _ = _JSEngine.set(object, _JSEngine.string(Self.keyName(key.base)), handle(for: element, depth: depth + 1))
            }
            return object
        }
        return _JSEngine.wrap(value, in: global)
    }

    /// A property key: a symbol stays a symbol, anything else is its string.
    func key(for value: Any?) -> _JSHandle {
        if let value = value as? JSValue, _JSEngine.kind(value.handle) == .symbol { return value.handle }
        return _JSEngine.string(Self.keyName(Self.flatten(value) ?? "undefined"))
    }

    private static func keyName(_ key: Any) -> String {
        switch key {
        case let key as String: return key
        case let key as NSString: return key.string
        case let key as JSValue: return key.toString() ?? ""
        case let key as any BinaryInteger: return String(describing: key)
        default: return String(describing: key)
        }
    }

    /// The value inside any number of optionals, or nil.
    static func flatten(_ value: Any?) -> Any? {
        guard let value else { return nil }
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first.flatMap { flatten($0.value) }
    }
    #endif
}

// MARK: - Values

/// A JavaScript value of a context.
open class JSValue: NSObject, @unchecked Sendable {
    /// The context the value belongs to.
    public let context: JSContext!

    #if os(WASI)
    let handle: _JSHandle

    init(handle: _JSHandle, in context: JSContext) {
        self.handle = handle
        self.context = context
        super.init()
    }

    private convenience init!(_ context: JSContext!, _ make: (JSContext) -> _JSHandle) {
        guard let context else { return nil }
        self.init(handle: make(context), in: context)
    }
    #else
    private init!(_ context: JSContext!, _ make: (JSContext) -> Void) { return nil }
    #endif

    /// `value` converted to a value of `context` (see `JSContext` for the conversions).
    public convenience init!(object value: Any!, in context: JSContext!) {
        #if os(WASI)
        self.init(context) { $0.handle(for: value) }
        #else
        self.init(context) { _ in }
        #endif
    }

    public convenience init!(bool value: Bool, in context: JSContext!) {
        #if os(WASI)
        self.init(context) { _ in .boolean(value) }
        #else
        self.init(context) { _ in }
        #endif
    }

    public convenience init!(double value: Double, in context: JSContext!) {
        #if os(WASI)
        self.init(context) { _ in .number(value) }
        #else
        self.init(context) { _ in }
        #endif
    }

    public convenience init!(int32 value: Int32, in context: JSContext!) { self.init(double: Double(value), in: context) }
    public convenience init!(uInt32 value: UInt32, in context: JSContext!) { self.init(double: Double(value), in: context) }

    public convenience init!(nullIn context: JSContext!) {
        #if os(WASI)
        self.init(context) { _ in .null }
        #else
        self.init(context) { _ in }
        #endif
    }

    public convenience init!(undefinedIn context: JSContext!) {
        #if os(WASI)
        self.init(context) { _ in .undefined }
        #else
        self.init(context) { _ in }
        #endif
    }

    /// A new empty object of the context's realm.
    public convenience init!(newObjectIn context: JSContext!) {
        #if os(WASI)
        self.init(context) { _JSEngine.object(in: $0.global) }
        #else
        self.init(context) { _ in }
        #endif
    }

    /// A new empty array of the context's realm.
    public convenience init!(newArrayIn context: JSContext!) {
        #if os(WASI)
        self.init(context) { _JSEngine.array(in: $0.global) }
        #else
        self.init(context) { _ in }
        #endif
    }

    /// A new `Error` with `message`.
    public convenience init!(newErrorFromMessage message: String!, in context: JSContext!) {
        #if os(WASI)
        self.init(context) { _JSEngine.error(message ?? "", in: $0.global) }
        #else
        self.init(context) { _ in }
        #endif
    }

    /// A new `RegExp`; a pattern the engine rejects throws into the context and gives undefined.
    public convenience init!(newRegularExpressionFromPattern pattern: String!, flags: String!, in context: JSContext!) {
        #if os(WASI)
        self.init(context) { context in
            switch _JSEngine.regexp(pattern ?? "", flags ?? "", in: context.global) {
            case .value(let value): return value
            case .exception(let thrown):
                context.notify(JSValue(handle: thrown, in: context))
                return .undefined
            }
        }
        #else
        self.init(context) { _ in }
        #endif
    }

    /// A new symbol described by `description`.
    public convenience init!(newSymbolFromDescription description: String!, in context: JSContext!) {
        #if os(WASI)
        self.init(context) { _JSEngine.symbol(description ?? "", in: $0.global) }
        #else
        self.init(context) { _ in }
        #endif
    }

    /// A promise already fulfilled with `result`.
    public convenience init!(newPromiseResolvedWithResult result: Any!, in context: JSContext!) {
        #if os(WASI)
        self.init(context) { context in _JSEngine.resolved(context.handle(for: result), in: context.global) }
        #else
        self.init(context) { _ in }
        #endif
    }

    /// A promise already rejected with `reason`.
    public convenience init!(newPromiseRejectedWithReason reason: Any!, in context: JSContext!) {
        #if os(WASI)
        self.init(context) { context in _JSEngine.rejected(context.handle(for: reason), in: context.global) }
        #else
        self.init(context) { _ in }
        #endif
    }

    // MARK: What the value is

    open var isUndefined: Bool { hasKind(.undefined) }
    open var isNull: Bool { hasKind(.null) }
    open var isBoolean: Bool { hasKind(.boolean) }
    open var isNumber: Bool { hasKind(.number) }
    open var isString: Bool { hasKind(.string) }
    /// Whether the value is an object (arrays, dates and functions are).
    open var isObject: Bool {
        #if os(WASI)
        switch _JSEngine.kind(handle) {
        case .object, .array, .date, .function: return true
        default: return false
        }
        #else
        return false
        #endif
    }
    open var isArray: Bool { hasKind(.array) }
    open var isDate: Bool { hasKind(.date) }
    open var isSymbol: Bool { hasKind(.symbol) }
    open var isBigInt: Bool { hasKind(.bigint) }

    private func hasKind(_ kind: _JSKind) -> Bool {
        #if os(WASI)
        return _JSEngine.kind(handle) == kind
        #else
        return false
        #endif
    }

    // MARK: Converting to Swift

    /// The value as a Swift value: nil for undefined, `NSNull` for null, `Bool`, `Double`,
    /// `String` and `Date` for those, an array or a dictionary (of the object's own enumerable
    /// properties) converted through, and the Swift value an opaque object stands for.
    open func toObject() -> Any! {
        #if os(WASI)
        return Self.object(handle, depth: 0)
        #else
        return nil
        #endif
    }

    /// The value as a Swift value when it is an instance of `expectedClass`, else nil.
    open func toObjectOf(_ expectedClass: AnyClass!) -> Any! {
        guard let object = toObject() else { return nil }
        guard let expectedClass else { return object }
        return ObjectIdentifier(type(of: object as AnyObject)) == ObjectIdentifier(expectedClass) ? object : nil
    }

    /// The value's truth, as `!!value` reads it.
    open func toBool() -> Bool {
        #if os(WASI)
        return _JSEngine.truth(handle)
        #else
        return false
        #endif
    }

    /// The value as a number, as `Number(value)` reads it (NaN when it is not one).
    open func toDouble() -> Double {
        #if os(WASI)
        return _JSEngine.number(handle)
        #else
        return .nan
        #endif
    }

    /// The value as a 32-bit integer, as `value | 0` reads it.
    open func toInt32() -> Int32 {
        #if os(WASI)
        return _JSEngine.int32(handle)
        #else
        return 0
        #endif
    }

    /// The value as an unsigned 32-bit integer, as `value >>> 0` reads it.
    open func toUInt32() -> UInt32 {
        #if os(WASI)
        return _JSEngine.uint32(handle)
        #else
        return 0
        #endif
    }

    open func toNumber() -> NSNumber! { NSNumber(value: toDouble()) }

    /// The value as a string, as `String(value)` reads it; nil when converting throws.
    open func toString() -> String! {
        #if os(WASI)
        return _JSEngine.text(handle)
        #else
        return nil
        #endif
    }

    /// The value as a date: its number as milliseconds since 1970 (a `Date`'s time).
    open func toDate() -> Date! {
        let milliseconds = toDouble()
        return milliseconds.isFinite ? Date(timeIntervalSince1970: milliseconds / 1000) : nil
    }

    /// The value as an array: an array's elements, an array-like object's indexed elements, or
    /// the value itself as the one element; nil for null and undefined.
    open func toArray() -> [Any]! {
        #if os(WASI)
        switch _JSEngine.kind(handle) {
        case .undefined, .null: return nil
        case .array: return Self.object(handle, depth: 0) as? [Any]
        default:
            let length = _JSEngine.length(handle)
            guard length >= 0, isObject else { return [toObject() as Any] }
            return (0..<length).map { index in
                Self.element(atIndex(index).handle, depth: 1)
            }
        }
        #else
        return nil
        #endif
    }

    /// The value's own enumerable properties, converted; nil when it is not an object.
    open func toDictionary() -> [AnyHashable: Any]! {
        #if os(WASI)
        guard isObject else { return nil }
        var entries: [AnyHashable: Any] = [:]
        for key in _JSEngine.keys(handle) {
            if case .value(let value) = _JSEngine.get(handle, _JSEngine.string(key)) { entries[key] = Self.element(value, depth: 1) }
        }
        return entries
        #else
        return nil
        #endif
    }

    #if os(WASI)
    /// A value as `toObject` converts it, `depth` levels into a structure.
    private static func object(_ value: _JSHandle, depth: Int) -> Any? {
        switch _JSEngine.kind(value) {
        case .undefined: return nil
        case .null: return NSNull()
        case .boolean: return value.boolean ?? false
        case .number: return value.number ?? .nan
        case .bigint: return _JSEngine.number(value)
        case .string: return value.string ?? ""
        case .symbol: return _JSEngine.text(value)
        case .date: return Date(timeIntervalSince1970: _JSEngine.number(value) / 1000)
        case .array:
            guard depth < 64 else { return [Any]() }
            let length = max(0, _JSEngine.length(value))
            return (0..<length).map { index -> Any in
                guard case .value(let item) = _JSEngine.get(value, .number(Double(index))) else { return NSNull() }
                return element(item, depth: depth + 1)
            }
        case .object, .function:
            if let swift = _JSEngine.unwrap(value) { return swift }
            guard depth < 64 else { return [AnyHashable: Any]() }
            var entries: [AnyHashable: Any] = [:]
            for key in _JSEngine.keys(value) {
                if case .value(let property) = _JSEngine.get(value, _JSEngine.string(key)) {
                    entries[key] = element(property, depth: depth + 1)
                }
            }
            return entries
        }
    }

    /// An element of an array or a dictionary: undefined becomes `NSNull`, as Foundation's
    /// collections hold no nil.
    private static func element(_ value: _JSHandle, depth: Int) -> Any {
        object(value, depth: depth) ?? NSNull()
    }
    #endif

    // MARK: Properties

    /// The property named `key` (a string, a number or a symbol).
    open func objectForKeyedSubscript(_ key: Any!) -> JSValue! {
        #if os(WASI)
        guard let context else { return nil }
        return context.settle(_JSEngine.get(handle, context.key(for: key)))
        #else
        return nil
        #endif
    }

    /// The element at `index`.
    open func objectAtIndexedSubscript(_ index: Int) -> JSValue! {
        #if os(WASI)
        guard let context else { return nil }
        return context.settle(_JSEngine.get(handle, .number(Double(index))))
        #else
        return nil
        #endif
    }

    /// Sets the property named `key` to `object`, converted.
    open func setObject(_ object: Any!, forKeyedSubscript key: Any!) {
        #if os(WASI)
        guard let context else { return }
        _ = context.settle(_JSEngine.set(handle, context.key(for: key), context.handle(for: object)))
        #endif
    }

    /// Sets the element at `index` to `object`, converted.
    open func setObject(_ object: Any!, atIndexedSubscript index: Int) {
        #if os(WASI)
        guard let context else { return }
        _ = context.settle(_JSEngine.set(handle, .number(Double(index)), context.handle(for: object)))
        #endif
    }

    open func forProperty(_ property: String!) -> JSValue! { objectForKeyedSubscript(property) }
    open func setValue(_ value: Any!, forProperty property: String!) { setObject(value, forKeyedSubscript: property) }
    open func atIndex(_ index: Int) -> JSValue! { objectAtIndexedSubscript(index) }
    open func setValue(_ value: Any!, at index: Int) { setObject(value, atIndexedSubscript: index) }

    /// Deletes the property, giving whether it is gone.
    @discardableResult
    open func deleteProperty(_ property: String!) -> Bool {
        #if os(WASI)
        guard let context else { return false }
        return context.settle(_JSEngine.remove(handle, context.key(for: property))).toBool()
        #else
        return false
        #endif
    }

    /// Whether the value has the property, its own or inherited (`property in value`).
    open func hasProperty(_ property: String!) -> Bool {
        #if os(WASI)
        guard let context else { return false }
        return context.settle(_JSEngine.has(handle, context.key(for: property))).toBool()
        #else
        return false
        #endif
    }

    /// Defines the property from a descriptor (a dictionary of the descriptor keys, or a value).
    open func defineProperty(_ property: String!, descriptor: Any!) {
        #if os(WASI)
        guard let context else { return }
        _ = context.settle(_JSEngine.define(handle, context.key(for: property), context.handle(for: descriptor)))
        #endif
    }

    // MARK: Calling

    /// Calls the value as a function with `arguments`, converted, and undefined as `this`.
    open func call(withArguments arguments: [Any]!) -> JSValue! {
        #if os(WASI)
        guard let context else { return nil }
        return context.settle(_JSEngine.call(handle, this: .undefined, (arguments ?? []).map { context.handle(for: $0) }))
        #else
        return nil
        #endif
    }

    /// Calls the value as a constructor (`new value(...arguments)`).
    open func construct(withArguments arguments: [Any]!) -> JSValue! {
        #if os(WASI)
        guard let context else { return nil }
        return context.settle(_JSEngine.construct(handle, (arguments ?? []).map { context.handle(for: $0) }))
        #else
        return nil
        #endif
    }

    /// Calls the value's method named `method` with `arguments`, converted, and the value as `this`.
    open func invokeMethod(_ method: String!, withArguments arguments: [Any]!) -> JSValue! {
        #if os(WASI)
        guard let context else { return nil }
        return context.settle(_JSEngine.invoke(handle, method ?? "", (arguments ?? []).map { context.handle(for: $0) }))
        #else
        return nil
        #endif
    }

    // MARK: Comparing

    /// Whether the value is `object`, converted, by `===` (NSObject's comparison method on
    /// Apple platforms, which JavaScriptCore's value overrides).
    #if canImport(ObjectiveC)
    open override func isEqual(to object: Any?) -> Bool { strictlyEquals(object) }
    #else
    open func isEqual(to object: Any!) -> Bool { strictlyEquals(object) }
    #endif

    private func strictlyEquals(_ object: Any?) -> Bool {
        #if os(WASI)
        guard let context else { return false }
        return _JSEngine.same(handle, context.handle(for: object))
        #else
        return false
        #endif
    }

    /// Whether the value equals `object`, converted, by `==`.
    open func isEqualWithTypeCoercion(to object: Any!) -> Bool {
        #if os(WASI)
        guard let context else { return false }
        return _JSEngine.loose(handle, context.handle(for: object))
        #else
        return false
        #endif
    }

    /// Whether the value is an instance of the constructor `value` (`instanceof`).
    open func isInstance(of value: Any!) -> Bool {
        #if os(WASI)
        guard let context else { return false }
        return _JSEngine.instance(handle, of: context.handle(for: value))
        #else
        return false
        #endif
    }

    open override var description: String { toString() ?? "undefined" }
}

/// What kind of value a script value is (`typeof`, with arrays, dates and null apart).
enum _JSKind: String {
    case undefined, null, boolean, number, string, symbol, bigint, array, date, function, object
}

// MARK: - Exports

/// The protocol a class's exported members are declared in, for script to call (needs the
/// Objective-C runtime; here no member is exported).
public protocol JSExport {}

// MARK: - Property descriptor keys

public let JSPropertyDescriptorWritableKey = "writable"
public let JSPropertyDescriptorEnumerableKey = "enumerable"
public let JSPropertyDescriptorConfigurableKey = "configurable"
public let JSPropertyDescriptorValueKey = "value"
public let JSPropertyDescriptorGetKey = "get"
public let JSPropertyDescriptorSetKey = "set"
