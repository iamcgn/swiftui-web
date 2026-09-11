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
}
