// ProgressView (Docs/elements/ProgressView.md): determinate bars and rings, the indeterminate
// spinner and bar, labels and value labels, styles; `controlSize` and `tint`.

/// A view that shows the progress toward completion of a task.
public struct ProgressView<Label: View, CurrentValueLabel: View>: View {
    package let fractionCompleted: Double?
    package let label: Label?
    package let currentValueLabel: CurrentValueLabel?

    @Environment(\.progressViewStyle) private var style

    public var body: some View {
        let configuration = ProgressViewStyleConfiguration(
            fractionCompleted: fractionCompleted,
            label: label.map { ProgressViewStyleConfiguration.Label(view: AnyView($0)) },
            currentValueLabel: currentValueLabel.map { ProgressViewStyleConfiguration.CurrentValueLabel(view: AnyView($0)) })
        style.makeBodyErased(configuration)
    }
}

extension ProgressView where CurrentValueLabel == EmptyView {
    /// An indeterminate progress view with a custom label.
    public init(@ViewBuilder label: () -> Label) {
        fractionCompleted = nil
        self.label = label()
        currentValueLabel = nil
    }

    /// A determinate progress view with a custom label.
    public init<V: BinaryFloatingPoint>(value: V?, total: V = 1.0, @ViewBuilder label: () -> Label) {
        fractionCompleted = value.map { Self.fraction($0, total) }
        self.label = label()
        currentValueLabel = nil
    }
}

extension ProgressView where Label == EmptyView, CurrentValueLabel == EmptyView {
    /// An indeterminate progress view.
    public init() {
        fractionCompleted = nil
        label = nil
        currentValueLabel = nil
    }

    /// A determinate progress view showing `value` out of `total`.
    public init<V: BinaryFloatingPoint>(value: V?, total: V = 1.0) {
        fractionCompleted = value.map { Self.fraction($0, total) }
        label = nil
        currentValueLabel = nil
    }
}

extension ProgressView where Label == Text, CurrentValueLabel == EmptyView {
    /// An indeterminate progress view titled by a localized string key.
    public init(_ titleKey: LocalizedStringKey) {
        fractionCompleted = nil
        label = Text(titleKey)
        currentValueLabel = nil
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S) {
        fractionCompleted = nil
        label = Text(title)
        currentValueLabel = nil
    }

    /// A determinate progress view titled by a localized string key.
    public init<V: BinaryFloatingPoint>(_ titleKey: LocalizedStringKey, value: V?, total: V = 1.0) {
        fractionCompleted = value.map { Self.fraction($0, total) }
        label = Text(titleKey)
        currentValueLabel = nil
    }

    @_disfavoredOverload
    public init<S: StringProtocol, V: BinaryFloatingPoint>(_ title: S, value: V?, total: V = 1.0) {
        fractionCompleted = value.map { Self.fraction($0, total) }
        label = Text(title)
        currentValueLabel = nil
    }
}

extension ProgressView {
    /// A determinate progress view with a label and a label for the current value.
    public init<V: BinaryFloatingPoint>(value: V?, total: V = 1.0, @ViewBuilder label: () -> Label,
                                        @ViewBuilder currentValueLabel: () -> CurrentValueLabel) {
        fractionCompleted = value.map { Self.fraction($0, total) }
        self.label = label()
        self.currentValueLabel = currentValueLabel()
    }

    package static func fraction<V: BinaryFloatingPoint>(_ value: V, _ total: V) -> Double {
        guard total != 0 else { return 0 }
        return min(max(Double(value) / Double(total), 0), 1)
    }
}

extension ProgressView where Label == ProgressViewStyleConfiguration.Label, CurrentValueLabel == ProgressViewStyleConfiguration.CurrentValueLabel {
    /// Creates a progress view based on a style configuration (custom styles).
    public init(_ configuration: ProgressViewStyleConfiguration) {
        fractionCompleted = configuration.fractionCompleted
        label = configuration.label
        currentValueLabel = configuration.currentValueLabel
    }
}

// MARK: - Styles

/// The properties of a progress view instance.
public struct ProgressViewStyleConfiguration {
    public struct Label {
        package let view: AnyView
        package init(view: AnyView) { self.view = view }
    }

    public struct CurrentValueLabel {
        package let view: AnyView
        package init(view: AnyView) { self.view = view }
    }

    /// The completed fraction, or nil for an indeterminate task.
    public let fractionCompleted: Double?
    public var label: Label?
    public var currentValueLabel: CurrentValueLabel?

    package init(fractionCompleted: Double?, label: Label?, currentValueLabel: CurrentValueLabel?) {
        self.fractionCompleted = fractionCompleted
        self.label = label
        self.currentValueLabel = currentValueLabel
    }
}

extension ProgressViewStyleConfiguration.Label: View {
    public var body: some View { view }
}

extension ProgressViewStyleConfiguration.CurrentValueLabel: View {
    public var body: some View { view }
}

/// A type that applies standard interaction behavior to all progress views within a view hierarchy.
public protocol ProgressViewStyle {
    associatedtype Body: View
    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body
    typealias Configuration = ProgressViewStyleConfiguration
}

extension ProgressViewStyle {
    @MainActor
    package func makeBodyErased(_ configuration: Configuration) -> AnyView {
        AnyView(makeBody(configuration: configuration))
    }
}

