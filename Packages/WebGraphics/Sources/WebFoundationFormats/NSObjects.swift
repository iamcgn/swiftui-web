// Foundation's object forms of its values on wasm: `NSDictionary` and `NSMutableDictionary`
// (ApolloAPI's JSON values, `json as? NSDictionary`), and `NSURL`, `NSUUID`, `NSLocale`,
// `NSTimeZone`, `NSIndexPath`, `NSIndexSet`, `NSURLComponents`, `NSURLQueryItem`,
// `NSMeasurement` and `NSCalendar` with the bridges that make `nsLocale as Locale` and
// `locale as NSLocale` convert, as on Apple platforms (swift-custom-dump names each one, and
// every TCA app builds it). Also `NSExceptionName`, and for Clendar's packages `NSArray`
// (CVCalendar's weekday symbols, SwiftyFORM) and `NSURLRequest`/`NSMutableURLRequest`
// (SwiftyStoreKit's receipt request).
//
// With the Objective-C runtime, `URL`, `UUID` and `Data` already bridge to the runtime's value
// box (ObjectiveCBridging.swift), so `NSURL`, `NSUUID` and `NSData` are kinds of that box and
// `nsURL as URL` still converts; without it, the box is declared here and each type bridges to
// its own class. In this module rather than WebFoundation, as a bridge keeps its class in every
// bundle that links the module that declares it (decision 0006).
#if os(WASI)
import WebFoundation

#if !canImport(ObjectiveC)
/// The object a dictionary is as Foundation's `NSDictionary` (ObjectiveCBridging.swift declares
/// it with the runtime): its keys as `AnyHashable`, values as `Any`. Equal when the entries are.
open class _WebNSDictionary: NSObject, @unchecked Sendable {
    public var entries: [AnyHashable: Any]
    public init(entries: [AnyHashable: Any]) {
        self.entries = entries
        super.init()
    }
    public override convenience init() { self.init(entries: [:]) }
    public var count: Int { entries.count }
    /// The value for the key, or nil (`object(forKey:)`).
    open subscript(key: Any) -> Any? { (key as? AnyHashable).flatMap { entries[$0] } }
    open override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? _WebNSDictionary else { return false }
        return _webEntriesEqual(entries, other.entries)
    }
    open override var hash: Int { entries.count }
}

/// The object a set is as Foundation's `NSSet` (ObjectiveCBridging.swift declares it with the
/// runtime): its members as `AnyHashable`. Equal when the members are.
open class _WebNSSet: NSObject, ExpressibleByArrayLiteral, @unchecked Sendable {
    public var members: [AnyHashable]
    public init(members: [AnyHashable]) {
        self.members = members
        super.init()
    }
    public override convenience init() { self.init(members: []) }
    public required convenience init(arrayLiteral elements: Any...) { self.init(members: _WebSetMember.distinct(elements)) }
    public var count: Int { members.count }
    open override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? _WebNSSet else { return false }
        return Set(members) == Set(other.members)
    }
    open override var hash: Int { members.count }
}

