// UIScrollView (Docs/elements/UIKit/UIScrollView.md): content scrolled by the bounds origin,
// wheel scrolling from the host, finger panning through a pan recognizer, and momentum after a
// pan on the scene's frame clock (UIKit's deceleration rate: the velocity keeps 0.998 of itself
// per millisecond).

/// The methods a scroll view's delegate implements.
@MainActor
public protocol UIScrollViewDelegate: AnyObject {
    func scrollViewDidScroll(_ scrollView: UIScrollView)
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView)
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool)
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView)
    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView)
}

extension UIScrollViewDelegate {
    public func scrollViewDidScroll(_ scrollView: UIScrollView) {}
    public func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {}
    public func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {}
    public func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {}
    public func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {}
}

/// A view that allows the scrolling and zooming of its contained views.
@MainActor
open class UIScrollView: UIView {
    public enum IndicatorStyle: Int, Sendable { case `default` = 0, black, white }
    public enum ContentInsetAdjustmentBehavior: Int, Sendable { case automatic = 0, scrollableAxes, never, always }
    public enum KeyboardDismissMode: Int, Sendable { case none = 0, onDrag, interactive }

    open var contentSize = CGSize.zero { didSet { clampOffset(); setNeedsDisplay() } }
    open var contentInset = UIEdgeInsets.zero { didSet { clampOffset() } }
    open var adjustedContentInset: UIEdgeInsets { contentInset }
    open var contentInsetAdjustmentBehavior: ContentInsetAdjustmentBehavior = .automatic
    open var isScrollEnabled = true
    open var isPagingEnabled = false
    open var bounces = true
    open var alwaysBounceVertical = false
    open var alwaysBounceHorizontal = false
    open var showsVerticalScrollIndicator = true
    open var showsHorizontalScrollIndicator = true
    open var indicatorStyle: IndicatorStyle = .default
    open var isDirectionalLockEnabled = false
    open var scrollsToTop = true
    open var keyboardDismissMode: KeyboardDismissMode = .none
    open var delaysContentTouches = true
    open var canCancelContentTouches = true
    open var minimumZoomScale: CGFloat = 1
    open var maximumZoomScale: CGFloat = 1
    open var zoomScale: CGFloat = 1
    open weak var delegate: (any UIScrollViewDelegate)?
    public private(set) var isDragging = false
    open var isDecelerating: Bool { momentum != nil }
    /// The velocity's factor per millisecond while decelerating.
    open var decelerationRate: DecelerationRate = .normal

    public struct DecelerationRate: Hashable, Sendable, RawRepresentable {
        public let rawValue: CGFloat
        public init(rawValue: CGFloat) { self.rawValue = rawValue }
        public static let normal = DecelerationRate(rawValue: 0.998)
        public static let fast = DecelerationRate(rawValue: 0.99)
    }

    /// The velocity (points per second) carrying the content after a pan.
    private var momentum: CGPoint?

    /// The pan that scrolls the content.
    public private(set) var panGestureRecognizer: UIPanGestureRecognizer!
    private var panStartOffset = CGPoint.zero

    open var contentOffset: CGPoint {
        get { bounds.origin }
        set {
            guard newValue != bounds.origin else { return }
            bounds.origin = newValue
            delegate?.scrollViewDidScroll(self)
            setNeedsDisplay()
        }
    }

