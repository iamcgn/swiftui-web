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
    /// Takes the item itself, as SwiftyFORM's toolbar's actions do: the item is an NSObject.
    @objc func nextField(_ sender: UIBarButtonItem) { calls.append("next \(sender.title ?? "")") }
}

/// Action methods that take the event too, as KeyboardToolbar's `touchDown(_ sender: UIButton,
/// event: UIEvent?)` does: they compile only where `UIEvent` is an Objective-C object.
@MainActor final class EventTarget: NSObject {
    var events: [String] = []
    @objc private func touchDown(_ sender: UIButton, event: UIEvent?) {
        events.append(event.map { "down \($0.type == .touches) \($0.allTouches?.count ?? 0)" } ?? "down nil")
    }
    static let touchDownAction = #selector(touchDown(_:event:))
}

/// A controller whose `@objc` method takes a rectangle and is declared in an extension, as
/// CVCalendar's content controllers' `updateFrames(_ frame: CGRect)` is, and a subclass that
/// overrides it: both compile only where `CGRect` is representable in Objective-C.
@MainActor class FramedController: UIViewController {
    var log: [String] = []
}

extension FramedController {
    @objc func updateFrames(_ frame: CGRect) { log.append("base \(Int(frame.width))x\(Int(frame.height))") }
}

@MainActor final class MonthFramedController: FramedController {
    override func updateFrames(_ frame: CGRect) {
        super.updateFrames(frame)
        log.append("month")
    }
}

/// A delegate protocol in CVCalendar's shape: `@objc` optional methods that return a size and a
/// block from a rectangle to a path.
@MainActor @objc protocol CalendarShapeDelegate {
    @objc optional func dotMarker(sizeOnDayView view: UIView) -> CGFloat
    @objc optional func selectionViewPath() -> ((CGRect) -> UIBezierPath)
    @objc optional func preferredSize() -> CGSize
}

@MainActor final class CalendarShapes: NSObject, CalendarShapeDelegate {
    func selectionViewPath() -> ((CGRect) -> UIBezierPath) { { UIBezierPath(rect: $0) } }
    func preferredSize() -> CGSize { CGSize(width: 44, height: 30) }
}

/// A controller whose `viewDidLoad()` override is in an extension, as Dime's
/// `extension UINavigationController { override open func viewDidLoad() }` is: it compiles only
/// where the method is `@objc dynamic`, as UIKit's is.
@MainActor final class ExtensionLoadedController: UIViewController {
    var events: [String] = []
}

extension ExtensionLoadedController {
    override func viewDidLoad() {
        super.viewDidLoad()
        events.append("load")
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        events.append("willAppear")
    }
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

    @Test func aControlSendsTheTouchEventToAnActionThatTakesOne() {
        let button = UIButton(type: .system)
        button.frame = CGRect(x: 0, y: 0, width: 100, height: 44)
        let target = EventTarget()
        button.addTarget(target, action: EventTarget.touchDownAction, for: .touchDown)
        let touch = UITouch(at: CGPoint(x: 10, y: 10), in: nil, view: button, type: .direct, timestamp: 0)
        let event = UIEvent(type: .touches, timestamp: 0)
        event.touches = [touch]
        button.touchesBegan([touch], with: event)
        // Outside a touch there is no event to send.
        button.sendActions(for: .touchDown)
        #expect(target.events == ["down true 1", "down nil"])
    }

