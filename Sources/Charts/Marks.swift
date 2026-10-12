// The marks: bars, lines, points, areas, rules and rectangles, each an init per combination of
// dimensions Swift Charts offers (a value, a start and end, or none on an axis).
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI

/// What every mark holds: its record.
public protocol _RecordMark: ChartContent where Body == Never {
    var _record: _MarkRecord { get }
}

extension _RecordMark {
    public var body: Never { fatalError() }
    @MainActor public func _collect(into records: inout [_MarkRecord]) {
        var record = _record
        record.index = records.count
        records.append(record)
    }
}

extension _MarkRecord {
    mutating func setX<V: Plottable>(_ v: PlottableValue<V>) { x = v.plotValue; xLabel = v.label; xUnit = v.unit }
    mutating func setY<V: Plottable>(_ v: PlottableValue<V>) { y = v.plotValue; yLabel = v.label; yUnit = v.unit }
    mutating func setXRange<V: Plottable>(_ start: PlottableValue<V>, _ end: PlottableValue<V>) {
        xStart = start.plotValue; xEnd = end.plotValue; xLabel = start.label
    }
    mutating func setYRange<V: Plottable>(_ start: PlottableValue<V>, _ end: PlottableValue<V>) {
        yStart = start.plotValue; yEnd = end.plotValue; yLabel = start.label
    }
}

/// A bar: a band on one axis and a value (or range) on the other.
public struct BarMark: _RecordMark {
    public let _record: _MarkRecord

    public init<X: Plottable, Y: Plottable>(x: PlottableValue<X>, y: PlottableValue<Y>, width: MarkDimension = .automatic, height: MarkDimension = .automatic, stacking: MarkStackingMethod = .standard) {
        var r = _MarkRecord(kind: .bar); r.setX(x); r.setY(y); r.width = width; r.height = height; _record = r
    }

    public init<X: Plottable, Y: Plottable>(x: PlottableValue<X>, yStart: PlottableValue<Y>, yEnd: PlottableValue<Y>, width: MarkDimension = .automatic) {
        var r = _MarkRecord(kind: .bar); r.setX(x); r.setYRange(yStart, yEnd); r.width = width; _record = r
    }

    public init<X: Plottable, Y: Plottable>(xStart: PlottableValue<X>, xEnd: PlottableValue<X>, y: PlottableValue<Y>, height: MarkDimension = .automatic) {
        var r = _MarkRecord(kind: .bar); r.setXRange(xStart, xEnd); r.setY(y); r.height = height; _record = r
    }

    public init<X: Plottable, Y: Plottable>(xStart: PlottableValue<X>, xEnd: PlottableValue<X>, yStart: PlottableValue<Y>, yEnd: PlottableValue<Y>) {
        var r = _MarkRecord(kind: .bar); r.setXRange(xStart, xEnd); r.setYRange(yStart, yEnd); _record = r
    }

    /// A bar over the whole y axis (a single stacked column).
    public init<X: Plottable>(x: PlottableValue<X>, width: MarkDimension = .automatic, stacking: MarkStackingMethod = .standard) {
        var r = _MarkRecord(kind: .bar); r.setX(x); r.width = width; _record = r
    }

    public init<Y: Plottable>(y: PlottableValue<Y>, height: MarkDimension = .automatic, stacking: MarkStackingMethod = .standard) {
        var r = _MarkRecord(kind: .bar); r.setY(y); r.height = height; _record = r
    }
}

/// How stacked marks combine (accepted; bars and areas stack by their series).
public enum MarkStackingMethod: Hashable, Sendable {
    case standard, normalized, center, unstacked
}

/// A line through the points of a series.
public struct LineMark: _RecordMark {
    public let _record: _MarkRecord

    public init<X: Plottable, Y: Plottable>(x: PlottableValue<X>, y: PlottableValue<Y>) {
        var r = _MarkRecord(kind: .line); r.setX(x); r.setY(y); _record = r
    }

    public init<X: Plottable, Y: Plottable, S: Plottable>(x: PlottableValue<X>, y: PlottableValue<Y>, series: PlottableValue<S>) {
        var r = _MarkRecord(kind: .line); r.setX(x); r.setY(y); r.dodge = series.plotValue.label; _record = r
    }
}

/// A symbol at a point.
public struct PointMark: _RecordMark {
    public let _record: _MarkRecord

