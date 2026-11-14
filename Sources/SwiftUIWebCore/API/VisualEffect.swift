// Visual effects (iOS 17): effects that change how a view draws, never its layout, so they can
// follow the view's own geometry. `visualEffect` hands the effect closure the view's geometry
// proxy; `scrollTransition` hands it the view's phase in the nearest scroll view (entering at the
// leading edge, fully in view, leaving at the trailing edge). The effects are opacity, scale,
// offset, rotation, 3D rotation, transforms, blur and the colour effects; the runtime applies them
// while painting (Runtime/VisualEffectNodes.swift), so a scroll moves them without a new layout.

/// Effects that change how a view draws without changing its layout.
public protocol VisualEffect: Sendable {
    /// The effect as steps from the innermost to the outermost.
    var _steps: [_VisualEffectStep] { get }
}

/// One effect of a `VisualEffect`.
public enum _VisualEffectStep: Sendable {
    case opacity(Double)
    case scale(CGSize, anchor: UnitPoint)
    case offset(CGSize)
    case rotation(Angle, anchor: UnitPoint)
    case rotation3D(Angle, axis: (x: CGFloat, y: CGFloat, z: CGFloat), anchor: UnitPoint)
    case transform(CGAffineTransform)
    case blur(CGFloat, opaque: Bool)
    case color(_ColorMatrixEffect.Kind)
    case blend(BlendMode)
}

/// The effect a `visualEffect` or `scrollTransition` closure starts from: none.
public struct EmptyVisualEffect: VisualEffect {
    public init() {}
    public var _steps: [_VisualEffectStep] { [] }
}

/// A visual effect with one more step.
public struct _VisualEffectModified: VisualEffect {
    public let _steps: [_VisualEffectStep]
}

extension _ColorMatrixEffect.Kind: @unchecked Sendable {}

extension VisualEffect {
    private func adding(_ step: _VisualEffectStep) -> _VisualEffectModified { _VisualEffectModified(_steps: _steps + [step]) }

    /// Sets the transparency of the view.
    public func opacity(_ opacity: Double) -> some VisualEffect { adding(.opacity(opacity)) }
    /// Scales the view by the given amounts about `anchor`.
    public func scaleEffect(_ scale: CGSize, anchor: UnitPoint = .center) -> some VisualEffect { adding(.scale(scale, anchor: anchor)) }
    /// Scales the view by the given amount in both dimensions about `anchor`.
    public func scaleEffect(_ s: CGFloat, anchor: UnitPoint = .center) -> some VisualEffect { adding(.scale(CGSize(width: s, height: s), anchor: anchor)) }
    /// Scales the view by the given horizontal and vertical amounts about `anchor`.
    public func scaleEffect(x: CGFloat = 1, y: CGFloat = 1, anchor: UnitPoint = .center) -> some VisualEffect {
        adding(.scale(CGSize(width: x, height: y), anchor: anchor))
    }
    /// Moves the view by `offset`.
    public func offset(_ offset: CGSize) -> some VisualEffect { adding(.offset(offset)) }
    /// Moves the view by the given distances.
    public func offset(x: CGFloat = 0, y: CGFloat = 0) -> some VisualEffect { adding(.offset(CGSize(width: x, height: y))) }
    /// Rotates the view about `anchor`.
    public func rotationEffect(_ angle: Angle, anchor: UnitPoint = .center) -> some VisualEffect { adding(.rotation(angle, anchor: anchor)) }
    /// Rotates the view in three dimensions about `axis` (its flat projection).
    public func rotation3DEffect(_ angle: Angle, axis: (x: CGFloat, y: CGFloat, z: CGFloat), anchor: UnitPoint = .center,
                                 anchorZ: CGFloat = 0, perspective: CGFloat = 1) -> some VisualEffect {
        adding(.rotation3D(angle, axis: axis, anchor: anchor))
    }
    /// Applies an affine transform about the view's origin.
    public func transformEffect(_ transform: CGAffineTransform) -> some VisualEffect { adding(.transform(transform)) }
    /// Blurs the view.
    public func blur(radius: CGFloat, opaque: Bool = false) -> some VisualEffect { adding(.blur(radius, opaque: opaque)) }
    /// Brightens the view.
    public func brightness(_ amount: Double) -> some VisualEffect { adding(.color(.brightness(amount))) }
    /// Sets the view's contrast.
    public func contrast(_ amount: Double) -> some VisualEffect { adding(.color(.contrast(amount))) }
    /// Sets the view's colour saturation.
    public func saturation(_ amount: Double) -> some VisualEffect { adding(.color(.saturation(amount))) }
    /// Takes colour out of the view.
    public func grayscale(_ amount: Double) -> some VisualEffect { adding(.color(.grayscale(amount))) }
    /// Rotates the view's hues.
    public func hueRotation(_ angle: Angle) -> some VisualEffect { adding(.color(.hueRotation(angle))) }
    /// Multiplies the view's colours by `color`.
    public func colorMultiply(_ color: Color) -> some VisualEffect { adding(.color(.colorMultiply(color))) }
    /// Composites the view with `blendMode`.
    public func blendMode(_ blendMode: BlendMode) -> some VisualEffect { adding(.blend(blendMode)) }
}

