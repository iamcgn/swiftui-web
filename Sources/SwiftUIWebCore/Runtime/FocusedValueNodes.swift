// Focused values runtime (API/FocusedValues.swift): `focusedValue` nodes register their writers;
// the runtime composes the values for the focused node's ancestry (scene values first, then the
// ancestors from the outermost in) and invalidates the views that read them when focus or a
// writer changes.

@MainActor
package final class FocusedValueNode<Content: View>: TypedNode<ModifiedContent<Content, _FocusedValueModifier>> {
    package private(set) var child: TypedNode<Content>!

    init(_ context: _NodeContext<ModifiedContent<Content, _FocusedValueModifier>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
        runtime.focusedValueNodes.append(WeakNode(node: self))
        runtime.focusedValuesDidChange()
    }

    override package func update(view: ModifiedContent<Content, _FocusedValueModifier>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: view.content, environment: environment, force: force)
        runtime.focusedValuesDidChange()
    }

    package var isScene: Bool { view.modifier.scene }
    package func write(into values: inout FocusedValues) { view.modifier.writer.write(&values) }

    override package func unmount() {
        runtime.focusedValueNodes.removeAll { $0.node === self || $0.node == nil }
        super.unmount()
        runtime.focusedValuesDidChange()
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "FocusedValue" }
}

@MainActor package protocol _FocusedValueProviding: AnyObject {
    var isScene: Bool { get }
    func write(into values: inout FocusedValues)
}
extension FocusedValueNode: _FocusedValueProviding {}

extension Runtime {
    /// The values the focused view and its ancestors export, under the scene values.
    public var focusedValues: FocusedValues {
        var values = FocusedValues()
        let providers = focusedValueNodes.compactMap { $0.node as? (ViewNode & _FocusedValueProviding) }
        for provider in providers where provider.isScene { provider.write(into: &values) }
        guard let focusedIdentifier, let focused = interactiveNode(semanticsIdentifier: focusedIdentifier) else { return values }
        var chain: [ViewNode & _FocusedValueProviding] = []
        var node: ViewNode? = focused
        while let current = node {
            if let provider = current as? (ViewNode & _FocusedValueProviding), !provider.isScene { chain.append(provider) }
            node = current.parent
        }
        for provider in chain.reversed() { provider.write(into: &values) }
        return values
    }

    /// A view reading focused values: invalidated when focus or a writer changes.
    package func registerFocusedValueObserver(_ node: ViewNode) {
        if !focusedValueObservers.contains(where: { $0.node === node }) { focusedValueObservers.append(WeakNode(node: node)) }
    }

    package func focusedValuesDidChange() {
        focusedValueObservers.removeAll { $0.node == nil }
        for entry in focusedValueObservers { entry.node?.invalidate() }
    }
}
