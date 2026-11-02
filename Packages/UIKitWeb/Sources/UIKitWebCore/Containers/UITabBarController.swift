// UITabBarController and UITabBar (Docs/elements/UIKit/Navigation.md): the selected child fills
// the container; the iOS 26 tab bar is an 83 pt band at the bottom holding a floating platter
// (62 tall, one 94 × 54 button per tab overlapping by 8) with a grey lens under the selection.

#if os(WASI)
import WebFoundation
#else
import Foundation
#endif

/// A container view controller that manages a multiselection interface, where the selection
/// determines which child view controller to display.
@preconcurrency @MainActor
open class UITabBarController: UIViewController {
    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    public required init?(coder: NSCoder) { return nil }

    public let tabBar = UITabBar()
    open weak var delegate: (any UITabBarControllerDelegate)?

    open var viewControllers: [UIViewController]? {
        didSet { setViewControllers(viewControllers ?? [], animated: false) }
    }

    /// The bar shows at most five tabs: with more controllers the fifth is More, a navigation
    /// controller listing the rest (uikit/tabs/more; `moreNavigationController`).
    static let maximumTabs = 5
    public private(set) lazy var moreNavigationController: UINavigationController = {
        let list = _MoreListController(tabs: self)
        let navigation = UINavigationController(rootViewController: list)
        navigation.tabBarItem = UITabBarItem(tabBarSystemItem: .more, tag: 0)
        return navigation
    }()
    /// The controllers the More list holds (those past the fourth).
    public var overflowControllers: [UIViewController] {
        guard let controllers = viewControllers, controllers.count > Self.maximumTabs else { return [] }
        return Array(controllers.dropFirst(Self.maximumTabs - 1))
    }
    /// The controllers whose tabs the bar shows: all of them, or the first four and More.
    public var tabControllers: [UIViewController] {
        guard let controllers = viewControllers else { return [] }
        if controllers.count <= Self.maximumTabs { return controllers }
        return Array(controllers.prefix(Self.maximumTabs - 1)) + [moreNavigationController]
    }
    /// The controllers the user may reorder in More's Edit screen (accepted: no edit screen).
    open var customizableViewControllers: [UIViewController]?

    open var selectedIndex: Int = 0 {
        didSet { if selectedIndex != oldValue { showSelected(previous: oldValue) } }
    }

    open var selectedViewController: UIViewController? {
        get {
            let tabs = tabControllers
            return tabs.indices.contains(selectedIndex) ? tabs[selectedIndex] : nil
        }
        set {
            guard let controller = newValue else { return }
            if let index = tabControllers.firstIndex(where: { $0 === controller }) { selectedIndex = index }
            else if overflowControllers.contains(where: { $0 === controller }) {
                selectedIndex = Self.maximumTabs - 1
                moreNavigationController.pushViewController(controller, animated: false)
            }
        }
    }

    public override init(nibName: String? = nil, bundle: Any? = nil) {
        super.init(nibName: nibName, bundle: bundle)
        tabBar.controller = self
    }

    open override func loadView() {
        let view = UIView(frame: UIScreen.main.bounds)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.backgroundColor = .systemBackground
        self.view = view
        view.addSubview(tabBar)
        showSelected(previous: nil)
    }

    open func setViewControllers(_ controllers: [UIViewController], animated: Bool) {
        for child in children where !controllers.contains(where: { $0 === child }) {
            child.viewIfLoaded?.removeFromSuperview()
            child.removeFromParent()
        }
        for controller in controllers where controller.parent !== self {
            addChild(controller)
            controller.didMove(toParent: self)
        }
        if viewControllers.map({ $0.map { ObjectIdentifier($0) } }) != controllers.map({ ObjectIdentifier($0) }) { viewControllers = controllers; return }
        if controllers.count > Self.maximumTabs, moreNavigationController.parent !== self {
            addChild(moreNavigationController)
            moreNavigationController.didMove(toParent: self)
        }
        tabBar.items = tabControllers.map { $0.tabBarItem }
        if selectedIndex >= tabControllers.count { selectedIndex = 0 }
        tabBar.selectedItem = tabBar.items?.indices.contains(selectedIndex) == true ? tabBar.items?[selectedIndex] : nil
        if isViewLoaded { showSelected(previous: nil) }
    }

    private func showSelected(previous: Int?) {
        guard let view = viewIfLoaded else { return }
        let controllers = tabControllers
        if let previous, controllers.indices.contains(previous), previous != selectedIndex, let old = controllers[previous].viewIfLoaded {
            if hasAppeared { controllers[previous].beginAppearanceTransition(false, animated: false) }
            old.removeFromSuperview()
            if hasAppeared { controllers[previous].endAppearanceTransition() }
        }
        if let selected = selectedViewController {
            let content = selected.view!
            if content.superview !== view {
                content.frame = view.bounds
                content.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                if hasAppeared { selected.beginAppearanceTransition(true, animated: false) }
                view.insertSubview(content, belowSubview: tabBar)
                if hasAppeared { selected.endAppearanceTransition() }
            }
            tabBar.selectedItem = selected.tabBarItem
            delegate?.tabBarController(self, didSelect: selected)
        }
        view.setNeedsLayout()
    }

