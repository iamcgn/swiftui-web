// Gesture recognizers (Docs/elements/UIKit/Gestures.md). Without an Objective-C runtime there
// is no `#selector`: recognizers take a closure handler (`UITapGestureRecognizer { _ in }`),
// and `addTarget(_:action:)` accepts a closure too.

/// The state of a gesture recognizer.
public enum UIGestureRecognizerState: Int, Sendable {
    case possible = 0, began, changed, ended, cancelled, failed
    public static let recognized = UIGestureRecognizerState.ended
}

/// The base class for gesture recognizers.
@MainActor
open class UIGestureRecognizer {
    public typealias State = UIGestureRecognizerState

    public private(set) var state: State = .possible
    public internal(set) weak var view: UIView?
    open var isEnabled = true
    open var cancelsTouchesInView = true
    open var delaysTouchesBegan = false
    open var delaysTouchesEnded = true
    open var name: String?
    open weak var delegate: (any UIGestureRecognizerDelegate)?
    var handlers: [(UIGestureRecognizer) -> Void] = []
    var touches: [UITouch] = []
    /// Recognizers this one waits for (`require(toFail:)`): it recognizes only once they failed.
    private(set) var failureRequirements: [WeakRecognizer] = []
    /// A transition held back while a required recognizer is still undecided.
    var deferredState: State?
    /// How the recognizer fared on the touch in flight (nil while still possible).
    enum Outcome { case recognized, failed }
    var outcomeThisTouch: Outcome?

    /// Makes this recognizer wait for `otherGestureRecognizer` to fail before it can recognize
    /// (a single tap deferring to a double tap).
    open func require(toFail otherGestureRecognizer: UIGestureRecognizer) {
        failureRequirements.append(WeakRecognizer(recognizer: otherGestureRecognizer))
    }

    /// The recognizers this one must see fail first: its own requirements and the delegates'.
    func requiredToFail(among others: [UIGestureRecognizer]) -> [UIGestureRecognizer] {
        var result = failureRequirements.compactMap(\.recognizer)
        for other in others where other !== self {
            if delegate?.gestureRecognizer(self, shouldRequireFailureOf: other) == true
                || other.delegate?.gestureRecognizer(other, shouldBeRequiredToFailBy: self) == true {
                result.append(other)
            }
        }
        return result
    }

    /// The framework's own recognizers (scroll views' pans, a table's swipe pan and tap) run
    /// alongside any other, as UIKit's internal recognizers cooperate: each decides on its own
    /// whether a drag is its (`UIScrollView.ignoringPan`, the table's delegate methods).
    var allowsSimultaneousRecognition = false

    /// Whether this recognizer and `other` may recognize at once (either delegate agreeing, or
    /// either being one of the framework's cooperative recognizers).
    func canRecognizeSimultaneously(with other: UIGestureRecognizer) -> Bool {
        allowsSimultaneousRecognition || other.allowsSimultaneousRecognition
            || (delegate?.gestureRecognizer(self, shouldRecognizeSimultaneouslyWith: other) ?? false)
            || (other.delegate?.gestureRecognizer(other, shouldRecognizeSimultaneouslyWith: self) ?? false)
    }

    public init() {}

    /// A recognizer that calls `handler` on every state change past `possible`.
    public convenience init(handler: @escaping (UIGestureRecognizer) -> Void) {
        self.init()
        handlers.append(handler)
    }

    /// Adds a handler (the closure form of target-action).
    open func addTarget(_ handler: @escaping (UIGestureRecognizer) -> Void) {
        handlers.append(handler)
    }

    open var numberOfTouches: Int { touches.count }

    open func location(in view: UIView?) -> CGPoint {
        guard let touch = touches.first else { return .zero }
        return touch.location(in: view)
    }

    open func location(ofTouch index: Int, in view: UIView?) -> CGPoint {
        guard touches.indices.contains(index) else { return .zero }
        return touches[index].location(in: view)
    }

    /// Moves to `state` and calls the handlers. Recognition (`began`, `ended`) waits while a
    /// recognizer this one requires to fail is still undecided (`TouchRouter.arbitrate`).
    func transition(to newState: State) {
        // A recognizer that failed stays failed until the touch sequence ends.
        if outcomeThisTouch == .failed { return }
        if newState == .began || newState == .ended, state == .possible {
            let peers = touches.first?.gestureRecognizers ?? pinchPeers ?? []
            // A required recognizer that recognized fails this one; an undecided one holds it.
            let required = requiredToFail(among: peers)
            if required.contains(where: { $0.outcomeThisTouch == .recognized || $0.hasRecognized }) { applyTransition(to: .failed); return }
            if required.contains(where: { $0.outcomeThisTouch == nil && !$0.hasRecognized }) { deferredState = newState; return }
            // Only one recognizer recognizes a touch unless a delegate allows both.
            if peers.contains(where: { $0 !== self && ($0.hasRecognized || $0.hasRecognizedThisFrame) && !$0.canRecognizeSimultaneously(with: self) }) {
                applyTransition(to: .failed)
                return
            }
        }
        applyTransition(to: newState)
    }

