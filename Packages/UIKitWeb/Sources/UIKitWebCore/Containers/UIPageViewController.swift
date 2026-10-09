// UIPageViewController (Docs/elements/UIKit/Navigation.md): pages from a data source shown
// one at a time in a paging scroll view of three slots (the neighbours loaded as a drag
// begins), the page indicator the data source's counts bring under them, and
// setViewControllers moving between pages. Measured on the iPhone SE simulator (iOS 26,
// uikit/page/scroll, uikit/page/curl): the scroll style's queuing scroll view spans the view
// widened by the inter-page spacing (−10 … 330 for 20), its slots 320 apart plus the spacing,
// 374 tall under a 26 pt page control centred at the bottom; the page-curl style shows its page
// edge to edge and scrolls like the scroll style (the curl itself is not drawn).

@MainActor
public protocol UIPageViewControllerDataSource: AnyObject {
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController?
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController?
    /// The indicator's page count (0 for none) and the current page.
    func presentationCount(for pageViewController: UIPageViewController) -> Int
    func presentationIndex(for pageViewController: UIPageViewController) -> Int
}

extension UIPageViewControllerDataSource {
    public func presentationCount(for pageViewController: UIPageViewController) -> Int { 0 }
    public func presentationIndex(for pageViewController: UIPageViewController) -> Int { 0 }
}

@MainActor
public protocol UIPageViewControllerDelegate: AnyObject {
    func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController])
    func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool)
    func pageViewController(_ pageViewController: UIPageViewController, spineLocationFor orientation: UIInterfaceOrientation) -> UIPageViewController.SpineLocation
}

extension UIPageViewControllerDelegate {
    public func pageViewController(_ pageViewController: UIPageViewController, willTransitionTo pendingViewControllers: [UIViewController]) {}
    public func pageViewController(_ pageViewController: UIPageViewController, didFinishAnimating finished: Bool, previousViewControllers: [UIViewController], transitionCompleted completed: Bool) {}
    public func pageViewController(_ pageViewController: UIPageViewController, spineLocationFor orientation: UIInterfaceOrientation) -> UIPageViewController.SpineLocation { .min }
}

/// The orientation of the interface (the browser's window is a portrait phone).
public enum UIInterfaceOrientation: Int, Sendable { case unknown = 0, portrait, portraitUpsideDown, landscapeLeft, landscapeRight }

/// A container view controller that manages navigation between pages of content.
@MainActor
open class UIPageViewController: UIViewController, UIScrollViewDelegate {
    public enum TransitionStyle: Int, Sendable { case pageCurl = 0, scroll }
    public enum NavigationOrientation: Int, Sendable { case horizontal = 0, vertical }
    public enum SpineLocation: Int, Sendable { case none = 0, min, mid, max }
    public enum NavigationDirection: Int, Sendable { case forward = 0, reverse }

