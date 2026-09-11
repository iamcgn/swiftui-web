// UIView.animate on the frame clock (Docs/elements/UIKit/Animation.md, decision 0014 Phase 3):
// property changes made inside an animation block are recorded as animations from the old
// value to the new one; the model takes the new value at once, painting reads the presented
// value while the animation runs, and the scene advances every group per frame.

/// A value a layer property can interpolate.
enum AnimatableValue {
    case scalar(Double)
    case point(CGPoint)
    case rect(CGRect)
    case color(RGBA?)
    case transform(CGAffineTransform)

    func interpolated(to other: AnimatableValue, _ t: Double) -> AnimatableValue {
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        switch (self, other) {
        case (.scalar(let a), .scalar(let b)): return .scalar(mix(a, b))
        case (.point(let a), .point(let b)): return .point(CGPoint(x: mix(a.x, b.x), y: mix(a.y, b.y)))
        case (.rect(let a), .rect(let b)):
            return .rect(CGRect(x: mix(a.minX, b.minX), y: mix(a.minY, b.minY), width: mix(a.width, b.width), height: mix(a.height, b.height)))
        case (.color(let a), .color(let b)):
            let from = a ?? (b.map { RGBA(red: $0.red, green: $0.green, blue: $0.blue, alpha: 0) } ?? .clear)
            let to = b ?? (a.map { RGBA(red: $0.red, green: $0.green, blue: $0.blue, alpha: 0) } ?? .clear)
            return .color(RGBA(red: mix(from.red, to.red), green: mix(from.green, to.green), blue: mix(from.blue, to.blue), alpha: mix(from.alpha, to.alpha)))
        case (.transform(let a), .transform(let b)):
            return .transform(CGAffineTransform(a: mix(a.a, b.a), b: mix(a.b, b.b), c: mix(a.c, b.c), d: mix(a.d, b.d), tx: mix(a.tx, b.tx), ty: mix(a.ty, b.ty)))
        default: return t < 1 ? self : other
        }
    }
}

/// The layer properties that animate.
enum AnimatableProperty: Hashable {
    case position, bounds, opacity, backgroundColor, transform, cornerRadius, borderWidth, shadowOpacity, borderColor
}

/// The timing of an animation block.
enum AnimationCurve {
    case easeInOut, easeIn, easeOut, linear
    case spring(damping: Double, velocity: Double)
    /// A CSS-style cubic bezier (`CAMediaTimingFunction(controlPoints:)`).
    case cubic(Double, Double, Double, Double)

    /// The eased fraction at linear fraction `t` (0…1).
    func value(at t: Double) -> Double {
        switch self {
        case .linear: return t
        case .cubic(let x1, let y1, let x2, let y2): return Self.cubicBezier(x1, y1, x2, y2, t)
        case .easeIn: return Self.cubicBezier(0.42, 0, 1, 1, t)
        case .easeOut: return Self.cubicBezier(0, 0, 0.58, 1, t)
        case .easeInOut: return Self.cubicBezier(0.42, 0, 0.58, 1, t)
        case .spring(let damping, let velocity):
            // A damped spring that settles by the end of the duration (UIKit's block spring).
            let zeta = max(0.05, min(1, damping))
            let omega = 6.9 / max(0.05, zeta)   // e^(-zeta * omega) ≈ 0.001 at t = 1
            let decay = _exp(-zeta * omega * t)
            if zeta >= 1 {
                return 1 - decay * (1 + (omega - velocity) * t)
            }
            let damped = omega * (1 - zeta * zeta).squareRoot()
            let phase = (zeta * omega - velocity) / damped
            return 1 - decay * (_cos(damped * t) + phase * _sin(damped * t))
        }
    }

    /// CSS's cubic-bezier(x1, y1, x2, y2): solve x(s) = t for s by Newton's method, return y(s).
    static func cubicBezier(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ t: Double) -> Double {
        if t <= 0 { return 0 }
        if t >= 1 { return 1 }
        func x(_ s: Double) -> Double { 3 * (1 - s) * (1 - s) * s * x1 + 3 * (1 - s) * s * s * x2 + s * s * s }
        func y(_ s: Double) -> Double { 3 * (1 - s) * (1 - s) * s * y1 + 3 * (1 - s) * s * s * y2 + s * s * s }
        func dx(_ s: Double) -> Double { 3 * (1 - s) * (1 - s) * x1 + 6 * (1 - s) * s * (x2 - x1) + 3 * s * s * (1 - x2) }
        var s = t
        for _ in 0..<8 {
            let slope = dx(s)
            if abs(slope) < 1e-6 { break }
            s -= (x(s) - t) / slope
            s = min(1, max(0, s))
        }
        return y(s)
    }
}

