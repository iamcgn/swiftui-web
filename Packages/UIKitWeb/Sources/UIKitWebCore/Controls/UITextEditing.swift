// The rest of UIKit's text editing surface that a text editor built on `UITextInput` uses
// (Runestone): text directions and the string tokenizer, the find interaction and text
// searching, the selection display interaction, the menu controller, the keyboard's shortcut
// bar and key codes. The web draws no find navigator, selection handles, edit menu bar or
// shortcut bar of its own here: these keep what the app sets and run what it calls, so a
// search the app starts finds, counts and decorates its results.
import WebFoundation   // `Selector` where there is no Objective-C runtime

// MARK: - Directions and the tokenizer

/// A direction in a text input's document: a storage direction or a layout direction.
public struct UITextDirection: RawRepresentable, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static func storage(_ direction: UITextStorageDirection) -> UITextDirection { UITextDirection(rawValue: direction.rawValue) }
    public static func layout(_ direction: UITextLayoutDirection) -> UITextDirection { UITextDirection(rawValue: direction.rawValue) }

    /// Whether the direction runs towards the document's end (forward, right or down).
    var isForward: Bool {
        rawValue == UITextStorageDirection.forward.rawValue || rawValue == UITextLayoutDirection.right.rawValue || rawValue == UITextLayoutDirection.down.rawValue
    }
}

/// Finds the boundaries of characters, words, sentences, lines and paragraphs in a text input.
@preconcurrency @MainActor
public protocol UITextInputTokenizer: AnyObject {
    func rangeEnclosingPosition(_ position: UITextPosition, with granularity: UITextGranularity, inDirection direction: UITextDirection) -> UITextRange?
    func isPosition(_ position: UITextPosition, atBoundary granularity: UITextGranularity, inDirection direction: UITextDirection) -> Bool
    func position(from position: UITextPosition, toBoundary granularity: UITextGranularity, inDirection direction: UITextDirection) -> UITextPosition?
    func isPosition(_ position: UITextPosition, withinTextUnit granularity: UITextGranularity, inDirection direction: UITextDirection) -> Bool
}

/// The tokenizer over a text input's string: words are runs of letters, digits and
/// underscores, lines and paragraphs end at a newline, sentences after `.`, `!` or `?`.
/// Offsets are the input's own (`offset(from:to:)`), counted in UTF-16 as UIKit's are.
@preconcurrency @MainActor
open class UITextInputStringTokenizer: UITextInputTokenizer {
    private weak var input: (any UITextInput)?

    public init(textInput: UIResponder & UITextInput) { input = textInput }
    init(input: any UITextInput) { self.input = input }

    /// The document as characters with their UTF-16 offsets, and the units of a granularity.
    private struct Document {
        var starts: [Int]      // UTF-16 offset of each character, then the end
        var characters: [Character]

        init(_ text: String) {
            characters = Array(text)
            starts = [0]
            starts.reserveCapacity(characters.count + 1)
            var offset = 0
            for character in characters {
                offset += character.utf16.count
                starts.append(offset)
            }
        }

        /// The character index at a UTF-16 offset (the next character's for an offset inside one).
        func index(of offset: Int) -> Int {
            var low = 0, high = starts.count - 1
            while low < high {
                let mid = (low + high) / 2
                if starts[mid] < offset { low = mid + 1 } else { high = mid }
            }
            return low
        }

        /// The units of a granularity, as UTF-16 ranges in document order.
        func units(_ granularity: UITextGranularity) -> [Range<Int>] {
            let count = characters.count
            func utf16(_ range: Range<Int>) -> Range<Int> { starts[range.lowerBound]..<starts[range.upperBound] }
            switch granularity {
            case .character:
                return (0..<count).map { utf16($0..<($0 + 1)) }
            case .document:
                return [utf16(0..<count)]
            case .word:
                var units: [Range<Int>] = []
                var start: Int?
                for (i, c) in characters.enumerated() {
                    let isWord = c.isLetter || c.isNumber || c == "_"
                    if isWord, start == nil { start = i }
                    if !isWord, let s = start { units.append(utf16(s..<i)); start = nil }
                }
                if let s = start { units.append(utf16(s..<count)) }
                return units
            case .line, .paragraph:
                var units: [Range<Int>] = []
                var start = 0
                for (i, c) in characters.enumerated() where c.isNewline {
                    units.append(utf16(start..<i))
                    start = i + 1
                }
                units.append(utf16(start..<count))
                return units
            case .sentence:
                var units: [Range<Int>] = []
                var start = 0, i = 0
                while i < count {
                    let c = characters[i]
                    if c == "." || c == "!" || c == "?" || c.isNewline {
                        var end = i + 1
                        while end < count, characters[end].isWhitespace { end += 1 }
                        units.append(utf16(start..<(i + 1)))
                        start = end
                        i = end
                    } else {
                        i += 1
                    }
                }
                if start < count { units.append(utf16(start..<count)) }
                return units
            }
        }
    }

