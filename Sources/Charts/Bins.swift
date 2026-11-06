// Bins: a numeric range cut into intervals, for histograms and colour bands
// (`NumberBins(range: 0...10, count: 5).index(for: 3.2)`).
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// One interval of a set of bins: from its lower bound up to, not including, its upper bound
/// (the last bin includes its upper bound).
public struct ChartBinRange<Bound: Comparable & Sendable>: Equatable, Sendable {
    public var lowerBound: Bound
    public var upperBound: Bound

    public init(lowerBound: Bound, upperBound: Bound) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }
}

/// A numeric range cut into intervals at thresholds.
public struct NumberBins<Value: BinaryFloatingPoint & Sendable>: RandomAccessCollection, Equatable, Sendable {
    /// The edges of the bins, in increasing order: one more than there are bins.
    public let thresholds: [Value]

    /// Bins with the given edges (sorted; at least two make one bin).
    public init(thresholds: [Value]) {
        self.thresholds = thresholds.sorted()
    }

    /// `count` bins of equal width across `range`.
    public init(range: ClosedRange<Value>, count: Int) {
        let n = Swift.max(count, 1)
        let width = (range.upperBound - range.lowerBound) / Value(n)
        thresholds = (0...n).map { $0 == n ? range.upperBound : range.lowerBound + Value($0) * width }
    }

    /// Bins of width `size` from the range's lower bound until they cover its upper bound.
    public init(size: Value, range: ClosedRange<Value>) {
        guard size > 0 else { thresholds = [range.lowerBound, range.upperBound]; return }
        var edges = [range.lowerBound]
        while let last = edges.last, last < range.upperBound { edges.append(last + size) }
        if edges.count == 1 { edges.append(range.lowerBound + size) }
        thresholds = edges
    }

    public var startIndex: Int { 0 }
    public var endIndex: Int { Swift.max(thresholds.count - 1, 0) }

    public subscript(position: Int) -> ChartBinRange<Value> {
        ChartBinRange(lowerBound: thresholds[position], upperBound: thresholds[position + 1])
    }

    /// The bin a value falls in; values past either end go to the first or the last bin.
    public func index(for value: Value) -> Int {
        guard count > 1 else { return 0 }
        for i in 1..<thresholds.count - 1 where value < thresholds[i] { return i - 1 }
        return count - 1
    }
}
