// UISearchBar (Docs/elements/UIKit/Bars.md): the iOS 26 search bar, 64 tall, holding a 44 pt
// glass capsule field 8 in and 10 down with a magnifier 12 in and 17 pt medium text 39.5 in;
// a Cancel button is a 44 pt glass circle with a cross at the right, the field ending 11 before
// it. The default style draws a faint band with hairlines; the minimal style draws no band and
// no capsule. A prompt adds a 34 pt band above the field with a centred 14 pt label; the bookmark
// (or results list) button sits at the field's end while it has no text, the clear button once
// it edits (uikit/search/looks). Measured on the iPhone SE simulator (uikit/search/basic).

/// The methods a search bar's delegate implements.
@MainActor
public protocol UISearchBarDelegate: AnyObject {
    func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool
    func searchBarTextDidBeginEditing(_ searchBar: UISearchBar)
    func searchBarShouldEndEditing(_ searchBar: UISearchBar) -> Bool
    func searchBarTextDidEndEditing(_ searchBar: UISearchBar)
    func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String)
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar)
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar)
    func searchBarBookmarkButtonClicked(_ searchBar: UISearchBar)
    func searchBarResultsListButtonClicked(_ searchBar: UISearchBar)
    func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int)
}

extension UISearchBarDelegate {
    public func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool { true }
    public func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {}
    public func searchBarShouldEndEditing(_ searchBar: UISearchBar) -> Bool { true }
    public func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {}
    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {}
    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {}
    public func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {}
    public func searchBarBookmarkButtonClicked(_ searchBar: UISearchBar) {}
    public func searchBarResultsListButtonClicked(_ searchBar: UISearchBar) {}
    public func searchBar(_ searchBar: UISearchBar, selectedScopeButtonIndexDidChange selectedScope: Int) {}
}

/// A specialized view for receiving search-related information from the user.
@MainActor
open class UISearchBar: UIView {
    public enum Style: Int, Sendable { case `default` = 0, prominent, minimal }

    static let height: CGFloat = 64
    static let fieldInset: CGFloat = 8
    static let fieldTop: CGFloat = 10
    static let fieldHeight: CGFloat = 44
    static let cancelGap: CGFloat = 11
    /// The scope bar under the field (uikit/search/scope): a 47 pt band holding a segmented
    /// control 8 in, 7 down (71 in the 111 pt bar), 8 above the bar's end; 15 pt titles.
    static let scopeInset: CGFloat = 8
    static let scopeGap: CGFloat = 7
    static let scopeBottom: CGFloat = 8
    /// The prompt's band above the field (uikit/search/looks): 34 tall, its 14 pt label 8 down.
    static let promptHeight: CGFloat = 34

    open var text: String? {
        get { searchTextField.text }
        set {
            searchTextField.text = newValue
            searchTextField.searchController?.searchDidChange()
        }
    }
    open var placeholder: String? {
        get { searchTextField.placeholder }
        set { searchTextField.placeholder = newValue }
    }
    open var prompt: String? { didSet { invalidateIntrinsicContentSize(); setNeedsLayout(); setNeedsDisplay() } }
    /// The bookmark (or results list) button at the field's end while it holds no text.
    open var showsBookmarkButton = false { didSet { searchTextField.setNeedsDisplay() } }
    open var showsSearchResultsButton = false { didSet { searchTextField.setNeedsDisplay() } }
    open var isSearchResultsButtonSelected = false
    open var searchBarStyle: Style = .default { didSet { searchTextField.showsCapsule = searchBarStyle != .minimal; setNeedsDisplay() } }
    open var showsCancelButton = false { didSet { cancelButton.isHidden = !showsCancelButton; setNeedsLayout() } }
    open var barTintColor: UIColor?
    open var isTranslucent = true
    open var barStyle = 0
    open var returnKeyType: UIReturnKeyType {
        get { searchTextField.returnKeyType }
        set { searchTextField.returnKeyType = newValue }
    }
    open var keyboardType: UIKeyboardType {
        get { searchTextField.keyboardType }
        set { searchTextField.keyboardType = newValue }
    }
    open var autocapitalizationType: UITextAutocapitalizationType {
        get { searchTextField.autocapitalizationType }
        set { searchTextField.autocapitalizationType = newValue }
    }
    open var autocorrectionType: UITextAutocorrectionType {
        get { searchTextField.autocorrectionType }
        set { searchTextField.autocorrectionType = newValue }
    }
    open weak var delegate: (any UISearchBarDelegate)?

