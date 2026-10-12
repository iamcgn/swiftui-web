// Axes: `AxisMarks` with its grid lines, ticks and labels, and the chart modifiers that
// configure them (`chartXAxis`, `chartYAxis`), the scales (`chartXScale`, `chartYScale`,
// `chartForegroundStyleScale`), the legend and the plot's styling. The modifiers are view
// modifiers, as Swift Charts' are: they set an environment configuration every chart below
// them reads.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI

/// Which values an axis marks.
public struct AxisMarkValues: Sendable {
    package enum Kind: Sendable {
        case automatic(desiredCount: Int?)
        case values([_PlotValue])
        case strideBy(Double)
        case strideCalendar(Calendar.Component, Int)
    }
    package let kind: Kind

    public static var automatic: AxisMarkValues { AxisMarkValues(kind: .automatic(desiredCount: nil)) }
    public static func automatic(desiredCount: Int? = nil, roundLowerBound: Bool? = nil, roundUpperBound: Bool? = nil) -> AxisMarkValues {
        AxisMarkValues(kind: .automatic(desiredCount: desiredCount))
    }
    public static func automatic(minimumStride: Int, desiredCount: Int? = nil) -> AxisMarkValues {
        AxisMarkValues(kind: .automatic(desiredCount: desiredCount))
    }
    public static func values<V: Plottable>(_ values: [V]) -> AxisMarkValues {
        AxisMarkValues(kind: .values(values.map { $0.primitivePlottable._plotValue }))
    }
    public static func stride(by step: Double) -> AxisMarkValues { AxisMarkValues(kind: .strideBy(step)) }
    public static func stride(by component: Calendar.Component, count: Int = 1, roundLowerBound: Bool? = nil, roundUpperBound: Bool? = nil, calendar: Calendar? = nil) -> AxisMarkValues {
        AxisMarkValues(kind: .strideCalendar(component, count))
    }
}

/// The side of the plot an axis sits on.
public enum AxisMarkPosition: Hashable, Sendable {
    case automatic, leading, trailing, top, bottom
}

/// Preset arrangements of an axis's marks.
public enum AxisMarkPreset: Hashable, Sendable {
    case automatic, aligned, extended
}

/// The parts of an axis mark (`AxisGridLine`, `AxisTick`, `AxisValueLabel`).
public protocol AxisMark {
    var _part: _AxisPart { get }
}

public struct _AxisPart {
    package enum Kind { case gridLine, tick, label }
    package let kind: Kind
    package var stroke: StrokeStyle?
    package var color: Color?
    package var length: CGFloat?
    package var anchor: UnitPoint?
    package var centered = false
    package var collisionResolution: AxisValueLabelCollisionResolution = .automatic
    package var format: ((_PlotValue) -> String)?
    package var content: ((_PlotValue) -> AnyView)?
}

public struct AxisGridLine: AxisMark {
    public let _part: _AxisPart
    public init(centered: Bool? = nil, stroke: StrokeStyle? = nil) {
        var part = _AxisPart(kind: .gridLine); part.stroke = stroke; part.centered = centered ?? false; _part = part
    }
}

public struct AxisTick: AxisMark {
    public enum Length: Sendable { case automatic, label, longestLabel, fixed(CGFloat) }
    public let _part: _AxisPart
    public init(centered: Bool? = nil, length: Length = .automatic, stroke: StrokeStyle? = nil) {
        var part = _AxisPart(kind: .tick); part.stroke = stroke; part.centered = centered ?? false
        if case .fixed(let l) = length { part.length = l }
        _part = part
    }
    public init(centered: Bool? = nil, length: CGFloat, stroke: StrokeStyle? = nil) {
        self.init(centered: centered, length: .fixed(length), stroke: stroke)
    }
}

/// What a label does when it would collide with its neighbour (accepted; labels that would
/// overlap the plot's end are dropped, as Swift Charts does).
public enum AxisValueLabelCollisionResolution: Hashable, Sendable {
    case automatic, greedy, disabled, truncate
}

public struct AxisValueLabel: AxisMark {
    public let _part: _AxisPart

    public init(centered: Bool? = nil, anchor: UnitPoint? = nil, multiLabelAlignment: Alignment? = nil, collisionResolution: AxisValueLabelCollisionResolution = .automatic,
                offsetsMarks: Bool? = nil, orientation: AxisValueLabelOrientation = .horizontal, horizontalSpacing: CGFloat? = nil, verticalSpacing: CGFloat? = nil) {
        var part = _AxisPart(kind: .label); part.anchor = anchor; part.centered = centered ?? false; part.collisionResolution = collisionResolution; _part = part
    }

