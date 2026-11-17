// What swift-navigation's UIKitNavigationShim adds to UIViewController on Apple's platforms
// (App/UIViewController.swift): work queued for a view's first appearance runs once when it
// appears, and a presented controller's dismiss work runs once when it is dismissed, an alert's
// after the handler of the action that dismissed it. Its UIKit bindings (UIKitNavigation, in
// EhPanda and CriticalMaps) present and dismiss through them.
import Testing
import UIKit

@Suite @MainActor struct UIKitNavigationShimTests {
    private func window() -> UIViewController {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 500), scale: 2)
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        window.rootViewController = root
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 500))
        return root
    }

    /// Lets the main actor's queued work run.
    private func settle(until done: () -> Bool) async {
        for _ in 0..<20 where !done() { await Task.yield() }
    }

    @Test func firstAppearanceWorkRunsOnce() {
        let root = window()
        let presented = UIViewController()
        var log: [String] = []
        #expect(!presented._UIKitNavigation_hasViewAppeared)
        presented._UIKitNavigation_onViewAppear.append { log.append("appeared") }
        root.present(presented, animated: false)
        UIKitScene.shared.layout(in: CGSize(width: 320, height: 500))
        #expect(log == ["appeared"])
        #expect(presented._UIKitNavigation_hasViewAppeared)
        #expect(presented._UIKitNavigation_onViewAppear.isEmpty)
        // Appearing again runs nothing queued before the first appearance.
        presented.dismiss(animated: false)
        root.present(presented, animated: false)
        UIKitScene.shared.layout(in: CGSize(width: 320, height: 500))
        #expect(log == ["appeared"])
    }

    @Test func dismissWorkRunsOnceWhenDismissed() async {
        let root = window()
        let presented = UIViewController()
        var dismissed = 0
        presented._UIKitNavigation_onDismiss = { dismissed += 1 }
        root.present(presented, animated: false)
        UIKitScene.shared.layout(in: CGSize(width: 320, height: 500))
        #expect(dismissed == 0)
        root.dismiss(animated: false)
        #expect(dismissed == 1)
        await settle { presented._UIKitNavigation_onDismiss == nil }
        #expect(presented._UIKitNavigation_onDismiss == nil)
    }

    /// A pushed controller that is popped is not dismissed, so its work waits.
    @Test func poppingIsNotDismissing() {
        let root = window()
        let navigation = UINavigationController(rootViewController: UIViewController())
        root.present(navigation, animated: false)
        UIKitScene.shared.layout(in: CGSize(width: 320, height: 500))
        let detail = UIViewController()
        var dismissed = 0
        detail._UIKitNavigation_onDismiss = { dismissed += 1 }
        navigation.pushViewController(detail, animated: false)
        UIKitScene.shared.layout(in: CGSize(width: 320, height: 500))
        navigation.popViewController(animated: false)
        UIKitScene.shared.layout(in: CGSize(width: 320, height: 500))
        #expect(dismissed == 0)
    }

    @Test func anAlertsDismissWorkRunsAfterTheActionsHandler() async {
        let root = window()
        let scene = UIKitScene.shared
        var log: [String] = []
        let alert = UIAlertController(title: "Delete file?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in log.append("handler") })
        alert._UIKitNavigation_onDismiss = { log.append("dismissed") }
        root.present(alert, animated: false)
        scene.layout(in: CGSize(width: 320, height: 500))
        let button = scene.semanticsTree().first { $0.label == "Delete" }
        #expect(button != nil)
        guard let button else { return }
        scene.pointerDown(at: CGPoint(x: button.frame.midX, y: button.frame.midY), type: .touch, time: 1)
        scene.pointerUp(at: CGPoint(x: button.frame.midX, y: button.frame.midY), time: 1.1)
        _ = scene.advanceFrame(elapsed: 0.5)
        await settle { log.count == 2 }
        #expect(log == ["handler", "dismissed"])
    }
}
