// UIKeyInput, UITextInput and UITextInteraction (uk-text-input): an app's own view that conforms
// takes input through the host's overlay like a text field. The host relays its hidden input's
// whole text; the scene turns the difference into `insertText`/`deleteBackward` (UIKeyInput)
// or `replace(_:withText:)` on the selected range plus selection updates (UITextInput), from a
// shadow of the text the host last had. `UITextInteraction` makes a tap on the view begin
// editing (first responder), as UIKit's does.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// The simple text input: characters typed and deleted.
@preconcurrency @MainActor
public protocol UIKeyInput: UITextInputTraits {
    var hasText: Bool { get }
    func insertText(_ text: String)
    func deleteBackward()
}

/// The traits of a text input (every one optional; the host reads them for its element).
@preconcurrency @MainActor
public protocol UITextInputTraits: AnyObject {
    var keyboardType: UIKeyboardType { get }
    var returnKeyType: UIReturnKeyType { get }
    var isSecureTextEntry: Bool { get }
    var autocapitalizationType: UITextAutocapitalizationType { get }
    var autocorrectionType: UITextAutocorrectionType { get }
    var textContentType: UITextContentType? { get }
}

extension UITextInputTraits {
    public var keyboardType: UIKeyboardType { .default }
    public var returnKeyType: UIReturnKeyType { .default }
    public var isSecureTextEntry: Bool { false }
    public var autocapitalizationType: UITextAutocapitalizationType { .sentences }
    public var autocorrectionType: UITextAutocorrectionType { .default }
    public var textContentType: UITextContentType? { nil }
}

/// A position in a text input's document (an offset in its characters here).
@preconcurrency @MainActor
open class UITextPosition: Equatable {
    public let offset: Int
    public init(offset: Int) { self.offset = offset }
    nonisolated public static func == (lhs: UITextPosition, rhs: UITextPosition) -> Bool { lhs.offset == rhs.offset }
}

/// A range in a text input's document.
@preconcurrency @MainActor
open class UITextRange: Equatable {
    public let start: UITextPosition
    public let end: UITextPosition
    public init(start: UITextPosition, end: UITextPosition) {
        self.start = start
        self.end = end
    }
    public var isEmpty: Bool { start.offset == end.offset }
    nonisolated public static func == (lhs: UITextRange, rhs: UITextRange) -> Bool { lhs.start == rhs.start && lhs.end == rhs.end }
}

public enum UITextStorageDirection: Int, Sendable { case forward, backward }
public enum UITextLayoutDirection: Int, Sendable { case right = 2, left, up, down }
public enum UITextGranularity: Int, Sendable { case character, word, sentence, paragraph, line, document }

/// A selection rectangle (`selectionRects(for:)`).
@preconcurrency @MainActor
open class UITextSelectionRect {
    open var rect: CGRect { .zero }
    open var writingDirection: UITextWritingDirection { .natural }
    open var containsStart: Bool { false }
    open var containsEnd: Bool { false }
    open var isVertical: Bool { false }
    public init() {}
}

public enum UITextWritingDirection: Int, Sendable { case natural = -1, leftToRight, rightToLeft }

/// The full text input: positions, ranges, the selection and marked text.
@preconcurrency @MainActor
public protocol UITextInput: UIKeyInput {
    func text(in range: UITextRange) -> String?
    func replace(_ range: UITextRange, withText text: String)
    var selectedTextRange: UITextRange? { get set }
    var markedTextRange: UITextRange? { get }
    func setMarkedText(_ markedText: String?, selectedRange: NSRange)
    func unmarkText()
    var beginningOfDocument: UITextPosition { get }
    var endOfDocument: UITextPosition { get }
    func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange?
    func position(from position: UITextPosition, offset: Int) -> UITextPosition?
    func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult
    func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int
    func caretRect(for position: UITextPosition) -> CGRect
    func firstRect(for range: UITextRange) -> CGRect
    func closestPosition(to point: CGPoint) -> UITextPosition?
    var inputDelegate: (any UITextInputDelegate)? { get set }
}