    /// A label with a fixed text for every value.
    public init(_ text: String, centered: Bool? = nil, anchor: UnitPoint? = nil, collisionResolution: AxisValueLabelCollisionResolution = .automatic) {
        var part = _AxisPart(kind: .label); part.anchor = anchor; part.centered = centered ?? false; part.format = { _ in text }; _part = part
    }

    /// A label formatted with a format style (dates and numbers).
    public init<F: FormatStyle>(format: F, centered: Bool? = nil, anchor: UnitPoint? = nil, collisionResolution: AxisValueLabelCollisionResolution = .automatic)
        where F.FormatInput: Plottable, F.FormatOutput == String {
        var part = _AxisPart(kind: .label); part.anchor = anchor; part.centered = centered ?? false
        part.format = { value in
            if let typed = _plottable(F.FormatInput.self, from: value) { return format.format(typed) }
            return value.label
        }
        _part = part
    }

    /// A label with custom content.
    public init<V: View>(centered: Bool? = nil, anchor: UnitPoint? = nil, collisionResolution: AxisValueLabelCollisionResolution = .automatic, @ViewBuilder content: () -> V) {
        var part = _AxisPart(kind: .label); part.anchor = anchor; part.centered = centered ?? false
        let view = AnyView(content())
        part.content = { _ in view }
        _part = part
    }
}

public enum AxisValueLabelOrientation: Hashable, Sendable { case horizontal, vertical, verticalReversed }

/// Converts a scale's value back to a plottable type (for formatted labels).
func _plottable<P: Plottable>(_ type: P.Type, from value: _PlotValue) -> P? {
    switch value {
    case .number(let n):
        if let d = n as? P.PrimitivePlottable { return P(primitivePlottable: d) }
        if P.PrimitivePlottable.self == Int.self, let i = Int(exactly: n) as? P.PrimitivePlottable { return P(primitivePlottable: i) }
        if P.PrimitivePlottable.self == Float.self, let f = Float(n) as? P.PrimitivePlottable { return P(primitivePlottable: f) }
        #if !os(WASI)
        if P.PrimitivePlottable.self == CGFloat.self, let f = CGFloat(n) as? P.PrimitivePlottable { return P(primitivePlottable: f) }
        #endif
        return nil
    case .category(let s): return (s as? P.PrimitivePlottable).flatMap { P(primitivePlottable: $0) }
    case .date(let d): return (d as? P.PrimitivePlottable).flatMap { P(primitivePlottable: $0) }
    }
}

/// The content of an axis: one or more `AxisMarks`.
public protocol AxisContent {
    var _axisMarks: [AxisMarks] { get }
}

@resultBuilder
public struct AxisContentBuilder {
    public static func buildBlock(_ marks: AxisMarks...) -> [AxisMarks] { marks }
    public static func buildBlock<C: AxisContent>(_ content: C) -> [AxisMarks] { content._axisMarks }
    public static func buildOptional(_ marks: [AxisMarks]?) -> [AxisMarks] { marks ?? [] }
    public static func buildEither(first: [AxisMarks]) -> [AxisMarks] { first }
    public static func buildEither(second: [AxisMarks]) -> [AxisMarks] { second }
}

@resultBuilder
public struct AxisMarkBuilder {
    public static func buildBlock(_ parts: any AxisMark...) -> [any AxisMark] { parts }
    public static func buildOptional(_ parts: [any AxisMark]?) -> [any AxisMark] { parts ?? [] }
    public static func buildEither(first: [any AxisMark]) -> [any AxisMark] { first }
    public static func buildEither(second: [any AxisMark]) -> [any AxisMark] { second }
    public static func buildExpression(_ part: any AxisMark) -> any AxisMark { part }
}

/// A group of axis marks: grid lines, ticks and labels at the values chosen.
public struct AxisMarks: AxisContent {
    package let values: AxisMarkValues
    package let position: AxisMarkPosition
    package let preset: AxisMarkPreset
    package let parts: [_AxisPart]
    /// `AxisMarks { value in ... }`: the parts per value (evaluated with the value).
    package let partsForValue: ((AxisValue) -> [_AxisPart])?
    package let stroke: StrokeStyle?

    public var _axisMarks: [AxisMarks] { [self] }

    /// Marks with the default grid line, tick and label at each value.
    public init(preset: AxisMarkPreset = .automatic, position: AxisMarkPosition = .automatic, values: AxisMarkValues = .automatic, stroke: StrokeStyle? = nil) {
        self.values = values; self.position = position; self.preset = preset; self.stroke = stroke
        parts = _AxisPart.defaults
        partsForValue = nil
    }

