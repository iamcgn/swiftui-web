// The items bars show (Docs/elements/UIKit/Navigation.md): a navigation item per view
// controller (title, bar button items, large title mode), bar button items (a title, an image
// or a system item, with an action), tab bar items.

/// An abstract superclass for items that can be added to a bar that appears at the bottom or
/// top of the screen.
@MainActor
open class UIBarItem {
    open var title: String? { didSet { itemDidChange() } }
    open var image: UIImage? { didSet { itemDidChange() } }
    open var isEnabled = true { didSet { itemDidChange() } }
    open var tag = 0
    open var imageInsets = UIEdgeInsets.zero
    open var accessibilityLabel: String?
    open var accessibilityIdentifier: String?

    public init() {}

    /// The bar showing the item, told when it changes.
    var onChange: (@MainActor () -> Void)?
    func itemDidChange() { onChange?() }
}

/// A specialized button for placement on a toolbar, navigation bar, or shortcuts bar.
@MainActor
open class UIBarButtonItem: UIBarItem {
    public enum Style: Int, Sendable { case plain = 0, done = 2 }
    public enum SystemItem: Int, Sendable {
        case done = 0, cancel, edit, save, add, flexibleSpace, fixedSpace, compose, reply, action, organize, bookmarks, search, refresh, stop, camera, trash, play, pause, rewind, fastForward, undo, redo, close
    }

    open var style: Style = .plain
    open var systemItem: SystemItem?
    open var width: CGFloat = 0
    open var tintColor: UIColor?
    open var primaryAction: UIAction? { didSet { itemDidChange() } }
    open var menu: UIMenu?
    /// The target and action of the classic initializer are kept for `#selector`-free
    /// dispatch through `primaryAction`; there is no Objective-C runtime to send them with.
    open weak var target: AnyObject?
    open var action: Any?

    public override init() { super.init() }

    public convenience init(title: String?, style: Style = .plain, target: AnyObject? = nil, action: Any? = nil) {
        self.init()
        self.title = title
        self.style = style
        self.target = target
        self.action = action
    }

    public convenience init(image: UIImage?, style: Style = .plain, target: AnyObject? = nil, action: Any? = nil) {
        self.init()
        self.image = image
        self.style = style
        self.target = target
        self.action = action
    }

    public convenience init(barButtonSystemItem systemItem: SystemItem, target: AnyObject? = nil, action: Any? = nil) {
        self.init()
        self.systemItem = systemItem
        self.target = target
        self.action = action
    }

    public convenience init(title: String? = nil, image: UIImage? = nil, primaryAction: UIAction?, menu: UIMenu? = nil) {
        self.init()
        self.title = title ?? primaryAction?.title
        self.image = image ?? primaryAction?.image
        self.primaryAction = primaryAction
        self.menu = menu
    }

    public convenience init(systemItem: SystemItem, primaryAction: UIAction?, menu: UIMenu? = nil) {
        self.init()
        self.systemItem = systemItem
        self.primaryAction = primaryAction
        self.menu = menu
    }

    /// The symbol a system item shows (the substrate's glyph table names).
    var systemImageName: String? {
        switch systemItem {
        case .add?: return "plus"
        case .done?, .save?: return nil
        case .edit?: return nil
        case .compose?: return "square.and.pencil"
        case .reply?: return "arrowshape.turn.up.left"
        case .action?: return "square.and.arrow.up"
        case .organize?: return "folder"
        case .bookmarks?: return "book"
        case .search?: return "magnifyingglass"
        case .refresh?: return "arrow.clockwise"
        case .stop?: return "xmark"
        case .camera?: return "camera"
        case .trash?: return "trash"
        case .play?: return "play.fill"
        case .pause?: return "pause.fill"
        case .rewind?: return "backward.fill"
        case .fastForward?: return "forward.fill"
        case .undo?: return "arrow.uturn.backward"
        case .redo?: return "arrow.uturn.forward"
        case .close?: return "xmark"
        default: return nil
        }
    }

    /// The title a system item shows.
    var systemTitle: String? {
        switch systemItem {
        case .done?: return "Done"
        case .cancel?: return "Cancel"
        case .edit?: return "Edit"
        case .save?: return "Save"
        default: return nil
        }
    }

    var isSpace: Bool { systemItem == .flexibleSpace || systemItem == .fixedSpace }
}

/// A menu (accepted for bar items and buttons; not shown).
@MainActor
public final class UIMenu {
    public let title: String
    public let children: [UIAction]
    public init(title: String = "", children: [UIAction] = []) {
        self.title = title
        self.children = children
    }
}

