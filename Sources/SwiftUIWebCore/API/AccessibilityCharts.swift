/// Chart descriptors (Accessibility's audio graphs, `Docs/elements/Accessibility.md`): the axes,
/// series and data points an app describes its chart with, and the SwiftUI modifier that
/// attaches one. The canvas host has no audio graph to give them to yet: the descriptor is made
/// on request (`_AccessibilityChartModifier.descriptor()`) and its title and summary are what a
/// host could announce.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// An axis of a chart descriptor: numeric or categorical.
public protocol AXDataAxisDescriptor {
    var title: String { get set }
}

/// A numeric axis: its range, gridlines and how a value reads aloud.
public final class AXNumericDataAxisDescriptor: AXDataAxisDescriptor {
    /// How values map onto the axis.
    public enum ScaleType: Int, Sendable {
        case linear
        case ln
        case log10
    }

    public var title: String
    public var range: ClosedRange<Double>
    public var gridlinePositions: [Double]
    public var scaleType: ScaleType = .linear
    public var valueDescriptionProvider: (Double) -> String

    public init(title: String, range: ClosedRange<Double>, gridlinePositions: [Double], valueDescriptionProvider: @escaping (Double) -> String) {
        self.title = title
        self.range = range
        self.gridlinePositions = gridlinePositions
        self.valueDescriptionProvider = valueDescriptionProvider
    }
}

/// A categorical axis: its categories in display order.
public final class AXCategoricalDataAxisDescriptor: AXDataAxisDescriptor {
    public var title: String
    public var categoryOrder: [String]

    public init(title: String, categoryOrder: [String]) {
        self.title = title
        self.categoryOrder = categoryOrder
    }
}

/// One value of a data point: a number on a numeric axis or a category on a categorical one.
public struct AXDataPointValue: Hashable, Sendable {
    public var number: Double
    public var category: String

    public static func number(_ number: Double) -> AXDataPointValue { AXDataPointValue(number: number, category: "") }
    public static func category(_ category: String) -> AXDataPointValue { AXDataPointValue(number: 0, category: category) }
}

/// A point of a series: its x value, an optional y value, values on the additional axes and a
/// label of its own.
public final class AXDataPoint {
    public typealias Value = AXDataPointValue

    public var xValue: Value
    public var yValue: Double?
    public var additionalValues: [Value]
    public var label: String?

    public init(x: Double, y: Double? = nil, additionalValues: [Value] = [], label: String? = nil) {
        xValue = .number(x)
        yValue = y
        self.additionalValues = additionalValues
        self.label = label
    }

    public init(x: String, y: Double? = nil, additionalValues: [Value] = [], label: String? = nil) {
        xValue = .category(x)
        yValue = y
        self.additionalValues = additionalValues
        self.label = label
    }
}

/// A named series of data points, continuous (a line) or discrete (bars, points).
public final class AXDataSeriesDescriptor {
    public var name: String
    public var isContinuous: Bool
    public var dataPoints: [AXDataPoint]

    public init(name: String, isContinuous: Bool, dataPoints: [AXDataPoint]) {
        self.name = name
        self.isContinuous = isContinuous
        self.dataPoints = dataPoints
    }
}

/// A whole chart: its title and summary, axes and series.
public final class AXChartDescriptor {
    /// The direction the chart's content reads in.
    public enum ContentDirection: Int, Sendable {
        case leftToRight
        case rightToLeft
        case topToBottom
        case bottomToTop
        case radialClockwise
        case radialCounterClockwise
    }

    public var title: String?
    public var summary: String?
    public var xAxis: any AXDataAxisDescriptor
    public var yAxis: AXNumericDataAxisDescriptor?
    public var additionalAxes: [any AXDataAxisDescriptor]
    public var series: [AXDataSeriesDescriptor]
    public var contentDirection: ContentDirection = .leftToRight
    public var contentFrame: CGRect = .zero

    public init(title: String?, summary: String?, xAxis: any AXDataAxisDescriptor, yAxis: AXNumericDataAxisDescriptor?,
                additionalAxes: [any AXDataAxisDescriptor] = [], series: [AXDataSeriesDescriptor]) {
        self.title = title
        self.summary = summary
        self.xAxis = xAxis
        self.yAxis = yAxis
        self.additionalAxes = additionalAxes
        self.series = series
    }
}

/// A type that makes a chart descriptor for `accessibilityChartDescriptor(_:)`, and updates it
/// when the chart changes.
@MainActor @preconcurrency
public protocol AXChartDescriptorRepresentable {
    func makeChartDescriptor() -> AXChartDescriptor
    func updateChartDescriptor(_ descriptor: AXChartDescriptor)
}

extension AXChartDescriptorRepresentable {
    public func updateChartDescriptor(_ descriptor: AXChartDescriptor) {}
}

/// Keeps the representable; the descriptor is made when asked for, as on Apple platforms. (The
/// conformance is an extension's, as the other modifiers', so the struct itself is not main-actor
/// isolated and the nonisolated `accessibilityChartDescriptor(_:)` can make it.)
public struct _AccessibilityChartModifier<Representable: AXChartDescriptorRepresentable> {
    let representable: Representable

    package init(representable: Representable) { self.representable = representable }

    /// The chart descriptor, made now.
    @MainActor public func descriptor() -> AXChartDescriptor { representable.makeChartDescriptor() }
}

extension _AccessibilityChartModifier: ViewModifier {
    public func body(content: Content) -> some View { content }
}

extension View {
    /// Describes the view's chart to assistive technologies with the descriptor `representable`
    /// makes.
    nonisolated public func accessibilityChartDescriptor<R: AXChartDescriptorRepresentable>(_ representable: R) -> some View {
        modifier(_AccessibilityChartModifier(representable: representable))
    }
}
