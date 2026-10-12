// Chart content: marks and what composes them (the builder, `ForEach`, conditionals) and the
// mark modifiers. Content resolves to `_MarkRecord`s the chart lays out; a record carries the
// mark's kind, its plotted values per dimension, its series (`foregroundStyle(by:)`) and its
// styling.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI

/// A type that represents the content that you draw on a chart.
public protocol ChartContent {
    associatedtype Body: ChartContent
    @ChartContentBuilder @MainActor @preconcurrency var body: Body { get }
    /// Appends the records this content stands for.
    @MainActor func _collect(into records: inout [_MarkRecord])
}

extension ChartContent {
    @MainActor public func _collect(into records: inout [_MarkRecord]) { body._collect(into: &records) }
}

extension Never: ChartContent {
    public var body: Never { fatalError("Never has no body") }
    @MainActor public func _collect(into records: inout [_MarkRecord]) {}
}

/// The kinds of mark.
public enum _MarkKind: Sendable { case bar, line, point, area, rule, rectangle }

/// A mark's resolved values and style.
public struct _MarkRecord {
    public var kind: _MarkKind
    package var x: _PlotValue?
    package var xStart: _PlotValue?
    package var xEnd: _PlotValue?
    package var y: _PlotValue?
    package var yStart: _PlotValue?
    package var yEnd: _PlotValue?
    package var xLabel: String?
    package var yLabel: String?
    package var xUnit: Calendar.Component?
    package var yUnit: Calendar.Component?
    /// The series the mark belongs to (`foregroundStyle(by:)`): the scale's label and the value.
    package var seriesLabel: String?
    package var series: String?
    /// `position(by:)`: the value marks are dodged by within a band.
    package var dodge: String?
    package var style: AnyShapeStyle?
    package var opacity: Double = 1
    package var cornerRadius: CGFloat = 0
    package var lineStyle: StrokeStyle?
    package var interpolation: InterpolationMethod = .linear
    package var symbol: _SymbolShape = .circle
    package var symbolSize: CGFloat?
    package var width: MarkDimension?
    package var height: MarkDimension?
    package var offset: CGSize = .zero
    package var annotations: [_Annotation] = []
    package var zIndex: Double = 0
    /// Where the record came from, for stable annotation ids.
    package var index = 0

    package init(kind: _MarkKind) { self.kind = kind }
}

/// An annotation a mark carries: a view placed against the mark's frame.
public struct _Annotation {
    package var position: AnnotationPosition
    package var alignment: Alignment
    package var spacing: CGFloat?
    package var overflow: AnnotationOverflowResolution
    package var content: AnyView
}

// MARK: - Builder

@resultBuilder
public struct ChartContentBuilder {
    public static func buildBlock() -> EmptyChartContent { EmptyChartContent() }
    public static func buildBlock<C: ChartContent>(_ content: C) -> C { content }
    public static func buildBlock<each C: ChartContent>(_ content: repeat each C) -> _TupleChartContent<repeat each C> {
        _TupleChartContent(content: (repeat each content))
    }
    public static func buildExpression<C: ChartContent>(_ content: C) -> C { content }
    public static func buildOptional<C: ChartContent>(_ content: C?) -> _OptionalChartContent<C> { _OptionalChartContent(content: content) }
    public static func buildEither<T: ChartContent, F: ChartContent>(first: T) -> _ConditionalChartContent<T, F> { .init(storage: .first(first)) }
    public static func buildEither<T: ChartContent, F: ChartContent>(second: F) -> _ConditionalChartContent<T, F> { .init(storage: .second(second)) }
    public static func buildArray<C: ChartContent>(_ components: [C]) -> _ArrayChartContent<C> { _ArrayChartContent(contents: components) }
    @MainActor public static func buildLimitedAvailability<C: ChartContent>(_ content: C) -> AnyChartContent { AnyChartContent(content) }
}

/// Content with no marks.
public struct EmptyChartContent: ChartContent {
    public init() {}
    public var body: Never { fatalError() }
    @MainActor public func _collect(into records: inout [_MarkRecord]) {}
}

public struct _TupleChartContent<each C: ChartContent>: ChartContent {
    let content: (repeat each C)
    public var body: Never { fatalError() }
    @MainActor public func _collect(into records: inout [_MarkRecord]) {
        for element in repeat each content { element._collect(into: &records) }
    }
}

public struct _OptionalChartContent<C: ChartContent>: ChartContent {
    let content: C?
    public var body: Never { fatalError() }
    @MainActor public func _collect(into records: inout [_MarkRecord]) { content?._collect(into: &records) }
}

public struct _ConditionalChartContent<T: ChartContent, F: ChartContent>: ChartContent {
    enum Storage { case first(T), second(F) }
    let storage: Storage
    public var body: Never { fatalError() }
    @MainActor public func _collect(into records: inout [_MarkRecord]) {
        switch storage {
        case .first(let c): c._collect(into: &records)
        case .second(let c): c._collect(into: &records)
        }
    }
}