    /// The scope bar: segment titles shown under the field while `showsScopeBar` is set.
    open var scopeButtonTitles: [String]? {
        didSet { rebuildScopeBar() }
    }
    open var showsScopeBar = false { didSet { scopeBar.isHidden = !showsScopeBar || (scopeButtonTitles ?? []).isEmpty; invalidateIntrinsicContentSize(); setNeedsLayout() } }
    open var selectedScopeButtonIndex: Int {
        get { scopeBar.selectedSegmentIndex }
        set { scopeBar.selectedSegmentIndex = newValue }
    }
    open func setShowsScope(_ show: Bool, animated: Bool) { showsScopeBar = show }
    private let scopeBar = UISegmentedControl(items: [])

    private func rebuildScopeBar() {
        let selected = scopeBar.selectedSegmentIndex
        scopeBar.removeAllSegments()
        for (index, title) in (scopeButtonTitles ?? []).enumerated() { scopeBar.insertSegment(withTitle: title, at: index, animated: false) }
        scopeBar.selectedSegmentIndex = scopeBar.numberOfSegments > 0 ? min(max(0, selected), scopeBar.numberOfSegments - 1) : UISegmentedControl.noSegment
        scopeBar.isHidden = !showsScopeBar || scopeBar.numberOfSegments == 0
        invalidateIntrinsicContentSize()
        setNeedsLayout()
    }

    /// Whether the scope bar takes room under the field.
    private var scopeBarIsShown: Bool { showsScopeBar && !(scopeButtonTitles ?? []).isEmpty }
    private var scopeHeight: CGFloat { scopeBarIsShown ? Self.scopeGap + UISegmentedControl.height + Self.scopeBottom : 0 }
    private var promptHeight: CGFloat { prompt == nil ? 0 : Self.promptHeight }
    /// A search controller's active layout (uikit/nav/search-results): a 60 pt bar whose field
    /// starts 16 in and a 44 pt cancel circle 16 from the trailing edge, 11 after the field.
    var isActiveLayout = false {
        didSet {
            searchTextField.isInline = false
            searchTextField.showsCapsule = isActiveLayout || searchBarStyle != .minimal
            setNeedsLayout()
            setNeedsDisplay()
        }
    }

    /// The text field the bar edits (public since iOS 13).
    public let searchTextField = UISearchTextField()
    private let cancelButton = SearchCancelButton()
    /// A navigation controller hosts the field in its floating bar (uikit/nav/search): the bar
    /// itself stays a 60 pt empty band under the navigation bar.
    var hostsFieldExternally = false {
        didSet {
            if hostsFieldExternally { searchTextField.isInline = true; searchTextField.showsCapsule = false }
            setNeedsLayout()
            setNeedsDisplay()
        }
    }
    static let navigationHeight: CGFloat = 60

