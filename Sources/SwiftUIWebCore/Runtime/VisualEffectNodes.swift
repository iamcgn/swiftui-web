// The node of `visualEffect` and `scrollTransition` (API/VisualEffect.swift): identity for layout;
// painting works the effects out from the view's geometry at that moment and applies them, the
// last one outermost, as the opacity, blur, colour and transform nodes would. A scroll moves the
// content without a new layout and the next paint reads the new position, so the effects follow
// the scroll frame by frame. An animated scroll transition switches phase after a layout pass and
// tweens the change.

@MainActor
package final class VisualEffectNode<Content: View>: UnaryLayoutModifierNode<Content, _VisualEffectModifier>, _PreferenceObserver {
    /// The animated scroll transition's phase value (-1, 0 or 1) after the last layout pass.
    private var animatedValue: Double?

    override package init(_ context: _NodeContext<ModifiedContent<Content, _VisualEffectModifier>>) {
        super.init(context)
        runtime.preferenceObservers.append(WeakObserver(self))
    }

    override package var paintsOutsideFrame: Bool { true }

    /// An animated scroll transition reads its phase after each layout pass, so a scroll view
    /// around it lays out as it scrolls.
    override package var readsGeometry: Bool {
        guard case .scrollTransition(let leading, let trailing, _, _) = modifier.source else { return false }
        return leading.isAnimated || trailing.isAnimated
    }

    override package var nodeDescription: String { "VisualEffect" }

    // MARK: Scroll transitions

    /// The nearest enclosing scroll view.
    private var viewport: (any _ScrollViewport)? {
        var node = parent
        while let current = node {
            if let scroll = current as? any _ScrollViewport { return scroll }
            node = current.parent
        }
        return nil
    }

    /// How far the view is from its identity phase along the scroll axis: -1 (fully past the top
    /// or leading edge's threshold) through 0 (in identity) to 1 (past the bottom or trailing
    /// edge's), measured against each edge's configuration.
    private func scrollProgress(_ leading: ScrollTransitionConfiguration, _ trailing: ScrollTransitionConfiguration, axis: Axis?) -> Double {
        guard hasBeenPlaced, let scroll = viewport else { return 0 }
        let axis = axis ?? (scroll.axes == .horizontal ? .horizontal : .vertical)
        let mine = frameInRoot, visible = scroll.frameInRoot, insets = scroll.contentInsets
        let (a, b) = axis == .vertical ? (mine.minY, mine.maxY) : (mine.minX, mine.maxX)
        var (s, e) = axis == .vertical ? (visible.minY + insets.top, visible.maxY - insets.bottom)
                                       : (visible.minX + insets.leading, visible.maxX - insets.trailing)
        let isLeading = (a + b) / 2 < (s + e) / 2
        let threshold = (isLeading ? leading : trailing).threshold
        s += threshold.inset
        e -= threshold.inset
        let length = max(b - a, 0.0001)
        let amount: Double
        switch threshold.kind {
        case .visible(let share):
            let hidden = Double(min(max(isLeading ? (s - a) / length : (b - e) / length, 0), 1))
            amount = share <= 0 ? (hidden >= 1 ? 1 : 0) : min(max((hidden - (1 - share)) / share, 0), 1)
        case .centered:
            let range = max((e - s) / 2 + length / 2, 0.0001)
            amount = Double(min(abs((a + b) / 2 - (s + e) / 2) / range, 1))
        }
        return isLeading ? -amount : amount
    }

    package func evaluatePreference() {
        guard hasBeenPlaced, case .scrollTransition(let leading, let trailing, let axis, _) = modifier.source,
              leading.isAnimated || trailing.isAnimated else { return }
        let progress = scrollProgress(leading, trailing, axis: axis)
        let configuration = progress < 0 ? leading : trailing
        guard case .animated(let animation) = configuration.kind else { return }
        let target: Double = progress == 0 ? 0 : (progress < 0 ? -1 : 1)
        guard let previous = animatedValue else {
            animatedValue = target
            return
        }
        guard previous != target else { return }
        let from = presentation?.effect?.value(at: runtime.animationClock).first ?? previous
        animatedValue = target
        if let animation {
            let presentation = self.presentation ?? NodePresentation()
            presentation.effect = Tween(from: [from], to: [target], animation: animation, start: runtime.animationClock)
            self.presentation = presentation
            runtime.register(animating: self)
        } else {
            presentation?.effect = nil
        }
    }

    /// The phase value to paint with: the tween's while an animated change runs, the view's place
    /// for an interactive transition.
    private func phaseValue(_ leading: ScrollTransitionConfiguration, _ trailing: ScrollTransitionConfiguration, axis: Axis?) -> Double {
        let progress = scrollProgress(leading, trailing, axis: axis)
        let configuration = progress < 0 ? leading : trailing
        switch configuration.kind {
        case .identity:
            return 0
        case .interactive(let curve):
            let eased = curve.value(at: abs(progress))
            return progress < 0 ? -eased : eased
        case .animated:
            if let tween = presentation?.effect?.value(at: runtime.animationClock).first { return tween }
            return animatedValue ?? (progress == 0 ? 0 : (progress < 0 ? -1 : 1))
        }
    }

    // MARK: Painting

    /// The steps to paint with now.
    package var currentSteps: [_VisualEffectStep] {
        switch modifier.source {
        case .geometry(let effect):
            return effect(GeometryProxy(node: self, size: frame.size))
        case .scrollTransition(let leading, let trailing, let axis, let steps):
            let value = phaseValue(leading, trailing, axis: axis)
            let identity = steps(.identity)
            guard value != 0 else { return identity }
            return _VisualEffectStep.interpolate(identity, steps(value < 0 ? .topLeading : .bottomTrailing), by: min(abs(value), 1))
        }
    }

    override package func paintTarget(_ target: ViewNode, in node: ViewNode, into list: inout DisplayList, context: PaintContext) {
        paint(currentSteps[...], target, node, &list, context)
    }

    private func paint(_ steps: ArraySlice<_VisualEffectStep>, _ target: ViewNode, _ node: ViewNode,
                       _ list: inout DisplayList, _ context: PaintContext) {
        guard let step = steps.last else {
            super.paintTarget(target, in: node, into: &list, context: context)
            return
        }
        let inner = steps.dropLast()
        let size = node.presentedFrame.size
        func transformed(_ local: CGAffineTransform, anchor: UnitPoint) {
            let p = CGPoint(x: context.origin.x + size.width * anchor.x, y: context.origin.y + size.height * anchor.y)
            let transform = CGAffineTransform(translationX: -p.x, y: -p.y).concatenating(local).concatenating(CGAffineTransform(translationX: p.x, y: p.y))
            paintTransformed(transform, into: &list) { list in paint(inner, target, node, &list, context) }
        }
        var effects = context
        switch step {
        case .opacity(let opacity):
            guard opacity > 0 else { return }
            if opacity < 1 { effects.effects.append(.opacity(opacity)) }
        case .blur(let radius, let opaque):
            if radius > 0 { effects.effects.append(.filter(.blur(radius: radius, opaque: opaque))) }
        case .color(let kind):
            let matrix = _ColorMatrixEffect(kind: kind).matrix(in: environment)
            if matrix != .identity { effects.effects.append(.filter(.colorMatrix(matrix))) }
        case .blend(let mode):
            if mode != .normal { effects.effects.append(.blend(mode)) }
        case .scale(let scale, let anchor):
            return transformed(CGAffineTransform(scaleX: scale.width, y: scale.height), anchor: anchor)
        case .offset(let offset):
            return transformed(CGAffineTransform(translationX: offset.width, y: offset.height), anchor: .topLeading)
        case .rotation(let angle, let anchor):
            return transformed(CGAffineTransform(rotationAngle: CGFloat(angle.radians)), anchor: anchor)
        case .rotation3D(let angle, let axis, let anchor):
            return transformed(_Rotation3DEffect.affine(radians: angle.radians, axis: axis), anchor: anchor)
        case .transform(let transform):
            return transformed(transform, anchor: .topLeading)
        }
        paint(inner, target, node, &list, effects)
    }
}

