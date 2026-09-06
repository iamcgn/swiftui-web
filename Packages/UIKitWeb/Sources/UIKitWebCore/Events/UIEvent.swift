// Touches and events. The scene turns the host's pointer events into one touch (a mouse or a
// finger) and delivers it through gesture recognizers, then the responder chain.

/// An object that describes a single user interaction with your app.
@MainActor
open class UIEvent {
    public enum EventType: Int, Sendable {
        case touches = 0, motion, remoteControl, presses, scroll = 10, hover, transform
    }

    public let type: EventType
    public let timestamp: Double
    var touches: Set<UITouch> = []

    init(type: EventType, timestamp: Double) {
        self.type = type
        self.timestamp = timestamp
    }

    open var allTouches: Set<UITouch>? { touches }

    open func touches(for view: UIView) -> Set<UITouch>? {
        let matching = touches.filter { $0.view === view }
        return matching.isEmpty ? nil : matching
    }

    open func touches(for window: UIWindow) -> Set<UITouch>? {
        let matching = touches.filter { $0.window === window }
        return matching.isEmpty ? nil : matching
    }

    open func touches(for gesture: UIGestureRecognizer) -> Set<UITouch>? {
        let matching = touches.filter { $0.gestureRecognizers?.contains { $0 === gesture } == true }
        return matching.isEmpty ? nil : matching
    }
}

/// An object representing the location, size, movement, and force of a touch.
@MainActor
public final class UITouch: Hashable {
    public enum Phase: Int, Sendable {
        case began = 0, moved, stationary, ended, cancelled, regionEntered, regionMoved, regionExited
    }

    public enum TouchType: Int, Sendable {
        case direct = 0, indirect, pencil, indirectPointer
    }

    public internal(set) var phase: Phase = .began
    public internal(set) var tapCount = 1
    public internal(set) var timestamp: Double
    public let type: TouchType
    public internal(set) weak var view: UIView?
    public internal(set) weak var window: UIWindow?
    public internal(set) var gestureRecognizers: [UIGestureRecognizer]?
    public var majorRadius: CGFloat { 10 }
    public var force: CGFloat { 0 }
    public var maximumPossibleForce: CGFloat { 0 }

    /// Locations in the window's coordinates.
    var windowLocation: CGPoint
    var previousWindowLocation: CGPoint

    init(at location: CGPoint, in window: UIWindow?, view: UIView?, type: TouchType, timestamp: Double) {
        windowLocation = location
        previousWindowLocation = location
        self.window = window
        self.view = view
        self.type = type
        self.timestamp = timestamp
    }

    /// The touch's location in a view's coordinates (nil: the window).
    public func location(in view: UIView?) -> CGPoint {
        guard let view, let window else { return windowLocation }
        return window.convert(windowLocation, to: view)
    }

    public func previousLocation(in view: UIView?) -> CGPoint {
        guard let view, let window else { return previousWindowLocation }
        return window.convert(previousWindowLocation, to: view)
    }

    nonisolated public static func == (lhs: UITouch, rhs: UITouch) -> Bool { lhs === rhs }
    nonisolated public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

/// A key press (the API is accepted; hardware keys reach text fields through the host).
@MainActor
public final class UIPress: Hashable {
    public enum Phase: Int, Sendable { case began = 0, changed, stationary, ended, cancelled }
    public let phase: Phase
    public let key: UIKey?
    init(phase: Phase, key: UIKey?) { self.phase = phase; self.key = key }
    nonisolated public static func == (lhs: UIPress, rhs: UIPress) -> Bool { lhs === rhs }
    nonisolated public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

public struct UIKey: Sendable {
    public let characters: String
    public let modifierFlags: UIKeyModifierFlags
}

public struct UIKeyModifierFlags: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let alphaShift = UIKeyModifierFlags(rawValue: 1 << 16)
    public static let shift = UIKeyModifierFlags(rawValue: 1 << 17)
    public static let control = UIKeyModifierFlags(rawValue: 1 << 18)
    public static let alternate = UIKeyModifierFlags(rawValue: 1 << 19)
    public static let command = UIKeyModifierFlags(rawValue: 1 << 20)
}

@MainActor
public final class UIPressesEvent: UIEvent {
    public let allPresses: Set<UIPress>
    init(presses: Set<UIPress>, timestamp: Double) {
        allPresses = presses
        super.init(type: .presses, timestamp: timestamp)
    }
}