// MARK: - Scroll transitions

/// Where a view is in its scroll view, as a scroll transition sees it.
public enum ScrollTransitionPhase: Sendable, Hashable {
    /// The view is entering or leaving at the top or leading edge.
    case topLeading
    /// The view is in view.
    case identity
    /// The view is entering or leaving at the bottom or trailing edge.
    case bottomTrailing

    /// Whether the view is in view.
    public var isIdentity: Bool { self == .identity }

    /// -1 at the top or leading edge, 0 in view, 1 at the bottom or trailing edge.
    public var value: Double {
        switch self {
        case .topLeading: -1
        case .identity: 0
        case .bottomTrailing: 1
        }
    }
}

/// How a scroll transition moves between its phases.
public struct ScrollTransitionConfiguration: Sendable {
    enum Kind: Sendable {
        case animated(Animation?)
        case interactive(UnitCurve)
        case identity
    }
    var kind: Kind
    var threshold: Threshold = .visible

    /// The phase changes when the view crosses the threshold, with the default animation.
    public static let animated = ScrollTransitionConfiguration(kind: .animated(.default))
    /// The effect follows the view as it scrolls across the threshold.
    public static let interactive = ScrollTransitionConfiguration(kind: .interactive(.easeInOut))
    /// The view stays in its identity phase.
    public static let identity = ScrollTransitionConfiguration(kind: .identity)

    /// The phase changes when the view crosses the threshold, with `animation`.
    public static func animated(_ animation: Animation = .default) -> Self { Self(kind: .animated(animation)) }
    /// The effect follows the view as it scrolls, along `timingCurve`.
    public static func interactive(timingCurve: UnitCurve = .easeInOut) -> Self { Self(kind: .interactive(timingCurve)) }

    /// The same configuration changing phase at `threshold`.
    public func threshold(_ threshold: Threshold) -> Self {
        var copy = self
        copy.threshold = threshold
        return copy
    }

    /// The same configuration animating its phase changes with `animation`.
    public func animation(_ animation: Animation) -> Self {
        guard case .animated = kind else { return self }
        var copy = self
        copy.kind = .animated(animation)
        return copy
    }

    /// Where in the scroll view the view is in its identity phase.
    public struct Threshold: Sendable {
        enum Kind: Sendable {
            /// In identity while at least this share of the view is visible.
            case visible(Double)
            /// In identity only while centred.
            case centered
        }
        var kind: Kind
        var inset: CGFloat = 0

        /// In identity while the whole view is visible.
        public static let visible = Threshold(kind: .visible(1))
        /// In identity while any of the view is visible.
        public static let hidden = Threshold(kind: .visible(0))
        /// In identity only while the view is centred in the scroll view.
        public static let centered = Threshold(kind: .centered)
        /// In identity while at least `amount` (0 to 1) of the view is visible.
        public static func visible(_ amount: Double) -> Threshold { Threshold(kind: .visible(min(max(amount, 0), 1))) }

