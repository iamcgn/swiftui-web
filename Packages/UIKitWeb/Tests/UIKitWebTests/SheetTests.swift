// Sheet detents, popovers and anchored action sheets (uk-sheets): the presentation controllers
// a presented controller gets, the medium detent's card and grabber, custom detents and corner
// radii, popovers kept as popovers (the arrow's side) or adapted to a sheet, action sheets
// anchored to a source, and the delegates' dismissal callbacks.
import Testing
import UIKit
@testable import UIKitWebCore

@Suite @MainActor struct SheetTests {
    private func window() -> (UIKitScene, UIWindow, UIViewController) {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 500), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        let root = UIViewController()
        root.view.backgroundColor = .white
        window.rootViewController = root
        window.makeKeyAndVisible()
        scene.textEngine = try! Goldens.textEngine()
        scene.layout(in: CGSize(width: 320, height: 500))
        return (scene, window, root)
    }

    private func layout(_ scene: UIKitScene) { scene.layout(in: CGSize(width: 320, height: 500)) }

    /// The page sheet card (29.86875 down, to floating-point noise).
    private func isPageSheet(_ frame: CGRect) -> Bool {
        frame.minX == 0 && abs(frame.minY - 29.86875) < 1e-6 && frame.width == 320 && abs(frame.height - 470) < 1e-6
    }

    @Test func presentationControllersFollowTheStyle() {
        let sheet = UIViewController()
        #expect(sheet.sheetPresentationController != nil && sheet.popoverPresentationController == nil)
        let popover = UIViewController()
        popover.modalPresentationStyle = .popover
        #expect(popover.popoverPresentationController != nil && popover.sheetPresentationController == nil)
        let full = UIViewController()
        full.modalPresentationStyle = .fullScreen
        #expect(full.presentationController == nil)
        let actions = UIAlertController(title: "T", message: nil, preferredStyle: .actionSheet)
        #expect(actions.popoverPresentationController != nil)
        #expect(UISheetPresentationController.Detent.medium() == .medium() && UISheetPresentationController.Detent.medium() != .large())
    }

    @Test func mediumDetentFloatsTheCard() {
        let (scene, window, root) = window()
        let presented = UIViewController()
        presented.view.backgroundColor = .systemGroupedBackground
        presented.sheetPresentationController?.detents = [.medium(), .large()]
        presented.sheetPresentationController?.prefersGrabberVisible = true
        root.present(presented, animated: false)
        layout(scene)
        // The card: 296 tall scaled 0.9713175 about its centre (uikit/sheet/medium's frames).
        let frame = presented.view.convert(presented.view.bounds, to: window)
        #expect(abs(frame.minX - 4.5892) < 0.01 && abs(frame.minY - 207.9107) < 0.02 && abs(frame.width - 310.8216) < 0.01 && abs(frame.height - 287.51) < 0.01)
        #expect(presented.view.layer.cornerRadius == 39)
        let container = presented.presentationController?.containerView
        #expect(container?.subviews.contains { $0 is GrabberView } == true)
        // Selecting the large detent puts the page sheet back; the grabber can go.
        presented.sheetPresentationController?.animateChanges {
            presented.sheetPresentationController?.selectedDetentIdentifier = .large
            presented.sheetPresentationController?.prefersGrabberVisible = false
        }
        layout(scene)
        #expect(isPageSheet(presented.view.frame) && presented.view.transform == .identity)
        #expect(container?.subviews.contains { $0 is GrabberView } == false)
        // A custom detent takes its resolver's height; a preferred corner radius applies.
        presented.sheetPresentationController?.detents = [.custom { _ in 200 }]
        presented.sheetPresentationController?.selectedDetentIdentifier = nil
        presented.sheetPresentationController?.preferredCornerRadius = 12
        layout(scene)
        #expect(abs(presented.view.convert(presented.view.bounds, to: window).height - 200 * 0.9713175) < 0.01)
        #expect(presented.view.layer.cornerRadius == 12)
        presented.dismiss(animated: false)
    }

    final class Keeper: NSObject, UIPopoverPresentationControllerDelegate {
        var dismissed = 0
        var vetoes = false
        func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle { .none }
        func presentationControllerShouldDismiss(_ presentationController: UIPresentationController) -> Bool { !vetoes }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { dismissed += 1 }
    }

    @Test func popoversStayOrAdapt() {
        let (scene, _, root) = window()
        let source = UIButton(type: .system)
        source.frame = CGRect(x: 110, y: 300, width: 100, height: 44)
        root.view.addSubview(source)
        let popover = UIViewController()
        popover.view.backgroundColor = .white
        popover.preferredContentSize = CGSize(width: 240, height: 120)
        popover.modalPresentationStyle = .popover
        let keeper = Keeper()
        popover.popoverPresentationController?.sourceView = source
        popover.popoverPresentationController?.delegate = keeper
        root.present(popover, animated: false)
        layout(scene)
        // The card centred on the source, 13 above it: its frame spans the arrow (uikit/popover/basic).
        #expect(popover.view.frame == CGRect(x: 40, y: 167, width: 240, height: 133))
        #expect(popover.popoverPresentationController?.arrowDirection == .down)
        #expect(popover.view.layer.popoverArrow == CGRect(x: 108, y: 120, width: 24, height: 13))
        // A tap outside dismisses unless the delegate vetoes; it hears of the dismissal.
        keeper.vetoes = true
        scene.pointerDown(at: CGPoint(x: 20, y: 20), type: .touch, time: 0); scene.pointerUp(at: CGPoint(x: 20, y: 20), time: 0.1)
        #expect(root.presentedViewController === popover && keeper.dismissed == 0)
        keeper.vetoes = false
        scene.pointerDown(at: CGPoint(x: 20, y: 20), type: .touch, time: 1); scene.pointerUp(at: CGPoint(x: 20, y: 20), time: 1.1)
        _ = scene.advanceFrame(elapsed: 0.6)
        #expect(root.presentedViewController == nil && keeper.dismissed == 1)
        // No room above a source near the top: the arrow points up from under it.
        source.frame.origin.y = 20
        let below = UIViewController()
        below.preferredContentSize = CGSize(width: 240, height: 120)
        below.modalPresentationStyle = .popover
        below.popoverPresentationController?.sourceView = source
        below.popoverPresentationController?.delegate = keeper
        root.present(below, animated: false)
        layout(scene)
        #expect(below.view.frame == CGRect(x: 40, y: 64, width: 240, height: 133) && below.popoverPresentationController?.arrowDirection == .up)
        below.dismiss(animated: false)
        // Without a delegate the popover adapts to the page sheet (uikit/popover/adapted).
        let adapted = UIViewController()
        adapted.modalPresentationStyle = .popover
        adapted.popoverPresentationController?.sourceView = source
        root.present(adapted, animated: false)
        layout(scene)
        #expect(isPageSheet(adapted.view.frame))
        adapted.dismiss(animated: false)
    }

    @Test func actionSheetsAnchorToTheirSource() {
        let (scene, _, root) = window()
        let source = UIButton(type: .system)
        source.frame = CGRect(x: 110, y: 300, width: 100, height: 44)
        root.view.addSubview(source)
        let sheet = UIAlertController(title: "Share", message: nil, preferredStyle: .actionSheet)
        var tapped: [String] = []
        sheet.addAction(UIAlertAction(title: "Copy Link", style: .default) { tapped.append($0.title ?? "") })
        sheet.addAction(UIAlertAction(title: "Save Image", style: .default))
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = source
        root.present(sheet, animated: false)
        layout(scene)
        // A 240 pt card above the source with the arrow below its frame; no cancel action.
        #expect(sheet.isAnchored)
        #expect(sheet.view.frame == CGRect(x: 40, y: 98, width: 240, height: 189))
        #expect(sheet.orderedActions.map(\.title) == ["Copy Link", "Save Image"])
        let buttons = sheet.view.subviews.compactMap { $0 as? AlertActionButton }
        #expect(buttons.map(\.frame) == [CGRect(x: 15.5, y: 71, width: 209, height: 48), CGRect(x: 15.5, y: 127, width: 209, height: 48)])
        // Tapping an action runs it; tapping outside dismisses.
        scene.pointerDown(at: CGPoint(x: 160, y: 190), type: .touch, time: 0); scene.pointerUp(at: CGPoint(x: 160, y: 190), time: 0.1)
        _ = scene.advanceFrame(elapsed: 0.6)
        #expect(tapped == ["Copy Link"] && root.presentedViewController == nil)
    }
}
