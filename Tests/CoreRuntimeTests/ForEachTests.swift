// Phase 2, element 1: ForEach reconciles by identity; Section is a transparent three-part list.
import Testing
import SwiftUI

private struct Leaf: View, Equatable {
    var id: Int
    typealias Body = Never
    static func _makeNode(_ context: _NodeContext<Leaf>) -> TypedNode<Leaf> { LeafNode(context) }
}

private struct Item: Identifiable, Equatable {
    var id: String
    var value: Int
}

/// A row whose state is seeded from its item once; reconciliation by id keeps it.
private struct Row: View {
    var item: Item
    @State var seeded: Int
    init(item: Item) {
        self.item = item
        _seeded = State(initialValue: item.value)
    }
    var body: some View { Leaf(id: seeded) }
}

private struct List: View {
    var items: [Item]
    var body: some View {
        ForEach(items) { Row(item: $0) }
    }
}

private struct Ranged: View {
    var count: Int
    var body: some View {
        Leaf(id: -1)
        ForEach(0..<count) { Leaf(id: $0) }
        ForEach(["a", "bb"], id: \.count) { Leaf(id: $0.count) }
    }
}

private struct Sectioned: View {
    var body: some View {
        Section("Title") {
            Leaf(id: 1)
            Leaf(id: 2)
        }
        Section {
            Leaf(id: 3)
        } header: {
            Leaf(id: 0)
        } footer: {
            Leaf(id: 4)
            Leaf(id: 5)
        }
        Section {
            ForEach(0..<2) { Leaf(id: 10 + $0) }
        }
    }
}

private struct Bound: View {
    @State var items = [Item(id: "a", value: 1), Item(id: "b", value: 2)]
    var body: some View {
        ForEach($items) { $item in
            Leaf(id: item.value)
        }
    }
}

@Suite @MainActor struct ForEachTests {
    private func leafIDs(_ node: ViewNode) -> [Int] {
        node.layoutChildren.compactMap { ($0 as? LeafNode<Leaf>)?.view.id }
    }

    private func forEachNode<D, I, C>(_ node: ViewNode, _: D.Type, _: I.Type, _: C.Type) -> ForEachNode<D, I, C>? {
        if let found = node as? ForEachNode<D, I, C> { return found }
        for child in node.structuralChildren {
            if let found = forEachNode(child, D.self, I.self, C.self) { return found }
        }
        return nil
    }

    @Test func rangesAndKeyPathsFlatten() throws {
        let runtime = Runtime()
        let node = runtime.mount(Ranged(count: 3))
        #expect(leafIDs(node) == [-1, 0, 1, 2, 1, 2])
        #expect(node.dump() == """
            CompositeNode<Ranged>
              Tuple(3)
                LeafNode<Leaf>
                ForEach(3)
                  LeafNode<Leaf>
                  LeafNode<Leaf>
                  LeafNode<Leaf>
                ForEach(2)
                  LeafNode<Leaf>
                  LeafNode<Leaf>
            """)
        runtime.mount(Ranged(count: 0))
        #expect(leafIDs(node) == [-1, 1, 2])
    }

    @Test func reconcilesByIdentity() throws {
        let runtime = Runtime()
        let a = Item(id: "a", value: 1), b = Item(id: "b", value: 2), c = Item(id: "c", value: 3)
        let root = runtime.mount(List(items: [a, b, c]))
        let node = try #require(forEachNode(root, [Item].self, String.self, Row.self))
        #expect(leafIDs(root) == [1, 2, 3])
        let (nodeA, nodeB, nodeC) = (node.children[0], node.children[1], node.children[2])

        // Reorder: nodes follow their ids and keep state (the seeded value ignores new items).
        runtime.mount(List(items: [c, Item(id: "a", value: 100), b]))
        #expect(node.children.map { ObjectIdentifier($0) } == [nodeC, nodeA, nodeB].map { ObjectIdentifier($0) })
        #expect(leafIDs(root) == [3, 1, 2])
        #expect(node.created == 3)

        // Insert and remove: new id → fresh subtree, vanished id → unmounted.
        runtime.mount(List(items: [Item(id: "d", value: 4), c, b]))
        #expect(!nodeA.isMounted)
        #expect(nodeB.isMounted && nodeC.isMounted)
        #expect(leafIDs(root) == [4, 3, 2])
        #expect(node.created == 4)

        // A returning id is a new identity: its state starts over.
        runtime.mount(List(items: [Item(id: "a", value: 7)]))
        #expect(leafIDs(root) == [7])
        #expect(!nodeB.isMounted && !nodeC.isMounted)
        #expect(node.created == 5)
    }

    @Test func duplicateIdsGetIndependentNodes() throws {
        let runtime = Runtime()
        let root = runtime.mount(List(items: [Item(id: "x", value: 1), Item(id: "x", value: 2)]))
        let node = try #require(forEachNode(root, [Item].self, String.self, Row.self))
        #expect(leafIDs(root) == [1, 2])
        let first = node.children[0], second = node.children[1]
        runtime.mount(List(items: [Item(id: "x", value: 3), Item(id: "x", value: 4)]))
        #expect(node.children[0] === first && node.children[1] === second)
        #expect(leafIDs(root) == [1, 2])
        runtime.mount(List(items: [Item(id: "x", value: 5)]))
        #expect(node.children.count == 1 && node.children[0] === first)
        #expect(!second.isMounted)
    }

    @Test func stateWritesInsideRowsInvalidateOnlyTheRow() throws {
        let runtime = Runtime()
        let root = try #require(runtime.mount(List(items: [Item(id: "a", value: 1), Item(id: "b", value: 2)])) as? CompositeNode<List>)
        let node = try #require(forEachNode(root, [Item].self, String.self, Row.self))
        let rowB = try #require(node.children[1] as? CompositeNode<Row>)
        rowB.view.seeded = 20
        runtime.flush()
        #expect(leafIDs(root) == [1, 20])
        #expect(root.bodyEvaluations == 1)
        #expect(rowB.bodyEvaluations == 2)
    }

    @Test func bindingCollectionsGiveElementBindings() throws {
        let runtime = Runtime()
        let root = try #require(runtime.mount(Bound()) as? CompositeNode<Bound>)
        #expect(leafIDs(root) == [1, 2])
        // Writing through the element binding updates the array in the view's state.
        // `Binding` is a `RandomAccessCollection` of element bindings, so the plain
        // collection initialiser applies; elements are identified through `Binding.id`.
        let node = try #require(forEachNode(root, Binding<[Item]>.self, String.self, Leaf.self))
        #expect(node.entries.map(\.id) == ["a", "b"])
        root.view.$items[1].value.wrappedValue = 5
        runtime.flush()
        #expect(root.view.items[1].value == 5)
        #expect(leafIDs(root) == [1, 5])
        #expect(node.children.count == 2)
    }

    @Test func sectionsAreTransparentLists() throws {
        let runtime = Runtime()
        let node = runtime.mount(Sectioned())
        #expect(leafIDs(node) == [1, 2, 0, 3, 4, 5, 10, 11])
        let dump = node.dump()
        #expect(dump.contains("Section\n      Text"))   // "Title" header is a Text
        #expect(dump.contains("""
                Section
                  Empty
                  ForEach(2)
                    LeafNode<Leaf>
                    LeafNode<Leaf>
                  Empty
            """))
        #expect(node.layoutChildren.count == 9)   // eight leaves plus the header text
    }
}
