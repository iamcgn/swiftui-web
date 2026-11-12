import WebFoundation   // Foundation everywhere: `NSStringFromSelector` with the Objective-C runtime
// UIControl (Docs/elements/UIKit/UIControl.md): tracking and target-action. Without an
// Objective-C runtime there is no `#selector`, so actions are `UIAction`s (`addAction(_:for:)`,
// the closure form iOS 14 added) and `addTarget(_:action:for:)` takes a closure. With the runtime
// (decision 0023) `addTarget(_:action:for:)` takes a selector as UIKit's does, sent through
// `UIApplication.sendAction(_:to:from:for:)` (a nil target: up the responder chain).

/// An item in a menu: an action, a submenu or a deferred element (Containers/Menus.swift).
@preconcurrency @MainActor
open class UIMenuElement: Hashable {
    public var title: String
    public var image: UIImage?
    public var subtitle: String?

    public init(title: String = "", image: UIImage? = nil, subtitle: String? = nil) {
        self.title = title
        self.image = image
        self.subtitle = subtitle
    }

    nonisolated public static func == (lhs: UIMenuElement, rhs: UIMenuElement) -> Bool { lhs === rhs }
    nonisolated public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// A menu element that performs its action in a closure.
@preconcurrency @MainActor
public final class UIAction: UIMenuElement {
    public typealias Handler = (UIAction) -> Void

    public let identifier: Identifier
    public var discoverabilityTitle: String?
    public var attributes: Attributes
    public var state: State
    let handler: Handler
    /// The sender of the action (the control that fired it), for the duration of the handler.
    public private(set) weak var sender: AnyObject?

    public init(title: String = "", subtitle: String? = nil, image: UIImage? = nil, identifier: Identifier? = nil, discoverabilityTitle: String? = nil,
                attributes: Attributes = [], state: State = .off, handler: @escaping Handler) {
        self.identifier = identifier ?? Identifier(rawValue: "UIAction-\(UIAction.counter)")
        UIAction.counter += 1
        self.discoverabilityTitle = discoverabilityTitle
        self.attributes = attributes
        self.state = state
        self.handler = handler
        super.init(title: title, image: image, subtitle: subtitle)
    }

    nonisolated(unsafe) private static var counter = 0

    func perform(sender: AnyObject?) {
        self.sender = sender
        handler(self)
        self.sender = nil
    }

    public struct Identifier: Hashable, Sendable, RawRepresentable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
    }

    public struct Attributes: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let disabled = Attributes(rawValue: 1)
        public static let destructive = Attributes(rawValue: 2)
        public static let hidden = Attributes(rawValue: 4)
    }

    public enum State: Int, Sendable { case off = 0, on, mixed }
}

