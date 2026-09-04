// Gauge (Docs/elements/Gauge.md): the macOS linear capacity gauge (a label over a tinted bar,
// value and bounds labels) and the accessory styles (linear with a knob, linear capacity,
// circular with a marker, circular capacity).

/// A view that shows a value within a range.
public struct Gauge<Label: View, CurrentValueLabel: View, BoundsLabel: View, MarkedValueLabels: View>: View {
    /// The value normalised into 0…1.
    package let value: Double
    package let label: Label
    package let currentValueLabel: CurrentValueLabel?
    package let minimumValueLabel: BoundsLabel?
    package let maximumValueLabel: BoundsLabel?
    package let markedValueLabels: MarkedValueLabels?

    @Environment(\.gaugeStyle) private var style

    public var body: some View {
        let configuration = GaugeStyleConfiguration(
            value: value,
            label: GaugeStyleConfiguration.Label(view: AnyView(label)),
            currentValueLabel: currentValueLabel.map { GaugeStyleConfiguration.CurrentValueLabel(view: AnyView($0)) },
            minimumValueLabel: minimumValueLabel.map { GaugeStyleConfiguration.MinimumValueLabel(view: AnyView($0)) },
            maximumValueLabel: maximumValueLabel.map { GaugeStyleConfiguration.MaximumValueLabel(view: AnyView($0)) })
        style.makeBodyErased(configuration)
    }

    package static func normalized<V: BinaryFloatingPoint>(_ value: V, in bounds: ClosedRange<V>) -> Double {
        let span = Double(bounds.upperBound) - Double(bounds.lowerBound)
        guard span > 0 else { return 0 }
        return min(max((Double(value) - Double(bounds.lowerBound)) / span, 0), 1)
    }
}

extension Gauge where CurrentValueLabel == EmptyView, BoundsLabel == EmptyView, MarkedValueLabels == EmptyView {
    /// Creates a gauge showing a value within a range and describes the gauge's purpose.
    public init<V: BinaryFloatingPoint>(value: V, in bounds: ClosedRange<V> = 0...1, @ViewBuilder label: () -> Label) {
        self.value = Self.normalized(value, in: bounds)
        self.label = label()
        currentValueLabel = nil
        minimumValueLabel = nil
        maximumValueLabel = nil
        markedValueLabels = nil
    }
}

extension Gauge where BoundsLabel == EmptyView, MarkedValueLabels == EmptyView {
    /// Creates a gauge showing a value within a range and that describes the gauge's purpose
    /// and current value.
    public init<V: BinaryFloatingPoint>(value: V, in bounds: ClosedRange<V> = 0...1, @ViewBuilder label: () -> Label,
                                        @ViewBuilder currentValueLabel: () -> CurrentValueLabel) {
        self.value = Self.normalized(value, in: bounds)
        self.label = label()
        self.currentValueLabel = currentValueLabel()
        minimumValueLabel = nil
        maximumValueLabel = nil
        markedValueLabels = nil
    }
}

extension Gauge where MarkedValueLabels == EmptyView {
    /// Creates a gauge showing a value within a range and describes the gauge's current,
    /// minimum, and maximum values.
    public init<V: BinaryFloatingPoint>(value: V, in bounds: ClosedRange<V> = 0...1, @ViewBuilder label: () -> Label,
                                        @ViewBuilder currentValueLabel: () -> CurrentValueLabel,
                                        @ViewBuilder minimumValueLabel: () -> BoundsLabel, @ViewBuilder maximumValueLabel: () -> BoundsLabel) {
        self.value = Self.normalized(value, in: bounds)
        self.label = label()
        self.currentValueLabel = currentValueLabel()
        self.minimumValueLabel = minimumValueLabel()
        self.maximumValueLabel = maximumValueLabel()
        markedValueLabels = nil
    }
}

extension Gauge where BoundsLabel == EmptyView {
    /// Creates a gauge representing a value within a range and describes the gauge's purpose,
    /// current value, and marked values (the marked labels are accepted and not drawn).
    public init<V: BinaryFloatingPoint>(value: V, in bounds: ClosedRange<V> = 0...1, @ViewBuilder label: () -> Label,
                                        @ViewBuilder currentValueLabel: () -> CurrentValueLabel,
                                        @ViewBuilder markedValueLabels: () -> MarkedValueLabels) {
        self.value = Self.normalized(value, in: bounds)
        self.label = label()
        self.currentValueLabel = currentValueLabel()
        minimumValueLabel = nil
        maximumValueLabel = nil
        self.markedValueLabels = markedValueLabels()
    }
}