    private func context(_ position: UITextPosition) -> (input: any UITextInput, offset: Int, document: Document)? {
        guard let input else { return nil }
        let offset = input.offset(from: input.beginningOfDocument, to: position)
        return (input, offset, Document(input.wholeText))
    }

    private func unit(around offset: Int, in units: [Range<Int>], forward: Bool) -> Range<Int>? {
        units.first { forward ? ($0.lowerBound <= offset && offset < $0.upperBound) : ($0.lowerBound < offset && offset <= $0.upperBound) }
    }

    open func rangeEnclosingPosition(_ position: UITextPosition, with granularity: UITextGranularity, inDirection direction: UITextDirection) -> UITextRange? {
        guard let c = context(position),
              let unit = unit(around: c.offset, in: c.document.units(granularity), forward: direction.isForward) else { return nil }
        return c.input.range(fromOffset: unit.lowerBound, toOffset: unit.upperBound)
    }

    open func isPosition(_ position: UITextPosition, atBoundary granularity: UITextGranularity, inDirection direction: UITextDirection) -> Bool {
        guard let c = context(position) else { return false }
        let forward = direction.isForward
        return c.document.units(granularity).contains { (forward ? $0.upperBound : $0.lowerBound) == c.offset }
    }

    open func position(from position: UITextPosition, toBoundary granularity: UITextGranularity, inDirection direction: UITextDirection) -> UITextPosition? {
        guard let c = context(position) else { return nil }
        let offset = c.offset, units = c.document.units(granularity)
        let target: Int?
        if direction.isForward {
            target = units.map(\.upperBound).filter { $0 > offset }.min()
        } else {
            target = units.map(\.lowerBound).filter { $0 < offset }.max()
        }
        guard let target else { return nil }
        return c.input.position(from: c.input.beginningOfDocument, offset: target)
    }

    open func isPosition(_ position: UITextPosition, withinTextUnit granularity: UITextGranularity, inDirection direction: UITextDirection) -> Bool {
        guard let c = context(position) else { return false }
        return unit(around: c.offset, in: c.document.units(granularity), forward: direction.isForward) != nil
    }
}

// MARK: - Find and text searching (iOS 16)

/// A document of a searchable object; nil for one with a single document.
public typealias UITextSearchDocumentIdentifier = AnyHashable?

/// How a search compares: whole words or parts of them, and the string comparison options.
public struct UITextSearchOptions: Sendable {
    public enum WordMatchMethod: Int, Sendable { case contains = 0, startsWith, fullWord }
    public var wordMatchMethod: WordMatchMethod = .contains
    public var stringCompareOptions: String.CompareOptions = []
    public init() {}
}

/// How a found range is drawn: normally, as a result, or as the highlighted result.
public enum UITextSearchFoundTextStyle: Int, Sendable { case normal = 0, found, highlighted }

/// Collects the ranges a search finds, as the searchable object reports them.
@preconcurrency @MainActor
public protocol UITextSearchAggregator<DocumentIdentifier>: AnyObject {
    associatedtype DocumentIdentifier: Hashable = AnyHashable?
    func foundRange(_ range: UITextRange, searchString string: String, document: DocumentIdentifier?)
    func invalidateFoundRange(_ range: UITextRange, document: DocumentIdentifier?)
    func invalidate()
    func finishedSearching()
}