    /// Whether the selected navigation stack has a pushed controller hiding the bar.
    var hidesTabBarForPushedController: Bool {
        guard let navigation = selectedViewController as? UINavigationController else { return false }
        return navigation.viewControllers.dropFirst().contains { $0.hidesBottomBarWhenPushed }
    }

    open override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        guard let view = viewIfLoaded else { return }
        let height = UITabBar.barHeight + view.safeAreaInsets.bottom
        tabBar.frame = CGRect(x: 0, y: view.bounds.height - height, width: view.bounds.width, height: height)
        // A controller pushed with `hidesBottomBarWhenPushed` (or any above it) hides the bar.
        tabBar.isHidden = hidesTabBarForPushedController
        if let content = selectedViewController?.viewIfLoaded {
            content.frame = view.bounds
            content.containerSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: tabBar.isHidden ? 0 : height, right: 0)
        }
    }
}

/// The methods a tab bar controller's delegate implements.
@preconcurrency @MainActor
public protocol UITabBarControllerDelegate: AnyObject {
    func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool
    func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController)
}

extension UITabBarControllerDelegate {
    public func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool { true }
    public func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {}
}

/// A control that displays one or more buttons in a tab bar for selecting between different
/// subtasks, views, or modes in an app.
@preconcurrency @MainActor
open class UITabBar: UIView {
    /// The band at the bottom (uikit/tabs/basic: 83 with no home indicator).
    static let barHeight: CGFloat = 83
    static let platterHeight: CGFloat = 62
    static let buttonSize = CGSize(width: 94, height: 54)
    /// Buttons sit 4 in and overlap by 8: the platter is 94 + 86 × (n − 1) + 8 wide.
    static let buttonPitch: CGFloat = 86

    open var items: [UITabBarItem]? { didSet { rebuild() } }
    open var selectedItem: UITabBarItem? { didSet { setNeedsDisplay() } }
    open weak var delegate: (any UITabBarDelegate)?
    open var tintColor2: UIColor?
    open var unselectedItemTintColor: UIColor?
    open var isTranslucent = true
    open var standardAppearance = UITabBarAppearance()
    open var scrollEdgeAppearance: UITabBarAppearance?
    weak var controller: UITabBarController?
    private var buttons: [TabButton] = []

    private func rebuild() {
        for button in buttons { button.removeFromSuperview() }
        buttons = (items ?? []).enumerated().map { index, item in
            let button = TabButton(item: item)
            button.addAction(UIAction { [weak self] _ in self?.select(index) }, for: .primaryActionTriggered)
            item.onChange = { [weak self] in self?.setNeedsLayout() }
            addSubview(button)
            return button
        }
        setNeedsLayout()
    }

    private func select(_ index: Int) {
        guard let items, items.indices.contains(index) else { return }
        if let controller, controller.tabControllers.indices.contains(index) {
            let target = controller.tabControllers[index]
            guard controller.delegate?.tabBarController(controller, shouldSelect: target) ?? true else { return }
            controller.selectedIndex = index
        } else {
            selectedItem = items[index]
        }
        delegate?.tabBar(self, didSelect: items[index])
    }

    /// The platter keeps 21 pt margins (uikit/tabs/more: 278 in 320): when the natural buttons
    /// would overflow it they shrink, their overlap growing by half the shrink (five tabs: 70
    /// wide, 50 apart).
    static let platterMargin: CGFloat = 21
    public var buttonWidth: CGFloat {
        let count = CGFloat(max(1, buttons.count))
        let natural = Self.buttonSize.width + Self.buttonPitch * (count - 1) + 8
        let maximum = bounds.width - 2 * Self.platterMargin
        guard natural > maximum, count > 1, maximum > 0 else { return Self.buttonSize.width }
        let shrink = (natural - maximum) / (1 + 1.5 * (count - 1))
        return max(44, Self.buttonSize.width - shrink)
    }
    public var buttonPitch: CGFloat {
        let shrink = Self.buttonSize.width - buttonWidth
        return Self.buttonPitch - 1.5 * shrink
    }

    /// The platter's frame within the bar.
    public var platterFrame: CGRect {
        let count = CGFloat(max(1, buttons.count))
        let width = buttonWidth + buttonPitch * (count - 1) + 8
        return CGRect(x: ((bounds.width - width) / 2).rounded(), y: 0, width: width, height: Self.platterHeight)
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        let platter = platterFrame
        let width = buttonWidth, pitch = buttonPitch
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: platter.minX + 4 + pitch * CGFloat(index), y: platter.minY + 4, width: width, height: Self.buttonSize.height)
            button.isSelected = button.item === selectedItem
        }
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: Self.barHeight) }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        GlassPainter.paintPlatter(context.absoluteRect(platterFrame), style: style, shadow: 0.1, into: &list)
    }
}

/// The methods a tab bar's delegate implements.
@preconcurrency @MainActor
public protocol UITabBarDelegate: AnyObject {
    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem)
}