extension Gauge {
    /// Creates a gauge representing a value within a range and describes the gauge's purpose,
    /// current, minimum, and maximum values, and marked values.
    public init<V: BinaryFloatingPoint>(value: V, in bounds: ClosedRange<V> = 0...1, @ViewBuilder label: () -> Label,
                                        @ViewBuilder currentValueLabel: () -> CurrentValueLabel,
                                        @ViewBuilder minimumValueLabel: () -> BoundsLabel, @ViewBuilder maximumValueLabel: () -> BoundsLabel,
                                        @ViewBuilder markedValueLabels: () -> MarkedValueLabels) {
        self.value = Self.normalized(value, in: bounds)
        self.label = label()
        self.currentValueLabel = currentValueLabel()
        self.minimumValueLabel = minimumValueLabel()
        self.maximumValueLabel = maximumValueLabel()
        self.markedValueLabels = markedValueLabels()
    }
}

// MARK: - Styles

/// The properties of a gauge instance.
public struct GaugeStyleConfiguration {
    public struct Label: View {
        package let view: AnyView
        package init(view: AnyView) { self.view = view }
        public var body: some View { view }
    }
    public struct CurrentValueLabel: View {
        package let view: AnyView
        package init(view: AnyView) { self.view = view }
        public var body: some View { view }
    }
    public struct MinimumValueLabel: View {
        package let view: AnyView
        package init(view: AnyView) { self.view = view }
        public var body: some View { view }
    }
    public struct MaximumValueLabel: View {
        package let view: AnyView
        package init(view: AnyView) { self.view = view }
        public var body: some View { view }
    }

    /// The value, normalised into 0…1.
    public var value: Double
    public var label: Label
    public var currentValueLabel: CurrentValueLabel?
    public var minimumValueLabel: MinimumValueLabel?
    public var maximumValueLabel: MaximumValueLabel?

    package init(value: Double, label: Label, currentValueLabel: CurrentValueLabel?, minimumValueLabel: MinimumValueLabel?, maximumValueLabel: MaximumValueLabel?) {
        self.value = value
        self.label = label
        self.currentValueLabel = currentValueLabel
        self.minimumValueLabel = minimumValueLabel
        self.maximumValueLabel = maximumValueLabel
    }
}

/// Defines the implementation of all gauge instances within a view hierarchy.
public protocol GaugeStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = GaugeStyleConfiguration
}

extension GaugeStyle {
    @MainActor
    package func makeBodyErased(_ configuration: Configuration) -> AnyView {
        AnyView(makeBody(configuration: configuration))
    }
}

/// The default gauge view style in the current context of the view being styled (the linear
/// capacity gauge on macOS).
public struct DefaultGaugeStyle: GaugeStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { _LinearCapacityGauge(configuration: configuration) }
}

/// A gauge style that shows a bar that fills from leading to trailing edges as the gauge's
/// current value increases.
public struct LinearCapacityGaugeStyle: GaugeStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { _LinearCapacityGauge(configuration: configuration) }
}

/// A gauge style that displays bar with a point marker to indicate the current value.
public struct AccessoryLinearGaugeStyle: GaugeStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { _AccessoryLinearGauge(configuration: configuration) }
}

/// A gauge style that displays bar that fills from leading to trailing edges as the gauge's
/// current value increases.
public struct AccessoryLinearCapacityGaugeStyle: GaugeStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { _AccessoryLinearCapacityGauge(configuration: configuration) }
}

/// A gauge style that displays an open ring with a marker that appears at a point along the
/// ring to indicate the gauge's current value.
public struct AccessoryCircularGaugeStyle: GaugeStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { _AccessoryCircularGauge(configuration: configuration, capacity: false) }
}

/// A gauge style that displays a closed ring that's partially filled in to indicate the gauge's
/// current value.
public struct AccessoryCircularCapacityGaugeStyle: GaugeStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View { _AccessoryCircularGauge(configuration: configuration, capacity: true) }
}

extension GaugeStyle where Self == DefaultGaugeStyle {
    public static var automatic: DefaultGaugeStyle { DefaultGaugeStyle() }
}
extension GaugeStyle where Self == LinearCapacityGaugeStyle {
    public static var linearCapacity: LinearCapacityGaugeStyle { LinearCapacityGaugeStyle() }
}
extension GaugeStyle where Self == AccessoryLinearGaugeStyle {
    public static var accessoryLinear: AccessoryLinearGaugeStyle { AccessoryLinearGaugeStyle() }
}
extension GaugeStyle where Self == AccessoryLinearCapacityGaugeStyle {
    public static var accessoryLinearCapacity: AccessoryLinearCapacityGaugeStyle { AccessoryLinearCapacityGaugeStyle() }
}
extension GaugeStyle where Self == AccessoryCircularGaugeStyle {
    public static var accessoryCircular: AccessoryCircularGaugeStyle { AccessoryCircularGaugeStyle() }
}
extension GaugeStyle where Self == AccessoryCircularCapacityGaugeStyle {
    public static var accessoryCircularCapacity: AccessoryCircularCapacityGaugeStyle { AccessoryCircularCapacityGaugeStyle() }
}