    public override init(frame: CGRect) {
        super.init(frame: CGRect(origin: frame.origin, size: CGSize(width: frame.width, height: frame.height > 0 ? frame.height : Self.height)))
        searchTextField.searchBar = self
        addSubview(searchTextField)
        cancelButton.isHidden = true
        cancelButton.addAction(UIAction { [weak self] _ in self?.cancel() }, for: .primaryActionTriggered)
        addSubview(cancelButton)
        scopeBar.isHidden = true
        scopeBar.titleSize = 15
        scopeBar.emphasisesSelection = false
        scopeBar.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            delegate?.searchBar(self, selectedScopeButtonIndexDidChange: scopeBar.selectedSegmentIndex)
        }, for: .valueChanged)
        addSubview(scopeBar)
    }

    open func setShowsCancelButton(_ showsCancelButton: Bool, animated: Bool) { self.showsCancelButton = showsCancelButton }

    private func cancel() {
        if searchTextField.isFirstResponder { _ = searchTextField.resignFirstResponder() }
        delegate?.searchBarCancelButtonClicked(self)
        searchTextField.searchController?.isActive = false
    }

    @discardableResult
    override open func becomeFirstResponder() -> Bool { searchTextField.becomeFirstResponder() }
    @discardableResult
    override open func resignFirstResponder() -> Bool { searchTextField.resignFirstResponder() }
    override open var isFirstResponder: Bool { searchTextField.isFirstResponder }

    override open func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width < CGFloat.greatestFiniteMagnitude ? size.width : bounds.width, height: Self.height + promptHeight + scopeHeight) }
    override open var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.height + promptHeight + scopeHeight) }

    override open func layoutSubviews() {
        super.layoutSubviews()
        guard !hostsFieldExternally else { return }
        if searchTextField.superview !== self { addSubview(searchTextField) }
        let inset: CGFloat = isActiveLayout ? 16 : Self.fieldInset
        let top = isActiveLayout ? 8 : promptHeight + Self.fieldTop
        let cancelShown = showsCancelButton || isActiveLayout
        cancelButton.isHidden = !cancelShown
        cancelButton.isProminent = isActiveLayout
        let cancelWidth = cancelShown ? Self.fieldHeight + Self.cancelGap : 0
        searchTextField.frame = CGRect(x: inset, y: top, width: bounds.width - 2 * inset - cancelWidth, height: Self.fieldHeight)
        cancelButton.frame = CGRect(x: bounds.width - inset - Self.fieldHeight, y: top, width: Self.fieldHeight, height: Self.fieldHeight)
        if scopeBarIsShown {
            scopeBar.frame = CGRect(x: Self.scopeInset, y: top + Self.fieldHeight + Self.scopeGap, width: bounds.width - 2 * Self.scopeInset, height: UISegmentedControl.height)
        }
    }

    /// The prompt's colour: a dark slate (43, 62, 90) on the simulator (the dark look is unverified).
    static let promptColor = UIColor(light: RGBA(r: 43, g: 62, b: 90), dark: RGBA(r: 200, g: 210, b: 230))

    /// The default style's band: a faint fill with 0.5 pt hairlines top and bottom; the prompt
    /// centred in its band above the field.
    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        guard !hostsFieldExternally, !isActiveLayout else { return }
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        if searchBarStyle != .minimal {
            let band: RGBA = style == .dark ? RGBA(r: 28, g: 28, b: 30) : RGBA(r: 252, g: 252, b: 252)
            list.append(.fillRect(rect, barTintColor?.rgba(for: style) ?? band))
            let hairline: RGBA = style == .dark ? RGBA(r: 255, g: 255, b: 255, a: 0.15) : RGBA(r: 0, g: 0, b: 0, a: 0.1)
            list.append(.fillRect(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 0.5), hairline))
            list.append(.fillRect(CGRect(x: rect.minX, y: rect.maxY - 0.5, width: rect.width, height: 0.5), hairline))
        }
        if let prompt {
            // A 14 pt label 18 tall 8 down, centred; its text centred in the label's line box.
            let font = UIFont.systemFont(ofSize: 14)
            let layout = UIKitScene.shared.textEngine.layout([StyledRun(prompt, font: font.resolved)], options: TextLayoutOptions(lineLimit: 1), width: nil)
            let width = (layout.size.width * 2).rounded(.up) / 2
            let x = rect.minX + ((bounds.width - width) / 2 * 2).rounded() / 2
            let baseline = rect.minY + 8 + ((18 - font.lineHeight) / 2 * 2).rounded() / 2 + font.ascender
            for fragment in layout.lines.first?.fragments ?? [] {
                list.append(.drawText(fragment.text, DisplayFont(font.resolved), origin: CGPoint(x: x + fragment.x, y: baseline), Self.promptColor.rgba(for: style)))
            }
        }
    }
}

