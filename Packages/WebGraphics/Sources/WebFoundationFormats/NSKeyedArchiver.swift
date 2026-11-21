// NSKeyedArchiver and NSKeyedUnarchiver on wasm: an object graph to and from the keyed archive
// format Apple's write, a property list with `$archiver`, `$version`, `$top` and `$objects`, in
// which each object is a dictionary of its keys plus a `$class` reference, and references are
// UIDs (binary marker 0x8, or a `CF$UID` dictionary in XML). Apps keep NSCoding objects in user
// defaults this way (IceCubes stores its theme's UIColors as base64 archives). Strings, numbers,
// data, dates, URLs, UUIDs, arrays, dictionaries and sets are written as Foundation's NS classes
// write them; any other object must conform to NSCoding. A class is archived under the name
// `NSStringFromClass` gives it ("Module.Class"; the framework's own classes, such as UIColor,
// under their bare Apple names) and found again by that name through Swift's type metadata.
// The coders live here, in WebFoundationFormats, and not in WebFoundation: a class keeps its
// methods in every bundle that links its module (decision 0006's budget), and a SwiftUI app that
// never archives would carry them. `import Foundation` re-exports this module; `import SwiftUI`
// does with the FoundationFormats trait, which Tools/Traits turns on for an app that names them.
// Not done: conditional objects (encoded as ordinary ones), cycles (an object that refers back
// to one still decoding reads nil there), delegates, and `Codable` values in an archive.
#if os(WASI)
import WebFoundation

/// The key the root object of an archive is stored under.
public let NSKeyedArchiveRootObjectKey = "root"

/// Foundation's coder error codes (NSCocoaErrorDomain).
let _coderReadCorruptError = 4864
let _coderValueNotFoundError = 4865
let _coderInvalidValueError = 4866

func _coderError(_ code: Int, _ message: String) -> NSError {
    NSError(domain: NSCocoaErrorDomain, code: code, userInfo: [NSDebugDescriptionErrorKey: message])
}

/// A UID, as a keyed archive stores references.
private func _uid(_ index: Int) -> _PlistValue { .dictionary([("CF$UID", .integer(Int64(index)))]) }

/// The names classes are archived under.
enum _ArchiveNames {
    /// Modules whose classes are archived under their bare names, as Apple's own classes are.
    static let frameworkModules = ["UIKitWebCore", "UIKitWeb", "WebFoundation", "WebFoundationFormats",
                                   "SwiftFoundation", "SwiftUIWebCore", "WebGraphics", "MapKit", "CoreLocation", "ObjectiveC"]
    nonisolated(unsafe) static var namesByClass: [ObjectIdentifier: String] = [:]
    nonisolated(unsafe) static var classesByName: [String: AnyClass] = [:]

    static func name(of cls: AnyClass) -> String {
        if let name = namesByClass[ObjectIdentifier(cls)] { return name }
        let qualified = _typeName(cls, qualified: true)
        for module in frameworkModules where qualified.hasPrefix(module + ".") {
            return String(qualified.dropFirst(module.count + 1))
        }
        return qualified
    }

    /// The class and its superclasses, by name, ending with NSObject as Apple's do.
    static func hierarchy(of cls: AnyClass) -> [String] {
        var names: [String] = []
        var current: AnyClass? = cls
        while let next = current {
            names.append(name(of: next))
            current = _getSuperclass(next)
        }
        if names.last != "NSObject" { names.append("NSObject") }
        return names
    }

    /// The class Swift knows by an archived name: one set for it, else the name itself, else
    /// the name in one of the framework modules.
    static func lookup(_ name: String, extra: [String: AnyClass]) -> AnyClass? {
        if let cls = extra[name] ?? classesByName[name] { return cls }
        if let cls = _typeByName(name) as? AnyClass { return cls }
        for module in frameworkModules {
            if let cls = _typeByName(module + "." + name) as? AnyClass { return cls }
        }
        return nil
    }
}

/// An encoder that stores an object's data in a keyed archive.
public final class NSKeyedArchiver: NSCoder {
    /// Whether every object archived must adopt NSSecureCoding.
    public var requiresSecureCoding: Bool
    /// The format the archive is written in: binary, as Apple's default.
    public var outputFormat: PropertyListSerialization.PropertyListFormat = .binary

