// A gesture recognizer fed by another framework's presses. SwiftUI's
// `UIGestureRecognizerRepresentable` (iOS 18) attaches a UIKit recognizer to a SwiftUI view;
// here a SwiftUI view has no UIView behind it, so the recognizer sits on a stand-in view the
// SwiftUI view's size and sees one touch per press, as `TouchRouter` delivers one: the delegate
// is asked whether it receives the touch, then touches began, moved and ended or cancelled,
// with the failure requirements and arbitration the router applies. Docs/elements/Gestures.md.

/// Drives one recognizer from presses in window coordinates.
@preconcurrency @MainActor
public final class HostedGestureRecognizerDriver {
    public let recognizer: UIGestureRecognizer
    /// The stand-in for the SwiftUI view: the recognizer's `view`, outside any window.
    public let view = UIView()
    private var touch: UITouch?
    private var event: UIEvent?

    public init(_ recognizer: UIGestureRecognizer) {
        self.recognizer = recognizer
        view.addGestureRecognizer(recognizer)
    }

    /// Where the SwiftUI view is in the window: the stand-in takes its frame, and a touch's
    /// `location(in:)` the stand-in is relative to its origin.
    public var frame: CGRect {
        get { view.frame }
        set {
            view.frame = newValue
            touch?.detachedViewOrigin = newValue.origin
        }
    }

    /// Whether the recognizer has begun or recognized on the press in flight.
    public var isRecognizing: Bool { recognizer.hasRecognized }

    /// A press at `point` (window coordinates).
    public func began(at point: CGPoint, time: Double) {
        cancel()
        guard recognizer.isEnabled else { return }
        let touch = UITouch(at: point, in: nil, view: view, type: .direct, timestamp: time)
        touch.detachedViewOrigin = view.frame.origin
        guard recognizer.delegate?.gestureRecognizer(recognizer, shouldReceive: touch) ?? true else { return }
        let event = UIEvent(type: .touches, timestamp: time)
        event.touches = [touch]
        touch.gestureRecognizers = [recognizer]
        self.touch = touch
        self.event = event
        recognizer.outcomeThisTouch = nil
        recognizer.deferredState = nil
        recognizer.touchesBegan([touch], with: event)
        TouchRouter.arbitrate([recognizer])
    }

    public func moved(to point: CGPoint, time: Double) {
        guard let touch, let event else { return }
        touch.previousWindowLocation = touch.windowLocation
        touch.windowLocation = point
        touch.timestamp = time
        event.timestamp = time
        touch.phase = .moved
        recognizer.touchesMoved([touch], with: event)
        TouchRouter.arbitrate([recognizer])
    }

    /// The press ended at `point`, or was cancelled (another gesture or a scroll took it).
    public func ended(at point: CGPoint, time: Double, cancelled: Bool = false) {
        guard let touch, let event else { return }
        touch.previousWindowLocation = touch.windowLocation
        touch.windowLocation = point
        touch.timestamp = time
        event.timestamp = time
        touch.phase = cancelled ? .cancelled : .ended
        if cancelled {
            recognizer.touchesCancelled([touch], with: event)
        } else {
            recognizer.touchesEnded([touch], with: event)
            TouchRouter.arbitrate([recognizer], touchEnded: true)
        }
        recognizer.hasRecognizedThisFrame = false
        recognizer.outcomeThisTouch = nil
        recognizer.deferredState = nil
        self.touch = nil
        self.event = nil
    }

    /// Cancels the press in flight, if any.
    public func cancel() {
        guard let touch else { return }
        ended(at: touch.windowLocation, time: touch.timestamp, cancelled: true)
    }
}
