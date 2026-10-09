// UINavigationController and UINavigationBar (Docs/elements/UIKit/Navigation.md): a stack of
// view controllers whose top one fills the container, under a translucent bar 10 below the
// safe area's top: an inline title (54 pt bar) or a large one (106.5), items and the back
// button as glass platters. Measured on the iPhone SE simulator (iOS 26).

/// A container view controller that defines a stack-based scheme for navigating hierarchical
/// content.
@MainActor
open class UINavigationController: UIViewController {
    public private(set) var viewControllers: [UIViewController] = []
    public let navigationBar = UINavigationBar()
    open weak var delegate: (any UINavigationControllerDelegate)?
    open var isNavigationBarHidden = false { didSet { navigationBar.isHidden = isNavigationBarHidden; viewIfLoaded?.setNeedsLayout() } }
    /// The toolbar floating over the bottom of the screen with the top controller's
    /// `toolbarItems` (hidden by default, as in UIKit).
    public let toolbar = UIToolbar()
    open var isToolbarHidden = true { didSet { toolbar.isHidden = isToolbarHidden; viewIfLoaded?.setNeedsLayout() } }
    open func setToolbarHidden(_ hidden: Bool, animated: Bool) { isToolbarHidden = hidden }
    /// The floating platter holding the top item's search field.
    private var searchPlatter: FloatingSearchPlatter?
    private weak var hostedSearchBar: UISearchBar?
    /// A search bar that hides on scroll shows again once the content is pulled past its top.
    private var searchBarRevealed = false
    /// The presented search's results view (or the dimming over the content) while it is active.
    private var searchResultsView: UIView?
    private var searchDimming: UIView?
    open var hidesBarsOnSwipe = false
    open var hidesBarsWhenKeyboardAppears = false
    /// The edge pan that pops interactively: the top screen follows the finger, the one below
    /// slides in behind it; releasing past half the width (or fast) completes the pop.
    public private(set) var interactivePopGestureRecognizer: UIGestureRecognizer?
    private var interactivePop: (top: UIView, previous: UIView, veil: UIView)?

    /// The operation a push or pop performs (`UINavigationControllerDelegate`'s animator).
    public enum Operation: Int, Sendable { case none = 0, push, pop }

    public init(rootViewController: UIViewController) {
        super.init(nibName: nil, bundle: nil)
        navigationBar.controller = self
        setViewControllers([rootViewController], animated: false)
    }

    public override init(nibName: String? = nil, bundle: Any? = nil) {
        super.init(nibName: nibName, bundle: bundle)
        navigationBar.controller = self
    }

    open var topViewController: UIViewController? { viewControllers.last }
    open var visibleViewController: UIViewController? { presentedViewController ?? topViewController }

