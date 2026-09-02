// Phase 1 step 2: the node tree mirrors the view type tree; lists flatten into the enclosing
// layout; the scheduler updates dirty nodes top-down once per flush.
import Testing
import SwiftUI

/// A primitive test view that occupies one layout slot.
private struct Leaf: View, Equatable {
    var id: Int
    typealias Body = Never
    static func _makeNode(_ context: _NodeContext<Leaf>) -> TypedNode<Leaf> {
        LeafNode(context)
    }
}

private struct Pair: View, Equatable {
    var base: Int
    var body: some View {
        Leaf(id: base)
        Leaf(id: base + 1)
    }
}

private struct Shape: Equatable {
    var flag = true
    var optional: Int? = 1
    var erased = 0
}

private struct Composite: View, Equatable {
    var shape = Shape()
    var body: some View {
        Leaf(id: 0)
        if shape.flag { Pair(base: 1) } else { Leaf(id: -1) }
        if let n = shape.optional { Leaf(id: n) }
        Group {
            Leaf(id: 5)
            Leaf(id: 6)
        }
        if shape.erased == 0 { AnyView(Leaf(id: 7)) } else { AnyView(Pair(base: 7)) }
    }
}

private struct Padded: ViewModifier {
    var amount: Int
    func body(content: Content) -> some View {
        Leaf(id: amount)
        content
    }
}

private struct DepthKey: EnvironmentKey { static let defaultValue = 0 }
extension EnvironmentValues {
    fileprivate var depth: Int {
        get { self[DepthKey.self] }
        set { self[DepthKey.self] = newValue }
    }
}

private struct Nested: View {
    var body: some View {
        Leaf(id: 1).environment(\.depth, 2)
    }
}