/// The search bar's field: a glass capsule with a magnifier and 17 pt medium text.
@MainActor
open class UISearchTextField: UITextField {
    weak var searchBar: UISearchBar?
    weak var searchController: UISearchController?
    var showsCapsule = true { didSet { setNeedsDisplay() } }
    static let textInset: CGFloat = 39.5
    /// In a navigation controller's floating bar the field is 38 tall in a 48 pt glass capsule:
    /// the magnifier sits at (13, 8.5) and the text starts 41.5 in (uikit/nav/search).
    var isInline = false { didSet { setNeedsDisplay() } }
    private var textInset: CGFloat { isInline ? 41.5 : Self.textInset }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        font = .systemFont(ofSize: 17, weight: .medium)
        placeholderColor = .secondaryLabel
        returnKeyType = .search
        autocapitalizationType = .none
        autocorrectionType = .no
        clearButtonMode = .whileEditing
    }

    override open func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: UISearchBar.fieldHeight) }
    override open var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: UISearchBar.fieldHeight) }

    /// Whether the bar's bookmark or results list button shows: at the field's end while it
    /// holds no text (uikit/search/looks).
    var showsAccessoryButton: Bool {
        guard let searchBar, searchBar.showsBookmarkButton || searchBar.showsSearchResultsButton else { return false }
        return text?.isEmpty != false
    }
    /// The button's image: 22.5 × 17.5 at 13 down, 38.5 before the capsule's end.
    var accessoryButtonRect: CGRect { CGRect(x: bounds.width - 38.5, y: 13, width: 22.5, height: 17.5) }

    /// The text starts 39.5 in (after the magnifier) and ends 7 before the capsule's edge, 44.5
    /// before it with the clear button showing, 29.5 with the bookmark button.
    override open func textRect(forBounds bounds: CGRect) -> CGRect {
        let line = (font ?? .systemFont(ofSize: 17)).lineHeight
        let trailing: CGFloat = showsClearButton ? 44.5 : showsAccessoryButton ? 29.5 : 7
        return CGRect(x: bounds.minX + textInset, y: bounds.minY + ((bounds.height - line) / 2).rounded(),
                      width: max(0, bounds.width - textInset - trailing), height: line.roundedUp(to: UIScreen.main.scale))
    }

    /// The clear button's disc: 17 pt in a 20.5 button 34.5 before the capsule's end, 11.5 down.
    override open func clearButtonRect(forBounds bounds: CGRect) -> CGRect {
        CGRect(x: bounds.maxX - 34.5 + 1.75, y: bounds.minY + 11.5 + 1.75, width: 17, height: 17)
    }
    override var clearButtonFill: UIColor { .secondaryLabel }

    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if isEnabled, showsAccessoryButton, let touch = touches.first, accessoryButtonRect.insetBy(dx: -8, dy: -12).contains(touch.location(in: self)), let searchBar {
            if searchBar.showsBookmarkButton { searchBar.delegate?.searchBarBookmarkButtonClicked(searchBar) }
            else { searchBar.delegate?.searchBarResultsListButtonClicked(searchBar) }
            return
        }
        super.touchesEnded(touches, with: event)
    }

    override open func becomeFirstResponder() -> Bool {
        guard !isFirstResponder else { return true }
        guard searchBar.map({ $0.delegate?.searchBarShouldBeginEditing($0) ?? true }) ?? true else { return false }
        guard super.becomeFirstResponder() else { return false }
        if let searchBar { searchBar.delegate?.searchBarTextDidBeginEditing(searchBar) }
        searchController?.searchDidChange()
        return true
    }

    override open func resignFirstResponder() -> Bool {
        guard isFirstResponder else { return true }
        guard searchBar.map({ $0.delegate?.searchBarShouldEndEditing($0) ?? true }) ?? true else { return false }
        guard super.resignFirstResponder() else { return false }
        if let searchBar { searchBar.delegate?.searchBarTextDidEndEditing(searchBar) }
        searchController?.searchDidEnd()
        return true
    }

    override func hostDidChange(_ newText: String) {
        super.hostDidChange(newText)
        if let searchBar { searchBar.delegate?.searchBar(searchBar, textDidChange: newText) }
        searchController?.searchDidChange()
    }

    override func hostDidSubmit() {
        super.hostDidSubmit()
        if let searchBar { searchBar.delegate?.searchBarSearchButtonClicked(searchBar) }
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        if showsCapsule {
            let fill: RGBA = style == .dark ? RGBA(r: 44, g: 44, b: 46) : RGBA(r: 252, g: 252, b: 252)
            list.append(.beginShadow(RGBA(red: 0, green: 0, blue: 0, alpha: 0.08), radius: 10, offset: CGSize(width: 0, height: 4)))
            list.append(.fillRRect(rect, cornerRadius: rect.height / 2, fill))
            list.append(.endGroup)
        }
        let ink = UIColor.secondaryLabel.rgba(for: style)
        let magnifier = isInline ? CGRect(x: 13, y: 8.5, width: 20.5, height: 20) : CGRect(x: 12, y: 11.5, width: 20.5, height: 20)
        SymbolPainter.paint(name: "magnifyingglass", in: context.absoluteRect(magnifier), color: ink, weight: 500, into: &list)
        if showsAccessoryButton, let searchBar {
            SymbolPainter.paint(name: searchBar.showsBookmarkButton ? "book" : "list.bullet", in: context.absoluteRect(accessoryButtonRect), color: ink, weight: 500, into: &list)
        }
        super.drawContent(into: &list, context: context, style: style)
    }
}