    public init<V: Plottable>(preset: AxisMarkPreset = .automatic, position: AxisMarkPosition = .automatic, values: [V], stroke: StrokeStyle? = nil) {
        self.init(preset: preset, position: position, values: .values(values), stroke: stroke)
    }

    /// Marks with the given parts at each value.
    public init(preset: AxisMarkPreset = .automatic, position: AxisMarkPosition = .automatic, values: AxisMarkValues = .automatic, @AxisMarkBuilder content: () -> [any AxisMark]) {
        self.values = values; self.position = position; self.preset = preset; stroke = nil
        parts = content().map(\._part)
        partsForValue = nil
    }

    public init<V: Plottable>(preset: AxisMarkPreset = .automatic, position: AxisMarkPosition = .automatic, values: [V], @AxisMarkBuilder content: () -> [any AxisMark]) {
        self.init(preset: preset, position: position, values: .values(values), content: content)
    }

    /// Marks whose parts depend on the value (`AxisMarks { value in if value.index % 2 == 0 { AxisValueLabel() } }`).
    public init(preset: AxisMarkPreset = .automatic, position: AxisMarkPosition = .automatic, values: AxisMarkValues = .automatic, @AxisMarkBuilder content: @escaping (AxisValue) -> [any AxisMark]) {
        self.values = values; self.position = position; self.preset = preset; stroke = nil
        parts = []
        partsForValue = { content($0).map(\._part) }
    }

    public init<V: Plottable>(preset: AxisMarkPreset = .automatic, position: AxisMarkPosition = .automatic, values: [V], @AxisMarkBuilder content: @escaping (AxisValue) -> [any AxisMark]) {
        self.init(preset: preset, position: position, values: .values(values), content: content)
    }

    func resolvedParts(for value: AxisValue) -> [_AxisPart] { partsForValue?(value) ?? parts }
}

extension _AxisPart {
    static var defaults: [_AxisPart] { [_AxisPart(kind: .gridLine), _AxisPart(kind: .tick), _AxisPart(kind: .label)] }
}

/// A value an axis marks, as the marks' closure sees it.
public struct AxisValue {
    public let index: Int
    public let count: Int
    let value: _PlotValue

    /// The value as a plottable type, if it is one.
    public func `as`<P: Plottable>(_ type: P.Type) -> P? { _plottable(type, from: value) }
}

/// Custom axis content (`AxisContent` conformers from a builder).
public struct _AxisMarksList: AxisContent {
    public let _axisMarks: [AxisMarks]
}

extension Array: AxisContent where Element == AxisMarks {
    public var _axisMarks: [AxisMarks] { self }
}

// MARK: - Configuration carried by the environment

/// An axis as the chart modifiers configured it.
package struct _AxisConfiguration {
    package var visibility: Visibility = .automatic
    package var marks: [AxisMarks]? = nil
    package var label: AnyView? = nil
    package var labelPosition: AxisMarkPosition = .automatic
}

/// A scale's domain as `chartXScale` / `chartYScale` set it.
package enum _ScaleDomain {
    case numbers(ClosedRange<Double>)
    case categories([String])
    case dates(ClosedRange<Date>)
}

package struct _LegendConfiguration {
    package var visibility: Visibility = .automatic
    package var position: AnnotationPosition = .bottom
    package var alignment: Alignment? = nil
    package var spacing: CGFloat? = nil
}

/// Everything the chart modifiers set.
package struct _ChartConfiguration {
    package var xAxis = _AxisConfiguration()
    package var yAxis = _AxisConfiguration()
    package var legend = _LegendConfiguration()
    package var xDomain: _ScaleDomain?
    package var yDomain: _ScaleDomain?
    /// `chartForegroundStyleScale`: colours by series value, or the palette in order.
    package var foregroundStyles: [(String, AnyShapeStyle)]?
    package var foregroundPalette: [AnyShapeStyle]?
    package var plotStyle: ((ChartPlotContent) -> AnyView)?
    package var overlay: ((ChartProxy) -> AnyView)?
    package var background: ((ChartProxy) -> AnyView)?
    package var symbolScale: [(String, _SymbolShape)]?
    package var xAxisLabel: AnyView?
    package var yAxisLabel: AnyView?

    package init() {}
}

struct _ChartConfigurationKey: EnvironmentKey {
    static var defaultValue: _ChartConfiguration { _ChartConfiguration() }
}