    private var objects: [_PlistValue] = [.string("$null")]
    private var identities: [ObjectIdentifier: Int] = [:]
    private var classIndices: [String: Int] = [:]
    private var containers: [[(key: String, value: _PlistValue)]] = [[]]
    private var classNames: [ObjectIdentifier: String] = [:]
    private var finished: Data?
    /// The first value that could not be archived.
    var _failure: NSError?

    /// An archiver for an archive that `encodedData` returns.
    public init(requiringSecureCoding requiresSecureCoding: Bool) {
        self.requiresSecureCoding = requiresSecureCoding
        super.init()
    }

    @available(*, deprecated, message: "Use init(requiringSecureCoding:) instead")
    public override convenience init() {
        self.init(requiringSecureCoding: false)
    }

    /// The archive of `object`, as the root object.
    public class func archivedData(withRootObject object: Any, requiringSecureCoding requiresSecureCoding: Bool) throws -> Data {
        let archiver = NSKeyedArchiver(requiringSecureCoding: requiresSecureCoding)
        archiver.encode(object, forKey: NSKeyedArchiveRootObjectKey)
        let data = archiver.encodedData
        if let failure = archiver._failure { throw failure }
        return data
    }

    @available(*, deprecated, message: "Use archivedData(withRootObject:requiringSecureCoding:) instead")
    public class func archivedData(withRootObject rootObject: Any) -> Data {
        (try? archivedData(withRootObject: rootObject, requiringSecureCoding: false)) ?? Data()
    }

    /// The name `cls` is archived under, by every archiver.
    public class func setClassName(_ codedName: String?, for cls: AnyClass) {
        _ArchiveNames.namesByClass[ObjectIdentifier(cls)] = codedName
    }

    public class func className(for cls: AnyClass) -> String? { _ArchiveNames.namesByClass[ObjectIdentifier(cls)] }

    /// The name `cls` is archived under by this archiver.
    public func setClassName(_ codedName: String?, for cls: AnyClass) {
        classNames[ObjectIdentifier(cls)] = codedName
    }

    public func className(for cls: AnyClass) -> String? { classNames[ObjectIdentifier(cls)] }

    /// The archive written so far, finished.
    public var encodedData: Data {
        finishEncoding()
        return finished ?? Data()
    }

    /// Ends the archive: values encoded after this are not in it.
    public func finishEncoding() {
        guard finished == nil else { return }
        let archive: _PlistValue = .dictionary([
            ("$version", .integer(100000)),
            ("$archiver", .string("NSKeyedArchiver")),
            ("$top", .dictionary(containers[0])),
            ("$objects", .array(objects)),
        ])
        switch outputFormat {
        case .xml: finished = Data(_PlistXML.write(archive).utf8)
        default: finished = Data(_PlistBinary.write(archive))
        }
    }

    // MARK: Encoding

    private func set(_ value: _PlistValue, forKey key: String) {
        guard finished == nil else { return }
        containers[containers.count - 1].append((key, value))
    }

    public override func encode(_ object: Any?, forKey key: String) { set(reference(object), forKey: key) }
    public override func encode(_ value: Bool, forKey key: String) { set(.bool(value), forKey: key) }
    public override func encode(_ value: Int, forKey key: String) { set(.integer(Int64(value)), forKey: key) }
    public override func encode(_ value: Int32, forKey key: String) { set(.integer(Int64(value)), forKey: key) }
    public override func encode(_ value: Int64, forKey key: String) { set(.integer(value), forKey: key) }
    public override func encode(_ value: Double, forKey key: String) { set(.real(value), forKey: key) }
    public override func encode(_ value: Float, forKey key: String) { set(.real(Double(value)), forKey: key) }

    private func append(_ value: _PlistValue) -> Int {
        objects.append(value)
        return objects.count - 1
    }

    private func classReference(_ name: String, _ hierarchy: [String]) -> _PlistValue {
        if let index = classIndices[name] { return _uid(index) }
        let index = append(.dictionary([("$classes", .array(hierarchy.map(_PlistValue.string))), ("$classname", .string(name))]))
        classIndices[name] = index
        return _uid(index)
    }

    /// An object written the way Foundation's class `name` writes itself.
    private func foundationObject(_ name: String, _ entries: [(key: String, value: _PlistValue)]) -> _PlistValue {
        _uid(append(.dictionary(entries + [("$class", classReference(name, [name, "NSObject"]))])))
    }

