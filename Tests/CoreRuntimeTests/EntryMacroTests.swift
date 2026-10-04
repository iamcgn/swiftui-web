// Phase 8 step 6, sw-entry-macro: `@Entry` on EnvironmentValues, FocusedValues and Transaction
// extensions, and focused values following keyboard focus.
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
extension EnvironmentValues {
    @Entry var accentWord: String = "plain"
    @Entry var entryDepth: Int = 1
}

extension FocusedValues {
    @Entry var selectedName: String?
    @Entry var counter: Binding<Int>?
}

extension Transaction {
    @Entry var tracksCompletion: Bool = false
}

@MainActor private final class Log { var seen: [String] = [] }
@Observable private final class Model { var count = 3 }

private struct Reader: View {
    @Environment(\.accentWord) private var word
    @Environment(\.entryDepth) private var depth
    let log: Log
    var body: some View {
        let _ = log.seen.append("\(word) \(depth)")
        return Text("Hi")
    }
}

private struct Watcher: View {
    @FocusedValue(\.selectedName) private var name
    @FocusedBinding(\.counter) private var counter
    let log: Log
    var body: some View {
        let _ = log.seen.append("name=\(name ?? "none") counter=\(counter.map(String.init) ?? "none")")
        return Text("Hi")
    }
}

@Suite @MainActor struct EntryMacroTests {
    private static let body = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)

    private func runtime<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: [RecordedTextEngine.key(font: Self.body, width: nil, string: "Hi"): .init(width: 16, height: 16, firstBaseline: 13, lastBaseline: 13)])
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 200, height: 100))
        return runtime
    }

    @Test func environmentAndTransactionEntries() {
        var values = EnvironmentValues()
        #expect(values.accentWord == "plain" && values.entryDepth == 1)
        values.accentWord = "bold"
        #expect(values.accentWord == "bold")
        let log = Log()
        _ = runtime(Reader(log: log).environment(\.entryDepth, 4).environment(\.accentWord, "deep"))
        #expect(log.seen.last == "deep 4")
        var transaction = Transaction()
        #expect(!transaction.tracksCompletion)
        transaction.tracksCompletion = true
        #expect(transaction.tracksCompletion)
    }

    @Test func focusedValuesFollowFocus() {
        let log = Log()
        let model = Model()
        let runtime = runtime(VStack {
            Watcher(log: log)
            Button("One") {}.focusedValue(\.selectedName, "one").focusedValue(\.counter, Binding(get: { model.count }, set: { model.count = $0 }))
            Button("Two") {}.focusedValue(\.selectedName, "two")
        }.focusedSceneValue(\.selectedName, "scene"))
        // Nothing focused: the scene value shows.
        #expect(log.seen.last == "name=scene counter=none")
        #expect(runtime.moveFocus(forward: true))
        runtime.layout(in: CGSize(width: 200, height: 100))
        #expect(log.seen.last == "name=one counter=3")
        #expect(runtime.focusedValues.counter?.wrappedValue == 3)
        runtime.focusedValues.counter?.wrappedValue = 5
        #expect(model.count == 5)
        #expect(runtime.moveFocus(forward: true))
        runtime.layout(in: CGSize(width: 200, height: 100))
        #expect(log.seen.last == "name=two counter=none")
    }
}
#endif
