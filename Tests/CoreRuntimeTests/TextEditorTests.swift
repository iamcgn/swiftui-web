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
}

@MainActor final class _EditorTextBox { var text: String; init(_ text: String) { self.text = text } }
#endif
