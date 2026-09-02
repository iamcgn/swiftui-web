// Phase 1 step 4: @Observable dependency tracking per body, @Environment(Type.self), @Bindable.
import Testing
import SwiftUI

private struct Leaf: View, Equatable {
    var id: Int
    typealias Body = Never
    static func _makeNode(_ context: _NodeContext<Leaf>) -> TypedNode<Leaf> { LeafNode(context) }
}

@Observable private final class Model {
    var a = 0
    var b = 0
    var unread = 0
}

private struct ReadsA: View {
    var model: Model
    var body: some View { Leaf(id: model.a) }
}

private struct ReadsB: View {
    var model: Model
    var body: some View { Leaf(id: model.b) }
}

private struct Parent: View {
    var model: Model
    var body: some View {
        ReadsA(model: model)
        ReadsB(model: model)
    }
}

private struct FromEnvironment: View {
    @Environment(Model.self) var model
    @Environment(Model.self) var optionalModel: Model?
    var body: some View { Leaf(id: model.a + (optionalModel == nil ? 0 : 100)) }
}

private struct Editor: View {
    @Bindable var model: Model
    var body: some View { Leaf(id: $model.a.wrappedValue) }
}

@Suite @MainActor struct ObservationTests {
    private func composites<V: View>(_ type: V.Type, in node: ViewNode) -> [CompositeNode<V>] {
        var found: [CompositeNode<V>] = []
        func walk(_ n: ViewNode) {
            if let c = n as? CompositeNode<V> { found.append(c) }
            n.structuralChildren.forEach(walk)
        }
        walk(node)
        return found
    }

    @Test func mutationInvalidatesOnlyReadingNodes() throws {
        let runtime = Runtime()
        let model = Model()
        let root = try #require(runtime.mount(Parent(model: model)) as? CompositeNode<Parent>)
        let readsA = try #require(composites(ReadsA.self, in: root).first)
        let readsB = try #require(composites(ReadsB.self, in: root).first)
        #expect((root.bodyEvaluations, readsA.bodyEvaluations, readsB.bodyEvaluations) == (1, 1, 1))

        model.a = 1
        #expect(readsA.needsUpdate)
        #expect(!readsB.needsUpdate)
        #expect(!root.needsUpdate)
        runtime.flush()
        #expect((root.bodyEvaluations, readsA.bodyEvaluations, readsB.bodyEvaluations) == (1, 2, 1))
        #expect(root.layoutChildren.compactMap { ($0 as? LeafNode<Leaf>)?.view.id } == [1, 0])

        // Several writes before a flush coalesce; tracking is re-armed after each evaluation.
        model.b = 2
        model.b = 3
        model.a = 4
        runtime.flush()
        #expect((root.bodyEvaluations, readsA.bodyEvaluations, readsB.bodyEvaluations) == (1, 3, 2))
        #expect(root.layoutChildren.compactMap { ($0 as? LeafNode<Leaf>)?.view.id } == [4, 3])

        // Properties nobody read do not invalidate anything.
        model.unread = 9
        #expect(!runtime.scheduler.hasPendingWork)
    }

    @Test func staleObservationSessionsDoNotInvalidate() throws {
        let runtime = Runtime()
        let model = Model()
        let root = try #require(runtime.mount(ReadsA(model: model)) as? CompositeNode<ReadsA>)
        // Each evaluation arms a new session (the view holds a class reference, so a re-mount
        // counts as changed). A mutation must then invalidate exactly once, not once per
        // session that ever observed the property.
        runtime.mount(ReadsA(model: model))
        root.invalidate()
        runtime.flush()
        #expect(root.bodyEvaluations == 3)
        model.a = 1
        #expect(root.needsUpdate)
        runtime.flush()
        #expect(root.bodyEvaluations == 4)
        #expect(!runtime.scheduler.hasPendingWork)
        model.a = 2
        runtime.flush()
        #expect(root.bodyEvaluations == 5)
    }

    @Test func environmentObjects() throws {
        let runtime = Runtime()
        let model = Model()
        model.a = 7
        let root = runtime.mount(FromEnvironment().environment(model))
        let reader = try #require(composites(FromEnvironment.self, in: root).first)
        #expect(reader.view.model === model)
        #expect(reader.view.optionalModel === model)
        #expect(root.layoutChildren.compactMap { ($0 as? LeafNode<Leaf>)?.view.id } == [107])

        model.a = 8
        runtime.flush()
        #expect(root.layoutChildren.compactMap { ($0 as? LeafNode<Leaf>)?.view.id } == [108])

        var values = EnvironmentValues()
        #expect(values[Model.self] == nil)
        values[Model.self] = model
        #expect(values[Model.self] === model)
        let optional = Environment<Model?>(Model.self)
        #expect(optional.wrappedValue == nil)
    }

    @Test func bindableProducesBindings() throws {
        let model = Model()
        let bindable = Bindable(model)
        let binding = bindable.a
        binding.wrappedValue = 5
        #expect(model.a == 5)
        #expect(Bindable(projectedValue: bindable).wrappedValue === model)

        let runtime = Runtime()
        let root = try #require(runtime.mount(Editor(model: model)) as? CompositeNode<Editor>)
        #expect(root.layoutChildren.compactMap { ($0 as? LeafNode<Leaf>)?.view.id } == [5])
        root.view.$model.a.wrappedValue = 6
        runtime.flush()
        #expect(root.bodyEvaluations == 2)
        #expect(root.layoutChildren.compactMap { ($0 as? LeafNode<Leaf>)?.view.id } == [6])
    }
}