/// `set as NSSet` and back, as with the runtime (ObjectiveCBridging.swift).
extension Set: @retroactive _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = _WebNSSet
    public func _bridgeToObjectiveC() -> _WebNSSet { _WebNSSet(members: map { AnyHashable($0) }) }
    public static func _forceBridgeFromObjectiveC(_ source: _WebNSSet, result: inout Set<Element>?) {
        guard _conditionallyBridgeFromObjectiveC(source, result: &result) else {
            fatalError("a set's members are not \(Element.self)")
        }
    }
    public static func _conditionallyBridgeFromObjectiveC(_ source: _WebNSSet, result: inout Set<Element>?) -> Bool {
        var converted = Set<Element>(minimumCapacity: source.members.count)
        for member in source.members {
            guard let typed = (member.base as? Element) ?? (member as? Element) else { result = nil; return false }
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

/// The object a value is as one of Foundation's classes (`NSURL`, `NSUUID`, `NSData`).
open class _WebNSValue: NSObject, @unchecked Sendable {
    private let _value: Any
    /// The value this object stands for.
    open var value: Any { _value }
    public init(_ value: Any) {
        _value = value
        super.init()
    }
    public override init() {
        _value = ()
        super.init()
    }
}

/// Whether two dictionaries hold equal entries, as `NSDictionary.isEqual(to:)` compares them.
public func _webEntriesEqual(_ lhs: [AnyHashable: Any], _ rhs: [AnyHashable: Any]) -> Bool {
    guard lhs.count == rhs.count else { return false }
    for (key, value) in lhs {
        guard let other = rhs[key], _webValuesEqual(value, other) else { return false }
    }
    return true
}

/// Whether two values Foundation's collections hold are equal: as hashables, else as objects.
public func _webValuesEqual(_ lhs: Any, _ rhs: Any) -> Bool {
    if let left = lhs as? AnyHashable, let right = rhs as? AnyHashable { return left == right }
    if let left = lhs as? NSObject, let right = rhs as? NSObject { return left.isEqual(right) }
    return false
}
#endif

// MARK: - NSSet

/// A static, unordered collection of distinct objects (a to-many relationship's value in Core
/// Data). `set as NSSet` and `nsSet as? Set<Child>` convert, as on Apple platforms.
public typealias NSSet = _WebNSSet

extension _WebNSSet: Sequence {
    public convenience init(array: [Any]) { self.init(members: _WebSetMember.distinct(array)) }
    public convenience init(object: Any) { self.init(array: [object]) }
    public convenience init(objects: Any...) { self.init(array: objects) }
    public convenience init(set: Set<AnyHashable>) { self.init(members: Array(set)) }
    public convenience init(set: NSSet) { self.init(members: set.members) }
    /// The members, in no particular order.
    public var allObjects: [Any] { members.map(_WebSetMember.value) }
    /// One member, or `nil` when the set is empty.
    public func anyObject() -> Any? { members.first.map(_WebSetMember.value) }
    public func contains(_ anObject: Any) -> Bool { members.contains(_WebSetMember.member(anObject)) }
    /// The member equal to `object`, or `nil`.
    public func member(_ object: Any) -> Any? {
        let key = _WebSetMember.member(object)
        return members.first { $0 == key }.map(_WebSetMember.value)
    }
    public func isSubset(of otherSet: Set<AnyHashable>) -> Bool { members.allSatisfy(otherSet.contains) }
    public func intersects(_ otherSet: Set<AnyHashable>) -> Bool { members.contains(where: otherSet.contains) }
    public func makeIterator() -> IndexingIterator<[Any]> { allObjects.makeIterator() }
}

// MARK: - NSArray

#if !canImport(ObjectiveC)
/// The object an array is as Foundation's `NSArray` (ObjectiveCBridging.swift declares it with
/// the runtime): its elements, each as `Any`.
public final class _WebNSArray: NSObject, @unchecked Sendable {
    public let elements: [Any]
    public init(elements: [Any]) {
        self.elements = elements
        super.init()
    }
    public var count: Int { elements.count }
    /// Equal when the elements are, pair by pair, as Foundation's arrays are (nested arrays too).
    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? _WebNSArray else { return false }
        return other.elements.count == elements.count && zip(elements, other.elements).allSatisfy { _webValuesEqual($0, $1) }
    }
    public override var hash: Int { elements.count }
}

/// `array as NSArray` and `nsArray as? [String]`, as with the runtime (ObjectiveCBridging.swift).
extension Array: @retroactive _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = _WebNSArray
    public func _bridgeToObjectiveC() -> _WebNSArray { _WebNSArray(elements: map { $0 as Any }) }
    public static func _forceBridgeFromObjectiveC(_ source: _WebNSArray, result: inout [Element]?) {
        guard _conditionallyBridgeFromObjectiveC(source, result: &result) else {
            fatalError("an array's elements are not \(Element.self)")
        }
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
        guard let source else { return [] }
        var result: [Element]?
        _forceBridgeFromObjectiveC(source, result: &result)
        return result ?? []
    }
}
#endif

/// A static ordered collection of objects (CVCalendar's weekday symbols, SwiftyFORM's values).
/// `array as NSArray` and `nsArray as! [String]` convert, as on Apple platforms.
public typealias NSArray = _WebNSArray

extension _WebNSArray: Sequence, _WebJSONCollection {
    public convenience init(array: [Any]) { self.init(elements: array) }
    public convenience init(object anObject: Any) { self.init(elements: [anObject]) }
    public convenience init(objects: Any...) { self.init(elements: objects) }

