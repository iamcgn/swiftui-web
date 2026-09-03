// Navigation stack runtime: the stack keeps its root and one node per pushed entry, all laid out
// centred in its frame, paints the top one, and takes its size from it (Docs/elements/Navigation.md).

@MainActor
package final class NavigationStackNode: LayoutNode<_NavigationStackHost> {
    package private(set) var root: TypedNode<AnyView>!
    package private(set) var context: _NavigationContext!

    /// One pushed view.
    package final class Entry {
        package enum Kind { case value(AnyHashable), view, presented(Binding<Bool>, owner: ObjectIdentifier) }
        package let kind: Kind
        package var view: AnyView?
        package var node: ViewNode?
        init(kind: Kind, view: AnyView?) { self.kind = kind; self.view = view }
    }

    package private(set) var entries: [Entry] = []
    private var lastValues: [AnyHashable] = []
    /// Destination builders registered by `navigationDestination(for:)` in the subtree, by type.
    package var destinations: [ObjectIdentifier: _NavigationDestinationBuilder] = [:]

    package init(_ context: _NodeContext<_NavigationStackHost>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        self.context = _NavigationContext(stack: self)
        root = AnyView._makeNode(_NodeContext(view: context.view.root, parent: self, environment: contentEnvironment))
        lastValues = context.view.values
        reconcile(with: context.view.values)
    }

    private var contentEnvironment: EnvironmentValues {
        var environment = environment
        environment._navigationContext = context
        environment.dismiss = DismissAction { [weak self] in self?.pop() }
        return environment
    }

    override package func update(view: _NavigationStackHost, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        root.update(view: view.root, environment: contentEnvironment, force: force)
        if view.values != lastValues {
            lastValues = view.values
            reconcile(with: view.values)
        }
        for entry in entries { refresh(entry, force: force) }
    }

    /// Makes the value entries match the path (reusing nodes for the unchanged prefix); views
    /// pushed by destination links or `isPresented` bindings stay, after the values.
    private func reconcile(with values: [AnyHashable]) {
        let valueEntries = entries.filter { if case .value = $0.kind { return true } else { return false } }
        let others = entries.filter { if case .value = $0.kind { return false } else { return true } }
        var kept: [Entry] = []
        for (index, value) in values.enumerated() {
            if index < valueEntries.count, case .value(let existing) = valueEntries[index].kind, existing == value {
                kept.append(valueEntries[index])
            } else {
                kept.append(Entry(kind: .value(value), view: nil))
            }
        }
        for entry in valueEntries where !kept.contains(where: { $0 === entry }) { entry.node?.unmount() }
        entries = kept + others
    }

    /// Builds or updates an entry's node from its view (values resolve through the registry).
    private func refresh(_ entry: Entry, force: Bool) {
        if case .value(let value) = entry.kind {
            entry.view = destinations[ObjectIdentifier(type(of: value.base))]?.make(value)
        }
        guard let view = entry.view else {
            entry.node?.unmount()
            entry.node = nil
            return
        }
        if let node = entry.node as? TypedNode<AnyView> {
            node.update(view: view, environment: contentEnvironment, force: force)
        } else {
            entry.node?.unmount()
            entry.node = AnyView._makeNode(_NodeContext(view: view, parent: self, environment: contentEnvironment))
        }
    }

    // MARK: Pushing and popping

    /// Pushes a value: appends it to the path (the binding's owner re-renders the stack).
    package func push(value: AnyHashable) {
        view.path.set(view.values + [value])
        syncWithBinding()
    }

    /// Re-reads the path after this node changed it, so a binding nobody observes still
    /// navigates (an observed one re-renders the stack as well, finding nothing to do).
    private func syncWithBinding() {
        let values = view.path.get()
        view = _NavigationStackHost(root: view.root, path: view.path, values: values)
        if values != lastValues {
            lastValues = values
            reconcile(with: values)
            for entry in entries { refresh(entry, force: false) }
        }
        runtime.requestLayout()
    }

    /// Pushes a destination view (not part of the path binding).
    package func push(view: AnyView) {
        let entry = Entry(kind: .view, view: view)
        entries.append(entry)
        refresh(entry, force: false)
        runtime.requestLayout()
    }

    /// `navigationDestination(isPresented:)` turned on: pushes its view once.
    package func present(_ view: AnyView, isPresented: Binding<Bool>, owner: ObjectIdentifier) {
        guard !entries.contains(where: { if case .presented(_, let o) = $0.kind { return o == owner } else { return false } }) else { return }
        let entry = Entry(kind: .presented(isPresented, owner: owner), view: view)
        entries.append(entry)
        refresh(entry, force: false)
        runtime.requestLayout()
    }

    /// `navigationDestination(isPresented:)` turned off: removes its view.
    package func dismiss(owner: ObjectIdentifier) {
        guard let index = entries.firstIndex(where: { if case .presented(_, let o) = $0.kind { return o == owner } else { return false } }) else { return }
        for entry in entries[index...] { entry.node?.unmount() }
        entries.removeSubrange(index...)
        runtime.requestLayout()
    }

    /// Pops the top entry. Returns false when the stack shows its root.
    @discardableResult
    package func pop() -> Bool {
        guard let top = entries.last else { return false }
        switch top.kind {
        case .value:
            view.path.set(Array(view.values.dropLast()))
            syncWithBinding()
        case .view:
            top.node?.unmount()
            entries.removeLast()
            runtime.requestLayout()
        case .presented(let binding, _):
            top.node?.unmount()
            entries.removeLast()
            binding.wrappedValue = false
            runtime.requestLayout()
        }
        return true
    }

    // MARK: Layout

    /// The layout nodes of the root and of each pushed view, bottom to top.
    private var groups: [[ViewNode]] { [root.layoutChildren] + entries.compactMap { $0.node?.layoutChildren } }

    private func size(of group: [ViewNode], _ proposal: ProposedViewSize) -> CGSize {
        group.reduce(CGSize.zero) { size, node in
            let fit = node.sizeThatFits(proposal)
            return CGSize(width: max(size.width, fit.width), height: max(size.height, fit.height))
        }
    }

    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        size(of: groups.last ?? [], proposal)
    }

    override package func layoutContents(proposal: ProposedViewSize) {
        for group in groups {
            for node in group {
                let size = node.sizeThatFits(proposal)
                node.place(at: CGPoint(x: (frame.width - size.width) / 2, y: (frame.height - size.height) / 2),
                           anchor: .topLeading, proposal: proposal, by: self)
            }
        }
    }

    override package var paintedChildren: [ViewNode] { groups.last ?? [] }
    override package var structuralChildren: [ViewNode] { [root as ViewNode] + entries.compactMap(\.node) }
    override package var nodeDescription: String { "NavigationStack" }

    override package func unmount() {
        for entry in entries { entry.node?.unmount() }
        entries.removeAll()
        super.unmount()
    }
}

