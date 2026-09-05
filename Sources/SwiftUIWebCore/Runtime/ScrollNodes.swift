// ScrollView: layout (flexible along its axes, content-sized across them), clipping, content
// offset, programmatic scrolling and user scrolling (wheel, pan, momentum). Measured behaviours
// are in Docs/elements/ScrollView.md; every constant is in PlatformMetrics.

/// A node `ScrollViewProxy.scrollTo` can address.
@MainActor
package protocol _ScrollTarget: AnyObject {
    /// Scrolls so the descendant identified by `id` is visible; false when there is none.
    func scrollTo(id: AnyHashable, anchor: UnitPoint?) -> Bool
}

/// A node that carries a `View.id(_:)` identifier.
@MainActor
package protocol _IdentifiedNode: AnyObject {
    var identifier: AnyHashable { get }
}

/// A node with a user-scrollable viewport.
@MainActor
package protocol _Scrollable: AnyObject {
    var isMounted: Bool { get }
    var contentOffset: CGPoint { get }
    /// Applies `delta` (positive moves the content up and left) and returns the part it could not
    /// consume, so enclosing scroll views can take over at the edges.
    func scroll(by delta: CGSize) -> CGSize
    /// Makes the indicators visible and restarts their fade.
    func showIndicators()
    /// Starts decelerating from `velocity` (points per second).
    func beginMomentum(velocity: CGSize)
    /// Whether momentum is still carrying the content.
    var isDecelerating: Bool { get }
    /// Stops momentum where the content is (a finger landing on a decelerating scroll view).
    func stopMomentum()
    /// Advances momentum and indicator fading by `elapsed` seconds; true while still animating.
    func advance(elapsed: Double) -> Bool
    /// Whether a frame that only scrolled can move the content instead of laying out (nothing
    /// inside reads its own geometry, no programmatic target pending).
    var canMoveContentOnly: Bool { get }
    /// Moves the content to the current offset without laying it out again.
    func moveContent()
}

extension Axis.Set {
    package init(_ axis: Axis) { self.init(rawValue: 1 << axis.rawValue) }
}

