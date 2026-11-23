// UIKeyInput / UITextInput / UITextInteraction (uk-text-input): an app's own views take the
// host's text element; the host's whole-text reports arrive as inserts and deletes, or as
// replacements of the changed range with the selection following; a tap begins editing.
import Testing
@testable import UIKitWebCore
import WebFoundation

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

/// An app's own position and range types, as Runestone's `IndexedPosition` and `IndexedRange`.
final class IndexedPosition: UITextPosition {
    let index: Int
    init(index: Int) { self.index = index }
}

final class IndexedRange: UITextRange {
    let range: NSRange
    init(_ range: NSRange) { self.range = range }
    override var start: UITextPosition { IndexedPosition(index: range.location) }
    override var end: UITextPosition { IndexedPosition(index: range.location + range.length) }
    override var isEmpty: Bool { range.length == 0 }
}

/// A document that only knows its own position types (UTF-16 offsets).
final class IndexedDocumentView: UIView, UITextInput, UITextSearching {
    var document = "one two three two"
    var selected = NSRange(location: 0, length: 0)
    var decorations: [String] = []
    var inputDelegate: (any UITextInputDelegate)?
    var hasText: Bool { !document.isEmpty }
    private func index(_ position: UITextPosition) -> Int { (position as! IndexedPosition).index }
    private func nsRange(_ range: UITextRange) -> NSRange { (range as! IndexedRange).range }
    func insertText(_ text: String) { replace(IndexedRange(selected), withText: text) }
    func deleteBackward() {}
    func text(in range: UITextRange) -> String? { (document as NSString).substring(with: nsRange(range)) }
    func replace(_ range: UITextRange, withText text: String) {
        document = (document as NSString).replacingCharacters(in: nsRange(range), with: text)
        selected = NSRange(location: nsRange(range).location + text.utf16.count, length: 0)
    }
    var selectedTextRange: UITextRange? {
        get { IndexedRange(selected) }
        set { selected = newValue.map(nsRange) ?? NSRange(location: 0, length: 0) }
    }
    var beginningOfDocument: UITextPosition { IndexedPosition(index: 0) }
    var endOfDocument: UITextPosition { IndexedPosition(index: document.utf16.count) }
    func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        let a = index(fromPosition), b = index(toPosition)
        return IndexedRange(NSRange(location: min(a, b), length: abs(b - a)))
    }
    func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        let target = index(position) + offset
        return target >= 0 && target <= document.utf16.count ? IndexedPosition(index: target) : nil
    }
    func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int { index(toPosition) - index(from) }
    func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
        index(position) < index(other) ? .orderedAscending : index(position) > index(other) ? .orderedDescending : .orderedSame
    }
    func caretRect(for position: UITextPosition) -> CGRect { .zero }
    override var canBecomeFirstResponder: Bool { true }

    // UITextSearching
    func compare(_ foundRange: UITextRange, toRange: UITextRange, document: UITextSearchDocumentIdentifier?) -> ComparisonResult {
        compare(foundRange.start, to: toRange.start)
    }
    func performTextSearch(queryString: String, options: UITextSearchOptions, resultAggregator: any UITextSearchAggregator<AnyHashable?>) {
        let text = self.document as NSString
        var from = 0
        while true {
            let found = text.range(of: queryString, options: options.stringCompareOptions, range: NSRange(location: from, length: text.length - from))
            guard found.location != NSNotFound else { break }
            resultAggregator.foundRange(IndexedRange(found), searchString: queryString, document: nil)
            from = found.location + found.length
        }
        resultAggregator.finishedSearching()
    }
    func decorate(foundTextRange: UITextRange, document: UITextSearchDocumentIdentifier?, usingStyle style: UITextSearchFoundTextStyle) {
        decorations.append("\(nsRange(foundTextRange).location) \(style)")
    }
    func clearAllDecoratedFoundText() { decorations.append("clear") }
}

/// A recognizer that recognizes by setting its own state, and watches it.
final class SelfRecognizingTap: UITapGestureRecognizer {
    var seen: [UIGestureRecognizer.State] = []
    override var state: UIGestureRecognizer.State { didSet { seen.append(state) } }
}

/// Finds the document view for the find interaction.
final class FindDelegate: UIFindInteractionDelegate {
    let searchable: any UITextSearching
    var began = 0
    init(searchable: any UITextSearching) { self.searchable = searchable }
    func findInteraction(_ interaction: UIFindInteraction, sessionFor view: UIView) -> UIFindSession? {
        UITextSearchingFindSession(searchableObject: searchable)
    }
    func findInteraction(_ interaction: UIFindInteraction, didBegin session: UIFindSession) { began += 1 }
}