/// An item in a tab bar.
@MainActor
open class UITabBarItem: UIBarItem {
    public enum SystemItem: Int, Sendable { case more = 0, favorites, featured, topRated, recents, contacts, history, bookmarks, search, downloads, mostRecent, mostViewed }

    open var selectedImage: UIImage?
    open var badgeValue: String? { didSet { itemDidChange() } }
    open var badgeColor: UIColor?

    public override init() { super.init() }

    public convenience init(title: String?, image: UIImage?, tag: Int) {
        self.init()
        self.title = title
        self.image = image
        self.tag = tag
    }

    public convenience init(title: String?, image: UIImage?, selectedImage: UIImage?) {
        self.init()
        self.title = title
        self.image = image
        self.selectedImage = selectedImage
    }

    public convenience init(tabBarSystemItem systemItem: SystemItem, tag: Int) {
        self.init()
        self.tag = tag
        switch systemItem {
        case .search: title = "Search"; image = UIImage(systemName: "magnifyingglass")
        case .favorites: title = "Favorites"; image = UIImage(systemName: "star")
        case .bookmarks: title = "Bookmarks"; image = UIImage(systemName: "book")
        case .history, .recents: title = systemItem == .history ? "History" : "Recents"; image = UIImage(systemName: "clock")
        case .contacts: title = "Contacts"; image = UIImage(systemName: "person")
        case .downloads: title = "Downloads"; image = UIImage(systemName: "arrow.down.circle")
        default: title = "More"; image = UIImage(systemName: "ellipsis")
        }
    }
}

/// The items a navigation bar shows for a view controller.
@MainActor
open class UINavigationItem {
    public enum LargeTitleDisplayMode: Int, Sendable { case automatic = 0, always, never, inline }
    public enum BackButtonDisplayMode: Int, Sendable { case `default` = 0, generic, minimal }

    open var title: String? { didSet { onChange?() } }
    open var titleView: UIView? { didSet { onChange?() } }
    open var prompt: String?
    open var backButtonTitle: String? { didSet { onChange?() } }
    open var backButtonDisplayMode: BackButtonDisplayMode = .default
    open var hidesBackButton = false { didSet { onChange?() } }
    open var largeTitleDisplayMode: LargeTitleDisplayMode = .automatic { didSet { onChange?() } }
    open var leftBarButtonItems: [UIBarButtonItem]? { didSet { onChange?() } }
    open var rightBarButtonItems: [UIBarButtonItem]? { didSet { onChange?() } }
    open var leftItemsSupplementBackButton = false
    open var backBarButtonItem: UIBarButtonItem?
    open var searchController: AnyObject?
    open var hidesSearchBarWhenScrolling = true

    open var leftBarButtonItem: UIBarButtonItem? {
        get { leftBarButtonItems?.first }
        set { leftBarButtonItems = newValue.map { [$0] } }
    }
    open var rightBarButtonItem: UIBarButtonItem? {
        get { rightBarButtonItems?.first }
        set { rightBarButtonItems = newValue.map { [$0] } }
    }

    public init() {}
    public init(title: String) { self.title = title }

    open func setRightBarButton(_ item: UIBarButtonItem?, animated: Bool) { rightBarButtonItem = item }
    open func setLeftBarButton(_ item: UIBarButtonItem?, animated: Bool) { leftBarButtonItem = item }
    open func setHidesBackButton(_ hidesBackButton: Bool, animated: Bool) { self.hidesBackButton = hidesBackButton }

    /// The bar showing the item.
    var onChange: (@MainActor () -> Void)?
}

extension UIViewController {
    /// The navigation item used to represent the view controller in a parent's navigation bar.
    public var navigationItem: UINavigationItem {
        if let item = storedNavigationItem { return item }
        let item = UINavigationItem()
        item.title = title
        storedNavigationItem = item
        return item
    }

    /// The tab bar item that represents the view controller in a tab bar.
    public var tabBarItem: UITabBarItem! {
        get {
            if let item = storedTabBarItem { return item }
            let item = UITabBarItem()
            item.title = title
            storedTabBarItem = item
            return item
        }
        set { storedTabBarItem = newValue }
    }

    /// The nearest ancestor that is a navigation controller.
    public var navigationController: UINavigationController? {
        var node: UIViewController? = parent
        while let current = node {
            if let navigation = current as? UINavigationController { return navigation }
            node = current.parent
        }
        return nil
    }

    /// The nearest ancestor that is a tab bar controller.
    public var tabBarController: UITabBarController? {
        var node: UIViewController? = parent
        while let current = node {
            if let tabs = current as? UITabBarController { return tabs }
            node = current.parent
        }
        return nil
    }
}