    private func fail(_ message: String) {
        if _failure == nil { _failure = _coderError(_coderInvalidValueError, message) }
    }

    /// A reference to `object`, archived on first use.
    private func reference(_ object: Any?) -> _PlistValue {
        guard let object = _unwrapped(object) else { return _uid(0) }
        switch object {
        case let string as String: return _uid(append(.string(string)))
        case let string as Substring: return _uid(append(.string(String(string))))
        case is Bool, is NSNumber, is Int, is Int8, is Int16, is Int32, is Int64,
             is UInt, is UInt8, is UInt16, is UInt32, is UInt64, is Double, is Float:
            guard let value = try? _PlistValue(object) else { break }
            return _uid(append(value))
        case let data as Data: return _uid(append(.data(Array(data))))
        case let date as Date: return foundationObject("NSDate", [("NS.time", .real(date.timeIntervalSinceReferenceDate))])
        case let url as URL: return foundationObject("NSURL", [("NS.base", _uid(0)), ("NS.relative", reference(url.absoluteString))])
        case let uuid as UUID:
            let bytes = withUnsafeBytes(of: uuid.uuid) { Array($0) }
            return foundationObject("NSUUID", [("NS.uuidbytes", .data(bytes))])
        case let array as [Any]: return foundationObject("NSArray", [("NS.objects", .array(array.map(reference)))])
        case let set as Set<AnyHashable>: return foundationObject("NSSet", [("NS.objects", .array(set.map { reference($0.base) }))])
        case let dictionary as [AnyHashable: Any]:
            let entries = Array(dictionary)
            return foundationObject("NSDictionary", [("NS.keys", .array(entries.map { reference($0.key.base) })),
                                                     ("NS.objects", .array(entries.map { reference($0.value) }))])
        case let coding as any NSCoding:
            guard type(of: coding) is AnyClass else { break }
            let instance = coding as AnyObject
            let cls: AnyClass = type(of: instance)
            if let index = identities[ObjectIdentifier(instance)] { return _uid(index) }
            if requiresSecureCoding, (cls as? any NSSecureCoding.Type)?.supportsSecureCoding != true {
                fail("This coder requires that objects conform to NSSecureCoding: \(_ArchiveNames.name(of: cls))")
                return _uid(0)
            }
            let index = append(.string("$null"))
            identities[ObjectIdentifier(instance)] = index
            containers.append([])
            coding.encode(with: self)
            let entries = containers.removeLast()
            let name = classNames[ObjectIdentifier(cls)] ?? _ArchiveNames.name(of: cls)
            var hierarchy = _ArchiveNames.hierarchy(of: cls)
            hierarchy[0] = name
            objects[index] = .dictionary(entries + [("$class", classReference(name, hierarchy))])
            return _uid(index)
        default: break
        }
        fail("The object of type \(_typeName(type(of: object))) does not conform to NSCoding")
        return _uid(0)
    }
}

/// `object` without the optionals an `Any?` may wrap around it, or nil for none.
func _unwrapped(_ object: Any?) -> Any? {
    guard let object else { return nil }
    let mirror = Mirror(reflecting: object)
    guard mirror.displayStyle == .optional else { return object }
    guard let wrapped = mirror.children.first?.value else { return nil }
    return _unwrapped(wrapped)
}

/// A decoder that restores the objects of a keyed archive.
public final class NSKeyedUnarchiver: NSCoder {
    /// What the unarchiver does when a value can't be decoded: it records the error either way,
    /// as there is no Objective-C exception to raise.
    public enum DecodingFailurePolicy: Int, Sendable {
        case raiseException = 0
        case setErrorAndReturn = 1
    }

    public var requiresSecureCoding = true
    public var decodingFailurePolicy: DecodingFailurePolicy = .raiseException
    /// The first error decoding met.
    public private(set) var error: (any Error)?

    private let objects: [_PlistValue]
    private var containers: [_PlistValue]
    private var decoded: [Int: Any] = [:]
    private var decoding: Set<Int> = []
    private var classes: [String: AnyClass] = [:]

