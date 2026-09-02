// Nodes for the data-driven list views. `ForEach` is the one place the runtime reconciles by
// key (Docs/ARCHITECTURE.md, invariant 1); `Section` is a transparent three-part list.

// MARK: ForEach

/// Keeps one child per element identity. On update, elements whose id already has a node reuse
/// it (state survives moves); new ids get fresh subtrees; vanished ids are unmounted. Children
/// are ordered like the data. Duplicate ids get independent nodes, as SwiftUI does (it warns).
@MainActor
package final class ForEachNode<Data: RandomAccessCollection, ID: Hashable, Content: View>:
    TypedNode<ForEach<Data, ID, Content>>
{
    package struct Entry {
        package let id: ID
        package let node: TypedNode<Content>
    }

    package private(set) var entries: [Entry] = []

    /// Number of subtrees created over the node's life, for tests.
    package private(set) var created = 0

    init(_ context: _NodeContext<ForEach<Data, ID, Content>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime,
                   environment: context.environment)
        reconcile(previous: [], environment: context.environment, force: false)
    }

    override package func update(view: ForEach<Data, ID, Content>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        reconcile(previous: entries, environment: environment, force: force)
    }

    private func reconcile(previous: [Entry], environment: EnvironmentValues, force: Bool) {
        // Group survivors by id; a queue per id keeps duplicates stable in order.
        var available: [ID: [TypedNode<Content>]] = [:]
        for entry in previous.reversed() {
            available[entry.id, default: []].append(entry.node)
        }
        var next: [Entry] = []
        next.reserveCapacity(view.data.count)
        for element in view.data {
            let id = view.id(of: element)
            let content = view.content(element)
            if let node = available[id]?.popLast() {
                node.update(view: content, environment: environment, force: force)
                next.append(Entry(id: id, node: node))
            } else {
                created += 1
                let node = Content._makeNode(_NodeContext(view: content, parent: self, environment: environment))
                next.append(Entry(id: id, node: node))
            }
        }
        for nodes in available.values {
            for node in nodes { node.unmount() }
        }
        entries = next
    }

    package var children: [TypedNode<Content>] { entries.map(\.node) }

    override package var structuralChildren: [ViewNode] { entries.map(\.node) }
    override package var layoutChildren: [ViewNode] { entries.flatMap { $0.node.layoutChildren } }
    override package var nodeDescription: String { "ForEach(\(entries.count))" }
}

// MARK: Section

/// Header, content and footer in order, each transparent to layout.
@MainActor
package final class SectionNode<Parent: View, Content: View, Footer: View>:
    TypedNode<Section<Parent, Content, Footer>>
{
    package private(set) var header: TypedNode<Parent>!
    package private(set) var content: TypedNode<Content>!
    package private(set) var footer: TypedNode<Footer>!

    init(_ context: _NodeContext<Section<Parent, Content, Footer>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime,
                   environment: context.environment)
        header = Parent._makeNode(_NodeContext(view: context.view.header, parent: self, environment: context.environment))
        content = Content._makeNode(_NodeContext(view: context.view.content, parent: self, environment: context.environment))
        footer = Footer._makeNode(_NodeContext(view: context.view.footer, parent: self, environment: context.environment))
    }

    override package func update(view: Section<Parent, Content, Footer>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        header.update(view: view.header, environment: environment, force: force)
        content.update(view: view.content, environment: environment, force: force)
        footer.update(view: view.footer, environment: environment, force: force)
    }

    override package var structuralChildren: [ViewNode] { [header, content, footer] }
    override package var layoutChildren: [ViewNode] {
        header.layoutChildren + content.layoutChildren + footer.layoutChildren
    }
    override package var nodeDescription: String { "Section" }
}
