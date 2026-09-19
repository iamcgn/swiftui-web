// Foundation's sort comparators on wasm (decision 0017): `ComparisonResult`, `SortOrder`,
// `SortComparator`, `ComparableComparator` and `sorted(using:)`. `KeyPathComparator` lives in
// SwiftUIWebCore, which needs it on every platform whose Foundation lacks it.
#if os(WASI)
public enum ComparisonResult: Int, Sendable, Hashable, Codable {
    case orderedAscending = -1
    case orderedSame = 0
    case orderedDescending = 1
}

public enum SortOrder: Hashable, Sendable, Codable {
    case forward, reverse
}

public protocol SortComparator<Compared>: Hashable {
    associatedtype Compared
    func compare(_ lhs: Compared, _ rhs: Compared) -> ComparisonResult
    var order: SortOrder { get set }
}

public struct ComparableComparator<Compared: Comparable>: SortComparator, Sendable {
    public var order: SortOrder
    public init(order: SortOrder = .forward) { self.order = order }
    public func compare(_ lhs: Compared, _ rhs: Compared) -> ComparisonResult {
        let result: ComparisonResult = lhs < rhs ? .orderedAscending : lhs == rhs ? .orderedSame : .orderedDescending
        return order == .forward ? result : ComparisonResult(rawValue: -result.rawValue)!
    }
}

extension Sequence {
    public func sorted<Comparator: SortComparator>(using comparator: Comparator) -> [Element] where Comparator.Compared == Element {
        sorted { comparator.compare($0, $1) == .orderedAscending }
    }
    public func sorted<S: Sequence>(using comparators: S) -> [Element] where S.Element: SortComparator, S.Element.Compared == Element {
        let comparators = Array(comparators)
        return sorted { lhs, rhs in
            for comparator in comparators {
                switch comparator.compare(lhs, rhs) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: continue
                }
            }
            return false
        }
    }
}

extension MutableCollection where Self: RandomAccessCollection {
    public mutating func sort<Comparator: SortComparator>(using comparator: Comparator) where Comparator.Compared == Element {
        sort { comparator.compare($0, $1) == .orderedAscending }
    }
    public mutating func sort<S: Sequence>(using comparators: S) where S.Element: SortComparator, S.Element.Compared == Element {
        let sorted = self.sorted(using: comparators)
        for (index, element) in zip(indices, sorted) { self[index] = element }
    }
}
#endif