    open override func loadView() {
        let view = UIView(frame: UIScreen.main.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.backgroundColor = .systemBackground
        self.view = view
        view.addSubview(navigationBar)
        toolbar.isFloating = true
        toolbar.isHidden = isToolbarHidden
        view.addSubview(toolbar)
        let edge = UIScreenEdgePanGestureRecognizer()
        edge.edges = .left
        edge.addTarget { [weak self] recognizer in self?.handleInteractivePop(recognizer as! UIScreenEdgePanGestureRecognizer) }
        view.addGestureRecognizer(edge)
        interactivePopGestureRecognizer = edge
        showTop()
    }

    // MARK: Interactive pop

    private func handleInteractivePop(_ pan: UIScreenEdgePanGestureRecognizer) {
        guard let view = viewIfLoaded else { return }
        let width = view.bounds.width
        switch pan.state {
        case .began:
            guard viewControllers.count > 1, let top = topViewController?.viewIfLoaded, let previous = viewControllers[viewControllers.count - 2].view else { return }
            previous.frame = CGRect(x: -width / 3, y: 0, width: width, height: view.bounds.height)
            view.insertSubview(previous, belowSubview: top)
            let veil = UIView(frame: view.bounds)
            veil.backgroundColor = UIColor(white: 0, alpha: 0.1)
            veil.isUserInteractionEnabled = false
            view.insertSubview(veil, aboveSubview: previous)
            interactivePop = (top, previous, veil)
            follow(pan)
        case .changed:
            follow(pan)
        case .ended, .cancelled, .failed:
            guard let pop = interactivePop else { return }
            interactivePop = nil
            let progress = min(max(pan.translation(in: view).x / width, 0), 1)
            let completes = pan.state == .ended && (progress > 0.5 || pan.velocity(in: view).x > 300)
            let remaining = completes ? 1 - progress : progress
            UIView.animate(withDuration: Self.slideDuration * Double(remaining), delay: 0, options: .curveEaseOut, animations: {
                pop.top.frame.origin.x = completes ? width : 0
                pop.previous.frame.origin.x = completes ? 0 : -width / 3
                pop.veil.backgroundColor = UIColor(white: 0, alpha: completes ? 0 : 0.1)
            }, completion: { [weak self] _ in
                pop.veil.removeFromSuperview()
                guard let self else { return }
                if completes {
                    // The previous screen is in place: the model pop keeps it and drops the top.
                    self.setViewControllers(Array(self.viewControllers.dropLast()), animated: false)
                } else {
                    pop.previous.removeFromSuperview()
                    pop.previous.frame.origin.x = 0
                }
            })
        default:
            break
        }
    }

    /// The screens follow the finger: the top one by the translation, the one below from a
    /// third of the width behind to its place, the veil fading with it.
    private func follow(_ pan: UIScreenEdgePanGestureRecognizer) {
        guard let pop = interactivePop, let view = viewIfLoaded else { return }
        let width = view.bounds.width
        let progress = min(max(pan.translation(in: view).x / width, 0), 1)
        pop.top.frame.origin.x = progress * width
        pop.previous.frame.origin.x = -width / 3 * (1 - progress)
        pop.veil.backgroundColor = UIColor(white: 0, alpha: 0.1 * (1 - progress))
    }

    // MARK: Large title collapse

    /// Whether the top screen's content has scrolled the large title away.
    private(set) var largeTitleCollapsed = false

    /// A scroll view inside the stack moved (`UIScrollView.contentOffset`). Scrolled past the
    /// large title's height the bar collapses to the inline title (SwiftUI's iOS behaviour,
    /// `Docs/elements/Navigation.md`: the content under the bar stays put, the bar shrinks);
    /// back at the top it expands again.
    func contentDidScroll(_ scrollView: UIScrollView) {
        guard !applyingCollapse, let top = topViewController?.viewIfLoaded, scrollView.isDescendant(of: top), let view = viewIfLoaded else { return }
        if hostedSearchBar != nil, topViewController?.navigationItem.hidesSearchBarWhenScrolling == true {
            // Pulled past the top the hidden search bar comes back; scrolled on it hides again.
            let pulled = scrollView.contentOffset.y + scrollView.adjustedContentInset.top < -1
            let scrolledAway = scrollView.contentOffset.y + scrollView.adjustedContentInset.top >= UINavigationBar.largeTitleHeight
            if pulled != searchBarRevealed, pulled || scrolledAway {
                searchBarRevealed = pulled
                view.setNeedsLayout()
            }
        }
        guard navigationBar.prefersLargeTitles, navigationBar.showsLargeTitleAtRest else { return }
        // How far the content scrolled from its rest under the expanded bar: the offset moves
        // with the inset when the bar collapses (UIScrollView.adjustedContentInsetDidChange), so
        // the sum is the same either way.
        let scrolled = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        // Collapsed, the content rests exactly where it collapsed (UIKit's bar reopens as the
        // content is pulled past the top): any pull beyond it expands the bar.
        if !largeTitleCollapsed, scrolled >= UINavigationBar.largeTitleHeight {
            largeTitleCollapsed = true
        } else if largeTitleCollapsed, scrolled < UINavigationBar.largeTitleHeight - 0.5 {
            largeTitleCollapsed = false
        } else {
            return
        }
        applyingCollapse = true
        navigationBar.isCollapsed = largeTitleCollapsed
        navigationBar.setNeedsLayout()
        view.setNeedsLayout()
        applyingCollapse = false
    }

    private var applyingCollapse = false

    /// A wheel scroll tried to go above the content's top (`UIScrollView.scroll(by:)`): a
    /// collapsed bar at rest expands.
    func contentDidPullBeyondTop(_ scrollView: UIScrollView) {
        guard largeTitleCollapsed, !applyingCollapse, let top = topViewController?.viewIfLoaded, scrollView.isDescendant(of: top), let view = viewIfLoaded else { return }
        largeTitleCollapsed = false
        applyingCollapse = true
        navigationBar.isCollapsed = false
        navigationBar.setNeedsLayout()
        view.setNeedsLayout()
        applyingCollapse = false
    }

    open func setNavigationBarHidden(_ hidden: Bool, animated: Bool) { isNavigationBarHidden = hidden }

    open func pushViewController(_ viewController: UIViewController, animated: Bool) {
        guard !viewControllers.contains(where: { $0 === viewController }) else { return }
        setViewControllers(viewControllers + [viewController], animated: animated)
    }

    @discardableResult
    open func popViewController(animated: Bool) -> UIViewController? {
        guard viewControllers.count > 1, let popped = viewControllers.last else { return nil }
        setViewControllers(Array(viewControllers.dropLast()), animated: animated)
        return popped
    }

    @discardableResult
    open func popToRootViewController(animated: Bool) -> [UIViewController]? {
        guard viewControllers.count > 1, let root = viewControllers.first else { return nil }
        let popped = Array(viewControllers.dropFirst())
        setViewControllers([root], animated: animated)
        return popped
    }

    @discardableResult
    open func popToViewController(_ viewController: UIViewController, animated: Bool) -> [UIViewController]? {
        guard let index = viewControllers.firstIndex(where: { $0 === viewController }), index < viewControllers.count - 1 else { return nil }
        let popped = Array(viewControllers[(index + 1)...])
        setViewControllers(Array(viewControllers[...index]), animated: animated)
        return popped
    }

    /// Replaces the stack: the old top disappears, the new one appears, the bar follows. An
    /// animated push or pop slides the screens over 0.35 s (the pushed one in from the trailing
    /// edge, the one below moving a third of the width behind a dimming veil, as iOS does).
    open func setViewControllers(_ controllers: [UIViewController], animated: Bool) {
        let oldTop = topViewController
        let isPush = controllers.count > viewControllers.count
        let slides = animated && isViewLoaded && hasAppeared && oldTop != nil && controllers.last !== oldTop && UIView.areAnimationsEnabled
        for controller in viewControllers where !controllers.contains(where: { $0 === controller }) {
            // The old top stays in the hierarchy through its slide out.
            if !(slides && controller === oldTop) { controller.viewIfLoaded?.removeFromSuperview() }
            controller.removeFromParent()
        }
        viewControllers = controllers
        for controller in controllers where controller.parent !== self {
            addChild(controller)
            controller.didMove(toParent: self)
        }
        if controllers.last !== oldTop {
            largeTitleCollapsed = false
            navigationBar.isCollapsed = false
            // The tab bar hides or shows for `hidesBottomBarWhenPushed`.
            tabBarController?.viewIfLoaded?.setNeedsLayout()
        }
        if let newTop = topViewController, newTop !== oldTop {
            delegate?.navigationController(self, willShow: newTop, animated: animated)
        }
        if isViewLoaded { showTop(previous: oldTop, sliding: slides ? (push: isPush, leaving: oldTop) : nil) }
        if let newTop = topViewController, newTop !== oldTop {
            delegate?.navigationController(self, didShow: newTop, animated: animated)
        }
    }

    /// The slide's duration.
    static let slideDuration = 0.35

    /// Puts the top controller's view in the container under the bar and hands the bar its items.
    private func showTop(previous: UIViewController? = nil, sliding: (push: Bool, leaving: UIViewController?)? = nil) {
        guard let view = viewIfLoaded else { return }
        let width = view.bounds.width
        var leavingView: UIView?
        if let previous, previous !== topViewController, let old = previous.viewIfLoaded, old.superview === view {
            if hasAppeared { previous.beginAppearanceTransition(false, animated: sliding != nil) }
            if sliding == nil {
                old.removeFromSuperview()
                if hasAppeared { previous.endAppearanceTransition() }
            } else {
                leavingView = old
            }
        }
        if let top = topViewController {
            let content = top.view!
            if content.superview !== view {
                content.frame = view.bounds
                content.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                if hasAppeared { top.beginAppearanceTransition(true, animated: sliding != nil) }
                if let sliding, let leavingView, let previous,
                   let animator = delegate?.navigationController(self, animationControllerFor: sliding.push ? .push : .pop, from: previous, to: top) {
                    // The delegate's animator moves the screens itself.
                    view.insertSubview(content, belowSubview: navigationBar)
                    let context = TransitionContext(containerView: view, from: previous, to: top,
                                                    initialFrames: [ObjectIdentifier(previous): leavingView.frame],
                                                    finalFrames: [ObjectIdentifier(top): view.bounds, ObjectIdentifier(previous): leavingView.frame],
                                                    onComplete: { [weak self] completed in
                                                        leavingView.removeFromSuperview()
                                                        leavingView.frame.origin = .zero
                                                        animator.animationEnded(completed)
                                                        if self?.hasAppeared == true {
                                                            previous.endAppearanceTransition()
                                                            top.endAppearanceTransition()
                                                        }
                                                    })
                    animator.animateTransition(using: context)
                } else if let sliding, let leavingView {
                    // The slide: the pushed screen starts off the trailing edge (a popped one a third
                    // to the leading side, behind) and both move together.
                    let startX: CGFloat = sliding.push ? width : -width / 3
                    content.frame.origin.x = startX
                    if sliding.push { view.insertSubview(content, belowSubview: navigationBar) } else { view.insertSubview(content, belowSubview: leavingView) }
                    let veil = UIView(frame: view.bounds)
                    veil.backgroundColor = UIColor(white: 0, alpha: sliding.push ? 0 : 0.1)
                    veil.isUserInteractionEnabled = false
                    view.insertSubview(veil, aboveSubview: sliding.push ? leavingView : content)
                    let previousController = previous
                    UIView.animate(withDuration: Self.slideDuration, delay: 0, options: .curveEaseInOut, animations: {
                        content.frame.origin.x = 0
                        leavingView.frame.origin.x = sliding.push ? -width / 3 : width
                        veil.backgroundColor = UIColor(white: 0, alpha: sliding.push ? 0.1 : 0)
                    }, completion: { [weak self] _ in
                        veil.removeFromSuperview()
                        leavingView.removeFromSuperview()
                        leavingView.frame.origin.x = 0
                        if self?.hasAppeared == true {
                            previousController?.endAppearanceTransition()
                            top.endAppearanceTransition()
                        }
                    })
                } else {
                    view.insertSubview(content, belowSubview: navigationBar)
                    if hasAppeared { top.endAppearanceTransition() }
                }
            }
            // A title or items set later (a hosting controller bridging its content's
            // navigation title and toolbar) rebuild the bar.
            top.navigationItem.onChange = { [weak self] in
                self?.navigationBar.rebuild()
                self?.navigationBar.setNeedsLayout()
            }
        }
        navigationBar.items = viewControllers.map(\.navigationItem)
        toolbar.items = topViewController?.toolbarItems
        hostSearchBar(of: topViewController)
        view.setNeedsLayout()
    }

    func toolbarItemsDidChange(for controller: UIViewController) {
        guard controller === topViewController else { return }
        toolbar.items = controller.toolbarItems
    }

    /// The top item's search controller: its bar sits under the navigation bar as an empty
    /// 60 pt band and its field lives in a glass capsule floating over the bottom.
    private func hostSearchBar(of controller: UIViewController?) {
        let searchBar = controller?.navigationItem.searchController?.searchBar
        guard searchBar !== hostedSearchBar else { return }
        if let old = hostedSearchBar {
            old.hostsFieldExternally = false
            old.removeFromSuperview()
        }
        searchPlatter?.removeFromSuperview()
        searchPlatter = nil
        hostedSearchBar = searchBar
        searchBarRevealed = false
        searchResultsView?.removeFromSuperview()
        searchResultsView = nil
        searchDimming?.removeFromSuperview()
        searchDimming = nil
        guard let searchBar, let view = viewIfLoaded else { return }
        searchBar.hostsFieldExternally = true
        controller?.navigationItem.searchController?.host = self
        view.insertSubview(searchBar, belowSubview: navigationBar)
        let platter = FloatingSearchPlatter(field: searchBar.searchTextField)
        view.addSubview(platter)
        searchPlatter = platter
    }

    /// The search controller became active or inactive, or its text changed.
    func searchPresentationDidChange() {
        guard let controller = topViewController?.navigationItem.searchController, let view = viewIfLoaded else { return }
        let results = controller.searchResultsController
        if controller.showsResults, let results {
            if searchResultsView == nil {
                results.willMove(toParent: self)
                results.loadViewIfNeeded()
                view.insertSubview(results.view, belowSubview: navigationBar)
                searchResultsView = results.view
            }
        } else if let shown = searchResultsView {
            shown.removeFromSuperview()
            searchResultsView = nil
        }
        // Active without results showing: the content is dimmed when the controller obscures it
        // (approximate: UIKit's dim is unmeasured).
        if controller.isActive, searchResultsView == nil, controller.obscuresBackgroundDuringPresentation {
            if searchDimming == nil {
                let dimming = UIView(frame: view.bounds)
                dimming.backgroundColor = UIColor(white: 0, alpha: 0.2)
                view.insertSubview(dimming, belowSubview: navigationBar)
                searchDimming = dimming
            }
        } else {
            searchDimming?.removeFromSuperview()
            searchDimming = nil
        }
        navigationBar.hostsActiveSearch = controller.isActive
        navigationBar.setNeedsLayout()
        view.setNeedsLayout()
    }

    /// Whether the top item's search bar hides until the content is pulled (iOS 26 hides it
    /// while the content can scroll and the item asks for it; uikit/nav/search-results).
    private var searchBarHidesForScrolling: Bool {
        guard let top = topViewController, top.navigationItem.hidesSearchBarWhenScrolling, !searchBarRevealed,
              let scrollView = top.viewIfLoaded?.firstDescendant(where: { $0 is UIScrollView }) as? UIScrollView else { return false }
        return scrollView.contentSize.height > scrollView.bounds.height - scrollView.adjustedContentInset.top - scrollView.adjustedContentInset.bottom
    }

    open override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        guard let view = viewIfLoaded else { return }
        let top = view.safeAreaInsets.top
        let height = navigationBar.isHidden ? 0 : navigationBar.preferredHeight
        navigationBar.frame = CGRect(x: 0, y: top + UINavigationBar.topOffset, width: view.bounds.width, height: height)
        var contentTop = navigationBar.isHidden ? 0 : navigationBar.frame.maxY
        let searchController = topViewController?.navigationItem.searchController
        let searchActive = searchController?.isActive == true
        let searchHidden = searchBarHidesForScrolling && !searchActive
        if let searchBar = hostedSearchBar {
            if searchActive {
                // Active: the bar takes the navigation bar's place (60 tall at 10), its field
                // inside it with the cancel circle; the results fill the container under it.
                searchBar.hostsFieldExternally = false
                searchBar.isActiveLayout = true
                if searchBar.superview !== navigationBar { navigationBar.addSubview(searchBar) }
                searchBar.frame = CGRect(origin: .zero, size: navigationBar.bounds.size)
                navigationBar.bringSubviewToFront(searchBar)
            } else {
                searchBar.isActiveLayout = false
                searchBar.hostsFieldExternally = true
                if searchBar.superview !== view { view.insertSubview(searchBar, belowSubview: navigationBar) }
                searchBar.frame = CGRect(x: 0, y: contentTop, width: view.bounds.width, height: searchHidden ? 0 : UISearchBar.navigationHeight)
                contentTop = searchBar.frame.maxY
            }
        }
        searchResultsView?.frame = view.bounds
        searchDimming?.frame = view.bounds
        // The floating bar: 76 tall over the bottom safe area, the platters in its top 48.
        let floatingY = view.bounds.height - view.safeAreaInsets.bottom - UIToolbar.floatingHeight
        toolbar.frame = CGRect(x: 0, y: floatingY, width: view.bounds.width, height: UIToolbar.floatingHeight)
        let platterShown = searchPlatter != nil && !searchHidden && !searchActive
        toolbar.isHidden = isToolbarHidden || (toolbar.items ?? []).isEmpty || platterShown
        if let platter = searchPlatter {
            platter.isHidden = !platterShown
            platter.frame = CGRect(x: UIToolbar.floatingInset, y: floatingY, width: view.bounds.width - 2 * UIToolbar.floatingInset, height: UIToolbar.height)
            view.bringSubviewToFront(platter)
        }
        var contentBottom: CGFloat = 0
        if !toolbar.isHidden || platterShown { contentBottom = view.bounds.height - floatingY }
        if let content = topViewController?.viewIfLoaded {
            // A screen mid-slide keeps its x (the animation owns it); its size follows the container.
            if content.frame.size != view.bounds.size { content.frame.size = view.bounds.size }
            if content.layer.animatingGroups.isEmpty, content.frame.origin != .zero, interactivePop == nil { content.frame.origin = .zero }
            content.containerSafeAreaInsets = UIEdgeInsets(top: contentTop, left: 0, bottom: contentBottom, right: 0)
        }
    }
}