extension EnvironmentValues {
    package var _chartConfiguration: _ChartConfiguration {
        get { self[_ChartConfigurationKey.self] }
        set { self[_ChartConfigurationKey.self] = newValue }
    }
}

/// The plot area view `chartPlotStyle` receives.
public struct ChartPlotContent: View {
    let content: AnyView
    public var body: some View { content }
}

/// A view modifier on `_ChartConfiguration`.
struct _ChartConfigurationModifier: ViewModifier {
    let change: (inout _ChartConfiguration) -> Void
    func body(content: Content) -> some View {
        content.transformEnvironment(\._chartConfiguration) { change(&$0) }
    }
}

extension View {
    func _chart(_ change: @escaping (inout _ChartConfiguration) -> Void) -> some View {
        modifier(_ChartConfigurationModifier(change: change))
    }

    /// Configures the x axis of charts in this view.
    public func chartXAxis(_ visibility: Visibility) -> some View {
        _chart { $0.xAxis.visibility = visibility }
    }

    public func chartXAxis<Content: AxisContent>(@AxisContentBuilder content: () -> Content) -> some View {
        let marks = content()._axisMarks
        return _chart { $0.xAxis.marks = marks }
    }

    public func chartYAxis(_ visibility: Visibility) -> some View {
        _chart { $0.yAxis.visibility = visibility }
    }

    public func chartYAxis<Content: AxisContent>(@AxisContentBuilder content: () -> Content) -> some View {
        let marks = content()._axisMarks
        return _chart { $0.yAxis.marks = marks }
    }

    /// Titles for the axes.
    public func chartXAxisLabel(_ label: String, position: AxisMarkPosition = .automatic, alignment: Alignment? = nil, spacing: CGFloat? = nil) -> some View {
        let view = AnyView(Text(label))
        return _chart { $0.xAxisLabel = view; $0.xAxis.labelPosition = position }
    }

    public func chartXAxisLabel<V: View>(position: AxisMarkPosition = .automatic, alignment: Alignment? = nil, spacing: CGFloat? = nil, @ViewBuilder content: () -> V) -> some View {
        let view = AnyView(content())
        return _chart { $0.xAxisLabel = view; $0.xAxis.labelPosition = position }
    }

    public func chartYAxisLabel(_ label: String, position: AxisMarkPosition = .automatic, alignment: Alignment? = nil, spacing: CGFloat? = nil) -> some View {
        let view = AnyView(Text(label))
        return _chart { $0.yAxisLabel = view; $0.yAxis.labelPosition = position }
    }

    public func chartYAxisLabel<V: View>(position: AxisMarkPosition = .automatic, alignment: Alignment? = nil, spacing: CGFloat? = nil, @ViewBuilder content: () -> V) -> some View {
        let view = AnyView(content())
        return _chart { $0.yAxisLabel = view; $0.yAxis.labelPosition = position }
    }

    /// The legend's visibility and placement.
    public func chartLegend(_ visibility: Visibility) -> some View {
        _chart { $0.legend.visibility = visibility }
    }

    public func chartLegend(position: AnnotationPosition = .automatic, alignment: Alignment? = nil, spacing: CGFloat? = nil) -> some View {
        _chart { $0.legend.position = position == .automatic ? .bottom : position; $0.legend.alignment = alignment; $0.legend.spacing = spacing }
    }

    public func chartLegend<V: View>(position: AnnotationPosition = .automatic, alignment: Alignment? = nil, spacing: CGFloat? = nil, @ViewBuilder content: () -> V) -> some View {
        _chart { $0.legend.position = position == .automatic ? .bottom : position; $0.legend.alignment = alignment; $0.legend.spacing = spacing }
    }

    /// Fixed domains.
    public func chartXScale(domain: ClosedRange<some BinaryFloatingPoint>, type: ScaleType? = nil) -> some View {
        let range = Double(domain.lowerBound)...Double(domain.upperBound)
        return _chart { $0.xDomain = .numbers(range) }
    }

    public func chartXScale(domain: ClosedRange<some BinaryInteger>, type: ScaleType? = nil) -> some View {
        let range = Double(domain.lowerBound)...Double(domain.upperBound)
        return _chart { $0.xDomain = .numbers(range) }
    }

    public func chartXScale(domain: ClosedRange<Date>, type: ScaleType? = nil) -> some View {
        _chart { $0.xDomain = .dates(domain) }
    }

    public func chartXScale(domain: [String], type: ScaleType? = nil) -> some View {
        _chart { $0.xDomain = .categories(domain) }
    }