package struct GaugeStyleKey: EnvironmentKey {
    package nonisolated(unsafe) static let defaultValue: any GaugeStyle = DefaultGaugeStyle()
}

extension EnvironmentValues {
    package var gaugeStyle: any GaugeStyle {
        get { self[GaugeStyleKey.self] }
        set { self[GaugeStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for gauges within this view.
    nonisolated public func gaugeStyle<S: GaugeStyle>(_ style: S) -> some View {
        environment(\.gaugeStyle, style)
    }
}

// MARK: - Bodies

/// Linear capacity: the label centred over a 16 pt bar (the bounds labels beside it at the
/// stack spacing), the current value label centred under it; the stack's default spacings.
package struct _LinearCapacityGauge {
    package let configuration: GaugeStyleConfiguration
    package init(configuration: GaugeStyleConfiguration) { self.configuration = configuration }
}

extension _LinearCapacityGauge: View {
    package var body: some View {
        VStack {
            configuration.label
            HStack(spacing: PlatformMetrics.gaugeBoundsSpacing) {
                if let minimum = configuration.minimumValueLabel { minimum }
                _GaugeBar(kind: .capacity, fraction: configuration.value)
                if let maximum = configuration.maximumValueLabel { maximum }
            }
            if let current = configuration.currentValueLabel { current }
        }
    }
}

/// Accessory linear capacity: the label, an 8 pt capsule bar and the secondary 12 pt current
/// value label 6 pt apart, leading-aligned, with the bounds labels beside the column.
package struct _AccessoryLinearCapacityGauge {
    package let configuration: GaugeStyleConfiguration
    package init(configuration: GaugeStyleConfiguration) { self.configuration = configuration }
}

extension _AccessoryLinearCapacityGauge: View {
    package var body: some View {
        HStack(spacing: PlatformMetrics.gaugeBoundsSpacing) {
            if let minimum = configuration.minimumValueLabel { minimum }
            VStack(alignment: .leading, spacing: PlatformMetrics.gaugeAccessorySpacing) {
                configuration.label
                _GaugeBar(kind: .accessoryCapacity, fraction: configuration.value)
                if let current = configuration.currentValueLabel {
                    // 12 pt glyphs a point further down than the 6 pt spacing (the golden's 52 pt height).
                    current.font(.system(size: PlatformMetrics.gaugeAccessoryCapacityValueSize)).foregroundColor(.secondary)
                        .padding(.top, PlatformMetrics.gaugeAccessoryValueExtraGap)
                }
            }
            if let maximum = configuration.maximumValueLabel { maximum }
        }
    }
}

/// Accessory linear: an 8 pt track with a knob, the minimum (or current) value label before it
/// and the maximum after it in the 17 pt semibold font, centred on the track and overflowing
/// the gauge's 8 pt height.
package struct _AccessoryLinearGauge {
    package let configuration: GaugeStyleConfiguration
    package init(configuration: GaugeStyleConfiguration) { self.configuration = configuration }
}

extension _AccessoryLinearGauge: View {
    package var body: some View {
        let leading: AnyView? = configuration.minimumValueLabel.map { AnyView($0) } ?? configuration.currentValueLabel.map { AnyView($0) }
        let trailing: AnyView? = configuration.maximumValueLabel.map { AnyView($0) }
        _AccessoryLinearLayout(hasLeading: leading != nil, hasTrailing: trailing != nil) {
            if let leading { leading.font(.system(size: PlatformMetrics.gaugeAccessoryValueSize, weight: .semibold)) }
            _GaugeBar(kind: .accessoryLinear, fraction: configuration.value)
            if let trailing { trailing.font(.system(size: PlatformMetrics.gaugeAccessoryValueSize, weight: .semibold)) }
        }
    }
}

/// The accessory linear row: as wide as proposed and as tall as the track; the labels are
/// centred on the track (the row's height ignores them) and the track fills the rest.
package struct _AccessoryLinearLayout: Layout {
    package let hasLeading: Bool
    package let hasTrailing: Bool

    package init(hasLeading: Bool, hasTrailing: Bool) {
        self.hasLeading = hasLeading
        self.hasTrailing = hasTrailing
    }

    private func labelWidths(_ subviews: Subviews) -> (leading: CGFloat, trailing: CGFloat) {
        let leading = hasLeading ? subviews[0].sizeThatFits(.unspecified).width + PlatformMetrics.gaugeBoundsSpacing : 0
        let trailing = hasTrailing ? subviews[subviews.count - 1].sizeThatFits(.unspecified).width + PlatformMetrics.gaugeBoundsSpacing : 0
        return (leading, trailing)
    }

    package func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let widths = labelWidths(subviews)
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? widths.leading + widths.trailing + PlatformMetrics.progressBarIdealWidth
        return CGSize(width: width, height: PlatformMetrics.gaugeAccessoryBarHeight)
    }

    package func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let widths = labelWidths(subviews)
        let trackIndex = hasLeading ? 1 : 0
        if hasLeading {
            subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: .unspecified)
        }
        let trackWidth = max(0, bounds.width - widths.leading - widths.trailing)
        subviews[trackIndex].place(at: CGPoint(x: bounds.minX + widths.leading, y: bounds.minY), anchor: .topLeading,
                                   proposal: ProposedViewSize(width: trackWidth, height: bounds.height))
        if hasTrailing {
            subviews[subviews.count - 1].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing, proposal: .unspecified)
        }
    }
}

