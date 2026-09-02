/// Runs an action when an `Equatable` value changes (`View.onChange`).
public struct _ValueActionModifier<Value: Equatable> {
    public var value: Value
    public var initial: Bool
    public var action: (Value, Value) -> Void

    public init(value: Value, initial: Bool, action: @escaping (Value, Value) -> Void) {
        self.value = value
        self.initial = initial
        self.action = action
    }
}

extension _ValueActionModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        ValueActionNode(context)
    }
}

extension View {
    /// Adds a modifier for this view that fires an action when a specific value changes. The
    /// action receives the old and the new value; with `initial`, it also runs when the view
    /// first appears.
    nonisolated public func onChange<V: Equatable>(of value: V, initial: Bool = false,
                                                   _ action: @escaping (_ oldValue: V, _ newValue: V) -> Void) -> some View {
        modifier(_ValueActionModifier(value: value, initial: initial, action: action))
    }

    /// Adds a modifier for this view that fires an action when a specific value changes.
    nonisolated public func onChange<V: Equatable>(of value: V, initial: Bool = false,
                                                   _ action: @escaping () -> Void) -> some View {
        modifier(_ValueActionModifier(value: value, initial: initial, action: { _, _ in action() }))
    }

    /// Adds a modifier for this view that fires an action when a specific value changes.
    @available(*, deprecated, message: "Use `onChange` with a two or zero parameter action closure instead.")
    nonisolated public func onChange<V: Equatable>(of value: V, perform action: @escaping (_ newValue: V) -> Void) -> some View {
        modifier(_ValueActionModifier(value: value, initial: false, action: { _, new in action(new) }))
    }
}

/// Transparent node that compares the modifier's value across updates and queues the action
/// with the scheduler, so it runs after the current update pass rather than in its middle.
@MainActor
package final class ValueActionNode<Content: View, Value: Equatable>: TypedNode<ModifiedContent<Content, _ValueActionModifier<Value>>> {
    package private(set) var child: TypedNode<Content>!

    init(_ context: _NodeContext<ModifiedContent<Content, _ValueActionModifier<Value>>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
        if context.view.modifier.initial {
            let modifier = context.view.modifier
            runtime.scheduler.enqueue { modifier.action(modifier.value, modifier.value) }
        }
    }

    override package func update(view: ModifiedContent<Content, _ValueActionModifier<Value>>, environment: EnvironmentValues, force: Bool) {
        let old = self.view.modifier.value
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: view.content, environment: environment, force: force)
        let new = view.modifier.value
        if old != new {
            let action = view.modifier.action
            runtime.scheduler.enqueue { action(old, new) }
        }
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "OnChange" }
}
