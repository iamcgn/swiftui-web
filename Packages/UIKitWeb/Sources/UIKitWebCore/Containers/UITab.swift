// Tabs (iOS 18, Docs/elements/UIKit/Navigation.md): a tab bar controller set up with `tabs`
// instead of `viewControllers`. Each `UITab` names its tab with a title, an image and an
// identifier, and gives its controller from a provider the first time the controller is
// needed; the bar shows the tabs that are not hidden, and `selectedTab` reads and sets the
// selection by tab, as swift-navigation's `bind(selectedTab:)` (EhPanda) does by identifier.
// Tab groups and the sidebar are not here: each tab is one tab of the bar.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// A tab in a tab bar controller: its title, image and identifier, and the controller it shows.
@preconcurrency @MainActor
open class UITab {
    /// The tab's identifier, unique among the controller's tabs.
    public let identifier: String
    open var title: String { didSet { updateItem() } }
    open var image: UIImage? { didSet { updateItem() } }
    open var subtitle: String?
    open var badgeValue: String? { didSet { updateItem() } }
    open var isEnabled = true { didSet { updateItem() } }
    /// A hidden tab leaves the bar (its controller is kept).
    open var isHidden = false { didSet { if isHidden != oldValue { tabBarController?.tabsDidChange() } } }
    open var userInfo: Any?
    /// The tab bar controller that shows the tab.
    public internal(set) weak var tabBarController: UITabBarController?

    private let provider: ((UITab) -> UIViewController)?
    private var provided: UIViewController?

    public init(title: String, image: UIImage?, identifier: String, viewControllerProvider: ((UITab) -> UIViewController)? = nil) {
        self.title = title
        self.image = image
        self.identifier = identifier
        provider = viewControllerProvider
    }

    /// The tab's controller, made by the provider the first time it's asked for (an empty
    /// controller for a tab with no provider).
    open var viewController: UIViewController? { resolvedViewController }

    var resolvedViewController: UIViewController {
        if let provided { return provided }
        let controller = provider?(self) ?? UIViewController()
        provided = controller
        updateItem()
        return controller
    }

    /// The controller's bar item shows the tab's title, image, badge and state.
    private func updateItem() {
        guard let controller = provided else { return }
        let item: UITabBarItem = controller.tabBarItem
        item.title = title
        item.image = image
        item.badgeValue = badgeValue
        item.isEnabled = isEnabled
    }
}

extension UITabBarController {
    /// Makes a tab bar controller showing `tabs`.
    public convenience init(tabs: [UITab]) {
        self.init(nibName: nil, bundle: nil)
        setTabs(tabs, animated: false)
    }

    /// The tabs; setting them shows their controllers (iOS 18).
    public var tabs: [UITab] {
        get { storedTabs }
        set { setTabs(newValue, animated: false) }
    }

    public func setTabs(_ tabs: [UITab], animated: Bool) {
        let selected = selectedTab
        for tab in storedTabs where tab.tabBarController === self && !tabs.contains(where: { $0 === tab }) { tab.tabBarController = nil }
        storedTabs = tabs
        for tab in tabs { tab.tabBarController = self }
        showTabs(keeping: selected, animated: animated)
    }

    /// The tab whose controller shows; setting it selects that tab (a hidden tab or one this
    /// controller does not hold leaves the selection as it is).
    public var selectedTab: UITab? {
        get {
            guard let selected = selectedViewController else { return nil }
            return storedTabs.first { !$0.isHidden && $0.viewController === selected }
        }
        set {
            guard let tab = newValue, !tab.isHidden, storedTabs.contains(where: { $0 === tab }) else { return }
            selectedViewController = tab.resolvedViewController
        }
    }

    /// The tab with `identifier`, or nil.
    public func tab(forIdentifier identifier: String) -> UITab? { storedTabs.first { $0.identifier == identifier } }

    /// A tab was hidden or shown: the bar shows the visible ones.
    func tabsDidChange() { showTabs(keeping: selectedTab, animated: false) }

    private func showTabs(keeping selected: UITab?, animated: Bool) {
        let visible = storedTabs.filter { !$0.isHidden }
        setViewControllers(visible.map { $0.resolvedViewController }, animated: animated)
        if let selected, !selected.isHidden, visible.contains(where: { $0 === selected }) {
            selectedViewController = selected.resolvedViewController
        }
    }
}