/// Accessory circular: the 58 pt ring with the current value label (24 pt medium) in its
/// centre; the open style puts the label, or the bounds labels, at the ring's ends in 11 pt.
package struct _AccessoryCircularGauge {
    package let configuration: GaugeStyleConfiguration
    package let capacity: Bool
    package init(configuration: GaugeStyleConfiguration, capacity: Bool) {
        self.configuration = configuration
        self.capacity = capacity
    }
}

extension _AccessoryCircularGauge: View {
    package var body: some View {
        let bounded = configuration.minimumValueLabel != nil || configuration.maximumValueLabel != nil
        ZStack {
            _GaugeRing(fraction: configuration.value, capacity: capacity, trimmed: !capacity && bounded)
            if let current = configuration.currentValueLabel {
                current.font(.system(size: PlatformMetrics.gaugeRingValueSize, weight: .medium)).offset(y: -PlatformMetrics.gaugeRingValueLift)
            }
            if !capacity {
                if bounded {
                    // The minimum label starts at the arc's first end, the maximum ends at its last.
                    ZStack {
                        if let minimum = configuration.minimumValueLabel {
                            minimum.frame(width: 2 * PlatformMetrics.gaugeRingEndOffset, alignment: .leading)
                        }
                        if let maximum = configuration.maximumValueLabel {
                            maximum.frame(width: 2 * PlatformMetrics.gaugeRingEndOffset, alignment: .trailing)
                        }
                    }
                    .font(.system(size: PlatformMetrics.gaugeRingLabelSize))
                    .offset(y: PlatformMetrics.gaugeRingEndOffset)
                } else {
                    configuration.label
                        .font(.system(size: PlatformMetrics.gaugeRingLabelSize))
                        .offset(y: PlatformMetrics.gaugeRingEndOffset)
                }
            }
        }
    }
}

// MARK: - Primitives

/// A gauge bar: the 16 pt capacity bar, the 8 pt accessory capacity capsule, or the accessory
/// track with its knob (`GaugeBarNode`).
public struct _GaugeBar: View {
    package enum Kind { case capacity, accessoryCapacity, accessoryLinear }
    package let kind: Kind
    package let fraction: Double
    package init(kind: Kind, fraction: Double) {
        self.kind = kind
        self.fraction = fraction
    }
    public typealias Body = Never
    public static func _makeNode(_ context: _NodeContext<_GaugeBar>) -> TypedNode<_GaugeBar> {
        GaugeBarNode(context)
    }
}

/// The accessory ring: open with a marker, or a closed capacity ring (`GaugeRingNode`).
public struct _GaugeRing: View {
    package let fraction: Double
    package let capacity: Bool
    /// The open ring's arc is shortened at both ends to make room for the bounds labels.
    package let trimmed: Bool
    package init(fraction: Double, capacity: Bool, trimmed: Bool) {
        self.fraction = fraction
        self.capacity = capacity
        self.trimmed = trimmed
    }
    public typealias Body = Never
    public static func _makeNode(_ context: _NodeContext<_GaugeRing>) -> TypedNode<_GaugeRing> {
        GaugeRingNode(context)
    }
}
