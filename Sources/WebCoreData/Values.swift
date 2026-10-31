// The values Core Data works with, without an Objective-C runtime: how a stored or fetched value
// is unwrapped, compared and matched (what predicates and sort descriptors run on), and the
// Foundation collection classes the generated accessors use. Apple's to-many relationships are
// `NSSet` and `NSOrderedSet`; here `NSSet` is `Set<AnyHashable>`, so the casts apps write
// (`children as? Set<Child>`, `children?.allObjects as? [Child]`) and the coercions
// (`Set<Child>` passed where an `NSSet` goes) work as they do with bridging.

/// An unordered collection of distinct objects (a to-many relationship's value).
public typealias NSSet = Set<AnyHashable>

extension Set where Element == AnyHashable {
    /// The members, as `NSSet.allObjects` lists them.
    public var allObjects: [Any] { map { $0.base } }
    /// One member, or `nil` when the set is empty.
    public func anyObject() -> Any? { first?.base }
    public init(array: [Any]) { self.init(array.compactMap { $0 as? AnyHashable }) }
    public init(object: Any) { self.init(array: [object]) }
    public init(objects: Any...) { self.init(array: objects) }
    public init(set: Set<AnyHashable>) { self = set }
    public func member(_ object: Any) -> Any? { (object as? AnyHashable).flatMap { contains($0) ? $0.base : nil } }
    /// The members sorted by the descriptors, as `NSSet.sortedArray(using:)`.
    public func sortedArray(using sortDescriptors: [NSSortDescriptor]) -> [Any] {
        NSSortDescriptor._sort(allObjects, by: sortDescriptors)
    }
    public func filtered(using predicate: NSPredicate) -> Set<AnyHashable> { filter { predicate.evaluate(with: $0.base) } }
}

/// An ordered collection of distinct objects (an ordered to-many relationship's value).
public struct NSOrderedSet: RandomAccessCollection, Hashable, @unchecked Sendable, CustomStringConvertible {
    public private(set) var array: [Any]
    private var members: Set<AnyHashable>

    public init() { array = []; members = [] }
    public init(array: [Any]) {
        self.array = []
        members = []
        for element in array { _append(element) }
    }
    public init(object: Any) { self.init(array: [object]) }
    public init(set: Set<AnyHashable>) { self.init(array: set.allObjects) }
    public init(orderedSet: NSOrderedSet) { self = orderedSet }

    public var startIndex: Int { 0 }
    public var endIndex: Int { array.count }
    public subscript(index: Int) -> Any { array[index] }
    public var set: Set<AnyHashable> { members }
    public var firstObject: Any? { array.first }
    public var lastObject: Any? { array.last }
    public func object(at index: Int) -> Any { array[index] }
    public func contains(_ object: Any) -> Bool { (object as? AnyHashable).map(members.contains) ?? false }
    public func index(of object: Any) -> Int {
        guard let key = object as? AnyHashable else { return Int.max }
        return array.firstIndex { ($0 as? AnyHashable) == key } ?? Int.max
    }
    public func sortedArray(using sortDescriptors: [NSSortDescriptor]) -> [Any] { NSSortDescriptor._sort(array, by: sortDescriptors) }
    public func filtered(using predicate: NSPredicate) -> NSOrderedSet { NSOrderedSet(array: array.filter { predicate.evaluate(with: $0) }) }

    mutating func _append(_ element: Any) {
        guard let key = element as? AnyHashable, !members.contains(key) else { return }
        members.insert(key)
        array.append(element)
    }
    mutating func _insert(_ element: Any, at index: Int) {
        guard let key = element as? AnyHashable, !members.contains(key) else { return }
        members.insert(key)
        array.insert(element, at: Swift.min(Swift.max(index, 0), array.count))
    }
    mutating func _remove(_ element: Any) {
        guard let key = element as? AnyHashable, members.remove(key) != nil else { return }
        array.removeAll { ($0 as? AnyHashable) == key }
    }
    mutating func _remove(at index: Int) {
        guard array.indices.contains(index) else { return }
        if let key = array[index] as? AnyHashable { members.remove(key) }
        array.remove(at: index)
    }

    public static func == (lhs: NSOrderedSet, rhs: NSOrderedSet) -> Bool {
        lhs.array.count == rhs.array.count && zip(lhs.array, rhs.array).allSatisfy { ($0 as? AnyHashable) == ($1 as? AnyHashable) }
    }
    public func hash(into hasher: inout Hasher) { hasher.combine(members) }
    public var description: String { "\(array)" }
}

#if os(WASI)
/// `Date`, as Foundation bridges it: `date as NSDate` in a predicate's arguments.
public typealias NSDate = Date
/// A block that compares two objects (Foundation's `Comparator`).
public typealias Comparator = (Any, Any) -> ComparisonResult
#endif

// MARK: - Unwrapping and comparing