/// One `UIView.animate` block: its timing and the layer changes recorded inside it.
@MainActor
final class UIViewAnimationGroup {
    let duration: Double
    let delay: Double
    let curve: AnimationCurve
    var completion: ((Bool) -> Void)?
    private(set) var elapsed: Double = 0
    /// Core Animation timing: how many times the animation plays (`.infinity` for ever) and
    /// whether it plays back to the start each time (`CAAnimation.repeatCount`, `autoreverses`).
    var repeatCount: Double = 1
    var autoreverses = false
    /// A Core Animation that keeps its final value (`fillMode` forwards without removal):
    /// finished, it stays on its layers at progress 1 until removed.
    var retainsFinalValue = false
    struct Entry {
        weak var layer: CALayer?
        let property: AnimatableProperty
        var from: AnimatableValue
        var to: AnimatableValue
    }
    private(set) var entries: [Entry] = []

    init(duration: Double, delay: Double, curve: AnimationCurve) {
        self.duration = duration
        self.delay = delay
        self.curve = curve
    }

    /// The eased progress now (0 before the delay ends, 1 when done); a repeating animation
    /// cycles, an autoreversing one goes back each odd cycle.
    var progress: Double {
        guard duration > 0 else { return elapsed >= delay ? 1 : 0 }
        let time = max(0, elapsed - delay)
        if isFinished { return autoreverses ? 0 : 1 }
        let cycle = time / duration
        var fraction = cycle - cycle.rounded(.down)
        if autoreverses, Int(cycle.rounded(.down)) % 2 == 1 { fraction = 1 - fraction }
        return curve.value(at: min(1, max(0, fraction)))
    }

    /// The whole run: the duration times the repeats (twice each when autoreversing).
    var totalDuration: Double {
        guard repeatCount.isFinite else { return .infinity }
        return duration * max(1, repeatCount) * (autoreverses ? 2 : 1)
    }

    var isFinished: Bool { elapsed >= delay + totalDuration }

    func record(_ layer: CALayer, _ property: AnimatableProperty, from: AnimatableValue, to: AnimatableValue) {
        if let index = entries.firstIndex(where: { $0.layer === layer && $0.property == property }) {
            entries[index].to = to
        } else {
            entries.append(Entry(layer: layer, property: property, from: from, to: to))
        }
        layer.animatingGroups.append(self)
    }

    /// Moves the clock; returns whether the group still runs. A finished group leaves its
    /// layers unless it retains its final value (`removeFromLayers` takes it off then).
    func advance(by seconds: Double) -> Bool {
        elapsed += seconds
        if isFinished {
            if !retainsFinalValue { removeFromLayers() }
            return false
        }
        return true
    }

    func removeFromLayers() {
        for entry in entries { entry.layer?.animatingGroups.removeAll { $0 === self } }
    }

    /// The presented value of a layer's property, if this group animates it.
    func presented(_ layer: CALayer, _ property: AnimatableProperty) -> AnimatableValue? {
        guard let entry = entries.first(where: { $0.layer === layer && $0.property == property }) else { return nil }
        return entry.from.interpolated(to: entry.to, progress)
    }
}

/// The animation block being recorded, if any.
@MainActor
enum UIViewAnimationContext {
    static var current: UIViewAnimationGroup?
    static var disabled = false

    /// Records a change to `property` when inside an animation block, or as a standalone
    /// layer's implicit animation under the current `CATransaction` (a view's backing layer
    /// animates only in `UIView.animate` blocks, as in UIKit).
    static func record(_ layer: CALayer, _ property: AnimatableProperty, from: AnimatableValue, to: AnimatableValue) {
        guard !disabled else { return }
        if let group = current {
            group.record(layer, property, from: from, to: to)
        } else if layer.view == nil, let group = CATransaction.implicitGroup() {
            group.record(layer, property, from: from, to: to)
        }
    }
}

extension CALayer {
    /// The value painting uses: the running animations' interpolation, else the model's.
    func presented(_ property: AnimatableProperty, model: AnimatableValue) -> AnimatableValue {
        guard !animatingGroups.isEmpty else { return model }
        // The most recent group animating the property wins.
        for group in animatingGroups.reversed() {
            if let value = group.presented(self, property) { return value }
        }
        return model
    }
}

extension UIKitScene {
    /// Runs the animation groups by `elapsed` seconds; true while any still runs.
    func advanceAnimations(elapsed: Double) -> Bool {
        guard !animationGroups.isEmpty else { return false }
        let finished = animationGroups.filter { !$0.advance(by: elapsed) }
        animationGroups.removeAll { group in finished.contains { $0 === group } }
        for group in finished {
            let completion = group.completion
            group.completion = nil
            completion?(true)
        }
        return !animationGroups.isEmpty
    }

    func add(_ group: UIViewAnimationGroup) {
        animationGroups.append(group)
        setNeedsFrame()
    }
}

extension AnimatableValue {
    var point: CGPoint { if case .point(let p) = self { return p }; return .zero }
    var rect: CGRect { if case .rect(let r) = self { return r }; return .zero }
    var scalar: Double { if case .scalar(let s) = self { return s }; return 0 }
    var transform: CGAffineTransform { if case .transform(let t) = self { return t }; return .identity }
    var color: RGBA? { if case .color(let c) = self { return c }; return nil }
}