    public override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        let pan = UIPanGestureRecognizer()
        pan.addTarget { [weak self] recognizer in self?.handlePan(recognizer as! UIPanGestureRecognizer) }
        panGestureRecognizer = pan
        addGestureRecognizer(pan)
    }

    override open var clipsHitTesting: Bool { true }

    open func setContentOffset(_ offset: CGPoint, animated: Bool) {
        contentOffset = clamped(offset)
        if animated { delegate?.scrollViewDidEndScrollingAnimation(self) }
    }

    open func scrollRectToVisible(_ rect: CGRect, animated: Bool) {
        var offset = contentOffset
        if rect.minX < offset.x { offset.x = rect.minX } else if rect.maxX > offset.x + bounds.width { offset.x = rect.maxX - bounds.width }
        if rect.minY < offset.y { offset.y = rect.minY } else if rect.maxY > offset.y + bounds.height { offset.y = rect.maxY - bounds.height }
        setContentOffset(offset, animated: animated)
    }

    open func flashScrollIndicators() {}

    /// The offset within the scrollable range.
    func clamped(_ offset: CGPoint) -> CGPoint {
        let maxX = max(-contentInset.left, contentSize.width + contentInset.right - bounds.width)
        let maxY = max(-contentInset.top, contentSize.height + contentInset.bottom - bounds.height)
        return CGPoint(x: min(max(offset.x, -contentInset.left), maxX), y: min(max(offset.y, -contentInset.top), maxY))
    }

    private func clampOffset() {
        let target = clamped(contentOffset)
        if target != contentOffset { contentOffset = target }
    }

    /// Scrolls by a wheel delta; false when nothing moved (an enclosing scroll view takes it).
    func scroll(by delta: CGSize) -> Bool {
        let target = clamped(CGPoint(x: contentOffset.x + delta.width, y: contentOffset.y + delta.height))
        guard target != contentOffset else { return false }
        contentOffset = target
        return true
    }

    private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard isScrollEnabled else { return }
        switch pan.state {
        case .began:
            panStartOffset = contentOffset
            isDragging = true
            delegate?.scrollViewWillBeginDragging(self)
        case .changed:
            let translation = pan.translation(in: self)
            contentOffset = clamped(CGPoint(x: panStartOffset.x - translation.x, y: panStartOffset.y - translation.y))
        case .ended, .cancelled, .failed:
            isDragging = false
            let velocity = pan.velocity(in: self)
            let carries = pan.state == .ended && (abs(velocity.x) > 50 || abs(velocity.y) > 50)
            delegate?.scrollViewDidEndDragging(self, willDecelerate: carries)
            if carries {
                momentum = CGPoint(x: -velocity.x, y: -velocity.y)
                UIKitScene.shared.beginDecelerating(self)
            }
        default: break
        }
    }

    /// Stops the momentum where the content is (a finger landing on the content).
    func stopMomentum() {
        guard momentum != nil else { return }
        momentum = nil
        delegate?.scrollViewDidEndDecelerating(self)
    }

    /// Carries the content by `elapsed` seconds of momentum; false when it has stopped.
    func advanceMomentum(elapsed: Double) -> Bool {
        guard var velocity = momentum else { return false }
        let target = clamped(CGPoint(x: contentOffset.x + velocity.x * elapsed, y: contentOffset.y + velocity.y * elapsed))
        let hitEdge = target.x != contentOffset.x + velocity.x * elapsed || target.y != contentOffset.y + velocity.y * elapsed
        if target != contentOffset { contentOffset = target }
        let factor = _pow(Double(decelerationRate.rawValue), elapsed * 1000)
        velocity = CGPoint(x: velocity.x * factor, y: velocity.y * factor)
        if hitEdge || (abs(velocity.x) < 4 && abs(velocity.y) < 4) {
            momentum = nil
            delegate?.scrollViewDidEndDecelerating(self)
            return false
        }
        momentum = velocity
        return true
    }

    override open func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        stopMomentum()
        super.touchesBegan(touches, with: event)
    }
}

extension UIKitScene {
    /// Registers a scroll view whose momentum needs frames.
    func beginDecelerating(_ scrollView: UIScrollView) {
        if !decelerating.contains(where: { $0 === scrollView }) { decelerating.append(scrollView) }
        setNeedsFrame()
    }

    /// Advances every decelerating scroll view; true while any still moves.
    func advanceScrolling(elapsed: Double) -> Bool {
        guard !decelerating.isEmpty else { return false }
        decelerating = decelerating.filter { $0.advanceMomentum(elapsed: elapsed) }
        return !decelerating.isEmpty
    }
}
