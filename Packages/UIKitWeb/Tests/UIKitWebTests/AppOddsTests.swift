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
    }
}