    public init<X: Plottable, Y: Plottable>(x: PlottableValue<X>, y: PlottableValue<Y>) {
        var r = _MarkRecord(kind: .point); r.setX(x); r.setY(y); _record = r
    }
}

/// The area under a series' line, or between two values.
public struct AreaMark: _RecordMark {
    public let _record: _MarkRecord

    public init<X: Plottable, Y: Plottable>(x: PlottableValue<X>, y: PlottableValue<Y>, stacking: MarkStackingMethod = .standard) {
        var r = _MarkRecord(kind: .area); r.setX(x); r.setY(y); _record = r
    }

    public init<X: Plottable, Y: Plottable>(x: PlottableValue<X>, yStart: PlottableValue<Y>, yEnd: PlottableValue<Y>) {
        var r = _MarkRecord(kind: .area); r.setX(x); r.setYRange(yStart, yEnd); _record = r
    }

    public init<X: Plottable, Y: Plottable, S: Plottable>(x: PlottableValue<X>, y: PlottableValue<Y>, series: PlottableValue<S>, stacking: MarkStackingMethod = .standard) {
        var r = _MarkRecord(kind: .area); r.setX(x); r.setY(y); r.dodge = series.plotValue.label; _record = r
    }

    public init<X: Plottable, Y: Plottable>(xStart: PlottableValue<X>, xEnd: PlottableValue<X>, y: PlottableValue<Y>) {
        var r = _MarkRecord(kind: .area); r.setXRange(xStart, xEnd); r.setY(y); _record = r
    }
}

/// A line across the plot at a value, or between two values.
public struct RuleMark: _RecordMark {
    public let _record: _MarkRecord

    public init<X: Plottable>(x: PlottableValue<X>) {
        var r = _MarkRecord(kind: .rule); r.setX(x); _record = r
    }

    public init<Y: Plottable>(y: PlottableValue<Y>) {
        var r = _MarkRecord(kind: .rule); r.setY(y); _record = r
    }

    public init<X: Plottable, Y: Plottable>(x: PlottableValue<X>, yStart: PlottableValue<Y>, yEnd: PlottableValue<Y>) {
        var r = _MarkRecord(kind: .rule); r.setX(x); r.setYRange(yStart, yEnd); _record = r
    }

    public init<X: Plottable, Y: Plottable>(xStart: PlottableValue<X>, xEnd: PlottableValue<X>, y: PlottableValue<Y>) {
        var r = _MarkRecord(kind: .rule); r.setXRange(xStart, xEnd); r.setY(y); _record = r
    }

    public init<X: Plottable, Y: Plottable>(xStart: PlottableValue<X>, xEnd: PlottableValue<X>, yStart: PlottableValue<Y>, yEnd: PlottableValue<Y>) {
        var r = _MarkRecord(kind: .rule); r.setXRange(xStart, xEnd); r.setYRange(yStart, yEnd); _record = r
    }
}

/// A rectangle between two values on each axis, or a cell of two bands.
public struct RectangleMark: _RecordMark {
    public let _record: _MarkRecord

    public init<X: Plottable, Y: Plottable>(x: PlottableValue<X>, y: PlottableValue<Y>, width: MarkDimension = .automatic, height: MarkDimension = .automatic) {
        var r = _MarkRecord(kind: .rectangle); r.setX(x); r.setY(y); r.width = width; r.height = height; _record = r
    }

    public init<X: Plottable, Y: Plottable>(xStart: PlottableValue<X>, xEnd: PlottableValue<X>, yStart: PlottableValue<Y>, yEnd: PlottableValue<Y>) {
        var r = _MarkRecord(kind: .rectangle); r.setXRange(xStart, xEnd); r.setYRange(yStart, yEnd); _record = r
    }

    public init<X: Plottable, Y: Plottable>(x: PlottableValue<X>, yStart: PlottableValue<Y>, yEnd: PlottableValue<Y>, width: MarkDimension = .automatic) {
        var r = _MarkRecord(kind: .rectangle); r.setX(x); r.setYRange(yStart, yEnd); r.width = width; _record = r
    }

    public init<X: Plottable, Y: Plottable>(xStart: PlottableValue<X>, xEnd: PlottableValue<X>, y: PlottableValue<Y>, height: MarkDimension = .automatic) {
        var r = _MarkRecord(kind: .rectangle); r.setXRange(xStart, xEnd); r.setY(y); r.height = height; _record = r
    }
}