    @Test func eventsTouchesAndPressesAreObjectiveCObjects() {
        let touch = UITouch(at: .zero, in: nil, view: nil, type: .direct, timestamp: 0)
        let event = UIEvent(type: .touches, timestamp: 0)
        let press = UIPress(phase: .began, key: nil)
        #expect((touch as AnyObject) is NSObject)
        #expect((event as AnyObject) is NSObject)
        #expect((press as AnyObject) is NSObject)
        // Hashable by identity, as before.
        let other = UITouch(at: .zero, in: nil, view: nil, type: .direct, timestamp: 0)
        #expect(Set([touch, touch, other]).count == 2)
        #expect(touch == touch && touch != other)
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

    @Test func aBarButtonItemSendsItselfToAMethodThatTakesAnItem() {
        let target = ActionTarget()
        let item = UIBarButtonItem(title: "Next", style: .plain, target: target, action: #selector(ActionTarget.nextField(_:)))
        let object: NSObject = item
        #expect(object.isEqual(item) && !object.isEqual(UIBarButtonItem()))
        BarPlatterButton(item: item).sendActions(for: .primaryActionTriggered)
        target.perform(#selector(ActionTarget.nextField(_:)), with: item)
        #expect(target.calls == ["next Next", "next Next"])
    }

    @Test func aLifecycleOverrideInAnExtensionRuns() {
        let controller = ExtensionLoadedController(nibName: nil, bundle: nil)
        controller.loadViewIfNeeded()
        controller.viewWillAppear(false)
        #expect(controller.events == ["load", "willAppear"])
        #expect(controller.responds(to: #selector(UIViewController.viewDidLoad)))
    }

    /// The selector and target are read on the tap: an item changed after its bar was built (an
    /// Edit button switched to Done, a target set later) sends the current pair.
    @Test func aBarButtonItemSendsItsCurrentSelector() {
        let first = ActionTarget(), second = ActionTarget()
        let item = UIBarButtonItem(title: "Edit", style: .plain, target: first, action: #selector(ActionTarget.tapped(_:)))
        let platter = BarPlatterButton(item: item)
        item.target = second
        item.action = #selector(ActionTarget.refresh)
        platter.sendActions(for: .primaryActionTriggered)
        #expect(first.calls.isEmpty && second.calls == ["refresh"])

        let late = UIBarButtonItem(title: "Done", style: .done, target: nil, action: nil)
        let latePlatter = BarPlatterButton(item: late)
        late.target = first
        late.action = #selector(ActionTarget.tapped(_:))
        latePlatter.sendActions(for: .primaryActionTriggered)
        #expect(first.calls == ["tapped item"])
    }

    /// CVCalendar's `@objc func updateFrames(_ frame: CGRect)` in an extension, overridden by a
    /// subclass: the override runs, with the rectangle as sent.
    @Test func anObjectiveCMethodTakesARectangleAndItsOverrideRuns() {
        let controller: FramedController = MonthFramedController(nibName: nil, bundle: nil)
        controller.updateFrames(CGRect(x: 0, y: 0, width: 320, height: 48))
        #expect(controller.log == ["base 320x48", "month"])
        #expect(controller.responds(to: #selector(FramedController.updateFrames(_:))))
    }

    /// An `@objc` optional method returns a block from a rectangle to a path, and another a
    /// size; an unimplemented one answers nil. The path is an NSObject, as UIKit's is.
    @Test func anObjectiveCProtocolReturnsAPathBlockAndASize() {
        let delegate: CalendarShapeDelegate = CalendarShapes()
        let rect = CGRect(x: 4, y: 6, width: 30, height: 20)
        let path = delegate.selectionViewPath?()(rect)
        #expect(path?.bounds == rect)
        #expect(delegate.preferredSize?() == CGSize(width: 44, height: 30))
        #expect(delegate.dotMarker?(sizeOnDayView: UIView()) == nil)
        let object: NSObject? = path
        #expect(object != nil && object?.isEqual(path) == true && object?.isEqual(UIBezierPath()) == false)
    }

    /// The geometry structs keep their value semantics: equal by value, hashable, with zero and
    /// null and the Int initializers.
    @Test func geometryStructsCompareAndHashByValue() {
        let a = CGRect(x: 1, y: 2, width: 3, height: 4)
        let b = CGRect(origin: CGPoint(x: 1.0, y: 2.0), size: CGSize(width: 3.0, height: 4.0))
        #expect(a == b && a != .zero && CGRect.null.isNull && CGPoint() == .zero && CGSize() == .zero)
        // On the Mac host these are Apple's structs, whose Hashable needs macOS 15.
        if #available(macOS 15, *) {
            #expect(Set([a, b, .zero]).count == 2 && Set([CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 1)]).count == 1)
        }
        #expect(a.maxX == 4 && a.midY == 4 && a.contains(CGPoint(x: 2, y: 3)))
    }
}
#endif
