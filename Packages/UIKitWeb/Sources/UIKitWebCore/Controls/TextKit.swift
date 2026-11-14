// TextKit 1 (Docs/elements/UIKit/TextView.md, "TextKit"): `NSTextStorage`, `NSLayoutManager` and
// `NSTextContainer` as UIKit code drives them, both a text view's own three (`textStorage`,
// `layoutManager`, `textContainer`) and a stand-alone set (a storage given a layout manager given
// a container of some size, as a label's link hit-testing builds). Glyphs are the text's UTF-16
// units one for one, so glyph and character ranges are the same ranges. The lines come from the
// text engine with the text view's own wrapping, at the container's width less its line
// fragment padding; each line fragment is the container's width wide and one line pitch tall
// (the tallest font's line height on the pixel grid), and owns the characters up to the next
// line's first, its trailing spaces and newline included. A glyph sits after the width of the
// line's text before it. A text view's layout manager answers for the text as the view draws
// it (its insets, alignment and fonts); exclusion paths do not reach the layout manager's
// answers, and there is no extra line fragment after a final newline.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

// MARK: - Text storage

/// What an edit of a text storage changed.
public struct NSTextStorageEditActions: OptionSet, Hashable, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let editedAttributes = NSTextStorageEditActions(rawValue: 1 << 0)
    public static let editedCharacters = NSTextStorageEditActions(rawValue: 1 << 1)
}

/// Hears a text storage's edits as they are processed.
public protocol NSTextStorageDelegate: AnyObject {
    func textStorage(_ textStorage: NSTextStorage, willProcessEditing editedMask: NSTextStorage.EditActions, range editedRange: NSRange, changeInLength delta: Int)
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions, range editedRange: NSRange, changeInLength delta: Int)
}

extension NSTextStorageDelegate {
    public func textStorage(_ textStorage: NSTextStorage, willProcessEditing editedMask: NSTextStorage.EditActions, range editedRange: NSRange, changeInLength delta: Int) {}
    public func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorage.EditActions, range editedRange: NSRange, changeInLength delta: Int) {}
}

/// A text storage's layout managers and the edit not yet processed.
struct TextStoragePending {
    var managers: [NSLayoutManager] = []
    var depth = 0
    var mask: NSTextStorageEditActions = []
    var range = NSRange(location: NSNotFound, length: 0)
    var delta = 0
}

#if os(WASI)
/// The attributed string a layout manager lays out: every change is an edit its layout managers
/// hear, at once or, inside `beginEditing()`/`endEditing()`, at the last `endEditing()`.
open class NSTextStorage: NSMutableAttributedString, @unchecked Sendable {
    var pending = TextStoragePending()
    open weak var delegate: (any NSTextStorageDelegate)?

    public convenience init() { self.init(string: "") }

    open override func _didChange(characters: Bool, range: NSRange, changeInLength: Int) {
        edited(characters ? .editedCharacters : .editedAttributes, range: range, changeInLength: changeInLength)
    }

    open override func beginEditing() { pending.depth += 1 }

    open override func endEditing() {
        pending.depth = max(0, pending.depth - 1)
        if pending.depth == 0 { processPendingEdit() }
    }

    /// The text and attributes as they are now.
    var contents: NSAttributedString { NSAttributedString(attributedString: self) }
}
#else
/// The attributed string a layout manager lays out: every change is an edit its layout managers
/// hear, at once or, inside `beginEditing()`/`endEditing()`, at the last `endEditing()`. (On the
/// host it wraps Foundation's attributed string, which is a class cluster there.)
open class NSTextStorage: @unchecked Sendable {
    var pending = TextStoragePending()
    open weak var delegate: (any NSTextStorageDelegate)?
    let backing: NSMutableAttributedString

    public init() { backing = NSMutableAttributedString(string: "") }
    public init(string: String) { backing = NSMutableAttributedString(string: string) }
    public init(string: String, attributes: [NSAttributedString.Key: Any]?) {
        backing = NSMutableAttributedString(string: string, attributes: attributes)
    }
    public init(attributedString: NSAttributedString) { backing = NSMutableAttributedString(attributedString: attributedString) }

    open var string: String { backing.string }
    open var length: Int { backing.length }

