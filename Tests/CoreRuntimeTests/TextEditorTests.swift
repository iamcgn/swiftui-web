// TextEditor: sizing (fills its proposal, default stack spacing), the text's inset, first
// baseline and line pitch, the background and its `scrollContentBackground`/plain-style
// removal, colours, focus and host text input (newline on submit). Layout against goldens is
// in GoldenFrameTests.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct TextEditorTests {
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)

    private func runtime<V: View>(_ view: V, size: CGSize = CGSize(width: 320, height: 200)) -> Runtime {
        var entries: [String: RecordedTextEngine.Entry] = [:]
        for (word, width, lines) in [("Hello", 31.0, 1), ("World", 36.0, 1), ("Hello\nWorld", 36.0, 2), ("Above", 38.5, 1), ("Hello\n", 31.0, 2)] {
            entries[RecordedTextEngine.key(font: Self.system13, width: nil, string: word)] = .init(width: width, height: 16 * Double(lines), firstBaseline: 13, lastBaseline: 13 + 16 * Double(lines - 1))
        }
        let runtime = Runtime()
        runtime.textEngine = RecordedTextEngine(entries: entries)
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime
    }

    private func commands(_ r: Runtime) -> [String] { r.render(scale: 2).commands.map(\.description) }

    @Test func sizingAndText() {
        let r = runtime(VStack(spacing: 8) {
            Text("Above")._probe("above")
            TextEditor(text: .constant("Hello\nWorld"))._probe("fill")
            TextEditor(text: .constant("Hello")).frame(width: 160, height: 40)._probe("narrow")
        })
        // The editor fills what is left at the stack's default 8 pt spacing (not the text's 8.15).
        #expect(r.probeFrames["fill"] == CGRect(x: 0, y: 24, width: 320, height: 128))
        #expect(r.probeFrames["narrow"]?.size == CGSize(width: 160, height: 40))
        let painted = commands(r)
        // White background; the text 5 pt in, the first baseline at the cap height (9.16), the
        // second line 12 pt lower, in black.
        #expect(painted.contains { $0.hasPrefix("fillRect(0, 24, 320, 128) #FFFFFF") })
        let node = r.root.descendants(where: { $0 is TextEditorNode }).first as! TextEditorNode
        #expect(node.linePitch == 12 && node.textRect == CGRect(x: 5, y: 0, width: 310, height: 128))
        #expect(abs(node.firstBaseline - 9.16) < 0.01)
        // (The recorded engine lays the whole string out as one fragment; the real engines wrap
        // and break at newlines, each line a pitch lower.)
        #expect(painted.contains { $0.hasPrefix("drawText(\"Hello\nWorld\"") && $0.contains(" at 5,\(24 + node.firstBaseline) ") && $0.contains("#000000") })
    }

    @Test func stylesAndSpacing() {
        let r = runtime(VStack(spacing: 8) {
            TextEditor(text: .constant("Hello")).scrollContentBackground(.hidden).frame(height: 40)._probe("hidden")
            TextEditor(text: .constant("Hello")).textEditorStyle(.plain).frame(height: 40)._probe("plain")
            TextEditor(text: .constant("Hello\nWorld")).lineSpacing(10).foregroundColor(.red).frame(height: 60)._probe("spaced")
        })
        let painted = commands(r)
        // Only the third editor paints its background; the spaced one's second line is 22 lower, in red.
        #expect(painted.filter { $0.hasPrefix("fillRect") && $0.contains("#FFFFFF") }.count == 1)
        let spacedY = r.probeFrames["spaced"]!.minY
        let spaced = r.root.descendants(where: { $0 is TextEditorNode }).last as! TextEditorNode
        #expect(spaced.linePitch == 22)
        #expect(painted.contains { $0.hasPrefix("drawText(\"Hello\nWorld\"") && $0.contains(" at 5,\(spacedY + spaced.firstBaseline) ") && $0.contains("#FF383C") })
    }

    @Test func focusAndInput() {
        let box = _EditorTextBox("Hello")
        let r = runtime(TextEditor(text: Binding(get: { box.text }, set: { box.text = $0 }))._probe("editor"))
        let editor = r.semanticsTree().first { $0.role == .textField }!
        #expect(editor.textInput?.isMultiline == true && editor.textInput?.lineHeight == 12)
        // A press focuses the editor; the host's input changes and submits flow into the binding.
        r.pointerDown(at: CGPoint(x: 100, y: 50)); r.pointerUp(at: CGPoint(x: 100, y: 50))
        #expect(r.focusedTextFieldIdentifier == editor.identifier)
        r.textField(editor.identifier, didChange: "Hello there")
        #expect(box.text == "Hello there")
        r.textFieldDidSubmit(editor.identifier)
        #expect(box.text == "Hello there\n")
    }

    @Observable @MainActor final class SelectionBox { var text = "Hello world"; var selection: TextSelection? }

    /// sw-texteditor: the selection binding follows the host's selection and sets it; a long
    /// text scrolls by the wheel (unfocused) and follows the host's textarea (focused); the
    /// find navigator highlights its matches, steps through them, replaces, and `findDisabled`
    /// keeps it away; `lineLimit` on an editor changes nothing (measured on macOS 27).
    @Test func selectionScrollingAndFinding() {
        let box = SelectionBox()
        let r = Runtime()
        r.textEngine = MonospaceTextEngine()
        r.mount(TextEditor(text: Binding(get: { box.text }, set: { box.text = $0 }), selection: Binding(get: { box.selection }, set: { box.selection = $0 }))
            .frame(width: 200, height: 60)._probe("editor"))
        r.layout(in: CGSize(width: 320, height: 200))
        let editor = r.semanticsTree().first { $0.role == .textField }!
        // The host reports a selection: the binding takes it (UTF-16 offsets → indices).
        r.textField(editor.identifier, selectionStart: 6, end: 11)
        #expect(box.selection?.range.map { String(box.text[$0]) } == "world")
        // The binding sets one: the semantics carry it to the host once.
        box.selection = TextSelection(range: box.text.startIndex..<box.text.index(box.text.startIndex, offsetBy: 5))
        r.layout(in: CGSize(width: 320, height: 200))
        let info = r.semanticsTree().first { $0.role == .textField }!.textInput!
        #expect(info.selection == TextRange(start: 0, end: 5), "\(info.selection as Any)")
        #expect(TextSelection(insertionPoint: box.text.startIndex).isInsertion && !TextSelection(range: box.text.startIndex..<box.text.endIndex).isInsertion)

        // Long content: twenty lines at a 12 pt pitch in a 60 pt frame scroll by the wheel.
        let long = _EditorTextBox((1...20).map { "Line \($0)" }.joined(separator: "\n"))
        let s = Runtime()
        s.textEngine = MonospaceTextEngine()
        s.mount(TextEditor(text: Binding(get: { long.text }, set: { long.text = $0 })).frame(width: 200, height: 60)._probe("editor"))
        s.layout(in: CGSize(width: 320, height: 200))
        let frame = s.probeFrames["editor"]!
        func firstLineY() -> CGFloat? {
            let commands = s.render(scale: 1).commands.map(\.description)
            guard let first = commands.first(where: { $0.hasPrefix("drawText(\"Line 1\"") }) else { return nil }
            let parts = first.split(separator: " ")
            return CGFloat(Double(parts[parts.firstIndex(of: "at")! + 1].split(separator: ",")[1]) ?? 0)
        }
        let before = firstLineY()!
        s.scrollWheel(by: CGSize(width: 0, height: 24), at: CGPoint(x: frame.midX, y: frame.midY))
        #expect(firstLineY() == before - 24)
        // Past the end it stops: 20 lines × 12 + the insets in 60 pt.
        s.scrollWheel(by: CGSize(width: 0, height: 10_000), at: CGPoint(x: frame.midX, y: frame.midY))
        let editorNode = s.semanticsTree().first { $0.role == .textField }!
        let offset = editorNode.textInput!.scrollOffset
        #expect(offset > 100 && offset < 240, "\(offset)")
        // The host's textarea scrolled back to the top: the painted text follows.
        s.textField(editorNode.identifier, scrolledTo: 0)
        #expect(firstLineY() == before)

        // The find navigator: matches of the query, case-insensitive, highlighted; Done hides it.
        let findBox = _EditorTextBox("Find me here, find me there")
        @MainActor final class Presented { var shown = true }
        let presented = Presented()
        let f = Runtime()
        f.textEngine = MonospaceTextEngine()
        f.mount(TextEditor(text: Binding(get: { findBox.text }, set: { findBox.text = $0 }))
            .findNavigator(isPresented: Binding(get: { presented.shown }, set: { presented.shown = $0 }))
            .frame(width: 300, height: 100)._probe("editor"))
        f.layout(in: CGSize(width: 320, height: 200))
        let field = f.semanticsTree().first { $0.role == .textField && $0.textInput?.isMultiline == false }!
        f.textField(field.identifier, didChange: "find")
        f.layout(in: CGSize(width: 320, height: 200))
        let highlights = f.render(scale: 1).commands.map(\.description).filter { $0.hasPrefix("fillRRect") && $0.contains("#FF") && !$0.contains("#FFFFFF") }
        #expect(highlights.count == 2, "\(highlights)")
        #expect(_FindBar.matches(of: "ME", in: findBox.text).count == 2 && _FindBar.matches(of: "", in: findBox.text).isEmpty && _FindBar.matches(of: "zz", in: findBox.text).isEmpty)
        // The editor's text starts under the 32 pt bar.
        let editorInfo = f.semanticsTree().first { $0.role == .textField && $0.textInput?.isMultiline == true }!.textInput!
        #expect(editorInfo.textRect.minY == f.probeFrames["editor"]!.minY + 32)
        // Done hides the bar: the text rect moves back up.
        let done = f.semanticsTree().first { $0.label == "Done" }!
        f.activate(semanticsIdentifier: done.identifier)
        f.layout(in: CGSize(width: 320, height: 200))
        #expect(!presented.shown)
        // findDisabled keeps the navigator away; lineLimit changes nothing.
        let d = Runtime()
        d.textEngine = MonospaceTextEngine()
        d.mount(TextEditor(text: .constant("One\nTwo\nThree\nFour")).lineLimit(2).findNavigator(isPresented: .constant(true)).findDisabled()
            .frame(width: 300, height: 100)._probe("editor"))
        d.layout(in: CGSize(width: 320, height: 200))
        let lines = d.render(scale: 1).commands.map(\.description).filter { $0.hasPrefix("drawText") }
        #expect(lines.count == 4 && d.semanticsTree().filter { $0.role == .textField }.count == 1, "\(lines)")
    }
}

@MainActor final class _EditorTextBox { var text: String; init(_ text: String) { self.text = text } }
#endif
