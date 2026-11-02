// UISplitViewController (uk-splitviewcontroller, Docs/elements/UIKit/Navigation.md): the
// column styles (double and triple) lay their columns side by side in a regular width — each
// column wrapped in a navigation controller as UIKit does — in the display mode the app
// prefers (beside, over or displacing the secondary), and collapse to the compact column (else
// the primary) in a compact width. Measured on the iPad simulator (uikit/split/*).
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// The methods the split view controller's delegate implements.
@preconcurrency @MainActor
public protocol UISplitViewControllerDelegate: AnyObject {
    func splitViewController(_ svc: UISplitViewController, topColumnForCollapsingToProposedTopColumn proposedTopColumn: UISplitViewController.Column) -> UISplitViewController.Column
    func splitViewController(_ svc: UISplitViewController, displayModeForExpandingToProposedDisplayMode proposedDisplayMode: UISplitViewController.DisplayMode) -> UISplitViewController.DisplayMode
    func splitViewController(_ svc: UISplitViewController, willShow column: UISplitViewController.Column)
    func splitViewController(_ svc: UISplitViewController, willHide column: UISplitViewController.Column)
    func splitViewControllerDidCollapse(_ svc: UISplitViewController)
    func splitViewControllerDidExpand(_ svc: UISplitViewController)
    func splitViewController(_ svc: UISplitViewController, willChangeTo displayMode: UISplitViewController.DisplayMode)
    func splitViewController(_ splitViewController: UISplitViewController, collapseSecondary secondaryViewController: UIViewController, onto primaryViewController: UIViewController) -> Bool
}

extension UISplitViewControllerDelegate {
    public func splitViewController(_ svc: UISplitViewController, topColumnForCollapsingToProposedTopColumn proposedTopColumn: UISplitViewController.Column) -> UISplitViewController.Column { proposedTopColumn }
    public func splitViewController(_ svc: UISplitViewController, displayModeForExpandingToProposedDisplayMode proposedDisplayMode: UISplitViewController.DisplayMode) -> UISplitViewController.DisplayMode { proposedDisplayMode }
    public func splitViewController(_ svc: UISplitViewController, willShow column: UISplitViewController.Column) {}
    public func splitViewController(_ svc: UISplitViewController, willHide column: UISplitViewController.Column) {}
    public func splitViewControllerDidCollapse(_ svc: UISplitViewController) {}
    public func splitViewControllerDidExpand(_ svc: UISplitViewController) {}
    public func splitViewController(_ svc: UISplitViewController, willChangeTo displayMode: UISplitViewController.DisplayMode) {}
    public func splitViewController(_ splitViewController: UISplitViewController, collapseSecondary secondaryViewController: UIViewController, onto primaryViewController: UIViewController) -> Bool { false }
}

/// A container view controller that implements a hierarchical interface.
@preconcurrency @MainActor
open class UISplitViewController: UIViewController {
    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    public required init?(coder: NSCoder) { return nil }

    public enum Style: Int, Sendable { case unspecified = 0, doubleColumn, tripleColumn }
    public enum Column: Int, Sendable { case primary = 0, supplementary, secondary, compact, inspector }
    public enum DisplayMode: Int, Sendable { case automatic = 0, secondaryOnly, oneBesideSecondary, oneOverSecondary, twoBesideSecondary, twoOverSecondary, twoDisplaceSecondary }
    public enum SplitBehavior: Int, Sendable { case automatic = 0, tile, overlay, displace }
    public enum PrimaryEdge: Int, Sendable { case leading = 0, trailing }
    public enum BackgroundStyle: Int, Sendable { case none = 0, sidebar }
    public enum DisplayModeButtonVisibility: Int, Sendable { case automatic = 0, never, always }
    public static let automaticDimension: CGFloat = -1