/// The search bar's Cancel button: a 44 pt glass circle with a light cross.
@MainActor
final class SearchCancelButton: UIControl {
    var isProminent = false { didSet { setNeedsDisplay() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = "Cancel"
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        let fill: RGBA = style == .dark ? RGBA(r: 44, g: 44, b: 46) : RGBA(r: 252, g: 252, b: 252)
        list.append(.beginShadow(RGBA(red: 0, green: 0, blue: 0, alpha: 0.08), radius: 10, offset: CGSize(width: 0, height: 4)))
        list.append(.fillRRect(rect, cornerRadius: rect.height / 2, fill))
        list.append(.endGroup)
        if isProminent {
            // An active search's cancel: a dark 17 pt cross (uikit/nav/search-results).
            let ink: RGBA = style == .dark ? RGBA(r: 235, g: 235, b: 235) : RGBA(r: 25, g: 25, b: 25)
            SymbolPainter.paint(name: "xmark", in: context.absoluteRect(CGRect(x: 13, y: 13.5, width: 17, height: 17)), color: ink, weight: 600, into: &list)
            return
        }
        let ink: RGBA = style == .dark ? RGBA(r: 110, g: 110, b: 115) : RGBA(r: 184, g: 184, b: 184)
        SymbolPainter.paint(name: "xmark", in: context.absoluteRect(CGRect(x: 10.5, y: 11, width: 22.5, height: 21.5)), color: ink, weight: 400, into: &list)
    }
}

/// The methods a search results updater implements.
@MainActor
public protocol UISearchResultsUpdating: AnyObject {
    func updateSearchResults(for searchController: UISearchController)
}

/// The methods a search controller's delegate implements.
@MainActor
public protocol UISearchControllerDelegate: AnyObject {
    func willPresentSearchController(_ searchController: UISearchController)
    func didPresentSearchController(_ searchController: UISearchController)
    func willDismissSearchController(_ searchController: UISearchController)
    func didDismissSearchController(_ searchController: UISearchController)
}

extension UISearchControllerDelegate {
    public func willPresentSearchController(_ searchController: UISearchController) {}
    public func didPresentSearchController(_ searchController: UISearchController) {}
    public func willDismissSearchController(_ searchController: UISearchController) {}
    public func didDismissSearchController(_ searchController: UISearchController) {}
}

/// A view controller that manages the display of search results based on interactions with a
/// search bar; in a navigation item the bar shows under the title (Containers/UINavigationController.swift)
/// and, active, takes the navigation bar's place with the results controller's view under it.
@MainActor
open class UISearchController: UIViewController {
    public let searchBar = UISearchBar()
    public let searchResultsController: UIViewController?
    open weak var searchResultsUpdater: (any UISearchResultsUpdating)?
    open weak var delegate: (any UISearchControllerDelegate)?
    open var obscuresBackgroundDuringPresentation = true
    open var hidesNavigationBarDuringPresentation = true
    open var automaticallyShowsCancelButton = true
    /// Whether the results controller shows while the search text is empty.
    open var showsSearchResultsController = false { didSet { host?.searchPresentationDidChange() } }
    /// Set to present the search (the bar at the top with its cancel button, the results
    /// controller or a dimmed background under it) or to dismiss it.
    open var isActive = false {
        didSet {
            guard isActive != oldValue else { return }
            if isActive { delegate?.willPresentSearchController(self) } else { delegate?.willDismissSearchController(self) }
            searchBar.isActiveLayout = isActive && host != nil
            host?.searchPresentationDidChange()
            if !isActive, searchBar.isFirstResponder { _ = searchBar.resignFirstResponder() }
            searchResultsUpdater?.updateSearchResults(for: self)
            if isActive { delegate?.didPresentSearchController(self) } else { delegate?.didDismissSearchController(self) }
        }
    }
    /// The navigation controller hosting the bar in its item.
    weak var host: UINavigationController?