/// The methods a navigation controller's delegate implements.
@MainActor
public protocol UINavigationControllerDelegate: AnyObject {
    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool)
    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool)
    /// An animator for a push or pop (nil for the standard slide).
    func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation,
                              from fromVC: UIViewController, to toVC: UIViewController) -> (any UIViewControllerAnimatedTransitioning)?
}

extension UINavigationControllerDelegate {
    public func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {}
    public func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {}
    public func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation,
                                     from fromVC: UIViewController, to toVC: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? { nil }
}

/// Navigational controls in a bar along the top of the screen.
@MainActor
open class UINavigationBar: UIView {
    /// The bar sits this far below the safe area's top (uikit/nav/basic: y 10 with no status bar).
    static let topOffset: CGFloat = 10
    /// The content area's height; the inline bar is one content area.
    static let contentHeight: CGFloat = 54
    /// The large title view's height under the content area.
    static let largeTitleHeight: CGFloat = 52.5

    open var items: [UINavigationItem]? { didSet { rebuild() } }
    open var topItem: UINavigationItem? { items?.last }
    open var backItem: UINavigationItem? { (items?.count ?? 0) > 1 ? items?[items!.count - 2] : nil }
    open var prefersLargeTitles = false { didSet { rebuild() } }
    open var isTranslucent = true
    open var barStyle = 0
    open var barTintColor: UIColor?
    open var titleTextAttributes: [String: Any]?
    open var largeTitleTextAttributes: [String: Any]?
    open var standardAppearance: UINavigationBarAppearance = UINavigationBarAppearance()
    open var scrollEdgeAppearance: UINavigationBarAppearance?
    open var compactAppearance: UINavigationBarAppearance?
    weak var controller: UINavigationController?