    public let style: Style
    open weak var delegate: (any UISplitViewControllerDelegate)?
    open var preferredDisplayMode: DisplayMode = .automatic { didSet { if preferredDisplayMode != oldValue { modeDidChange() } } }
    open var preferredSplitBehavior: SplitBehavior = .automatic { didSet { viewIfLoaded?.setNeedsLayout() } }
    open var preferredPrimaryColumnWidth: CGFloat = UISplitViewController.automaticDimension { didSet { viewIfLoaded?.setNeedsLayout() } }
    open var preferredPrimaryColumnWidthFraction: CGFloat = UISplitViewController.automaticDimension { didSet { viewIfLoaded?.setNeedsLayout() } }
    open var minimumPrimaryColumnWidth: CGFloat = UISplitViewController.automaticDimension
    open var maximumPrimaryColumnWidth: CGFloat = UISplitViewController.automaticDimension
    open var preferredSupplementaryColumnWidth: CGFloat = UISplitViewController.automaticDimension { didSet { viewIfLoaded?.setNeedsLayout() } }
    open var preferredSupplementaryColumnWidthFraction: CGFloat = UISplitViewController.automaticDimension { didSet { viewIfLoaded?.setNeedsLayout() } }
    open var minimumSupplementaryColumnWidth: CGFloat = UISplitViewController.automaticDimension
    open var maximumSupplementaryColumnWidth: CGFloat = UISplitViewController.automaticDimension
    open var presentsWithGesture = true
    open var showsSecondaryOnlyButton = false { didSet { updateBarItems() } }
    open var displayModeButtonVisibility: DisplayModeButtonVisibility = .automatic { didSet { updateBarItems() } }
    open var primaryEdge: PrimaryEdge = .leading { didSet { viewIfLoaded?.setNeedsLayout() } }
    open var primaryBackgroundStyle: BackgroundStyle = .none

    /// The controllers set per column (the app's), and the navigation controllers wrapping them.
    private var columnControllers: [Column: UIViewController] = [:]
    private var wrappers: [Column: UINavigationController] = [:]
    /// The display mode in effect; the primary's width and the supplementary's.
    public private(set) var displayMode: DisplayMode = .automatic
    public private(set) var primaryColumnWidth: CGFloat = 0
    public private(set) var supplementaryColumnWidth: CGFloat = 0
    public private(set) var isCollapsed = false
    private var compactWidth = false
    /// The dimming over the secondary under an overlaid column.
    private let dimming = UIView()
    var dimmingIsHidden: Bool { dimming.isHidden || dimming.superview == nil }
    private let separators: [UIView] = [UIView(), UIView()]

    public init(style: Style) {
        self.style = style
        super.init(nibName: nil, bundle: nil)
    }

    public override init(nibName: String? = nil, bundle: Any? = nil) {
        style = .unspecified
        super.init(nibName: nibName, bundle: bundle)
    }

    // MARK: Columns

    /// The classic API: the primary then the secondary (and the supplementary between, for
    /// three columns).
    open var viewControllers: [UIViewController] {
        get {
            if style == .unspecified { return classicControllers }
            return [columnControllers[.primary], style == .tripleColumn ? columnControllers[.supplementary] : nil, columnControllers[.secondary]].compactMap { $0 }
        }
        set {
            if style == .unspecified {
                classicControllers = newValue
                viewIfLoaded?.setNeedsLayout()
                return
            }
            if newValue.count > 0 { setViewController(newValue[0], for: .primary) }
            if style == .tripleColumn, newValue.count > 2 {
                setViewController(newValue[1], for: .supplementary)
                setViewController(newValue[2], for: .secondary)
            } else if newValue.count > 1 {
                setViewController(newValue[1], for: .secondary)
            }
        }
    }
    private var classicControllers: [UIViewController] = []

    /// Sets a column's controller, wrapped in a navigation controller unless it is one (UIKit
    /// does the same for the primary, supplementary and secondary columns; the compact column
    /// shows as it is, so `show(.secondary)` pushes only when it is a navigation controller).
    open func setViewController(_ vc: UIViewController?, for column: Column) {
        if let old = wrappers[column] ?? (column == .compact ? columnControllers[.compact] : nil) {
            old.willMove(toParent: nil)
            old.viewIfLoaded?.removeFromSuperview()
            old.removeFromParent()
        }
        wrappers[column] = nil
        columnControllers[column] = vc
        guard let vc else { viewIfLoaded?.setNeedsLayout(); return }
        if column != .compact {
            wrappers[column] = vc as? UINavigationController ?? UINavigationController(rootViewController: vc)
        }
        updateBarItems()
        viewIfLoaded?.setNeedsLayout()
    }