    public init(searchResultsController: UIViewController? = nil) {
        self.searchResultsController = searchResultsController
        super.init(nibName: nil, bundle: nil)
        searchBar.searchBarStyle = .minimal
        searchBar.searchTextField.searchController = self
    }

    /// Whether the results controller's view shows: active with text, or always when asked.
    var showsResults: Bool {
        guard isActive, searchResultsController != nil else { return false }
        return showsSearchResultsController || searchBar.text?.isEmpty == false
    }

    /// Typing (or focus) activates the controller and asks the updater for results.
    func searchDidChange() {
        if !isActive, searchBar.isFirstResponder { isActive = true; return }
        host?.searchPresentationDidChange()
        searchResultsUpdater?.updateSearchResults(for: self)
    }

    func searchDidEnd() {
        guard isActive else { searchResultsUpdater?.updateSearchResults(for: self); return }
        // The field lost focus (the keyboard went away): the search stays presented until Cancel.
        searchResultsUpdater?.updateSearchResults(for: self)
    }
}

/// The glass capsule a navigation controller's floating bar shows a search field in: 48 tall,
/// the field 38 tall 5 in (uikit/nav/search).
@MainActor
final class FloatingSearchPlatter: UIView {
    let field: UISearchTextField

    init(field: UISearchTextField) {
        self.field = field
        super.init(frame: .zero)
        field.isInline = true
        field.showsCapsule = false
        addSubview(field)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        field.frame = bounds.insetBy(dx: 5, dy: 5)
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        let fill: RGBA = style == .dark ? RGBA(r: 44, g: 44, b: 46) : RGBA(r: 252, g: 252, b: 252)
        list.append(.beginShadow(RGBA(red: 0, green: 0, blue: 0, alpha: 0.08), radius: 10, offset: CGSize(width: 0, height: 4)))
        list.append(.fillRRect(rect, cornerRadius: rect.height / 2, fill))
        list.append(.endGroup)
    }
}