extension UITextInput {
    public var markedTextRange: UITextRange? { nil }
    public func setMarkedText(_ markedText: String?, selectedRange: NSRange) {}
    public func unmarkText() {}
    public func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        UITextRange(start: UITextPosition(offset: min(fromPosition.offset, toPosition.offset)), end: UITextPosition(offset: max(fromPosition.offset, toPosition.offset)))
    }
    public func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        let target = position.offset + offset
        guard target >= 0, target <= endOfDocument.offset else { return nil }
        return UITextPosition(offset: target)
    }
    public func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
        position.offset < other.offset ? .orderedAscending : position.offset > other.offset ? .orderedDescending : .orderedSame
    }
    public func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int { toPosition.offset - from.offset }
    public func firstRect(for range: UITextRange) -> CGRect { caretRect(for: range.start) }
    public func closestPosition(to point: CGPoint) -> UITextPosition? { endOfDocument }
    /// The selection as a character range (helper).
    public var selectedRange: NSRange {
        guard let range = selectedTextRange else { return NSRange(location: endOfDocument.offset, length: 0) }
        return NSRange(location: range.start.offset, length: range.end.offset - range.start.offset)
    }
}

/// Told before and after the text or selection changes.
@preconcurrency @MainActor
public protocol UITextInputDelegate: AnyObject {
    func selectionWillChange(_ textInput: (any UITextInput)?)
    func selectionDidChange(_ textInput: (any UITextInput)?)
    func textWillChange(_ textInput: (any UITextInput)?)
    func textDidChange(_ textInput: (any UITextInput)?)
}

/// Makes a tap on a text input view begin editing (and the standard editing look: none here).
@preconcurrency @MainActor
public final class UITextInteraction: UIInteraction {
    public enum Mode: Int, Sendable { case editable, nonEditable }
    public let textInteractionMode: Mode
    public weak var textInput: (any UITextInput)?
    public private(set) weak var view: UIView?
    private var tap: UITapGestureRecognizer?

    public init(for mode: Mode) { textInteractionMode = mode }
    public static func textInteraction(for mode: Mode) -> UITextInteraction { UITextInteraction(for: mode) }

    public func willMove(to view: UIView?) {
        if let tap, let old = self.view { old.removeGestureRecognizer(tap) }
        tap = nil
    }

    public func didMove(to view: UIView?) {
        self.view = view
        guard let view, textInteractionMode == .editable else { return }
        let recognizer = UITapGestureRecognizer(handler: { [weak view] _ in
            guard let view, view.canBecomeFirstResponder else { return }
            _ = view.becomeFirstResponder()
        })
        view.addGestureRecognizer(recognizer)
        tap = recognizer
    }
}

// MARK: - The host relay

/// The scene's bookkeeping for a `UIKeyInput`/`UITextInput` view: the text the host last had,
/// so its next report becomes the typed or deleted characters.
@preconcurrency @MainActor
final class HostKeyInputShadow {
    var text = ""
    var selection = NSRange(location: 0, length: 0)
}