    open func viewController(for column: Column) -> UIViewController? { columnControllers[column] }

    /// Shows a column: the primary expands the sidebar, the secondary in a compact width
    /// pushes onto the compact column's stack.
    open func show(_ column: Column) {
        switch column {
        case .primary:
            if isCollapsed { return }
            delegate?.splitViewController(self, willShow: .primary)
            if style == .tripleColumn {
                preferredDisplayMode = splitBehavior == .overlay ? .twoOverSecondary : splitBehavior == .displace ? .twoDisplaceSecondary : .twoBesideSecondary
            } else {
                preferredDisplayMode = splitBehavior == .tile ? .oneBesideSecondary : .oneOverSecondary
            }
        case .supplementary:
            if isCollapsed || style != .tripleColumn { return }
            if displayMode == .secondaryOnly { preferredDisplayMode = .oneBesideSecondary }
        case .secondary:
            if isCollapsed, let compact = collapsedStack, let secondary = columnControllers[.secondary] {
                if !compact.viewControllers.contains(where: { $0 === secondary }) { compact.pushViewController(secondary, animated: false) }
            } else if displayMode == .oneOverSecondary || displayMode == .twoOverSecondary {
                preferredDisplayMode = .secondaryOnly
            }
        case .compact, .inspector: break
        }
    }

    /// Hides a column: the primary (or both leading columns) leaves the secondary alone.
    open func hide(_ column: Column) {
        guard !isCollapsed else { return }
        switch column {
        case .primary:
            delegate?.splitViewController(self, willHide: .primary)
            preferredDisplayMode = style == .tripleColumn ? .oneBesideSecondary : .secondaryOnly
        case .supplementary:
            guard style == .tripleColumn else { return }
            preferredDisplayMode = .secondaryOnly
        default: break
        }
    }

    /// `show(_:sender:)` from a column's controller: the secondary takes it (pushed onto the
    /// compact stack when collapsed).
    open override func show(_ vc: UIViewController, sender: Any?) { showDetailViewController(vc, sender: sender) }

    open override func showDetailViewController(_ vc: UIViewController, sender: Any?) {
        if isCollapsed, let compact = collapsedStack {
            compact.pushViewController(vc, animated: true)
        } else {
            setViewController(vc, for: .secondary)
        }
    }

    /// The bar button item that toggles the sidebar (the secondary's leading item).
    public private(set) lazy var displayModeButtonItem: UIBarButtonItem = {
        let item = UIBarButtonItem(image: UIImage(systemName: "sidebar.leading"), style: .plain)
        item.primaryAction = UIAction { [weak self] _ in self?.toggleSidebar() }
        return item
    }()

    private func toggleSidebar() {
        let primaryShown = style == .tripleColumn
            ? (displayMode == .twoBesideSecondary || displayMode == .twoOverSecondary || displayMode == .twoDisplaceSecondary)
            : displayMode != .secondaryOnly && displayMode != .automatic
        if primaryShown { hide(.primary) } else { show(.primary) }
    }

    // MARK: The modes

    /// The split behaviour in effect: tile unless the app prefers otherwise.
    open var splitBehavior: SplitBehavior { preferredSplitBehavior == .automatic ? .tile : preferredSplitBehavior }

    /// The display mode a preference resolves to for the style and behaviour.
    private func resolvedDisplayMode() -> DisplayMode {
        let triple = style == .tripleColumn
        switch preferredDisplayMode {
        case .automatic:
            return triple ? (splitBehavior == .tile ? .twoBesideSecondary : splitBehavior == .overlay ? .twoOverSecondary : .twoDisplaceSecondary) : (splitBehavior == .tile ? .oneBesideSecondary : .oneOverSecondary)
        case .twoBesideSecondary, .twoOverSecondary, .twoDisplaceSecondary:
            return triple ? preferredDisplayMode : (splitBehavior == .tile ? .oneBesideSecondary : .oneOverSecondary)
        case .oneOverSecondary where splitBehavior == .tile && style == .doubleColumn:
            return .oneOverSecondary
        default: return preferredDisplayMode
        }
    }

