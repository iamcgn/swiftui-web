// `IndexSet.rangeView` on wasm: the set as its runs of consecutive integers, which
// swift-identified-collections' `remove(atOffsets:)` and `move(fromOffsets:toOffset:)` walk.
// Here rather than beside `IndexSet` in WebFoundation, so a bundle that never asks for the runs
// does not carry their collection type.
#if os(WASI)
import WebFoundation

extension IndexSet {
    /// The runs of consecutive integers in a set, in ascending order.
    public struct RangeView: BidirectionalCollection, Equatable, Hashable, Sendable {
        let ranges: [Range<Int>]

        init(_ set: IndexSet, within bounds: Range<Int>?) {
            var runs: [Range<Int>] = []
            for value in set where bounds?.contains(value) ?? true {
                if let last = runs.last, last.upperBound == value {
                    runs[runs.count - 1] = last.lowerBound..<value + 1
                } else {
                    runs.append(value..<value + 1)
                }
            }
            ranges = runs
        }

        public var startIndex: Int { ranges.startIndex }
        public var endIndex: Int { ranges.endIndex }
        public func index(after i: Int) -> Int { i + 1 }
        public func index(before i: Int) -> Int { i - 1 }
        public subscript(position: Int) -> Range<Int> { ranges[position] }
    }

    /// The set's runs of consecutive integers: `[1, 2, 3, 7]` gives `1..<4` and `7..<8`.
    public var rangeView: RangeView { RangeView(self, within: nil) }

    /// The runs that fall within `range`, cut at its ends.
    public func rangeView<R: RangeExpression>(of range: R) -> RangeView where R.Bound == Int {
        RangeView(self, within: range.relative(to: Int.min..<Int.max))
    }
}
#endif