/// The base class for controls, which are visual elements that convey a specific action or
/// intention in response to user interactions.
@preconcurrency @MainActor
open class UIControl: UIView {
    public struct Event: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let touchDown = Event(rawValue: 1 << 0)
        public static let touchDownRepeat = Event(rawValue: 1 << 1)
        public static let touchDragInside = Event(rawValue: 1 << 2)
        public static let touchDragOutside = Event(rawValue: 1 << 3)
        public static let touchDragEnter = Event(rawValue: 1 << 4)
        public static let touchDragExit = Event(rawValue: 1 << 5)
        public static let touchUpInside = Event(rawValue: 1 << 6)
        public static let touchUpOutside = Event(rawValue: 1 << 7)
        public static let touchCancel = Event(rawValue: 1 << 8)
        public static let valueChanged = Event(rawValue: 1 << 12)
        public static let primaryActionTriggered = Event(rawValue: 1 << 13)
        public static let menuActionTriggered = Event(rawValue: 1 << 14)
        public static let editingDidBegin = Event(rawValue: 1 << 16)
        public static let editingChanged = Event(rawValue: 1 << 17)
        public static let editingDidEnd = Event(rawValue: 1 << 18)
        public static let editingDidEndOnExit = Event(rawValue: 1 << 19)
        public static let allTouchEvents = Event(rawValue: 0x00000FFF)
        public static let allEditingEvents = Event(rawValue: 0x000F0000)
        public static let allEvents = Event(rawValue: 0xFFFFFFFF)
    }

    public struct State: OptionSet, Hashable, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let normal = State([])
        public static let highlighted = State(rawValue: 1 << 0)
        public static let disabled = State(rawValue: 1 << 1)
        public static let selected = State(rawValue: 1 << 2)
        public static let focused = State(rawValue: 1 << 3)
        /// The bits left for the app's own states.
        public static let application = State(rawValue: 0x00FF0000)
        /// The bits UIKit keeps for itself.
        public static let reserved = State(rawValue: 0xFF000000)
    }

    public enum ContentVerticalAlignment: Int, Sendable { case center = 0, top, bottom, fill }
    public enum ContentHorizontalAlignment: Int, Sendable { case center = 0, left, right, fill, leading, trailing }

    open var isEnabled = true { didSet { stateDidChange() } }
    /// Controls take keyboard focus (Events/Keyboard.swift).
    override open var canBecomeFocused: Bool { true }
    open var isSelected = false { didSet { stateDidChange() } }
    open var isHighlighted = false { didSet { stateDidChange() } }
    open var contentVerticalAlignment: ContentVerticalAlignment = .center
    open var contentHorizontalAlignment: ContentHorizontalAlignment = .center
    open var isTracking = false
    open var isTouchInside = false
    open var showsMenuAsPrimaryAction = false

    open var state: State {
        var state = State.normal
        if !isEnabled { state.insert(.disabled) }
        if isSelected { state.insert(.selected) }
        if isHighlighted { state.insert(.highlighted) }
        return state
    }

    /// Subclasses repaint for a new state.
    open func stateDidChange() { setNeedsDisplay() }

    // MARK: Actions

    private var actions: [(action: UIAction, events: Event)] = []

    open func addAction(_ action: UIAction, for controlEvents: Event) {
        actions.append((action, controlEvents))
    }

    open func removeAction(_ action: UIAction, for controlEvents: Event) {
        actions.removeAll { $0.action === action && !$0.events.intersection(controlEvents).isEmpty }
    }

    open func removeAction(identifiedBy identifier: UIAction.Identifier, for controlEvents: Event) {
        actions.removeAll { $0.action.identifier == identifier && !$0.events.intersection(controlEvents).isEmpty }
    }

    /// The closure form of target-action: `addTarget(self, action: #selector(...), for:)` has no
    /// selector here; pass the method as a closure.
    open func addTarget(_ target: AnyObject? = nil, action: @escaping (UIControl) -> Void, for controlEvents: Event) {
        addAction(UIAction { [weak self] _ in if let self { action(self) } }, for: controlEvents)
    }

    #if canImport(ObjectiveC)
    /// The targets and selectors added with `addTarget(_:action:for:)`, each sent by an action in
    /// `actions` so the two kinds fire in the order they were added. A target is held weakly, as
    /// UIKit holds it.
    private struct TargetAction {
        weak var target: AnyObject?
        let hasTarget: Bool
        let selector: Selector
        let action: UIAction
    }
    private var targetActions: [TargetAction] = []

    /// Sends `action` to `target` (nil: the first responder that handles it) on `controlEvents`.
    /// Adding a target and selector again adds the events to the first.
    open func addTarget(_ target: Any?, action: Selector, for controlEvents: Event) {
        let object = target.map { $0 as AnyObject }
        if let existing = targetActions.first(where: { $0.hasTarget == (object != nil) && $0.target === object && $0.selector == action }),
           let index = actions.firstIndex(where: { $0.action === existing.action }) {
            actions[index].events.formUnion(controlEvents)
            return
        }
        let hasTarget = object != nil
        let send = UIAction { [weak self, weak object] _ in
            guard let self, !hasTarget || object != nil else { return }
            self.sendAction(action, to: object, for: nil)
        }
        targetActions.append(TargetAction(target: object, hasTarget: hasTarget, selector: action, action: send))
        actions.append((send, controlEvents))
    }

    /// Takes `controlEvents` off the matching targets and selectors (a nil target: every target;
    /// a nil action: every selector), dropping those left with no events.
    open func removeTarget(_ target: Any?, action: Selector?, for controlEvents: Event) {
        let object = target.map { $0 as AnyObject }
        for entry in targetActions where (object == nil || entry.target === object) && (action == nil || entry.selector == action) {
            guard let index = actions.firstIndex(where: { $0.action === entry.action }) else { continue }
            actions[index].events.subtract(controlEvents)
            if actions[index].events.isEmpty { actions.remove(at: index) }
        }
        targetActions.removeAll { entry in !actions.contains { $0.action === entry.action } }
    }

    /// The targets added with `addTarget(_:action:for:)` that are still alive.
    open var allTargets: Set<AnyHashable> {
        Set(targetActions.compactMap { $0.target as? AnyHashable })
    }

    /// The selector names sent to `target` (nil: the responder chain) on `controlEvent`, or nil.
    open func actions(forTarget target: Any?, forControlEvent controlEvent: Event) -> [String]? {
        let object = target.map { $0 as AnyObject }
        let names = targetActions.filter { entry in
            entry.hasTarget == (object != nil) && entry.target === object
                && actions.contains { $0.action === entry.action && !$0.events.intersection(controlEvent).isEmpty }
        }.map { NSStringFromSelector($0.selector) }
        return names.isEmpty ? nil : names
    }

    /// Sends `action` as the control's target-action does: through the application, to
    /// `target` or, with none, up the responder chain from the first responder.
    open func sendAction(_ action: Selector, to target: Any?, for event: UIEvent?) {
        UIApplication.shared.sendAction(action, to: target, from: self, for: event)
    }
    #endif

    open var allControlEvents: Event { actions.reduce(Event()) { $0.union($1.events) } }

    open func sendActions(for controlEvents: Event) {
        for entry in actions where !entry.events.intersection(controlEvents).isEmpty {
            entry.action.perform(sender: self)
        }
    }

    open func enumerateEventHandlers(_ iterator: (UIAction?, Event, Bool) -> Void) {
        for entry in actions { iterator(entry.action, entry.events, true) }
    }

    // MARK: Tracking

    open func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool { true }
    open func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool { true }
    open func endTracking(_ touch: UITouch?, with event: UIEvent?) {}
    open func cancelTracking(with event: UIEvent?) {}

    /// The menu a long press on the control opens (buttons and bar platters set it).
    var longPressMenu: UIMenu? { nil }
    private var longPressTimer: UIKitScene.Timer?
    private var longPressStart = CGPoint.zero

    override open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isEnabled, let touch = touches.first else { return }
        isTracking = beginTracking(touch, with: event)
        guard isTracking else { return }
        isTouchInside = true
        isHighlighted = true
        sendActions(for: touch.tapCount > 1 ? [.touchDown, .touchDownRepeat] : .touchDown)
        if let menu = longPressMenu {
            longPressStart = touch.location(in: nil)
            longPressTimer?.cancel()
            longPressTimer = UIKitScene.shared.schedule(after: MenuPresenter.longPressDuration) { [weak self] in
                guard let self, self.isTracking else { return }
                self.isTracking = false
                self.isHighlighted = false
                self.isTouchInside = false
                MenuPresenter.present(menu, from: self)
            }
        }
    }

    override open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isTracking, let touch = touches.first else { return }
        if longPressTimer != nil {
            let location = touch.location(in: nil)
            if abs(location.x - longPressStart.x) > 10 || abs(location.y - longPressStart.y) > 10 { longPressTimer?.cancel(); longPressTimer = nil }
        }
        let inside = point(inside: touch.location(in: self), with: event)
        if inside != isTouchInside {
            isTouchInside = inside
            isHighlighted = inside
            sendActions(for: inside ? .touchDragEnter : .touchDragExit)
        }
        isTracking = continueTracking(touch, with: event)
        sendActions(for: inside ? .touchDragInside : .touchDragOutside)
    }

    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        longPressTimer?.cancel()
        longPressTimer = nil
        guard isTracking, let touch = touches.first else { return }
        isTracking = false
        isHighlighted = false
        let inside = point(inside: touch.location(in: self), with: event)
        endTracking(touch, with: event)
        if inside {
            sendActions(for: [.touchUpInside, .primaryActionTriggered])
        } else {
            sendActions(for: .touchUpOutside)
        }
        isTouchInside = false
    }

    override open func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        longPressTimer?.cancel()
        longPressTimer = nil
        guard isTracking else { return }
        isTracking = false
        isHighlighted = false
        isTouchInside = false
        cancelTracking(with: event)
        sendActions(for: .touchCancel)
    }

    override open var accessibilityTraits: UIAccessibilityTraits {
        get { var t = super.accessibilityTraits; if !isEnabled { t.insert(.notEnabled) }; if isSelected { t.insert(.selected) }; return t }
        set { super.accessibilityTraits = newValue }
    }
}