    private let titleLabel = UILabel()
    private let largeTitleLabel = UILabel()
    private var backButton: BarPlatterButton?
    private var leftButtons: [BarPlatterButton] = []
    private var rightButtons: [BarPlatterButton] = []

    public override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textAlignment = .center
        // A navigation title is a heading to assistive technology (uk-accessibility).
        titleLabel.accessibilityTraits = .header
        addSubview(titleLabel)
        largeTitleLabel.font = .systemFont(ofSize: 34, weight: .bold)
        largeTitleLabel.accessibilityTraits = .header
        addSubview(largeTitleLabel)
    }

    /// Set while the top screen's content has scrolled the large title away.
    var isCollapsed = false { didSet { if isCollapsed != oldValue { setNeedsLayout(); controller?.viewIfLoaded?.setNeedsLayout() } } }

    /// Whether the top item shows a large title (collapsed by scrolling: the inline one).
    var showsLargeTitle: Bool { showsLargeTitleAtRest && !isCollapsed }

    /// Whether the top item would show a large title with its content at the top.
    var showsLargeTitleAtRest: Bool {
        guard prefersLargeTitles, let item = topItem else { return false }
        switch item.largeTitleDisplayMode {
        case .always: return true
        case .never, .inline: return false
        case .automatic: return (items?.count ?? 0) == 1 || (items?.first?.largeTitleDisplayMode == .always)
        }
    }

    /// An active search controller's bar takes the whole bar (60 tall) and hides its content.
    var hostsActiveSearch = false { didSet { if hostsActiveSearch != oldValue { setNeedsLayout(); controller?.viewIfLoaded?.setNeedsLayout() } } }

    var preferredHeight: CGFloat { hostsActiveSearch ? UISearchBar.navigationHeight : Self.contentHeight + (showsLargeTitle ? Self.largeTitleHeight : 0) }

    func rebuild() {
        backButton?.removeFromSuperview()
        backButton = nil
        for button in leftButtons + rightButtons { button.removeFromSuperview() }
        leftButtons = []
        rightButtons = []
        guard let item = topItem else { setNeedsLayout(); return }
        if backItem != nil, !item.hidesBackButton {
            let back = BarPlatterButton(kind: .chevron)
            back.addAction(UIAction { [weak self] _ in _ = self?.controller?.popViewController(animated: true) }, for: .primaryActionTriggered)
            back.accessibilityLabel = "Back"
            addSubview(back)
            backButton = back
        }
        for barItem in item.leftBarButtonItems ?? [] where !barItem.isSpace {
            let button = BarPlatterButton(item: barItem)
            addSubview(button)
            leftButtons.append(button)
        }
        for barItem in item.rightBarButtonItems ?? [] where !barItem.isSpace {
            let button = BarPlatterButton(item: barItem)
            addSubview(button)
            rightButtons.append(button)
        }
        controller?.viewIfLoaded?.setNeedsLayout()
        setNeedsLayout()
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        let item = topItem
        let large = showsLargeTitle && !hostsActiveSearch
        // The inline title: 24.5 tall at 9.75, centred (uikit/nav/basic); hidden under a large
        // title or an active search.
        titleLabel.text = item?.title
        titleLabel.isHidden = large || item?.titleView != nil || hostsActiveSearch
        backButton?.isHidden = hostsActiveSearch
        for button in leftButtons + rightButtons { button.isHidden = hostsActiveSearch }
        let titleWidth = titleLabel.intrinsicContentSize.width
        titleLabel.frame = CGRect(x: ((bounds.width - titleWidth) / 2 * 4).rounded() / 4, y: 9.75, width: titleWidth, height: 24.5)
        // The large title: 34 pt bold at 16, 49 tall under the content area (uikit/nav/large).
        largeTitleLabel.text = large ? item?.title : nil
        largeTitleLabel.isHidden = !large
        if large { largeTitleLabel.frame = CGRect(x: 16, y: Self.contentHeight, width: largeTitleLabel.intrinsicContentSize.width, height: 49) }
        // Platters: 44 tall from the bar's top, 16 from the edges, 8 apart (uikit/nav/items).
        var x: CGFloat = 16
        if let backButton {
            backButton.frame = CGRect(x: x, y: 0, width: backButton.platterWidth, height: 44)
            x += backButton.platterWidth + 8
        }
        for button in leftButtons {
            button.frame = CGRect(x: x, y: 0, width: button.platterWidth, height: 44)
            x += button.platterWidth + 8
        }
        var right = bounds.width - 16
        for button in rightButtons {
            button.frame = CGRect(x: right - button.platterWidth, y: 0, width: button.platterWidth, height: 44)
            right -= button.platterWidth + 8
        }
        if let custom = item?.titleView {
            // The title view: its intrinsic size (or what it says fits), at most the room between
            // the items, centred in the bar's content area; off centre only when it has to be.
            if custom.superview !== self { addSubview(custom) }
            let room = CGSize(width: max(0, right - x - 8), height: 44)
            var size = custom.intrinsicContentSize
            if size.width <= 0 || size.height <= 0 { size = custom.sizeThatFits(room) }
            if size.width <= 0 || size.height <= 0 { size = custom.frame.size }
            size.width = min(size.width, room.width)
            size.height = min(size.height, room.height)
            var originX = (bounds.width - size.width) / 2
            originX = min(max(originX, x + 8), right - size.width)
            custom.frame = CGRect(x: originX, y: (44 - size.height) / 2, width: size.width, height: size.height)
        }
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: preferredHeight) }
}

