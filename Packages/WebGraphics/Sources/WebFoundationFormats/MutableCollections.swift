// Foundation's mutable object collections on wasm: `NSMutableArray`, `NSMutableSet` and
// `NSCountedSet`, with `NSEnumerator` and the `Comparator` block that sorts them. OldOS's
// UIImageColors counts an image's colours in an `NSCountedSet` and sorts them in an
// `NSMutableArray`; the arrays and sets are kinds of `NSArray` and `NSSet` (NSObjects.swift), so
// `mutable as NSArray` and `nsArray as? [Int]` convert as on Apple platforms.
#if os(WASI)
import WebFoundation

/// Foundation's block that orders two objects (`sortedArray(comparator:)`, `sort(comparator:)`).
public typealias Comparator = (Any, Any) -> ComparisonResult

// MARK: - Enumerators

/// Walks a collection's objects one at a time (`objectEnumerator()`), as Foundation's does:
/// `nextObject()` until it answers nil, or `for object in enumerator`.
open class NSEnumerator: NSObject, Sequence, IteratorProtocol, @unchecked Sendable {
    private var remaining: [Any]
    private var position = 0
    /// An enumerator over `objects` in order (a subclass overrides `nextObject()` instead).
    public init(_webObjects objects: [Any]) {
        remaining = objects
        super.init()
    }
    public override convenience init() { self.init(_webObjects: []) }
    /// The next object, or nil once every object has been walked.
    open func nextObject() -> Any? {
        guard position < remaining.count else { return nil }
        defer { position += 1 }
        return remaining[position]
    }
    /// The objects not yet walked; the enumerator is then at its end.
    open var allObjects: [Any] {
        var objects: [Any] = []
        while let object = nextObject() { objects.append(object) }
        return objects
    }
    public func next() -> Any? { nextObject() }
}

// MARK: - Arrays