/// An object whose text a find session searches: it finds, compares and decorates ranges.
@preconcurrency @MainActor
public protocol UITextSearching: AnyObject {
    var selectedTextRange: UITextRange? { get }
    func compare(_ foundRange: UITextRange, toRange: UITextRange, document: UITextSearchDocumentIdentifier?) -> ComparisonResult
    func performTextSearch(queryString: String, options: UITextSearchOptions, resultAggregator: any UITextSearchAggregator<AnyHashable?>)
    func decorate(foundTextRange: UITextRange, document: UITextSearchDocumentIdentifier?, usingStyle style: UITextSearchFoundTextStyle)
    func clearAllDecoratedFoundText()
    var supportsTextReplacement: Bool { get }
    func shouldReplace(foundTextRange: UITextRange, document: UITextSearchDocumentIdentifier?, withText replacementText: String) -> Bool
    func replace(foundTextRange: UITextRange, document: UITextSearchDocumentIdentifier?, withText replacementText: String)
    func replaceAll(queryString: String, options: UITextSearchOptions, withText replacementText: String)
    func willHighlight(foundTextRange: UITextRange, document: UITextSearchDocumentIdentifier?)
    func scrollRangeToVisible(_ range: UITextRange, inDocument document: UITextSearchDocumentIdentifier?)
    var selectedTextSearchDocument: UITextSearchDocumentIdentifier? { get }
    func compareOrderFromDocument(_ fromDocument: UITextSearchDocumentIdentifier?, toDocument: UITextSearchDocumentIdentifier?) -> ComparisonResult
}

extension UITextSearching {
    public var supportsTextReplacement: Bool { false }
    public func shouldReplace(foundTextRange: UITextRange, document: UITextSearchDocumentIdentifier?, withText replacementText: String) -> Bool { true }
    public func replace(foundTextRange: UITextRange, document: UITextSearchDocumentIdentifier?, withText replacementText: String) {}
    public func replaceAll(queryString: String, options: UITextSearchOptions, withText replacementText: String) {}
    public func willHighlight(foundTextRange: UITextRange, document: UITextSearchDocumentIdentifier?) {}
    public func scrollRangeToVisible(_ range: UITextRange, inDocument document: UITextSearchDocumentIdentifier?) {}
    public var selectedTextSearchDocument: UITextSearchDocumentIdentifier? { nil }
    public func compareOrderFromDocument(_ fromDocument: UITextSearchDocumentIdentifier?, toDocument: UITextSearchDocumentIdentifier?) -> ComparisonResult { .orderedSame }
}

/// A find session: runs searches and replacements and steps through the results.
@preconcurrency @MainActor
open class UIFindSession {
    public enum SearchResultDisplayStyle: Int, Sendable { case currentAndTotal = 0, total, none }

    public init() {}
    open var resultCount: Int { 0 }
    open var highlightedResultIndex: Int { 0 }
    open var searchResultDisplayStyle: SearchResultDisplayStyle = .currentAndTotal
    open var supportsReplacement: Bool { false }
    open var allowsReplacementForCurrentlyHighlightedResult: Bool { supportsReplacement }
    open func performSearch(query: String, options: UITextSearchOptions?) {}
    open func performSingleReplacement(query: String, replacementString: String, options: UITextSearchOptions?) {}
    open func replaceAll(queryString query: String, replacementString: String, options: UITextSearchOptions?) {}
    open func highlightNextResult(in direction: UITextStorageDirection) {}
    open func invalidateFoundResults() {}
}

/// The ranges a text searching session found, in the order the object reported them.
@preconcurrency @MainActor
final class _FindSessionAggregator: UITextSearchAggregator {
    typealias DocumentIdentifier = AnyHashable?
    var found: [(range: UITextRange, document: AnyHashable?)] = []
    var finished = false
    func foundRange(_ range: UITextRange, searchString string: String, document: AnyHashable??) { found.append((range, document ?? nil)) }
    func invalidateFoundRange(_ range: UITextRange, document: AnyHashable??) { found.removeAll { $0.range == range } }
    func invalidate() { found.removeAll() }
    func finishedSearching() { finished = true }
}

/// A find session over a `UITextSearching` object: a search collects its results, which are
/// decorated as found, and stepping through them highlights one at a time.
@preconcurrency @MainActor
open class UITextSearchingFindSession: UIFindSession {
    open weak var searchableObject: (any UITextSearching)?
    private var aggregator = _FindSessionAggregator()
    private var highlighted: Int?
    private var lastQuery: (String, UITextSearchOptions)?

    public init(searchableObject: any UITextSearching) {
        self.searchableObject = searchableObject
        super.init()
    }

    open override var resultCount: Int { aggregator.found.count }
    open override var highlightedResultIndex: Int { highlighted ?? 0 }
    open override var supportsReplacement: Bool { searchableObject?.supportsTextReplacement ?? false }