@Suite @MainActor struct TextInputProtocolTests {
    @Test func anInputWithItsOwnPositionTypesTakesTheHostsTextAndSearches() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        let view = IndexedDocumentView(frame: CGRect(x: 10, y: 10, width: 200, height: 40))
        controller.view.addSubview(view)
        scene.layout(in: CGSize(width: 320, height: 400))
        // The host's text and selection reach it as its own ranges.
        scene.textField(view.semanticsIdentifier, focused: true)
        scene.textField(view.semanticsIdentifier, didChange: "one two three two!")
        #expect(view.document == "one two three two!" && view.selected == NSRange(location: 18, length: 0))
        scene.textField(view.semanticsIdentifier, selectionStart: 4, end: 7)
        #expect(view.selected == NSRange(location: 4, length: 3) && view.selectedRange == NSRange(location: 4, length: 3))
        // The default string tokenizer finds words in its offsets.
        let tokenizer = view.tokenizer
        let word = tokenizer.rangeEnclosingPosition(IndexedPosition(index: 5), with: .word, inDirection: .storage(.forward)) as? IndexedRange
        #expect(word?.range == NSRange(location: 4, length: 3))
        let next = tokenizer.position(from: IndexedPosition(index: 5), toBoundary: .word, inDirection: UITextDirection(rawValue: UITextStorageDirection.forward.rawValue)) as? IndexedPosition
        #expect(next?.index == 7)
        #expect(tokenizer.isPosition(IndexedPosition(index: 4), atBoundary: .word, inDirection: .storage(.backward)))
        // A find session collects, decorates and steps through the results.
        let delegate = FindDelegate(searchable: view)
        let find = UIFindInteraction(sessionDelegate: delegate)
        view.addInteraction(find)
        find.presentFindNavigator(showingReplace: false)
        #expect(find.isFindNavigatorVisible && delegate.began == 1)
        find.searchText = "two"
        #expect(find.activeFindSession?.resultCount == 2)
        #expect(view.decorations == ["clear", "4 found", "14 found", "4 highlighted"])
        find.findNext()
        #expect(find.activeFindSession?.highlightedResultIndex == 1 && view.decorations.suffix(2) == ["4 found", "14 highlighted"])
        find.dismissFindNavigator()
        #expect(!find.isFindNavigatorVisible)
        // Equal ranges of the app's own type compare by identity, as NSObjects do.
        #expect(IndexedRange(NSRange(location: 1, length: 1)) != IndexedRange(NSRange(location: 1, length: 1)))
        #expect(UITextRange(start: UITextPosition(offset: 1), end: UITextPosition(offset: 2)) == UITextRange(start: UITextPosition(offset: 1), end: UITextPosition(offset: 2)))
        scene.removeAllWindows()
    }

    @Test func aRecognizerSubclassSetsAndObservesItsState() {
        var fired = 0
        let tap = SelfRecognizingTap { _ in fired += 1 }
        tap.state = .ended
        // The app's transition runs the handler and resets, and the observer saw both. The reset
        // runs inside the app's own assignment, so the observer on that assignment also sees
        // the reset state once more when it returns.
        #expect(fired == 1 && tap.seen.filter { $0 == .ended }.count == 1)
        #expect(tap.seen.first == .ended && tap.seen.last == .possible && tap.state == .possible)
    }

    @Test func keysHaveHIDUsagesAndTheMenuControllerKeepsItsState() {
        #expect(UIKey(characters: "", modifierFlags: [], key: .upArrow).keyCode == .keyboardUpArrow)
        #expect(UIKey(characters: "c", modifierFlags: .command).keyCode == .keyboardC)
        #expect(UIKey(characters: "0", modifierFlags: []).keyCode == .keyboard0)
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        UIMenuController.shared.menuItems = [UIMenuItem(title: "Replace", action: Selector("replace"))]
        UIMenuController.shared.showMenu(from: view, rect: CGRect(x: 1, y: 2, width: 3, height: 4))
        #expect(UIMenuController.shared.isMenuVisible)
        UIMenuController.shared.hideMenu(from: view)
        #expect(!UIMenuController.shared.isMenuVisible && UIMenuController.shared.menuItems?.first?.title == "Replace")
        let style = NSMutableParagraphStyle()
        style.tabStops = [NSTextTab(textAlignment: .left, location: 40)]
        style.defaultTabInterval = 40
        #expect(style.tabStops.map(\.location) == [40] && style.defaultTabInterval == 40 && style.baseWritingDirection == .natural)
    }

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
