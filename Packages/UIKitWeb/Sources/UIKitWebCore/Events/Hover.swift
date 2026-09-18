// Hover and pointer interactions (Docs/elements/UIKit/UIView.md, hover): a pointer that moves
// over the scene without a press hovers the view under it. `UIHoverGestureRecognizer`s on the
// hit view and its superviews begin when the pointer enters their view, change as it moves and
// end when it leaves; a `UIPointerInteraction`'s delegate picks the pointer's look, which the
// host shows as its cursor (a browser's CSS cursor). A hosted tree hovers the same way from its
// host's pointer (SwiftUIWeb's representables).

/// A continuous gesture recognizer that follows the pointer while it is over the view, with no
/// press: `began` on entry, `changed` on every move inside, `ended` on exit.
@MainActor
open class UIHoverGestureRecognizer: UIGestureRecognizer {
    /// The pointer's position in window coordinates.
    private var hoverLocation = CGPoint.zero
    /// The z offset a hovering pencil reports; a pointer has none.
    open var zOffset: CGFloat { 0 }

    override open func location(in view: UIView?) -> CGPoint {
        view.map { $0.convert(hoverLocation, from: nil) } ?? hoverLocation
    }

    func hover(at point: CGPoint) {
        hoverLocation = point
        if state == .possible {
            guard mayBegin() else { return }
            transition(to: .began)
        } else {
            transition(to: .changed)
        }
    }

    func hoverEnded() {
        if state == .began || state == .changed { transition(to: .ended) }
    }
}

/// The requirements for an interaction a view holds (`UIView.addInteraction`).
@MainActor
public protocol UIInteraction: AnyObject {
    var view: UIView? { get }
    func willMove(to view: UIView?)
    func didMove(to view: UIView?)
}

extension UIInteraction {
    public func willMove(to view: UIView?) {}
    public func didMove(to view: UIView?) {}
}

/// A region of a view the pointer treats as one.
public struct UIPointerRegion: Sendable {
    public let rect: CGRect
    public let identifier: (any Hashable & Sendable)?
    public init(rect: CGRect, identifier: (any Hashable & Sendable)? = nil) {
        self.rect = rect
        self.identifier = identifier
    }
}

/// A view the pointer's effect targets (the interaction's view here; no snapshot is taken).
@MainActor
public final class UITargetedPreview {
    public let view: UIView
    public init(view: UIView) { self.view = view }
}

/// How the pointer changes over a view.
@MainActor
public enum UIPointerEffect {
    case automatic(UITargetedPreview)
    case highlight(UITargetedPreview)
    case lift(UITargetedPreview)
    case hover(UITargetedPreview, preferredTintMode: TintMode = .overlay, prefersShadow: Bool = false, prefersScaledContent: Bool = true)
    public enum TintMode: Int, Sendable { case none = 0, overlay, underlay }
}

/// The pointer's shape over a view.
public enum UIPointerShape: Sendable {
    case path(UIBezierPath)
    case roundedRect(CGRect, radius: CGFloat = UIPointerShape.defaultCornerRadius)
    case verticalBeam(length: CGFloat)
    case horizontalBeam(length: CGFloat)
    public static let defaultCornerRadius: CGFloat = 8
}

/// The pointer's look over a view: an effect, a shape, or the system pointer, or hidden.
@MainActor
public final class UIPointerStyle {
    public let effect: UIPointerEffect?
    public let shape: UIPointerShape?
    public let isHidden: Bool
    public var accessories: [UIPointerAccessory] = []

    public init(effect: UIPointerEffect, shape: UIPointerShape? = nil) {
        self.effect = effect
        self.shape = shape
        isHidden = false
    }

    public init(shape: UIPointerShape, constrainedAxes: UIAxis = []) {
        effect = nil
        self.shape = shape
        isHidden = false
    }

    private init(hidden: Bool) {
        effect = nil
        shape = nil
        isHidden = hidden
    }

    /// The system pointer, unchanged.
    public static func system() -> UIPointerStyle { UIPointerStyle(hidden: false) }
    /// No pointer at all.
    public static func hidden() -> UIPointerStyle { UIPointerStyle(hidden: true) }

    /// The CSS cursor the browser host shows for this style: a beam is a text cursor, a hidden
    /// pointer none, an effect or a custom shape the hand a hover-effect control gets; the system
    /// style leaves the host's cursor alone.
    var cursor: String? {
        if isHidden { return "none" }
        switch shape {
        case .horizontalBeam: return "text"
        case .verticalBeam: return "vertical-text"
        case .path, .roundedRect: return "pointer"
        case nil: return effect == nil ? nil : "pointer"
        }
    }
}

/// An accessory drawn with the pointer (accepted).
public struct UIPointerAccessory: Sendable {
    public init() {}
}

/// The methods a pointer interaction's delegate implements.
@MainActor
public protocol UIPointerInteractionDelegate: AnyObject {
    func pointerInteraction(_ interaction: UIPointerInteraction, regionFor request: UIPointerRegionRequest, defaultRegion: UIPointerRegion) -> UIPointerRegion?
    func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle?
    func pointerInteraction(_ interaction: UIPointerInteraction, willEnter region: UIPointerRegion, animator: any UIPointerInteractionAnimating)
    func pointerInteraction(_ interaction: UIPointerInteraction, willExit region: UIPointerRegion, animator: any UIPointerInteractionAnimating)
}

