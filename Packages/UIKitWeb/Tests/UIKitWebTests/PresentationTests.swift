// UIAlertController (Containers/UIAlertController.swift): presenting puts the card in the
// window, tapping an action runs its handler and dismisses, and the scene keeps rendering
// afterwards; a page sheet dismisses on a tap outside.
import Testing
import UIKit

@Suite @MainActor struct PresentationTests {
    private func window() -> (UIWindow, UIViewController) {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 320, height: 500), scale: 2)
        let root = UIViewController()
        root.view.backgroundColor = .white
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
        window.rootViewController = root
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 320, height: 500))
        return (window, root)
    }

    @Test func alertActionsRunAndDismiss() {
        let (window, root) = window()
        let scene = UIKitScene.shared
        var chosen: String?
        let alert = UIAlertController(title: "Delete file?", message: "This cannot be undone.", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in chosen = "cancel" })
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in chosen = "delete" })
        root.present(alert, animated: false)
        scene.layout(in: CGSize(width: 320, height: 500))
        #expect(root.presentedViewController === alert)
        #expect(alert.view.frame.width == 300)
        let semantics = scene.semanticsTree()
        let cancel = semantics.first { $0.label == "Cancel" }
        #expect(cancel != nil, "\(semantics.map(\.label))")
        guard let cancel else { return }
        // A tap on Cancel runs the handler, dismisses, and the next frames render.
        scene.pointerDown(at: CGPoint(x: cancel.frame.midX, y: cancel.frame.midY), type: .touch, time: 1)
        scene.pointerUp(at: CGPoint(x: cancel.frame.midX, y: cancel.frame.midY), time: 1.1)
        #expect(chosen == "cancel")
        #expect(root.presentedViewController == nil)
        scene.layout(in: CGSize(width: 320, height: 500))
        _ = scene.render(scale: 2, background: false)
        #expect(!scene.semanticsTree().contains { $0.label == "Cancel" })
        #expect(window.subviews.count == 1)
    }

    /// An alert's text fields sit in the card and type through the host; the handler reads them.
    @Test func alertTextFieldsTypeThroughTheHost() {
        let (_, root) = window()
        let scene = UIKitScene.shared
        scene.textEngine = try! Goldens.textEngine()
        var saved: String?
        let alert = UIAlertController(title: "Rename", message: "Enter a new name for the file.", preferredStyle: .alert)
        alert.addTextField { field in field.placeholder = "Name" }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak alert] _ in saved = alert?.textFields?.first?.text })
        root.present(alert, animated: false)
        scene.layout(in: CGSize(width: 320, height: 500))
        #expect(alert.view.frame == CGRect(x: 10, y: 147, width: 300, height: 206))
        guard let field = alert.textFields?.first else { Issue.record("no field"); return }
        #expect(field.convert(field.bounds, to: nil) == CGRect(x: 32.5, y: 238, width: 255, height: 20.5))
        guard let node = scene.semanticsTree().first(where: { $0.textInput != nil }) else { Issue.record("no input"); return }
        #expect(node.textInput?.placeholder == "Name")
        scene.textField(node.identifier, focused: true)
        #expect(field.isFirstResponder)
        scene.textField(node.identifier, didChange: "Notes")
        guard let save = scene.semanticsTree().first(where: { $0.label == "Save" }) else { Issue.record("no Save"); return }
        scene.activate(semanticsIdentifier: save.identifier)
        #expect(saved == "Notes")
        #expect(root.presentedViewController == nil)
    }

    /// A second presentation from a controller already presenting is refused, as UIKit refuses
    /// it, so the first alert keeps its presenter and its container (the settings example's
    /// Reset button once fired twice and the orphaned first alert was freed under its container).
    @Test func presentingWhilePresentingIsRefused() {
        let (window, root) = window()
        let scene = UIKitScene.shared
        let first = UIAlertController(title: "First", message: nil, preferredStyle: .alert)
        first.addAction(UIAlertAction(title: "OK", style: .default))
        root.present(first, animated: true)
        do {
            let second = UIAlertController(title: "Second", message: nil, preferredStyle: .alert)
            second.addAction(UIAlertAction(title: "OK", style: .default))
            root.present(second, animated: true)
        }
        #expect(root.presentedViewController === first)
        #expect(window.subviews.count == 2)
        scene.layout(in: CGSize(width: 320, height: 500))
        let labels = scene.semanticsTree().map(\.label)
        #expect(labels.contains("First"))
        #expect(!labels.contains("Second"))
        first.dismiss(animated: false)
        #expect(root.presentedViewController == nil)
        #expect(window.subviews.count == 1)
    }

    /// A bar button item's primary action runs once per tap (UIControl sends
    /// `primaryActionTriggered` on the touch up; the bar button must not send it again).
    @Test func barButtonActionRunsOncePerTap() {
        let (_, root) = window()
        let scene = UIKitScene.shared
        let counts = Counts()
        let content = UIViewController()
        content.title = "Home"
        content.navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Reset", primaryAction: UIAction { _ in counts.taps += 1 })
        let nav = UINavigationController(rootViewController: content)
        root.addChild(nav)
        root.view.addSubview(nav.view)
        nav.view.frame = root.view.bounds
        nav.didMove(toParent: root)
        scene.layout(in: CGSize(width: 320, height: 500))
        guard let reset = scene.semanticsTree().first(where: { $0.label == "Reset" }) else { Issue.record("no Reset"); return }
        scene.pointerDown(at: CGPoint(x: reset.frame.midX, y: reset.frame.midY), type: .touch, time: 1)
        scene.pointerUp(at: CGPoint(x: reset.frame.midX, y: reset.frame.midY), time: 1.1)
        #expect(counts.taps == 1)
    }

    /// The browser's overlay activates the element on click while the pointer events land too:
    /// the activation dismisses the alert between the pointer's down and up.
    @Test func activationBetweenPointerDownAndUpSurvives() {
        let (window, root) = window()
        let scene = UIKitScene.shared
        let alert = UIAlertController(title: "Delete file?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive))
        root.present(alert, animated: true)
        scene.layout(in: CGSize(width: 320, height: 500))
        guard let cancel = scene.semanticsTree().first(where: { $0.label == "Cancel" }) else { Issue.record("no Cancel"); return }
        scene.pointerDown(at: CGPoint(x: cancel.frame.midX, y: cancel.frame.midY), type: .touch, time: 1)
        scene.activate(semanticsIdentifier: cancel.identifier)
        scene.pointerUp(at: CGPoint(x: cancel.frame.midX, y: cancel.frame.midY), time: 1.1)
        scene.blur(semanticsIdentifier: cancel.identifier)
        #expect(root.presentedViewController == nil)
        scene.layout(in: CGSize(width: 320, height: 500))
        _ = scene.render(scale: 2, background: false)
        _ = scene.semanticsTree()
        #expect(window.subviews.count == 1)
    }

    @Test func aTapOutsideASheetDismissesIt() {
        let (_, root) = window()
        let scene = UIKitScene.shared
        let sheet = UIViewController()
        sheet.view.backgroundColor = .white
        root.present(sheet, animated: false)
        scene.layout(in: CGSize(width: 320, height: 500))
        #expect(sheet.view.frame.minY > 29 && sheet.view.frame.minY < 31)
        scene.pointerDown(at: CGPoint(x: 160, y: 10), type: .touch, time: 1)
        scene.pointerUp(at: CGPoint(x: 160, y: 10), time: 1.1)
        #expect(root.presentedViewController == nil)
        scene.layout(in: CGSize(width: 320, height: 500))
        _ = scene.render(scale: 2, background: false)
    }
}

@MainActor
private final class Counts {
    var taps = 0
}
