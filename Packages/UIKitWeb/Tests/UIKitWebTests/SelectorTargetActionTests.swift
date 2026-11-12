// Target-action with selectors on the Objective-C runtime (decision 0023): a control's
// `addTarget(_:action:for:)`, a gesture recognizer's `init(target:action:)` and a bar button
// item's target and action, as UIKit apps and packages write them (Popovers' long-press menu,
// CVCalendar's day taps). Recognizers are NSObjects, so an `@objc` method can take one.
#if canImport(ObjectiveC)
import Testing
import UIKit
@testable import UIKitWebCore

@MainActor final class ActionTarget: NSObject {
    var calls: [String] = []
    @objc func tapped(_ sender: Any?) { calls.append(sender is UIButton ? "tapped button" : sender is UIBarButtonItem ? "tapped item" : "tapped") }
    @objc func refresh() { calls.append("refresh") }
    @objc func pressed(_ recognizer: UILongPressGestureRecognizer) { calls.append("pressed \(recognizer.state.rawValue)") }
    @objc func tappedView(_ recognizer: UITapGestureRecognizer) { calls.append("tap \(recognizer.state == .ended)") }
}

@Suite @MainActor struct SelectorTargetActionTests {
    @Test func aControlSendsItsSelectorsInOrderAndLetsThemGo() {
        let button = UIButton(type: .system)
        let target = ActionTarget()
        var order: [String] = []
        button.addAction(UIAction { _ in order.append("action") }, for: .touchUpInside)
        button.addTarget(target, action: #selector(ActionTarget.tapped(_:)), for: .touchUpInside)
        button.addTarget(target, action: #selector(ActionTarget.refresh), for: [.touchUpInside, .valueChanged])
        button.sendActions(for: .touchUpInside)
        #expect(order == ["action"])
        #expect(target.calls == ["tapped button", "refresh"])
        #expect(button.allTargets == [AnyHashable(target)])
        #expect(button.actions(forTarget: target, forControlEvent: .touchUpInside) == ["tapped:", "refresh"])
        #expect(button.actions(forTarget: target, forControlEvent: .valueChanged) == ["refresh"])

        // Taking touchUpInside off `refresh` leaves it on valueChanged; a nil action takes every
        // selector of the target off the event.
        button.removeTarget(target, action: #selector(ActionTarget.refresh), for: .touchUpInside)
        target.calls.removeAll()
        button.sendActions(for: .touchUpInside)
        #expect(target.calls == ["tapped button"])
        button.removeTarget(target, action: nil, for: .allEvents)
        target.calls.removeAll()
        button.sendActions(for: [.touchUpInside, .valueChanged])
        #expect(target.calls.isEmpty)
        #expect(button.allTargets.isEmpty)
        #expect(order == ["action", "action", "action"])
    }

    @Test func aControlHoldsItsTargetWeakly() {
        let button = UIButton(type: .system)
        weak var gone: ActionTarget?
        do {
            let target = ActionTarget()
            gone = target
            button.addTarget(target, action: #selector(ActionTarget.refresh), for: .touchUpInside)
        }
        #expect(gone == nil)
        button.sendActions(for: .touchUpInside)
        #expect(button.allTargets.isEmpty)
    }

    @Test func aRecognizerSendsItsSelectorWithItself() {
        let scene = UIKitScene.shared
        scene.removeAllWindows()
        scene.configureScreen(size: CGSize(width: 300, height: 300), scale: 2)
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let target = ActionTarget()
        let tap = UITapGestureRecognizer(target: target, action: #selector(ActionTarget.tappedView(_:)))
        view.addGestureRecognizer(tap)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        window.addSubview(view)
        window.makeKeyAndVisible()
        scene.layout(in: CGSize(width: 300, height: 300))

        scene.pointerDown(at: CGPoint(x: 50, y: 50), type: .touch, time: 0)
        scene.pointerUp(at: CGPoint(x: 50, y: 50), time: 0.05)
        #expect(target.calls == ["tap true"])

        tap.removeTarget(target, action: nil)
        scene.pointerDown(at: CGPoint(x: 50, y: 50), type: .touch, time: 1)
        scene.pointerUp(at: CGPoint(x: 50, y: 50), time: 1.05)
        #expect(target.calls == ["tap true"])
        scene.removeAllWindows()
    }

    @Test func aRecognizerIsAnObjectiveCObject() {
        let target = ActionTarget()
        let press = UILongPressGestureRecognizer(target: target, action: #selector(ActionTarget.pressed(_:)))
        let recognizer: NSObject = press
        #expect(recognizer.isEqual(press) && !recognizer.isEqual(UILongPressGestureRecognizer()))
        // The recognizer goes to the `@objc` method that takes it, as a long press sends it.
        target.perform(#selector(ActionTarget.pressed(_:)), with: press)
        #expect(target.calls == ["pressed 0"])
    }

    @Test func aBarButtonItemSendsItsSelectorOnATap() {
        let target = ActionTarget()
        let item = UIBarButtonItem(title: "Edit", style: .plain, target: target, action: #selector(ActionTarget.tapped(_:)))
        let platter = BarPlatterButton(item: item)
        platter.sendActions(for: .primaryActionTriggered)
        #expect(target.calls == ["tapped item"])
        #expect(platter.longPressMenu == nil)
    }
}
#endif
