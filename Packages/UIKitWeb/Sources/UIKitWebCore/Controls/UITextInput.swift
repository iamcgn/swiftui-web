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

/// A position in a text input's document (an offset in its characters here). An app's own
/// position subclass (`IndexedPosition: UITextPosition`) starts from `init()`: it has no offset
/// of ours, and compares by identity, as UIKit's (NSObject) positions do.
@preconcurrency @MainActor
open class UITextPosition: Equatable {
    // Set once, by the convenience initializer, before the position is shared.
    nonisolated(unsafe) private var _offset: Int?
    /// The offset this position was made with (0 for an app's own subclass, which keeps its own).
    public var offset: Int { _offset ?? 0 }
    /// `init()` is the one designated initializer, as UIKit's is, so an app's subclass
    /// (`init(index:) { self.index = index }`) calls it implicitly.
    public init() {}
    public convenience init(offset: Int) {
        self.init()
        _offset = offset
    }
    nonisolated public static func == (lhs: UITextPosition, rhs: UITextPosition) -> Bool {
        if let a = lhs._offset, let b = rhs._offset { return a == b }
        return lhs === rhs
    }
}

/// A range in a text input's document. An app's own range subclass (`IndexedRange: UITextRange`)
/// starts from `init()` and overrides `start`, `end` and `isEmpty`, as with UIKit's.
@preconcurrency @MainActor
open class UITextRange: Equatable {
    // Set once, by the convenience initializer, before the range is shared.
    nonisolated(unsafe) private var _start: UITextPosition?
    nonisolated(unsafe) private var _end: UITextPosition?
    open var start: UITextPosition { _start ?? UITextPosition(offset: 0) }
    open var end: UITextPosition { _end ?? UITextPosition(offset: 0) }
    /// `init()` is the one designated initializer, as with UITextPosition.
    public init() {}
    public convenience init(start: UITextPosition, end: UITextPosition) {
        self.init()
        _start = start
        _end = end
    }
    open var isEmpty: Bool { start == end }
    nonisolated public static func == (lhs: UITextRange, rhs: UITextRange) -> Bool {
        if let ls = lhs._start, let le = lhs._end, let rs = rhs._start, let re = rhs._end { return ls == rs && le == re }
        return lhs === rhs
    }
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

/// UIKit's name for the writing direction (`NSWritingDirection`, Drawing/StringDrawing.swift).
public typealias UITextWritingDirection = NSWritingDirection

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
    /// Finds word, line and paragraph boundaries for the input (a string tokenizer by default).
    var tokenizer: any UITextInputTokenizer { get }
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
    public var tokenizer: any UITextInputTokenizer { UITextInputStringTokenizer(input: self) }
    /// The selection as a character range (helper), measured with the input's own offsets.
    public var selectedRange: NSRange {
        let begin = beginningOfDocument
        guard let range = selectedTextRange else { return NSRange(location: offset(from: begin, to: endOfDocument), length: 0) }
        let start = offset(from: begin, to: range.start)
        return NSRange(location: start, length: offset(from: begin, to: range.end) - start)
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
    /// Asked whether a tap may begin the interaction, and told when it begins and ends.
    public weak var delegate: (any UITextInteractionDelegate)?
    private var tap: UITapGestureRecognizer?

    /// The interaction's recognizers, for an app to make its own wait for them
    /// (`require(toFail:)`): the tap that begins editing.
    public var gesturesForFailureRequirements: [UIGestureRecognizer] { tap.map { [$0] } ?? [] }

    public init(for mode: Mode) { textInteractionMode = mode }
    public static func textInteraction(for mode: Mode) -> UITextInteraction { UITextInteraction(for: mode) }

    public func willMove(to view: UIView?) {
        if let tap, let old = self.view { old.removeGestureRecognizer(tap) }
        tap = nil
    }

    public func didMove(to view: UIView?) {
        self.view = view
        guard let view, textInteractionMode == .editable else { return }
        let recognizer = UITapGestureRecognizer(handler: { [weak self, weak view] tap in
            guard let self, let view, view.canBecomeFirstResponder else { return }
            if let delegate = self.delegate {
                guard delegate.interactionShouldBegin(self, at: tap.location(in: view)) else { return }
                delegate.interactionWillBegin(self)
            }
            _ = view.becomeFirstResponder()
        })
        view.addGestureRecognizer(recognizer)
        tap = recognizer
    }
}

/// Asked whether a text interaction may begin at a point, and told when it begins and ends.
@preconcurrency @MainActor
public protocol UITextInteractionDelegate: AnyObject {
    func interactionShouldBegin(_ interaction: UITextInteraction, at point: CGPoint) -> Bool
    func interactionWillBegin(_ interaction: UITextInteraction)
    func interactionDidEnd(_ interaction: UITextInteraction)
}

extension UITextInteractionDelegate {
    public func interactionShouldBegin(_ interaction: UITextInteraction, at point: CGPoint) -> Bool { true }
    public func interactionWillBegin(_ interaction: UITextInteraction) {}
    public func interactionDidEnd(_ interaction: UITextInteraction) {}
}

// MARK: - The host relay

extension UITextInput {
    /// The range between two offsets from the document's start, made by the input.
    func range(fromOffset lower: Int, toOffset upper: Int) -> UITextRange? {
        let begin = beginningOfDocument
        guard let start = position(from: begin, offset: lower), let end = position(from: begin, offset: upper) else { return nil }
        return textRange(from: start, to: end)
    }

    /// The whole document's text.
    var wholeText: String {
        guard let all = textRange(from: beginningOfDocument, to: endOfDocument) else { return "" }
        return text(in: all) ?? ""
    }
}

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
            // Positions and ranges come from the input itself, so an app's own position and
            // range subclasses (Runestone's `IndexedRange`) are what it is handed.
            let inserted = String(newChars[prefix..<(newChars.count - suffix)])
            if let replaced = input.range(fromOffset: prefix, toOffset: oldChars.count - suffix) {
                input.inputDelegate?.textWillChange(input)
                input.replace(replaced, withText: inserted)
                input.inputDelegate?.textDidChange(input)
            }
            let caret = prefix + inserted.count
            if let range = input.range(fromOffset: caret, toOffset: caret) { input.selectedTextRange = range }
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
        let lower = characters(upTo: start), upper = characters(upTo: end)
        let current = input.selectedRange
        guard input.selectedTextRange == nil || current.location != lower || current.length != upper - lower,
              let range = input.range(fromOffset: lower, toOffset: upper) else { return }
        input.inputDelegate?.selectionWillChange(input)
        input.selectedTextRange = range
        input.inputDelegate?.selectionDidChange(input)
        shadow.selection = NSRange(location: lower, length: upper - lower)
    }

    /// Return on a key-input view: a newline for `UITextInput` (its own document), nothing else.
    func relayHostSubmit(to view: UIView) {
        if let input = view as? any UIKeyInput, !(view is any UITextInput) { input.insertText("\n") }
    }

    func keyInputShadow(for view: UIView) -> HostKeyInputShadow {
        if let shadow = keyInputShadows[ObjectIdentifier(view)]?.shadow { return shadow }
        let shadow = HostKeyInputShadow()
        if let input = view as? any UITextInput {
            shadow.text = input.wholeText
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
            shadow.text = input.wholeText
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
