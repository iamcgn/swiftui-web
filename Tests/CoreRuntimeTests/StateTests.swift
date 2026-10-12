// Phase 1 step 3: DynamicProperty installation, State, Binding, coalesced flushes.
import Testing
import SwiftUI

private struct Leaf: View, Equatable {
    var id: Int
    typealias Body = Never
    static func _makeNode(_ context: _NodeContext<Leaf>) -> TypedNode<Leaf> { LeafNode(context) }
}

private struct Counter: View {
    @State var count = 0
    var body: some View { Leaf(id: count) }
}

private struct Parent: View {
    var tick: Int
    var flag = true
    var identity = 0
    var body: some View {
        Leaf(id: tick)
        if flag { Counter() } else { Counter() }
        Counter().id(identity)
    }
}

private struct Pack: DynamicProperty {
    @State var inner = 1
    var updates = 0
    mutating func update() { updates += 1 }
}

private struct Nested: View {
    var pack = Pack()
    var body: some View { Leaf(id: pack.inner) }
}

private struct ThemeKey: EnvironmentKey { static let defaultValue = "light" }
extension EnvironmentValues {
    fileprivate var theme: String {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

private struct Themed: View {
    @Environment(\.theme) var theme
    var body: some View { Leaf(id: theme.count) }
}

private struct Wrapper: View {
    var body: some View { Themed().environment(\.theme, "dark") }
}

private struct Point: Equatable { var x = 0; var y = 0 }

@Suite @MainActor struct StateTests {
    private func counters(_ node: ViewNode) -> [CompositeNode<Counter>] {
        var found: [CompositeNode<Counter>] = []
        func walk(_ n: ViewNode) {
            if let c = n as? CompositeNode<Counter> { found.append(c) }
            n.structuralChildren.forEach(walk)
        }
        walk(node)
        return found
    }

    @Test func stateSurvivesParentReevaluation() throws {
        let runtime = Runtime()
        let root = try #require(runtime.mount(Parent(tick: 0)) as? CompositeNode<Parent>)
        let counter = try #require(counters(root).first)
        #expect(counter.view.count == 0)
        #expect(root.layoutChildren.compactMap { ($0 as? LeafNode<Leaf>)?.view.id } == [0, 0, 0])

        counter.view.count = 5           // the installed view writes through to the box
        #expect(counter.view.count == 5)
        #expect(runtime.scheduler.hasPendingWork)
        runtime.flush()
        #expect(root.layoutChildren.compactMap { ($0 as? LeafNode<Leaf>)?.view.id } == [0, 5, 0])

        runtime.mount(Parent(tick: 1))   // parent re-evaluates; child identity is unchanged
        #expect(root.bodyEvaluations == 2)
        #expect(counters(root).first === counter)
        #expect(counter.view.count == 5)
        #expect(root.layoutChildren.compactMap { ($0 as? LeafNode<Leaf>)?.view.id } == [1, 5, 0])
    }

    @Test func stateResetsOnBranchSwitchAndID() throws {
        let runtime = Runtime()
        let root = try #require(runtime.mount(Parent(tick: 0)) as? CompositeNode<Parent>)
        let (branchCounter, idCounter) = (counters(root)[0], counters(root)[1])
        branchCounter.view.count = 3
        idCounter.view.count = 4
        runtime.flush()
        #expect(root.layoutChildren.compactMap { ($0 as? LeafNode<Leaf>)?.view.id } == [0, 3, 4])

        runtime.mount(Parent(tick: 0, flag: false))
        #expect(!branchCounter.isMounted)
        #expect(counters(root)[0].view.count == 0)
        #expect(counters(root)[1] === idCounter)
        #expect(idCounter.view.count == 4)

        runtime.mount(Parent(tick: 0, flag: false, identity: 1))
        #expect(!idCounter.isMounted)
        #expect(counters(root)[1].view.count == 0)
        #expect(root.layoutChildren.compactMap { ($0 as? LeafNode<Leaf>)?.view.id } == [0, 0, 0])
    }

    @Test func writesCoalesceIntoOneFlush() throws {
        let runtime = Runtime()
        let root = try #require(runtime.mount(Counter()) as? CompositeNode<Counter>)
        #expect(root.bodyEvaluations == 1)
        root.view.count = 1
        root.view.count = 2
        root.view.count += 1
        #expect(root.bodyEvaluations == 1)
        runtime.flush()
        #expect(root.bodyEvaluations == 2)
        #expect(runtime.scheduler.flushCount == 1)
        #expect(root.layoutChildren.compactMap { ($0 as? LeafNode<Leaf>)?.view.id } == [3])

        // Writing through a binding is the same.
        let binding = root.view.$count
        binding.wrappedValue = 10
        runtime.flush()
        #expect(root.bodyEvaluations == 3)
        #expect(root.view.count == 10)
        #expect(binding.wrappedValue == 10)
    }

    @Test func uninstalledStateReadsInitialValueAndDropsWrites() {
        let counter = Counter()
        #expect(counter.count == 0)
        counter.count = 9
        #expect(counter.count == 0)
        #expect(counter.$count.wrappedValue == 0)
    }

    @Test func bindingProjections() throws {
        final class Store { var point = Point(); var optional: Int? = 3; var list = [1, 2, 3] }
        let store = Store()
        let point = Binding(get: { store.point }, set: { store.point = $0 })
        point.x.wrappedValue = 7
        #expect(store.point == Point(x: 7, y: 0))
        #expect(point.y.wrappedValue == 0)

        let constant = Binding.constant(1)
        constant.wrappedValue = 2
        #expect(constant.wrappedValue == 1)

        let optional = Binding(get: { store.optional }, set: { store.optional = $0 })
        let unwrapped = try #require(Binding(optional))
        unwrapped.wrappedValue = 4
        #expect(store.optional == 4)
        store.optional = nil
        #expect(Binding(optional) == nil)

        let rewrapped = Binding<Int?>(unwrapped)
        rewrapped.wrappedValue = 8
        #expect(store.optional == 8)
        rewrapped.wrappedValue = nil          // nil writes are ignored by the projection
        #expect(store.optional == 8)

        let list = Binding(get: { store.list }, set: { store.list = $0 })
        #expect(list.count == 3)
        list[1].wrappedValue = 20
        #expect(store.list == [1, 20, 3])
        #expect(list.map(\.wrappedValue) == [1, 20, 3])

        var transaction = Transaction()
        transaction.disablesAnimations = true
        #expect(point.transaction(transaction).transaction.disablesAnimations)
        #expect(Binding(projectedValue: point).wrappedValue == store.point)
    }

    @Test func nestedDynamicPropertiesInstallAndUpdate() throws {
        let runtime = Runtime()
        let root = try #require(runtime.mount(Nested()) as? CompositeNode<Nested>)
        #expect(root.view.pack.updates == 1)
        root.view.pack.inner = 5
        runtime.flush()
        #expect(root.bodyEvaluations == 2)
        #expect(root.view.pack.inner == 5)
        #expect(root.view.pack.updates == 2)
        #expect(root.layoutChildren.compactMap { ($0 as? LeafNode<Leaf>)?.view.id } == [5])
    }

    @Test func environmentPropertyResolvesAtInstall() throws {
        let runtime = Runtime()
        let root = runtime.mount(Wrapper())
        var themed: CompositeNode<Themed>?
        func walk(_ n: ViewNode) {
            if let t = n as? CompositeNode<Themed> { themed = t }
            n.structuralChildren.forEach(walk)
        }
        walk(root)
        let node = try #require(themed)
        #expect(node.view.theme == "dark")
        #expect(root.layoutChildren.compactMap { ($0 as? LeafNode<Leaf>)?.view.id } == [4])
        #expect(Themed().theme == "light")
    }
}

// Decision 0021: a `@StateObject` on the `App` struct is one object for the process.
@MainActor
@Suite struct AppStateObjectTests {
    final class Model: ObservableObject {
        nonisolated(unsafe) static var made = 0
        @Published var count = 0
        init() { Model.made += 1 }
    }
    struct Probe: App {
        @StateObject var model = Model()
        var body: some Scene { WindowGroup { Text("\(model.count)") } }
    }

    @Test func appStateObjectIsMadeOnceAndItsChangesRereadTheBody() {
        Model.made = 0
        _ = Probe._windows()
        _ = Probe._rootView()
        _ = Probe._windows()
        #expect(Model.made == 1)
        // A host: the model's change re-reads the body and updates the root in place.
        let runtime = Runtime()
        runtime.mount(Probe._rootView())
        var remounts = 0
        _appRemount = (runtime, { runtime.mount(Probe._rootView()); remounts += 1 })
        defer { _appRemount = nil }
        let texts = { runtime.root.descendants(where: { $0 is TextNode }).compactMap { ($0 as? TextNode)?.view.resolvedString } }
        #expect(texts() == ["0"])
        Probe._instance.model.count = 5
        Probe._instance.model.count = 6
        runtime.flush()
        #expect(remounts == 1 && texts() == ["6"])
    }
}
