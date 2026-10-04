// Phase 8 step 6, sw-focus: key-up phases, onKeyPress(characters:), the responder commands
// (onCommand, onCopyCommand, onCutCommand, onPasteCommand), defaultFocus, focusSection in the
// Tab order, focusScope with prefersDefaultFocus and resetFocus, focus restored after a sheet
// closes, and type-to-select in lists.
import Testing
import SwiftUI
import SwiftUIWebHeadless

#if !os(WASI)
@MainActor private final class Log { var events: [String] = [] }

@Suite @MainActor struct FocusCommandTests {
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)

    private func engine() -> RecordedTextEngine {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for (word, width) in [("Apple", 35.0), ("Banana", 45.0), ("Cherry", 41.5), ("Avocado", 50.0), ("One", 25.0), ("Two", 26.0), ("Three", 36.0),
                              ("Four", 30.0), ("Focus me", 52.0), ("Open", 32.0), ("Close", 36.0), ("Field", 30.0)] {
            entries[RecordedTextEngine.key(font: Self.system13, width: nil, string: word)] = .init(width: width, height: 16, firstBaseline: 13, lastBaseline: 13)
        }
        return RecordedTextEngine(entries: entries)
    }

    private func runtime<V: View>(_ view: V) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = engine()
        runtime.mount(view)
        runtime.layout(in: CGSize(width: 320, height: 200))
        return runtime
    }

    private func relayout(_ r: Runtime) { r.layout(in: CGSize(width: 320, height: 200)) }
    private func sel(_ name: String) -> Selector { Selector(name) }

    private func key(_ key: KeyEquivalent, _ modifiers: EventModifiers = [], characters: String? = nil, time: Double = 0) -> KeyEvent {
        KeyEvent(key: key, characters: characters ?? (key.character.isLetter || key.character.isNumber ? String(key.character) : ""), modifiers: modifiers, time: time)
    }

    private func focusedButton(_ r: Runtime, _ label: String) -> Bool {
        r.focusedIdentifier == r.semanticsTree().first { $0.label == label }?.identifier
    }

    @Test func keyUpPhasesAndCharacterSets() {
        let log = Log()
        let r = runtime(Text("Focus me").focusable()
            .onKeyPress(characters: .decimalDigits) { log.events.append("digit \($0.characters)"); return .handled }
            .onKeyPress(.space, phases: [.up]) { _ in log.events.append("space up"); return .handled }
            .onKeyPress(keys: ["a"], phases: .all) { log.events.append("a \($0.phase == .up ? "up" : "down")"); return .handled })
        r.moveFocus()
        #expect(r.keyDown(key("5")))
        #expect(!r.keyDown(key("b")))
        #expect(!r.keyDown(key(.space)))
        #expect(r.keyUp(key(.space)))
        #expect(r.keyDown(key("a")) && r.keyUp(key("a")))
        #expect(log.events == ["digit 5", "space up", "a down", "a up"])
    }

    @Test func commandsReachTheFocusedChain() async throws {
        let log = Log()
        let r = runtime(VStack {
            Button("One") {}
                .onCommand(sel("selectAll:"), perform: { log.events.append("select all") })
                .onCopyCommand { [NSItemProvider(object: "copied" as NSString)] }
                .onPasteCommand(of: [.plainText]) { providers in log.events.append("pasted \(providers.count)") }
            Button("Two") {}.onCommand(sel("undo:"), perform: nil)
        })
        r.moveFocus()
        #expect(focusedButton(r, "One"))
        #expect(r.keyDown(key("a", [.command])))
        #expect(log.events == ["select all"])
        // A nil action does not handle the command; nothing else does either.
        r.moveFocus()
        #expect(!r.keyDown(key("z", [.command])))
        #expect(r.performCommand(sel("selectAll:")))   // falls back to the tree's handler
        #expect(log.events == ["select all", "select all"])
        // Copy loads the provider's text onto the pasteboard; paste hands it back as a provider.
        r.moveFocus()
        #expect(focusedButton(r, "One"))
        #expect(r.pasteboardText == nil)
        #expect(!r.keyDown(key("v", [.command])))
        #expect(r.keyDown(key("c", [.command])))
        for _ in 0..<50 where r.pasteboardText == nil { try await Task.sleep(for: .milliseconds(20)) }
        #expect(r.pasteboardText == "copied")
        #expect(r.keyDown(key("v", [.command])))
        #expect(log.events.last == "pasted 1")
        // The paste handler's types must include a text type.
        let image = Log()
        let other = runtime(Button("One") {}.onPasteCommand(of: [UTType("public.png")]) { _ in image.events.append("pasted") })
        other.setPasteboard([_TransferItem("text")])
        other.moveFocus()
        #expect(!other.keyDown(key("v", [.command])) && image.events.isEmpty)
    }

    struct Fields: View {
        enum Field: Hashable { case first, second }
        @FocusState private var focus: Field?
        var body: some View {
            VStack {
                TextField("Field", text: .constant("")).focused($focus, equals: .first)
                TextField("Field", text: .constant("")).focused($focus, equals: .second)
                Text(focus == .second ? "Two" : focus == .first ? "One" : "Three")
            }
            .defaultFocus($focus, .second)
        }
    }

    @Test func defaultFocusAppliesOnceMounted() {
        let r = runtime(Fields())
        relayout(r)
        #expect(r.semanticsTree().contains { $0.label == "Two" })
        #expect(r.focusedTextFieldIdentifier != nil && r.focusedTextFieldIdentifier == r.focusedIdentifier)
        // With something already focused the default does not override it.
        let busy = Runtime()
        busy.textEngine = engine()
        busy.mount(VStack { Button("Open") {}; Fields() })
        busy.layout(in: CGSize(width: 320, height: 200))
        busy.moveFocus()
        busy.layout(in: CGSize(width: 320, height: 200))
        #expect(focusedButton(busy, "Open"))
    }

    @Test func focusSectionsKeepTheirElementsTogether() {
        // Without sections the Tab order is the paint order.
        let plain = runtime(VStack {
            Button("One") {}
            Button("Two") {}.focusSection()
            Button("Three") {}
            Button("Four") {}
        })
        plain.moveFocus(); plain.moveFocus()
        #expect(focusedButton(plain, "Two"))
        plain.moveFocus()
        #expect(focusedButton(plain, "Three"))
        // A section around Two and Four (a Group split by Three, which has its own section)
        // keeps Four right after Two.
        let grouped = runtime(VStack {
            Button("One") {}
            Group { Button("Two") {}; Button("Three") {}.focusSection(); Button("Four") {} }.focusSection()
        })
        var order: [String] = []
        for _ in 0..<4 { grouped.moveFocus(); order.append(grouped.semanticsTree().first { $0.identifier == grouped.focusedIdentifier }?.label ?? "?") }
        #expect(order == ["One", "Two", "Four", "Three"])
    }

    struct Scoped: View {
        @Namespace private var scope
        @Environment(\.resetFocus) private var resetFocus
        var body: some View {
            VStack {
                Button("One") {}
                VStack {
                    Button("Two") {}
                    Button("Three") {}.prefersDefaultFocus(in: scope)
                    Button("Four") {}
                }
                .focusScope(scope)
                Button("Open") { resetFocus(in: scope) }
            }
        }
    }

    @Test func focusScopesLandOnThePreferredDefault() {
        let r = runtime(Scoped())
        r.moveFocus()
        #expect(focusedButton(r, "One"))
        // Entering the scope lands on Three; moving inside it is sequential.
        r.moveFocus()
        #expect(focusedButton(r, "Three"))
        r.moveFocus()
        #expect(focusedButton(r, "Four"))
        r.moveFocus()
        #expect(focusedButton(r, "Open"))
        // resetFocus sends focus to the preferred default.
        r.keyDown(key(.space))
        #expect(focusedButton(r, "Three"))
    }

    struct Sheet: View {
        @State private var shown = false
        var body: some View {
            VStack {
                Button("Open") { shown = true }
                Button("Close") {}
            }
            .sheet(isPresented: $shown) { Button("Close") { shown = false } }
        }
    }

    @Test func focusReturnsAfterASheetCloses() {
        let r = runtime(Sheet())
        r.moveFocus()
        #expect(focusedButton(r, "Open"))
        r.keyDown(key(.space))
        relayout(r)
        #expect(r.hasPresentations)
        // Focus moves into the sheet; closing it brings focus back to the Open button.
        r.moveFocus()
        let inSheet = r.focusedIdentifier
        r.keyDown(key(.space))
        relayout(r)
        #expect(!r.hasPresentations)
        #expect(r.focusedIdentifier != inSheet && focusedButton(r, "Open"))
    }

    struct Item: Identifiable, Hashable { let id: Int; let name: String }
    static let items = [Item(id: 1, name: "Apple"), Item(id: 2, name: "Banana"), Item(id: 3, name: "Avocado"), Item(id: 4, name: "Cherry")]

    @Test func typeToSelectInLists() {
        let box = _SelectionBox()
        let r = runtime(List(Self.items, selection: Binding<Int?>(get: { box.value }, set: { box.value = $0 })) { Text($0.name) })
        r.moveFocus()
        #expect(r.keyDown(key("c", time: 0)))
        #expect(box.value == 4)
        // Letters within a second of each other build a prefix; after a pause it starts over.
        #expect(r.keyDown(key("a", time: 2)))
        #expect(box.value == 1)
        #expect(r.keyDown(key("v", time: 2.2)))
        #expect(box.value == 3)
        #expect(r.keyDown(key("b", time: 4)))
        #expect(box.value == 2)
        #expect(!r.keyDown(key("z", time: 4.1)))
        #expect(box.value == 2)
    }
}

private final class _SelectionBox: @unchecked Sendable { var value: Int? = nil }
#endif
