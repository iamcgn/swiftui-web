// UIScrollView (Docs/elements/UIKit/UIScrollView.md): content scrolled by the bounds origin,
// wheel scrolling from the host, finger panning through a pan recognizer, momentum after a pan
// on the scene's frame clock (UIKit's deceleration rate: the velocity keeps 0.998 of itself per
// millisecond), rubber banding past the edges, paging, and the indicators UIKit shows while
// the content moves (3 pt bars 3 in from the edges and the ends, black at 35 %, uikit/textview).

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
    /// The content inset plus the safe area the scroll view lies under, per
    /// `contentInsetAdjustmentBehavior`: `.never` adds nothing, `.always` the whole safe area,
    /// `.automatic` and `.scrollableAxes` the safe area along the axes the content scrolls on
    /// (ios/representable/safearea-scroll-ignored: a scroll view under a bar starts its content
    /// below the bar).
    open var adjustedContentInset: UIEdgeInsets {
        var insets = contentInset
        let safe = safeAreaInsets
        switch contentInsetAdjustmentBehavior {
        case .never: break
        case .always:
            insets.top += safe.top; insets.bottom += safe.bottom; insets.left += safe.left; insets.right += safe.right
        case .automatic, .scrollableAxes:
            if alwaysBounceVertical || contentSize.height + contentInset.top + contentInset.bottom > bounds.height + 0.5 {
                insets.top += safe.top; insets.bottom += safe.bottom
            }
            if alwaysBounceHorizontal || contentSize.width + contentInset.left + contentInset.right > bounds.width + 0.5 {
                insets.left += safe.left; insets.right += safe.right
            }
        }
        return insets
    }
    open var contentInsetAdjustmentBehavior: ContentInsetAdjustmentBehavior = .automatic { didSet { adjustedContentInsetDidChange() } }
    /// The adjusted inset the offset was last clamped against: content resting at the top stays
    /// at the top when the inset changes (UIKit moves the offset with the adjustment).
    private var appliedAdjustedInset = UIEdgeInsets.zero

    /// The safe area or the behaviour changed: the offset follows the new adjusted inset.
    open func adjustedContentInsetDidChange() {
        let adjusted = adjustedContentInset
        guard adjusted != appliedAdjustedInset else { return }
        var offset = contentOffset
        if offset.y == -appliedAdjustedInset.top { offset.y = -adjusted.top }
        if offset.x == -appliedAdjustedInset.left { offset.x = -adjusted.left }
        appliedAdjustedInset = adjusted
        contentOffset = clamped(offset)
        setNeedsLayout()
    }

    override open func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        adjustedContentInsetDidChange()
    }
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

    /// The indicators: shown while the finger moves the content or momentum carries it, faded
    /// out 0.3 s after it stops (hidden at rest, as UIKit hides them).
    let verticalIndicator = ScrollIndicatorView()
    let horizontalIndicator = ScrollIndicatorView()
    static let indicatorThickness: CGFloat = 3
    static let indicatorInset: CGFloat = 3
    static let indicatorMinimumLength: CGFloat = 36
    private var indicatorFade: UIKitScene.Timer?
    /// The offset past an edge the finger has dragged to (unclamped), while bouncing.
    private var overscroll = CGPoint.zero

    /// The pan that scrolls the content.
    public private(set) var panGestureRecognizer: UIPanGestureRecognizer!
    private var panStartOffset = CGPoint.zero

    open var contentOffset: CGPoint {
        get { bounds.origin }
        set {
            guard newValue != bounds.origin else { return }
            bounds.origin = newValue
            layoutIndicators()
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
        for indicator in [verticalIndicator, horizontalIndicator] {
            indicator.alpha = 0
            indicator.isUserInteractionEnabled = false
            addSubview(indicator)
        }
    }

    // MARK: Indicators

    override open func layoutSubviews() {
        super.layoutSubviews()
        adjustedContentInsetDidChange()
        layoutIndicators()
    }

    /// The bars' places for the offset: a track the length of the view less 3 at each end, the
    /// bar as long as the visible fraction of the content (at least 36), 3 from the far edges.
    func layoutIndicators() {
        let visible = bounds.size
        let inset = Self.indicatorInset
        let thickness = Self.indicatorThickness
        let content = contentSize
        let vertical = content.height > visible.height + 0.5 && showsVerticalScrollIndicator
        verticalIndicator.isHidden = !vertical
        if vertical {
            let track = visible.height - 2 * inset - (content.width > visible.width ? thickness + inset : 0)
            let length = max(Self.indicatorMinimumLength, (track * visible.height / content.height).rounded())
            let range = max(0, content.height - visible.height)
            let fraction = range > 0 ? min(1, max(0, contentOffset.y / range)) : 0
            verticalIndicator.frame = CGRect(x: contentOffset.x + visible.width - inset - thickness, y: contentOffset.y + inset + ((track - length) * fraction).rounded(),
                                             width: thickness, height: length)
        }
        let horizontal = content.width > visible.width + 0.5 && showsHorizontalScrollIndicator
        horizontalIndicator.isHidden = !horizontal
        if horizontal {
            let track = visible.width - 2 * inset - (vertical ? thickness + inset : 0)
            let length = max(Self.indicatorMinimumLength, (track * visible.width / content.width).rounded())
            let range = max(0, content.width - visible.width)
            let fraction = range > 0 ? min(1, max(0, contentOffset.x / range)) : 0
            horizontalIndicator.frame = CGRect(x: contentOffset.x + inset + ((track - length) * fraction).rounded(), y: contentOffset.y + visible.height - inset - thickness,
                                               width: length, height: thickness)
        }
        bringSubviewToFront(verticalIndicator)
        bringSubviewToFront(horizontalIndicator)
    }

    /// Shows the indicators (cancelling a pending fade); `fadeIndicators` hides them 0.3 s later.
    func showIndicators() {
        indicatorFade?.cancel()
        indicatorFade = nil
        for indicator in [verticalIndicator, horizontalIndicator] where indicator.alpha != 1 {
            UIView.performWithoutAnimation { indicator.alpha = 1 }
        }
        layoutIndicators()
    }

    func fadeIndicators() {
        guard indicatorFade == nil else { return }
        indicatorFade = UIKitScene.shared.schedule(after: 0.3) { [weak self] in
            guard let self else { return }
            self.indicatorFade = nil
            UIView.animate(withDuration: 0.25) {
                self.verticalIndicator.alpha = 0
                self.horizontalIndicator.alpha = 0
            }
        }
    }

    /// Flashes the indicators: shown, then faded.
    open func flashScrollIndicators() {
        showIndicators()
        fadeIndicators()
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

    /// The offset within the scrollable range.
    func clamped(_ offset: CGPoint) -> CGPoint {
        let inset = adjustedContentInset
        let maxX = max(-inset.left, contentSize.width + inset.right - bounds.width)
        let maxY = max(-inset.top, contentSize.height + inset.bottom - bounds.height)
        return CGPoint(x: min(max(offset.x, -inset.left), maxX), y: min(max(offset.y, -inset.top), maxY))
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

    /// The distance the content shows for a drag `over` past an edge on an axis `dimension`
    /// long: UIKit's rubber band, `(1 - 1 / (over * 0.55 / dimension + 1)) * dimension`.
    static func rubberBanded(_ over: CGFloat, dimension: CGFloat) -> CGFloat {
        guard dimension > 0, over != 0 else { return 0 }
        let magnitude = (1 - 1 / (abs(over) * 0.55 / dimension + 1)) * dimension
        return over < 0 ? -magnitude : magnitude
    }

    /// The offset a drag to `raw` shows: clamped, plus the rubber band past the edges when bouncing.
    private func bounced(_ raw: CGPoint) -> CGPoint {
        let inside = clamped(raw)
        guard bounces else { return inside }
        let canBounceVertically = alwaysBounceVertical || contentSize.height + contentInset.top + contentInset.bottom > bounds.height
        let canBounceHorizontally = alwaysBounceHorizontal || contentSize.width + contentInset.left + contentInset.right > bounds.width
        let overX = canBounceHorizontally ? raw.x - inside.x : 0
        let overY = canBounceVertically ? raw.y - inside.y : 0
        return CGPoint(x: inside.x + Self.rubberBanded(overX, dimension: bounds.width), y: inside.y + Self.rubberBanded(overY, dimension: bounds.height))
    }

    /// Whether a pan mostly along an axis this view cannot scroll is left to an enclosing
    /// scroll view (a carousel inside a list: horizontal drags scroll the carousel, vertical
    /// ones the list).
    private var ignoringPan = false

    private func handlePan(_ pan: UIPanGestureRecognizer) {
        guard isScrollEnabled else { return }
        if pan.state == .began {
            let translation = pan.translation(in: self)
            let scrollsHorizontally = alwaysBounceHorizontal || contentSize.width + contentInset.left + contentInset.right > bounds.width + 0.5
            let scrollsVertically = alwaysBounceVertical || contentSize.height + contentInset.top + contentInset.bottom > bounds.height + 0.5
            let mostlyVertical = abs(translation.y) > abs(translation.x)
            ignoringPan = mostlyVertical ? (!scrollsVertically && scrollsHorizontally) : (!scrollsHorizontally && scrollsVertically)
        }
        guard !ignoringPan else { return }
        switch pan.state {
        case .began:
            panStartOffset = contentOffset
            isDragging = true
            showIndicators()
            delegate?.scrollViewWillBeginDragging(self)
        case .changed:
            let translation = pan.translation(in: self)
            let raw = CGPoint(x: panStartOffset.x - translation.x, y: panStartOffset.y - translation.y)
            contentOffset = bounced(raw)
            showIndicators()
        case .ended, .cancelled, .failed:
            isDragging = false
            let velocity = pan.velocity(in: self)
            let resting = clamped(contentOffset)
            if resting != contentOffset {
                // Past an edge: spring back, no momentum.
                delegate?.scrollViewDidEndDragging(self, willDecelerate: false)
                settle(to: resting, duration: 0.4)
                return
            }
            if isPagingEnabled {
                // Snap to the page the drag and its velocity point at.
                let width = bounds.width, height = bounds.height
                var target = contentOffset
                if width > 0 { target.x = ((contentOffset.x - velocity.x * 0.1) / width).rounded() * width }
                if height > 0 { target.y = ((contentOffset.y - velocity.y * 0.1) / height).rounded() * height }
                delegate?.scrollViewDidEndDragging(self, willDecelerate: false)
                settle(to: clamped(target), duration: 0.3)
                return
            }
            let carries = pan.state == .ended && (abs(velocity.x) > 50 || abs(velocity.y) > 50)
            delegate?.scrollViewDidEndDragging(self, willDecelerate: carries)
            if carries {
                momentum = CGPoint(x: -velocity.x, y: -velocity.y)
                UIKitScene.shared.beginDecelerating(self)
            } else {
                fadeIndicators()
            }
        default: break
        }
    }

    /// Animates the offset to `target` (the spring back from an edge, a page snap) and fades
    /// the indicators when it lands; the delegate hears `scrollViewDidEndDecelerating`.
    private func settle(to target: CGPoint, duration: Double) {
        UIView.animate(withDuration: duration, delay: 0, options: .curveEaseOut, animations: {
            self.contentOffset = target
        }, completion: { [weak self] _ in
            guard let self else { return }
            self.layoutIndicators()
            self.delegate?.scrollViewDidEndDecelerating(self)
            self.fadeIndicators()
        })
    }

    /// Stops the momentum where the content is (a finger landing on the content).
    func stopMomentum() {
        guard momentum != nil else { return }
        momentum = nil
        delegate?.scrollViewDidEndDecelerating(self)
        fadeIndicators()
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
            fadeIndicators()
            return false
        }
        momentum = velocity
        showIndicators()
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

/// A scroll indicator: a 1.5 pt-cornered bar, black at 35 % (white at 50 % for the white style).
@MainActor
final class ScrollIndicatorView: UIView {
    var style: UIScrollView.IndicatorStyle = .default

    override func drawContent(into list: inout DisplayList, context: PaintContext, style appearance: UIUserInterfaceStyle) {
        let rect = context.absoluteRect(CGRect(origin: .zero, size: bounds.size))
        let color: RGBA
        switch style {
        case .white: color = RGBA(r: 255, g: 255, b: 255, a: 0.5)
        case .black: color = RGBA(r: 0, g: 0, b: 0, a: 0.35)
        case .default: color = appearance == .dark ? RGBA(r: 255, g: 255, b: 255, a: 0.35) : RGBA(r: 0, g: 0, b: 0, a: 0.35)
        }
        list.append(.fillRRect(rect, cornerRadius: 1.5, color))
    }
}