protocol _CDOptional { var _cdWrapped: Any? { get } }
extension Optional: _CDOptional {
    var _cdWrapped: Any? {
        switch self {
        case .some(let wrapped): return _cdUnwrap(wrapped)
        case .none: return nil
        }
    }
}

/// The value inside any number of optionals, or `nil`.
func _cdUnwrap(_ value: Any?) -> Any? {
    guard let value else { return nil }
    if let optional = value as? _CDOptional { return optional._cdWrapped }
    return value
}

/// A value as a number, when it is one (Booleans count as 0 and 1, as `NSNumber` holds them).
func _cdDouble(_ value: Any?) -> Double? {
    switch _cdUnwrap(value) {
    case let v as Int: return Double(v)
    case let v as Int64: return Double(v)
    case let v as Int32: return Double(v)
    case let v as Int16: return Double(v)
    case let v as Int8: return Double(v)
    case let v as UInt: return Double(v)
    case let v as UInt64: return Double(v)
    case let v as UInt32: return Double(v)
    case let v as UInt16: return Double(v)
    case let v as UInt8: return Double(v)
    case let v as Double: return v
    case let v as Float: return Double(v)
    case let v as Bool: return v ? 1 : 0
    case let v as NSNumber: return v.doubleValue
    default: return nil
    }
}

/// A value as an integer, when it is a whole number.
func _cdInt64(_ value: Any?) -> Int64? {
    switch _cdUnwrap(value) {
    case let v as Int: return Int64(v)
    case let v as Int64: return v
    case let v as Int32: return Int64(v)
    case let v as Int16: return Int64(v)
    case let v as Int8: return Int64(v)
    case let v as UInt: return Int64(truncatingIfNeeded: v)
    case let v as UInt64: return Int64(truncatingIfNeeded: v)
    case let v as UInt32: return Int64(v)
    case let v as UInt16: return Int64(v)
    case let v as UInt8: return Int64(v)
    case let v as Bool: return v ? 1 : 0
    case let v as Double where v.rounded() == v && abs(v) < 9.2e18: return Int64(v)
    case let v as Float where v.rounded() == v && abs(v) < 9.2e18: return Int64(v)
    case let v as NSNumber: return v.int64Value
    default: return nil
    }
}

func _cdString(_ value: Any?) -> String? {
    switch _cdUnwrap(value) {
    case let v as String: return v
    case let v as Substring: return String(v)
    case let v as Character: return String(v)
    default: return nil
    }
}

func _cdDate(_ value: Any?) -> Date? { _cdUnwrap(value) as? Date }

/// The elements of a collection value (an array, a set, an ordered set), or `nil` when the
/// value is not one. Strings and data are not collections here.
func _cdElements(_ value: Any?) -> [Any]? {
    switch _cdUnwrap(value) {
    case let v as NSOrderedSet: return v.array
    case let v as Set<AnyHashable>: return v.map(\.base)
    case is String, is Data: return nil
    case let v as [Any]: return v
    default: return nil
    }
}

/// How two values order: numbers numerically, strings by their characters (case- and
/// diacritic-insensitively when asked), dates by time; `nil` when they do not compare.
func _cdCompare(_ lhs: Any?, _ rhs: Any?, _ options: NSComparisonPredicate.Options = []) -> ComparisonResult? {
    let a = _cdUnwrap(lhs), b = _cdUnwrap(rhs)
    if let x = _cdInt64(a), let y = _cdInt64(b), !(a is Double || a is Float || b is Double || b is Float) {
        return x < y ? .orderedAscending : x == y ? .orderedSame : .orderedDescending
    }
    if let x = _cdDouble(a), let y = _cdDouble(b) {
        return x < y ? .orderedAscending : x == y ? .orderedSame : .orderedDescending
    }
    if let x = _cdString(a), let y = _cdString(b) {
        let l = _cdFold(x, options), r = _cdFold(y, options)
        return l < r ? .orderedAscending : l == r ? .orderedSame : .orderedDescending
    }
    if let x = a as? Date, let y = b as? Date {
        return x < y ? .orderedAscending : x == y ? .orderedSame : .orderedDescending
    }
    if let x = a as? UUID, let y = b as? UUID {
        return x.uuidString < y.uuidString ? .orderedAscending : x == y ? .orderedSame : .orderedDescending
    }
    if let x = a as? URL, let y = b as? URL {
        return x.absoluteString < y.absoluteString ? .orderedAscending : x == y ? .orderedSame : .orderedDescending
    }
    return nil
}

