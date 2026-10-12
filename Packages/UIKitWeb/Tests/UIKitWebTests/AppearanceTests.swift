// UIAppearance (uk-appearance): proxies record key-path values that apply when a view enters a
// window; contained proxies apply to views under the named containers only; later entries win.
import Testing
import UIKitWebCore

@Suite @MainActor struct AppearanceTests {
    final class Badge: UILabel {}

    @Test func proxiesApplyOnEnteringAWindow() {
        let registry = _UIAppearanceRegistry.shared
        registry.removeAll()
        defer { registry.removeAll() }
        UILabel.appearance().textColor = .red
        UILabel.appearance().numberOfLines = 2
        #expect(UILabel.appearance().textColor == .red && UILabel.appearance().numberOfLines == 2)
        let label = UILabel()
        label.textColor = .blue
        // Not in a window yet: nothing applied.
        #expect(label.textColor == .blue && label.numberOfLines == 1)
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        let window = UIWindow()
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.addSubview(label)
        // Entering the window applies the proxy over the earlier explicit value, as UIKit does.
        #expect(label.textColor == .red && label.numberOfLines == 2)
        // A subclass takes its superclass's entries; its own entries come after.
        Badge.appearance().textColor = .green
        let badge = Badge()
        controller.view.addSubview(badge)
        #expect(badge.textColor == .green && badge.numberOfLines == 2)
        // Containment: a label inside a stack view only.
        UILabel.appearance(whenContainedInInstancesOf: [UIStackView.self]).textColor = .orange
        let stack = UIStackView()
        controller.view.addSubview(stack)
        let inside = UILabel(), outside = UILabel()
        stack.addArrangedSubview(inside)
        controller.view.addSubview(outside)
        #expect(inside.textColor == .orange && outside.textColor == .red)
        // Containment through the controller: labels under a navigation controller's views.
        UILabel.appearance(whenContainedInInstancesOf: [UINavigationController.self]).textColor = .purple
        let navigation = UINavigationController(rootViewController: UIViewController())
        scene.removeAllWindows()
        let navWindow = UIWindow()
        navWindow.rootViewController = navigation
        navWindow.makeKeyAndVisible()
        let navLabel = UILabel()
        navigation.topViewController!.view.addSubview(navLabel)
        #expect(navLabel.textColor == .purple)
        scene.removeAllWindows()
    }
}
