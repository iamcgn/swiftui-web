// A navigation controller delegate that forwards to another one asks, for each optional method,
// whether that one implements it (`base?.navigationController?(...)`), as swift-navigation's
// NavigationStackController does. That needs the `@objc` protocol of optional methods UIKit
// declares, and so everything the methods take or return representable in Objective-C:
// the orientation mask (a C option set), the orientation and the operation (`@objc` enums), the
// transition protocols and their keys.
import Testing
import UIKit

@Suite @MainActor struct NavigationDelegateForwardingTests {
    @Test func orientationMaskKeepsUIKitsValues() {
        #expect(UIInterfaceOrientationMask.portrait.rawValue == 2)
        #expect(UIInterfaceOrientationMask.landscape == [.landscapeLeft, .landscapeRight])
        #expect(UIInterfaceOrientationMask.all == [.portrait, .portraitUpsideDown, .landscapeLeft, .landscapeRight])
        #expect(UIInterfaceOrientationMask.allButUpsideDown.rawValue == 26)
        #expect(Set([UIInterfaceOrientationMask.portrait, .portrait]).count == 1)
        #expect(UIViewController().supportedInterfaceOrientations == .allButUpsideDown)
    }

    /// A subclass sets its stack through `viewControllers` and calls UIKit's bar-class
    /// initializer (swift-navigation's NavigationStackController does both).
    final class Stack: UINavigationController {
        init(root: UIViewController) {
            super.init(navigationBarClass: nil, toolbarClass: nil)
            viewControllers = [root]
        }
        required init?(coder: NSCoder) { nil }
    }

    @Test func aSubclassSetsItsStack() {
        let root = UIViewController(), detail = UIViewController()
        let stack = Stack(root: root)
        #expect(stack.viewControllers.count == 1 && stack.topViewController === root && root.parent === stack)
        stack.viewControllers = [root, detail]
        #expect(stack.topViewController === detail && detail.navigationController === stack)
        stack.viewControllers = [detail]
        #expect(root.parent == nil && stack.viewControllers.count == 1)
    }

    @Test func alertActionsCarryTheirAccessibilityLabel() {
        let action = UIAlertAction(title: "OK", style: .default)
        #expect(action.accessibilityLabel == nil)
        action.accessibilityLabel = "Confirm"
        #expect(action.accessibilityLabel == "Confirm")
    }

    #if canImport(ObjectiveC)
    /// Implements only `didShow` and the animator.
    final class Partial: NSObject, UINavigationControllerDelegate {
        var shown: [String] = []
        var animator: (any UIViewControllerAnimatedTransitioning)?
        func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
            shown.append(viewController.title ?? "?")
        }
        func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation,
                                  from fromVC: UIViewController, to toVC: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? { animator }
    }

    /// Implements every method by forwarding it to `base` when `base` implements it.
    final class Forwarder: NSObject, UINavigationControllerDelegate {
        weak var base: (any UINavigationControllerDelegate)?
        var willShow: [String] = []
        func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
            willShow.append(viewController.title ?? "?")
            base?.navigationController?(navigationController, willShow: viewController, animated: animated)
        }
        func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
            base?.navigationController?(navigationController, didShow: viewController, animated: animated)
        }
        func navigationControllerSupportedInterfaceOrientations(_ navigationController: UINavigationController) -> UIInterfaceOrientationMask {
            base?.navigationControllerSupportedInterfaceOrientations?(navigationController) ?? .all
        }
        func navigationControllerPreferredInterfaceOrientationForPresentation(_ navigationController: UINavigationController) -> UIInterfaceOrientation {
            base?.navigationControllerPreferredInterfaceOrientationForPresentation?(navigationController)
                ?? navigationController.topViewController?.preferredInterfaceOrientationForPresentation ?? .portrait
        }
        func navigationController(_ navigationController: UINavigationController,
                                  interactionControllerFor animationController: any UIViewControllerAnimatedTransitioning) -> (any UIViewControllerInteractiveTransitioning)? {
            base?.navigationController?(navigationController, interactionControllerFor: animationController)
        }
        func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation,
                                  from fromVC: UIViewController, to toVC: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
            base?.navigationController?(navigationController, animationControllerFor: operation, from: fromVC, to: toVC)
        }
    }

    final class Fade: NSObject, UIViewControllerAnimatedTransitioning {
        var seen: [String] = []
        func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> Double { 0 }
        func animateTransition(using context: any UIViewControllerContextTransitioning) {
            seen.append("\(context.viewController(forKey: .from)?.title ?? "-")>\(context.viewController(forKey: .to)?.title ?? "-")")
            context.completeTransition(true)
        }
    }

    private func screen(_ title: String) -> UIViewController {
        let controller = UIViewController()
        controller.title = title
        return controller
    }

    @Test func aForwardingDelegateReachesOnlyWhatItsBaseImplements() {
        let navigation = UINavigationController(rootViewController: screen("Root"))
        let base = Partial(), forwarder = Forwarder()
        forwarder.base = base
        navigation.delegate = forwarder
        navigation.pushViewController(screen("Detail"), animated: false)
        #expect(forwarder.willShow == ["Detail"])
        #expect(base.shown == ["Detail"])
        // `base` implements neither orientation method, so the forwarder's fallbacks answer.
        #expect(forwarder.navigationControllerSupportedInterfaceOrientations(navigation) == .all)
        #expect(forwarder.navigationControllerPreferredInterfaceOrientationForPresentation(navigation) == .portrait)
        #expect(forwarder.navigationController(navigation, interactionControllerFor: Fade()) == nil)
        // Nor does a delegate without them answer for them.
        let delegate: any UINavigationControllerDelegate = base
        #expect(delegate.navigationControllerSupportedInterfaceOrientations?(navigation) == nil)
        // `responds(to:)` tells the same, as the protocol refines NSObjectProtocol.
        #expect(delegate.responds(to: #selector(UINavigationControllerDelegate.navigationController(_:didShow:animated:))))
        #expect(!delegate.responds(to: #selector(UINavigationControllerDelegate.navigationControllerSupportedInterfaceOrientations(_:))))
    }

    @Test func aForwardedAnimatorMovesThePush() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 300, height: 400), scale: 2)
        let navigation = UINavigationController(rootViewController: screen("Root"))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
        window.rootViewController = navigation
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 300, height: 400))
        let base = Partial(), forwarder = Forwarder(), fade = Fade()
        base.animator = fade
        forwarder.base = base
        navigation.delegate = forwarder
        navigation.pushViewController(screen("Detail"), animated: true)
        scene.layout(in: CGSize(width: 300, height: 400))
        #expect(fade.seen == ["Root>Detail"])
        #expect(base.shown == ["Detail"])
    }
    #endif
}