    /// The recognizers sharing a pinch (no touches carry them).
    var pinchPeers: [UIGestureRecognizer]?

    func applyTransition(to newState: State) {
        deferredState = nil
        state = newState
        if newState == .ended { hasRecognizedThisFrame = true }
        if newState == .began || newState == .ended { outcomeThisTouch = .recognized }
        if newState == .failed || newState == .cancelled { outcomeThisTouch = .failed }
        // Actions see began, changed, ended and cancelled; a failure is not reported.
        if newState != .possible, newState != .failed {
            for handler in handlers { handler(self) }
        }
        if newState == .ended || newState == .cancelled || newState == .failed {
            // Recognizers reset after a frame; here at once, once the handlers have run.
            state = .possible
            touches.removeAll()
            reset()
        }
    }

    /// A pinch from the host (the scene feeds pinch and rotation recognizers; others ignore it).
    func pinch(_ phase: ContinuousGesturePhase, scale: CGFloat, rotation: CGFloat, location: CGPoint, time: Double) {}

    open func reset() {}

    /// Whether the recognizer may begin (the view's and the delegate's say).
    func mayBegin() -> Bool {
        guard isEnabled, let view else { return false }
        guard view.gestureRecognizerShouldBegin(self) else { return false }
        return delegate?.gestureRecognizerShouldBegin(self) ?? true
    }

    // Subclasses handle touches in their own coordinates.
    open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) { self.touches = Array(touches) }
    open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {}
    open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {}
    open func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { transition(to: .cancelled) }

    /// Whether this recognizer has claimed the touch (the view stops seeing it).
    var hasRecognized: Bool { state == .began || state == .changed || state == .ended }
    /// Set when a discrete gesture recognized on the touch that just ended (it has already
    /// reset to `possible` by the time the scene routes the touch).
    var hasRecognizedThisFrame = false
}

struct WeakRecognizer {
    weak var recognizer: UIGestureRecognizer?
}

/// Fine-tuning of gesture recognition.
@MainActor
public protocol UIGestureRecognizerDelegate: AnyObject {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool
}

extension UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { true }
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool { true }
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
}

/// A discrete gesture recognizer that interprets single or multiple taps.
@MainActor
open class UITapGestureRecognizer: UIGestureRecognizer {
    open var numberOfTapsRequired = 1
    open var numberOfTouchesRequired = 1
    private var startLocation = CGPoint.zero
    private var tapsSoFar = 0
    private var lastTapTime: Double = 0
    /// Set once the finger travelled: the tap has failed for this touch (the state resets to
    /// possible at once, so the end of the touch must not recognise it).
    private var travelled = false

    override open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        startLocation = touch.location(in: nil)
        travelled = false
        if event.timestamp - lastTapTime > 0.35 { tapsSoFar = 0 }
    }

    override open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, !travelled else { return }
        let location = touch.location(in: nil)
        // A finger that travels fails the tap (UIKit's slop is about 10 pt).
        if abs(location.x - startLocation.x) > 10 || abs(location.y - startLocation.y) > 10 { travelled = true; transition(to: .failed) }
    }

    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard state == .possible, !travelled, mayBegin() else { return }
        tapsSoFar += 1
        lastTapTime = event.timestamp
        if tapsSoFar >= numberOfTapsRequired {
            tapsSoFar = 0
            transition(to: .ended)
        }
    }
}

/// A discrete gesture recognizer that interprets long presses.
@MainActor
open class UILongPressGestureRecognizer: UIGestureRecognizer {
    open var minimumPressDuration: Double = 0.5
    open var allowableMovement: CGFloat = 10
    open var numberOfTouchesRequired = 1
    private var startLocation = CGPoint.zero
    private var startTime: Double = 0
    private var timer: UIKitScene.Timer?