/// A bar's appearance (accepted; the iOS 26 bar is drawn as measured).
@MainActor
public final class UINavigationBarAppearance {
    public var backgroundColor: UIColor?
    public var titleTextAttributes: [String: Any] = [:]
    public var largeTitleTextAttributes: [String: Any] = [:]
    public var shadowColor: UIColor?
    public init() {}
    public func configureWithOpaqueBackground() {}
    public func configureWithTransparentBackground() {}
    public func configureWithDefaultBackground() {}
}

/// A glass platter in a bar (uikit/nav/items): a near-white capsule with a faint shadow holding
/// a 17 pt medium title 12 in, a 23 × 22 image, or the back chevron.
@MainActor
final class BarPlatterButton: UIControl {
    enum Kind { case title(String), image(String), chevron }
    let kind: Kind
    weak var item: UIBarButtonItem?
    private let label = UILabel()
    /// The capsule's height: 44 in a navigation bar, 48 in a toolbar (uikit/toolbar/basic).
    var platterHeight: CGFloat = 44
    /// A `done` item: the capsule filled with the tint, a white semibold title (uikit/toolbar/basic).
    private(set) var isProminent = false

    init(item: UIBarButtonItem, platterHeight: CGFloat = 44) {
        self.item = item
        self.platterHeight = platterHeight
        isProminent = item.style == .done
        if let name = item.image?.name, item.image?.isSystemSymbol == true {
            kind = .image(name)
        } else if let name = item.systemImageName {
            kind = .image(name)
        } else {
            kind = .title(item.title ?? item.systemTitle ?? "")
        }
        super.init(frame: .zero)
        configure()
        isEnabled = item.isEnabled
        accessibilityLabel = item.title ?? item.systemTitle ?? item.systemImageName
        if let action = item.primaryAction { addAction(action, for: .primaryActionTriggered) }
        // An item with a menu and no primary action opens the menu on a tap; with both, a long press.
        if item.primaryAction == nil, item.menu != nil {
            addAction(UIAction { [weak self] _ in
                guard let self, let menu = self.item?.menu else { return }
                MenuPresenter.present(menu, from: self)
            }, for: .primaryActionTriggered)
        }
    }