extension UIPointerInteractionDelegate {
    public func pointerInteraction(_ interaction: UIPointerInteraction, regionFor request: UIPointerRegionRequest, defaultRegion: UIPointerRegion) -> UIPointerRegion? { defaultRegion }
    public func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? { nil }
    public func pointerInteraction(_ interaction: UIPointerInteraction, willEnter region: UIPointerRegion, animator: any UIPointerInteractionAnimating) {}
    public func pointerInteraction(_ interaction: UIPointerInteraction, willExit region: UIPointerRegion, animator: any UIPointerInteractionAnimating) {}
}

/// The pointer's position a region is asked for.
public struct UIPointerRegionRequest: Sendable {
    public let location: CGPoint
    public init(location: CGPoint) { self.location = location }
}

/// Animations alongside a pointer entering or leaving a region (run at once here).
@MainActor
public protocol UIPointerInteractionAnimating: AnyObject {
    func addAnimations(_ animations: @escaping () -> Void)
    func addCompletion(_ completion: @escaping (Bool) -> Void)
}

final class ImmediatePointerAnimator: UIPointerInteractionAnimating {
    func addAnimations(_ animations: @escaping () -> Void) { animations() }
    func addCompletion(_ completion: @escaping (Bool) -> Void) { completion(true) }
}

/// An interaction that changes the pointer's look over its view.
@MainActor
public final class UIPointerInteraction: UIInteraction {
    public weak var delegate: (any UIPointerInteractionDelegate)?
    public var isEnabled = true
    public private(set) weak var view: UIView?
    /// The region the pointer is in, while it is over the view.
    private var currentRegion: UIPointerRegion?

    public init(delegate: (any UIPointerInteractionDelegate)? = nil) {
        self.delegate = delegate
    }

    public func willMove(to view: UIView?) { self.view = view }
    public func didMove(to view: UIView?) { self.view = view }

    /// Asks the delegate for the pointer's look at `point` (in the view's coordinates).
    func style(at point: CGPoint) -> UIPointerStyle? {
        guard isEnabled, let view else { return nil }
        let defaultRegion = UIPointerRegion(rect: view.bounds)
        let region = delegate?.pointerInteraction(self, regionFor: UIPointerRegionRequest(location: point), defaultRegion: defaultRegion) ?? defaultRegion
        if currentRegion == nil { delegate?.pointerInteraction(self, willEnter: region, animator: ImmediatePointerAnimator()) }
        currentRegion = region
        return delegate?.pointerInteraction(self, styleFor: region) ?? .system()
    }

    func pointerLeft() {
        if let region = currentRegion { delegate?.pointerInteraction(self, willExit: region, animator: ImmediatePointerAnimator()) }
        currentRegion = nil
    }

    /// Asks the delegate again (`invalidate()`).
    public func invalidate() { currentRegion = nil }
}

/// Routes press-less pointer moves to the hover recognizers and pointer interactions of the
/// views under the pointer: one router per window scene, one per hosted tree.
@MainActor
final class HoverRouter {
    /// The views under the pointer, from the hit view up to the window.
    private var hoveredViews: [UIView] = []
    /// The cursor the hovered pointer interaction or control asks for.
    private(set) var cursor: String?

    /// The pointer is at `point` in `window`, or has left (`nil`).
    func update(to point: CGPoint?, in window: UIWindow?) {
        var chain: [UIView] = []
        if let point, let window, let hit = window.hitTest(point, with: nil) {
            var view: UIView? = hit
            while let v = view { chain.append(v); view = v.superview }
        }
        // Views the pointer left, deepest first.
        for view in hoveredViews where !chain.contains(where: { $0 === view }) {
            for recognizer in view.gestureRecognizers ?? [] { (recognizer as? UIHoverGestureRecognizer)?.hoverEnded() }
            for interaction in view.interactions { (interaction as? UIPointerInteraction)?.pointerLeft() }
        }
        hoveredViews = chain
        var cursor: String?
        if let point {
            for view in chain {
                for recognizer in view.gestureRecognizers ?? [] { (recognizer as? UIHoverGestureRecognizer)?.hover(at: point) }
                let local = view.convert(point, from: nil)
                for interaction in view.interactions {
                    guard cursor == nil, let pointer = interaction as? UIPointerInteraction else { continue }
                    cursor = pointer.style(at: local)?.cursor
                }
                if cursor == nil, let button = view as? UIButton, button.isPointerInteractionEnabled, button.isEnabled { cursor = "pointer" }
            }
        }
        self.cursor = cursor
        UIKitScene.shared.setNeedsFrame()
    }
}

extension UIView {
    /// The interactions this view holds (`UIPointerInteraction`).
    public var interactions: [any UIInteraction] {
        get { storedInteractions }
        set {
            for interaction in storedInteractions { interaction.willMove(to: nil); interaction.didMove(to: nil) }
            storedInteractions = newValue
            for interaction in newValue { interaction.willMove(to: self); interaction.didMove(to: self) }
        }
    }

    public func addInteraction(_ interaction: any UIInteraction) {
        interaction.willMove(to: self)
        storedInteractions.append(interaction)
        interaction.didMove(to: self)
    }

    public func removeInteraction(_ interaction: any UIInteraction) {
        interaction.willMove(to: nil)
        storedInteractions.removeAll { $0 === interaction }
        interaction.didMove(to: nil)
    }
}