    override open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first, mayBegin() else { return }
        startLocation = touch.location(in: nil)
        startTime = event.timestamp
        timer = UIKitScene.shared.schedule(after: minimumPressDuration) { [weak self] in
            guard let self, self.state == .possible else { return }
            self.transition(to: .began)
        }
    }

    override open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: nil)
        let moved = abs(location.x - startLocation.x) > allowableMovement || abs(location.y - startLocation.y) > allowableMovement
        switch state {
        case .possible where moved: timer?.cancel(); transition(to: .failed)
        case .began, .changed: transition(to: .changed)
        default: break
        }
    }

    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        timer?.cancel()
        switch state {
        case .began, .changed: transition(to: .ended)
        default: transition(to: .failed)
        }
    }

    override open func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        timer?.cancel()
        super.touchesCancelled(touches, with: event)
    }
}

/// A continuous gesture recognizer that interprets panning gestures.
@MainActor
open class UIPanGestureRecognizer: UIGestureRecognizer {
    open var minimumNumberOfTouches = 1
    open var maximumNumberOfTouches = Int.max
    private var startLocation = CGPoint.zero
    private var lastLocation = CGPoint.zero
    private var lastTime: Double = 0
    private var currentVelocity = CGPoint.zero
    private var accumulated = CGPoint.zero

    override open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        startLocation = touch.location(in: nil)
        lastLocation = startLocation
        lastTime = event.timestamp
        accumulated = .zero
    }

    override open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first else { return }
        let location = touch.location(in: nil)
        let dt = event.timestamp - lastTime
        if dt > 0 { currentVelocity = CGPoint(x: (location.x - lastLocation.x) / dt, y: (location.y - lastLocation.y) / dt) }
        lastLocation = location
        lastTime = event.timestamp
        switch state {
        case .possible:
            // The pan begins once the finger has travelled the slop; the translation is set
            // first so the view can judge the direction in `gestureRecognizerShouldBegin`.
            if abs(location.x - startLocation.x) > 10 || abs(location.y - startLocation.y) > 10 {
                accumulated = CGPoint(x: location.x - startLocation.x, y: location.y - startLocation.y)
                if mayBegin() { transition(to: .began) } else { accumulated = .zero }
            }
        case .began, .changed:
            accumulated = CGPoint(x: location.x - startLocation.x, y: location.y - startLocation.y)
            transition(to: .changed)
        default: break
        }
    }

    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        switch state {
        case .began, .changed: transition(to: .ended)
        default: transition(to: .failed)
        }
    }

    /// The pan's total translation in `view`'s coordinates (the window's scale: no transforms).
    open func translation(in view: UIView?) -> CGPoint { CGPoint(x: accumulated.x + translationOffset.x, y: accumulated.y + translationOffset.y) }
    private var translationOffset = CGPoint.zero

    open func setTranslation(_ translation: CGPoint, in view: UIView?) {
        translationOffset = CGPoint(x: translation.x - accumulated.x, y: translation.y - accumulated.y)
    }

    open func velocity(in view: UIView?) -> CGPoint { currentVelocity }

    override open func reset() {
        translationOffset = .zero
        accumulated = .zero
        currentVelocity = .zero
    }
}

/// A discrete gesture recognizer that interprets swiping gestures in one or more directions.
@MainActor
open class UISwipeGestureRecognizer: UIGestureRecognizer {
    public struct Direction: OptionSet, Sendable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let right = Direction(rawValue: 1 << 0)
        public static let left = Direction(rawValue: 1 << 1)
        public static let up = Direction(rawValue: 1 << 2)
        public static let down = Direction(rawValue: 1 << 3)
    }

    open var direction: Direction = .right
    open var numberOfTouchesRequired = 1
    private var startLocation = CGPoint.zero
    private var startTime: Double = 0
    private var decided = false

    override open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first else { return }
        startLocation = touch.location(in: nil)
        startTime = event.timestamp
        decided = false
    }

    /// Recognizes once the finger travelled 50 pt mostly along a permitted direction within
    /// half a second; a slow or sideways move fails.
    override open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = touches.first, !decided else { return }
        let location = touch.location(in: nil)
        let dx = location.x - startLocation.x, dy = location.y - startLocation.y
        let distance = max(abs(dx), abs(dy))
        guard distance >= 50 else { return }
        decided = true
        if event.timestamp - startTime > 0.5 { transition(to: .failed); return }
        let swiped: Direction
        if abs(dx) >= abs(dy) { swiped = dx > 0 ? .right : .left } else { swiped = dy > 0 ? .down : .up }
        guard min(abs(dx), abs(dy)) <= distance / 2, direction.contains(swiped), mayBegin() else { transition(to: .failed); return }
        transition(to: .ended)
    }

    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if !decided { transition(to: .failed) }
    }
}