    override var longPressMenu: UIMenu? { item?.primaryAction != nil ? item?.menu : nil }

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        configure()
    }

    private func configure() {
        isAccessibilityElement = true
        accessibilityTraits = .button
        if case .title(let text) = kind {
            label.text = text
            label.font = .systemFont(ofSize: 17, weight: isProminent ? .semibold : .medium)
            label.textColor = isProminent ? .white : .label
            addSubview(label)
        }
    }

    /// The image a system item draws, at its own size (a 17 pt medium symbol: 23 × 22 for plus,
    /// 24 × 28 for trash, 24.5 × 30 for the share arrow), centred in the capsule.
    static func imageSize(for name: String) -> CGSize {
        switch name {
        case "trash": return CGSize(width: 24, height: 28)
        case "square.and.arrow.up": return CGSize(width: 24.5, height: 30)
        default: return CGSize(width: 23, height: 22)
        }
    }

    /// 44 for an image or the chevron; a title's width plus 24 (uikit/nav/items: 54.5 for "Edit").
    var platterWidth: CGFloat {
        switch kind {
        case .title: return label.intrinsicContentSize.width + 24
        case .image, .chevron: return platterHeight
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if case .title = kind {
            // The 24.5 pt label sits 9.5 down in a 44 pt platter, 12 down in a 48 pt one.
            let y = platterHeight == 44 ? 9.5 : ((platterHeight - 24.5) / 2 * 2).rounded() / 2
            label.frame = CGRect(x: 12, y: y, width: bounds.width - 24, height: 24.5)
        }
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        if isProminent {
            list.append(.beginShadow(RGBA(red: 0, green: 0, blue: 0, alpha: 0.08), radius: 10, offset: CGSize(width: 0, height: 4)))
            list.append(.fillRRect(rect, cornerRadius: rect.height / 2, (tintColor ?? .systemBlue).rgba(for: style)))
            list.append(.endGroup)
        } else {
            GlassPainter.paintPlatter(rect, style: style, into: &list)
        }
        let ink = isProminent ? UIColor.white.rgba(for: style) : (isEnabled ? UIColor.label : UIColor.tertiaryLabel).rgba(for: style)
        switch kind {
        case .image(let name):
            let size = Self.imageSize(for: name)
            let image = CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
            SymbolPainter.paint(name: name, in: context.absoluteRect(image), color: ink, weight: 500, into: &list)
        case .chevron:
            var chevron = Path()
            let centre = CGPoint(x: rect.midX - 1, y: rect.midY)
            chevron.move(to: CGPoint(x: centre.x + 4.5, y: centre.y - 9))
            chevron.addLine(to: CGPoint(x: centre.x - 4.5, y: centre.y))
            chevron.addLine(to: CGPoint(x: centre.x + 4.5, y: centre.y + 9))
            list.append(.strokePath(chevron, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round), ink))
        case .title:
            break
        }
    }
}