/// The default progress view style in the current context: linear for determinate tasks, a
/// spinner otherwise.
public struct DefaultProgressViewStyle {
    public init() {}
}

extension DefaultProgressViewStyle: ProgressViewStyle {
    public func makeBody(configuration: Configuration) -> some View {
        if configuration.fractionCompleted != nil {
            _LinearProgress(configuration: configuration)
        } else {
            _CircularProgress(configuration: configuration)
        }
    }
}

/// A progress view that visually indicates its progress using a horizontal bar.
public struct LinearProgressViewStyle {
    public init() {}
}

extension LinearProgressViewStyle: ProgressViewStyle {
    public func makeBody(configuration: Configuration) -> some View {
        _LinearProgress(configuration: configuration)
    }
}

/// A progress view that visually indicates its progress using a circular gauge.
public struct CircularProgressViewStyle {
    public init() {}
}

extension CircularProgressViewStyle: ProgressViewStyle {
    public func makeBody(configuration: Configuration) -> some View {
        _CircularProgress(configuration: configuration)
    }
}

extension ProgressViewStyle where Self == DefaultProgressViewStyle {
    public static var automatic: DefaultProgressViewStyle { DefaultProgressViewStyle() }
}

extension ProgressViewStyle where Self == LinearProgressViewStyle {
    public static var linear: LinearProgressViewStyle { LinearProgressViewStyle() }
}

extension ProgressViewStyle where Self == CircularProgressViewStyle {
    public static var circular: CircularProgressViewStyle { CircularProgressViewStyle() }
}

package struct ProgressViewStyleKey: EnvironmentKey {
    package nonisolated(unsafe) static let defaultValue: any ProgressViewStyle = DefaultProgressViewStyle()
}

extension EnvironmentValues {
    package var progressViewStyle: any ProgressViewStyle {
        get { self[ProgressViewStyleKey.self] }
        set { self[ProgressViewStyleKey.self] = newValue }
    }
}

extension View {
    /// Sets the style for progress views in this view.
    nonisolated public func progressViewStyle<S: ProgressViewStyle>(_ style: S) -> some View {
        environment(\.progressViewStyle, style)
    }
}

// MARK: - Bodies

/// Linear: the label above the bar row, the current value label under it (macOS: a 20 pt row
/// holding an 8 pt pill).
package struct _LinearProgress {
    package let configuration: ProgressViewStyleConfiguration
    package init(configuration: ProgressViewStyleConfiguration) { self.configuration = configuration }
}

extension _LinearProgress: View {
    package var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let label = configuration.label { label }
            _ProgressBar(fraction: configuration.fractionCompleted)
            if let value = configuration.currentValueLabel { value.foregroundColor(.secondary) }
        }
    }
}

/// Circular: the ring (or spinner) with the labels under it in the secondary colour.
package struct _CircularProgress {
    package let configuration: ProgressViewStyleConfiguration
    @Environment(\.controlSize) private var controlSize
    package init(configuration: ProgressViewStyleConfiguration) { self.configuration = configuration }
}

extension _CircularProgress: View {
    package var body: some View {
        VStack {
            _ProgressRing(fraction: configuration.fractionCompleted, diameter: PlatformMetrics.progressRingDiameter(controlSize))
            if let label = configuration.label { label.foregroundColor(.secondary) }
            if let value = configuration.currentValueLabel { value.foregroundColor(.secondary) }
        }
    }
}

/// The bar: as wide as proposed, 20 pt tall.
public struct _ProgressBar: View {
    package let fraction: Double?
    package init(fraction: Double?) { self.fraction = fraction }
    public typealias Body = Never
    public static func _makeNode(_ context: _NodeContext<_ProgressBar>) -> TypedNode<_ProgressBar> {
        ProgressBarNode(context)
    }
}

/// The ring or spinner, a square of the control size's diameter.
public struct _ProgressRing: View {
    package let fraction: Double?
    package let diameter: CGFloat
    package init(fraction: Double?, diameter: CGFloat) {
        self.fraction = fraction
        self.diameter = diameter
    }
    public typealias Body = Never
    public static func _makeNode(_ context: _NodeContext<_ProgressRing>) -> TypedNode<_ProgressRing> {
        ProgressRingNode(context)
    }
}

// MARK: - Control size and tint

/// The size classes of controls.
public enum ControlSize: Hashable, CaseIterable, Sendable {
    case mini, small, regular, large, extraLarge
}

package struct ControlSizeKey: EnvironmentKey {
    package static let defaultValue = ControlSize.regular
}

package struct TintKey: EnvironmentKey {
    package static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    /// The size class of controls in this environment (progress spinners follow it).
    public var controlSize: ControlSize {
        get { self[ControlSizeKey.self] }
        set { self[ControlSizeKey.self] = newValue }
    }

    /// The tint set by `tint(_:)` (recorded; the measured control looks are the inactive
    /// window's greys, which a tint does not change).
    package var _tint: Color? {
        get { self[TintKey.self] }
        set { self[TintKey.self] = newValue }
    }
}

extension View {
    /// Sets the size class of controls in this view.
    nonisolated public func controlSize(_ size: ControlSize) -> some View {
        environment(\.controlSize, size)
    }

    /// Sets the tint of controls in this view.
    nonisolated public func tint(_ tint: Color?) -> some View {
        environment(\._tint, tint)
    }
}