/// Registers its destination builder with the enclosing stack; transparent for layout.
@MainActor
package final class NavigationDestinationNode<Content: View, D: Hashable>: UnaryLayoutModifierNode<Content, _NavigationDestinationModifier<D>> {
    private let type: ObjectIdentifier

    package init(_ context: _NodeContext<ModifiedContent<Content, _NavigationDestinationModifier<D>>>, type: ObjectIdentifier) {
        self.type = type
        super.init(context)
        register()
    }

    override package func update(view: ModifiedContent<Content, _NavigationDestinationModifier<D>>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        register()
    }

    private func register() {
        environment._navigationContext?.stack?.destinations[type] = modifier.builder
    }
}

/// Pushes its destination while its binding is true.
@MainActor
package final class NavigationPresentedDestinationNode<Content: View>: UnaryLayoutModifierNode<Content, _NavigationPresentedSync> {
    override package init(_ context: _NodeContext<ModifiedContent<Content, _NavigationPresentedSync>>) {
        super.init(context)
        sync()
    }

    override package func update(view: ModifiedContent<Content, _NavigationPresentedSync>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        sync()
    }

    private func sync() {
        guard let stack = environment._navigationContext?.stack else { return }
        if modifier.presented {
            stack.present(modifier.destination, isPresented: modifier.binding, owner: ObjectIdentifier(self))
        } else {
            stack.dismiss(owner: ObjectIdentifier(self))
        }
    }
}

/// Records the navigation title on the runtime; transparent for layout.
@MainActor
package final class NavigationTitleNode<Content: View>: UnaryLayoutModifierNode<Content, _NavigationTitleModifier> {
    override package init(_ context: _NodeContext<ModifiedContent<Content, _NavigationTitleModifier>>) {
        super.init(context)
        runtime.navigationTitle = modifier.title
    }

    override package func update(view: ModifiedContent<Content, _NavigationTitleModifier>, environment: EnvironmentValues, force: Bool) {
        super.update(view: view, environment: environment, force: force)
        runtime.navigationTitle = modifier.title
    }
}

extension Runtime {
    /// Pops the innermost navigation stack that has something pushed (a host's back button or
    /// key). Returns false when nothing was popped.
    @discardableResult
    public func navigateBack() -> Bool {
        let stacks = root.descendants(where: { $0 is NavigationStackNode }).compactMap { $0 as? NavigationStackNode }
        for stack in stacks.reversed() where stack.pop() { return true }
        return false
    }
}
