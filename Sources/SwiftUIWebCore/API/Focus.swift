/// Keyboard focus as view state (`Docs/elements/Focus.md`): `@FocusState` holds which view is
/// focused, `focused(_:)`/`focused(_:equals:)` tie a text field to it in both directions.
@propertyWrapper
public struct FocusState<Value: Hashable>: DynamicProperty {
    package var box: _FocusStateBox<Value>?
    package let initial: Value

    /// Creates a focus state that binds to a Boolean.
    public init() where Value == Bool {
        initial = false
    }

    /// Creates a focus state that binds to an optional value.
    public init<T: Hashable>() where Value == T? {
        initial = nil
    }

    /// The current state value, taking into account whatever bindings might be associated
    /// with the property. Setting it moves focus.
    public var wrappedValue: Value {
        get { box?.value ?? initial }
        nonmutating set { box?.set(newValue) }
    }

    /// A projection of the focus state value that returns a binding.
    public var projectedValue: Binding { Binding(box: box, initial: initial) }

    /// A property wrapper type that can read and write a value that indicates the current focus.
    @propertyWrapper
    public struct Binding {
        package let box: _FocusStateBox<Value>?
        package let initial: Value

        public var wrappedValue: Value {
            get { box?.value ?? initial }
            nonmutating set { box?.set(newValue) }
        }

        public var projectedValue: Binding { self }
    }

    @MainActor
    public mutating func _install(in node: ViewNode, slot: inout AnyObject?) {
        if let existing = slot as? _FocusStateBox<Value> {
            box = existing
        } else {
            let created = _FocusStateBox(value: initial, node: node)
            slot = created
            box = created
        }
    }
}

/// Storage for one `@FocusState`: the value, the owning node (invalidated when the value
/// changes) and the focus targets that follow it.
@MainActor
package final class _FocusStateBox<Value: Hashable> {
    package nonisolated(unsafe) private(set) var value: Value
    private weak var node: ViewNode?
    /// The nodes with `focused` modifiers bound to this state, by their focus value.
    package var targets: [(value: Value, node: WeakNode)] = []

    package init(value: Value, node: ViewNode) {
        self.value = value
        self.node = node
    }

    /// A programmatic focus change: records the value, re-renders, and moves the runtime's focus.
    package nonisolated func set(_ newValue: Value) {
        nonisolated(unsafe) let value = newValue
        MainActor.assumeIsolated { applyProgrammatic(value) }
    }

    private func applyProgrammatic(_ newValue: Value) {
        guard newValue != value else { return }
        value = newValue
        node?.invalidate()
        guard let runtime = node?.runtime else { return }
        if let target = targets.first(where: { $0.value == newValue })?.node.node as? any _FocusTargetProviding {
            runtime.focus(semanticsIdentifier: target.focusTargetIdentifier)
        } else if isUnfocusedValue(newValue) {
            runtime.focus(semanticsIdentifier: nil)
        }
    }

    /// The runtime's focus changed: mirror it into the value without moving focus again.
    package func focusDidChange(to identifier: Int?) {
        let newValue: Value
        if let identifier, let target = targets.first(where: { ($0.node.node as? any _FocusTargetProviding)?.focusTargetIdentifier == identifier }) {
            newValue = target.value
        } else if let identifier, targets.contains(where: { _ in true }), Value.self == Bool.self {
            _ = identifier
            newValue = false as! Value
        } else if let identifier {
            _ = identifier
            newValue = unfocusedValue()
        } else {
            newValue = unfocusedValue()
        }
        guard newValue != value else { return }
        value = newValue
        node?.invalidate()
    }

    private func unfocusedValue() -> Value {
        if Value.self == Bool.self { return false as! Value }
        return (Optional<Any>.none as Any) as? Value ?? value
    }

    private func isUnfocusedValue(_ value: Value) -> Bool {
        if let bool = value as? Bool { return !bool }
        if case Optional<Any>.none = (value as Any) { return true }
        return false
    }
}

/// A node whose subtree's text field can take focus for a `focused` modifier.
@MainActor
package protocol _FocusTargetProviding: AnyObject {
    var focusTargetIdentifier: Int? { get }
}

/// `focused(_:)`/`focused(_:equals:)`: registers the modified view with the focus state.
public struct _FocusedModifier<Value: Hashable> {
    package let box: _FocusStateBox<Value>?
    package let value: Value

    package init(box: _FocusStateBox<Value>?, value: Value) {
        self.box = box
        self.value = value
    }
}

extension _FocusedModifier: ViewModifier {
    public typealias Body = Never
    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        FocusedNode(context)
    }
}

extension View {
    /// Modifies this view by binding its focus state to the given Boolean state value.
    nonisolated public func focused(_ condition: FocusState<Bool>.Binding) -> some View {
        modifier(_FocusedModifier(box: condition.box, value: true))
    }

    /// Modifies this view by binding its focus state to the given state value.
    nonisolated public func focused<Value: Hashable>(_ binding: FocusState<Value?>.Binding, equals value: Value) -> some View {
        modifier(_FocusedModifier(box: binding.box, value: value))
    }
}