public struct _ArrayChartContent<C: ChartContent>: ChartContent {
    let contents: [C]
    public var body: Never { fatalError() }
    @MainActor public func _collect(into records: inout [_MarkRecord]) {
        for c in contents { c._collect(into: &records) }
    }
}

/// A type-erased chart content.
public struct AnyChartContent: ChartContent {
    let collect: @MainActor (inout [_MarkRecord]) -> Void
    @MainActor public init<C: ChartContent>(_ content: C) { collect = { content._collect(into: &$0) } }
    public var body: Never { fatalError() }
    @MainActor public func _collect(into records: inout [_MarkRecord]) { collect(&records) }
}

/// Plots a mark for every element of a collection.
extension ForEach: ChartContent where Content: ChartContent {
    public var body: Never { fatalError() }
    @MainActor public func _collect(into records: inout [_MarkRecord]) {
        for element in data { content(element)._collect(into: &records) }
    }
}

extension ForEach where ID == Data.Element.ID, Content: ChartContent, Data.Element: Identifiable {
    public init(_ data: Data, @ChartContentBuilder content: @escaping (Data.Element) -> Content) {
        self.init(data: data, id: \.id, content: content)
    }
}

extension ForEach where Content: ChartContent {
    public init(_ data: Data, id: KeyPath<Data.Element, ID>, @ChartContentBuilder content: @escaping (Data.Element) -> Content) {
        self.init(data: data, id: id, content: content)
    }
}

extension ForEach where Data == Range<Int>, ID == Int, Content: ChartContent {
    public init(_ data: Range<Int>, @ChartContentBuilder content: @escaping (Int) -> Content) {
        self.init(data: data, id: \.self, content: content)
    }
}

// MARK: - Mark modifiers

/// A mark with a modifier applied: the record changed after the mark makes it.
public struct _ModifiedChartContent<C: ChartContent>: ChartContent {
    let content: C
    let modify: (inout _MarkRecord) -> Void
    public var body: Never { fatalError() }
    @MainActor public func _collect(into records: inout [_MarkRecord]) {
        var own: [_MarkRecord] = []
        content._collect(into: &own)
        for var record in own {
            modify(&record)
            record.index = records.count
            records.append(record)
        }
    }
}

/// How a line or area connects its points.
public enum InterpolationMethod: Hashable, Sendable {
    case linear, monotone, catmullRom, cardinal, stepStart, stepCenter, stepEnd
}

/// The shape of a point mark or a line's symbols.
public enum _SymbolShape: Hashable, Sendable {
    case circle, square, triangle, diamond, cross, plus, asterisk, pentagon
}

/// The width or height of a bar, in points or as a fraction of the band.
public enum MarkDimension: Hashable, Sendable {
    case automatic
    case fixed(CGFloat)
    case ratio(CGFloat)
    case inset(CGFloat)

    public init(floatLiteral value: Double) { self = .fixed(CGFloat(value)) }
    public init(integerLiteral value: Int) { self = .fixed(CGFloat(value)) }
}

extension MarkDimension: ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {}

/// Where an annotation sits against its mark.
public enum AnnotationPosition: Hashable, Sendable {
    case automatic, overlay, top, bottom, leading, trailing, topLeading, topTrailing, bottomLeading, bottomTrailing
}

/// What an annotation does past the plot's edge (accepted; annotations are not moved).
public struct AnnotationOverflowResolution: Sendable {
    public enum Strategy: Sendable { case automatic, fit, disabled, padScale }
    public var x: Strategy
    public var y: Strategy
    public init(x: Strategy = .automatic, y: Strategy = .automatic) { self.x = x; self.y = y }
    public static let automatic = AnnotationOverflowResolution()
}

/// The symbol shapes `symbol(_:)` takes.
public protocol ChartSymbolShape {
    var _symbol: _SymbolShape { get }
}

public struct BasicChartSymbolShape: ChartSymbolShape, Sendable {
    public let _symbol: _SymbolShape
    public static let circle = BasicChartSymbolShape(_symbol: .circle)
    public static let square = BasicChartSymbolShape(_symbol: .square)
    public static let triangle = BasicChartSymbolShape(_symbol: .triangle)
    public static let diamond = BasicChartSymbolShape(_symbol: .diamond)
    public static let cross = BasicChartSymbolShape(_symbol: .cross)
    public static let plus = BasicChartSymbolShape(_symbol: .plus)
    public static let asterisk = BasicChartSymbolShape(_symbol: .asterisk)
    public static let pentagon = BasicChartSymbolShape(_symbol: .pentagon)
}

extension ChartSymbolShape where Self == BasicChartSymbolShape {
    public static var circle: BasicChartSymbolShape { .circle }
    public static var square: BasicChartSymbolShape { .square }
    public static var triangle: BasicChartSymbolShape { .triangle }
    public static var diamond: BasicChartSymbolShape { .diamond }
    public static var cross: BasicChartSymbolShape { .cross }
    public static var plus: BasicChartSymbolShape { .plus }
    public static var asterisk: BasicChartSymbolShape { .asterisk }
    public static var pentagon: BasicChartSymbolShape { .pentagon }
}

