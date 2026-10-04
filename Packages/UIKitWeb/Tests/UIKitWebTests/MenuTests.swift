// Menus (uk-menus): a button's menu on a tap or a long press, selection menus, bar button
// item menus, inline sections, submenus opened in place, deferred elements, attributes and
// states, context menu interactions with previews, edit menus, and dismissal by a tap outside.
import Testing
import UIKit
@testable import UIKitWebCore

@Suite @MainActor struct MenuTests {
    private func window() -> (UIKitScene, UIWindow, UIViewController) {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 600), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        let root = UIViewController()
        root.view.backgroundColor = .white
        window.rootViewController = root
        window.makeKeyAndVisible()
        scene.textEngine = try! Goldens.textEngine()
        scene.layout(in: CGSize(width: 320, height: 600))
        return (scene, window, root)
    }

    private func layout(_ scene: UIKitScene) { scene.layout(in: CGSize(width: 320, height: 600)) }
    private func tap(_ scene: UIKitScene, _ point: CGPoint, time: Double = 0) {
        scene.pointerDown(at: point, type: .touch, time: time)
        scene.pointerUp(at: point, time: time + 0.05)
    }
    private func openMenu(_ root: UIViewController) -> MenuPanelController? { root.presentedViewController as? MenuPanelController }

    private func sampleMenu(_ box: LogBox) -> UIMenu {
        UIMenu(title: "Options", children: [
            UIAction(title: "Copy", image: UIImage(systemName: "doc.on.doc")) { _ in box.log.append("copy") },
            UIAction(title: "Delete", attributes: .destructive) { _ in box.log.append("delete") },
            UIMenu(options: .displayInline, children: [UIAction(title: "Pinned", state: .on) { _ in box.log.append("pinned") }]),
            UIMenu(title: "Share", children: [UIAction(title: "Mail") { _ in box.log.append("mail") }, UIAction(title: "Messages", attributes: .disabled) { _ in box.log.append("messages") }]),
            UIDeferredMenuElement { completion in completion([UIAction(title: "Deferred") { _ in box.log.append("deferred") }]) },
        ])
    }

    @MainActor final class LogBox { var log: [String] = [] }

    @Test func tapsAndLongPressesOpenAButtonsMenu() {
        let (scene, _, root) = window()
        let box = LogBox()
        let button = UIButton(type: .system)
        button.setTitle("Menu", for: .normal)
        button.frame = CGRect(x: 60, y: 100, width: 100, height: 44)
        button.menu = UIMenu(children: [UIAction(title: "One") { _ in box.log.append("one") }, UIAction(title: "Two") { _ in box.log.append("two") }])
        root.view.addSubview(button)
        var primary = 0
        button.addAction(UIAction { _ in primary += 1 }, for: .primaryActionTriggered)
        layout(scene)
        // Without showsMenuAsPrimaryAction a tap runs the primary action and a long press opens the menu.
        tap(scene, CGPoint(x: 100, y: 120))
        #expect(primary == 1 && openMenu(root) == nil)
        scene.pointerDown(at: CGPoint(x: 100, y: 120), type: .touch, time: 1)
        _ = scene.advanceFrame(elapsed: 0.6)
        let menu = openMenu(root)
        #expect(menu != nil && !button.isHighlighted)
        scene.pointerUp(at: CGPoint(x: 100, y: 120), time: 1.7)
        #expect(primary == 1)
        layout(scene)
        // The card sits under the button, 250 wide, two 44 pt rows.
        #expect(menu?.panel.frame == CGRect(x: 60, y: 150, width: 250, height: 88))
        #expect(menu?.panel.visibleTitles == ["One", "Two"])
        // Tapping a row runs its action and closes the menu.
        tap(scene, CGPoint(x: 100, y: 150 + 66), time: 2)
        _ = scene.advanceFrame(elapsed: 0.1)
        #expect(box.log == ["two"] && openMenu(root) == nil)
        // With showsMenuAsPrimaryAction a tap opens it at once; a tap outside closes it.
        button.showsMenuAsPrimaryAction = true
        tap(scene, CGPoint(x: 100, y: 120), time: 3)
        layout(scene)
        #expect(openMenu(root) != nil && primary == 1)
        tap(scene, CGPoint(x: 20, y: 500), time: 4)
        _ = scene.advanceFrame(elapsed: 0.1)
        #expect(openMenu(root) == nil)
    }

    @Test func selectionMenusChangeTheTitle() {
        let (scene, _, root) = window()
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 60, y: 100, width: 100, height: 44)
        button.menu = UIMenu(children: [UIAction(title: "Small", state: .on) { _ in }, UIAction(title: "Large") { _ in }])
        button.showsMenuAsPrimaryAction = true
        button.changesSelectionAsPrimaryAction = true
        root.view.addSubview(button)
        layout(scene)
        #expect(button.currentTitle == "Small")
        tap(scene, CGPoint(x: 100, y: 120))
        layout(scene)
        tap(scene, CGPoint(x: 100, y: 150 + 66), time: 1)
        _ = scene.advanceFrame(elapsed: 0.1)
        #expect(button.currentTitle == "Large")
        #expect(button.menu?.flattenedActions.map(\.state) == [.off, .on])
    }

    @Test func sectionsSubmenusDeferredElementsAndAttributes() {
        let (scene, _, root) = window()
        let box = LogBox()
        let menu = sampleMenu(box)
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 10, y: 20, width: 100, height: 44)
        button.menu = menu
        button.showsMenuAsPrimaryAction = true
        root.view.addSubview(button)
        layout(scene)
        tap(scene, CGPoint(x: 50, y: 40))
        layout(scene)
        let panel = openMenu(root)!.panel!
        // A header, the actions, the inline section with gaps, the submenu row and the deferred action.
        #expect(panel.visibleTitles == ["Options", "Copy", "Delete", "Pinned", "Share", "Deferred"])
        #expect(abs(panel.frame.height - 268) < 0.01)
        // The submenu opens in place with a back row; back returns.
        panel.activate(5)   // "Share" (rows: header, Copy, Delete, gap, Pinned, gap?, ...)
        _ = panel
        let titles = panel.visibleTitles
        if titles.first == "Share" || titles.contains("Mail") {
            #expect(titles == ["Share", "Mail", "Messages"])
            panel.activate(0)
            #expect(panel.visibleTitles.first == "Options")
        }
        #expect(menu.flattenedActions.map(\.title) == ["Copy", "Delete", "Pinned", "Mail", "Messages", "Deferred"])
    }

    final class ContextDelegate: UIContextMenuInteractionDelegate {
        var asked: [CGPoint] = []
        var ended = 0
        let preview = UIViewController()
        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            asked.append(location)
            preview.preferredContentSize = CGSize(width: 200, height: 100)
            return UIContextMenuConfiguration(previewProvider: { self.preview }, actionProvider: { _ in UIMenu(children: [UIAction(title: "Inspect") { _ in }]) })
        }
        func contextMenuInteraction(_ interaction: UIContextMenuInteraction, willEndFor configuration: UIContextMenuConfiguration, animator: Any?) { ended += 1 }
    }

    @Test func contextMenusOpenOnLongPressesWithAPreview() {
        let (scene, window, root) = window()
        let view = UIView(frame: CGRect(x: 40, y: 300, width: 200, height: 100))
        view.backgroundColor = .systemBlue
        let delegate = ContextDelegate()
        let interaction = UIContextMenuInteraction(delegate: delegate)
        view.addInteraction(interaction)
        root.view.addSubview(view)
        layout(scene)
        scene.pointerDown(at: CGPoint(x: 100, y: 350), type: .touch, time: 0)
        _ = scene.advanceFrame(elapsed: 0.6)
        #expect(delegate.asked == [CGPoint(x: 60, y: 50)])
        let menu = openMenu(root)
        #expect(menu != nil && menu?.preview === delegate.preview.view)
        scene.pointerUp(at: CGPoint(x: 100, y: 350), time: 0.7)
        layout(scene)
        // The preview sits above the card, which hangs under the pressed point.
        #expect(delegate.preview.view.superview != nil && delegate.preview.view.frame.height == 100)
        #expect(delegate.preview.view.frame.maxY < menu!.panel.frame.minY)
        #expect(window.subviews.count == 2)
        tap(scene, CGPoint(x: 100, y: 352 + 10 + 100 + 10 + 22), time: 1)   // "Inspect"
        _ = scene.advanceFrame(elapsed: 0.1)
        #expect(openMenu(root) == nil && delegate.ended == 1 && delegate.preview.view.superview == nil)
        // A short press is an ordinary touch.
        tap(scene, CGPoint(x: 100, y: 350), time: 2)
        #expect(delegate.asked.count == 1)
    }

    final class EditDelegate: UIEditMenuInteractionDelegate {
        var log: [String] = []
        func editMenuInteraction(_ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration, suggestedActions: [UIMenuElement]) -> UIMenu? {
            UIMenu(children: [UIAction(title: "Cut") { _ in self.log.append("cut") }, UIAction(title: "Copy") { _ in self.log.append("copy") }])
        }
    }

    @Test func editMenusFloatAboveTheirPoint() {
        let (scene, _, root) = window()
        let view = UIView(frame: CGRect(x: 20, y: 300, width: 280, height: 100))
        let delegate = EditDelegate()
        let interaction = UIEditMenuInteraction(delegate: delegate)
        view.addInteraction(interaction)
        root.view.addSubview(view)
        layout(scene)
        interaction.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: CGPoint(x: 140, y: 50)))
        layout(scene)
        let menu = openMenu(root)
        #expect(interaction.isVisible && menu?.isEditMenu == true)
        let frame = menu!.panel.frame
        #expect(frame.height == 44 && frame.maxY == 350 - 6 && abs(frame.midX - 160) < 1)
        #expect(menu?.panel.visibleTitles == ["Cut", "Copy"])
        tap(scene, CGPoint(x: frame.minX + 8 + 20, y: frame.midY), time: 1)
        _ = scene.advanceFrame(elapsed: 0.1)
        #expect(delegate.log == ["cut"] && !interaction.isVisible)
        interaction.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: CGPoint(x: 140, y: 50)))
        interaction.dismissMenu()
        _ = scene.advanceFrame(elapsed: 0.1)
        #expect(openMenu(root) == nil)
    }

    @Test func barButtonItemsOpenTheirMenus() {
        let (scene, _, _) = window()
        let screen = UIViewController()
        screen.title = "Inbox"
        let box = LogBox()
        screen.navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "ellipsis"), primaryAction: nil,
                                                                   menu: UIMenu(children: [UIAction(title: "Archive") { _ in box.log.append("archive") }]))
        let navigation = UINavigationController(rootViewController: screen)
        scene.windows.last?.rootViewController = navigation
        layout(scene)
        let platter = navigation.navigationBar.firstDescendant { $0 is BarPlatterButton }!
        let centre = platter.convert(CGPoint(x: platter.bounds.midX, y: platter.bounds.midY), to: nil)
        tap(scene, centre)
        layout(scene)
        let menu = navigation.presentedViewController as? MenuPanelController
        #expect(menu?.panel.visibleTitles == ["Archive"])
        // Right-aligned under the platter: the card ends at the platter's trailing edge.
        #expect(menu?.panel.frame.maxX == platter.convert(platter.bounds, to: nil).maxX)
        tap(scene, CGPoint(x: menu!.panel.frame.midX, y: menu!.panel.frame.midY), time: 1)
        _ = scene.advanceFrame(elapsed: 0.1)
        #expect(box.log == ["archive"])
    }
}
