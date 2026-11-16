// Smaller UIKit surface apps use: a font's descriptor for another design or size, home screen
// quick actions kept and handed back, and a presentation's delegate set through the base
// `UIPresentationController` type, as an app's sheet coordinator does.
import Testing
import UIKit
@testable import UIKitWebCore

@Suite @MainActor struct AppOddsTests {
    @Test func fontDescriptorsGiveDesignsAndSizes() throws {
        let bold = UIFont.systemFont(ofSize: 17, weight: .bold)
        let rounded = try #require(bold.fontDescriptor.withDesign(.rounded))
        let font = UIFont(descriptor: rounded, size: 0)
        #expect(font.resolved.family == "system-rounded")
        #expect(font.resolved.size == 17 && font.weight == .bold)
        #expect(UIFont(descriptor: rounded, size: 22).resolved.size == 22)
        #expect(UIFont(descriptor: bold.fontDescriptor.withSize(12), size: 0).pointSize == 12)
        let serif = try #require(UIFont.monospacedSystemFont(ofSize: 13, weight: .regular).fontDescriptor.withDesign(.serif))
        #expect(UIFont(descriptor: serif, size: 0).resolved.family == "system-serif")
        #expect(UIFont(descriptor: try #require(rounded.withDesign(.default)), size: 0).resolved.family == "system")
    }

    @Test func shortcutItemsAreKept() {
        let item = UIApplicationShortcutItem(type: "add", localizedTitle: "New Event", localizedSubtitle: nil,
                                             icon: UIApplicationShortcutIcon(type: .compose), userInfo: nil)
        UIApplication.shared.shortcutItems = [item]
        #expect(UIApplication.shared.shortcutItems?.first === item)
        #expect(item.type == "add" && item.icon?.type == .compose)
        let mutable = UIMutableApplicationShortcutItem(type: "search", localizedTitle: "Search")
        mutable.localizedTitle = "Find"
        mutable.icon = UIApplicationShortcutIcon(systemImageName: "magnifyingglass")
        #expect(mutable.localizedTitle == "Find" && mutable.icon?.imageName == "magnifyingglass")
        #expect(UIScene.ConnectionOptions().shortcutItem == nil)
        UIApplication.shared.shortcutItems = nil
    }

    final class Coordinator: NSObject, UIAdaptivePresentationControllerDelegate {}

    @Test func presentationDelegateThroughTheBaseType() {
        let presented = UIViewController()
        presented.modalPresentationStyle = .popover
        let coordinator = Coordinator()
        let base: UIPresentationController? = presented.presentationController
        base?.delegate = coordinator
        #expect(presented.popoverPresentationController?.delegate === coordinator)
        #expect(presented.presentationController?.adaptiveDelegate === coordinator)
    }

    /// Responders and layers are Hashable by identity, as UIKit's NSObjects are: a dictionary
    /// keyed by view controllers, a set of views.
    @Test func respondersAreHashable() {
        let first = UIViewController(), second = UIViewController()
        let titles: [UIViewController: String] = [first: "Walk", second: "Charts"]
        #expect(titles[first] == "Walk" && titles[second] == "Charts")
        let view = UIView()
        #expect(Set([view, view, UIView()]).count == 2)
        #expect(view == view && view != UIView())
        #expect(view.isEqual(view) && !view.isEqual(first))
        let layer = CALayer()
        #expect(Set([layer, layer]).count == 1)
    }

