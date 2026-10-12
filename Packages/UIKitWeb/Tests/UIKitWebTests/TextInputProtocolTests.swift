// UIKeyInput / UITextInput / UITextInteraction (uk-text-input): an app's own views take the
// host's text element; the host's whole-text reports arrive as inserts and deletes, or as
// replacements of the changed range with the selection following; a tap begins editing.
import Testing
@testable import UIKitWebCore
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// The simple form: a view that keeps a string.
final class KeyInputView: UIView, UIKeyInput {
    var text = ""
    var log: [String] = []
    var hasText: Bool { !text.isEmpty }
    func insertText(_ string: String) { text += string; log.append("insert \(string)") }
    func deleteBackward() { if !text.isEmpty { text.removeLast() }; log.append("delete") }
    override var canBecomeFirstResponder: Bool { true }
    var keyboardType: UIKeyboardType { .numberPad }
}

/// The full form: a document with a selection.
final class DocumentView: UIView, UITextInput {
    var document = "Hello"
    var selected = NSRange(location: 5, length: 0)
    var log: [String] = []
    var inputDelegate: (any UITextInputDelegate)?
    var hasText: Bool { !document.isEmpty }
    func insertText(_ text: String) { replace(selectedTextRange!, withText: text) }
    func deleteBackward() {
        guard selected.location > 0 || selected.length > 0 else { return }
        let range = selected.length > 0 ? selected : NSRange(location: selected.location - 1, length: 1)
        replace(UITextRange(start: UITextPosition(offset: range.location), end: UITextPosition(offset: range.location + range.length)), withText: "")
    }
    func text(in range: UITextRange) -> String? {
        let chars = Array(document)
        return String(chars[max(0, range.start.offset)..<min(chars.count, range.end.offset)])
    }
    func replace(_ range: UITextRange, withText text: String) {
        var chars = Array(document)
        chars.replaceSubrange(range.start.offset..<range.end.offset, with: Array(text))
        document = String(chars)
        selected = NSRange(location: range.start.offset + text.count, length: 0)
        log.append("replace \(range.start.offset)..<\(range.end.offset) with \(text)")
    }
    var selectedTextRange: UITextRange? {
        get { UITextRange(start: UITextPosition(offset: selected.location), end: UITextPosition(offset: selected.location + selected.length)) }
        set { selected = newValue.map { NSRange(location: $0.start.offset, length: $0.end.offset - $0.start.offset) } ?? NSRange(location: 0, length: 0) }
    }
    var beginningOfDocument: UITextPosition { UITextPosition(offset: 0) }
    var endOfDocument: UITextPosition { UITextPosition(offset: document.count) }
    func caretRect(for position: UITextPosition) -> CGRect { CGRect(x: CGFloat(position.offset) * 8, y: 0, width: 1, height: 20) }
    override var canBecomeFirstResponder: Bool { true }
}

@Suite @MainActor struct TextInputProtocolTests {
    @Test func keyInputAndTextInputTakeTheHostsText() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        let simple = KeyInputView(frame: CGRect(x: 10, y: 10, width: 200, height: 40))
        simple.addInteraction(UITextInteraction(for: .editable))
        let document = DocumentView(frame: CGRect(x: 10, y: 60, width: 200, height: 40))
        document.addInteraction(UITextInteraction(for: .editable))
        controller.view.addSubview(simple)
        controller.view.addSubview(document)
        scene.layout(in: CGSize(width: 320, height: 400))
        // Both appear as text fields with text elements over their bounds; the document's
        // element carries its text; the simple view's traits reach the element.
        let tree = scene.semanticsTree()
        let simpleNode = tree.first { $0.identifier == simple.semanticsIdentifier }!
        let documentNode = tree.first { $0.identifier == document.semanticsIdentifier }!
        #expect(simpleNode.role == .textField && simpleNode.textInput?.textRect == CGRect(x: 10, y: 10, width: 200, height: 40))
        #expect(simpleNode.textInput?.inputMode == UIKeyboardType.numberPad.inputMode && simpleNode.textInput?.paintsCaret == true)
        #expect(documentNode.textInput?.text == "Hello")
        // A tap begins editing (the interaction); the host focuses the element.
        scene.pointerDown(at: CGPoint(x: 50, y: 30), type: .mouse, time: 0)
        scene.pointerUp(at: CGPoint(x: 50, y: 30), time: 0.05)
        #expect(simple.isFirstResponder && scene.focusedTextFieldIdentifier == simple.semanticsIdentifier)
        // The host types: whole-text reports become inserts and deletes.
        scene.textField(simple.semanticsIdentifier, didChange: "12")
        scene.textField(simple.semanticsIdentifier, didChange: "123")
        scene.textField(simple.semanticsIdentifier, didChange: "1")
        #expect(simple.text == "1" && simple.log == ["insert 12", "insert 3", "delete", "delete"])
        scene.textFieldDidSubmit(simple.semanticsIdentifier)
        #expect(simple.text == "1\n")
        // The document: the changed range is replaced, the caret follows; the selection relays.
        scene.textField(document.semanticsIdentifier, focused: true)
        #expect(document.isFirstResponder)
        scene.textField(document.semanticsIdentifier, didChange: "Hello!")
        #expect(document.document == "Hello!" && document.log.last == "replace 5..<5 with !" && document.selected == NSRange(location: 6, length: 0))
        scene.textField(document.semanticsIdentifier, didChange: "Jello!")
        #expect(document.document == "Jello!" && document.log.last == "replace 0..<1 with J")
        scene.textField(document.semanticsIdentifier, didChange: "Jo!")
        #expect(document.document == "Jo!" && document.log.last == "replace 1..<4 with ", "the common suffix stays: \(document.log.last ?? "")")
        scene.textField(document.semanticsIdentifier, selectionStart: 0, end: 2)
        #expect(document.selected == NSRange(location: 0, length: 2))
        // The protocol's default helpers.
        #expect(document.offset(from: document.beginningOfDocument, to: document.endOfDocument) == 3)
        #expect(document.position(from: document.beginningOfDocument, offset: 9) == nil)
        #expect(document.compare(UITextPosition(offset: 1), to: UITextPosition(offset: 2)) == .orderedAscending)
        scene.removeAllWindows()
    }
}