    private func modeDidChange() {
        let mode = resolvedDisplayMode()
        guard mode != displayMode else { return }
        delegate?.splitViewController(self, willChangeTo: mode)
        viewIfLoaded?.setNeedsLayout()
    }

    // MARK: Layout

    open override func loadView() {
        let view = UIView(frame: UIScreen.main.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.backgroundColor = .systemBackground
        self.view = view
        dimming.backgroundColor = UIColor.black.withAlphaComponent(0.2)
        dimming.isHidden = true
        let tap = UITapGestureRecognizer()
        tap.addTarget { [weak self] _ in self?.hide(.primary) }
        dimming.addGestureRecognizer(tap)
        for separator in separators {
            separator.backgroundColor = .opaqueSeparator
            separator.isHidden = true
        }
    }

    /// The compact threshold: a window narrower than 500 pt collapses, as UIKit's compact
    /// width class does.
    open override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let compact = (view.traitCollection.horizontalSizeClass == .compact) || view.bounds.width < 500
        if compact != compactWidth || (compact && !isCollapsed) || (!compact && isCollapsed) {
            compactWidth = compact
            if compact { collapse() } else { expand() }
        }
        if style == .unspecified { layoutClassic(); return }
        if isCollapsed { layoutCollapsed() } else { layoutColumns() }
    }

    /// The controller the compact width shows: the compact column's, else the primary's stack.
    private var collapsedController: UIViewController? { columnControllers[.compact] ?? wrappers[.primary] }
    /// The stack `show(.secondary)` pushes onto when collapsed: the primary's, when no compact
    /// column stands in for the others (uikit/split/collapsed; with one, nothing is pushed).
    private var collapsedStack: UINavigationController? { columnControllers[.compact] == nil ? wrappers[.primary] : nil }

    private func collapse() {
        guard !isCollapsed else { return }
        isCollapsed = true
        for (_, wrapper) in wrappers where wrapper.parent === self { detach(wrapper) }
        dimming.isHidden = true
        for separator in separators { separator.isHidden = true }
        // Without a compact column the secondary collapses onto the primary's stack, shown on
        // top (uikit/split/collapsed: the detail with a back button), unless the delegate keeps
        // the primary on top or handles the collapse itself.
        if columnControllers[.compact] == nil, let stack = wrappers[.primary], let secondary = columnControllers[.secondary], let primary = columnControllers[.primary] {
            let top = delegate?.splitViewController(self, topColumnForCollapsingToProposedTopColumn: .secondary) ?? .secondary
            let handled = delegate?.splitViewController(self, collapseSecondary: secondary, onto: primary) ?? false
            if top == .secondary, !handled, !stack.viewControllers.contains(where: { $0 === secondary }) {
                stack.pushViewController(secondary, animated: false)
            }
        } else {
            _ = delegate?.splitViewController(self, topColumnForCollapsingToProposedTopColumn: .compact)
        }
        delegate?.splitViewControllerDidCollapse(self)
        updateBarItems()
    }

    private func expand() {
        guard isCollapsed else { return }
        isCollapsed = false
        if let compact = columnControllers[.compact], compact.parent === self { detach(compact) }
        // The secondary pushed onto the primary's stack goes back to its column.
        if let stack = wrappers[.primary], let secondary = columnControllers[.secondary], stack.viewControllers.contains(where: { $0 === secondary }) {
            stack.setViewControllers(stack.viewControllers.filter { $0 !== secondary }, animated: false)
            wrappers[.secondary] = nil
            setViewController(secondary, for: .secondary)
        }
        displayMode = delegate?.splitViewController(self, displayModeForExpandingToProposedDisplayMode: resolvedDisplayMode()) ?? resolvedDisplayMode()
        delegate?.splitViewControllerDidExpand(self)
        updateBarItems()
    }

