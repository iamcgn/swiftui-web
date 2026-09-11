// UISearchBar (Docs/elements/UIKit/Bars.md): the iOS 26 search bar, 64 tall, holding a 44 pt
// glass capsule field 8 in and 10 down with a magnifier 12 in and 17 pt medium text 39.5 in;
// a Cancel button is a 44 pt glass circle with a cross at the right, the field ending 11 before
// it. The default style draws a faint band with hairlines; the minimal style draws no band and
// no capsule. Measured on the iPhone SE simulator (uikit/search/basic).

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
}

extension UISearchBarDelegate {
    public func searchBarShouldBeginEditing(_ searchBar: UISearchBar) -> Bool { true }
    public func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {}
    public func searchBarShouldEndEditing(_ searchBar: UISearchBar) -> Bool { true }
    public func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {}
    public func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {}
    public func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {}
    public func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {}
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

    open var text: String? {
        get { searchTextField.text }
        set { searchTextField.text = newValue }
    }
    open var placeholder: String? {
        get { searchTextField.placeholder }
        set { searchTextField.placeholder = newValue }
    }
    open var prompt: String?
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

    /// The text field the bar edits (public since iOS 13).
    public let searchTextField = UISearchTextField()
    private let cancelButton = SearchCancelButton()
    /// A navigation controller hosts the field in its floating bar (uikit/nav/search): the bar
    /// itself stays a 60 pt empty band under the navigation bar.
    var hostsFieldExternally = false { didSet { setNeedsLayout(); setNeedsDisplay() } }
    static let navigationHeight: CGFloat = 60

    public override init(frame: CGRect) {
        super.init(frame: CGRect(origin: frame.origin, size: CGSize(width: frame.width, height: frame.height > 0 ? frame.height : Self.height)))
        searchTextField.searchBar = self
        addSubview(searchTextField)
        cancelButton.isHidden = true
        cancelButton.addAction(UIAction { [weak self] _ in self?.cancel() }, for: .primaryActionTriggered)
        addSubview(cancelButton)
    }

    open func setShowsCancelButton(_ showsCancelButton: Bool, animated: Bool) { self.showsCancelButton = showsCancelButton }

    private func cancel() {
        if searchTextField.isFirstResponder { _ = searchTextField.resignFirstResponder() }
        delegate?.searchBarCancelButtonClicked(self)
    }

    @discardableResult
    override open func becomeFirstResponder() -> Bool { searchTextField.becomeFirstResponder() }
    @discardableResult
    override open func resignFirstResponder() -> Bool { searchTextField.resignFirstResponder() }
    override open var isFirstResponder: Bool { searchTextField.isFirstResponder }

    override open func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width < CGFloat.greatestFiniteMagnitude ? size.width : bounds.width, height: Self.height) }
    override open var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: Self.height) }

    override open func layoutSubviews() {
        super.layoutSubviews()
        guard !hostsFieldExternally else { return }
        if searchTextField.superview !== self { addSubview(searchTextField) }
        let cancelWidth = showsCancelButton ? Self.fieldHeight + Self.cancelGap : 0
        searchTextField.frame = CGRect(x: Self.fieldInset, y: Self.fieldTop, width: bounds.width - 2 * Self.fieldInset - cancelWidth, height: Self.fieldHeight)
        cancelButton.frame = CGRect(x: bounds.width - Self.fieldInset - Self.fieldHeight, y: Self.fieldTop, width: Self.fieldHeight, height: Self.fieldHeight)
    }

    /// The default style's band: a faint fill with 0.5 pt hairlines top and bottom.
    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        guard searchBarStyle != .minimal, !hostsFieldExternally else { return }
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        let band: RGBA = style == .dark ? RGBA(r: 28, g: 28, b: 30) : RGBA(r: 252, g: 252, b: 252)
        list.append(.fillRect(rect, barTintColor?.rgba(for: style) ?? band))
        let hairline: RGBA = style == .dark ? RGBA(r: 255, g: 255, b: 255, a: 0.15) : RGBA(r: 0, g: 0, b: 0, a: 0.1)
        list.append(.fillRect(CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: 0.5), hairline))
        list.append(.fillRect(CGRect(x: rect.minX, y: rect.maxY - 0.5, width: rect.width, height: 0.5), hairline))
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
    }

    override open func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: UISearchBar.fieldHeight) }
    override open var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: UISearchBar.fieldHeight) }

    /// The text starts 39.5 in (after the magnifier) and ends 8 before the capsule's edge.
    override open func textRect(forBounds bounds: CGRect) -> CGRect {
        let line = (font ?? .systemFont(ofSize: 17)).lineHeight
        return CGRect(x: bounds.minX + textInset, y: bounds.minY + ((bounds.height - line) / 2).rounded(),
                      width: max(0, bounds.width - textInset - 8), height: line.roundedUp(to: UIScreen.main.scale))
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
        super.drawContent(into: &list, context: context, style: style)
    }
}

/// The search bar's Cancel button: a 44 pt glass circle with a light cross.
@MainActor
final class SearchCancelButton: UIControl {
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
        let ink: RGBA = style == .dark ? RGBA(r: 110, g: 110, b: 115) : RGBA(r: 184, g: 184, b: 184)
        SymbolPainter.paint(name: "xmark", in: context.absoluteRect(CGRect(x: 10.5, y: 11, width: 22.5, height: 21.5)), color: ink, weight: 400, into: &list)
    }
}

/// The methods a search results updater implements.
@MainActor
public protocol UISearchResultsUpdating: AnyObject {
    func updateSearchResults(for searchController: UISearchController)
}

/// A view controller that manages the display of search results based on interactions with a
/// search bar; in a navigation item the bar shows under the title (Containers/UINavigationController.swift).
@MainActor
open class UISearchController: UIViewController {
    public let searchBar = UISearchBar()
    public let searchResultsController: UIViewController?
    open weak var searchResultsUpdater: (any UISearchResultsUpdating)?
    open var obscuresBackgroundDuringPresentation = true
    open var hidesNavigationBarDuringPresentation = true
    open var automaticallyShowsCancelButton = true
    open var showsSearchResultsController = false
    open private(set) var isActive = false

    public init(searchResultsController: UIViewController? = nil) {
        self.searchResultsController = searchResultsController
        super.init(nibName: nil, bundle: nil)
        searchBar.searchBarStyle = .minimal
        searchBar.searchTextField.searchController = self
    }

    /// Typing (or focus) activates the controller and asks the updater for results.
    func searchDidChange() {
        if !isActive, searchBar.isFirstResponder { isActive = true }
        searchResultsUpdater?.updateSearchResults(for: self)
    }

    func searchDidEnd() {
        isActive = false
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