/// Whether two values are equal as a predicate compares them.
func _cdEqual(_ lhs: Any?, _ rhs: Any?, _ options: NSComparisonPredicate.Options = []) -> Bool {
    let a = _cdUnwrap(lhs), b = _cdUnwrap(rhs)
    switch (a, b) {
    case (nil, nil): return true
    case (nil, _), (_, nil): return false
    default: break
    }
    if let x = a as? NSManagedObject, let y = b as? NSManagedObject { return x === y || x.objectID == y.objectID }
    if let x = a as? NSManagedObject, let y = b as? NSManagedObjectID { return x.objectID == y }
    if let x = a as? NSManagedObjectID, let y = b as? NSManagedObject { return x == y.objectID }
    if let x = a as? NSManagedObjectID, let y = b as? NSManagedObjectID { return x == y }
    if let x = a as? Data, let y = b as? Data { return x == y }
    if let x = a as? UUID, let y = b as? UUID { return x == y }
    if let x = a as? UUID, let y = _cdString(b) { return x.uuidString.lowercased() == y.lowercased() }
    if let x = _cdString(a), let y = b as? UUID { return y.uuidString.lowercased() == x.lowercased() }
    if let result = _cdCompare(a, b, options) { return result == .orderedSame }
    if let x = a as? AnyHashable, let y = b as? AnyHashable { return x == y }
    if let x = a, let y = b, type(of: x) is AnyClass, type(of: y) is AnyClass { return (x as AnyObject) === (y as AnyObject) }
    return false
}

/// A string as `[c]` (case-insensitive) and `[d]` (diacritic-insensitive) compare it.
func _cdFold(_ string: String, _ options: NSComparisonPredicate.Options) -> String {
    var result = string
    if options.contains(.diacriticInsensitive) { result = _cdStripDiacritics(result) }
    if options.contains(.caseInsensitive) { result = result.lowercased() }
    return result
}

/// Latin letters without their accents, and combining marks dropped (the diacritic folding
/// `[d]` asks for, as far as the Latin scripts go).
func _cdStripDiacritics(_ string: String) -> String {
    var scalars = String.UnicodeScalarView()
    for scalar in string.unicodeScalars {
        let v = scalar.value
        if (0x0300...0x036F).contains(v) { continue }
        if let base = _cdLatinBase[v] { scalars.append(contentsOf: base.unicodeScalars) } else { scalars.append(scalar) }
    }
    return String(scalars)
}

private let _cdLatinBase: [UInt32: String] = {
    var table: [UInt32: String] = [:]
    let groups: [(String, String)] = [
        ("ÀÁÂÃÄÅĀĂĄǍ", "A"), ("àáâãäåāăąǎ", "a"), ("ÇĆĈĊČ", "C"), ("çćĉċč", "c"), ("ĎĐ", "D"), ("ďđ", "d"),
        ("ÈÉÊËĒĔĖĘĚ", "E"), ("èéêëēĕėęě", "e"), ("ĜĞĠĢ", "G"), ("ĝğġģ", "g"), ("ĤĦ", "H"), ("ĥħ", "h"),
        ("ÌÍÎÏĨĪĬĮİǏ", "I"), ("ìíîïĩīĭįıǐ", "i"), ("Ĵ", "J"), ("ĵ", "j"), ("Ķ", "K"), ("ķ", "k"),
        ("ĹĻĽĿŁ", "L"), ("ĺļľŀł", "l"), ("ÑŃŅŇ", "N"), ("ñńņň", "n"), ("ÒÓÔÕÖØŌŎŐǑ", "O"), ("òóôõöøōŏőǒ", "o"),
        ("ŔŖŘ", "R"), ("ŕŗř", "r"), ("ŚŜŞŠ", "S"), ("śŝşš", "s"), ("ŢŤŦ", "T"), ("ţťŧ", "t"),
        ("ÙÚÛÜŨŪŬŮŰŲǓ", "U"), ("ùúûüũūŭůűųǔ", "u"), ("Ŵ", "W"), ("ŵ", "w"), ("ÝŸŶ", "Y"), ("ýÿŷ", "y"),
        ("ŹŻŽ", "Z"), ("źżž", "z"),
    ]
    for (letters, base) in groups { for scalar in letters.unicodeScalars { table[scalar.value] = base } }
    return table
}()

/// `LIKE`: `*` matches any run of characters, `?` any one.
func _cdLike(_ string: String, _ pattern: String) -> Bool {
    let s = Array(string), p = Array(pattern)
    var si = 0, pi = 0, star = -1, mark = 0
    while si < s.count {
        if pi < p.count, p[pi] == "?" || p[pi] == s[si] { si += 1; pi += 1 }
        else if pi < p.count, p[pi] == "*" { star = pi; mark = si; pi += 1 }
        else if star >= 0 { pi = star + 1; mark += 1; si = mark }
        else { return false }
    }
    while pi < p.count, p[pi] == "*" { pi += 1 }
    return pi == p.count
}

/// `MATCHES`: the whole string against an ICU-style regular expression.
func _cdMatches(_ string: String, _ pattern: String) -> Bool {
    guard let regex = try? Regex(pattern) else { return false }
    return (try? regex.wholeMatch(in: string)) != nil
}
