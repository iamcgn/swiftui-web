// The Combine-free ObservableObject family (Phase 3): @Published sends objectWillChange,
// @StateObject persists per view identity and re-renders, @ObservedObject re-subscribes when
// its object changes, @EnvironmentObject reads the environment, $object gives bindings.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct ObservableObjectTests {
    final class Counter: ObservableObject {
        @Published var count = 0
        @Published var on = false
        nonisolated(unsafe) static var created = 0
        init() { Self.created += 1 }
    }

    final class Manual: ObservableObject {
        let objectWillChange = ObservableObjectPublisher()
        var value = 0 { willSet { objectWillChange.send() } }
    }

    private func texts(_ r: Runtime) -> [String] {
        r.render(scale: 2).commands.map(\.description).compactMap { c in c.hasPrefix("drawText(\"") ? String(c.dropFirst(10).prefix { $0 != "\"" }) : nil }
    }

    private func runtime<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        var entries: [String: RecordedTextEngine.Entry] = [:]
        let f = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
        for word in ["0", "1", "2", "3", "+", "A", "B", "on", "off"] {
            entries[RecordedTextEngine.key(font: f, width: nil, string: word)] = .init(width: 10, height: 16, firstBaseline: 13, lastBaseline: 13)
        }
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 200, height: 100))
        return runtime
    }

    @Observable final class Parent: @unchecked Sendable { var tick = 0 }

    struct StateOwner: View {
        let parent: Parent
        @StateObject private var counter = Counter()
        var body: some View {
            VStack {
                Text("\(parent.tick)")
                Text("\(counter.count)")
                Button("+") { counter.count += 1 }
                Toggle("A", isOn: $counter.on)
            }
        }
    }

    @Test func stateObjectPersistsAndReRenders() {
        Counter.created = 0
        let parent = Parent()
        let r = runtime(StateOwner(parent: parent))
        #expect(Counter.created == 1)
        #expect(texts(r) == ["0", "0", "+"])   // the toggle label is in the body font the test engine lacks
        let plus = r.semanticsTree().first { $0.label == "+" }!
        r.activate(semanticsIdentifier: plus.identifier)
        r.layout(in: CGSize(width: 200, height: 100))
        #expect(texts(r) == ["0", "1", "+"])
        // The parent re-rendering keeps the same object (no new instance, the count survives).
        parent.tick += 1
        r.layout(in: CGSize(width: 200, height: 100))
        #expect(texts(r) == ["1", "1", "+"] && Counter.created == 1)
        // The binding from $counter.on toggles the published property and re-renders.
        let toggle = r.semanticsTree().first { $0.label == "A" }!
        r.activate(semanticsIdentifier: toggle.identifier)
        r.layout(in: CGSize(width: 200, height: 100))
        #expect(r.semanticsTree().first { $0.label == "A" }?.isOn == true)
    }

    @Observable final class Holder: @unchecked Sendable { var counter = Counter() }

    struct Observer: View {
        let holder: Holder
        var body: some View { Observed(counter: holder.counter) }
    }

    struct Observed: View {
        @ObservedObject var counter: Counter
        var body: some View { Text("\(counter.count)") }
    }

    @Test func observedObjectFollowsChangesAndReplacement() {
        let holder = Holder()
        let r = runtime(Observer(holder: holder))
        holder.counter.count = 2
        r.layout(in: CGSize(width: 200, height: 100))
        #expect(texts(r) == ["2"])
        let replacement = Counter()
        replacement.count = 3
        holder.counter = replacement
        r.layout(in: CGSize(width: 200, height: 100))
        #expect(texts(r) == ["3"])
        // The old object no longer re-renders the view; the new one does.
        replacement.count = 1
        r.layout(in: CGSize(width: 200, height: 100))
        #expect(texts(r) == ["1"])
    }

    struct Root: View {
        let manual: Manual
        var body: some View { Leaf().environmentObject(manual) }
    }

    struct Leaf: View {
        @EnvironmentObject var manual: Manual
        var body: some View { Text("\(manual.value)") }
    }

    @Test func environmentObjectAndManualPublisher() {
        let manual = Manual()
        let r = runtime(Root(manual: manual))
        #expect(texts(r) == ["0"])
        manual.value = 2
        r.layout(in: CGSize(width: 200, height: 100))
        #expect(texts(r) == ["2"])
        // Objects without their own publisher get one, stable per instance.
        let counter = Counter()
        #expect(counter.objectWillChange === counter.objectWillChange)
        var fired = 0
        let cancellable = counter.objectWillChange.sink { fired += 1 }
        counter.count = 5
        #expect(fired == 1)
        cancellable.cancel()
        counter.count = 6
        #expect(fired == 1)
    }
}
#endif