    /// The element at the index; out of range stops, as Foundation raises `NSRangeException`.
    public func object(at index: Int) -> Any {
        precondition(elements.indices.contains(index), "*** -[NSArray objectAtIndex:]: index \(index) beyond bounds [0 .. \(count - 1)]")
        return elements[index]
    }
    public subscript(index: Int) -> Any { object(at: index) }
    public var firstObject: Any? { elements.first }
    public var lastObject: Any? { elements.last }
    public func contains(_ anObject: Any) -> Bool { elements.contains { _webValuesEqual($0, anObject) } }
    /// The lowest index whose element equals the object, or `NSNotFound`.
    public func index(of anObject: Any) -> Int { elements.firstIndex { _webValuesEqual($0, anObject) } ?? NSNotFound }
    /// The elements in the range; a range past the end stops, as Foundation raises.
    public func subarray(with range: NSRange) -> [Any] {
        precondition(range.location >= 0 && range.length >= 0 && range.location + range.length <= count,
                     "*** -[NSArray subarrayWithRange:]: range {\(range.location), \(range.length)} extends beyond bounds [0 .. \(count - 1)]")
        return Array(elements[range.location..<(range.location + range.length)])
    }
    /// A new array of these elements followed by the object.
    public func adding(_ anObject: Any) -> [Any] { elements + [anObject] }
    /// A new array of these elements followed by the other array's.
    public func addingObjects(from otherArray: [Any]) -> [Any] { elements + otherArray }
    /// The elements' descriptions joined by the separator.
    public func componentsJoined(by separator: String) -> String { elements.map { "\($0)" }.joined(separator: separator) }
    // `@objc` with the runtime, as Foundation's is, so a call on `AnyObject` finds it: AcknowList
    // filters an `[AnyObject]` plist with `item.isEqual(to: headerItem)`.
    #if canImport(ObjectiveC)
    @objc public func isEqual(to otherArray: [Any]) -> Bool { _webIsEqual(to: otherArray) }
    #else
    public func isEqual(to otherArray: [Any]) -> Bool { _webIsEqual(to: otherArray) }
    #endif
    private func _webIsEqual(to otherArray: [Any]) -> Bool {
        otherArray.count == elements.count && zip(elements, otherArray).allSatisfy { _webValuesEqual($0, $1) }
    }
    public func makeIterator() -> IndexingIterator<[Any]> { elements.makeIterator() }
    public var _webJSONValue: Any { elements }
}

// MARK: - NSDictionary

/// A static collection of objects associated with unique keys.
public typealias NSDictionary = _WebNSDictionary

extension _WebNSDictionary: Sequence, _WebJSONCollection {
    public var _webJSONValue: Any { entries }
    public convenience init(dictionary otherDictionary: [AnyHashable: Any]) { self.init(entries: otherDictionary) }
    public convenience init(object: Any, forKey key: AnyHashable) { self.init(entries: [key: object]) }
    public convenience init(objects: [Any], forKeys keys: [AnyHashable]) {
        var entries: [AnyHashable: Any] = [:]
        for (key, object) in zip(keys, objects) { entries[key] = object }
        self.init(entries: entries)
    }

    public var allKeys: [Any] { entries.keys.map { $0.base } }
    public var allValues: [Any] { Array(entries.values) }
    /// The value for the key, or nil.
    public func object(forKey aKey: Any) -> Any? { (aKey as? AnyHashable).flatMap { entries[$0] } }
    /// The keys whose value is `anObject`.
    public func allKeys(for anObject: Any) -> [Any] {
        entries.filter { _webValuesEqual($0.value, anObject) }.map { $0.key.base }
    }
    // `@objc` with the runtime, as Foundation's is, so a call on `AnyObject` finds it (AcknowList's
    // `item.isEqual(to: headerItem)` with a `[String: String]`).
    #if canImport(ObjectiveC)
    @objc public func isEqual(to otherDictionary: [AnyHashable: Any]) -> Bool { _webEntriesEqual(entries, otherDictionary) }
    #else
    public func isEqual(to otherDictionary: [AnyHashable: Any]) -> Bool { _webEntriesEqual(entries, otherDictionary) }
    #endif
    /// Calls the block with each key and value; setting `stop` ends the walk.
    public func enumerateKeysAndObjects(_ block: (Any, Any, UnsafeMutablePointer<Bool>) -> Void) {
        var stop = false
        for (key, value) in entries {
            block(key.base, value, &stop)
            if stop { return }
        }
    }

    /// The entries as Foundation's `NSDictionary` iterates them: each key and value as `Any`.
    public struct Iterator: IteratorProtocol {
        var base: Dictionary<AnyHashable, Any>.Iterator
        public mutating func next() -> (key: Any, value: Any)? {
            base.next().map { (key: $0.key.base, value: $0.value) }
        }
    }
    public func makeIterator() -> Iterator { Iterator(base: entries.makeIterator()) }
}