    open func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }
    open func attribute(_ name: NSAttributedString.Key, at location: Int, effectiveRange range: NSRangePointer?) -> Any? {
        backing.attribute(name, at: location, effectiveRange: range)
    }
    open func attributedSubstring(from range: NSRange) -> NSAttributedString { backing.attributedSubstring(from: range) }
    open func enumerateAttributes(in enumerationRange: NSRange, options opts: NSAttributedString.EnumerationOptions = [],
                                  using block: ([NSAttributedString.Key: Any], NSRange, UnsafeMutablePointer<ObjCBool>) -> Void) {
        backing.enumerateAttributes(in: enumerationRange, options: opts, using: block)
    }

    open func replaceCharacters(in range: NSRange, with str: String) {
        backing.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: NSRange(location: range.location, length: str.utf16.count), changeInLength: str.utf16.count - range.length)
    }
    open func replaceCharacters(in range: NSRange, with attrString: NSAttributedString) {
        backing.replaceCharacters(in: range, with: attrString)
        edited(.editedCharacters, range: NSRange(location: range.location, length: attrString.length), changeInLength: attrString.length - range.length)
    }
    open func insert(_ attrString: NSAttributedString, at loc: Int) { replaceCharacters(in: NSRange(location: loc, length: 0), with: attrString) }
    open func append(_ attrString: NSAttributedString) { replaceCharacters(in: NSRange(location: length, length: 0), with: attrString) }
    open func deleteCharacters(in range: NSRange) { replaceCharacters(in: range, with: "") }
    open func setAttributedString(_ attrString: NSAttributedString) { replaceCharacters(in: NSRange(location: 0, length: length), with: attrString) }

    open func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
    }
    open func addAttribute(_ name: NSAttributedString.Key, value: Any, range: NSRange) {
        backing.addAttribute(name, value: value, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
    }
    open func addAttributes(_ attrs: [NSAttributedString.Key: Any], range: NSRange) {
        backing.addAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
    }
    open func removeAttribute(_ name: NSAttributedString.Key, range: NSRange) {
        backing.removeAttribute(name, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
    }

    open func beginEditing() { pending.depth += 1 }

    open func endEditing() {
        pending.depth = max(0, pending.depth - 1)
        if pending.depth == 0 { processPendingEdit() }
    }

    /// The text and attributes as they are now.
    var contents: NSAttributedString { NSAttributedString(attributedString: backing) }
}
#endif

extension NSTextStorage {
    public typealias EditActions = NSTextStorageEditActions

    /// The layout managers laying this text out.
    public var layoutManagers: [NSLayoutManager] { pending.managers }

    public func addLayoutManager(_ aLayoutManager: NSLayoutManager) {
        guard !pending.managers.contains(where: { $0 === aLayoutManager }) else { return }
        pending.managers.append(aLayoutManager)
        MainActor.assumeIsolated { aLayoutManager.attach(self) }
    }

    public func removeLayoutManager(_ aLayoutManager: NSLayoutManager) {
        pending.managers.removeAll { $0 === aLayoutManager }
        MainActor.assumeIsolated { aLayoutManager.detach(from: self) }
    }

    /// The edit being gathered: what changed, the range in the new text, and the change in length.
    public var editedMask: EditActions { pending.mask }
    public var editedRange: NSRange { pending.range }
    public var changeInLength: Int { pending.delta }
    /// Attributes are fixed as they are set, never later.
    public var fixesAttributesLazily: Bool { false }

    /// Records an edit (the mutators call it): processed at once outside `beginEditing()`, else
    /// gathered with the others until the last `endEditing()`.
    public func edited(_ editedMask: EditActions, range editedRange: NSRange, changeInLength delta: Int) {
        if pending.mask.isEmpty {
            pending.range = editedRange
            pending.delta = delta
        } else {
            // The earlier range in the new text's offsets, joined with this one.
            var earlier = pending.range
            let earlierEnd = earlier.location + earlier.length
            if editedRange.location <= earlierEnd { earlier.length = max(0, earlier.length + delta) }
            if editedRange.location < earlier.location { earlier.location = max(0, earlier.location + delta) }
            let start = min(earlier.location, editedRange.location)
            let end = max(earlier.location + earlier.length, editedRange.location + editedRange.length)
            pending.range = NSRange(location: start, length: end - start)
            pending.delta += delta
        }
        pending.mask.formUnion(editedMask)
        if pending.depth == 0 { processPendingEdit() }
    }

    /// Processes the gathered edit now (the last `endEditing()` does).
    public func processEditing() { processPendingEdit() }

    func processPendingEdit() {
        guard !pending.mask.isEmpty else { return }
        let mask = pending.mask, range = pending.range, delta = pending.delta
        delegate?.textStorage(self, willProcessEditing: mask, range: range, changeInLength: delta)
        delegate?.textStorage(self, didProcessEditing: mask, range: range, changeInLength: delta)
        pending.mask = []
        pending.range = NSRange(location: NSNotFound, length: 0)
        pending.delta = 0
        let managers = pending.managers
        MainActor.assumeIsolated {
            for manager in managers {
                manager.processEditing(for: self, edited: mask, range: range, changeInLength: delta, invalidatedRange: range)
            }
        }
    }
}

// MARK: - Text container

/// The region lines are laid out in: its size (a zero or unbounded width leaves the lines
/// unwrapped), the padding either side of each line, a line limit, and the paths (in the
/// container's coordinates: the view's inside its insets) lines flow around, by their bounds: a
/// line whose band a path crosses starts after it when it lies in the left half, ends before it
/// when in the right. A text view's own container follows the view's width.
@preconcurrency @MainActor
open class NSTextContainer {
    private var storedSize: CGSize
    /// The size; a text view's container that tracks the view is the view's width inside its
    /// insets.
    open var size: CGSize {
        get {
            guard let owner else { return storedSize }
            let insets = owner.textContainerInset
            let width = widthTracksTextView ? max(0, owner.bounds.width - insets.left - insets.right) : storedSize.width
            let height = heightTracksTextView ? max(0, owner.bounds.height - insets.top - insets.bottom) : storedSize.height
            return CGSize(width: width, height: height)
        }
        set {
            storedSize = newValue
            changed()
        }
    }
    open var widthTracksTextView = false { didSet { changed() } }
    open var heightTracksTextView = false { didSet { changed() } }
    open var lineFragmentPadding: CGFloat = 5 { didSet { changed() } }
    open var maximumNumberOfLines = 0 { didSet { changed() } }
    open var lineBreakMode: NSLineBreakMode = .byWordWrapping { didSet { changed() } }
    open var exclusionPaths: [UIBezierPath] = [] { didSet { changed() } }
    /// The layout manager laying lines out in this container.
    public internal(set) weak var layoutManager: NSLayoutManager?
    /// Whether the container is a plain rectangle (no exclusion paths).
    open var isSimpleRectangularTextContainer: Bool { exclusionPaths.isEmpty }
    weak var owner: UITextView?

    public init(size: CGSize) { storedSize = size }
    public convenience init() { self.init(size: .zero) }

    /// Moves this container (and the layout manager's other containers) to another layout manager.
    open func replaceLayoutManager(_ newLayoutManager: NSLayoutManager) {
        guard let old = layoutManager, old !== newLayoutManager else { newLayoutManager.addTextContainer(self); return }
        let containers = old.textContainers
        while !old.textContainers.isEmpty { old.removeTextContainer(at: 0) }
        for container in containers { newLayoutManager.addTextContainer(container) }
        if let storage = old.textStorage { storage.removeLayoutManager(old); storage.addLayoutManager(newLayoutManager) }
    }

    private func changed() {
        layoutManager?.invalidateLines()
        owner?.textDidChange()
    }
}

// MARK: - Layout manager

/// Hears when a layout manager has laid its text out.
@preconcurrency @MainActor
public protocol NSLayoutManagerDelegate: AnyObject {
    func layoutManager(_ layoutManager: NSLayoutManager, didCompleteLayoutFor textContainer: NSTextContainer?, atEnd layoutFinishedFlag: Bool)
}

extension NSLayoutManagerDelegate {
    public func layoutManager(_ layoutManager: NSLayoutManager, didCompleteLayoutFor textContainer: NSTextContainer?, atEnd layoutFinishedFlag: Bool) {}
}

/// Lays a text storage's characters out in its text containers (the first one here) and answers
/// where each glyph and line is.
@preconcurrency @MainActor
open class NSLayoutManager {
    /// The storage laid out (it keeps its layout managers; a layout manager does not keep it).
    open private(set) weak var textStorage: NSTextStorage?
    open private(set) var textContainers: [NSTextContainer] = []
    open weak var delegate: (any NSLayoutManagerDelegate)?
    open var allowsNonContiguousLayout = false
    open var hasNonContiguousLayout: Bool { false }
    open var showsInvisibleCharacters = false
    open var showsControlCharacters = false
    open var usesFontLeading = true
    open var limitsLayoutForSuspiciousContents = true
    /// The text view these are the TextKit objects of: its text, fonts and insets are laid out.
    weak var textView: UITextView?
    private var lines: LaidOutText?

    public init() {}

    // MARK: Storage and containers

    func attach(_ storage: NSTextStorage) {
        textStorage = storage
        invalidateLines()
    }

    func detach(from storage: NSTextStorage) {
        if textStorage === storage { textStorage = nil }
        invalidateLines()
    }

    /// Lays out another storage instead.
    open func replaceTextStorage(_ newTextStorage: NSTextStorage) {
        textStorage?.removeLayoutManager(self)
        newTextStorage.addLayoutManager(self)
    }

    open func addTextContainer(_ container: NSTextContainer) { insertTextContainer(container, at: textContainers.count) }

    open func insertTextContainer(_ container: NSTextContainer, at index: Int) {
        textContainers.insert(container, at: max(0, min(index, textContainers.count)))
        container.layoutManager = self
        invalidateLines()
    }

    open func removeTextContainer(at index: Int) {
        guard textContainers.indices.contains(index) else { return }
        let container = textContainers.remove(at: index)
        if container.layoutManager === self { container.layoutManager = nil }
        invalidateLines()
    }

    /// The storage changed: the lines are laid out again when next asked, and a text view
    /// shows the new text.
    open func processEditing(for textStorage: NSTextStorage, edited editMask: NSTextStorage.EditActions, range newCharRange: NSRange,
                             changeInLength delta: Int, invalidatedRange invalidatedCharRange: NSRange) {
        invalidateLines()
        textView?.storageDidEdit(textStorage)
    }

    func invalidateLines() { lines = nil }

    // MARK: Layout

    open func invalidateLayout(forCharacterRange charRange: NSRange, actualCharacterRange actualCharRange: NSRangePointer?) {
        actualCharRange?.pointee = charRange
        invalidateLines()
    }
    open func invalidateGlyphs(forCharacterRange charRange: NSRange, changeInLength delta: Int, actualCharacterRange actualCharRange: NSRangePointer?) {
        actualCharRange?.pointee = charRange
        invalidateLines()
    }
    open func invalidateDisplay(forCharacterRange charRange: NSRange) { textView?.setNeedsDisplay() }
    open func invalidateDisplay(forGlyphRange glyphRange: NSRange) { textView?.setNeedsDisplay() }

    open func ensureLayout(for container: NSTextContainer) { _ = laidOut() }
    open func ensureLayout(forCharacterRange charRange: NSRange) { _ = laidOut() }
    open func ensureLayout(forGlyphRange glyphRange: NSRange) { _ = laidOut() }
    open func ensureLayout(forBoundingRect bounds: CGRect, in container: NSTextContainer) { _ = laidOut() }

    /// The glyphs: one for each UTF-16 unit of the text.
    open var numberOfGlyphs: Int { laidOut().length }

    open func glyphIndexForCharacter(at charIndex: Int) -> Int { max(0, min(charIndex, laidOut().length)) }
    open func characterIndexForGlyph(at glyphIndex: Int) -> Int { max(0, min(glyphIndex, laidOut().length)) }

    open func glyphRange(forCharacterRange charRange: NSRange, actualCharacterRange actualCharRange: NSRangePointer?) -> NSRange {
        let range = clamped(charRange)
        actualCharRange?.pointee = range
        return range
    }

    open func characterRange(forGlyphRange glyphRange: NSRange, actualGlyphRange: NSRangePointer?) -> NSRange {
        let range = clamped(glyphRange)
        actualGlyphRange?.pointee = range
        return range
    }

    /// The glyphs laid out in a container: all of them, in the first.
    open func glyphRange(for container: NSTextContainer) -> NSRange {
        container === textContainers.first ? NSRange(location: 0, length: laidOut().length) : NSRange(location: 0, length: 0)
    }

    open func textContainer(forGlyphAt glyphIndex: Int, effectiveRange effectiveGlyphRange: NSRangePointer?) -> NSTextContainer? {
        effectiveGlyphRange?.pointee = NSRange(location: 0, length: laidOut().length)
        return textContainers.first
    }

    open func textContainer(forGlyphAt glyphIndex: Int, effectiveRange effectiveGlyphRange: NSRangePointer?, withoutAdditionalLayout flag: Bool) -> NSTextContainer? {
        textContainer(forGlyphAt: glyphIndex, effectiveRange: effectiveGlyphRange)
    }

    /// The line fragment holding a glyph (the container's width by a line pitch), with the
    /// glyphs of its line.
    open func lineFragmentRect(forGlyphAt glyphIndex: Int, effectiveRange effectiveGlyphRange: NSRangePointer?) -> CGRect {
        let layout = laidOut()
        guard let index = layout.lineIndex(forGlyph: glyphIndex) else { effectiveGlyphRange?.pointee = NSRange(location: 0, length: 0); return .zero }
        effectiveGlyphRange?.pointee = layout.lines[index].characters
        return layout.lines[index].fragmentRect
    }

    open func lineFragmentRect(forGlyphAt glyphIndex: Int, effectiveRange effectiveGlyphRange: NSRangePointer?, withoutAdditionalLayout flag: Bool) -> CGRect {
        lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: effectiveGlyphRange)
    }

    /// The part of a glyph's line fragment its text uses, with the line fragment padding either side.
    open func lineFragmentUsedRect(forGlyphAt glyphIndex: Int, effectiveRange effectiveGlyphRange: NSRangePointer?) -> CGRect {
        let layout = laidOut()
        guard let index = layout.lineIndex(forGlyph: glyphIndex) else { effectiveGlyphRange?.pointee = NSRange(location: 0, length: 0); return .zero }
        effectiveGlyphRange?.pointee = layout.lines[index].characters
        return layout.lines[index].usedRect
    }

    open func lineFragmentUsedRect(forGlyphAt glyphIndex: Int, effectiveRange effectiveGlyphRange: NSRangePointer?, withoutAdditionalLayout flag: Bool) -> CGRect {
        lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: effectiveGlyphRange)
    }

    /// A glyph's position in its line fragment: across from the fragment's left edge, down to
    /// the baseline.
    open func location(forGlyphAt glyphIndex: Int) -> CGPoint {
        let layout = laidOut()
        guard let index = layout.lineIndex(forGlyph: glyphIndex) else { return .zero }
        return CGPoint(x: layout.x(of: glyphIndex, inLine: index), y: layout.baselineOffset)
    }

    /// The rectangle the glyphs take in the container: across each line they are on, the lines' height.
    open func boundingRect(forGlyphRange glyphRange: NSRange, in container: NSTextContainer) -> CGRect {
        let layout = laidOut()
        let range = clamped(glyphRange)
        var result = CGRect.null
        for index in layout.lineIndices(touching: range) {
            let line = layout.lines[index]
            let start = max(range.location, line.characters.location)
            let end = min(range.location + range.length, line.characters.location + line.characters.length)
            let x0 = layout.x(of: start, inLine: index), x1 = layout.x(of: max(start, end), inLine: index)
            result = result.union(CGRect(x: x0, y: line.fragmentRect.minY, width: max(0, x1 - x0), height: line.fragmentRect.height))
        }
        return result.isNull ? .zero : result
    }

    /// The rectangle every line's used part fills.
    open func usedRect(for container: NSTextContainer) -> CGRect {
        let layout = laidOut()
        guard !layout.lines.isEmpty else { return CGRect(x: 0, y: 0, width: 2 * layout.padding, height: layout.pitch) }
        return layout.lines.map(\.usedRect).reduce(CGRect.null) { $0.union($1) }
    }

    /// The glyphs of the lines a rectangle (in the container) crosses.
    open func glyphRange(forBoundingRect bounds: CGRect, in container: NSTextContainer) -> NSRange {
        let crossed = laidOut().lines.filter { $0.fragmentRect.intersects(bounds) }
        guard let first = crossed.first, let last = crossed.last else { return NSRange(location: 0, length: 0) }
        let end = last.characters.location + last.characters.length
        return NSRange(location: first.characters.location, length: end - first.characters.location)
    }

    open func glyphRange(forBoundingRectWithoutAdditionalLayout bounds: CGRect, in container: NSTextContainer) -> NSRange {
        glyphRange(forBoundingRect: bounds, in: container)
    }

    /// Calls `block` for each line fragment holding glyphs of the range, in order, with its
    /// rectangle, its used rectangle, the container and its glyphs.
    open func enumerateLineFragments(forGlyphRange glyphRange: NSRange,
                                     using block: (CGRect, CGRect, NSTextContainer, NSRange, UnsafeMutablePointer<ObjCBool>) -> Void) {
        let layout = laidOut()
        guard let container = textContainers.first else { return }
        var stop = ObjCBool(false)
        for index in layout.lineIndices(touching: clamped(glyphRange)) {
            let line = layout.lines[index]
            block(line.fragmentRect, line.usedRect, container, line.characters, &stop)
            if stop.boolValue { break }
        }
    }

    /// Calls `block` for each rectangle the range takes (one for each line it is on).
    open func enumerateEnclosingRects(forGlyphRange glyphRange: NSRange, withinSelectedGlyphRange selectedRange: NSRange, in textContainer: NSTextContainer,
                                      using block: (CGRect, UnsafeMutablePointer<ObjCBool>) -> Void) {
        let layout = laidOut()
        let range = clamped(glyphRange)
        var stop = ObjCBool(false)
        for index in layout.lineIndices(touching: range) {
            let line = layout.lines[index]
            let start = max(range.location, line.characters.location)
            let end = min(range.location + range.length, line.characters.location + line.characters.length)
            let x0 = layout.x(of: start, inLine: index), x1 = layout.x(of: max(start, end), inLine: index)
            block(CGRect(x: x0, y: line.fragmentRect.minY, width: max(0, x1 - x0), height: line.fragmentRect.height), &stop)
            if stop.boolValue { break }
        }
    }

    /// The character under a point in the container (the line at its height, the character
    /// across from it; past either end of a line, that end's character), and how far across
    /// that character the point is, 0 to 1.
    open func characterIndex(for point: CGPoint, in container: NSTextContainer,
                             fractionOfDistanceBetweenInsertionPoints partialFraction: UnsafeMutablePointer<CGFloat>?) -> Int {
        let (index, fraction) = laidOut().character(at: point)
        partialFraction?.pointee = fraction
        return index
    }

    open func glyphIndex(for point: CGPoint, in container: NSTextContainer, fractionOfDistanceThroughGlyph partialFraction: UnsafeMutablePointer<CGFloat>?) -> Int {
        characterIndex(for: point, in: container, fractionOfDistanceBetweenInsertionPoints: partialFraction)
    }

    open func glyphIndex(for point: CGPoint, in container: NSTextContainer) -> Int {
        characterIndex(for: point, in: container, fractionOfDistanceBetweenInsertionPoints: nil)
    }

    /// A position between glyphs: where the insertion point before `glyphIndex` goes.
    open func fractionOfDistanceThroughGlyph(for point: CGPoint, in container: NSTextContainer) -> CGFloat {
        laidOut().character(at: point).fraction
    }

    /// No glyph is cut by a line's truncation here.
    open func truncatedGlyphRange(inLineFragmentForGlyphAt glyphIndex: Int) -> NSRange { NSRange(location: NSNotFound, length: 0) }

    /// No extra line fragment follows a final newline here.
    open var extraLineFragmentRect: CGRect { .zero }
    open var extraLineFragmentUsedRect: CGRect { .zero }
    open var extraLineFragmentTextContainer: NSTextContainer? { nil }

    /// A font's line height (its ascender to descender plus its leading).
    open func defaultLineHeight(for theFont: UIFont) -> CGFloat { theFont.lineHeight + theFont.leading }
    /// A font's baseline below the top of its line.
    open func defaultBaselineOffset(for theFont: UIFont) -> CGFloat { theFont.ascender }

    private func clamped(_ range: NSRange) -> NSRange {
        let length = laidOut().length
        let start = max(0, min(range.location, length))
        let end = max(start, min(range.location + max(0, range.length), length))
        return NSRange(location: start, length: end - start)
    }

    // MARK: Lines

    /// The lines as they are now, laid out again only after a change.
    func laidOut() -> LaidOutText {
        let source = currentSource()
        if let lines, lines.source == source.key { return lines }
        let laid = LaidOutText(source)
        lines = laid
        delegate?.layoutManager(self, didCompleteLayoutFor: textContainers.first, atEnd: true)
        return laid
    }

    /// What the lines are laid out from: a text view's text as it draws it, else the storage
    /// in the first container.
    private func currentSource() -> LaidOutText.Source {
        if let textView { return textView.textKitSource() }
        let container = textContainers.first
        let padding = container?.lineFragmentPadding ?? 0
        let width = container?.size.width ?? 0
        let wrapWidth: CGFloat? = width > 0 && width < 1e7 ? max(0, width - 2 * padding) : nil
        var runs: [StyledRun] = []
        var fonts: [UIFont] = []
        var alignment = NSTextAlignment.natural
        let fallback = UIFont(name: "Helvetica", size: 12) ?? .systemFont(ofSize: 12)
        if let storage = textStorage, storage.length > 0 {
            let utf16 = Array(storage.string.utf16)
            storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length), options: []) { attributes, range, _ in
                let font = attributes[.font] as? UIFont ?? fallback
                let piece = String(decoding: utf16[range.location..<min(utf16.count, range.location + range.length)], as: UTF16.self)
                runs.append(StyledRun(piece, font: font.resolved))
                fonts.append(font)
                if range.location == 0, let style = attributes[.paragraphStyle] as? NSParagraphStyle { alignment = style.alignment }
            }
        }
        let tallest = fonts.max { $0.lineHeight < $1.lineHeight } ?? fallback
        let scale = UIScreen.main.scale
        let limit = (container?.maximumNumberOfLines ?? 0) > 0 ? container?.maximumNumberOfLines : nil
        return LaidOutText.Source(runs: runs, wrapWidth: wrapWidth, containerWidth: wrapWidth.map { $0 + 2 * padding },
                                  lineLimit: limit, padding: padding, pitch: (tallest.lineHeight + tallest.leading).roundedUp(to: scale),
                                  baselineOffset: tallest.ascender.roundedUp(to: scale), alignment: alignment)
    }
}

