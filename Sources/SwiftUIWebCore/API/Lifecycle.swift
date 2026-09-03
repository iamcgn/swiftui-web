/// Appearance actions and tasks tied to a view's time in the tree (`Docs/elements/Lifecycle.md`).
///
/// `onAppear` runs after the update pass that inserts the view, `onDisappear` after the one that
/// removes it; `task` starts a `Task` when the view appears and cancels it when the view
/// disappears or its `id` changes.
public struct _AppearanceActionModifier {
    package let appear: _ActionBox?
    package let disappear: _ActionBox?

    package init(appear: (@MainActor () -> Void)?, disappear: (@MainActor () -> Void)?) {
        self.appear = appear.map { _ActionBox($0) }
        self.disappear = disappear.map { _ActionBox($0) }
    }
}

extension _AppearanceActionModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        AppearanceActionNode(context)
    }
}

/// Holds a task's async body (a class so the runtime's field reflection ignores it).
package final class _AsyncActionBox: Sendable {
    package let run: @MainActor @Sendable () async -> Void
    package init(_ run: @escaping @MainActor @Sendable () async -> Void) { self.run = run }
}

public struct _TaskModifier {
    package let id: AnyHashable?
    package let priority: TaskPriority
    package let action: _AsyncActionBox

    package init(id: AnyHashable?, priority: TaskPriority, action: @escaping @MainActor @Sendable () async -> Void) {
        self.id = id
        self.priority = priority
        self.action = _AsyncActionBox(action)
    }
}

extension _TaskModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        TaskNode(context)
    }
}

extension View {
    /// Adds an action to perform before this view appears.
    nonisolated public func onAppear(perform action: (@MainActor () -> Void)? = nil) -> some View {
        modifier(_AppearanceActionModifier(appear: action, disappear: nil))
    }

    /// Adds an action to perform after this view disappears.
    nonisolated public func onDisappear(perform action: (@MainActor () -> Void)? = nil) -> some View {
        modifier(_AppearanceActionModifier(appear: nil, disappear: action))
    }

    /// Adds an asynchronous task to perform before this view appears.
    nonisolated public func task(priority: TaskPriority = .userInitiated, _ action: @escaping @MainActor @Sendable () async -> Void) -> some View {
        modifier(_TaskModifier(id: nil, priority: priority, action: action))
    }

    /// Adds a task to perform before this view appears or when a specified value changes.
    nonisolated public func task<T: Equatable>(id value: T, priority: TaskPriority = .userInitiated,
                                               _ action: @escaping @MainActor @Sendable () async -> Void) -> some View {
        modifier(_TaskModifier(id: AnyHashable(_EquatableBox(value)), priority: priority, action: action))
    }
}

/// Wraps an `Equatable` value so it can be compared through `AnyHashable`.
package struct _EquatableBox<T: Equatable>: Hashable {
    package let value: T
    package init(_ value: T) { self.value = value }
    package func hash(into hasher: inout Hasher) {}
    package static func == (lhs: Self, rhs: Self) -> Bool { lhs.value == rhs.value }
}