/// A dynamic collection of objects associated with unique keys.
open class NSMutableDictionary: _WebNSDictionary, ExpressibleByDictionaryLiteral, @unchecked Sendable {
    public convenience init(capacity numItems: Int) { self.init(entries: Dictionary(minimumCapacity: numItems)) }
    /// `let body: NSMutableDictionary = ["receipt-data": receipt]` (SwiftyStoreKit).
    public required convenience init(dictionaryLiteral elements: (Any, Any)...) {
        var entries: [AnyHashable: Any] = [:]
        for (key, value) in elements {
            guard let key = key as? AnyHashable else { preconditionFailure("an NSDictionary key must be hashable, not \(type(of: key))") }
            entries[key] = value
        }
        self.init(entries: entries)
    }

    // A dictionary's key-value coding is its entries: a value sets or (nil) removes the key's.
    #if canImport(ObjectiveC)
    open override func setValue(_ value: Any?, forKey key: String) { entries[key] = value }
    open override func value(forKey key: String) -> Any? { entries[key] }
    #else
    open func setValue(_ value: Any?, forKey key: String) { entries[key] = value }
    open func value(forKey key: String) -> Any? { entries[key] }
    #endif

    open func setObject(_ anObject: Any, forKey aKey: AnyHashable) { entries[aKey] = anObject }
    open func removeObject(forKey aKey: Any) {
        if let key = aKey as? AnyHashable { entries[key] = nil }
    }
    open func removeAllObjects() { entries.removeAll() }
    open func removeObjects(forKeys keyArray: [Any]) { keyArray.forEach(removeObject(forKey:)) }
    open func addEntries(from otherDictionary: [AnyHashable: Any]) { entries.merge(otherDictionary) { _, new in new } }
    open func setDictionary(_ otherDictionary: [AnyHashable: Any]) { entries = otherDictionary }
    open override subscript(key: Any) -> Any? {
        get { (key as? AnyHashable).flatMap { entries[$0] } }
        set {
            guard let key = key as? AnyHashable else { return }
            entries[key] = newValue
        }
    }
}

// MARK: - Values as objects

/// A Foundation class that holds one value of its bridged type.
public protocol _WebValueObject: AnyObject {
    associatedtype Value
    var _webValue: Value { get }
    init(_webValue: Value)
}

/// A value that bridges to its Foundation class.
public protocol _WebObjectBridged: _ObjectiveCBridgeable where _ObjectiveCType: _WebValueObject, _ObjectiveCType.Value == Self {}

extension _WebObjectBridged {
    public func _bridgeToObjectiveC() -> _ObjectiveCType { _ObjectiveCType(_webValue: self) }
    public static func _forceBridgeFromObjectiveC(_ source: _ObjectiveCType, result: inout Self?) { result = source._webValue }
    public static func _conditionallyBridgeFromObjectiveC(_ source: _ObjectiveCType, result: inout Self?) -> Bool {
        result = source._webValue
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: _ObjectiveCType?) -> Self { source!._webValue }
}

/// A URL as an object.
public final class NSURL: _WebNSValue, _WebValueObject, @unchecked Sendable {
    public init(_webValue: URL) { super.init(_webValue) }
    public var _webValue: URL { value as! URL }
    public convenience init?(string URLString: String) {
        guard let url = URL(string: URLString) else { return nil }
        self.init(_webValue: url)
    }
    public convenience init(fileURLWithPath path: String) { self.init(_webValue: URL(fileURLWithPath: path)) }
    #if canImport(ObjectiveC)
    // `@objc`, as on Apple, so a key path can run through a URL: Hipstapaper's
    // `#keyPath(CD_Website.cd_resolvedURL.absoluteString)` in an `NSPredicate`.
    @objc public var absoluteString: String? { _webValue.absoluteString }
    @objc public var absoluteURL: URL? { _webValue.absoluteURL }
    @objc public var path: String? { _webValue.path }
    @objc public var scheme: String? { _webValue.scheme }
    @objc public var host: String? { _webValue.host }
    @objc public var lastPathComponent: String? { _webValue.lastPathComponent }
    @objc public var isFileURL: Bool { _webValue.isFileURL }
    #else
    public var absoluteString: String? { _webValue.absoluteString }
    public var absoluteURL: URL? { _webValue.absoluteURL }
    public var path: String? { _webValue.path }
    public var scheme: String? { _webValue.scheme }
    public var host: String? { _webValue.host }
    public var lastPathComponent: String? { _webValue.lastPathComponent }
    public var isFileURL: Bool { _webValue.isFileURL }
    #endif
    public override func isEqual(_ object: Any?) -> Bool { (object as? NSURL)?._webValue == _webValue }
    public override var hash: Int { _webValue.hashValue }
}

