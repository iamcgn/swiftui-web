// KeyPathComparator for platforms whose Foundation lacks it (the wasm SDK's FoundationEssentials
// ships `SortComparator`, `SortOrder` and `ComparableComparator` but not the key-path
// comparator that `Table` sorting and `sorted(using:)` calls need). Apple platforms use
// Foundation's.
#if os(WASI)
import Foundation

/// A comparator that compares two values by a key path's value.
// The value closures only read the key path they capture (`@unchecked`: closures over a
// generic metatype cannot be `@Sendable` under Swift 6.3).
public struct KeyPathComparator<Compared>: SortComparator, @unchecked Sendable {
    /// The key path whose values are compared.
    public let keyPath: PartialKeyPath<Compared> & Sendable
    /// The order the comparator applies.
    public var order: SortOrder
    private let compareValues: (Compared, Compared) -> ComparisonResult

    /// Creates a comparator using a key path to a comparable value.
    public init<Value: Comparable>(_ keyPath: KeyPath<Compared, Value> & Sendable, order: SortOrder = .forward) {
        self.keyPath = keyPath
        self.order = order
        compareValues = { lhs, rhs in
            let a = lhs[keyPath: keyPath], b = rhs[keyPath: keyPath]
            return a < b ? .orderedAscending : a == b ? .orderedSame : .orderedDescending
        }
    }

    /// Creates a comparator using a key path and a comparator for its value.
    public init<Value, Comparator: SortComparator>(_ keyPath: KeyPath<Compared, Value> & Sendable, comparator: Comparator, order: SortOrder = .forward)
    where Comparator.Compared == Value, Comparator: Sendable {
        self.keyPath = keyPath
        self.order = order
        let forward = { var copy = comparator; copy.order = .forward; return copy }()
        compareValues = { forward.compare($0[keyPath: keyPath], $1[keyPath: keyPath]) }
    }

    public func compare(_ lhs: Compared, _ rhs: Compared) -> ComparisonResult {
        let result = compareValues(lhs, rhs)
        switch (order, result) {
        case (.forward, _): return result
        case (.reverse, .orderedAscending): return .orderedDescending
        case (.reverse, .orderedDescending): return .orderedAscending
        case (.reverse, .orderedSame): return .orderedSame
        }
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.keyPath == rhs.keyPath && lhs.order == rhs.order }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(keyPath)
        hasher.combine(order)
    }
}
#endif