extension ScrollTransitionConfiguration {
    var isAnimated: Bool {
        if case .animated = kind { return true }
        return false
    }
}

extension _VisualEffectStep {
    /// The steps `t` of the way from `a` to `b` (an interactive scroll transition between its
    /// identity and an edge); steps that differ in kind switch halfway.
    static func interpolate(_ a: [_VisualEffectStep], _ b: [_VisualEffectStep], by t: Double) -> [_VisualEffectStep] {
        guard a.count == b.count else { return t < 0.5 ? a : b }
        return zip(a, b).map { $0.interpolated(to: $1, by: t) }
    }

    func interpolated(to other: _VisualEffectStep, by t: Double) -> _VisualEffectStep {
        // Local functions can't overload (CGFloat is Double on some platforms), so each has its own name.
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        func mixLength(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * CGFloat(t) }
        func mixSize(_ x: CGSize, _ y: CGSize) -> CGSize { CGSize(width: mixLength(x.width, y.width), height: mixLength(x.height, y.height)) }
        func mixAngle(_ x: Angle, _ y: Angle) -> Angle { .radians(mix(x.radians, y.radians)) }
        switch (self, other) {
        case (.opacity(let x), .opacity(let y)): return .opacity(mix(x, y))
        case (.scale(let x, _), .scale(let y, let anchor)): return .scale(mixSize(x, y), anchor: anchor)
        case (.offset(let x), .offset(let y)): return .offset(mixSize(x, y))
        case (.rotation(let x, _), .rotation(let y, let anchor)): return .rotation(mixAngle(x, y), anchor: anchor)
        case (.rotation3D(let x, _, _), .rotation3D(let y, let axis, let anchor)): return .rotation3D(mixAngle(x, y), axis: axis, anchor: anchor)
        case (.transform(let x), .transform(let y)):
            return .transform(CGAffineTransform(a: mixLength(x.a, y.a), b: mixLength(x.b, y.b), c: mixLength(x.c, y.c), d: mixLength(x.d, y.d), tx: mixLength(x.tx, y.tx), ty: mixLength(x.ty, y.ty)))
        case (.blur(let x, _), .blur(let y, let opaque)): return .blur(mixLength(x, y), opaque: opaque)
        case (.color(.brightness(let x)), .color(.brightness(let y))): return .color(.brightness(mix(x, y)))
        case (.color(.contrast(let x)), .color(.contrast(let y))): return .color(.contrast(mix(x, y)))
        case (.color(.saturation(let x)), .color(.saturation(let y))): return .color(.saturation(mix(x, y)))
        case (.color(.grayscale(let x)), .color(.grayscale(let y))): return .color(.grayscale(mix(x, y)))
        case (.color(.hueRotation(let x)), .color(.hueRotation(let y))): return .color(.hueRotation(mixAngle(x, y)))
        default: return t < 0.5 ? self : other
        }
    }
}