/// A URL load request as an object, the request `URLRequest` bridges to; `NSMutableURLRequest`
/// changes it (SwiftyStoreKit's receipt validation builds one and passes it `as URLRequest`).
open class NSURLRequest: NSObject, @unchecked Sendable {
    /// The cache policies, by the name Foundation declares them under (`URLRequest.CachePolicy`
    /// is its alias there): OAuth2's `cachePolicy: NSURLRequest.CachePolicy` parameter.
    public typealias CachePolicy = URLRequest.CachePolicy
    /// The request this object holds.
    public fileprivate(set) var _webValue: URLRequest
    public init(_webValue: URLRequest) {
        self._webValue = _webValue
        super.init()
    }
    public convenience init(url URL: URL) { self.init(_webValue: URLRequest(url: URL)) }
    public convenience init(url URL: URL, cachePolicy: URLRequest.CachePolicy, timeoutInterval: TimeInterval) {
        self.init(_webValue: URLRequest(url: URL, cachePolicy: cachePolicy, timeoutInterval: timeoutInterval))
    }
    open var url: URL? { _webValue.url }
    open var cachePolicy: URLRequest.CachePolicy { _webValue.cachePolicy }
    open var timeoutInterval: TimeInterval { _webValue.timeoutInterval }
    open var httpMethod: String? { _webValue.httpMethod }
    open var allHTTPHeaderFields: [String: String]? { _webValue.allHTTPHeaderFields }
    open var httpBody: Data? { _webValue.httpBody }
    open var mainDocumentURL: URL? { _webValue.mainDocumentURL }
    open var httpShouldHandleCookies: Bool { _webValue.httpShouldHandleCookies }
    open var allowsCellularAccess: Bool { _webValue.allowsCellularAccess }
    open func value(forHTTPHeaderField field: String) -> String? { _webValue.value(forHTTPHeaderField: field) }
    open override func isEqual(_ object: Any?) -> Bool { (object as? NSURLRequest)?._webValue == _webValue }
    open override var hash: Int { _webValue.hashValue }
}

/// A URL load request whose URL, method, headers and body can change.
open class NSMutableURLRequest: NSURLRequest, @unchecked Sendable {
    open override var url: URL? {
        get { _webValue.url }
        set { _webValue.url = newValue }
    }
    open override var cachePolicy: URLRequest.CachePolicy {
        get { _webValue.cachePolicy }
        set { _webValue.cachePolicy = newValue }
    }
    open override var timeoutInterval: TimeInterval {
        get { _webValue.timeoutInterval }
        set { _webValue.timeoutInterval = newValue }
    }
    /// The method, "GET" unless set (not optional here, as in Foundation).
    open override var httpMethod: String {
        get { _webValue.httpMethod ?? "GET" }
        set { _webValue.httpMethod = newValue }
    }
    open override var allHTTPHeaderFields: [String: String]? {
        get { _webValue.allHTTPHeaderFields }
        set { _webValue.allHTTPHeaderFields = newValue }
    }
    open override var httpBody: Data? {
        get { _webValue.httpBody }
        set { _webValue.httpBody = newValue }
    }
    open override var mainDocumentURL: URL? {
        get { _webValue.mainDocumentURL }
        set { _webValue.mainDocumentURL = newValue }
    }
    open override var httpShouldHandleCookies: Bool {
        get { _webValue.httpShouldHandleCookies }
        set { _webValue.httpShouldHandleCookies = newValue }
    }
    open override var allowsCellularAccess: Bool {
        get { _webValue.allowsCellularAccess }
        set { _webValue.allowsCellularAccess = newValue }
    }
    open func setValue(_ value: String?, forHTTPHeaderField field: String) { _webValue.setValue(value, forHTTPHeaderField: field) }
    open func addValue(_ value: String, forHTTPHeaderField field: String) { _webValue.addValue(value, forHTTPHeaderField: field) }
}

/// `request as NSURLRequest` and `mutableRequest as URLRequest`, as on Apple platforms.
extension URLRequest: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSURLRequest
    public func _bridgeToObjectiveC() -> NSURLRequest { NSURLRequest(_webValue: self) }
    public static func _forceBridgeFromObjectiveC(_ source: NSURLRequest, result: inout URLRequest?) { result = source._webValue }
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSURLRequest, result: inout URLRequest?) -> Bool {
        result = source._webValue
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSURLRequest?) -> URLRequest { source!._webValue }
}

