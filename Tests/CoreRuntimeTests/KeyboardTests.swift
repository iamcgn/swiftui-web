// Keyboard: general focus and the focus ring, key dispatch from the focused view outwards
// (onKeyPress, move/exit/delete commands), list arrow-key selection, menu keyboard navigation,
// keyboard shortcuts and Escape for presentations. Layout against goldens is in GoldenFrameTests.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct KeyboardTests {
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)
    static let body = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: .body)

    private func engine() -> RecordedTextEngine {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for (word, width) in [("Apple", 35.0), ("Banana", 45.0), ("Cherry", 41.5), ("Focus me", 52.0), ("Save", 29.0), ("Go", 17.0),
                              ("Cancel", 42.0), ("Cut", 21.5), ("Copy", 31.5), ("Options", 47.5), ("Sheet", 35.0), ("Done", 33.0)] {
            entries[RecordedTextEngine.key(font: Self.system13, width: nil, string: word)] = .init(width: width, height: 16, firstBaseline: 13, lastBaseline: 13)
            entries[RecordedTextEngine.key(font: Self.body, width: nil, string: word)] = .init(width: width, height: 18.5, firstBaseline: 14, lastBaseline: 14)
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

    private func key(_ key: KeyEquivalent, _ modifiers: EventModifiers = []) -> KeyEvent { KeyEvent(key: key, modifiers: modifiers) }

    struct Item: Identifiable, Hashable { let id: Int; let name: String }
    static let items = [Item(id: 1, name: "Apple"), Item(id: 2, name: "Banana"), Item(id: 3, name: "Cherry")]

    @Test func listArrowKeysMoveTheSelection() {
        let box = _KeyBox()
        let binding = Binding<Int?>(get: { box.selection }, set: { box.selection = $0 })
        let r = runtime(List(Self.items, selection: binding) { Text($0.name) })
        // A selectable list is a focusable listbox in the accessibility tree.
        let list = r.semanticsTree().first { $0.role == .list }!
        #expect(list.isFocusable)
        // Keys do nothing until the list has focus.
        #expect(!r.keyDown(key(.downArrow)))
        r.focus(semanticsIdentifier: list.identifier)
        #expect(r.keyDown(key(.downArrow)) && box.selection == 1)
        #expect(r.keyDown(key(.downArrow)) && box.selection == 2)
        #expect(r.keyDown(key(.upArrow)) && box.selection == 1)
        #expect(r.keyDown(key(.end)) && box.selection == 3)
        #expect(r.keyDown(key(.downArrow)) && box.selection == 3)
        #expect(r.keyDown(key(.home)) && box.selection == 1)
        // The focused list paints its selection in the accent colour.
        relayout(r)
        let commands = r.render(scale: 2).commands.map(\.description)
        #expect(commands.contains { $0.hasPrefix("fillRRect(10, 10, 300, 24) r=7 #") && !$0.contains("#000000") })
        // Shift extends a multiple selection from the anchor row.
        let set = _KeySetBox()
        let multi = runtime(List(Self.items, selection: Binding<Set<Int>>(get: { set.value }, set: { set.value = $0 })) { Text($0.name) })
        multi.focus(semanticsIdentifier: multi.semanticsTree().first { $0.role == .list }!.identifier)
        multi.keyDown(key(.downArrow))
        multi.keyDown(key(.downArrow, .shift))
        multi.keyDown(key(.downArrow, .shift))
        #expect(set.value == [1, 2, 3])
        multi.keyDown(key(.upArrow))
        #expect(set.value == [2])
    }

    @Test func keyPressAndCommandsOnTheFocusedView() {
        let box = _KeyBox()
        let r = runtime(Text("Focus me").focusable()
            .onKeyPress(.upArrow) { box.log = "up"; return .handled }
            .onKeyPress(keys: ["a", "b"]) { press in box.log = "letter \(press.characters)"; return .ignored }
            .onMoveCommand { box.log = "move \($0)" }
            .onExitCommand { box.log = "exit" }
            .onDeleteCommand { box.log = "delete" })
        let focusable = r.semanticsTree().first { $0.isFocusable }!
        #expect(focusable.role == .group && focusable.label == "Focus me")
        #expect(!r.keyDown(key(.upArrow)) && box.log == "")
        r.focus(semanticsIdentifier: focusable.identifier)
        #expect(r.keyDown(key(.upArrow)) && box.log == "up")
        // A key the inner handler does not claim reaches the outer command.
        #expect(r.keyDown(key(.rightArrow)) && box.log == "move right")
        #expect(r.keyDown(key(.escape)) && box.log == "exit")
        #expect(r.keyDown(key(.delete)) && box.log == "delete")
        // An ignored result lets the press go on (nothing else handles "a").
        #expect(!r.keyDown(KeyEvent(key: "a", characters: "a")) && box.log == "letter a")
        // The focus ring is painted around the focused view for keyboard focus only.
        relayout(r)
        #expect(r.render(scale: 2).commands.map(\.description).contains { $0.hasPrefix("strokePath") && $0.contains("w=3") })
        r.focus(semanticsIdentifier: focusable.identifier, keyboard: false)
        #expect(!r.render(scale: 2).commands.map(\.description).contains { $0.hasPrefix("strokePath") })
        r.blur(semanticsIdentifier: focusable.identifier)
        #expect(r.focusedIdentifier == nil)
    }

    @Test func shortcutsActivateButtons() {
        let box = _KeyBox()
        let r = runtime(HStack {
            Button("Save") { box.log = "save" }.keyboardShortcut("s")
            Button("Go") { box.log = "go" }.keyboardShortcut(.defaultAction)
            Button("Cancel") { box.log = "cancel" }.keyboardShortcut(.cancelAction)
        })
        #expect(!r.keyDown(KeyEvent(key: "s", characters: "s")) && box.log == "")
        #expect(r.keyDown(key("s", .command)) && box.log == "save")
        #expect(r.keyDown(key(.return)) && box.log == "go")
        #expect(r.keyDown(key(.escape)) && box.log == "cancel")
        #expect(!r.keyDown(key("s", [.command, .shift])))
    }

    @Test func escapeDismissesAndMenusNavigate() {
        let box = _KeyBox()
        let r = runtime(VStack {
            Button("Cancel") { box.log = "cancel" }.keyboardShortcut(.cancelAction)
            Menu("Options") {
                Button("Cut") { box.log = "cut" }
                Button("Copy") { box.log = "copy" }
            }._probe("menu")
        })
        // A sheet with its own cancel button: Escape runs that; a sheet without one closes on
        // Escape before the window's cancel action runs.
        let closed = _KeyBox()
        r.present(kind: .sheet, view: AnyView(Button("Done") { closed.log = "done" }.keyboardShortcut(.cancelAction)),
                  environment: EnvironmentValues(), anchor: nil) {}
        relayout(r)
        #expect(r.keyDown(key(.escape)) && closed.log == "done" && box.log == "" && r.presentations.count == 1)
        r.dismissTopmostPresentation()
        r.present(kind: .sheet, view: AnyView(Text("Sheet")), environment: EnvironmentValues(), anchor: nil) { closed.log = "dismissed" }
        relayout(r)
        #expect(r.keyDown(key(.escape)) && r.presentations.isEmpty && closed.log == "dismissed" && box.log == "")
        #expect(r.keyDown(key(.escape)) && box.log == "cancel")
        let menu = r.probeFrames["menu"]!
        r.pointerDown(at: CGPoint(x: menu.midX, y: menu.midY)); r.pointerUp(at: CGPoint(x: menu.midX, y: menu.midY))
        relayout(r)
        #expect(r.presentations.first?.kind == .menu)
        // Down twice highlights the second row; Return runs it and closes the menu.
        #expect(r.keyDown(key(.downArrow)) && r.keyDown(key(.downArrow)))
        #expect(r.presentations.first?.highlightedIndex == 1)
        #expect(r.render(scale: 2).commands.map(\.description).contains { $0.hasPrefix("fillRRect") && $0.contains("r=4 #000000@0.1") })
        #expect(r.keyDown(key(.return)) && box.log == "copy" && r.presentations.isEmpty)
        // Up from nothing highlights the last row; Escape closes.
        r.pointerDown(at: CGPoint(x: menu.midX, y: menu.midY)); r.pointerUp(at: CGPoint(x: menu.midX, y: menu.midY))
        relayout(r)
        #expect(r.keyDown(key(.upArrow)) && r.presentations.first?.highlightedIndex == 1)
        #expect(r.keyDown(key(.escape)) && r.presentations.isEmpty)
    }

    @Test func tabMovesFocusAndSpaceActivates() {
        let box = _KeyBox()
        let r = runtime(VStack {
            Text("Focus me")
            Button("Save") { box.log = "save" }
            Text("Focus me").focusable()
            Button("Go") { box.log = "go" }
        })
        let ids = r.semanticsTree().filter { $0.role == .button || $0.isFocusable }.map(\.identifier)
        #expect(r.focusOrder == ids && ids.count == 3)
        // Tab from nothing focuses the first element, then cycles; Shift-Tab goes back.
        #expect(r.keyDown(key(.tab)) && r.focusedIdentifier == ids[0] && r.focusVisible)
        #expect(r.keyDown(key(.tab)) && r.focusedIdentifier == ids[1])
        #expect(r.keyDown(key(.tab, .shift)) && r.focusedIdentifier == ids[0])
        #expect(r.keyDown(key(.tab, .shift)) && r.focusedIdentifier == ids[2])
        // Space and Return activate a focused button, not a focusable view.
        #expect(r.keyDown(key(.space)) && box.log == "go")
        r.moveFocus(forward: true)
        #expect(r.focusedIdentifier == ids[0])
        #expect(r.keyDown(key(.return)) && box.log == "save")
        r.focus(semanticsIdentifier: ids[1])
        #expect(!r.keyDown(key(.space)) && box.log == "save")
    }

    @Test func domKeys() {
        #expect(KeyEquivalent(domKey: "ArrowUp") == .upArrow)
        #expect(KeyEquivalent(domKey: "Enter") == .return)
        #expect(KeyEquivalent(domKey: " ") == .space)
        #expect(KeyEquivalent(domKey: "S") == "s")
        #expect(KeyEquivalent(domKey: "Shift") == nil)
    }
}

private final class _KeyBox: @unchecked Sendable {
    var log = ""
    var selection: Int? = nil
    var sheet = false
}
private final class _KeySetBox: @unchecked Sendable { var value: Set<Int> = [] }
#endif
