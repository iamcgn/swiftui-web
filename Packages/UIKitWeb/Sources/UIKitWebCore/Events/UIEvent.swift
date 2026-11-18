import WebFoundation   // Foundation everywhere: NSObject's Hashable for the sets of touches and presses
// Touches and events. The scene turns the host's pointer events into one touch (a mouse or a
// finger) and delivers it through gesture recognizers, then the responder chain.

/// An object that describes a single user interaction with your app. Rooted as the responders
/// are (`UIResponderBase`, `NSObject` with the runtime), as UIKit's is an `NSObject`: an `@objc`
/// action method can take the event (KeyboardToolbar's `touchDown(_ sender: UIButton, event:
/// UIEvent?)`), and a control sends it one.
@preconcurrency @MainActor
open class UIEvent: UIResponderBase {
    public enum EventType: Int, Sendable {
        case touches = 0, motion, remoteControl, presses, scroll = 10, hover, transform
    }

    /// What a motion or remote-control event is: a shake, or a media key (Harbour's
    /// `motionEnded(_:with:)` checks for `.motionShake`). A page hears neither, so the scene
    /// sends no such events and an event made here is `.none`.
    /// `@objc` with the runtime, so the motion methods that take it are `@objc` too and an app
    /// can override them from an extension (Harbour's `extension UIWindow { override func
    /// motionEnded(_:with:) }`), as UIKit's Objective-C methods allow.
    #if canImport(ObjectiveC)
    @objc public enum EventSubtype: Int, Sendable {
        case none = 0
        case motionShake = 1
        case remoteControlPlay = 100, remoteControlPause, remoteControlStop, remoteControlTogglePlayPause,
             remoteControlNextTrack, remoteControlPreviousTrack, remoteControlBeginSeekingBackward,
             remoteControlEndSeekingBackward, remoteControlBeginSeekingForward, remoteControlEndSeekingForward
    }
    #else
    public enum EventSubtype: Int, Sendable {
        case none = 0
        case motionShake = 1
        case remoteControlPlay = 100, remoteControlPause, remoteControlStop, remoteControlTogglePlayPause,
             remoteControlNextTrack, remoteControlPreviousTrack, remoteControlBeginSeekingBackward,
             remoteControlEndSeekingBackward, remoteControlBeginSeekingForward, remoteControlEndSeekingForward
    }
    #endif

    public let type: EventType
    public internal(set) var timestamp: Double
    var touches: Set<UITouch> = []

    init(type: EventType, timestamp: Double) {
        self.type = type
        self.timestamp = timestamp
        super.init()
    }

    /// The motion or remote-control kind of the event (`.none` for touches and presses).
    open var subtype: EventSubtype { .none }

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

/// An object representing the location, size, movement, and force of a touch. An `NSObject`
/// with the runtime, as UIKit's is, and Hashable by identity through its root.
@preconcurrency @MainActor
public final class UITouch: UIResponderBase {
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
        super.init()
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
}

/// A key press from the host's keyboard (Events/Keyboard.swift sends them down the responder chain).
/// An `NSObject` with the runtime, as UIKit's is, and Hashable by identity through its root.
@preconcurrency @MainActor
public final class UIPress: UIResponderBase {
    public enum Phase: Int, Sendable { case began = 0, changed, stationary, ended, cancelled }
    public let phase: Phase
    public let key: UIKey?
    init(phase: Phase, key: UIKey?) { self.phase = phase; self.key = key; super.init() }
}

public struct UIKey: Sendable {
    public let characters: String
    public let modifierFlags: UIKeyModifierFlags
    /// The host's key (the arrows, Tab, Return… beside the characters).
    public let key: KeyEquivalent
    public var charactersIgnoringModifiers: String { characters }
    public init(characters: String, modifierFlags: UIKeyModifierFlags, key: KeyEquivalent? = nil) {
        self.characters = characters
        self.modifierFlags = modifierFlags
        self.key = key ?? KeyEquivalent(characters.first ?? " ")
    }
}

public struct UIKeyModifierFlags: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let alphaShift = UIKeyModifierFlags(rawValue: 1 << 16)
    public static let shift = UIKeyModifierFlags(rawValue: 1 << 17)
    public static let control = UIKeyModifierFlags(rawValue: 1 << 18)
    public static let alternate = UIKeyModifierFlags(rawValue: 1 << 19)
    public static let command = UIKeyModifierFlags(rawValue: 1 << 20)
}

@preconcurrency @MainActor
public final class UIPressesEvent: UIEvent {
    public let allPresses: Set<UIPress>
    init(presses: Set<UIPress>, timestamp: Double) {
        allPresses = presses
        super.init(type: .presses, timestamp: timestamp)
    }
}