/// A universally unique value as an object.
public final class NSUUID: _WebNSValue, _WebValueObject, @unchecked Sendable {
    public init(_webValue: UUID) { super.init(_webValue) }
    public var _webValue: UUID { value as! UUID }
    public override convenience init() { self.init(_webValue: UUID()) }
    public convenience init?(uuidString string: String) {
        guard let uuid = UUID(uuidString: string) else { return nil }
        self.init(_webValue: uuid)
    }
    /// A UUID from its 16 bytes (RevenueCat reads one out of `Data` this way).
    public convenience init(uuidBytes bytes: UnsafePointer<UInt8>!) {
        let b = UnsafeBufferPointer(start: bytes, count: 16)
        self.init(_webValue: UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                                         b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])))
    }
    public var uuidString: String { _webValue.uuidString }
    /// Copies the UUID's 16 bytes into `uuid` (Objective-C's `getUUIDBytes:`).
    public func getBytes(_ uuid: UnsafeMutablePointer<UInt8>!) {
        withUnsafeBytes(of: _webValue.uuid) { raw in
            for i in 0..<16 { uuid[i] = raw[i] }
        }
    }
    public override func isEqual(_ object: Any?) -> Bool { (object as? NSUUID)?._webValue == _webValue }
    public override var hash: Int { _webValue.hashValue }
}

extension URL: _WebObjectBridged { public typealias _ObjectiveCType = NSURL }
extension UUID: @retroactive _ObjectiveCBridgeable, _WebObjectBridged { public typealias _ObjectiveCType = NSUUID }

/// A locale as an object.
public final class NSLocale: NSObject, _WebValueObject, @unchecked Sendable {
    public let _webValue: Locale
    public init(_webValue: Locale) {
        self._webValue = _webValue
        super.init()
    }
    public convenience init(localeIdentifier string: String) { self.init(_webValue: Locale(identifier: string)) }
    public var localeIdentifier: String { _webValue.identifier }
    public class var current: Locale { Locale.current }
    public class var autoupdatingCurrent: Locale { Locale.autoupdatingCurrent }
    public typealias LanguageDirection = Locale.LanguageDirection
    public class func characterDirection(forLanguage isoLangCode: String) -> LanguageDirection { Locale.characterDirection(forLanguage: isoLangCode) }
    public class func lineDirection(forLanguage isoLangCode: String) -> LanguageDirection { Locale.lineDirection(forLanguage: isoLangCode) }
    public override func isEqual(_ object: Any?) -> Bool { (object as? NSLocale)?._webValue == _webValue }
    public override var hash: Int { _webValue.hashValue }
}
extension Locale: _WebObjectBridged { public typealias _ObjectiveCType = NSLocale }

/// A time zone as an object.
public final class NSTimeZone: NSObject, _WebValueObject, @unchecked Sendable {
    public let _webValue: TimeZone
    public init(_webValue: TimeZone) {
        self._webValue = _webValue
        super.init()
    }
    public convenience init?(name tzName: String) {
        guard let zone = TimeZone(identifier: tzName) else { return nil }
        self.init(_webValue: zone)
    }
    public convenience init(forSecondsFromGMT seconds: Int) { self.init(_webValue: TimeZone(secondsFromGMT: seconds) ?? .current) }
    public var name: String { _webValue.identifier }
    public var secondsFromGMT: Int { _webValue.secondsFromGMT() }
    public class var local: TimeZone { TimeZone.current }
    public class var system: TimeZone { TimeZone.current }
    public override func isEqual(_ object: Any?) -> Bool { (object as? NSTimeZone)?._webValue == _webValue }
    public override var hash: Int { _webValue.hashValue }
}
extension TimeZone: _WebObjectBridged { public typealias _ObjectiveCType = NSTimeZone }