    private func attach(_ wrapper: UIViewController, frame: CGRect, below: UIView? = nil) {
        if wrapper.parent !== self {
            addChild(wrapper)
            wrapper.view.frame = frame
            view.addSubview(wrapper.view)
            wrapper.didMove(toParent: self)
        } else if wrapper.view.superview !== view {
            view.addSubview(wrapper.view)
        }
        wrapper.view.frame = frame
        wrapper.view.layoutIfNeeded()
    }

    private func detach(_ wrapper: UIViewController?) {
        guard let wrapper, wrapper.parent === self else { return }
        wrapper.willMove(toParent: nil)
        wrapper.view.removeFromSuperview()
        wrapper.removeFromParent()
    }

    private func layoutCollapsed() {
        let shown = collapsedController
        for (_, wrapper) in wrappers where wrapper !== shown { detach(wrapper) }
        dimming.isHidden = true
        for separator in separators { separator.isHidden = true }
        guard let shown else { return }
        attach(shown, frame: view.bounds)
        (shown as? UINavigationController)?.navigationBar.edgeInset = 16
    }

    /// The columns' widths for the view's width: the sidebar 320 (280 beside a 340 pt
    /// supplementary) unless the app prefers a width or a fraction, clamped to the minimum and
    /// maximum (uikit/split/columns, triple, modes measured on the iPad simulator).
    func columnWidths(for width: CGFloat) -> (primary: CGFloat, supplementary: CGFloat) {
        var primary: CGFloat
        if preferredPrimaryColumnWidth >= 0 {
            primary = preferredPrimaryColumnWidth
        } else if preferredPrimaryColumnWidthFraction >= 0 {
            primary = (width * preferredPrimaryColumnWidthFraction).rounded()
        } else {
            primary = style == .tripleColumn ? Self.triplePrimaryWidth : Self.defaultPrimaryWidth
        }
        let minimum = minimumPrimaryColumnWidth >= 0 ? minimumPrimaryColumnWidth : 0
        let maximum = maximumPrimaryColumnWidth >= 0 ? maximumPrimaryColumnWidth : width
        primary = min(max(primary, minimum), maximum)
        var supplementary: CGFloat = 0
        if style == .tripleColumn {
            if preferredSupplementaryColumnWidth >= 0 {
                supplementary = preferredSupplementaryColumnWidth
            } else if preferredSupplementaryColumnWidthFraction >= 0 {
                supplementary = (width * preferredSupplementaryColumnWidthFraction).rounded()
            } else {
                supplementary = Self.defaultSupplementaryWidth
            }
            let minimum = minimumSupplementaryColumnWidth >= 0 ? minimumSupplementaryColumnWidth : 0
            let maximum = maximumSupplementaryColumnWidth >= 0 ? maximumSupplementaryColumnWidth : width
            supplementary = min(max(supplementary, minimum), maximum)
        }
        return (primary, supplementary)
    }

    static let defaultPrimaryWidth: CGFloat = 320
    static let triplePrimaryWidth: CGFloat = 280
    static let defaultSupplementaryWidth: CGFloat = 340
    /// The least a tiled secondary keeps beside three columns; narrower, the primary overlays
    /// the other two (1000 wide: 280 + 340 leave 380, and the primary overlays).
    static let minimumTiledSecondaryWidth: CGFloat = 420

