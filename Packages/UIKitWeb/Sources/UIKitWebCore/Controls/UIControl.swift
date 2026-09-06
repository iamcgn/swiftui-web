// UIControl (Docs/elements/UIKit/UIControl.md): tracking and target-action. Without an
// Objective-C runtime there is no `#selector`, so actions are `UIAction`s (`addAction(_:for:)`,
// the closure form iOS 14 added) and `addTarget(_:action:for:)` takes a closure.

/// A menu element that performs its action in a closure.
@MainActor
public final class UIAction: Hashable {
    public typealias Handler = (UIAction) -> Void

    public var title: String
    public var image: UIImage?
    public let identifier: Identifier
    public var discoverabilityTitle: String?
    public var attributes: Attributes
    public var state: State
    public var subtitle: String?
    let handler: Handler
    /// The sender of the action (the control that fired it), for the duration of the handler.
    public private(set) weak var sender: AnyObject?

    public init(title: String = "", image: UIImage? = nil, identifier: Identifier? = nil, discoverabilityTitle: String? = nil,
                attributes: Attributes = [], state: State = .off, handler: @escaping Handler) {
        self.title = title
        self.image = image
        self.identifier = identifier ?? Identifier(rawValue: "UIAction-\(UIAction.counter)")
        UIAction.counter += 1
        self.discoverabilityTitle = discoverabilityTitle
        self.attributes = attributes
        self.state = state
        self.handler = handler
    }

    nonisolated(unsafe) private static var counter = 0

    func perform(sender: AnyObject?) {
        self.sender = sender
        handler(self)
        self.sender = nil
    }

    nonisolated public static func == (lhs: UIAction, rhs: UIAction) -> Bool { lhs === rhs }
    nonisolated public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }

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
@MainActor
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
    }

    public enum ContentVerticalAlignment: Int, Sendable { case center = 0, top, bottom, fill }
    public enum ContentHorizontalAlignment: Int, Sendable { case center = 0, left, right, fill, leading, trailing }

    open var isEnabled = true { didSet { stateDidChange() } }
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

    override open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isEnabled, let touch = touches.first else { return }
        isTracking = beginTracking(touch, with: event)
        guard isTracking else { return }
        isTouchInside = true
        isHighlighted = true
        sendActions(for: touch.tapCount > 1 ? [.touchDown, .touchDownRepeat] : .touchDown)
    }

    override open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard isTracking, let touch = touches.first else { return }
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
