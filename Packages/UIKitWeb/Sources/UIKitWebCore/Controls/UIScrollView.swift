// UIScrollView (Docs/elements/UIKit/UIScrollView.md): content scrolled by the bounds origin,
// wheel scrolling from the host and finger panning through a pan recognizer. Momentum and
// bounce arrive with the animation clock (Phase 3).

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
    open var isDecelerating: Bool { false }

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
            delegate?.scrollViewDidEndDragging(self, willDecelerate: false)
        default: break
        }
    }
}