    /// What the measured iOS 27 split view does: a sidebar beside the secondary floats over
    /// it — the secondary spans the whole width with its bar's content inset by the sidebar
    /// (uikit/split/columns: the detail's title centred in the uncovered 480) — while a
    /// tiled supplementary sits beside the secondary with a 1 pt separator (uikit/split/triple:
    /// 340, then the secondary at 341); an overlaid column dims what it covers with black at
    /// 20 % and keeps its toggle 16 from its edge, a tiled one 10.
    private func layoutColumns() {
        detach(columnControllers[.compact])
        let mode = resolvedDisplayMode()
        displayMode = mode
        let bounds = view.bounds
        let widths = columnWidths(for: bounds.width)
        primaryColumnWidth = widths.primary
        supplementaryColumnWidth = widths.supplementary
        let triple = style == .tripleColumn
        // In three columns "one" is the supplementary (the column beside the secondary) and
        // "two" adds the primary; in two columns "one" is the primary.
        let two = mode == .twoBesideSecondary || mode == .twoOverSecondary || mode == .twoDisplaceSecondary
        let showsPrimary = triple ? two : mode != .secondaryOnly
        let showsSupplementary = triple && mode != .secondaryOnly
        var primaryOverlays = mode == .oneOverSecondary || mode == .twoOverSecondary
        let supplementaryOverlays = mode == .twoOverSecondary
        let trailing = primaryEdge == .trailing
        // Three tiled columns the width cannot hold: the primary overlays the other two.
        if showsPrimary, showsSupplementary, !primaryOverlays, bounds.width - widths.primary - widths.supplementary < Self.minimumTiledSecondaryWidth {
            primaryOverlays = true
        }
        // Where the tiled columns end: the secondary follows them (the double column's secondary
        // spans the width under the floating sidebar).
        var tiledLeading: CGFloat = 0
        if showsPrimary, !primaryOverlays, triple, showsSupplementary { tiledLeading += widths.primary }
        if showsSupplementary, !supplementaryOverlays { tiledLeading += widths.supplementary }
        let secondaryFrame: CGRect
        let secondaryInset: CGFloat
        if triple, showsSupplementary, !supplementaryOverlays {
            let x = tiledLeading + 1
            secondaryFrame = CGRect(x: trailing ? 0 : x, y: 0, width: bounds.width - x, height: bounds.height)
            secondaryInset = 0
        } else {
            secondaryFrame = bounds
            secondaryInset = showsPrimary && !primaryOverlays && !triple ? widths.primary : 0
        }
        if let secondary = wrappers[.secondary] {
            attach(secondary, frame: secondaryFrame)
            secondary.navigationBar.leadingInset = trailing ? 0 : secondaryInset
            secondary.navigationBar.edgeInset = 10
            secondary.navigationBar.titleOffset = 0
        }
        // The supplementary: tiled beside the secondary (after the tiled primary), or overlaid.
        if let supplementary = wrappers[.supplementary] {
            if showsSupplementary {
                let x = (showsPrimary && !primaryOverlays) ? widths.primary : 0
                attach(supplementary, frame: CGRect(x: trailing ? bounds.width - x - widths.supplementary : x, y: 0, width: widths.supplementary, height: bounds.height))
                supplementary.navigationBar.edgeInset = supplementaryOverlays ? 16 : 10
                supplementary.navigationBar.titleOffset = supplementaryOverlays ? -3 : 0
            } else {
                detach(supplementary)
            }
        }
        if let primary = wrappers[.primary] {
            if showsPrimary {
                attach(primary, frame: CGRect(x: trailing ? bounds.width - widths.primary : 0, y: 0, width: widths.primary, height: bounds.height))
                primary.navigationBar.edgeInset = primaryOverlays ? 16 : 10
                primary.navigationBar.titleOffset = primaryOverlays ? -3 : 0
            } else {
                detach(primary)
            }
        }
        // The dimming over what an overlaid column covers, under it.
        let dims = showsPrimary && primaryOverlays
        dimming.isHidden = !dims
        if dims {
            dimming.frame = bounds
            view.addSubview(dimming)
            if let supplementary = wrappers[.supplementary], showsSupplementary, !supplementaryOverlays, supplementary.view.superview === view {
                // A tiled supplementary sits under the dimming with the secondary.
                view.insertSubview(dimming, aboveSubview: supplementary.view)
            }
            if let primary = wrappers[.primary], primary.view.superview === view { view.bringSubviewToFront(primary.view) }
            if supplementaryOverlays, let supplementary = wrappers[.supplementary], supplementary.view.superview === view { view.bringSubviewToFront(supplementary.view) }
        }
        // The hairline between a tiled supplementary and the secondary.
        let separator = separators[0]
        if triple, showsSupplementary, !supplementaryOverlays {
            separator.isHidden = false
            separator.frame = CGRect(x: trailing ? bounds.width - tiledLeading - 1 : tiledLeading, y: 0, width: 1, height: bounds.height)
            view.addSubview(separator)
            if dims { view.insertSubview(separator, belowSubview: dimming) }
        } else {
            separator.isHidden = true
        }
        separators[1].isHidden = true
        placeToggle(showsPrimary: showsPrimary, showsSupplementary: showsSupplementary, primaryOverlays: primaryOverlays)
    }

