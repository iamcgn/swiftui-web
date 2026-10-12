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

// MARK: - pf-native-text (2026-10-12)

@Suite @MainActor struct NativeTextAndWindowTests {
    @Observable final class Model { var name = ""; var submitted = 0 }

    struct Fields: View {
        let model: Model
        var body: some View {
            VStack { TextField("Name", text: Bindable(model).name)._probe("field") }.padding()
        }
    }

    private func host(_ model: Model) -> NativeHost {
        let host = NativeHost(size: CGSize(width: 320, height: 200)) { AnyView(Fields(model: model)) }
        host.makeView()
        host.runtime.layout(in: CGSize(width: 320, height: 200))
        return host
    }

    @Test func selectionAwareEditingAndMarkedText() {
        let model = Model()
        let h = host(model)
        let field = h.runtime.semanticsTree().first { $0.role == .textField }!
        h.runtime.focus(semanticsIdentifier: field.identifier)
        h.view.insertText("hello world", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(model.name == "hello world" && h.view.selectedRange() == NSRange(location: 11, length: 0))
        // The caret moves, the selection extends, typing replaces it.
        h.view.doCommand(by: #selector(NSResponder.moveToBeginningOfLine(_:)))
        #expect(h.view.selectedRange() == NSRange(location: 0, length: 0))
        for _ in 0..<5 { h.view.doCommand(by: #selector(NSResponder.moveRightAndModifySelection(_:))) }
        #expect(h.view.selectedRange() == NSRange(location: 0, length: 5))
        h.view.insertText("goodbye", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(model.name == "goodbye world" && h.view.selectedRange() == NSRange(location: 7, length: 0))
        h.view.doCommand(by: #selector(NSResponder.deleteBackward(_:)))
        #expect(model.name == "goodby world")
        h.view.doCommand(by: #selector(NSResponder.selectAll(_:)))
        #expect(h.view.selectedRange() == NSRange(location: 0, length: 12))
        h.view.doCommand(by: #selector(NSResponder.moveToEndOfLine(_:)))
        // An input method composes: the marked text sits in the text, underlined by the scene,
        // and its commit replaces it.
        h.view.setMarkedText("にほ", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(model.name == "goodby worldにほ" && h.view.hasMarkedText() && h.view.markedRange() == NSRange(location: 12, length: 2))
        #expect(h.view.selectedRange() == NSRange(location: 14, length: 0))
        h.runtime.layout(in: CGSize(width: 320, height: 200))
        let underline = h.runtime.render(scale: 2).commands.map(\.description).filter { $0.hasPrefix("fillRect") && $0.contains(", 1) ") }
        #expect(!underline.isEmpty, "the marked text is underlined: \(underline)")
        h.view.setMarkedText("にほん", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(model.name == "goodby worldにほん" && h.view.markedRange() == NSRange(location: 12, length: 3))
        h.view.insertText("日本", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(model.name == "goodby world日本" && !h.view.hasMarkedText() && h.view.selectedRange() == NSRange(location: 14, length: 0))
        // The candidate window asks where the caret is: a rectangle inside the field.
        let rect = h.view.firstRect(forCharacterRange: NSRange(location: 12, length: 0), actualRange: nil)
        #expect(rect.width == 1 && rect.height > 10)
        // A click places the caret by the text's advances (after "goodby ").
        let frame = h.runtime.probeFrames["field"]!
        let input = h.runtime.semanticsTree().first { $0.role == .textField }!.textInput!
        let x = input.textRect.minX + h.host.textEngine.advance(of: "goodby ", font: input.font)
        _ = frame
        h.view.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: x, y: 200 - input.textRect.midY), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!)
        #expect(h.view.selectedRange().location == 7, "\(h.view.selectedRange())")
    }

    struct WindowApp: App {
        var body: some Scene {
            WindowGroup { Text("Main") }
            Window("Inspector", id: "inspector") { Text("Inside")._probe("inside") }
        }
    }

    @Test func windowPresentationsOpenAsRealWindows() {
        let host = NativeHost(size: CGSize(width: 400, height: 300)) { AnyView(Text("Main")) }
        host.makeView()
        host.runtime.installWindows(WindowApp._windows())
        host.runtime.layout(in: CGSize(width: 400, height: 300))
        #expect(host.runtime.realWindowHost != nil)
        #expect(host.runtime.openWindow(id: "inspector", value: nil))
        host.runtime.layout(in: CGSize(width: 400, height: 300))
        let windows = host.runtime.hostedWindows()
        #expect(windows.count == 1 && windows[0].title == "Inspector" && host.realWindows?.openWindowIdentifiers.count == 1)
        // The main view paints no window card; the window's own list has the content.
        let main = host.runtime.render(scale: 2).commands.map(\.description)
        #expect(!main.contains { $0.hasPrefix("drawText(\"Inside\"") } && !main.contains { $0.hasPrefix("drawText(\"Inspector\"") })
        let own = host.runtime.render(hostedWindow: windows[0].id, scale: 2).commands.map(\.description)
        #expect(own.contains { $0.hasPrefix("drawText(\"Inside\"") }, "\(own)")
        // Resizing the window follows into the presentation; closing it dismisses the presentation.
        host.runtime.hostedWindow(windows[0].id, didResizeTo: CGSize(width: 300, height: 200))
        host.runtime.layout(in: CGSize(width: 400, height: 300))
        #expect(host.runtime.hostedWindows().first?.contentSize == CGSize(width: 300, height: 200))
        host.runtime.hostedWindowDidClose(windows[0].id)
        host.runtime.layout(in: CGSize(width: 400, height: 300))
        #expect(host.runtime.openWindowCount == 0 && host.realWindows?.openWindowIdentifiers.isEmpty == true)
    }
}
#endif