    /// An unarchiver for the keyed archive `data` holds.
    public init(forReadingFrom data: Data) throws {
        let archive: _PlistValue
        do { archive = try _PlistValue.read(Array(data)).0 } catch {
            throw _coderError(_coderReadCorruptError, "The data couldn’t be read because it isn’t in the correct format.")
        }
        guard case .string("NSKeyedArchiver")? = archive._entry("$archiver"),
              case .array(let objects)? = archive._entry("$objects"),
              let top = archive._entry("$top"), case .dictionary = top else {
            throw _coderError(_coderReadCorruptError, "The data couldn’t be read because it isn’t in the correct format.")
        }
        self.objects = objects
        containers = [top]
        super.init()
    }

    /// The root object of `data`, of class `cls`, or nil when the archive's root is nil.
    public class func unarchivedObject<DecodedObjectType>(ofClass cls: DecodedObjectType.Type, from data: Data) throws -> DecodedObjectType? {
        try unarchivedObject(ofClasses: [cls], from: data).map { object in
            guard let typed = object as? DecodedObjectType else {
                throw _coderError(_coderReadCorruptError, "value for key 'root' was of unexpected class '\(_typeName(type(of: object), qualified: false))'")
            }
            return typed
        }
    }

    /// The root object of `data`, of one of `classes`.
    public class func unarchivedObject(ofClasses classes: [Any.Type], from data: Data) throws -> Any? {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        let object = unarchiver._decodeObject(forKey: NSKeyedArchiveRootObjectKey, classes: classes)
        if let error = unarchiver.error { throw error }
        return object
    }

    /// The root array of `data`, of objects of class `cls`.
    public class func unarchivedArrayOfObjects<DecodedObjectType>(ofClass cls: DecodedObjectType.Type, from data: Data) throws -> [DecodedObjectType]? {
        guard let object = try unarchivedObject(ofClasses: [cls], from: data) else { return nil }
        guard let array = object as? [DecodedObjectType] else {
            throw _coderError(_coderReadCorruptError, "value for key 'root' was of unexpected class '\(_typeName(type(of: object), qualified: false))'")
        }
        return array
    }

    @available(*, deprecated, message: "Use unarchivedObject(ofClass:from:) instead")
    public class func unarchiveTopLevelObjectWithData(_ data: Data) throws -> Any? {
        let unarchiver = try NSKeyedUnarchiver(forReadingFrom: data)
        unarchiver.requiresSecureCoding = false
        let object = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
        if let error = unarchiver.error { throw error }
        return object
    }

    @available(*, deprecated, message: "Use unarchivedObject(ofClass:from:) instead")
    public class func unarchiveObject(with data: Data) -> Any? {
        try? unarchiveTopLevelObjectWithData(data)
    }

    /// The class to decode objects archived under `codedName` as, for every unarchiver.
    public class func setClass(_ cls: AnyClass?, forClassName codedName: String) {
        _ArchiveNames.classesByName[codedName] = cls
    }

    public class func `class`(forClassName codedName: String) -> AnyClass? { _ArchiveNames.classesByName[codedName] }

    /// The class to decode objects archived under `codedName` as, for this unarchiver.
    public func setClass(_ cls: AnyClass?, forClassName codedName: String) {
        classes[codedName] = cls
    }

    public func `class`(forClassName codedName: String) -> AnyClass? { classes[codedName] }

    public func finishDecoding() {}

    // MARK: Decoding

    private func value(forKey key: String) -> _PlistValue? { containers[containers.count - 1]._entry(key) }

    private func fail(_ code: Int, _ message: String) {
        if error == nil { error = _coderError(code, message) }
    }

    public override func containsValue(forKey key: String) -> Bool { value(forKey: key) != nil }

    public override func decodeObject(forKey key: String) -> Any? {
        _decodeObject(forKey: key, classes: [])
    }

    public override func _decodeObject(forKey key: String, classes allowed: [Any.Type]) -> Any? {
        guard let value = value(forKey: key) else { return nil }
        for cls in allowed {
            if let cls = cls as? AnyClass {
                let name = _ArchiveNames.name(of: cls)
                if classes[name] == nil { classes[name] = cls }
            }
        }
        guard let index = value._uid else { return value.object }
        return object(at: index)
    }

    public override func decodeBool(forKey key: String) -> Bool {
        switch value(forKey: key) {
        case .bool(let flag)?: return flag
        case .integer(let integer)?: return integer != 0
        default: return false
        }
    }

    public override func decodeInteger(forKey key: String) -> Int { Int(truncatingIfNeeded: decodeInt64(forKey: key)) }
    public override func decodeInt32(forKey key: String) -> Int32 { Int32(truncatingIfNeeded: decodeInt64(forKey: key)) }

