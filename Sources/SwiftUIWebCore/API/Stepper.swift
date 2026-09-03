/// A control that performs increment and decrement actions.
///
/// macOS geometry measured in `Docs/elements/Stepper.md`: a 20 × 26 button pair (up and down
/// chevrons) 8 pt after the body-font label; the control is its natural size (centred by a frame).
public struct Stepper<Label: View>: View {
    package let label: Label
    package let increment: _ActionBox
    package let decrement: _ActionBox
    package let onEditingChanged: _EditingBox

    /// Creates a stepper configured with custom increment and decrement actions.
    public init(@ViewBuilder label: () -> Label, onIncrement: (@MainActor () -> Void)?, onDecrement: (@MainActor () -> Void)?,
                onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.label = label()
        self.increment = _ActionBox(onIncrement ?? {})
        self.decrement = _ActionBox(onDecrement ?? {})
        self.onEditingChanged = _EditingBox(onEditingChanged)
    }

    /// Creates a stepper configured to increment or decrement a binding to a value by a step.
    public init<V: Strideable>(value: Binding<V>, step: V.Stride = 1, @ViewBuilder label: () -> Label,
                               onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(label: label, onIncrement: { value.wrappedValue = value.wrappedValue.advanced(by: step) },
                  onDecrement: { value.wrappedValue = value.wrappedValue.advanced(by: -step) }, onEditingChanged: onEditingChanged)
    }

    /// Creates a stepper configured to increment or decrement a binding to a value by a step,
    /// within bounds.
    public init<V: Strideable>(value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1, @ViewBuilder label: () -> Label,
                               onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(label: label,
                  onIncrement: { value.wrappedValue = min(value.wrappedValue.advanced(by: step), bounds.upperBound) },
                  onDecrement: { value.wrappedValue = max(value.wrappedValue.advanced(by: -step), bounds.lowerBound) },
                  onEditingChanged: onEditingChanged)
    }

    @Environment(\.labelsHidden) private var labelsHidden
    @Environment(\._formStyle) private var formStyle

    public var body: some View {
        _FormLabeledRow(label: labelsHidden ? nil : AnyView(_ControlLabel(label: label)),
                        content: AnyView(_StepperControl(increment: increment, decrement: decrement, onEditingChanged: onEditingChanged)),
                        mode: formStyle == .grouped ? .grouped : .centered)
    }
}

extension Stepper where Label == Text {
    public init(_ titleKey: LocalizedStringKey, onIncrement: (@MainActor () -> Void)?, onDecrement: (@MainActor () -> Void)?,
                onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(label: { Text(titleKey) }, onIncrement: onIncrement, onDecrement: onDecrement, onEditingChanged: onEditingChanged)
    }

    @_disfavoredOverload
    public init<S: StringProtocol>(_ title: S, onIncrement: (@MainActor () -> Void)?, onDecrement: (@MainActor () -> Void)?,
                                   onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(label: { Text(title) }, onIncrement: onIncrement, onDecrement: onDecrement, onEditingChanged: onEditingChanged)
    }

    public init<V: Strideable>(_ titleKey: LocalizedStringKey, value: Binding<V>, step: V.Stride = 1,
                               onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(value: value, step: step, label: { Text(titleKey) }, onEditingChanged: onEditingChanged)
    }

    @_disfavoredOverload
    public init<S: StringProtocol, V: Strideable>(_ title: S, value: Binding<V>, step: V.Stride = 1,
                                                  onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(value: value, step: step, label: { Text(title) }, onEditingChanged: onEditingChanged)
    }

    public init<V: Strideable>(_ titleKey: LocalizedStringKey, value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1,
                               onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(value: value, in: bounds, step: step, label: { Text(titleKey) }, onEditingChanged: onEditingChanged)
    }

    @_disfavoredOverload
    public init<S: StringProtocol, V: Strideable>(_ title: S, value: Binding<V>, in bounds: ClosedRange<V>, step: V.Stride = 1,
                                                  onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
        self.init(value: value, in: bounds, step: step, label: { Text(title) }, onEditingChanged: onEditingChanged)
    }
}

/// The 20 × 26 up/down button pair (`StepperControlNode`).
public struct _StepperControl: View {
    package let increment: _ActionBox
    package let decrement: _ActionBox
    package let onEditingChanged: _EditingBox

    package init(increment: _ActionBox, decrement: _ActionBox, onEditingChanged: _EditingBox) {
        self.increment = increment
        self.decrement = decrement
        self.onEditingChanged = onEditingChanged
    }

    public typealias Body = Never

    public static func _makeNode(_ context: _NodeContext<_StepperControl>) -> TypedNode<_StepperControl> {
        StepperControlNode(context)
    }
}