/// A continuous gesture recognizer that interprets panning gestures that start near an edge of
/// the screen.
@MainActor
open class UIScreenEdgePanGestureRecognizer: UIPanGestureRecognizer {
    open var edges: UIRectEdge = []
    private var startedAtEdge = false
    /// How far from the edge a pan may start.
    static let edgeWidth: CGFloat = 20

    override open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first, let window = touch.window else { startedAtEdge = false; return }
        let location = touch.location(in: nil)
        let bounds = window.bounds
        startedAtEdge = (edges.contains(.left) && location.x <= bounds.minX + Self.edgeWidth)
            || (edges.contains(.right) && location.x >= bounds.maxX - Self.edgeWidth)
            || (edges.contains(.top) && location.y <= bounds.minY + Self.edgeWidth)
            || (edges.contains(.bottom) && location.y >= bounds.maxY - Self.edgeWidth)
        if !startedAtEdge { transition(to: .failed) }
    }

    override open func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard startedAtEdge else { return }
        super.touchesMoved(touches, with: event)
    }

    override open func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard startedAtEdge else { return }
        super.touchesEnded(touches, with: event)
    }
}

/// A continuous gesture recognizer that interprets pinching gestures (fed by the host's
/// trackpad or two-finger pinch through `UIKitScene.pinch`).
@MainActor
open class UIPinchGestureRecognizer: UIGestureRecognizer {
    open var scale: CGFloat = 1
    open private(set) var velocity: CGFloat = 0
    private var lastScale: CGFloat = 1
    private var lastTime: Double = 0
    private var centre = CGPoint.zero
    private weak var window: UIWindow?

    override open func location(in view: UIView?) -> CGPoint {
        guard let view, let window else { return centre }
        return window.convert(centre, to: view)
    }

    override open var numberOfTouches: Int { state == .possible ? 0 : 2 }

    override func pinch(_ phase: ContinuousGesturePhase, scale: CGFloat, rotation: CGFloat, location: CGPoint, time: Double) {
        centre = location
        window = view?.window
        switch phase {
        case .began:
            lastScale = 1
            lastTime = time
            velocity = 0
            self.scale = 1
        case .changed:
            if time > lastTime { velocity = (scale - lastScale) / (time - lastTime) }
            lastScale = scale
            lastTime = time
            self.scale = scale
            if state == .possible {
                // Begins once the scale has moved a hundredth.
                guard abs(scale - 1) >= 0.01, mayBegin() else { return }
                transition(to: .began)
            } else {
                transition(to: .changed)
            }
        case .ended:
            self.scale = scale
            if state == .began || state == .changed { transition(to: .ended) } else { transition(to: .failed) }
        case .cancelled:
            if state == .began || state == .changed { transition(to: .cancelled) } else { transition(to: .failed) }
        }
    }

    override open func reset() {
        scale = 1
        velocity = 0
    }
}

/// A continuous gesture recognizer that interprets rotation gestures involving two touches.
@MainActor
open class UIRotationGestureRecognizer: UIGestureRecognizer {
    open var rotation: CGFloat = 0
    open private(set) var velocity: CGFloat = 0
    private var lastRotation: CGFloat = 0
    private var lastTime: Double = 0
    private var centre = CGPoint.zero
    private weak var window: UIWindow?

    override open func location(in view: UIView?) -> CGPoint {
        guard let view, let window else { return centre }
        return window.convert(centre, to: view)
    }

    override open var numberOfTouches: Int { state == .possible ? 0 : 2 }

    override func pinch(_ phase: ContinuousGesturePhase, scale: CGFloat, rotation: CGFloat, location: CGPoint, time: Double) {
        centre = location
        window = view?.window
        switch phase {
        case .began:
            lastRotation = 0
            lastTime = time
            velocity = 0
            self.rotation = 0
        case .changed:
            if time > lastTime { velocity = (rotation - lastRotation) / (time - lastTime) }
            lastRotation = rotation
            lastTime = time
            self.rotation = rotation
            if state == .possible {
                // Begins once the fingers turned half a degree.
                guard abs(rotation) >= 0.5 * .pi / 180, mayBegin() else { return }
                transition(to: .began)
            } else {
                transition(to: .changed)
            }
        case .ended:
            self.rotation = rotation
            if state == .began || state == .changed { transition(to: .ended) } else { transition(to: .failed) }
        case .cancelled:
            if state == .began || state == .changed { transition(to: .cancelled) } else { transition(to: .failed) }
        }
    }

    override open func reset() {
        rotation = 0
        velocity = 0
    }
}
