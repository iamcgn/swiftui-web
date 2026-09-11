// UINavigationController (Containers/UINavigationController.swift): an animated push slides the
// new screen in from the trailing edge over 0.35 s while the old one moves a third of the width
// behind a veil, and the old screen leaves when the slide ends; a pop reverses it; the delegate
// hears about both.
import Testing
import UIKit
@testable import UIKitWebCore

@Suite @MainActor struct NavigationTests {
    final class Log: UINavigationControllerDelegate {
        var shown: [String] = []
        func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
            shown.append((viewController.title ?? "?") + (animated ? "*" : ""))
        }
    }

    private func screen(_ title: String) -> UIViewController {
        let controller = UIViewController()
        controller.title = title
        controller.view.backgroundColor = .white
        return controller
    }

    @Test func pushSlidesAndPopReverses() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 300, height: 400), scale: 2)
        let root = screen("Root")
        let navigation = UINavigationController(rootViewController: root)
        let log = Log()
        navigation.delegate = log
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 300, height: 400))

        let detail = screen("Detail")
        navigation.pushViewController(detail, animated: true)
        scene.layout(in: CGSize(width: 300, height: 400))
        // The model moved at once: the detail's frame is the container's; the old screen still
        // hangs in the hierarchy for the slide.
        #expect(detail.view.frame.origin.x == 0)
        #expect(root.view.superview != nil)
        #expect(scene.isAnimating)
        #expect(navigation.navigationBar.items?.count == 2)
        // Half way through the slide the detail is painted part way across.
        _ = scene.advanceFrame(elapsed: 0.175)
        let midway = detail.view.layer.presented(.position, model: .point(detail.view.layer.position)).point.x - detail.view.bounds.width / 2
        #expect(midway > 50 && midway < 250, "\(midway)")
        // The end: the old screen has left, the delegate heard.
        _ = scene.advanceFrame(elapsed: 0.2)
        #expect(root.view.superview == nil)
        #expect(!scene.isAnimating)
        #expect(log.shown == ["Detail*"])

        let popped = navigation.popViewController(animated: true)
        #expect(popped === detail)
        scene.layout(in: CGSize(width: 300, height: 400))
        #expect(root.view.superview != nil && detail.view.superview != nil)
        _ = scene.advanceFrame(elapsed: 0.4)
        #expect(detail.view.superview == nil)
        #expect(navigation.topViewController === root)
        #expect(log.shown == ["Detail*", "Root*"])
    }

    @Test func unanimatedChangesApplyAtOnce() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 300, height: 400), scale: 2)
        let root = screen("Root")
        let navigation = UINavigationController(rootViewController: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 300, height: 400))
        navigation.pushViewController(screen("Detail"), animated: false)
        scene.layout(in: CGSize(width: 300, height: 400))
        #expect(root.view.superview == nil)
        #expect(!scene.isAnimating)
    }

    /// The top controller's toolbar items float over the bottom (leading, centred, trailing
    /// groups) and a search controller's field floats there in a capsule.
    @Test func toolbarItemsAndSearchFloatOverTheBottom() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = try! Goldens.textEngine()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        let root = UIViewController()
        root.title = "Files"
        root.toolbarItems = [
            UIBarButtonItem(title: "Edit", style: .plain, target: nil, action: nil),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace),
            UIBarButtonItem(barButtonSystemItem: .add),
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace),
            UIBarButtonItem(barButtonSystemItem: .action),
        ]
        let navigation = UINavigationController(rootViewController: root)
        navigation.isToolbarHidden = false
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 400))
        #expect(navigation.toolbar.frame == CGRect(x: 0, y: 324, width: 320, height: 76))
        let platters = scene.semanticsTree().filter { $0.role == .button && $0.frame.minY == 324 }.sorted { $0.frame.minX < $1.frame.minX }
        #expect(platters.map(\.frame.minX) == [28, 136, 244])
        #expect(root.view.safeAreaInsets.bottom == 76)

        let searching = UIViewController()
        searching.title = "Items"
        let controller = UISearchController(searchResultsController: nil)
        controller.searchBar.placeholder = "Search items"
        searching.navigationItem.searchController = controller
        navigation.pushViewController(searching, animated: false)
        scene.layout(in: CGSize(width: 320, height: 400))
        #expect(navigation.toolbar.isHidden)
        #expect(controller.searchBar.frame == CGRect(x: 0, y: 64, width: 320, height: 60))
        #expect(controller.searchBar.searchTextField.convert(controller.searchBar.searchTextField.bounds, to: nil) == CGRect(x: 33, y: 329, width: 254, height: 38))
        guard let field = scene.semanticsTree().first(where: { $0.textInput != nil }) else { Issue.record("no field"); return }
        #expect(field.textInput?.placeholder == "Search items")
        scene.textField(field.identifier, focused: true)
        scene.textField(field.identifier, didChange: "Sw")
        #expect(controller.isActive)
        #expect(controller.searchBar.text == "Sw")
    }
}