    public func chartXScale(domain: ScaleDomain, type: ScaleType? = nil) -> some View {
        _chart { _ in }
    }

    public func chartYScale(domain: ClosedRange<some BinaryFloatingPoint>, type: ScaleType? = nil) -> some View {
        let range = Double(domain.lowerBound)...Double(domain.upperBound)
        return _chart { $0.yDomain = .numbers(range) }
    }

    public func chartYScale(domain: ClosedRange<some BinaryInteger>, type: ScaleType? = nil) -> some View {
        let range = Double(domain.lowerBound)...Double(domain.upperBound)
        return _chart { $0.yDomain = .numbers(range) }
    }

    public func chartYScale(domain: ClosedRange<Date>, type: ScaleType? = nil) -> some View {
        _chart { $0.yDomain = .dates(domain) }
    }

    public func chartYScale(domain: [String], type: ScaleType? = nil) -> some View {
        _chart { $0.yDomain = .categories(domain) }
    }

    public func chartYScale(domain: ScaleDomain, type: ScaleType? = nil) -> some View {
        _chart { _ in }
    }

    /// Colours per series value (`["Online": .blue, "Store": .green]`) or a palette in order.
    public func chartForegroundStyleScale<S: ShapeStyle>(_ mapping: KeyValuePairs<String, S>) -> some View {
        let styles = mapping.map { ($0.key, AnyShapeStyle($0.value)) }
        return _chart { $0.foregroundStyles = styles }
    }

    public func chartForegroundStyleScale<S: ShapeStyle>(range: [S]) -> some View {
        let palette = range.map { AnyShapeStyle($0) }
        return _chart { $0.foregroundPalette = palette }
    }

    public func chartForegroundStyleScale<S: ShapeStyle>(domain: [String], range: [S]) -> some View {
        let styles = zip(domain, range).map { ($0, AnyShapeStyle($1)) }
        return _chart { $0.foregroundStyles = styles }
    }

    public func chartForegroundStyleScale<S: ShapeStyle>(_ mapping: @escaping (String) -> S) -> some View {
        _chart { _ in }
    }

    public func chartSymbolScale<S: ChartSymbolShape>(_ mapping: KeyValuePairs<String, S>) -> some View {
        let scale = mapping.map { ($0.key, $0.value._symbol) }
        return _chart { $0.symbolScale = scale }
    }

    /// Styles the plot area (its frame, background, clipping).
    public func chartPlotStyle<V: View>(@ViewBuilder content: @escaping (ChartPlotContent) -> V) -> some View {
        _chart { $0.plotStyle = { AnyView(content($0)) } }
    }

    /// Views over and under the plot with a proxy for its geometry.
    public func chartOverlay<V: View>(alignment: Alignment = .center, @ViewBuilder content: @escaping (ChartProxy) -> V) -> some View {
        _chart { $0.overlay = { AnyView(content($0)) } }
    }

    public func chartBackground<V: View>(alignment: Alignment = .center, @ViewBuilder content: @escaping (ChartProxy) -> V) -> some View {
        _chart { $0.background = { AnyView(content($0)) } }
    }

    /// Accepted; the scrolling, selection and gesture modifiers do nothing yet.
    public func chartScrollableAxes(_ axes: Axis.Set) -> some View { self }
    public func chartXVisibleDomain(length: some Numeric) -> some View { self }
    public func chartScrollPosition<V: Plottable>(x: Binding<V>) -> some View { self }
    public func chartScrollPosition<V: Plottable>(y: Binding<V>) -> some View { self }
    public func chartXSelection<V: Plottable>(value: Binding<V?>) -> some View { self }
    public func chartYSelection<V: Plottable>(value: Binding<V?>) -> some View { self }
    public func chartXSelection<V: Plottable>(range: Binding<ClosedRange<V>?>) -> some View { self }
    public func chartAngleSelection<V: Plottable>(value: Binding<V?>) -> some View { self }
    public func chartGesture(_ gesture: @escaping (ChartProxy) -> some Gesture) -> some View { self }
}

/// The kinds of scale (accepted; every continuous scale is linear).
public enum ScaleType: Hashable, Sendable {
    case linear, log, date, category, symmetricLog, squareRoot
}

/// Scale domain options (`.automatic(includesZero:reversed:)`).
public struct ScaleDomain: Sendable {
    public static func automatic(includesZero: Bool? = nil, reversed: Bool? = nil) -> ScaleDomain { ScaleDomain() }
    public static var automatic: ScaleDomain { ScaleDomain() }
}
