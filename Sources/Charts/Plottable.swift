// Swift Charts for SwiftUIWeb (sw-frameworks, decision 0018, Docs/elements/Charts.md): the
// `Charts` module apps import unmodified. Values plotted on an axis are `Plottable`: numbers
// make a quantitative scale, strings a nominal one (bands in order of appearance), dates a
// temporal one. `PlottableValue` pairs a value with the label the axis and legend show.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI

/// A value a chart can plot: a number, a string or a date, or a type that converts to one.
public protocol Plottable {
    associatedtype PrimitivePlottable: PrimitivePlottableProtocol
    var primitivePlottable: PrimitivePlottable { get }
    init?(primitivePlottable: PrimitivePlottable)
}

/// The values a scale understands directly.
public protocol PrimitivePlottableProtocol: Plottable where PrimitivePlottable == Self {
    var _plotValue: _PlotValue { get }
}

extension PrimitivePlottableProtocol {
    public var primitivePlottable: Self { self }
    public init?(primitivePlottable: Self) { self = primitivePlottable }
}

/// A plotted value as the scales see it.
public enum _PlotValue: Hashable, Sendable {
    case number(Double)
    case category(String)
    case date(Date)

    package var number: Double? { if case .number(let n) = self { return n } else { return nil } }
    package var category: String? { if case .category(let s) = self { return s } else { return nil } }
    package var date: Date? { if case .date(let d) = self { return d } else { return nil } }

    /// The position on a continuous scale: the number, or the date's seconds.
    package var continuous: Double? {
        switch self {
        case .number(let n): return n
        case .date(let d): return d.timeIntervalSinceReferenceDate
        case .category: return nil
        }
    }

    package var label: String {
        switch self {
        case .number(let n): return _formatNumber(n)
        case .category(let s): return s
        case .date(let d): return _formatDate(d, unit: nil)
        }
    }
}

extension Double: PrimitivePlottableProtocol { public var _plotValue: _PlotValue { .number(self) } }
extension Float: PrimitivePlottableProtocol { public var _plotValue: _PlotValue { .number(Double(self)) } }
#if !os(WASI)   // on wasm CGFloat is Double (WebGraphics)
extension CGFloat: PrimitivePlottableProtocol { public var _plotValue: _PlotValue { .number(Double(self)) } }
#endif
extension Int: PrimitivePlottableProtocol { public var _plotValue: _PlotValue { .number(Double(self)) } }
extension Int8: PrimitivePlottableProtocol { public var _plotValue: _PlotValue { .number(Double(self)) } }
extension Int16: PrimitivePlottableProtocol { public var _plotValue: _PlotValue { .number(Double(self)) } }
extension Int32: PrimitivePlottableProtocol { public var _plotValue: _PlotValue { .number(Double(self)) } }
extension Int64: PrimitivePlottableProtocol { public var _plotValue: _PlotValue { .number(Double(self)) } }
extension UInt: PrimitivePlottableProtocol { public var _plotValue: _PlotValue { .number(Double(self)) } }
extension UInt8: PrimitivePlottableProtocol { public var _plotValue: _PlotValue { .number(Double(self)) } }
extension UInt16: PrimitivePlottableProtocol { public var _plotValue: _PlotValue { .number(Double(self)) } }
extension UInt32: PrimitivePlottableProtocol { public var _plotValue: _PlotValue { .number(Double(self)) } }
extension UInt64: PrimitivePlottableProtocol { public var _plotValue: _PlotValue { .number(Double(self)) } }
extension String: PrimitivePlottableProtocol { public var _plotValue: _PlotValue { .category(self) } }
extension Date: PrimitivePlottableProtocol { public var _plotValue: _PlotValue { .date(self) } }

/// Enums with a plottable raw value plot as that value (`enum Kind: String, Plottable`).
extension Plottable where Self: RawRepresentable, RawValue: PrimitivePlottableProtocol {
    public var primitivePlottable: RawValue { rawValue }
    public init?(primitivePlottable: RawValue) { self.init(rawValue: primitivePlottable) }
}

/// Labeled data for a mark's dimension: `.value("Month", sale.month)`.
public struct PlottableValue<Value: Plottable> {
    public let label: String
    public let value: Value
    /// The calendar unit a date value stands for (`.value("Day", date, unit: .day)`): a bar
    /// spans the unit.
    package let unit: Calendar.Component?

    init(label: String, value: Value, unit: Calendar.Component? = nil) {
        self.label = label
        self.value = value
        self.unit = unit
    }

    /// Creates a plottable value with the given label and value.
    public static func value(_ label: String, _ value: Value) -> PlottableValue<Value> {
        PlottableValue(label: label, value: value)
    }

    public static func value<S: StringProtocol>(_ label: S, _ value: Value) -> PlottableValue<Value> {
        PlottableValue(label: String(label), value: value)
    }

    package var plotValue: _PlotValue { value.primitivePlottable._plotValue }
}

extension PlottableValue where Value == Date {
    /// A date value standing for a calendar unit: the mark covers the whole unit.
    public static func value(_ label: String, _ value: Date, unit: Calendar.Component, calendar: Calendar? = nil) -> PlottableValue<Date> {
        PlottableValue(label: label, value: value, unit: unit)
    }
}

// MARK: - Formatting

/// Axis label numbers: integers plain, others with up to two decimals, thousands as "1K"-style
/// only when the step itself is a whole thousand (Swift Charts keeps "1,000" below a million).
package func _formatNumber(_ n: Double) -> String {
    if n == n.rounded() && abs(n) < 1e15 {
        let whole = Int(n)
        if abs(whole) >= 1000 { return _grouped(whole) }
        return String(whole)
    }
    // Two decimals, trailing zeros dropped (no `String(format:)`: it is not in the wasm substrate).
    let hundredths = Int((abs(n) * 100).rounded())
    var s = (n < 0 ? "-" : "") + String(hundredths / 100) + "." + String(hundredths % 100 / 10) + String(hundredths % 10)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s
}

func _grouped(_ n: Int) -> String {
    let digits = Array(String(abs(n)))
    var out: [Character] = []
    for (i, c) in digits.reversed().enumerated() {
        if i > 0 && i % 3 == 0 { out.append(",") }
        out.append(c)
    }
    return (n < 0 ? "-" : "") + String(out.reversed())
}

/// Temporal axis labels: the unit's natural short form (months as "Jan", days as "12",
/// years as "2026", hours as "3 PM").
package func _formatDate(_ date: Date, unit: Calendar.Component?) -> String {
    let calendar = Calendar.current
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    switch unit ?? .day {
    case .year: return String(components.year ?? 0)
    case .month: return _monthNames[max(0, min(11, (components.month ?? 1) - 1))]
    case .hour, .minute:
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let twelve = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "AM" : "PM"
        return minute == 0 ? "\(twelve) \(suffix)" : "\(twelve):\(minute < 10 ? "0" : "")\(minute)"
    default: return String(components.day ?? 0)
    }
}

let _monthNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
