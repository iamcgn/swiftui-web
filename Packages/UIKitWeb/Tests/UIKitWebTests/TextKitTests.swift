// TextKit 1 (Controls/TextKit.swift): a text view's text storage, layout manager and container
// (glyph and line rectangles, the character under a point, edits to the storage showing in the
// view), a stand-alone storage, layout manager and container laid out at the container's size,
// and the text view's `UITextInput` (positions, the caret, typing and deleting). Laid out with
// the synthetic engine on every platform, so a 17 pt character is 8.5 points wide and a line
// 20.5 points tall.
import Testing
import UIKit
@testable import UIKitWebCore
import WebGraphics

@Suite(.serialized) @MainActor struct TextKitTests {
    private func window() -> UIViewController {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = SyntheticTextEngine()
        scene.configureScreen(size: CGSize(width: 320, height: 500), scale: 2)
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        window.rootViewController = root
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 500))
        return root
    }

    private func textView(_ text: String, width: CGFloat) -> UITextView {
        let root = window()
        let view = UITextView(frame: CGRect(x: 0, y: 0, width: width, height: 300))
        view.font = .systemFont(ofSize: 17)
        view.text = text
        root.view.addSubview(view)
        UIKitScene.shared.layout(in: CGSize(width: 320, height: 500))
        return view
    }

    @Test func aTextViewsLayoutManagerAnswersForItsGlyphs() {
        let view = textView("Hello world", width: 200)
        let manager = view.layoutManager
        let container = view.textContainer
        #expect(view.textStorage.string == "Hello world")
        #expect(manager.textStorage === view.textStorage)
        #expect(manager.textContainers.first === container)
        #expect(container.layoutManager === manager)
        #expect(container.size.width == 200)
        manager.ensureLayout(for: container)
        #expect(manager.numberOfGlyphs == 11)
        #expect(manager.glyphRange(forCharacterRange: NSRange(location: 6, length: 5), actualCharacterRange: nil) == NSRange(location: 6, length: 5))
        #expect(manager.glyphIndexForCharacter(at: 4) == 4)
        #expect(manager.glyphRange(for: container) == NSRange(location: 0, length: 11))

        // "w" starts after "Hello " (51) and the 5 pt padding.
        #expect(manager.boundingRect(forGlyphRange: NSRange(location: 6, length: 1), in: container) == CGRect(x: 56, y: 0, width: 8.5, height: 20.5))
        var lineRange = NSRange(location: 0, length: 0)
        #expect(manager.lineFragmentRect(forGlyphAt: 3, effectiveRange: &lineRange) == CGRect(x: 0, y: 0, width: 200, height: 20.5))
        #expect(lineRange == NSRange(location: 0, length: 11))
        // The used part: the text's 93.5 and the padding either side.
        #expect(manager.lineFragmentUsedRect(forGlyphAt: 3, effectiveRange: nil) == CGRect(x: 0, y: 0, width: 103.5, height: 20.5))
        #expect(manager.usedRect(for: container) == CGRect(x: 0, y: 0, width: 103.5, height: 20.5))
        #expect(manager.location(forGlyphAt: 6) == CGPoint(x: 56, y: 16.5))

        // The character under a point, and how far across it.
        var fraction: CGFloat = -1
        #expect(manager.characterIndex(for: CGPoint(x: 60, y: 10), in: container, fractionOfDistanceBetweenInsertionPoints: &fraction) == 6)
        #expect(abs(fraction - 4 / 8.5) < 0.001)
        #expect(manager.characterIndex(for: CGPoint(x: 180, y: 10), in: container, fractionOfDistanceBetweenInsertionPoints: &fraction) == 10)
        #expect(fraction == 1)
        #expect(manager.characterIndex(for: CGPoint(x: -4, y: 90), in: container, fractionOfDistanceBetweenInsertionPoints: nil) == 0)
    }

    @Test func wrappedLinesOwnTheirTrailingSpace() {
        // 90 points inside the padding: "aaaa bbbb " fits, "cccc" wraps.
        let view = textView("aaaa bbbb cccc", width: 100)
        let manager = view.layoutManager
        let container = view.textContainer
        var lineRange = NSRange(location: 0, length: 0)
        #expect(manager.lineFragmentRect(forGlyphAt: 12, effectiveRange: &lineRange) == CGRect(x: 0, y: 20.5, width: 100, height: 20.5))
        #expect(lineRange == NSRange(location: 10, length: 4))
        var fragments: [NSRange] = []
        var rects: [CGRect] = []
        manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: 14)) { rect, _, fragmentContainer, range, _ in
            fragments.append(range)
            rects.append(rect)
            #expect(fragmentContainer === container)
        }
        #expect(fragments == [NSRange(location: 0, length: 10), NSRange(location: 10, length: 4)])
        #expect(rects.map(\.minY) == [0, 20.5])
        // Across both lines: from "a" at 30.5 on the first to the end of "cc" on the second.
        #expect(manager.boundingRect(forGlyphRange: NSRange(location: 3, length: 9), in: container) == CGRect(x: 5, y: 0, width: 85, height: 41))
        let lineCharacters = manager.characterRange(forGlyphRange: lineRange, actualGlyphRange: nil)
        #expect(lineCharacters == NSRange(location: 10, length: 4))
        #expect(manager.characterIndex(for: CGPoint(x: 7, y: 30), in: container, fractionOfDistanceBetweenInsertionPoints: nil) == 10)
        // The caret at the second line's start, in the view under the 8 pt inset.
        #expect(view.caretRect(for: UITextPosition(offset: 10)) == CGRect(x: 5, y: 28.5, width: 2, height: 20.5))
        #expect(view.firstRect(for: UITextRange(start: UITextPosition(offset: 5), end: UITextPosition(offset: 12)))
                == CGRect(x: 47.5, y: 8, width: 42.5, height: 20.5))
    }

    @Test func storageEditsShowInTheView() {
        let view = textView("Hello world", width: 200)
        let listener = StorageListener()
        let storage = view.textStorage
        storage.delegate = listener
        storage.beginEditing()
        storage.addAttribute(.foregroundColor, value: UIColor.red, range: NSRange(location: 0, length: 5))
        storage.addAttribute(.foregroundColor, value: UIColor.blue, range: NSRange(location: 6, length: 5))
        #expect(listener.processed.isEmpty)
        storage.endEditing()
        // One edit, both ranges.
        #expect(listener.processed.count == 1)
        #expect(listener.processed.first?.mask == .editedAttributes)
        #expect(listener.processed.first?.range == NSRange(location: 0, length: 11))
        #expect((view.attributedText.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor)?.rgba(for: .light) == UIColor.red.rgba(for: .light))
        UIKitScene.shared.layout(in: CGSize(width: 320, height: 500))
        let colours = UIKitScene.shared.render(scale: 2, background: false).commands.compactMap { command -> (String, RGBA)? in
            if case .drawText(let text, _, _, let colour) = command { return (text, colour) }
            return nil
        }
        #expect(colours.first { $0.0 == "Hello" }?.1 == UIColor.red.rgba(for: .light))
        #expect(colours.first { $0.0 == "world" }?.1 == UIColor.blue.rgba(for: .light))

        storage.replaceCharacters(in: NSRange(location: 0, length: 5), with: "Howdy")
        #expect(view.text == "Howdy world")
        #expect(listener.processed.last?.mask == .editedCharacters)
        #expect(listener.processed.last?.delta == 0)
        storage.replaceCharacters(in: NSRange(location: 5, length: 6), with: "")
        #expect(view.text == "Howdy")
        #expect(view.layoutManager.numberOfGlyphs == 5)

        // The view's text fills the storage.
        view.text = "New text"
        #expect(view.textStorage.string == "New text")
        #expect(view.layoutManager.numberOfGlyphs == 8)
    }

    @Test func aStandAloneLayoutManagerLaysOutInItsContainer() {
        _ = window()
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: .zero)
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        container.maximumNumberOfLines = 0
        manager.addTextContainer(container)
        let storage = NSTextStorage(attributedString: NSAttributedString(string: "Tap here please", attributes: [.font: UIFont.systemFont(ofSize: 17)]))
        storage.addLayoutManager(manager)
        #expect(storage.layoutManagers.count == 1)
        #expect(manager.textStorage === storage)
        // A zero size leaves the text on one line; "h" starts after "Tap ".
        #expect(manager.characterIndex(for: CGPoint(x: 35, y: 5), in: container, fractionOfDistanceBetweenInsertionPoints: nil) == 4)
        #expect(manager.usedRect(for: container).height == 20.5)
        // 60 points wide: "Tap " / "here " / "please".
        container.size = CGSize(width: 60, height: 100)
        #expect(manager.characterIndex(for: CGPoint(x: 2, y: 25), in: container, fractionOfDistanceBetweenInsertionPoints: nil) == 4)
        #expect(manager.characterIndex(for: CGPoint(x: 9, y: 45), in: container, fractionOfDistanceBetweenInsertionPoints: nil) == 10)
        #expect(manager.usedRect(for: container) == CGRect(x: 0, y: 0, width: 51, height: 61.5))
        var lineRange = NSRange(location: 0, length: 0)
        _ = manager.lineFragmentRect(forGlyphAt: 6, effectiveRange: &lineRange)
        #expect(lineRange == NSRange(location: 4, length: 5))
        // An edit lays the lines out again.
        storage.replaceCharacters(in: NSRange(location: 0, length: 4), with: "")
        #expect(manager.numberOfGlyphs == 11)
        _ = manager.lineFragmentRect(forGlyphAt: 0, effectiveRange: &lineRange)
        #expect(lineRange == NSRange(location: 0, length: 5))
        storage.removeLayoutManager(manager)
        #expect(manager.textStorage == nil)
        #expect(manager.numberOfGlyphs == 0)
    }

    @Test func aTextViewIsATextInput() {
        let view = CaretView(frame: CGRect(x: 0, y: 0, width: 200, height: 300))
        let root = window()
        view.font = .systemFont(ofSize: 17)
        view.text = "Hello"
        root.view.addSubview(view)
        let listener = ChangeListener()
        view.delegate = listener
        let input: any UITextInput = view
        #expect(input.hasText)
        #expect(input.endOfDocument.offset == 5)
        guard let start = input.position(from: input.beginningOfDocument, offset: 1), let end = input.position(from: start, offset: 3),
              let range = input.textRange(from: start, to: end) else { Issue.record("no range"); return }
        #expect(input.text(in: range) == "ell")
        input.selectedTextRange = range
        #expect(view.selectedRange == NSRange(location: 1, length: 3))
        input.insertText("ipp")
        #expect(view.text == "Hippo")
        #expect(view.selectedRange == NSRange(location: 4, length: 0))
        input.deleteBackward()
        #expect(view.text == "Hipo")
        view.text = "Hi👋"
        view.selectedRange = NSRange(location: 4, length: 0)
        input.deleteBackward()
        #expect(view.text == "Hi")
        input.replace(UITextRange(start: UITextPosition(offset: 0), end: UITextPosition(offset: 2)), withText: "Bye")
        #expect(view.text == "Bye")
        #expect(listener.changed == 4)
        // The caret sits after the glyphs before it; a subclass's caret replaces it.
        #expect(view.caretRect(for: UITextPosition(offset: 1)) == CGRect(x: 13.5, y: 8, width: 2, height: 20.5))
        view.overrideCaret = CGRect(x: 1, y: 2, width: 3, height: 4)
        #expect(input.caretRect(for: UITextPosition(offset: 1)) == CGRect(x: 1, y: 2, width: 3, height: 4))
        // The insertion point nearest a point: past a character's middle, after it.
        #expect(view.closestPosition(to: CGPoint(x: 15, y: 15))?.offset == 1)
        #expect(view.closestPosition(to: CGPoint(x: 20, y: 15))?.offset == 2)
    }
}

/// A text view whose caret an app sets, as a keyboard prototype's does.
private final class CaretView: UITextView {
    var overrideCaret: CGRect?
    override func caretRect(for position: UITextPosition) -> CGRect { overrideCaret ?? super.caretRect(for: position) }
}

private final class StorageListener: NSTextStorageDelegate {
    var processed: [(mask: NSTextStorage.EditActions, range: NSRange, delta: Int)] = []
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions, range editedRange: NSRange, changeInLength delta: Int) {
        processed.append((editedMask, editedRange, delta))
    }
}

@MainActor
private final class ChangeListener: UITextViewDelegate {
    var changed = 0
    func textViewDidChange(_ textView: UITextView) { changed += 1 }
}