    public override func decodeInt64(forKey key: String) -> Int64 {
        switch value(forKey: key) {
        case .integer(let integer)?: return integer
        case .unsigned(let integer)?: return Int64(truncatingIfNeeded: integer)
        case .real(let number)?: return number.isFinite ? Int64(exactly: number.rounded(.towardZero)) ?? 0 : 0
        case .bool(let flag)?: return flag ? 1 : 0
        default: return 0
        }
    }

    public override func decodeDouble(forKey key: String) -> Double {
        switch value(forKey: key) {
        case .real(let number)?: return number
        case .integer(let integer)?: return Double(integer)
        case .unsigned(let integer)?: return Double(integer)
        default: return 0
        }
    }

    public override func decodeFloat(forKey key: String) -> Float { Float(decodeDouble(forKey: key)) }

    private func items(_ value: _PlistValue?) -> [Any] {
        guard case .array(let items)? = value else { return [] }
        return items.map { item in item._uid.flatMap(object(at:)) ?? item.object }
    }

    /// The object the archive holds at `index`, decoded once.
    private func object(at index: Int) -> Any? {
        guard index != 0 else { return nil }
        if let object = decoded[index] { return object }
        guard index < objects.count else {
            fail(_coderReadCorruptError, "The archive refers to an object it does not hold")
            return nil
        }
        let value = objects[index]
        guard let classIndex = value._entry("$class")?._uid else {
            if case .string("$null") = value { return nil }
            decoded[index] = value.object
            return value.object
        }
        guard classIndex < objects.count, case .string(let name)? = objects[classIndex]._entry("$classname") else {
            fail(_coderReadCorruptError, "The archive's object has no class")
            return nil
        }
        guard !decoding.contains(index) else { return nil }
        decoding.insert(index)
        defer { decoding.remove(index) }
        let result: Any?
        switch name {
        case "NSArray", "NSMutableArray":
            result = items(value._entry("NS.objects"))
        case "NSSet", "NSMutableSet":
            result = Set(items(value._entry("NS.objects")).compactMap { $0 as? AnyHashable })
        case "NSDictionary", "NSMutableDictionary":
            let keys = items(value._entry("NS.keys")), values = items(value._entry("NS.objects"))
            if keys.allSatisfy({ $0 is String }) {
                var dictionary: [String: Any] = [:]
                for (key, item) in zip(keys, values) { dictionary[key as! String] = item }
                result = dictionary
            } else {
                var dictionary: [AnyHashable: Any] = [:]
                for (key, item) in zip(keys, values) { if let key = key as? AnyHashable { dictionary[key] = item } }
                result = dictionary
            }
        case "NSDate":
            if case .real(let time)? = value._entry("NS.time") { result = Date(timeIntervalSinceReferenceDate: time) } else { result = nil }
        case "NSString", "NSMutableString":
            result = value._entry("NS.string")?.object as? String ?? ""
        case "NSData", "NSMutableData":
            if case .data(let bytes)? = value._entry("NS.data") { result = Data(bytes) } else { result = nil }
        case "NSURL":
            let relative = value._entry("NS.relative")?._uid.flatMap(object(at:)) as? String ?? ""
            let base = value._entry("NS.base")?._uid.flatMap(object(at:)) as? URL
            result = URL(string: relative, relativeTo: base)
        case "NSUUID":
            guard case .data(let bytes)? = value._entry("NS.uuidbytes"), bytes.count == 16 else { result = nil; break }
            result = UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                                 bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
        default:
            var found: AnyClass? = _ArchiveNames.lookup(name, extra: classes)
            if found == nil, case .array(let hierarchy)? = objects[classIndex]._entry("$classes") {
                for case .string(let superclass) in hierarchy.dropFirst() where superclass != "NSObject" {
                    if let cls = _ArchiveNames.lookup(superclass, extra: classes) { found = cls; break }
                }
            }
            guard let coding = found as? any NSCoding.Type else {
                fail(_coderReadCorruptError, "cannot decode object of class (\(name)) for key (root); the class may be defined in source code or a library that is not linked")
                return nil
            }
            containers.append(value)
            result = coding.init(coder: self)
            containers.removeLast()
        }
        if result == nil, error == nil { fail(_coderReadCorruptError, "The object of class \(name) could not be decoded") }
        decoded[index] = result
        return result
    }
}

#endif
