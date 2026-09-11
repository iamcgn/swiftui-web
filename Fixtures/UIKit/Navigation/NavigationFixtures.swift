// UINavigationController and UITabBarController (Docs/elements/UIKit/Navigation.md): the
// navigation bar with an inline and a large title, a push and a pop, bar button items, and a
// tab bar with two tabs, measured against UIKit on the simulator.
#if canImport(UIKit)
import UIKit
import UIKitFixtureKit

/// A screen with a title and one label at (16, 16) of its view.
final class ScreenController: UIViewController {
    var text = ""
    var probeName = ""

    static func make(title: String, text: String, probe: String) -> ScreenController {
        let controller = ScreenController()
        controller.title = title
        controller.text = text
        controller.probeName = probe
        return controller
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 17)
        label.sizeToFit()
        label.frame.origin = CGPoint(x: 16, y: 16)
        view.addSubview(label.probe(probeName))
    }
}

@MainActor public final class NavigationModel {
    var navigation: UINavigationController?
    public init() {}
}

public enum NavigationFixtures {
    public static let all = [basic, large, push, items, tabs]

    /// An inline title bar over a screen.
    public static let basic = UIKitFixture("uikit/nav/basic", size: CGSize(width: 320, height: 400)) {
        let root = ScreenController.make(title: "Settings", text: "Content", probe: "label")
        let navigation = UINavigationController(rootViewController: root)
        navigation.navigationBar.probe("bar")
        root.view.probe("content")
        return navigation
    }

    /// A large title bar.
    public static let large = UIKitFixture("uikit/nav/large", size: CGSize(width: 320, height: 400)) {
        let root = ScreenController.make(title: "Settings", text: "Content", probe: "label")
        let navigation = UINavigationController(rootViewController: root)
        navigation.navigationBar.prefersLargeTitles = true
        navigation.navigationBar.probe("bar")
        root.view.probe("content")
        return navigation
    }

    /// A push shows the pushed screen under a bar with a back button; a pop returns.
    public static let push = UIKitFixture("uikit/nav/push", size: CGSize(width: 320, height: 400),
                                          model: { NavigationModel() },
                                          steps: [UIKitFixtureStep("push") { model in
                                                      let detail = ScreenController.make(title: "Detail", text: "Detail content", probe: "detailLabel")
                                                      model.navigation?.pushViewController(detail, animated: false)
                                                      detail.view.probe("detail")
                                                  },
                                                  UIKitFixtureStep("pop") { model in _ = model.navigation?.popViewController(animated: false) }],
                                          controller: { model in
        let root = ScreenController.make(title: "Settings", text: "Content", probe: "label")
        let navigation = UINavigationController(rootViewController: root)
        navigation.navigationBar.probe("bar")
        root.view.probe("content")
        model.navigation = navigation
        return navigation
    })

    /// Bar button items: a titled right item, a system left item.
    public static let items = UIKitFixture("uikit/nav/items", size: CGSize(width: 320, height: 400)) {
        let root = ScreenController.make(title: "Inbox", text: "Content", probe: "label")
        root.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Edit", style: .plain, target: nil, action: nil)
        root.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: nil, action: nil)
        let navigation = UINavigationController(rootViewController: root)
        navigation.navigationBar.probe("bar")
        root.view.probe("content")
        return navigation
    }

    /// Two tabs; the first is selected.
    public static let tabs = UIKitFixture("uikit/tabs/basic", size: CGSize(width: 320, height: 400)) {
        let home = ScreenController.make(title: "Home", text: "Home content", probe: "label")
        home.tabBarItem = UITabBarItem(title: "Home", image: UIImage(systemName: "house"), tag: 0)
        let search = ScreenController.make(title: "Search", text: "Search content", probe: "searchLabel")
        search.tabBarItem = UITabBarItem(title: "Search", image: UIImage(systemName: "magnifyingglass"), tag: 1)
        let tabs = UITabBarController()
        tabs.viewControllers = [home, search]
        tabs.tabBar.probe("tabBar")
        home.view.probe("content")
        return tabs
    }
}
#endif