    open override func performSearch(query: String, options: UITextSearchOptions?) {
        guard let object = searchableObject else { return }
        let options = options ?? UITextSearchOptions()
        object.clearAllDecoratedFoundText()
        aggregator = _FindSessionAggregator()
        highlighted = nil
        lastQuery = (query, options)
        object.performTextSearch(queryString: query, options: options, resultAggregator: aggregator)
        for result in aggregator.found { object.decorate(foundTextRange: result.range, document: result.document, usingStyle: .found) }
        // The first result at or after the selection is the highlighted one.
        guard !aggregator.found.isEmpty else { return }
        var first = 0
        if let selection = object.selectedTextRange,
           let index = aggregator.found.firstIndex(where: { object.compare($0.range, toRange: selection, document: $0.document) != .orderedAscending }) {
            first = index
        }
        highlight(first)
    }

    open override func highlightNextResult(in direction: UITextStorageDirection) {
        let count = aggregator.found.count
        guard count > 0 else { return }
        guard let current = highlighted else { highlight(0); return }
        highlight(direction == .forward ? (current + 1) % count : (current - 1 + count) % count)
    }

    private func highlight(_ index: Int) {
        guard let object = searchableObject else { return }
        if let previous = highlighted, aggregator.found.indices.contains(previous) {
            let result = aggregator.found[previous]
            object.decorate(foundTextRange: result.range, document: result.document, usingStyle: .found)
        }
        highlighted = index
        let result = aggregator.found[index]
        object.willHighlight(foundTextRange: result.range, document: result.document)
        object.decorate(foundTextRange: result.range, document: result.document, usingStyle: .highlighted)
        object.scrollRangeToVisible(result.range, inDocument: result.document)
    }

    open override func performSingleReplacement(query: String, replacementString: String, options: UITextSearchOptions?) {
        guard let object = searchableObject, object.supportsTextReplacement else { return }
        if lastQuery?.0 != query || highlighted == nil { performSearch(query: query, options: options) }
        guard let index = highlighted, aggregator.found.indices.contains(index) else { return }
        let result = aggregator.found[index]
        guard object.shouldReplace(foundTextRange: result.range, document: result.document, withText: replacementString) else { return }
        object.replace(foundTextRange: result.range, document: result.document, withText: replacementString)
        performSearch(query: query, options: options)
    }

    open override func replaceAll(queryString query: String, replacementString: String, options: UITextSearchOptions?) {
        guard let object = searchableObject, object.supportsTextReplacement else { return }
        object.replaceAll(queryString: query, options: options ?? UITextSearchOptions(), withText: replacementString)
        performSearch(query: query, options: options)
    }

    open override func invalidateFoundResults() {
        searchableObject?.clearAllDecoratedFoundText()
        aggregator = _FindSessionAggregator()
        highlighted = nil
    }
}

/// Gives the find interaction its session, and is told when a session begins and ends.
@preconcurrency @MainActor
public protocol UIFindInteractionDelegate: AnyObject {
    func findInteraction(_ interaction: UIFindInteraction, sessionFor view: UIView) -> UIFindSession?
    func findInteraction(_ interaction: UIFindInteraction, didBegin session: UIFindSession)
    func findInteraction(_ interaction: UIFindInteraction, didEnd session: UIFindSession)
}

extension UIFindInteractionDelegate {
    public func findInteraction(_ interaction: UIFindInteraction, didBegin session: UIFindSession) {}
    public func findInteraction(_ interaction: UIFindInteraction, didEnd session: UIFindSession) {}
}

/// Find (and replace) in a view. The web shows no find navigator: presenting one begins a
/// session from the delegate, and the search text the app sets is searched in it.
@preconcurrency @MainActor
open class UIFindInteraction: UIInteraction {
    open weak var delegate: (any UIFindInteractionDelegate)?
    public private(set) weak var view: UIView?
    open private(set) var activeFindSession: UIFindSession?
    open var isFindNavigatorVisible: Bool { activeFindSession != nil }
    open var searchText: String? {
        didSet { if let searchText, let session = activeFindSession { session.performSearch(query: searchText, options: nil) } }
    }
    open var replacementText: String?
    open var optionsMenuProvider: (([UIMenuElement]) -> UIMenu?)?

    public init(sessionDelegate: any UIFindInteractionDelegate) { delegate = sessionDelegate }

    open func willMove(to view: UIView?) {}
    open func didMove(to view: UIView?) { self.view = view }

    open func presentFindNavigator(showingReplace: Bool) {
        guard activeFindSession == nil, let view, let session = delegate?.findInteraction(self, sessionFor: view) else { return }
        activeFindSession = session
        delegate?.findInteraction(self, didBegin: session)
        if let searchText, !searchText.isEmpty { session.performSearch(query: searchText, options: nil) }
    }