/// A layout manager's lines: each one's characters (UTF-16 offsets), its line fragment and used
/// rectangles in the container, and, measured when first asked, where each of its characters
/// starts.
@MainActor
final class LaidOutText {
    struct Source {
        var runs: [StyledRun]
        /// The width lines wrap to (inside the padding); nil leaves them unwrapped.
        var wrapWidth: CGFloat?
        /// The container's width; nil for an unwrapped container (the widest line and the padding).
        var containerWidth: CGFloat?
        var lineLimit: Int?
        var padding: CGFloat
        var pitch: CGFloat
        var baselineOffset: CGFloat
        var alignment: NSTextAlignment

        /// What decides the lines (the fonts as the runs carry them).
        var key: Key { Key(runs: runs, wrapWidth: wrapWidth, containerWidth: containerWidth, lineLimit: lineLimit, padding: padding,
                           pitch: pitch, baselineOffset: baselineOffset, alignment: alignment.rawValue) }
        struct Key: Equatable {
            var runs: [StyledRun]
            var wrapWidth: CGFloat?
            var containerWidth: CGFloat?
            var lineLimit: Int?
            var padding: CGFloat
            var pitch: CGFloat
            var baselineOffset: CGFloat
            var alignment: Int
        }
    }

    struct Line {
        /// The characters the line owns: to the next line's first.
        var characters: NSRange
        var fragmentRect: CGRect
        var usedRect: CGRect
        /// Where the line's text starts across the container.
        var textX: CGFloat
        /// The UTF-16 offsets where the line's characters start, through the end of what it owns
        /// (less a final newline), and the width of the line's text before each, once measured.
        var boundaries: [Int]
        var advances: [CGFloat]?
    }

