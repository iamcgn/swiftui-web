// The native host without a window: text input into the focused text field through the
// NSTextInputClient path, and the accessibility elements built from the semantics tree.
#if canImport(AppKit)
import AppKit
import Testing
import SwiftUI
import SwiftUIWebCore
import SwiftUIWebNative

@Suite @MainActor struct NativeHostTests {
    final class Model: @unchecked Sendable {
        var name = ""
        var submitted = 0
        var pressed = 0
        var on = false
    }

    private func host(_ model: Model) -> NativeHost {
        let host = NativeHost(size: CGSize(width: 320, height: 200)) {
            AnyView(VStack(spacing: 12) {
                TextField("Name", text: Binding(get: { model.name }, set: { model.name = $0 }))
                    .onSubmit { model.submitted += 1 }
                Button("Go") { model.pressed += 1 }
                Toggle("Dark", isOn: Binding(get: { model.on }, set: { model.on = $0 }))
            })
        }
        host.makeView()
        host.runtime.layout(in: CGSize(width: 320, height: 200))
        return host
    }

    @Test func typingEditsTheFocusedTextField() {
        let model = Model()
        let h = host(model)
        let field = h.runtime.semanticsTree().first { $0.role == .textField }!
        // Nothing is typed without focus.
        h.view.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(model.name == "")
        h.runtime.focus(semanticsIdentifier: field.identifier)
        h.view.insertText("ab", replacementRange: NSRange(location: NSNotFound, length: 0))
        h.view.insertText(NSAttributedString(string: "c"), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(model.name == "abc")
        h.view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        #expect(model.name == "ab")
        h.view.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        #expect(model.submitted == 1)
        #expect(h.view.selectedRange() == NSRange(location: 2, length: 0))
        #expect(h.view.hasMarkedText() == false)
        // The runtime's semantics carry the text the caret follows.
        h.runtime.layout(in: CGSize(width: 320, height: 200))
        #expect(h.runtime.semanticsTree().first { $0.role == .textField }?.textInput?.text == "ab")
    }

    @Test func accessibilityElementsMirrorTheSemantics() {
        let model = Model()
        let h = host(model)
        let elements = h.view.accessibilityElements()
        #expect(elements.map { $0.accessibilityRole() } == [.textField, .button, .checkBox])
        #expect(elements.map { $0.accessibilityLabel() } == ["Name", "Go", "Dark"])
        #expect(elements[2].accessibilityValue() as? Int == 0)
        // Frames come from the layout (no window: in the view's coordinates).
        #expect(elements[1].accessibilityFrame().width > 0)
        // Pressing goes back to the runtime.
        #expect(elements[1].accessibilityPerformPress() && model.pressed == 1)
        #expect(elements[2].accessibilityPerformPress() && model.on == true)
        h.runtime.layout(in: CGSize(width: 320, height: 200))
        #expect(h.view.accessibilityElements()[2].accessibilityValue() as? Int == 1)
        #expect(h.view.accessibilityChildren()?.count == 3)
        #expect(h.view.isAccessibilityElement() == false)
    }
}
#endif