    open func dismissFindNavigator() {
        guard let session = activeFindSession else { return }
        session.invalidateFoundResults()
        activeFindSession = nil
        delegate?.findInteraction(self, didEnd: session)
    }

    open func findNext() { activeFindSession?.highlightNextResult(in: .forward) }
    open func findPrevious() { activeFindSession?.highlightNextResult(in: .backward) }
    open func updateResultCount() {}
}

// MARK: - Selection display (iOS 17)

/// Supplies the view the selection highlight is drawn below text in.
@preconcurrency @MainActor
public protocol UITextSelectionDisplayInteractionDelegate: AnyObject {
    func selectionContainerViewBelowText(for interaction: UITextSelectionDisplayInteraction) -> UIView
}

extension UITextSelectionDisplayInteractionDelegate {
    public func selectionContainerViewBelowText(for interaction: UITextSelectionDisplayInteraction) -> UIView {
        interaction.view ?? UIView()
    }
}

/// The system's cursor, selection highlight and handles for a text input. The web draws none of
/// its own here (an app's input draws its caret, `paintsCaret`); activation and updates are kept.
@preconcurrency @MainActor
open class UITextSelectionDisplayInteraction: UIResponderBase, UIInteraction {
    open weak var textInput: (any UITextInput)?
    open weak var delegate: (any UITextSelectionDisplayInteractionDelegate)?
    public private(set) weak var view: UIView?
    open var isActivated = false
    open var cursorView = UIView()
    open var highlightView = UIView()
    open var handleViews: [UIView] = []

    public init(textInput: any UITextInput, delegate: any UITextSelectionDisplayInteractionDelegate) {
        self.textInput = textInput
        self.delegate = delegate
        super.init()
    }

    open func willMove(to view: UIView?) {}
    open func didMove(to view: UIView?) { self.view = view }
    open func setNeedsSelectionUpdate() {}
    open func layoutManagedSubviews() {}
}

// MARK: - The menu controller

/// A custom item of the edit menu (`UIMenuController.menuItems`), sent down the responder chain.
@preconcurrency @MainActor
open class UIMenuItem {
    open var title: String
    open var action: Selector
    public init(title: String, action: Selector) {
        self.title = title
        self.action = action
    }
}

/// The edit menu of iOS 15 and earlier (`UIEditMenuInteraction` replaces it). The web shows no
/// menu from it: showing and hiding keep `isMenuVisible`, and the items are kept.
@preconcurrency @MainActor
open class UIMenuController {
    public enum ArrowDirection: Int, Sendable { case `default` = 0, up, down, left, right }

    public static let shared = UIMenuController()
    nonisolated public static let willShowMenuNotification = NSNotification.Name("UIMenuControllerWillShowMenuNotification")
    nonisolated public static let didShowMenuNotification = NSNotification.Name("UIMenuControllerDidShowMenuNotification")
    nonisolated public static let willHideMenuNotification = NSNotification.Name("UIMenuControllerWillHideMenuNotification")
    nonisolated public static let didHideMenuNotification = NSNotification.Name("UIMenuControllerDidHideMenuNotification")

    open var menuItems: [UIMenuItem]?
    open var arrowDirection: ArrowDirection = .default
    open private(set) var isMenuVisible = false
    open private(set) var menuFrame: CGRect = .zero

    public init() {}

    open func showMenu(from targetView: UIView, rect targetRect: CGRect) {
        menuFrame = targetView.convert(targetRect, to: nil)
        isMenuVisible = true
    }
    open func hideMenu(from targetView: UIView) { isMenuVisible = false }
    open func hideMenu() { isMenuVisible = false }
    open func update() {}
    open func setTargetRect(_ targetRect: CGRect, in targetView: UIView) { menuFrame = targetView.convert(targetRect, to: nil) }
    open func setMenuVisible(_ menuVisible: Bool, animated: Bool) { isMenuVisible = menuVisible }
}

// MARK: - The keyboard's shortcut bar and key codes

/// A group of bar button items, as the keyboard's shortcut bar and toolbars take them.
@preconcurrency @MainActor
open class UIBarButtonItemGroup {
    open var barButtonItems: [UIBarButtonItem]
    open var representativeItem: UIBarButtonItem?
    open var isHidden = false
    public init(barButtonItems: [UIBarButtonItem], representativeItem: UIBarButtonItem?) {
        self.barButtonItems = barButtonItems
        self.representativeItem = representativeItem
    }
}

