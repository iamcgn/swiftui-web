extension IDView where Content: View {
    @MainActor
    public static func _makeNode(_ context: _NodeContext<IDView<Content, ID>>) -> TypedNode<IDView<Content, ID>> {
        IDNode(context)
    }
}

/// Rebuilds its content when the identifier changes. Transparent to layout.
@MainActor
package final class IDNode<Content: View, ID: Hashable>: TypedNode<IDView<Content, ID>> {
    package private(set) var child: TypedNode<Content>!

    init(_ context: _NodeContext<IDView<Content, ID>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime,
                   environment: context.environment)
        child = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
    }

    override package func update(view: IDView<Content, ID>, environment: EnvironmentValues, force: Bool) {
        let idChanged = self.view.id != view.id
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        if idChanged {
            child.unmount()
            child = Content._makeNode(_NodeContext(view: view.content, parent: self, environment: environment))
        } else {
            child.update(view: view.content, environment: environment, force: force)
        }
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "ID(\(view.id))" }
}
