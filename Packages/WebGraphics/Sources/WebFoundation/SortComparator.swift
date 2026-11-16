// Foundation's sort comparators on wasm (decision 0017): `ComparisonResult`, `SortOrder`,
// `SortComparator`, `ComparableComparator`, `KeyPathComparator`, `String.StandardComparator` and
// `sorted(using:)`. A package that imports only Foundation sorts by key path too (BackyardBirds'
// data package).
#if os(WASI)
import FoundationEssentials
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

extension String {
    /// Foundation's string comparators: `.lexical` orders by the strings' Unicode scalars,
    /// `.localized` as the current locale's collation does, and `.localizedStandard` as the
    /// Finder does, with numbers by value ("File 2" before "File 10").
    public struct StandardComparator: SortComparator, Sendable {
        /// Orders strings by their scalars, ignoring the locale.
        public static let lexical = StandardComparator([], isLocalized: false)
        /// Orders strings as the current locale's collation does.
        public static let localized = StandardComparator([], isLocalized: true)
        /// Orders strings as the Finder lists file names.
        public static let localizedStandard = StandardComparator(.numeric, isLocalized: true)

        /// The comparison options the comparator applies.
        public let options: String.CompareOptions
        /// Whether the comparator orders by the current locale.
        public let isLocalized: Bool
        public var order: SortOrder

        public init(_ options: String.CompareOptions, isLocalized: Bool = true, order: SortOrder = .forward) {
            self.options = options
            self.isLocalized = isLocalized
            self.order = order
        }

        public func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
            let result = lhs.compare(rhs, options: options, locale: isLocalized ? Locale.current : nil)
            return order == .forward ? result : ComparisonResult(rawValue: -result.rawValue)!
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.options.rawValue == rhs.options.rawValue && lhs.isLocalized == rhs.isLocalized && lhs.order == rhs.order
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(options.rawValue)
            hasher.combine(isLocalized)
            hasher.combine(order)
        }
    }
}

extension SortComparator where Self == String.StandardComparator {
    public static var lexical: String.StandardComparator { String.StandardComparator.lexical }
    public static var localized: String.StandardComparator { String.StandardComparator.localized }
    public static var localizedStandard: String.StandardComparator { String.StandardComparator.localizedStandard }
}
#endif