        /// A threshold `amount` (0 to 1) of the way from this one to `other`.
        public func interpolated(towards other: Threshold, amount: Double) -> Threshold {
            switch (kind, other.kind) {
            case (.visible(let a), .visible(let b)):
                var mixed = Threshold(kind: .visible(a + (b - a) * amount))
                mixed.inset = inset + (other.inset - inset) * CGFloat(amount)
                return mixed
            default:
                return amount < 0.5 ? self : other
            }
        }

        /// The same threshold measured against the scroll view's visible area inset by `length`.
        public func inset(by length: CGFloat) -> Threshold {
            var copy = self
            copy.inset = length
            return copy
        }
    }
}

/// The scroll view's coordinate space: its visible area, the content's scroll included.
public struct _ScrollViewCoordinateSpaceName: Hashable, Sendable {}

extension CoordinateSpaceProtocol where Self == NamedCoordinateSpace {
    /// The nearest enclosing scroll view's coordinate space.
    public static var scrollView: NamedCoordinateSpace { NamedCoordinateSpace(AnyHashable(_ScrollViewCoordinateSpaceName())) }
    /// The nearest enclosing scroll view along `axis`'s coordinate space.
    public static func scrollView(axis: Axis) -> NamedCoordinateSpace { scrollView }
}

// MARK: - Modifiers

/// `visualEffect` and `scrollTransition`: how the view's effects are worked out when it paints.
public struct _VisualEffectModifier {
    package enum Source {
        /// From the view's geometry.
        case geometry(@MainActor (GeometryProxy) -> [_VisualEffectStep])
        /// From the view's phase in its scroll view: the configurations at the top or leading
        /// edge and at the bottom or trailing edge, the axis, and each phase's steps.
        case scrollTransition(leading: ScrollTransitionConfiguration, trailing: ScrollTransitionConfiguration, axis: Axis?,
                              steps: @MainActor (ScrollTransitionPhase) -> [_VisualEffectStep])
    }
    package var source: Source
}

extension _VisualEffectModifier: ViewModifier {
    public typealias Body = Never

    public static func _makeNode<Content: View>(_ context: _NodeContext<ModifiedContent<Content, Self>>) -> TypedNode<ModifiedContent<Content, Self>> {
        VisualEffectNode(context)
    }
}

extension View {
    /// Applies the effects that `effect` returns from the view's geometry. They change how the
    /// view draws, not its layout, and follow its geometry as it moves.
    nonisolated public func visualEffect(_ effect: @escaping @MainActor @Sendable (EmptyVisualEffect, GeometryProxy) -> some VisualEffect) -> some View {
        modifier(_VisualEffectModifier(source: .geometry { effect(EmptyVisualEffect(), $0)._steps }))
    }

    /// Applies the effects that `transition` returns for the view's phase in the nearest scroll
    /// view as it scrolls in and out of view.
    nonisolated public func scrollTransition(_ configuration: ScrollTransitionConfiguration = .interactive, axis: Axis? = nil,
                                             transition: @escaping @MainActor @Sendable (EmptyVisualEffect, ScrollTransitionPhase) -> some VisualEffect) -> some View {
        scrollTransition(topLeading: configuration, bottomTrailing: configuration, axis: axis, transition: transition)
    }

    /// Applies the effects that `transition` returns for the view's phase, configured apart for
    /// the top or leading edge and the bottom or trailing edge.
    nonisolated public func scrollTransition(topLeading: ScrollTransitionConfiguration, bottomTrailing: ScrollTransitionConfiguration,
                                             axis: Axis? = nil,
                                             transition: @escaping @MainActor @Sendable (EmptyVisualEffect, ScrollTransitionPhase) -> some VisualEffect) -> some View {
        modifier(_VisualEffectModifier(source: .scrollTransition(leading: topLeading, trailing: bottomTrailing, axis: axis,
                                                                 steps: { transition(EmptyVisualEffect(), $0)._steps })))
    }
}