    /// The sidebar toggle: at the trailing edge of the primary's bar while it shows (and at
    /// the leading edge of a column it overlays), at the leading edge of the next column's
    /// bar when hidden.
    private func placeToggle(showsPrimary: Bool, showsSupplementary: Bool, primaryOverlays: Bool) {
        guard style != .unspecified, displayModeButtonVisibility != .never else { return }
        let next: Column = style == .tripleColumn && showsSupplementary ? .supplementary : .secondary
        for (column, controller) in columnControllers {
            let item = controller.navigationItem
            let wantsTrailing = column == .primary && showsPrimary
            let wantsLeading = column == next && (!showsPrimary || primaryOverlays)
            var leading = (item.leftBarButtonItems ?? []).filter { $0 !== displayModeButtonItem && $0 !== toggleCopy }
            var trailingItems = (item.rightBarButtonItems ?? []).filter { $0 !== displayModeButtonItem && $0 !== toggleCopy }
            if wantsTrailing { trailingItems = [displayModeButtonItem] + trailingItems }
            if wantsLeading { leading = [toggleCopy] + leading }
            func same(_ a: [UIBarButtonItem], _ b: [UIBarButtonItem]?) -> Bool { a.count == (b ?? []).count && zip(a, b ?? []).allSatisfy { $0 === $1 } }
            if !same(leading, item.leftBarButtonItems) { item.leftBarButtonItems = leading.isEmpty ? nil : leading }
            if !same(trailingItems, item.rightBarButtonItems) { item.rightBarButtonItems = trailingItems.isEmpty ? nil : trailingItems }
        }
    }

    /// A second toggle for the column under an overlaid sidebar (one item cannot sit in two bars).
    private lazy var toggleCopy: UIBarButtonItem = {
        let item = UIBarButtonItem(image: UIImage(systemName: "sidebar.leading"), style: .plain)
        item.primaryAction = UIAction { [weak self] _ in self?.toggleSidebar() }
        return item
    }()

    /// The unspecified style: the classic two controllers side by side, the first 320 wide.
    private func layoutClassic() {
        let bounds = view.bounds
        guard classicControllers.count >= 1 else { return }
        if isCollapsed {
            for controller in classicControllers.dropFirst() where controller.parent === self { controller.willMove(toParent: nil); controller.view.removeFromSuperview(); controller.removeFromParent() }
            attachClassic(classicControllers[0], frame: bounds)
            return
        }
        let widths = columnWidths(for: bounds.width)
        primaryColumnWidth = widths.primary
        displayMode = resolvedDisplayMode()
        attachClassic(classicControllers[0], frame: CGRect(x: 0, y: 0, width: widths.primary, height: bounds.height))
        if classicControllers.count > 1 {
            attachClassic(classicControllers[1], frame: CGRect(x: widths.primary, y: 0, width: bounds.width - widths.primary, height: bounds.height))
        }
    }

    private func attachClassic(_ controller: UIViewController, frame: CGRect) {
        if controller.parent !== self {
            addChild(controller)
            view.addSubview(controller.view)
            controller.didMove(toParent: self)
        }
        controller.view.frame = frame
    }

    /// Bar items follow the next layout (`placeToggle`).
    private func updateBarItems() { viewIfLoaded?.setNeedsLayout() }
}

extension UIViewController {
    /// The nearest ancestor that is a split view controller.
    public var splitViewController: UISplitViewController? {
        var node: UIViewController? = parent
        while let current = node {
            if let split = current as? UISplitViewController { return split }
            node = current.parent
        }
        return nil
    }
}
