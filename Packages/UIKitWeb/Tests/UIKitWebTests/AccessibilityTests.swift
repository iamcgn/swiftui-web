// uk-accessibility (Views/UIAccessibility.swift, Events/TouchRouter.swift's walk): the
// semantics tree follows accessibilityElements and a modal view, carries traits, custom
// actions and the enabled state, runs custom, escape and magic-tap actions by name, and
// UIAccessibility.post queues announcements and focus moves for the host.
import Testing
import UIKit
import UIKitFixtures
import UIKitFixtureKit
@testable import UIKitWebCore

@MainActor private final class Escaper: UIView {
    var escaped = 0, tapped = 0
    override func accessibilityPerformEscape() -> Bool { escaped += 1; return true }
    override func accessibilityPerformMagicTap() -> Bool { tapped += 1; return true }
}

@Suite @MainActor struct AccessibilityTests {
    private func run(_ name: String) -> (UIKitScene, UIKitFixtureRunner) {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.textEngine = try! Goldens.textEngine()
        let fixture = AllUIKitFixtures.all.first { $0.name == name }!
        let runner = UIKitFixtureRunner(fixture, textEngine: scene.textEngine, assets: Goldens.assets)
        _ = runner.layoutFrames()
        return (scene, runner)
    }

    @Test func theTreeFollowsOrderTraitsAndModality() {
        let (scene, runner) = run("uikit/accessibility/basic")
        let tree = scene.semanticsTree()
        let labels = tree.map(\.label)
        #expect(labels.first == "Inbox" && tree[0].role == .heading)
        // accessibilityElements orders the buttons C, A, B; the hidden label is absent.
        #expect(labels.firstIndex(of: "C")! < labels.firstIndex(of: "A")! && labels.firstIndex(of: "A")! < labels.firstIndex(of: "B")!)
        #expect(!labels.contains("Secret") && !labels.contains("Modal"))
        let row = tree.first { $0.label == "Archived: 0" }!
        #expect(row.customActions == ["Archive", "Flag"] && row.role == .text)
        #expect(tree.first { $0.label == "Badge" }?.role == .image)
        let disabled = tree.first { $0.label == "Disabled" }!
        #expect(disabled.role == .button && !disabled.isEnabled)
        #expect(tree.first { $0.label == "Selected" }?.isSelected == true)
        #expect(tree.first { $0.label == "Terms" }?.role == .link)
        #expect(tree.first { $0.label == "Notifications" }?.role == .switch && tree.first { $0.label == "Notifications" }?.isOn == true)
        #expect(tree.first { $0.label == "Volume" }?.role == .slider)
        #expect(tree.first { $0.label == "Ready" }?.isLive == true)
        // The custom action runs by name and the tree follows.
        scene.performAccessibilityAction(semanticsIdentifier: row.identifier, name: "Archive")
        #expect(scene.semanticsTree().contains { $0.label == "Archived: 1" })
        // The modal panel hides its siblings once shown.
        runner.apply(step: 0)
        let modal = scene.semanticsTree().map(\.label)
        #expect(modal == ["Modal", "Close"])
    }

    @Test func postsQueueAnnouncementsAndFocusMoves() {
        let (scene, _) = run("uikit/accessibility/basic")
        #expect(scene.takeAccessibilityEvents().isEmpty)
        let announce = scene.semanticsTree().first { $0.label == "Announce" }!
        scene.activate(semanticsIdentifier: announce.identifier)
        #expect(scene.takeAccessibilityEvents() == [.announce("Saved")])
        #expect(scene.semanticsTree().contains { $0.label == "Announced" })
        let link = scene.semanticsTree().first { $0.label == "Terms" }!
        let view = scene.windows.first!.descendant(withSemanticsIdentifier: link.identifier)!
        UIAccessibility.post(notification: .layoutChanged, argument: view)
        UIAccessibility.post(notification: .screenChanged, argument: "New screen")
        #expect(scene.takeAccessibilityEvents() == [.focus(link.identifier), .layoutChanged, .announce("New screen"), .screenChanged])
        #expect(scene.takeAccessibilityEvents().isEmpty)
        #expect(!UIAccessibility.isVoiceOverRunning && UIAccessibility.isReduceMotionEnabled == scene.hostReducesMotion)
    }

    @Test func escapeMagicTapFrameAndActionsOnViews() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 200, height: 200), scale: 2)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let panel = Escaper(frame: CGRect(x: 10, y: 10, width: 100, height: 100))
        let inner = UIView(frame: CGRect(x: 10, y: 10, width: 40, height: 40))
        inner.isAccessibilityElement = true
        inner.accessibilityLabel = "Inner"
        inner.accessibilityFrame = CGRect(x: 0, y: 0, width: 200, height: 50)
        var ran: [String] = []
        inner.accessibilityCustomActions = [UIAccessibilityCustomAction(name: "Do") { action in ran.append(action.name); return true }]
        panel.addSubview(inner)
        window.addSubview(panel)
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 200, height: 200))
        let node = scene.semanticsTree().first { $0.label == "Inner" }!
        #expect(node.frame == CGRect(x: 0, y: 0, width: 200, height: 50) && node.customActions == ["Do"])
        scene.performAccessibilityAction(semanticsIdentifier: node.identifier, name: "escape")   // the superview handles it
        scene.performAccessibilityAction(semanticsIdentifier: node.identifier, name: "magicTap")
        scene.performAccessibilityAction(semanticsIdentifier: node.identifier, name: "Do")
        scene.performAccessibilityAction(semanticsIdentifier: node.identifier, name: "Missing")
        #expect(panel.escaped == 1 && panel.tapped == 1 && ran == ["Do"])
        #expect(inner.performAccessibilityCustomAction(named: "Do") && !inner.performAccessibilityCustomAction(named: "Missing"))
        let action = UIAccessibilityCustomAction(attributedName: NSAttributedString(string: "Named")) { _ in false }
        #expect(action.name == "Named" && !action.perform())
    }
}