    /// Core Animation's transform arithmetic: rotation about any axis, composition in order, and
    /// the inverse.
    @Test func transformsCompose() {
        func near(_ a: CATransform3D, _ b: CATransform3D) -> Bool {
            let l = a._rows.flatMap { $0 }, r = b._rows.flatMap { $0 }
            return zip(l, r).allSatisfy { abs($0 - $1) < 1e-9 }
        }
        // A quarter turn about z is the 2D rotation.
        let turned = CATransform3DRotate(CATransform3DIdentity, .pi / 2, 0, 0, 1)
        #expect(near(turned, CATransform3DMakeAffineTransform(CGAffineTransform(rotationAngle: .pi / 2))))
        // About y, the plane narrows: x scales by the cosine.
        let spun = CATransform3DRotate(CATransform3DIdentity, .pi / 3, 0, 1, 0)
        #expect(abs(spun.m11 - 0.5) < 1e-9 && abs(spun.m22 - 1) < 1e-9)
        #expect(!CATransform3DIsAffine(spun) && CATransform3DIsAffine(turned))
        // Translate(Scale(I)) moves first, then scales: (1, 1) -> (6, 1) -> (12, 2).
        let moved = CATransform3DTranslate(CATransform3DMakeScale(2, 2, 1), 5, 0, 0)
        #expect(moved.m41 == 10 && moved.m11 == 2)
        let scaledAfter = CATransform3DConcat(CATransform3DMakeTranslation(5, 0, 0), CATransform3DMakeScale(2, 2, 1))
        #expect(scaledAfter.m41 == 10)
        let mixed = CATransform3DConcat(spun, CATransform3DTranslate(CATransform3DMakeScale(3, 2, 1), 4, -1, 2))
        #expect(near(CATransform3DConcat(mixed, CATransform3DInvert(mixed)), CATransform3DIdentity))
        var flat = CATransform3DIdentity
        flat.m11 = 0
        #expect(CATransform3DEqualToTransform(CATransform3DInvert(flat), flat))
        // A tiny scale is invertible, as Core Animation inverts it (issue 173).
        let tiny = CATransform3DMakeScale(1e-13, 1, 1)
        let undone = CATransform3DInvert(tiny)
        #expect(abs(undone.m11 - 1e13) <= 1e13 * 1e-12)
        #expect(near(CATransform3DConcat(tiny, undone), CATransform3DIdentity))
        // A singular matrix whose elimination leaves only rounding error still has no inverse.
        var rankTwo = CATransform3DIdentity
        rankTwo.m11 = 0.1; rankTwo.m12 = 0.2; rankTwo.m21 = 0.3; rankTwo.m22 = 0.6
        #expect(CATransform3DEqualToTransform(CATransform3DInvert(rankTwo), rankTwo))
    }

    /// `endEditing(_:)` resigns a text field inside the view (and leaves one elsewhere), and
    /// the window does it for the whole window.
    @Test func endEditingResignsTheFieldInside() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 400), scale: 2)
        let root = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        window.rootViewController = root
        window.makeKeyAndVisible()
        let form = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 100))
        let field = UITextField(frame: CGRect(x: 10, y: 10, width: 200, height: 30))
        let other = UIView(frame: CGRect(x: 0, y: 200, width: 320, height: 100))
        form.addSubview(field)
        root.view.addSubview(form)
        root.view.addSubview(other)
        #expect(field.becomeFirstResponder())
        #expect(!other.endEditing(true) && field.isFirstResponder)
        #expect(form.endEditing(false) && !field.isFirstResponder)
        #expect(field.becomeFirstResponder())
        window.endEditing(true)
        #expect(!field.isFirstResponder)
    }

    /// Colour components as hue, saturation and brightness, the inverse of `init(hue:...)`.
    @Test func colorsGiveHueSaturationAndBrightness() {
        var hue: CGFloat = -1, saturation: CGFloat = -1, brightness: CGFloat = -1, alpha: CGFloat = -1
        #expect(UIColor(hue: 0.6, saturation: 0.5, brightness: 0.8, alpha: 0.7).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha))
        #expect(abs(hue - 0.6) < 1e-9 && abs(saturation - 0.5) < 1e-9 && abs(brightness - 0.8) < 1e-9 && abs(alpha - 0.7) < 1e-9)
        #expect(UIColor.red.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil))
        #expect(hue == 0 && saturation == 1 && brightness == 1)
        #expect(UIColor(white: 0.5, alpha: 1).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil))
        #expect(hue == 0 && saturation == 0 && brightness == 0.5)
    }

    /// Bar spacers, orientations, the app's layout direction and Dynamic Type category, and the
    /// reduce-motion notification posted when the host's setting changes.
    @Test func spacersOrientationsAndSettings() {
        let fixed = UIBarButtonItem.fixedSpace(12)
        #expect(fixed.width == 12 && fixed.isSpace)
        #expect(UIBarButtonItem.flexibleSpace().isSpace && UIBarButtonItem.fixedSpace().width == 8)
        let controller = UIViewController()
        #expect(controller.supportedInterfaceOrientations == .allButUpsideDown)
        #expect(controller.supportedInterfaceOrientations.contains(.landscapeLeft) && !controller.supportedInterfaceOrientations.contains(.portraitUpsideDown))
        #expect(controller.preferredInterfaceOrientationForPresentation == .portrait)
        #expect(!controller.isBeingPresented && !controller.isBeingDismissed)
        #expect(UIApplication.shared.userInterfaceLayoutDirection == .leftToRight)
        #expect(UIApplication.shared.preferredContentSizeCategory == UIScreen.main.traitCollection.preferredContentSizeCategory)

        let posted = Posted()
        let token = NotificationCenter.default.addObserver(forName: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated { posted.count += 1 }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        UIKitScene.shared.hostReducesMotion = true
        UIKitScene.shared.hostReducesMotion = true
        #expect(posted.count == 1 && UIAccessibility.isReduceMotionEnabled)
        UIKitScene.shared.hostReducesMotion = false
        #expect(posted.count == 2)
    }

    @MainActor final class Posted {
        var count = 0
    }
}
