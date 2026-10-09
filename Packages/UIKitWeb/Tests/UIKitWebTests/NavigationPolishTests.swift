// Navigation polish (uk-nav-polish): the interactive edge-pan pop, the large title collapsing as
// the content scrolls, title view sizing, hidesBottomBarWhenPushed, and custom transitions for
// presentations and pushes through the transitioning protocols.
import Testing
import UIKit

@Suite @MainActor struct NavigationPolishTests {
    @MainActor final class Log: UINavigationControllerDelegate {
        var shown: [String] = []
        var animator: (any UIViewControllerAnimatedTransitioning)?
        func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
            shown.append(viewController.title ?? "?")
        }
        func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation,
                                  from fromVC: UIViewController, to toVC: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? { animator }
    }

    private func screen(_ title: String) -> UIViewController {
        let controller = UIViewController()
        controller.title = title
        controller.view.backgroundColor = .white
        return controller
    }

    private func scene(size: CGSize = CGSize(width: 300, height: 400)) -> (UIKitScene, UIWindow) {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: size, scale: 2)
        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        return (scene, window)
    }

    @Test func edgePanPopsInteractively() {
        let (scene, window) = scene()
        let root = screen("Root"), detail = screen("Detail")
        let navigation = UINavigationController(rootViewController: root)
        let log = Log()
        navigation.delegate = log
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 300, height: 400))
        navigation.pushViewController(detail, animated: false)
        scene.layout(in: CGSize(width: 300, height: 400))
        #expect(navigation.interactivePopGestureRecognizer is UIScreenEdgePanGestureRecognizer)
        // The finger drags the detail across; the root slides in behind it.
        scene.pointerDown(at: CGPoint(x: 8, y: 200), type: .touch, time: 0)
        scene.pointerMoved(to: CGPoint(x: 100, y: 200), time: 0.1)
        #expect(detail.view.frame.origin.x == 92)
        #expect(root.view.superview != nil && abs(root.view.frame.origin.x + 100 * (1 - 92.0 / 300)) < 0.01)
        scene.pointerMoved(to: CGPoint(x: 200, y: 200), time: 0.2)
        scene.pointerUp(at: CGPoint(x: 200, y: 200), time: 0.3)
        scene.layout(in: CGSize(width: 300, height: 400))
        #expect(scene.isAnimating)
        _ = scene.advanceFrame(elapsed: 0.3)
        #expect(navigation.topViewController === root)
        #expect(detail.view.superview == nil && root.view.frame.origin.x == 0)
        #expect(log.shown.last == "Root")
        // A short, slow drag cancels: the detail settles back and the root leaves again.
        navigation.pushViewController(detail, animated: false)
        scene.layout(in: CGSize(width: 300, height: 400))
        scene.pointerDown(at: CGPoint(x: 8, y: 200), type: .touch, time: 1)
        scene.pointerMoved(to: CGPoint(x: 60, y: 200), time: 1.5)
        scene.pointerUp(at: CGPoint(x: 60, y: 200), time: 1.8)
        _ = scene.advanceFrame(elapsed: 0.3)
        #expect(navigation.topViewController === detail && root.view.superview == nil && detail.view.frame.origin.x == 0)
        // A drag starting away from the edge does nothing.
        scene.pointerDown(at: CGPoint(x: 100, y: 200), type: .touch, time: 2)
        scene.pointerMoved(to: CGPoint(x: 250, y: 200), time: 2.1)
        scene.pointerUp(at: CGPoint(x: 250, y: 200), time: 2.2)
        _ = scene.advanceFrame(elapsed: 0.3)
        #expect(navigation.topViewController === detail && detail.view.frame.origin.x == 0)
    }

    @Test func largeTitleCollapsesWhenTheContentScrolls() {
        let (scene, window) = scene()
        let root = screen("Inbox")
        let scroll = UIScrollView(frame: root.view.bounds)
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.contentSize = CGSize(width: 300, height: 2000)
        root.view.addSubview(scroll)
        let navigation = UINavigationController(rootViewController: root)
        navigation.navigationBar.prefersLargeTitles = true
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 300, height: 400))
        #expect(navigation.navigationBar.frame.height == 106.5)
        #expect(root.view.safeAreaInsets.top == 116.5 && scroll.contentOffset.y == -116.5)
        // Scrolling past the large title collapses the bar; the offset follows the shrunken
        // inset, so the content rises by the collapse (uikit/nav/search-results).
        scroll.contentOffset.y += 60
        scene.layout(in: CGSize(width: 300, height: 400))
        #expect(navigation.navigationBar.frame.height == 54)
        #expect(root.view.safeAreaInsets.top == 64 && scroll.contentOffset.y == -4)
        // Scrolling back keeps it collapsed until the content is back at its rest under the bar.
        scroll.contentOffset.y -= 5
        scene.layout(in: CGSize(width: 300, height: 400))
        #expect(navigation.navigationBar.frame.height == 54)
        scroll.contentOffset.y = -64
        scene.layout(in: CGSize(width: 300, height: 400))
        #expect(navigation.navigationBar.frame.height == 106.5 && scroll.contentOffset.y == -116.5)
        // A wheel pull past the top at rest changes nothing.
        scene.scrollWheel(by: CGSize(width: 0, height: -10), at: CGPoint(x: 150, y: 300))
        scene.layout(in: CGSize(width: 300, height: 400))
        #expect(navigation.navigationBar.frame.height == 106.5 && scroll.contentOffset.y == -116.5)
        // A push starts the new screen with its own large title at rest.
        scroll.contentOffset.y += 60
        scene.layout(in: CGSize(width: 300, height: 400))
        let detail = screen("Message")
        detail.navigationItem.largeTitleDisplayMode = .always
        navigation.pushViewController(detail, animated: false)
        scene.layout(in: CGSize(width: 300, height: 400))
        #expect(navigation.navigationBar.frame.height == 106.5)
    }

    @Test func pushedControllersHideTheTabBar() {
        let (scene, window) = scene()
        let root = screen("Feed")
        let navigation = UINavigationController(rootViewController: root)
        let tabs = UITabBarController()
        tabs.viewControllers = [navigation, screen("Other")]
        window.rootViewController = tabs
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 300, height: 400))
        #expect(!tabs.tabBar.isHidden && navigation.view.safeAreaInsets.bottom == 83)
        let detail = screen("Post")
        detail.hidesBottomBarWhenPushed = true
        navigation.pushViewController(detail, animated: false)
        scene.layout(in: CGSize(width: 300, height: 400))
        #expect(tabs.tabBar.isHidden && navigation.view.safeAreaInsets.bottom == 0)
        navigation.pushViewController(screen("Reply"), animated: false)
        scene.layout(in: CGSize(width: 300, height: 400))
        #expect(tabs.tabBar.isHidden)
        _ = navigation.popToRootViewController(animated: false)
        scene.layout(in: CGSize(width: 300, height: 400))
        #expect(!tabs.tabBar.isHidden && navigation.view.safeAreaInsets.bottom == 83)
    }

    @MainActor final class Fade: NSObject, UIViewControllerAnimatedTransitioning, UIViewControllerTransitioningDelegate {
        var ended: [Bool] = []
        var seen: [String] = []
        let duration = 0.2
        func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> Double { duration }
        func animateTransition(using context: any UIViewControllerContextTransitioning) {
            let to = context.viewController(forKey: .to), from = context.viewController(forKey: .from)
            seen.append("\(from?.title ?? "-")>\(to?.title ?? "-")")
            if let toView = context.view(forKey: .to), toView.superview == nil || to?.presentingViewController != nil {
                context.containerView.addSubview(toView)
                toView.frame = context.finalFrame(for: to!)
                toView.alpha = 0
                UIView.animate(withDuration: duration, animations: { toView.alpha = 1 }, completion: { _ in context.completeTransition(true) })
            } else if let fromView = context.view(forKey: .from) {
                UIView.animate(withDuration: duration, animations: { fromView.alpha = 0 }, completion: { _ in context.completeTransition(true) })
            }
        }
        func animationEnded(_ transitionCompleted: Bool) { ended.append(transitionCompleted) }
        func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? { self }
        func animationController(forDismissed dismissed: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? { self }
    }

    @Test func customPresentationTransitions() {
        let (scene, window) = scene(size: CGSize(width: 320, height: 500))
        let root = screen("Root")
        window.rootViewController = root
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 500))
        let fade = Fade()
        let modal = screen("Modal")
        modal.modalPresentationStyle = .custom
        modal.transitioningDelegate = fade
        var presented = false
        root.present(modal, animated: true) { presented = true }
        scene.layout(in: CGSize(width: 320, height: 500))
        #expect(scene.isAnimating && !presented)
        #expect(fade.seen == ["Root>Modal"])
        #expect(modal.view.frame == window.bounds)
        _ = scene.advanceFrame(elapsed: 0.3)
        #expect(presented && fade.ended == [true] && modal.view.alpha == 1)
        var dismissed = false
        modal.dismiss(animated: true) { dismissed = true }
        #expect(fade.seen == ["Root>Modal", "Modal>Root"])
        #expect(window.subviews.count == 2)
        _ = scene.advanceFrame(elapsed: 0.3)
        #expect(dismissed && fade.ended == [true, true] && window.subviews.count == 1)
    }

    @Test func customPushTransitions() {
        let (scene, window) = scene()
        let root = screen("Root")
        let navigation = UINavigationController(rootViewController: root)
        let log = Log()
        let fade = Fade()
        log.animator = fade
        navigation.delegate = log
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 300, height: 400))
        let detail = screen("Detail")
        navigation.pushViewController(detail, animated: true)
        scene.layout(in: CGSize(width: 300, height: 400))
        #expect(fade.seen == ["Root>Detail"])
        #expect(detail.view.frame == navigation.view.bounds && root.view.superview != nil)
        #expect(scene.isAnimating)
        _ = scene.advanceFrame(elapsed: 0.3)
        #expect(root.view.superview == nil && fade.ended == [true] && log.shown.last == "Detail")
    }

    final class Sized: UIView {
        override var intrinsicContentSize: CGSize { CGSize(width: 100, height: 30) }
    }

    @Test func titleViewsTakeTheirSize() {
        let (scene, window) = scene()
        let root = screen("Root")
        let custom = Sized()
        root.navigationItem.titleView = custom
        root.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Edit", primaryAction: nil)
        let navigation = UINavigationController(rootViewController: root)
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        scene.textEngine = try! Goldens.textEngine()
        scene.layout(in: CGSize(width: 300, height: 400))
        #expect(custom.frame == CGRect(x: 100, y: 7, width: 100, height: 30))
        // Too wide to centre: it moves off centre to keep clear of the items.
        let wide = UIView()
        wide.frame.size = CGSize(width: 260, height: 20)
        root.navigationItem.titleView = wide
        scene.layout(in: CGSize(width: 300, height: 400))
        #expect(wide.frame.maxX <= 300 - 16 - 54.5 - 8 + 0.01 && wide.frame.minX >= 24)
    }
}