    let source: Source.Key
    let runs: [StyledRun]
    /// Each run's first UTF-16 offset.
    let runStarts: [Int]
    let length: Int
    let padding: CGFloat
    let pitch: CGFloat
    let baselineOffset: CGFloat
    var lines: [Line] = []

    init(_ source: Source) {
        self.source = source.key
        runs = source.runs
        var starts: [Int] = []
        var offset = 0
        for run in runs { starts.append(offset); offset += run.string.utf16.count }
        runStarts = starts
        length = offset
        padding = source.padding
        pitch = source.pitch
        baselineOffset = source.baselineOffset
        let text = runs.map(\.string).joined()
        guard runs.contains(where: { !$0.string.isEmpty }) else { return }
        let layout = UIKitScene.shared.textEngine.layout(runs, options: UITextView.layoutOptions(lineLimit: source.lineLimit), width: source.wrapWidth)
        let utf16 = Array(text.utf16)
        let starts16 = layout.lines.map { min(length, max(0, $0.range.lowerBound.utf16Offset(in: text))) }
        let containerWidth = source.containerWidth ?? ((layout.lines.map(\.width).max() ?? 0) + 2 * source.padding)
        let wrap = containerWidth - 2 * source.padding
        for (index, line) in layout.lines.enumerated() {
            let start = index == 0 ? 0 : max(starts16[index], lines.last.map { $0.characters.location } ?? 0)
            let end = index + 1 < starts16.count ? max(start, starts16[index + 1]) : length
            let y = CGFloat(index) * source.pitch
            let inset: CGFloat
            switch source.alignment {
            case .center: inset = (wrap - line.inkWidth) / 2
            case .right: inset = wrap - line.inkWidth
            default: inset = 0
            }
            let textX = source.padding + inset + (line.fragments.first?.x ?? 0)
            // The character boundaries up to the end, a final newline left out.
            var last = end
            if last > start, utf16[last - 1] == 10 { last -= 1 }
            let piece = String(decoding: utf16[start..<last], as: UTF16.self)
            var boundaries: [Int] = []
            var offset = start
            for character in piece { boundaries.append(offset); offset += character.utf16.count }
            boundaries.append(last)
            lines.append(Line(characters: NSRange(location: start, length: end - start),
                              fragmentRect: CGRect(x: 0, y: y, width: containerWidth, height: source.pitch),
                              usedRect: CGRect(x: textX - source.padding, y: y, width: line.width + 2 * source.padding, height: source.pitch),
                              textX: textX, boundaries: boundaries, advances: nil))
        }
    }