extension ChartContent {
    func _modified(_ modify: @escaping (inout _MarkRecord) -> Void) -> _ModifiedChartContent<Self> {
        _ModifiedChartContent(content: self, modify: modify)
    }

    /// Colours the mark by a category: every distinct value gets the next palette colour and a
    /// legend entry.
    public func foregroundStyle<D: Plottable>(by value: PlottableValue<D>) -> some ChartContent {
        let label = value.label
        let series = value.plotValue.label
        return _modified { $0.seriesLabel = label; $0.series = series }
    }

    /// Colours the mark with a style (a colour, a gradient, a material).
    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> some ChartContent {
        let erased = AnyShapeStyle(style)
        return _modified { $0.style = erased }
    }

    public func opacity(_ opacity: Double) -> some ChartContent {
        _modified { $0.opacity *= opacity }
    }

    public func cornerRadius(_ radius: CGFloat, style: RoundedCornerStyle = .continuous) -> some ChartContent {
        _modified { $0.cornerRadius = radius }
    }

    public func lineStyle(_ style: StrokeStyle) -> some ChartContent {
        _modified { $0.lineStyle = style }
    }

    public func interpolationMethod(_ method: InterpolationMethod) -> some ChartContent {
        _modified { $0.interpolation = method }
    }

    /// Shows a symbol at each point of a line (`PointMark` draws one already).
    public func symbol<S: ChartSymbolShape>(_ shape: S) -> some ChartContent {
        let symbol = shape._symbol
        return _modified { $0.symbol = symbol; if $0.kind == .line, $0.symbolSize == nil { $0.symbolSize = _defaultSymbolArea } }
    }

    public func symbol(by value: PlottableValue<some Plottable>) -> some ChartContent {
        _modified { if $0.kind == .line, $0.symbolSize == nil { $0.symbolSize = _defaultSymbolArea } }
    }

    /// The symbol's area in square points (Swift Charts' default is about 50: an 8 pt circle).
    public func symbolSize(_ area: CGFloat) -> some ChartContent {
        _modified { $0.symbolSize = area }
    }

    public func symbolSize(_ size: CGSize) -> some ChartContent {
        _modified { $0.symbolSize = size.width * size.height * .pi / 4 }
    }

    public func symbolSize(by value: PlottableValue<some Plottable>) -> some ChartContent {
        _modified { _ in }
    }

    /// Dodges marks sharing a band by a category (bars side by side instead of stacked).
    public func position<P: Plottable>(by value: PlottableValue<P>, axis: Axis? = nil, span: MarkDimension = .automatic) -> some ChartContent {
        let dodge = value.plotValue.label
        return _modified { $0.dodge = dodge }
    }

    public func offset(x: CGFloat = 0, y: CGFloat = 0) -> some ChartContent {
        _modified { $0.offset.width += x; $0.offset.height += y }
    }

    public func offset(_ value: CGSize) -> some ChartContent { offset(x: value.width, y: value.height) }

    public func zIndex(_ value: Double) -> some ChartContent {
        _modified { $0.zIndex = value }
    }

    /// Places a view against the mark.
    public func annotation<V: View>(position: AnnotationPosition = .automatic, alignment: Alignment = .center, spacing: CGFloat? = nil,
                                    overflowResolution: AnnotationOverflowResolution = .automatic, @ViewBuilder content: () -> V) -> some ChartContent {
        let annotation = _Annotation(position: position, alignment: alignment, spacing: spacing, overflow: overflowResolution, content: AnyView(content()))
        return _modified { $0.annotations.append(annotation) }
    }

    public func annotation<V: View>(position: AnnotationPosition = .automatic, alignment: Alignment = .center, spacing: CGFloat? = nil,
                                    overflowResolution: AnnotationOverflowResolution = .automatic, @ViewBuilder content: (AnnotationContext) -> V) -> some ChartContent {
        annotation(position: position, alignment: alignment, spacing: spacing, overflowResolution: overflowResolution) { content(AnnotationContext()) }
    }

    /// Accepted; the hosts do not shade by a second style yet.
    public func accessibilityLabel(_ label: String) -> some ChartContent { _modified { _ in } }
    public func accessibilityValue(_ value: String) -> some ChartContent { _modified { _ in } }
    public func accessibilityHidden(_ hidden: Bool) -> some ChartContent { _modified { _ in } }
    public func clipShape<S: Shape>(_ shape: S, style: FillStyle = FillStyle()) -> some ChartContent { _modified { _ in } }
    public func shadow(color: Color = .black, radius: CGFloat, x: CGFloat = 0, y: CGFloat = 0) -> some ChartContent { _modified { _ in } }
    public func blur(radius: CGFloat) -> some ChartContent { _modified { _ in } }
    public func alignsMarkStylesWithPlotArea(_ aligns: Bool = true) -> some ChartContent { _modified { _ in } }
}

/// Passed to an annotation's content closure (the context's members are reserved).
public struct AnnotationContext {
    public var targetSize: CGSize = .zero
}

/// The area of the default symbol: an 8 pt circle.
let _defaultSymbolArea: CGFloat = 16 * .pi