/// The shortcut bar above the keyboard (iPad). The web shows none: the groups are kept.
@preconcurrency @MainActor
open class UITextInputAssistantItem {
    open var allowsHidingShortcuts = true
    open var leadingBarButtonGroups: [UIBarButtonItemGroup] = []
    open var trailingBarButtonGroups: [UIBarButtonItemGroup] = []
    open var keyboardActionButtonItem: UIBarButtonItem?
    public init() {}
}

/// A key's USB HID usage (`UIKey.keyCode`): the letters, digits, editing and arrow keys.
public enum UIKeyboardHIDUsage: Int, Sendable {
    case keyboardErrorRollOver = 0x01
    case keyboardA = 0x04, keyboardB, keyboardC, keyboardD, keyboardE, keyboardF, keyboardG, keyboardH, keyboardI, keyboardJ,
         keyboardK, keyboardL, keyboardM, keyboardN, keyboardO, keyboardP, keyboardQ, keyboardR, keyboardS, keyboardT,
         keyboardU, keyboardV, keyboardW, keyboardX, keyboardY, keyboardZ
    case keyboard1 = 0x1E, keyboard2, keyboard3, keyboard4, keyboard5, keyboard6, keyboard7, keyboard8, keyboard9, keyboard0
    case keyboardReturnOrEnter = 0x28, keyboardEscape, keyboardDeleteOrBackspace, keyboardTab, keyboardSpacebar,
         keyboardHyphen, keyboardEqualSign, keyboardOpenBracket, keyboardCloseBracket, keyboardBackslash, keyboardNonUSPound,
         keyboardSemicolon, keyboardQuote, keyboardGraveAccentAndTilde, keyboardComma, keyboardPeriod, keyboardSlash, keyboardCapsLock
    case keyboardF1 = 0x3A, keyboardF2, keyboardF3, keyboardF4, keyboardF5, keyboardF6, keyboardF7, keyboardF8, keyboardF9,
         keyboardF10, keyboardF11, keyboardF12
    case keyboardInsert = 0x49, keyboardHome, keyboardPageUp, keyboardDeleteForward, keyboardEnd, keyboardPageDown,
         keyboardRightArrow, keyboardLeftArrow, keyboardDownArrow, keyboardUpArrow
    case keyboardLeftControl = 0xE0, keyboardLeftShift, keyboardLeftAlt, keyboardLeftGUI,
         keyboardRightControl, keyboardRightShift, keyboardRightAlt, keyboardRightGUI
}

extension UIKey {
    /// The key's HID usage, from the host's key and characters (the error code for a key with
    /// no usage here).
    public var keyCode: UIKeyboardHIDUsage {
        switch key {
        case .upArrow: return .keyboardUpArrow
        case .downArrow: return .keyboardDownArrow
        case .leftArrow: return .keyboardLeftArrow
        case .rightArrow: return .keyboardRightArrow
        case .escape: return .keyboardEscape
        case .delete: return .keyboardDeleteOrBackspace
        case .deleteForward: return .keyboardDeleteForward
        case .return: return .keyboardReturnOrEnter
        case .tab: return .keyboardTab
        case .space: return .keyboardSpacebar
        case .home: return .keyboardHome
        case .end: return .keyboardEnd
        case .pageUp: return .keyboardPageUp
        case .pageDown: return .keyboardPageDown
        default: break
        }
        guard let scalar = charactersIgnoringModifiers.lowercased().unicodeScalars.first else { return .keyboardErrorRollOver }
        switch scalar {
        case "a"..."z": return UIKeyboardHIDUsage(rawValue: 0x04 + Int(scalar.value - 97)) ?? .keyboardErrorRollOver
        case "1"..."9": return UIKeyboardHIDUsage(rawValue: 0x1E + Int(scalar.value - 49)) ?? .keyboardErrorRollOver
        case "0": return .keyboard0
        case "-": return .keyboardHyphen
        case "=": return .keyboardEqualSign
        case "[": return .keyboardOpenBracket
        case "]": return .keyboardCloseBracket
        case "\\": return .keyboardBackslash
        case ";": return .keyboardSemicolon
        case "'": return .keyboardQuote
        case "`": return .keyboardGraveAccentAndTilde
        case ",": return .keyboardComma
        case ".": return .keyboardPeriod
        case "/": return .keyboardSlash
        default: return .keyboardErrorRollOver
        }
    }
}
