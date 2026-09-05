/// A control for selecting a value from a bounded linear range of values.
///
/// macOS geometry measured in `Docs/elements/Slider.md`: a 16 pt tall flexible track (5 pt line,
/// 22 × 16 knob whose centre travels 11 pt in from each end, 2 pt ticks along the bottom when
/// stepped), the label in the body font and the value labels in the footnote font, 8 pt apart.
public struct Slider<Label: View, ValueLabel: View>: View {
    package let value: _SliderValue
    package let range: ClosedRange<Double>
    package let step: Double?
    package let label: Label
    package let minimumValueLabel: ValueLabel
    package let maximumValueLabel: ValueLabel
    package let onEditingChanged: _EditingBox

    package init(value: _SliderValue, range: ClosedRange<Double>, step: Double?, label: Label,
                 minimumValueLabel: ValueLabel, maximumValueLabel: ValueLabel, onEditingChanged: @escaping (Bool) -> Void) {
        self.value = value
        self.range = range
        self.step = step
        self.label = label
        self.minimumValueLabel = minimumValueLabel
        self.maximumValueLabel = maximumValueLabel
        self.onEditingChanged = _EditingBox(onEditingChanged)
    }

    @Environment(\.labelsHidden) private var labelsHidden
    @Environment(\._formStyle) private var formStyle
    @Environment(\.platformProfile) private var profile

    public var body: some View {
        let current = value.get()   // read here so observation tracks it
        let track = HStack(alignment: .center, spacing: PlatformMetrics.controlLabelSpacing) {
            minimumValueLabel.font(.footnote).foregroundStyle(Color.secondary)._pixelAligned()
            _SliderTrack(value: value, current: current, range: range, step: step, onEditingChanged: onEditingChanged)._pixelAligned()
            maximumValueLabel.font(.footnote).foregroundStyle(Color.secondary)._pixelAligned()
        }
        switch formStyle {
        case nil:
            // iOS shows no label outside a form (ios/slider/basic `labelled` is the bare track).
            HStack(alignment: .center, spacing: PlatformMetrics.controlLabelSpacing) {
                if !labelsHidden && !profile.isIOS { _ControlLabel(label: label)._pixelAligned() }
                track
            }
        case .columns:
            // The form draws the label in the default font on a 23 pt row (Docs/elements/Form.md).
            _FormLabeledRow(label: labelsHidden ? nil : AnyView(_ControlLabel(label: label).font(.system(size: PlatformMetrics.buttonLabelSize))),
                            content: AnyView(track), mode: .sliderColumns)
        case .grouped:
            _FormLabeledRow(label: labelsHidden ? nil : AnyView(_ControlLabel(label: label)), content: AnyView(track), mode: .grouped)
        }
    }
}

/// Holds an `onEditingChanged` callback (a class so the runtime's field reflection ignores it).
package final class _EditingBox {
    package let run: (Bool) -> Void
    package init(_ run: @escaping (Bool) -> Void) { self.run = run }
}

/// Type-erased access to a slider's value as a `Double`.
@MainActor
package final class _SliderValue {
    package let get: () -> Double
    package let set: (Double) -> Void

    package init<V: BinaryFloatingPoint>(_ binding: Binding<V>) {
        get = { Double(binding.wrappedValue) }
        set = { binding.wrappedValue = V($0) }
    }
}

extension Slider where Label == EmptyView, ValueLabel == EmptyView {
    /// Creates a slider to select a value from a given range.
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1,
                                        onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint {
        self.init(value: _SliderValue(value), range: Double(bounds.lowerBound)...Double(bounds.upperBound), step: nil,
                  label: EmptyView(), minimumValueLabel: EmptyView(), maximumValueLabel: EmptyView(), onEditingChanged: onEditingChanged)
    }

    /// Creates a slider to select a value from a given range, subject to a step increment.
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1,
                                        onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint {
        self.init(value: _SliderValue(value), range: Double(bounds.lowerBound)...Double(bounds.upperBound), step: Double(step),
                  label: EmptyView(), minimumValueLabel: EmptyView(), maximumValueLabel: EmptyView(), onEditingChanged: onEditingChanged)
    }
}

extension Slider where ValueLabel == EmptyView {
    /// Creates a slider to select a value from a given range, which displays the provided label.
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1, @ViewBuilder label: () -> Label,
                                        onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint {
        self.init(value: _SliderValue(value), range: Double(bounds.lowerBound)...Double(bounds.upperBound), step: nil,
                  label: label(), minimumValueLabel: EmptyView(), maximumValueLabel: EmptyView(), onEditingChanged: onEditingChanged)
    }

    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1, @ViewBuilder label: () -> Label,
                                        onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint {
        self.init(value: _SliderValue(value), range: Double(bounds.lowerBound)...Double(bounds.upperBound), step: Double(step),
                  label: label(), minimumValueLabel: EmptyView(), maximumValueLabel: EmptyView(), onEditingChanged: onEditingChanged)
    }
}

extension Slider {
    /// Creates a slider with a label and labels for its minimum and maximum values.
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1, @ViewBuilder label: () -> Label,
                                        @ViewBuilder minimumValueLabel: () -> ValueLabel, @ViewBuilder maximumValueLabel: () -> ValueLabel,
                                        onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint {
        self.init(value: _SliderValue(value), range: Double(bounds.lowerBound)...Double(bounds.upperBound), step: nil,
                  label: label(), minimumValueLabel: minimumValueLabel(), maximumValueLabel: maximumValueLabel(), onEditingChanged: onEditingChanged)
    }

    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1, @ViewBuilder label: () -> Label,
                                        @ViewBuilder minimumValueLabel: () -> ValueLabel, @ViewBuilder maximumValueLabel: () -> ValueLabel,
                                        onEditingChanged: @escaping (Bool) -> Void = { _ in }) where V.Stride: BinaryFloatingPoint {
        self.init(value: _SliderValue(value), range: Double(bounds.lowerBound)...Double(bounds.upperBound), step: Double(step),
                  label: label(), minimumValueLabel: minimumValueLabel(), maximumValueLabel: maximumValueLabel(), onEditingChanged: onEditingChanged)
    }
}

/// The painted, draggable track (`SliderTrackNode`).
public struct _SliderTrack: View {
    package let value: _SliderValue
    package let current: Double
    package let range: ClosedRange<Double>
    package let step: Double?
    package let onEditingChanged: _EditingBox

    package init(value: _SliderValue, current: Double, range: ClosedRange<Double>, step: Double?, onEditingChanged: _EditingBox) {
        self.value = value
        self.current = current
        self.range = range
        self.step = step
        self.onEditingChanged = onEditingChanged
    }

    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_SliderTrack>) -> TypedNode<_SliderTrack> {
        SliderTrackNode(context)
    }
}