@Suite @MainActor struct NodeTreeTests {
    @Test func treeMirrorsTypeTreeAndFlattens() {
        let runtime = Runtime()
        let node = runtime.mount(Composite())
        #expect(node.dump() == """
            CompositeNode<Composite>
              Tuple(5)
                LeafNode<Leaf>
                Conditional(first)
                  CompositeNode<Pair>
                    Tuple(2)
                      LeafNode<Leaf>
                      LeafNode<Leaf>
                Optional(some)
                  LeafNode<Leaf>
                Group
                  Tuple(2)
                    LeafNode<Leaf>
                    LeafNode<Leaf>
                Conditional(first)
                  AnyView(Leaf)
                    LeafNode<Leaf>
            """)
        // Leaf 0, Pair (2), optional (1), group (2), AnyView leaf (1) = 7 layout slots.
        let leaves = node.layoutChildren.compactMap { $0 as? LeafNode<Leaf> }
        #expect(leaves.map(\.view.id) == [0, 1, 2, 1, 5, 6, 7])
        #expect(node.layoutChildren.count == 7)
        #expect(runtime.root.layoutChildren.count == 7)
    }

    @Test func branchSwitchTearsDownOldSubtree() throws {
        let runtime = Runtime()
        let node = try #require(runtime.mount(Composite()) as? CompositeNode<Composite>)
        let tuple = try #require(node.child as? TupleNode<(Leaf, _ConditionalContent<Pair, Leaf>, Leaf?, Group<TupleView<(Leaf, Leaf)>>, _ConditionalContent<AnyView, AnyView>)>)
        let conditional = try #require(tuple.children[1] as? ConditionalNode<Pair, Leaf>)
        let firstBranch = conditional.activeNode
        #expect(firstBranch.isMounted)

        runtime.mount(Composite(shape: Shape(flag: false)))
        #expect(!firstBranch.isMounted)
        #expect(conditional.activeNode !== firstBranch)
        #expect(conditional.nodeDescription == "Conditional(second)")
        #expect(node.layoutChildren.count == 6)

        // Same branch again: the node is kept and updated in place.
        let secondBranch = conditional.activeNode
        runtime.mount(Composite(shape: Shape(flag: false, optional: nil)))
        #expect(conditional.activeNode === secondBranch)
        #expect(tuple.children[2].nodeDescription == "Optional(none)")
        #expect(node.layoutChildren.count == 5)

        runtime.mount(Composite(shape: Shape(flag: false, optional: 9)))
        let optionalLeaf = try #require(tuple.children[2].layoutChildren.first as? LeafNode<Leaf>)
        #expect(optionalLeaf.view.id == 9)
    }

    @Test func anyViewRebuildsOnlyWhenTypeChanges() throws {
        let runtime = Runtime()
        let node = try #require(runtime.mount(Composite()) as? CompositeNode<Composite>)
        func anyNode() throws -> AnyViewNode {
            let tuple = try #require(node.child as? TupleNode<(Leaf, _ConditionalContent<Pair, Leaf>, Leaf?, Group<TupleView<(Leaf, Leaf)>>, _ConditionalContent<AnyView, AnyView>)>)
            let conditional = try #require(tuple.children[4] as? ConditionalNode<AnyView, AnyView>)
            return try #require(conditional.activeNode as? AnyViewNode)
        }
        let before = try anyNode()
        let leafNode = before.child
        runtime.mount(Composite(shape: Shape(erased: 0)))   // same type: keeps the child
        #expect(try anyNode().child === leafNode)

        runtime.mount(Composite(shape: Shape(erased: 1)))   // different branch → new AnyView node
        let after = try anyNode()
        #expect(after !== before)
        #expect(after.nodeDescription == "AnyView(Pair)")
        #expect(node.layoutChildren.count == 8)
    }

    @Test func modifierBodyMountsContentPlaceholder() throws {
        let runtime = Runtime()
        let node = runtime.mount(Leaf(id: 1).modifier(Padded(amount: 10)))
        #expect(node.dump() == """
            Modifier<Padded>
              Tuple(2)
                LeafNode<Leaf>
                ModifierContent
                  LeafNode<Leaf>
            """)
        let leaves = node.layoutChildren.compactMap { $0 as? LeafNode<Leaf> }
        #expect(leaves.map(\.view.id) == [10, 1])
        let contentLeaf = leaves[1]

        // Updating only the content keeps the placeholder's node and pushes the new value.
        runtime.mount(Leaf(id: 2).modifier(Padded(amount: 10)))
        #expect(contentLeaf.isMounted)
        #expect(contentLeaf.view.id == 2)
        #expect(node.layoutChildren.compactMap { ($0 as? LeafNode<Leaf>)?.view.id } == [10, 2])
    }

    @Test func environmentModifierAppliesToSubtree() throws {
        let runtime = Runtime()
        let node = runtime.mount(Nested())
        let leaf = try #require(node.layoutChildren.first as? LeafNode<Leaf>)
        #expect(leaf.environment.depth == 2)
        #expect(node.environment.depth == 0)
        #expect(node.dump() == """
            CompositeNode<Nested>
              Environment<_EnvironmentKeyWritingModifier<Int>>
                LeafNode<Leaf>
            """)
        // Environment writes are transparent to layout.
        #expect(node.layoutChildren.count == 1)

        // The generation only moves when a value actually changes.
        var values = EnvironmentValues()
        let g0 = values.generation
        values.depth = 5
        #expect(values.generation != g0)
        let copy = values
        #expect(copy.generation == values.generation)
    }

    @Test func schedulerUpdatesTopDownOnce() throws {
        let runtime = Runtime()
        var needsFlushCalls = 0
        runtime.scheduler.onNeedsFlush = { needsFlushCalls += 1 }

        let node = try #require(runtime.mount(Composite()) as? CompositeNode<Composite>)
        let tuple = try #require(node.child as? TupleNode<(Leaf, _ConditionalContent<Pair, Leaf>, Leaf?, Group<TupleView<(Leaf, Leaf)>>, _ConditionalContent<AnyView, AnyView>)>)
        let conditional = try #require(tuple.children[1] as? ConditionalNode<Pair, Leaf>)
        let pair = try #require(conditional.activeNode as? CompositeNode<Pair>)
        #expect(node.bodyEvaluations == 1)
        #expect(pair.bodyEvaluations == 1)

        // Equal value: no body evaluation.
        runtime.mount(Composite())
        #expect(node.bodyEvaluations == 1)
        #expect(pair.bodyEvaluations == 1)

        // Invalidate child first, then parent: one flush, each body evaluated once, top-down.
        pair.invalidate()
        node.invalidate()
        #expect(needsFlushCalls == 1)
        #expect(runtime.scheduler.hasPendingWork)
        runtime.flush()
        #expect(node.bodyEvaluations == 2)
        #expect(pair.bodyEvaluations == 2)
        #expect(!runtime.scheduler.hasPendingWork)
        #expect(runtime.scheduler.flushCount == 1)

        // Idle flush is a no-op; a second invalidation batch requests a flush again.
        runtime.flush()
        #expect(runtime.scheduler.flushCount == 1)
        pair.invalidate()
        pair.invalidate()
        #expect(needsFlushCalls == 2)
        runtime.flush()
        #expect(pair.bodyEvaluations == 3)
        #expect(node.bodyEvaluations == 2)
    }

    @Test func rootRemountReplacesDifferentType() {
        let runtime = Runtime()
        let first = runtime.mount(Leaf(id: 1))
        let second = runtime.mount(Pair(base: 3))
        #expect(!first.isMounted)
        #expect(second.isMounted)
        #expect(runtime.root.layoutChildren.count == 2)
    }
}