    /// The line holding a glyph: the last line starting at or before it.
    func lineIndex(forGlyph glyph: Int) -> Int? {
        guard !lines.isEmpty else { return nil }
        return lines.lastIndex { $0.characters.location <= max(0, glyph) } ?? 0
    }

    /// The lines a range touches (an empty range, the line holding its location).
    func lineIndices(touching range: NSRange) -> [Int] {
        guard !lines.isEmpty else { return [] }
        if range.length == 0 { return lineIndex(forGlyph: range.location).map { [$0] } ?? [] }
        let end = range.location + range.length
        return lines.indices.filter {
            let line = lines[$0].characters
            return line.location < end && line.location + line.length > range.location
        }
    }

    /// Where the glyph at a UTF-16 offset starts across the container (its line's).
    func x(of offset: Int, inLine index: Int) -> CGFloat {
        let advances = measuredAdvances(ofLine: index)
        let line = lines[index]
        let position = line.boundaries.lastIndex { $0 <= offset } ?? 0
        return line.textX + advances[min(position, advances.count - 1)]
    }

    /// The width of the line's text before each boundary.
    private func measuredAdvances(ofLine index: Int) -> [CGFloat] {
        if let advances = lines[index].advances { return advances }
        let boundaries = lines[index].boundaries
        let start = boundaries.first ?? 0
        let engine = UIKitScene.shared.textEngine
        let advances = boundaries.map { end -> CGFloat in
            let pieces = styledRuns(from: start, to: end)
            return pieces.isEmpty ? 0 : engine.layout(pieces, options: .default, width: nil).size.width
        }
        lines[index].advances = advances
        return advances
    }