extension _WebNSArray {
    /// An enumerator over the elements in order.
    public func objectEnumerator() -> NSEnumerator { NSEnumerator(_webObjects: elements) }
    /// An enumerator over the elements from the last to the first.
    public func reverseObjectEnumerator() -> NSEnumerator { NSEnumerator(_webObjects: elements.reversed()) }
    /// The elements in the order the comparator gives, equal elements keeping their order.
    public func sortedArray(comparator cmptr: Comparator) -> [Any] { _WebSort.stable(elements, cmptr) }
    /// The elements in the order the function gives (its context passed through).
    public func sortedArray(_ comparator: (Any, Any, UnsafeMutableRawPointer?) -> Int, context: UnsafeMutableRawPointer?) -> [Any] {
        _WebSort.stable(elements) { ComparisonResult(rawValue: comparator($0, $1, context).signum()) ?? .orderedSame }
    }
    /// Calls the block with each element and its index; setting `stop` ends the walk.
    public func enumerateObjects(_ block: (Any, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {
        var stop: ObjCBool = false
        for (index, element) in elements.enumerated() {
            block(element, index, &stop)
            if stop.boolValue { return }
        }
    }
    /// The lowest index whose element passes the test, or `NSNotFound`.
    public func indexOfObject(passingTest predicate: (Any, Int, UnsafeMutablePointer<ObjCBool>) -> Bool) -> Int {
        var stop: ObjCBool = false
        for (index, element) in elements.enumerated() {
            if predicate(element, index, &stop) { return index }
            if stop.boolValue { break }
        }
        return NSNotFound
    }
}

/// An ordered collection of objects that changes: added, inserted, removed, replaced and sorted
/// in place.
open class NSMutableArray: _WebNSArray, @unchecked Sendable {
    /// An empty array with room for `numItems` objects.
    public convenience init(capacity numItems: Int) {
        self.init(elements: [])
        elements.reserveCapacity(Swift.max(0, numItems))
    }

    open func add(_ anObject: Any) { elements.append(anObject) }
    open func addObjects(from otherArray: [Any]) { elements += otherArray }
    /// Puts the object at the index, moving the later elements up; an index past the end stops,
    /// as Foundation raises `NSRangeException`.
    open func insert(_ anObject: Any, at index: Int) {
        precondition(index >= 0 && index <= elements.count, "*** -[NSMutableArray insertObject:atIndex:]: index \(index) beyond bounds [0 .. \(elements.count)]")
        elements.insert(anObject, at: index)
    }
    open func removeObject(at index: Int) {
        precondition(elements.indices.contains(index), "*** -[NSMutableArray removeObjectAtIndex:]: index \(index) beyond bounds [0 .. \(elements.count - 1)]")
        elements.remove(at: index)
    }
    /// Removes the last element; an empty array is left as it is, as Foundation's is.
    open func removeLastObject() { if !elements.isEmpty { elements.removeLast() } }
    /// Removes every element equal to the object.
    open func remove(_ anObject: Any) { elements.removeAll { _webValuesEqual($0, anObject) } }
    open func removeObjects(in otherArray: [Any]) {
        elements.removeAll { element in otherArray.contains { _webValuesEqual(element, $0) } }
    }
    open func removeObjects(in range: NSRange) {
        precondition(range.location >= 0 && range.length >= 0 && range.location + range.length <= elements.count,
                     "*** -[NSMutableArray removeObjectsInRange:]: range {\(range.location), \(range.length)} extends beyond bounds [0 .. \(elements.count - 1)]")
        elements.removeSubrange(range.location..<(range.location + range.length))
    }
    open func removeAllObjects() { elements.removeAll() }
    open func replaceObject(at index: Int, with anObject: Any) {
        precondition(elements.indices.contains(index), "*** -[NSMutableArray replaceObjectAtIndex:withObject:]: index \(index) beyond bounds [0 .. \(elements.count - 1)]")
        elements[index] = anObject
    }
    open func exchangeObject(at idx1: Int, withObjectAt idx2: Int) { elements.swapAt(idx1, idx2) }
    open func setArray(_ otherArray: [Any]) { elements = otherArray }
    /// Sorts the elements in place in the order the comparator gives, equal ones keeping their order.
    open func sort(comparator cmptr: Comparator) { elements = _WebSort.stable(elements, cmptr) }
}

/// A stable sort by a comparator, as `NSSortStable` sorts.
enum _WebSort {
    static func stable(_ elements: [Any], _ comparator: Comparator) -> [Any] {
        elements.enumerated().sorted { lhs, rhs in
            switch comparator(lhs.element, rhs.element) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: lhs.offset < rhs.offset
            }
        }.map(\.element)
    }
}

// MARK: - Sets

extension _WebNSSet {
    /// An enumerator over the members, in no particular order.
    public func objectEnumerator() -> NSEnumerator { NSEnumerator(_webObjects: allObjects) }
}

/// An unordered collection of distinct objects that changes.
open class NSMutableSet: _WebNSSet, @unchecked Sendable {
    /// An empty set with room for `numItems` objects.
    public convenience init(capacity numItems: Int) {
        self.init(members: [])
        members.reserveCapacity(Swift.max(0, numItems))
    }
    /// Adds the object, unless an equal one is a member already.
    open func add(_ object: Any) {
        let member = _WebSetMember.member(object)
        if !members.contains(member) { members.append(member) }
    }
    open func addObjects(from array: [Any]) { array.forEach(add) }
    open func remove(_ object: Any) {
        let member = _WebSetMember.member(object)
        members.removeAll { $0 == member }
    }
    open func removeAllObjects() { members.removeAll() }
    /// Adds each of the other set's members.
    open func union(_ otherSet: Set<AnyHashable>) { otherSet.forEach(add) }
    /// Removes each of the other set's members.
    open func minus(_ otherSet: Set<AnyHashable>) { members.removeAll(where: otherSet.contains) }
    /// Keeps only the members the other set also has.
    open func intersect(_ otherSet: Set<AnyHashable>) { members.removeAll { !otherSet.contains($0) } }
    open func setSet(_ otherSet: Set<AnyHashable>) { members = Array(otherSet) }
}

/// A set that counts how many times each distinct object was added: `count(for:)` answers it,
/// and a member stays until it has been removed as many times.
open class NSCountedSet: NSMutableSet, @unchecked Sendable {
    private var counts: [AnyHashable: Int]
    /// A set of these members, each counted as many times as it appears.
    public override init(members: [AnyHashable]) {
        var counts: [AnyHashable: Int] = [:], distinct: [AnyHashable] = []
        for member in members {
            if counts[member] == nil { distinct.append(member) }
            counts[member, default: 0] += 1
        }
        self.counts = counts
        super.init(members: distinct)
    }
    /// A set of the array's objects, each counted as many times as it appears there.
    public convenience init(array: [Any]) { self.init(members: array.map(_WebSetMember.member)) }
    /// How many times an object equal to `object` was added (0 for one that is not a member).
    open func count(for object: Any) -> Int { counts[_WebSetMember.member(object)] ?? 0 }
    open override func add(_ object: Any) {
        let member = _WebSetMember.member(object)
        let count = counts[member] ?? 0
        if count == 0 { members.append(member) }
        counts[member] = count + 1
    }
    /// Takes one away from the object's count, and the object out of the set when it reaches 0.
    open override func remove(_ object: Any) {
        let member = _WebSetMember.member(object)
        guard let count = counts[member] else { return }
        if count > 1 {
            counts[member] = count - 1
        } else {
            counts[member] = nil
            members.removeAll { $0 == member }
        }
    }
    open override func removeAllObjects() {
        counts.removeAll()
        members.removeAll()
    }
    open override func minus(_ otherSet: Set<AnyHashable>) { otherSet.forEach(remove) }
    open override func intersect(_ otherSet: Set<AnyHashable>) {
        for member in members where !otherSet.contains(member) { counts[member] = nil }
        members.removeAll { !otherSet.contains($0) }
    }
    open override func setSet(_ otherSet: Set<AnyHashable>) {
        removeAllObjects()
        otherSet.forEach(add)
    }
}
#endif
