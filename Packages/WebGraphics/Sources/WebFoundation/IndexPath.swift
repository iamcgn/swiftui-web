// Foundation's index path (decision 0017): FoundationEssentials' member carries the attributed
// string, calendar and file manager code with it.
#if os(WASI)
public struct IndexPath: Hashable, Sendable, Comparable, ExpressibleByArrayLiteral, CustomStringConvertible,
                         RandomAccessCollection, MutableCollection {
    public var indexes: [Int]
    public init() { indexes = [] }
    public init(indexes: [Int]) { self.indexes = indexes }
    public init(indexes: some Sequence<Int>) { self.indexes = Array(indexes) }
    public init(index: Int) { indexes = [index] }
    public init(arrayLiteral elements: Int...) { indexes = elements }
    public var startIndex: Int { 0 }
    public var endIndex: Int { indexes.count }
    public subscript(position: Int) -> Int {
        get { indexes[position] }
        set { indexes[position] = newValue }
    }
    public subscript(bounds: Range<Int>) -> IndexPath {
        get { IndexPath(indexes: indexes[bounds]) }
        set { indexes.replaceSubrange(bounds, with: newValue.indexes) }
    }
    public func index(after i: Int) -> Int { i + 1 }
    public func index(before i: Int) -> Int { i - 1 }
    public mutating func append(_ other: Int) { indexes.append(other) }
    public mutating func append(_ other: IndexPath) { indexes.append(contentsOf: other.indexes) }
    public mutating func append(_ other: [Int]) { indexes.append(contentsOf: other) }
    public func appending(_ other: Int) -> IndexPath { IndexPath(indexes: indexes + [other]) }
    public func appending(_ other: IndexPath) -> IndexPath { IndexPath(indexes: indexes + other.indexes) }
    public func appending(_ other: [Int]) -> IndexPath { IndexPath(indexes: indexes + other) }
    public func dropLast() -> IndexPath { IndexPath(indexes: indexes.dropLast()) }
    public static func < (lhs: IndexPath, rhs: IndexPath) -> Bool { lhs.indexes.lexicographicallyPrecedes(rhs.indexes) }
    public static func + (lhs: IndexPath, rhs: IndexPath) -> IndexPath { lhs.appending(rhs) }
    public static func += (lhs: inout IndexPath, rhs: IndexPath) { lhs.append(rhs) }
    public var description: String { "[" + indexes.map(String.init).joined(separator: ", ") + "]" }
}
#endif
