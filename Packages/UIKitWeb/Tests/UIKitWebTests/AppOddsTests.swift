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
}
