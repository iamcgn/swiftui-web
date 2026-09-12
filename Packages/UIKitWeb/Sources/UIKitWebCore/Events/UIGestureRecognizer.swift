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

    /// Moves to `state` and calls the handlers.
    func transition(to newState: State) {
        state = newState
        if newState == .ended { hasRecognizedThisFrame = true }
        if newState != .possible {
            for handler in handlers { handler(self) }
        }
        if newState == .ended || newState == .cancelled || newState == .failed {
            // Recognizers reset after a frame; here at once, once the handlers have run.
            state = .possible
            touches.removeAll()
            reset()
        }
    }

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

/// Fine-tuning of gesture recognition.
@MainActor
public protocol UIGestureRecognizerDelegate: AnyObject {
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool
}

extension UIGestureRecognizerDelegate {
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool { true }
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool { true }
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