/// An index path as an object.
public final class NSIndexPath: NSObject, _WebValueObject, @unchecked Sendable {
    public let _webValue: IndexPath
    public init(_webValue: IndexPath) {
        self._webValue = _webValue
        super.init()
    }
    public convenience init(index: Int) { self.init(_webValue: IndexPath(index: index)) }
    public convenience init(indexes: [Int]) { self.init(_webValue: IndexPath(indexes: indexes)) }
    public convenience init(row: Int, section: Int) { self.init(_webValue: IndexPath(indexes: [section, row])) }
    public convenience init(item: Int, section: Int) { self.init(_webValue: IndexPath(indexes: [section, item])) }
    public var length: Int { _webValue.count }
    public func index(atPosition position: Int) -> Int { _webValue[position] }
    public var section: Int { _webValue.count > 0 ? _webValue[0] : NSNotFound }
    public var row: Int { _webValue.count > 1 ? _webValue[1] : NSNotFound }
    public var item: Int { row }
    public override func isEqual(_ object: Any?) -> Bool { (object as? NSIndexPath)?._webValue == _webValue }
    public override var hash: Int { _webValue.hashValue }
}
extension IndexPath: _WebObjectBridged { public typealias _ObjectiveCType = NSIndexPath }

/// An index set as an object.
public final class NSIndexSet: NSObject, _WebValueObject, @unchecked Sendable {
    public let _webValue: IndexSet
    public init(_webValue: IndexSet) {
        self._webValue = _webValue
        super.init()
    }
    public convenience init(index value: Int) { self.init(_webValue: IndexSet(integer: value)) }
    public convenience init(indexesIn range: NSRange) {
        self.init(_webValue: IndexSet(integersIn: range.location..<(range.location + range.length)))
    }
    public override convenience init() { self.init(_webValue: IndexSet()) }
    public var count: Int { _webValue.count }
    public var firstIndex: Int { _webValue.first ?? NSNotFound }
    public var lastIndex: Int { _webValue.last ?? NSNotFound }
    public func contains(_ value: Int) -> Bool { _webValue.contains(value) }
    public override func isEqual(_ object: Any?) -> Bool { (object as? NSIndexSet)?._webValue == _webValue }
    public override var hash: Int { _webValue.hashValue }
}
extension IndexSet: _WebObjectBridged { public typealias _ObjectiveCType = NSIndexSet }

/// A URL's parts as an object.
public final class NSURLComponents: NSObject, _WebValueObject, @unchecked Sendable {
    public let _webValue: URLComponents
    public init(_webValue: URLComponents) {
        self._webValue = _webValue
        super.init()
    }
    public convenience init?(string URLString: String) {
        guard let components = URLComponents(string: URLString) else { return nil }
        self.init(_webValue: components)
    }
    public var url: URL? { _webValue.url }
    public var string: String? { _webValue.string }
    public override func isEqual(_ object: Any?) -> Bool { (object as? NSURLComponents)?._webValue == _webValue }
    public override var hash: Int { _webValue.hashValue }
}
extension URLComponents: _WebObjectBridged { public typealias _ObjectiveCType = NSURLComponents }

/// A query item as an object.
public final class NSURLQueryItem: NSObject, _WebValueObject, @unchecked Sendable {
    public let _webValue: URLQueryItem
    public init(_webValue: URLQueryItem) {
        self._webValue = _webValue
        super.init()
    }
    public convenience init(name: String, value: String?) { self.init(_webValue: URLQueryItem(name: name, value: value)) }
    public var name: String { _webValue.name }
    public var value: String? { _webValue.value }
    public override func isEqual(_ object: Any?) -> Bool { (object as? NSURLQueryItem)?._webValue == _webValue }
    public override var hash: Int { _webValue.hashValue }
}
extension URLQueryItem: _WebObjectBridged { public typealias _ObjectiveCType = NSURLQueryItem }

/// A measurement as an object: its amount and unit.
public final class NSMeasurement: NSObject, @unchecked Sendable {
    public let doubleValue: Double
    public let unit: Unit
    public init(doubleValue: Double, unit: Unit) {
        self.doubleValue = doubleValue
        self.unit = unit
        super.init()
    }
    public override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? NSMeasurement else { return false }
        return other.doubleValue == doubleValue && other.unit == unit
    }
    public override var hash: Int { doubleValue.hashValue }
}

extension Measurement: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSMeasurement
    public func _bridgeToObjectiveC() -> NSMeasurement { NSMeasurement(doubleValue: value, unit: unit) }
    public static func _forceBridgeFromObjectiveC(_ source: NSMeasurement, result: inout Measurement?) {
        guard _conditionallyBridgeFromObjectiveC(source, result: &result) else {
            fatalError("an NSMeasurement's unit is not \(UnitType.self)")
        }
    }
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSMeasurement, result: inout Measurement?) -> Bool {
        guard let unit = source.unit as? UnitType else {
            result = nil
            return false
        }
        result = Measurement(value: source.doubleValue, unit: unit)
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSMeasurement?) -> Measurement {
        var result: Measurement?
        _forceBridgeFromObjectiveC(source!, result: &result)
        return result!
    }
}