/// Node for `ScrollView`. The builder content is wrapped in an implicit centre-aligned `VStack`
/// (fixture `scroll/children`), which is the single content node placed at `-contentOffset`.
@MainActor
package final class ScrollNode<Content: View>: LayoutNode<ScrollView<Content>>, _ScrollTarget, _Scrollable {
    override package var clipsHitTesting: Bool { true }
    package private(set) var child: TypedNode<VStack<Content>>!

    /// The current offset of the content within the viewport, clamped to the content at layout.
    package private(set) var contentOffset: CGPoint = .zero

    /// The content's size for the most recent layout.
    package private(set) var contentSize: CGSize = .zero

    private var appliedDefaultAnchor = false
    private var pendingTarget: (id: AnyHashable, anchor: UnitPoint?)?

    // Animation state, advanced by the host through `Runtime.advanceScrollAnimations`.
    package private(set) var indicatorOpacity: Double = 0
    private var indicatorHold: Double = 0
    package private(set) var velocity: CGSize = .zero

    package init(_ context: _NodeContext<ScrollView<Content>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        child = VStack<Content>._makeNode(_NodeContext(view: Self.wrapped(context.view), parent: self, environment: context.environment))
    }

    private static func wrapped(_ view: ScrollView<Content>) -> VStack<Content> {
        VStack { view.content }
    }

    override package func update(view: ScrollView<Content>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        child.update(view: Self.wrapped(view), environment: environment, force: force)
    }

    package var axes: Axis.Set { view.axes }
    package var isScrollEnabled: Bool { environment.isScrollEnabled }
    override package var extendsIntoSafeArea: Bool { true }

    /// Safe-area insets from an enclosing `safeAreaInset`/`safeAreaPadding`: the scroll view
    /// keeps its frame and insets the content (read at layout, kept for scrolling).
    package private(set) var contentInsets = EdgeInsets()

    /// Whether an indicator may show along each axis.
    package var showsIndicators: (horizontal: Bool, vertical: Bool) {
        guard view.showsIndicators else { return (false, false) }
        return (axes.contains(.horizontal) && environment.horizontalScrollIndicatorVisibility.showsIndicators,
                axes.contains(.vertical) && environment.verticalScrollIndicatorVisibility.showsIndicators)
    }

    // MARK: Layout

    /// Along a scroll axis the content is proposed nothing (its ideal length); across it, the
    /// proposal passes through.
    private func contentProposal(_ proposal: ProposedViewSize) -> ProposedViewSize {
        ProposedViewSize(width: axes.contains(.horizontal) ? nil : proposal.width,
                         height: axes.contains(.vertical) ? nil : proposal.height)
    }

    /// Along a scroll axis the scroll view takes the proposal (its content's length when there is
    /// none); across it, exactly the content's size (fixtures `scroll/narrow-content`,
    /// `scroll/wide-content`).
    override package func computeSizeThatFits(_ proposal: ProposedViewSize) -> CGSize {
        let insets = inheritedSafeAreaInsets
        var size = child.sizeThatFits(contentProposal(proposal, insets: insets))
        size.width += insets.leading + insets.trailing
        size.height += insets.top + insets.bottom
        for axis in Axis.allCases where axes.contains(Axis.Set(axis)) {
            if let length = proposal[axis] { size[axis] = length }
        }
        return size
    }

    /// The content proposal with the safe-area insets taken off across the scroll axes.
    private func contentProposal(_ proposal: ProposedViewSize, insets: EdgeInsets) -> ProposedViewSize {
        var result = contentProposal(proposal)
        if let width = result.width { result.width = max(0, width - insets.leading - insets.trailing) }
        if let height = result.height { result.height = max(0, height - insets.top - insets.bottom) }
        return result
    }

    /// The largest offset along each scroll axis for the current content and viewport.
    package var maximumOffset: CGPoint {
        let insets = contentInsets
        return CGPoint(x: axes.contains(.horizontal) ? max(0, contentSize.width + insets.leading + insets.trailing - frame.width) : 0,
                       y: axes.contains(.vertical) ? max(0, contentSize.height + insets.top + insets.bottom - frame.height) : 0)
    }

    private func clamped(_ offset: CGPoint) -> CGPoint {
        let maximum = maximumOffset
        return CGPoint(x: min(max(0, offset.x), maximum.x), y: min(max(0, offset.y), maximum.y))
    }

    override package func layoutContents(proposal: ProposedViewSize) {
        contentInsets = inheritedSafeAreaInsets
        let contentProposal = contentProposal(proposal, insets: contentInsets)
        contentSize = child.sizeThatFits(contentProposal)
        if !appliedDefaultAnchor {
            appliedDefaultAnchor = true
            if let anchor = environment.defaultScrollAnchor {
                let maximum = maximumOffset
                contentOffset = CGPoint(x: maximum.x * anchor.x, y: maximum.y * anchor.y)
            }
        }
        contentOffset = clamped(contentOffset)
        placeContent(proposal: contentProposal)
        // A programmatic target needs the content's fresh frames, so it is resolved after the
        // first placement and the content placed again when the offset moves.
        if let target = pendingTarget {
            pendingTarget = nil
            if let rect = targetRect(id: target.id) {
                let offset = offset(scrollingTo: rect, anchor: target.anchor)
                if offset != contentOffset {
                    contentOffset = offset
                    placeContent(proposal: contentProposal)
                }
            }
        }
    }

    private func placeContent(proposal: ProposedViewSize) {
        child.place(at: contentOrigin, anchor: .topLeading, proposal: proposal, by: self)
    }

    /// Where the content's top-left sits: the safe-area inset, scrolled by the offset.
    private var contentOrigin: CGPoint {
        CGPoint(x: contentInsets.leading - contentOffset.x, y: contentInsets.top - contentOffset.y)
    }

    private var geometryCheckGeneration: UInt64 = .max
    private var contentReadsGeometry = false

    package var canMoveContentOnly: Bool {
        guard pendingTarget == nil, hasBeenPlaced else { return false }
        if geometryCheckGeneration != runtime.layoutGeneration {
            geometryCheckGeneration = runtime.layoutGeneration
            contentReadsGeometry = !child.collectNodes(where: { $0.readsGeometry }).isEmpty
        }
        return !contentReadsGeometry
    }

    package func moveContent() {
        child.moveFrame(toOrigin: contentOrigin)
    }

    /// The frame of the identified descendant in content coordinates, or `nil`.
    private func targetRect(id: AnyHashable) -> CGRect? {
        guard let node = identifiedNode(id) else { return nil }
        let frames = node.layoutChildren.map(\.frameInRoot)
        guard var union = frames.first else { return nil }
        for frame in frames.dropFirst() { union = union.union(frame) }
        let origin = child.frameInRoot.origin
        return CGRect(x: union.minX - origin.x, y: union.minY - origin.y, width: union.width, height: union.height)
    }

    private func identifiedNode(_ id: AnyHashable) -> ViewNode? {
        child.descendants(where: { ($0 as? _IdentifiedNode)?.identifier == id }).first
    }

    /// The offset that shows `rect` (content coordinates): aligned on `anchor` in both the target
    /// and the viewport, or with the smallest change that brings it fully into view
    /// (fixture `scroll/scroll-to`).
    private func offset(scrollingTo rect: CGRect, anchor: UnitPoint?) -> CGPoint {
        var offset = contentOffset
        for axis in Axis.allCases where axes.contains(Axis.Set(axis)) {
            let viewport = frame.size[axis]
            let start = rect.origin[axis], length = rect.size[axis]
            if let anchor {
                let fraction = axis == .horizontal ? anchor.x : anchor.y
                offset[axis] = start + fraction * length - fraction * viewport
            } else if start < offset[axis] {
                offset[axis] = start
            } else if start + length > offset[axis] + viewport {
                offset[axis] = start + length - viewport
            }
        }
        return clamped(offset)
    }

    // MARK: Programmatic and user scrolling

    package func scrollTo(id: AnyHashable, anchor: UnitPoint?) -> Bool {
        guard identifiedNode(id) != nil else { return false }
        pendingTarget = (id, anchor)
        runtime.requestLayout(invalidatingSizes: false)
        return true
    }

    package func scroll(by delta: CGSize) -> CGSize {
        guard isScrollEnabled else { return delta }
        var remaining = delta
        var offset = contentOffset
        let maximum = maximumOffset
        for axis in Axis.allCases where axes.contains(Axis.Set(axis)) {
            let target = offset[axis] + delta[axis]
            let clampedValue = min(max(0, target), maximum[axis])
            remaining[axis] = target - clampedValue
            offset[axis] = clampedValue
        }
        if offset != contentOffset {
            contentOffset = offset
            runtime.noteScrolled(self)
            runtime.requestLayout(invalidatingSizes: false)
        }
        return remaining
    }

    package func showIndicators() {
        let shows = showsIndicators
        guard shows.horizontal || shows.vertical else { return }
        indicatorOpacity = 1
        indicatorHold = PlatformMetrics.scrollerHoldSeconds
        runtime.animate(self)
    }

    package func beginMomentum(velocity: CGSize) {
        guard velocity != .zero else { return }
        self.velocity = velocity
        runtime.animate(self)
    }

    package var isDecelerating: Bool { velocity != .zero }

    package func stopMomentum() {
        velocity = .zero
        indicatorHold = PlatformMetrics.scrollerHoldSeconds
    }

    package func advance(elapsed: Double) -> Bool {
        var animating = false
        if velocity != .zero {
            let step = CGSize(width: velocity.width * elapsed, height: velocity.height * elapsed)
            let remaining = scroll(by: step)
            // Momentum stops at an edge (no rubber band, see the element doc) and below a floor.
            let decay = _decay(PlatformMetrics.scrollDecelerationRate, milliseconds: elapsed * 1000)
            velocity = CGSize(width: remaining.width == 0 ? velocity.width * decay : 0,
                              height: remaining.height == 0 ? velocity.height * decay : 0)
            if abs(velocity.width) < PlatformMetrics.scrollVelocityFloor { velocity.width = 0 }
            if abs(velocity.height) < PlatformMetrics.scrollVelocityFloor { velocity.height = 0 }
            if velocity != .zero { animating = true }
            indicatorHold = PlatformMetrics.scrollerHoldSeconds
        }
        if indicatorOpacity > 0 {
            if indicatorHold > 0 {
                indicatorHold = max(0, indicatorHold - elapsed)
            } else {
                indicatorOpacity = max(0, indicatorOpacity - elapsed / PlatformMetrics.scrollerFadeSeconds)
                runtime.requestLayout(invalidatingSizes: false)
            }
            if indicatorOpacity > 0 { animating = true }
        }
        return animating
    }

    // MARK: Painting and hit testing

    override package var paintedChildren: [ViewNode] { [child] }

    override package func paint(into list: inout DisplayList, context: PaintContext) {
        let clips = !environment.isScrollClipDisabled
        var context = context
        if clips {
            let bounds = absoluteBounds(context)
            list.append(.save)
            list.append(.clipRect(bounds))
            // Subtrees entirely outside the viewport (by more than the margin) are not painted.
            context.visibleRect = bounds.insetBy(dx: -PlatformMetrics.scrollCullMargin, dy: -PlatformMetrics.scrollCullMargin)
        }
        paintChildren(into: &list, context: context)
        if clips { list.append(.restore) }
        paintIndicators(into: &list, context: context)
    }

    /// Overlay scrollers: a knob on the trailing edge of each scrollable axis, shown only while
    /// scrolling (approximate; the goldens never show one at rest).
    private func paintIndicators(into list: inout DisplayList, context: PaintContext) {
        guard indicatorOpacity > 0 else { return }
        let shows = showsIndicators
        let thickness = PlatformMetrics.scrollerThickness, inset = PlatformMetrics.scrollerInset
        for axis in Axis.allCases where axis == .horizontal ? shows.horizontal : shows.vertical {
            let viewport = frame.size[axis], content = contentSize[axis]
            guard content > viewport, viewport > 2 * inset else { continue }
            let track = viewport - 2 * inset
            let knob = min(track, max(PlatformMetrics.scrollerMinimumKnobLength, track * viewport / content))
            let position = inset + (track - knob) * (contentOffset[axis] / (content - viewport))
            let rect = axis == .vertical
                ? CGRect(x: frame.width - inset - thickness, y: position, width: thickness, height: knob)
                : CGRect(x: position, y: frame.height - inset - thickness, width: knob, height: thickness)
            list.append(.fillRRect(context.absoluteRect(rect), cornerRadius: thickness / 2,
                                   PlatformMetrics.scrollerKnob.multiplyingAlpha(by: indicatorOpacity)))
        }
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var nodeDescription: String { "ScrollView" }
}

/// Node for `ScrollViewReader`: evaluates the content closure with a proxy to itself, tracking
/// the observable state the closure reads, and is transparent to layout.
@MainActor
package final class ScrollViewReaderNode<Content: View>: TypedNode<ScrollViewReader<Content>> {
    package private(set) var child: TypedNode<Content>!

    package init(_ context: _NodeContext<ScrollViewReader<Content>>) {
        super.init(view: context.view, parent: context.parent, runtime: context.runtime, environment: context.environment)
        evaluate()
    }

    override package func update(view: ScrollViewReader<Content>, environment: EnvironmentValues, force: Bool) {
        self.view = view
        self.environment = environment
        clearNeedsUpdate()
        evaluate()
    }

    private func evaluate() {
        let content = _trackingObservation(for: self) { view.content(ScrollViewProxy(reader: self)) }
        if let child {
            child.update(view: content, environment: environment)
        } else {
            child = Content._makeNode(_NodeContext(view: content, parent: self, environment: environment))
        }
    }

    override package var structuralChildren: [ViewNode] { [child] }
    override package var layoutChildren: [ViewNode] { child.layoutChildren }
    override package var nodeDescription: String { "ScrollViewReader" }
}

extension IDNode: _IdentifiedNode {
    package var identifier: AnyHashable { AnyHashable(view.id) }
}

// MARK: - Runtime: user scrolling

/// The kind of device behind a pointer event. Touch pointers pan scroll views; mice press.
public enum PointerType: Sendable {
    case mouse, touch, pen
}

/// A touch pan in progress: the scroll views under the finger, innermost first.
package struct PanState {
    package let nodes: [ViewNode & _Scrollable]
    package let start: CGPoint
    package var last: CGPoint
    package var lastTime: Double
    package var velocity: CGSize = .zero
    package var active = false
}

extension Runtime {
    /// Scroll views on the hit path under `point` (window coordinates), innermost first.
    package func scrollableNodes(at point: CGPoint) -> [ViewNode & _Scrollable] {
        var result: [ViewNode & _Scrollable] = []
        func visit(_ node: ViewNode, _ local: CGPoint) {
            if let scrollable = node as? (ViewNode & _Scrollable) { result.append(scrollable) }
            for child in node.paintedChildren.reversed() {
                let childPoint = CGPoint(x: local.x - child.frame.minX, y: local.y - child.frame.minY)
                guard child.contains(childPoint) else { continue }
                visit(child, childPoint)
                return
            }
        }
        for node in root.layoutChildren.reversed() {
            let local = CGPoint(x: point.x - node.frame.minX, y: point.y - node.frame.minY)
            guard node.contains(local) else { continue }
            visit(node, local)
            break
        }
        return result.reversed()
    }

    /// Applies a scroll delta (points; positive moves the content up and left) to the scroll
    /// views under `point`, innermost first, each taking what it can (scroll chaining).
    @discardableResult
    package func scroll(by delta: CGSize, at point: CGPoint) -> CGSize {
        scroll(by: delta, through: scrollableNodes(at: point))
    }

    private func scroll(by delta: CGSize, through nodes: [ViewNode & _Scrollable]) -> CGSize {
        var remaining = delta
        for node in nodes {
            let before = node.contentOffset
            remaining = node.scroll(by: remaining)
            if node.contentOffset != before { node.showIndicators() }
            if remaining == .zero { break }
        }
        return remaining
    }

    /// A wheel event at `point`; deltas are in points (the host has already normalised line and
    /// page modes). Desktop wheel deltas carry the OS's own momentum, so none is added.
    public func scrollWheel(by delta: CGSize, at point: CGPoint) {
        scroll(by: delta, at: point)
    }

    /// Registers a scroll view whose momentum or indicators need frames.
    package func animate(_ node: ViewNode & _Scrollable) {
        if !animatingScrollNodes.contains(where: { $0 === node }) { animatingScrollNodes.append(node) }
        requestLayout(invalidatingSizes: false)
    }

    /// Advances scroll momentum and indicator fades by `elapsed` seconds. Hosts call this once
    /// per frame; true means another frame is needed.
    public func advanceScrollAnimations(elapsed: Double) -> Bool {
        animatingScrollNodes.removeAll { !$0.isMounted }
        animatingScrollNodes = animatingScrollNodes.filter { $0.advance(elapsed: elapsed) }
        return !animatingScrollNodes.isEmpty
    }

    // MARK: Touch panning

    /// Starts tracking a touch that may become a pan of the scroll views under `point`.
    package func beginPan(at point: CGPoint, time: Double) {
        let nodes = scrollableNodes(at: point)
        guard !nodes.isEmpty else { return }
        var state = PanState(nodes: nodes, start: point, last: point, lastTime: time)
        // A finger landing on decelerating content stops it where it is and owns the touch:
        // the content follows it at once and lifting delivers no press (iOS behaviour).
        let decelerating = nodes.filter(\.isDecelerating)
        if !decelerating.isEmpty {
            for node in decelerating { node.stopMomentum() }
            state.active = true
            requestLayout(invalidatingSizes: false)
        }
        pan = state
    }

    /// Feeds a touch move to the pan; once the finger has travelled `PlatformMetrics.panSlop`
    /// the pan is active, the pending press is cancelled and the content follows the finger.
    package func continuePan(to point: CGPoint, time: Double) {
        guard var state = pan else { return }
        if !state.active {
            let dx = point.x - state.start.x, dy = point.y - state.start.y
            guard dx * dx + dy * dy >= PlatformMetrics.panSlop * PlatformMetrics.panSlop else { return }
            state.active = true
            pressedNode?.pressEnded(inside: false)
            pressedNode = nil
        }
        let delta = CGSize(width: state.last.x - point.x, height: state.last.y - point.y)
        _ = scroll(by: delta, through: state.nodes)
        let dt = time - state.lastTime
        if dt > 0 {
            let sample = CGSize(width: delta.width / dt, height: delta.height / dt)
            state.velocity = CGSize(width: 0.6 * sample.width + 0.4 * state.velocity.width,
                                    height: 0.6 * sample.height + 0.4 * state.velocity.height)
        }
        state.last = point
        state.lastTime = time
        pan = state
    }

    /// Ends the pan; an active one hands its velocity to the innermost scroll view. Returns
    /// whether a pan consumed the touch (so no press should be delivered).
    @discardableResult
    package func endPan(time: Double) -> Bool {
        guard let state = pan else { return false }
        pan = nil
        guard state.active else { return false }
        // A finger that stopped before lifting leaves no momentum.
        if time - state.lastTime < PlatformMetrics.panRestInterval, let node = state.nodes.first {
            node.beginMomentum(velocity: state.velocity)
        }
        return true
    }
}

/// `rate` raised to the whole number of milliseconds, by squaring: no libm (`pow` is not
/// importable on wasm through `@_silgen_name`, unlike `cos`/`sin`) and deterministic.
package func _decay(_ rate: Double, milliseconds: Double) -> Double {
    var exponent = max(0, Int(milliseconds.rounded()))
    var base = rate, result = 1.0
    while exponent > 0 {
        if exponent & 1 == 1 { result *= base }
        base *= base
        exponent >>= 1
    }
    return result
}
