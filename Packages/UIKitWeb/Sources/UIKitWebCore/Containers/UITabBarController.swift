// UITabBarController and UITabBar (Docs/elements/UIKit/Navigation.md): the selected child fills
// the container; the iOS 26 tab bar is an 83 pt band at the bottom holding a floating platter
// (62 tall, one 94 × 54 button per tab overlapping by 8) with a grey lens under the selection.

/// A container view controller that manages a multiselection interface, where the selection
/// determines which child view controller to display.
@MainActor
open class UITabBarController: UIViewController {
    public let tabBar = UITabBar()
    open weak var delegate: (any UITabBarControllerDelegate)?

    open var viewControllers: [UIViewController]? {
        didSet { setViewControllers(viewControllers ?? [], animated: false) }
    }

    open var selectedIndex: Int = 0 {
        didSet { if selectedIndex != oldValue { showSelected(previous: oldValue) } }
    }

    open var selectedViewController: UIViewController? {
        get { viewControllers?.indices.contains(selectedIndex) == true ? viewControllers?[selectedIndex] : nil }
        set {
            if let controller = newValue, let index = viewControllers?.firstIndex(where: { $0 === controller }) { selectedIndex = index }
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
        tabBar.items = controllers.map { $0.tabBarItem }
        if selectedIndex >= controllers.count { selectedIndex = 0 }
        tabBar.selectedItem = tabBar.items?.indices.contains(selectedIndex) == true ? tabBar.items?[selectedIndex] : nil
        if isViewLoaded { showSelected(previous: nil) }
    }

    private func showSelected(previous: Int?) {
        guard let view = viewIfLoaded, let controllers = viewControllers else { return }
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

    open override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        guard let view = viewIfLoaded else { return }
        let height = UITabBar.barHeight + view.safeAreaInsets.bottom
        tabBar.frame = CGRect(x: 0, y: view.bounds.height - height, width: view.bounds.width, height: height)
        if let content = selectedViewController?.viewIfLoaded {
            content.frame = view.bounds
            content.containerSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: tabBar.isHidden ? 0 : height, right: 0)
        }
    }
}

/// The methods a tab bar controller's delegate implements.
@MainActor
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
@MainActor
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
        if let controller, let target = controller.viewControllers?[index] {
            guard controller.delegate?.tabBarController(controller, shouldSelect: target) ?? true else { return }
            controller.selectedIndex = index
        } else {
            selectedItem = items[index]
        }
        delegate?.tabBar(self, didSelect: items[index])
    }

    /// The platter's frame within the bar.
    var platterFrame: CGRect {
        let count = CGFloat(max(1, buttons.count))
        let width = Self.buttonSize.width + Self.buttonPitch * (count - 1) + 8
        return CGRect(x: ((bounds.width - width) / 2).rounded(), y: 0, width: width, height: Self.platterHeight)
    }

    open override func layoutSubviews() {
        super.layoutSubviews()
        let platter = platterFrame
        for (index, button) in buttons.enumerated() {
            button.frame = CGRect(x: platter.minX + 4 + Self.buttonPitch * CGFloat(index), y: platter.minY + 4, width: Self.buttonSize.width, height: Self.buttonSize.height)
            button.isSelected = button.item === selectedItem
        }
    }

    open override func sizeThatFits(_ size: CGSize) -> CGSize { CGSize(width: size.width, height: Self.barHeight) }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let platter = context.absoluteRect(platterFrame)
        let fill: RGBA = style == .dark ? RGBA(r: 44, g: 44, b: 46) : RGBA(r: 252, g: 252, b: 252)
        list.append(.beginShadow(RGBA(red: 0, green: 0, blue: 0, alpha: 0.1), radius: 12, offset: CGSize(width: 0, height: 4)))
        list.append(.fillRRect(platter, cornerRadius: platter.height / 2, fill))
        list.append(.endGroup)
    }
}

/// The methods a tab bar's delegate implements.
@MainActor
public protocol UITabBarDelegate: AnyObject {
    func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem)
}

extension UITabBarDelegate {
    public func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {}
}

/// A tab bar's appearance (accepted).
@MainActor
public final class UITabBarAppearance {
    public var backgroundColor: UIColor?
    public init() {}
    public func configureWithOpaqueBackground() {}
    public func configureWithTransparentBackground() {}
    public func configureWithDefaultBackground() {}
}

/// One tab: a 94 × 54 button with the item's symbol 28 tall at 5.5 and its 10 pt title at 35,
/// a grey lens behind the selected one (uikit/tabs/basic).
@MainActor
final class TabButton: UIControl {
    let item: UITabBarItem
    private let label = UILabel()

    init(item: UITabBarItem) {
        self.item = item
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityTraits = .button
        label.textAlignment = .center
        addSubview(label)
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
    }

    override func drawContent(into list: inout DisplayList, context: PaintContext, style: UIUserInterfaceStyle) {
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        if isSelected {
            let lens: RGBA = style == .dark ? RGBA(r: 58, g: 58, b: 60) : RGBA(r: 233, g: 234, b: 234)
            list.append(.fillRRect(rect, cornerRadius: rect.height / 2, lens))
        }
        let ink = (isSelected ? tintColor ?? .tintColor : .label).rgba(for: style)
        let image = (isSelected ? item.selectedImage : nil) ?? item.image
        if let image, image.isSystemSymbol {
            SymbolPainter.paint(name: image.name, in: context.absoluteRect(CGRect(x: (bounds.width - 28) / 2, y: 5.5, width: 28, height: 28)), color: ink, weight: isSelected ? 600 : 500, into: &list)
        }
    }

    override func decorateSemantics(_ node: inout SemanticsNode) {
        node.role = .button
        if isSelected { node.isOn = true }
    }
}