extension Calendar: _ObjectiveCBridgeable {
    public typealias _ObjectiveCType = NSCalendar
    public func _bridgeToObjectiveC() -> NSCalendar { NSCalendar(_webValue: self) }
    public static func _forceBridgeFromObjectiveC(_ source: NSCalendar, result: inout Calendar?) { result = source._webValue }
    public static func _conditionallyBridgeFromObjectiveC(_ source: NSCalendar, result: inout Calendar?) -> Bool {
        result = source._webValue
        return true
    }
    public static func _unconditionallyBridgeFromObjectiveC(_ source: NSCalendar?) -> Calendar { source?._webValue ?? .current }
}

// MARK: - NSExceptionName

/// The name of an exception (Foundation's string-backed constant type).
public struct NSExceptionName: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public static let genericException = NSExceptionName("NSGenericException")
    public static let rangeException = NSExceptionName("NSRangeException")
    public static let invalidArgumentException = NSExceptionName("NSInvalidArgumentException")
    public static let internalInconsistencyException = NSExceptionName("NSInternalInconsistencyException")
    public static let mallocException = NSExceptionName("NSMallocException")
    public static let objectInaccessibleException = NSExceptionName("NSObjectInaccessibleException")
    public static let objectNotAvailableException = NSExceptionName("NSObjectNotAvailableException")
    public static let destinationInvalidException = NSExceptionName("NSDestinationInvalidException")
    public static let portTimeoutException = NSExceptionName("NSPortTimeoutException")
    public static let invalidSendPortException = NSExceptionName("NSInvalidSendPortException")
    public static let invalidReceivePortException = NSExceptionName("NSInvalidReceivePortException")
    public static let portSendException = NSExceptionName("NSPortSendException")
    public static let portReceiveException = NSExceptionName("NSPortReceiveException")
    public static let characterConversionException = NSExceptionName("NSCharacterConversionException")
    public static let fileHandleOperationException = NSExceptionName("NSFileHandleOperationException")
    public static let undefinedKeyException = NSExceptionName("NSUnknownKeyException")
}

// MARK: - NSException

/// An exception: a name, a reason and user info (swift-custom-dump prints one, crash reporters
/// install an uncaught-exception handler). Raising one hands it to that handler and stops the
/// program, as an uncaught Objective-C exception does: a page has no `@try` to catch it.
open class NSException: NSObject, @unchecked Sendable {
    private let _name: NSExceptionName
    private let _reason: String?
    private let _userInfo: [AnyHashable: Any]?

    public init(name aName: NSExceptionName, reason aReason: String?, userInfo aUserInfo: [AnyHashable: Any]? = nil) {
        _name = aName
        _reason = aReason
        _userInfo = aUserInfo
        super.init()
    }

    open var name: NSExceptionName { _name }
    open var reason: String? { _reason }
    open var userInfo: [AnyHashable: Any]? { _userInfo }
    /// The return addresses and symbols of the stack it was raised on: none here, as wasm
    /// cannot walk its own stack.
    open var callStackReturnAddresses: [NSNumber] { [] }
    open var callStackSymbols: [String] { [] }

    open override var description: String { reason ?? name.rawValue }

    /// Hands the exception to the uncaught-exception handler, then stops the program.
    open func raise() {
        _uncaughtExceptionHandler?(self)
        fatalError("*** Terminating app due to uncaught exception '\(name.rawValue)', reason: '\(reason ?? "")'")
    }

    /// Raises an exception with the name and the format as its reason.
    open class func raise(_ name: NSExceptionName, format: String, arguments argList: CVaListPointer) {
        NSException(name: name, reason: format, userInfo: nil).raise()
    }
}

/// What runs with an exception nobody caught, before the program stops.
public typealias NSUncaughtExceptionHandler = (NSException) -> Void

nonisolated(unsafe) private var _uncaughtExceptionHandler: NSUncaughtExceptionHandler?

/// Sets the handler a raised exception is handed to (crash reporters log it there).
public func NSSetUncaughtExceptionHandler(_ handler: NSUncaughtExceptionHandler?) { _uncaughtExceptionHandler = handler }

/// The handler set with `NSSetUncaughtExceptionHandler`, if any.
public func NSGetUncaughtExceptionHandler() -> NSUncaughtExceptionHandler? { _uncaughtExceptionHandler }
#endif