extension UIKitScene {
    /// The host reported the element's text for a key-input view: the difference is relayed as
    /// inserts and deletes (`UIKeyInput`), or as a replacement of the selected range (`UITextInput`).
    func relayHostText(_ newText: String, to view: UIView) {
        let shadow = keyInputShadow(for: view)
        let old = shadow.text
        guard old != newText else { return }
        if let input = view as? any UITextInput {
            // The common prefix and suffix bound what changed; that range is replaced.
            let oldChars = Array(old), newChars = Array(newText)
            var prefix = 0
            while prefix < oldChars.count, prefix < newChars.count, oldChars[prefix] == newChars[prefix] { prefix += 1 }
            var suffix = 0
            while suffix < oldChars.count - prefix, suffix < newChars.count - prefix, oldChars[oldChars.count - 1 - suffix] == newChars[newChars.count - 1 - suffix] { suffix += 1 }
            let replaced = UITextRange(start: UITextPosition(offset: prefix), end: UITextPosition(offset: oldChars.count - suffix))
            let inserted = String(newChars[prefix..<(newChars.count - suffix)])
            input.inputDelegate?.textWillChange(input)
            input.replace(replaced, withText: inserted)
            input.inputDelegate?.textDidChange(input)
            let caret = prefix + inserted.count
            input.selectedTextRange = UITextRange(start: UITextPosition(offset: caret), end: UITextPosition(offset: caret))
        } else if let input = view as? any UIKeyInput {
            let oldChars = Array(old), newChars = Array(newText)
            var prefix = 0
            while prefix < oldChars.count, prefix < newChars.count, oldChars[prefix] == newChars[prefix] { prefix += 1 }
            for _ in 0..<(oldChars.count - prefix) { input.deleteBackward() }
            if prefix < newChars.count { input.insertText(String(newChars[prefix...])) }
        }
        shadow.text = newText
    }

    /// The host's selection for a `UITextInput` view (UTF-16 offsets from the element).
    func relayHostSelection(start: Int, end: Int, to view: UIView) {
        guard let input = view as? any UITextInput else { return }
        let shadow = keyInputShadow(for: view)
        let utf16 = Array(shadow.text.utf16)
        func characters(upTo offset: Int) -> Int { String(decoding: utf16.prefix(max(0, min(offset, utf16.count))), as: UTF16.self).count }
        let range = UITextRange(start: UITextPosition(offset: characters(upTo: start)), end: UITextPosition(offset: characters(upTo: end)))
        guard input.selectedTextRange != range else { return }
        input.inputDelegate?.selectionWillChange(input)
        input.selectedTextRange = range
        input.inputDelegate?.selectionDidChange(input)
        shadow.selection = NSRange(location: range.start.offset, length: range.end.offset - range.start.offset)
    }

    /// Return on a key-input view: a newline for `UITextInput` (its own document), nothing else.
    func relayHostSubmit(to view: UIView) {
        if let input = view as? any UIKeyInput, !(view is any UITextInput) { input.insertText("\n") }
    }

    func keyInputShadow(for view: UIView) -> HostKeyInputShadow {
        if let shadow = keyInputShadows[ObjectIdentifier(view)]?.shadow { return shadow }
        let shadow = HostKeyInputShadow()
        if let input = view as? any UITextInput {
            shadow.text = input.text(in: UITextRange(start: input.beginningOfDocument, end: input.endOfDocument)) ?? ""
        }
        keyInputShadows[ObjectIdentifier(view)] = (shadow, UIKitScene.WeakView(view: view))
        return shadow
    }

    /// The text input element for a key-input view's semantics: the view's text (a
    /// `UITextInput`'s document, else empty) in an element over its bounds, the caret the
    /// view's own (`paintsCaret`), Return inserting a newline.
    func keyInputInfo(for view: UIView) -> TextInputInfo? {
        guard view is any UIKeyInput, view.canBecomeFirstResponder else { return nil }
        let shadow = keyInputShadow(for: view)
        if let input = view as? any UITextInput {
            shadow.text = input.text(in: UITextRange(start: input.beginningOfDocument, end: input.endOfDocument)) ?? ""
        }
        let traits = view as? any UITextInputTraits
        var info = TextInputInfo(text: shadow.text, placeholder: "", isSecure: traits?.isSecureTextEntry ?? false, textRect: view.convert(view.bounds, to: nil),
                                 font: DisplayFont(UIFont.systemFont(ofSize: 17).resolved), isEnabled: true)
        info.isMultiline = true
        info.submitsOnReturn = false
        info.paintsCaret = true
        if let traits {
            info.inputMode = traits.keyboardType.inputMode
            info.autocapitalize = traits.autocapitalizationType.token
            info.enterKeyHint = traits.returnKeyType.enterKeyHint
            info.autocorrect = traits.autocorrectionType != .no
            info.autocomplete = traits.textContentType?.rawValue
        }
        return info
    }
}