    /// The runs' text between two UTF-16 offsets, in the runs' fonts. Spaces at the end are
    /// measured as no-break spaces: a line's trailing spaces hang, so they would measure nothing.
    private func styledRuns(from start: Int, to end: Int) -> [StyledRun] {
        guard end > start else { return [] }
        var result: [StyledRun] = []
        for (index, run) in runs.enumerated() {
            let runStart = runStarts[index], runEnd = runStart + run.string.utf16.count
            let from = max(start, runStart), to = min(end, runEnd)
            guard from < to else { continue }
            let utf16 = Array(run.string.utf16)
            result.append(StyledRun(String(decoding: utf16[(from - runStart)..<(to - runStart)], as: UTF16.self), font: run.font))
        }
        for index in result.indices.reversed() {
            let text = result[index].string
            let trailing = text.reversed().prefix { $0 == " " }.count
            if trailing > 0 { result[index].string = String(text.dropLast(trailing)) + String(repeating: "\u{00A0}", count: trailing) }
            if trailing < text.count { break }
        }
        return result
    }

    /// The character under a point and how far across it the point is.
    func character(at point: CGPoint) -> (index: Int, fraction: CGFloat) {
        guard !lines.isEmpty else { return (0, 0) }
        let row = point.y < 0 ? 0 : min(lines.count - 1, Int(point.y / max(pitch, 1)))
        let advances = measuredAdvances(ofLine: row)
        let line = lines[row]
        let across = point.x - line.textX
        let characters = line.boundaries.count - 1
        guard characters > 0 else { return (line.characters.location, 0) }
        if across <= 0 { return (line.boundaries[0], 0) }
        for k in 0..<characters where across < advances[k + 1] {
            let width = advances[k + 1] - advances[k]
            return (line.boundaries[k], width > 0 ? (across - advances[k]) / width : 0)
        }
        return (line.boundaries[characters - 1], 1)
    }
}