    public struct OptionsKey: Hashable, Sendable, RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let spineLocation = OptionsKey(rawValue: "UIPageViewControllerOptionSpineLocationKey")
        public static let interPageSpacing = OptionsKey(rawValue: "UIPageViewControllerOptionInterPageSpacingKey")
    }

    public let transitionStyle: TransitionStyle
    public let navigationOrientation: NavigationOrientation
    public let spineLocation: SpineLocation
    public let options: [OptionsKey: Any]?
    open var isDoubleSided = false
    open weak var dataSource: (any UIPageViewControllerDataSource)?
    open weak var delegate: (any UIPageViewControllerDelegate)?
    /// The gesture recognizers a page-curl controller exposes (the scroll view's pan here).
    open var gestureRecognizers: [UIGestureRecognizer] { scrollView.gestureRecognizers ?? [] }
    open private(set) var viewControllers: [UIViewController]?

    /// The gap between pages while scrolling (`OptionsKey.interPageSpacing`).
    let interPageSpacing: CGFloat
    let scrollView = UIScrollView()
    let pageControl = UIPageControl()
    private var slots: [UIView] = []
    /// The controllers in the slots before and after the current page while a drag runs.
    private var neighbours: (before: UIViewController?, after: UIViewController?) = (nil, nil)

    public init(transitionStyle style: TransitionStyle, navigationOrientation: NavigationOrientation, options: [OptionsKey: Any]? = nil) {
        transitionStyle = style
        self.navigationOrientation = navigationOrientation
        self.options = options
        spineLocation = (options?[.spineLocation] as? SpineLocation) ?? ((options?[.spineLocation] as? Int).flatMap(SpineLocation.init(rawValue:))) ?? .min
        interPageSpacing = style == .scroll ? ((options?[.interPageSpacing] as? CGFloat) ?? (options?[.interPageSpacing] as? Double).map { CGFloat($0) } ?? (options?[.interPageSpacing] as? Int).map { CGFloat($0) } ?? 0) : 0
        super.init(nibName: nil, bundle: nil)
    }

    open override func loadView() {
        let view = UIView(frame: UIScreen.main.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.backgroundColor = .systemBackground
        self.view = view
        scrollView.isPagingEnabled = true
        scrollView.bounces = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.delegate = self
        view.addSubview(scrollView)
        slots = (0..<3).map { _ in UIView() }
        for slot in slots { scrollView.addSubview(slot) }
        pageControl.isHidden = true
        pageControl.addAction(UIAction { [weak self] _ in self?.pageControlChanged() }, for: .valueChanged)
        view.addSubview(pageControl)
        if let current = viewControllers?.first { install(current, in: 1) }
    }

    /// Shows `viewControllers` (one page; two only with a mid spine, which shows the first).
    open func setViewControllers(_ viewControllers: [UIViewController]?, direction: NavigationDirection, animated: Bool, completion: ((Bool) -> Void)? = nil) {
        let previous = self.viewControllers ?? []
        self.viewControllers = viewControllers
        if viewIfLoaded != nil {
            for slot in slots.indices { clear(slot: slot) }
            if let current = viewControllers?.first { install(current, in: 1) }
            viewIfLoaded?.setNeedsLayout()
        }
        updatePageControl()
        if previous.first !== viewControllers?.first { delegate?.pageViewController(self, didFinishAnimating: true, previousViewControllers: previous, transitionCompleted: true) }
        completion?(true)
    }

    // MARK: Slots

    private var horizontal: Bool { navigationOrientation == .horizontal }
    private var showsIndicator: Bool { transitionStyle == .scroll && (dataSource?.presentationCount(for: self) ?? 0) > 0 }
    private var pageSize: CGSize {
        guard let view = viewIfLoaded else { return .zero }
        return CGSize(width: view.bounds.width, height: view.bounds.height - (showsIndicator ? UIPageControl.height : 0))
    }
    private var pitch: CGFloat { (horizontal ? pageSize.width : pageSize.height) + interPageSpacing }

    private func install(_ controller: UIViewController, in slot: Int) {
        guard controller.parent !== self || controller.viewIfLoaded?.superview !== slots[slot] else { return }
        if controller.parent !== self { addChild(controller) }
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(origin: .zero, size: slots[slot].bounds.size)
        controller.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        slots[slot].addSubview(controller.view)
        controller.didMove(toParent: self)
    }

    private func clear(slot: Int) {
        for subview in slots[slot].subviews {
            if let child = children.first(where: { $0.viewIfLoaded === subview }) {
                child.willMove(toParent: nil)
                subview.removeFromSuperview()
                child.removeFromParent()
            } else {
                subview.removeFromSuperview()
            }
        }
    }

    open override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        guard let view = viewIfLoaded else { return }
        let size = pageSize
        let spacing = interPageSpacing
        if horizontal {
            scrollView.frame = CGRect(x: -spacing / 2, y: 0, width: size.width + spacing, height: size.height)
            scrollView.contentSize = CGSize(width: 3 * (size.width + spacing), height: size.height)
            for (index, slot) in slots.enumerated() { slot.frame = CGRect(x: spacing / 2 + CGFloat(index) * (size.width + spacing), y: 0, width: size.width, height: size.height) }
        } else {
            scrollView.frame = CGRect(x: 0, y: -spacing / 2, width: size.width, height: size.height + spacing)
            scrollView.contentSize = CGSize(width: size.width, height: 3 * (size.height + spacing))
            for (index, slot) in slots.enumerated() { slot.frame = CGRect(x: 0, y: spacing / 2 + CGFloat(index) * (size.height + spacing), width: size.width, height: size.height) }
        }
        for slot in slots { for subview in slot.subviews { subview.frame = CGRect(origin: .zero, size: slot.bounds.size) } }
        if !scrollView.isDragging, !scrollView.isDecelerating { scrollView.contentOffset = horizontal ? CGPoint(x: pitch, y: 0) : CGPoint(x: 0, y: pitch) }
        pageControl.isHidden = !showsIndicator
        if showsIndicator {
            let width = pageControl.sizeThatFits(.zero).width
            pageControl.frame = CGRect(x: ((view.bounds.width - width) / 2).rounded(), y: view.bounds.height - UIPageControl.height, width: width, height: UIPageControl.height)
        }
    }

    private func updatePageControl() {
        guard let dataSource else { pageControl.numberOfPages = 0; return }
        pageControl.numberOfPages = dataSource.presentationCount(for: self)
        pageControl.currentPage = dataSource.presentationIndex(for: self)
        viewIfLoaded?.setNeedsLayout()
    }

    private func pageControlChanged() {
        guard let current = viewControllers?.first, let dataSource else { return }
        let index = dataSource.presentationIndex(for: self)
        let target = pageControl.currentPage > index ? dataSource.pageViewController(self, viewControllerAfter: current) : pageControl.currentPage < index ? dataSource.pageViewController(self, viewControllerBefore: current) : nil
        guard let target else { return }
        setViewControllers([target], direction: pageControl.currentPage > index ? .forward : .reverse, animated: true)
    }

    // MARK: Dragging between pages

    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard let current = viewControllers?.first, let dataSource else { return }
        neighbours = (dataSource.pageViewController(self, viewControllerBefore: current), dataSource.pageViewController(self, viewControllerAfter: current))
        if let before = neighbours.before { install(before, in: 0) }
        if let after = neighbours.after { install(after, in: 2) }
        // Without a neighbour the content ends at the current page.
        let pitch = self.pitch
        let start = neighbours.before == nil ? pitch : 0
        let end = neighbours.after == nil ? 2 * pitch : 3 * pitch
        if horizontal {
            scrollView.contentInset = UIEdgeInsets(top: 0, left: -start, bottom: 0, right: -(3 * pitch - end))
        } else {
            scrollView.contentInset = UIEdgeInsets(top: -start, left: 0, bottom: -(3 * pitch - end), right: 0)
        }
        delegate?.pageViewController(self, willTransitionTo: [neighbours.before, neighbours.after].compactMap { $0 })
    }

    /// A paging scroll view always settles on a page with an animation that ends here.
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) { settlePage() }

    /// The drag ended on a slot: the slot's page becomes the current one.
    private func settlePage() {
        let position = horizontal ? scrollView.contentOffset.x : scrollView.contentOffset.y
        let slot = Int((position / pitch).rounded())
        let previous = viewControllers ?? []
        let target: UIViewController? = slot <= 0 ? neighbours.before : slot >= 2 ? neighbours.after : nil
        scrollView.contentInset = .zero
        if let target {
            viewControllers = [target]
            for index in slots.indices where index != slot { clear(slot: index) }
            // The page moves to the middle slot and the offset recentres on it.
            if let pageView = target.viewIfLoaded { slots[1].addSubview(pageView) }
            updatePageControl()
            delegate?.pageViewController(self, didFinishAnimating: true, previousViewControllers: previous, transitionCompleted: true)
        } else {
            for index in [0, 2] { clear(slot: index) }
            delegate?.pageViewController(self, didFinishAnimating: true, previousViewControllers: previous, transitionCompleted: false)
        }
        neighbours = (nil, nil)
        scrollView.contentOffset = horizontal ? CGPoint(x: pitch, y: 0) : CGPoint(x: 0, y: pitch)
        viewIfLoaded?.setNeedsLayout()
    }
}
