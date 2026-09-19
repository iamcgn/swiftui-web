// Foundation's `IndexSet` on wasm (decision 0017): FoundationEssentials has none. A set of
// integers iterated in ascending order, with the surface `List` editing, tables and collection
// views use.
#if os(WASI)
public struct IndexSet: Hashable, Sendable, Codable, ExpressibleByArrayLiteral, Sequence, CustomStringConvertible {
    public var indices: Set<Int>

    public init() { indices = [] }
    public init(_ indices: some Sequence<Int>) { self.indices = Set(indices) }
    public init(integer: Int) { indices = [integer] }
    public init(integersIn range: Range<Int>) { indices = Set(range) }
    public init(integersIn range: ClosedRange<Int>) { indices = Set(range) }
    public init(arrayLiteral elements: Int...) { indices = Set(elements) }

    public func makeIterator() -> IndexingIterator<[Int]> { indices.sorted().makeIterator() }
    public var count: Int { indices.count }
    public var isEmpty: Bool { indices.isEmpty }
    public var first: Int? { indices.min() }
    public var last: Int? { indices.max() }
    public func contains(_ integer: Int) -> Bool { indices.contains(integer) }
    public func contains(integersIn range: Range<Int>) -> Bool { range.allSatisfy(indices.contains) }
    public mutating func insert(_ integer: Int) { indices.insert(integer) }
    public mutating func insert(integersIn range: Range<Int>) { indices.formUnion(range) }
    public mutating func remove(_ integer: Int) { indices.remove(integer) }
    public mutating func remove(integersIn range: Range<Int>) { indices.subtract(range) }
    public mutating func removeAll() { indices.removeAll() }
    public mutating func formUnion(_ other: IndexSet) { indices.formUnion(other.indices) }
    public func union(_ other: IndexSet) -> IndexSet { IndexSet(indices.union(other.indices)) }
    public mutating func formIntersection(_ other: IndexSet) { indices.formIntersection(other.indices) }
    public func intersection(_ other: IndexSet) -> IndexSet { IndexSet(indices.intersection(other.indices)) }
    public mutating func subtract(_ other: IndexSet) { indices.subtract(other.indices) }
    public func subtracting(_ other: IndexSet) -> IndexSet { IndexSet(indices.subtracting(other.indices)) }
    public func filteredIndexSet(includeInteger: (Int) throws -> Bool) rethrows -> IndexSet { IndexSet(try indices.filter(includeInteger)) }
    /// Integers shifted by `delta` from `integer` on (Foundation's `shift(startingAt:by:)`).
    public mutating func shift(startingAt integer: Int, by delta: Int) {
        indices = Set(indices.map { $0 >= integer ? $0 + delta : $0 })
    }
    public var description: String { "IndexSet(" + indices.sorted().map(String.init).joined(separator: ", ") + ")" }
}
#endif