extension UITabBarDelegate {
    public func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {}
}

/// A tab bar's appearance (accepted).
@preconcurrency @MainActor
public final class UITabBarAppearance {
    public var backgroundColor: UIColor?
    public init() {}
    public func configureWithOpaqueBackground() {}
    public func configureWithTransparentBackground() {}
    public func configureWithDefaultBackground() {}
}

/// One tab: a 94 × 54 button with the item's symbol 28 tall at 5.5 and its 10 pt title at 35,
/// a grey lens behind the selected one (uikit/tabs/basic).
@preconcurrency @MainActor
final class TabButton: UIControl {
    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    required init?(coder: NSCoder) { return nil }

    let item: UITabBarItem
    private let label = UILabel()
    /// The badge (uikit/tabs/more): a red capsule 21.5 tall centred 5.5 past the image box's
    /// trailing edge, 6 from the top, its 12 pt medium white label 4 in; a count is round.
    private let badge = UIView()
    private let badgeLabel = UILabel()

    init(item: UITabBarItem) {
        self.item = item
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityTraits = .button
        label.textAlignment = .center
        addSubview(label)
        badge.layer.cornerRadius = 10.75
        badge.layer.masksToBounds = true
        badgeLabel.font = .systemFont(ofSize: 12, weight: .medium)
        badgeLabel.textColor = .white
        badgeLabel.textAlignment = .center
        badge.addSubview(badgeLabel)
        addSubview(badge)
    }

    override var accessibilityLabel: String? {
        get { super.accessibilityLabel ?? item.title }
        set { super.accessibilityLabel = newValue }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.text = item.title
        label.font = .systemFont(ofSize: 10, weight: isSelected ? .semibold : .medium)
        label.textColor = isSelected ? tintColor : .label
        let width = label.intrinsicContentSize.width
        label.frame = CGRect(x: ((bounds.width - width) / 2 * 2).rounded() / 2, y: 35, width: width, height: 12)
        if let value = item.badgeValue, !value.isEmpty {
            badge.isHidden = false
            badge.backgroundColor = item.badgeColor ?? .systemRed
            badgeLabel.text = value
            let labelWidth = badgeLabel.intrinsicContentSize.width
            let badgeWidth = max(21.5, labelWidth + 8)
            badge.frame = CGRect(x: (bounds.width + 28) / 2 + 5.5 - badgeWidth / 2, y: 6, width: badgeWidth, height: 21.5)
            badgeLabel.frame = CGRect(x: 4, y: 2, width: badgeWidth - 8, height: 17.5)
        } else {
            badge.isHidden = true
        }
    }

    override var accessibilityValue: String? {
        get { super.accessibilityValue ?? item.badgeValue }
        set { super.accessibilityValue = newValue }
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        if isSelected {
            // The lens darkens the glass under it: 233 over the 252 platter, the content showing
            // through over colour (ios/representable/hostingsafearea-tabs).
            let lens: RGBA = style == .dark ? RGBA(red: 1, green: 1, blue: 1, alpha: 0.08) : RGBA(red: 0, green: 0, blue: 0, alpha: 0.075)
            list.append(.fillRRect(rect, cornerRadius: rect.height / 2, lens))
        }
        let ink = (isSelected ? tintColor ?? .tintColor : .label).rgba(for: style)
        let image = (isSelected ? item.selectedImage : nil) ?? item.image
        let imageBox = CGRect(x: (bounds.width - 28) / 2, y: 5.5, width: 28, height: 28)
        if let image, image.isSystemSymbol {
            SymbolPainter.paint(name: image.name, in: context.absoluteRect(imageBox), color: ink, weight: isSelected ? 600 : 500, into: &list)
        }
    }

    override func decorateSemantics(_ node: inout SemanticsNode) {
        node.role = .button
        if isSelected { node.isOn = true }
    }
}

/// The More tab's list: a row per overflowing controller, its tab item's image and title; a
/// tap pushes the controller onto the More navigation stack.
@preconcurrency @MainActor
public final class _MoreListController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    /// No archive to decode on the web: nil, as for an archive this class cannot read.
    public required init?(coder: NSCoder) { return nil }

    unowned let tabs: UITabBarController
    private let table = UITableView(frame: .zero, style: .plain)

    init(tabs: UITabBarController) {
        self.tabs = tabs
        super.init(nibName: nil, bundle: nil)
        title = "More"
    }

    override public func loadView() {
        table.frame = UIScreen.main.bounds
        table.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        table.dataSource = self
        table.delegate = self
        view = table
    }

    override public func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        table.reloadData()
    }

    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { tabs.overflowControllers.count }

    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "more") ?? UITableViewCell(style: .default, reuseIdentifier: "more")
        let controller = tabs.overflowControllers[indexPath.row]
        cell.textLabel?.text = controller.tabBarItem.title ?? controller.title
        cell.imageView?.image = controller.tabBarItem.image
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: false)
        let controller = tabs.overflowControllers[indexPath.row]
        tabs.moreNavigationController.pushViewController(controller, animated: true)
        tabs.delegate?.tabBarController(tabs, didSelect: controller)
    }
}
