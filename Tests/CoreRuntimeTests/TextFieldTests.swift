// TextField / SecureField (Phase 2): geometry, painting of bezel, text, placeholder and
// bullets, styles, the host entry points (text change, submit, focus) and the semantics node
// a host builds its input element from. Layout against goldens is in GoldenFrameTests.
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebHeadless

#if !os(WASI)
@Suite @MainActor struct TextFieldTests {
    static let system13 = ResolvedFont(family: "system", size: 13, weight: .regular, italic: false, textStyle: nil)

    private func engine() -> RecordedTextEngine {
        RecordedTextEngine(entries: [
            RecordedTextEngine.key(font: Self.system13, width: nil, string: "Hello"): .init(width: 31, height: 16, firstBaseline: 13, lastBaseline: 13),
            RecordedTextEngine.key(font: Self.system13, width: nil, string: "Placeholder"): .init(width: 69.5, height: 16, firstBaseline: 13, lastBaseline: 13),
            RecordedTextEngine.key(font: Self.system13, width: nil, string: "Name"): .init(width: 35.5, height: 16, firstBaseline: 13, lastBaseline: 13),
        ])
    }

    private func runtime<V: View>(_ view: V, size: CGSize = CGSize(width: 200, height: 100)) -> Runtime {
        let runtime = Runtime()
        runtime.textEngine = engine()
        runtime.mount(view)
        runtime.layout(in: size)
        return runtime
    }

    @Test func roundedFieldGeometryAndPainting() {
        let r = runtime(TextField("Placeholder", text: .constant("Hello"))._probe("field"))
        #expect(r.probeFrames["field"] == CGRect(x: 0, y: 38, width: 200, height: 24))
        let commands = r.render(scale: 2).commands.map(\.description)
        #expect(commands == [
            "fillRRect(-1, 37, 202, 26) r=6 #000000@\(23.0 / 255)",
            "fillRRect(0, 38, 200, 24) r=5 #FFFFFF",
            "save", "clipRect(6, 42, 188, 16)",
            "drawText(\"Hello\" system 13 w400 at 6,55 #000000@0.85)",
            "restore",
        ])
        // Empty: the placeholder in the secondary colour; frames unchanged.
        let empty = runtime(TextField("Placeholder", text: .constant(""))._probe("field"))
        #expect(empty.probeFrames["field"]?.height == 24)
        #expect(empty.render(scale: 2).commands.map(\.description)[2] == "drawText(\"Placeholder\" system 13 w400 at 6,55 #000000@0.5)")
        // The text line sits on the button baseline (17): a label aligns on it.
        let row = runtime(HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Name")._probe("label")
            TextField("Placeholder", text: .constant("Hello"))._probe("field")
        })
        #expect(row.probeFrames["label"] == CGRect(x: 0, y: 42, width: 35.5, height: 16))
        #expect(row.probeFrames["field"] == CGRect(x: 43.5, y: 38, width: 156.5, height: 24))
    }

    @Test func stylesSecureAndDisabled() {
        let plain = runtime(TextField("Placeholder", text: .constant("Hello")).textFieldStyle(.plain)._probe("field"))
        #expect(plain.probeFrames["field"] == CGRect(x: 0, y: 42, width: 200, height: 16))
        #expect(plain.render(scale: 2).commands.map(\.description) == ["save", "clipRect(0, 42, 200, 16)", "drawText(\"Hello\" system 13 w400 at 0,55 #000000@0.85)", "restore"])
        let square = runtime(TextField("Placeholder", text: .constant("Hello")).textFieldStyle(.squareBorder)._probe("field"))
        #expect(square.probeFrames["field"]?.height == 24)
        // Secure: one 5.5 pt bullet per character at an 8 pt pitch, none for the placeholder.
        let secure = runtime(SecureField("Password", text: .constant("Hello")))
        let bullets = secure.render(scale: 2).commands.filter { if case .fillPath = $0 { return true } else { return false } }
        #expect(bullets.count == 5)
        if case .fillPath(let first, _, _) = bullets[0] { #expect(first.boundingRect == CGRect(x: 7.5, y: 47.25, width: 5.5, height: 5.5)) }
        if case .fillPath(let second, _, _) = bullets[1] { #expect(second.boundingRect.minX == 15.5) }
        // Disabled: a translucent fill and dimmed text; no focus on press.
        let disabled = runtime(TextField("Placeholder", text: .constant("Hello")).disabled(true))
        let list = disabled.render(scale: 2).commands.map(\.description)
        #expect(list[1] == "fillRRect(0, 38, 200, 24) r=5 #FFFFFF@\(192.0 / 255)")
        #expect(list[4].hasSuffix("#000000@0.255)"))
        disabled.pointerDown(at: CGPoint(x: 50, y: 50)); disabled.pointerUp(at: CGPoint(x: 50, y: 50))
        #expect(disabled.focusedTextFieldIdentifier == nil)
        // Ideal width fits the longer of text and placeholder plus the insets.
        let ideal = runtime(TextField("Placeholder", text: .constant("Hello")).fixedSize()._probe("field"))
        #expect(ideal.probeFrames["field"]?.size == CGSize(width: 81.5, height: 24))
    }

    @Test func hostEntryPoints() {
        let box = _TextBox("")
        let submitted = _TextBox("")
        let binding = Binding(get: { box.value }, set: { box.value = $0 })
        let r = runtime(TextField("Placeholder", text: binding).onSubmit { submitted.value += "!" })
        let node = r.semanticsTree()[0]
        #expect(node.role == .textField && node.label == "Placeholder")
        let info = try! #require(node.textInput)
        #expect(info.text == "" && info.placeholder == "Placeholder" && !info.isSecure && info.isEnabled)
        #expect(info.textRect == CGRect(x: 6, y: 42, width: 188, height: 16))
        #expect(info.font == DisplayFont(Self.system13))
        r.textField(node.identifier, didChange: "Hi")
        #expect(box.value == "Hi")
        r.textFieldDidSubmit(node.identifier)
        #expect(submitted.value == "!")
        // A press focuses the field; the host's blur clears it.
        r.pointerDown(at: CGPoint(x: 50, y: 50)); r.pointerUp(at: CGPoint(x: 50, y: 50))
        #expect(r.focusedTextFieldIdentifier == node.identifier)
        r.layout(in: CGSize(width: 200, height: 100))
        #expect(r.render(scale: 2).commands.contains { if case .strokePath = $0 { return true } else { return false } })
        r.textField(node.identifier, focused: false)
        #expect(r.focusedTextFieldIdentifier == nil)
        // A secure field's semantics carry the secure flag.
        let secure = runtime(SecureField("Password", text: .constant("x")))
        #expect(secure.semanticsTree()[0].textInput?.isSecure == true)
    }
}

private final class _TextBox: @unchecked Sendable {
    var value: String
    init(_ value: String) { self.value = value }
}
#endif
