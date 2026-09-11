// Turning a host's pointer into UIKit touches for one window: hit test, the gesture
// recognizers on the hit view and its ancestors first, then the responder chain. The scene
// routes the pointer over its windows through one router; a tree hosted inside another
// framework's scene (SwiftUIWeb's representables, decision 0014) owns its own.

@MainActor
final class TouchRouter {
    private var activeTouch: UITouch?
    private var activeEvent: UIEvent?
    private var lastTapTime: Double = 0
    private var lastTapLocation = CGPoint.zero

    /// Whether a touch is in progress.
    var isTracking: Bool { activeTouch != nil }
    /// The view the touch in progress landed on.
    var hitView: UIView? { activeTouch?.view }

    /// A press at `point` (in `window`'s coordinates).
    func pointerDown(at point: CGPoint, in window: UIWindow, type: PointerType, time: Double) {
        let hit = window.hitTest(window.convert(point, from: nil), with: nil)
        let touch = UITouch(at: point, in: window, view: hit, type: type == .touch ? .direct : .indirectPointer, timestamp: time)
        if time - lastTapTime < 0.35, abs(point.x - lastTapLocation.x) < 20, abs(point.y - lastTapLocation.y) < 20 { touch.tapCount = 2 }
        lastTapTime = time
        lastTapLocation = point
        let event = UIEvent(type: .touches, timestamp: time)
        event.touches = [touch]
        activeTouch = touch
        activeEvent = event
        // Gesture recognizers on the hit view and its ancestors see the touch first.
        var recognizers: [UIGestureRecognizer] = []
        var view: UIView? = hit
        while let v = view {
            recognizers += (v.gestureRecognizers ?? []).filter { $0.isEnabled && ($0.delegate?.gestureRecognizer($0, shouldReceive: touch) ?? true) }
            view = v.superview
        }
        touch.gestureRecognizers = recognizers
        for recognizer in recognizers { recognizer.touchesBegan([touch], with: event) }
        if !recognizers.contains(where: { $0.hasRecognized && $0.cancelsTouchesInView }) {
            hit?.touchesBegan([touch], with: event)
        }
        // A press outside the first responder ends its editing.
        let scene = UIKitScene.shared
        if let responder = scene.firstResponder as? UIView, responder.window === window,
           hit !== responder, !(hit?.isDescendant(of: responder) ?? false) {
            _ = responder.resignFirstResponder()
        }
        scene.setNeedsFrame()
    }

    func pointerMoved(to point: CGPoint, time: Double) {
        guard let touch = activeTouch, let event = activeEvent else { return }
        touch.previousWindowLocation = touch.windowLocation
        touch.windowLocation = point
        touch.timestamp = time
        event.timestamp = time
        touch.phase = .moved
        let wasRecognized = touch.gestureRecognizers?.contains { $0.hasRecognized && $0.cancelsTouchesInView } ?? false
        for recognizer in touch.gestureRecognizers ?? [] { recognizer.touchesMoved([touch], with: event) }
        let recognized = touch.gestureRecognizers?.contains { $0.hasRecognized && $0.cancelsTouchesInView } ?? false
        if recognized, !wasRecognized {
            touch.phase = .cancelled
            touch.view?.touchesCancelled([touch], with: event)
            touch.phase = .moved
        } else if !recognized {
            touch.view?.touchesMoved([touch], with: event)
        }
        UIKitScene.shared.setNeedsFrame()
    }

    /// The press ended at `point`; `cancelled` delivers a cancellation instead (the host's scroll
    /// view took the touch).
    func pointerUp(at point: CGPoint, time: Double, cancelled: Bool = false) {
        guard let touch = activeTouch, let event = activeEvent else { return }
        touch.previousWindowLocation = touch.windowLocation
        touch.windowLocation = point
        touch.timestamp = time
        event.timestamp = time
        let recognized = touch.gestureRecognizers?.contains { $0.hasRecognized && $0.cancelsTouchesInView } ?? false
        touch.phase = cancelled ? .cancelled : .ended
        if touch.phase == .cancelled {
            for recognizer in touch.gestureRecognizers ?? [] { recognizer.touchesCancelled([touch], with: event) }
            if !recognized { touch.view?.touchesCancelled([touch], with: event) }
        } else {
            for recognizer in touch.gestureRecognizers ?? [] { recognizer.touchesEnded([touch], with: event) }
            let nowRecognized = touch.gestureRecognizers?.contains { $0.cancelsTouchesInView && $0.hasRecognizedThisFrame } ?? false
            if !recognized {
                if nowRecognized { touch.view?.touchesCancelled([touch], with: event) } else { touch.view?.touchesEnded([touch], with: event) }
            }
        }
        for recognizer in touch.gestureRecognizers ?? [] { recognizer.hasRecognizedThisFrame = false }
        activeTouch = nil
        activeEvent = nil
        UIKitScene.shared.setNeedsFrame()
    }
}

extension UIView {
    /// Appends the semantics nodes of this view's subtree, in paint order: an accessibility
    /// element contributes itself and (unless it is a control) its descendants' elements.
    func collectSemantics(into nodes: inout [SemanticsNode]) {
        guard !isHidden, alpha > 0.01, !accessibilityElementsHidden else { return }
        if let hosted = _hostedSemantics() {
            // A hosting view's elements come in its coordinates: move them to the window's.
            let origin = convert(CGPoint.zero, to: nil)
            for var element in hosted {
                element.frame = element.frame.offsetBy(dx: origin.x, dy: origin.y)
                if var input = element.textInput {
                    input.textRect = input.textRect.offsetBy(dx: origin.x, dy: origin.y)
                    element.textInput = input
                }
                nodes.append(element)
            }
            return
        }
        if let node = semanticsNode() {
            nodes.append(node)
            if !(self is UIControl) { for subview in subviews { subview.collectSemantics(into: &nodes) } }
            return
        }
        for subview in subviews { subview.collectSemantics(into: &nodes) }
    }

    /// The view in this subtree reported under `identifier` in the semantics tree.
    func descendant(withSemanticsIdentifier identifier: Int) -> UIView? {
        if semanticsIdentifier == identifier { return self }
        for subview in subviews {
            if let found = subview.descendant(withSemanticsIdentifier: identifier) { return found }
        }
        return nil
    }

    /// The nearest scroll view at or above this view that scrolls, with the axes it moves on.
    var enclosingScrollAxes: (horizontal: Bool, vertical: Bool) {
        var view: UIView? = self
        while let v = view {
            if let scroll = v as? UIScrollView, scroll.isScrollEnabled {
                let content = scroll.contentSize
                return (content.width > scroll.bounds.width + 0.5, content.height > scroll.bounds.height + 0.5)
            }
            view = v.superview
        }
        return (false, false)
    }
}
