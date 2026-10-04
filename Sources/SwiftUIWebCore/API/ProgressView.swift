#if os(WASI)
import WebFoundation   // never full Foundation on wasm: it links ICU (decisions 0006, 0017)
#else
import Foundation
#endif
import Observation     // `_WebProgress` is observable

// ProgressView (Docs/elements/ProgressView.md): determinate bars and rings, the indeterminate
// spinner and bar, labels and value labels, styles; `controlSize` and `tint`.

/// A view that shows the progress toward completion of a task.
public struct ProgressView<Label: View, CurrentValueLabel: View>: View {
    package let fractionCompleted: Double?
    package let label: Label?
    package let currentValueLabel: CurrentValueLabel?
    /// `ProgressView(timerInterval:)`: the bar follows the clock through the animation timeline.
    package var timer: (interval: ClosedRange<Date>, countsDown: Bool)?
    /// `ProgressView(_ progress: Progress)` on Apple platforms: the fraction re-read every frame.
    package var polled: _PolledFraction?

    @Environment(\.progressViewStyle) private var style

    public var body: some View {
        if let timer {
            TimelineView(.animation) { context in
                styled(Self.timerFraction(timer.interval, countsDown: timer.countsDown, at: context.date))
            }
        } else if let polled {
            TimelineView(.animation(minimumInterval: 0.1)) { _ in styled(polled.read()) }
        } else {
            styled(fractionCompleted)
        }
    }

    private func styled(_ fraction: Double?) -> AnyView {
        let configuration = ProgressViewStyleConfiguration(
            fractionCompleted: fraction,
            label: label.map { ProgressViewStyleConfiguration.Label(view: AnyView($0)) },
            currentValueLabel: currentValueLabel.map { ProgressViewStyleConfiguration.CurrentValueLabel(view: AnyView($0)) })
        return style.makeBodyErased(configuration)
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

extension ProgressView where Label == EmptyView, CurrentValueLabel == _TimerIntervalLabel {
    /// A progress view that fills (or, counting down, empties) over `timerInterval`, its current
    /// value label the time left as m:ss, refreshed every frame.
    public init(timerInterval: ClosedRange<Date>, countsDown: Bool = true) {
        fractionCompleted = Self.timerFraction(timerInterval, countsDown: countsDown, at: Date())
        label = nil
        currentValueLabel = _TimerIntervalLabel(interval: timerInterval, countsDown: countsDown)
        timer = (timerInterval, countsDown)
    }
}

extension ProgressView where CurrentValueLabel == _TimerIntervalLabel {
    public init(timerInterval: ClosedRange<Date>, countsDown: Bool = true, @ViewBuilder label: () -> Label) {
        fractionCompleted = Self.timerFraction(timerInterval, countsDown: countsDown, at: Date())
        self.label = label()
        currentValueLabel = _TimerIntervalLabel(interval: timerInterval, countsDown: countsDown)
        timer = (timerInterval, countsDown)
    }
}

extension ProgressView {
    public init(timerInterval: ClosedRange<Date>, countsDown: Bool = true, @ViewBuilder label: () -> Label,
                @ViewBuilder currentValueLabel: () -> CurrentValueLabel) {
        fractionCompleted = Self.timerFraction(timerInterval, countsDown: countsDown, at: Date())
        self.label = label()
        self.currentValueLabel = currentValueLabel()
        timer = (timerInterval, countsDown)
    }

    package static func timerFraction(_ interval: ClosedRange<Date>, countsDown: Bool, at date: Date) -> Double {
        let total = interval.upperBound.timeIntervalSince(interval.lowerBound)
        guard total > 0 else { return countsDown ? 0 : 1 }
        let elapsed = min(max(date.timeIntervalSince(interval.lowerBound), 0), total)
        return countsDown ? 1 - elapsed / total : elapsed / total
    }
}

extension ProgressView where Label == Text, CurrentValueLabel == EmptyView {
    /// A progress view following a `_WebProgress` (wasm's `Progress`): its fraction, or
    /// indeterminate while the object is; the label its description.
    public init(_ progress: _WebProgress) {
        fractionCompleted = progress.isIndeterminate ? nil : progress.fractionCompleted
        label = progress.localizedDescription.isEmpty ? nil : Text(progress.localizedDescription)
        currentValueLabel = nil
    }
}

extension ProgressView where Label == Text, CurrentValueLabel == EmptyView {
    /// A progress view re-reading `fraction` every frame (Apple platforms' Foundation `Progress`).
    public init(_polling fraction: @escaping @MainActor () -> Double?, description: String?) {
        fractionCompleted = fraction()
        label = description.flatMap { $0.isEmpty ? nil : Text($0) }
        currentValueLabel = nil
        polled = _PolledFraction(fraction)
    }
}

/// A fraction re-read every frame (a class so the runtime's field reflection ignores it).
public final class _PolledFraction {
    package let read: @MainActor () -> Double?
    package init(_ read: @escaping @MainActor () -> Double?) { self.read = read }
}

/// The current value label of a timer-interval progress view: the time left (or elapsed) as
/// m:ss, re-read every frame through the animation timeline.
public struct _TimerIntervalLabel: View {
    package let interval: ClosedRange<Date>
    package let countsDown: Bool

    package static func text(for interval: ClosedRange<Date>, countsDown: Bool, at date: Date) -> String {
        let total = interval.upperBound.timeIntervalSince(interval.lowerBound)
        let elapsed = min(max(date.timeIntervalSince(interval.lowerBound), 0), max(total, 0))
        let shown = Int((countsDown ? total - elapsed : elapsed).rounded(.up))
        return "\(shown / 60):" + (shown % 60 < 10 ? "0" : "") + "\(shown % 60)"
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 0.25)) { context in
            Text(Self.text(for: interval, countsDown: countsDown, at: context.date))
        }
    }
}

/// The progress object of wasm's `Progress` (the thin module names it so; Apple platforms keep
/// Foundation's): unit counts, a fraction, a description, observable.
@Observable
public final class _WebProgress {
    public var totalUnitCount: Int64
    public var completedUnitCount: Int64 = 0
    public var localizedDescription = ""
    public var isCancelled = false

    public init(totalUnitCount: Int64) { self.totalUnitCount = totalUnitCount }

    /// Zero to one; indeterminate while the total is zero or less.
    public var fractionCompleted: Double {
        guard totalUnitCount > 0 else { return 0 }
        return min(max(Double(completedUnitCount) / Double(totalUnitCount), 0), 1)
    }
    public var isIndeterminate: Bool { totalUnitCount <= 0 }
    public var isFinished: Bool { totalUnitCount > 0 && completedUnitCount >= totalUnitCount }
    public func cancel() { isCancelled = true }
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
        VStack(alignment: .leading, spacing: PlatformMetrics.progressLabelSpacing) {
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
            _ProgressRing(fraction: PlatformMetrics.progressCircularIsSpinner ? nil : configuration.fractionCompleted,
                          diameter: PlatformMetrics.progressRingDiameter(controlSize))
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
