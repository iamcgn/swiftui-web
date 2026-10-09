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
    private(set) var duration: Double
    let delay: Double
    private(set) var curve: AnimationCurve
    var completion: ((Bool) -> Void)?
    private(set) var elapsed: Double = 0
    /// Core Animation timing: how many times the animation plays (`.infinity` for ever) and
    /// whether it plays back to the start each time (`CAAnimation.repeatCount`, `autoreverses`).
    var repeatCount: Double = 1
    var autoreverses = false
    /// A Core Animation that keeps its final value (`fillMode` forwards without removal):
    /// finished, it stays on its layers at progress 1 until removed.
    var retainsFinalValue = false
    /// A property animator's group runs backwards after `isReversed` (the entries swap ends).
    private(set) var isReversed = false
    struct Entry {
        weak var layer: CALayer?
        let property: AnimatableProperty
        var from: AnimatableValue
        var to: AnimatableValue
        /// The entry's window as fractions of the group's cycle (a grouped child's own
        /// beginTime and duration; an animator block added with a delay factor).
        var start: Double = 0
        var end: Double = 1
        /// The entry's own curve, when it differs from the group's (a grouped child's).
        var curve: AnimationCurve? = nil
        /// Keyframes (time 0…1, value) interpolated piecewise instead of `from` → `to`;
        /// `discrete` holds each value until the next time.
        var keyframes: [(Double, AnimatableValue)]? = nil
        var discrete = false
        /// An additive animation: the interpolated value is added to the model's.
        var additive = false
    }
    private(set) var entries: [Entry] = []
    /// Scrubbing linearly (`UIViewPropertyAnimator.scrubsLinearly`): the curve is skipped.
    var scrubsLinearly = false

    init(duration: Double, delay: Double, curve: AnimationCurve) {
        self.duration = duration
        self.delay = delay
        self.curve = curve
    }

    /// The eased progress now (0 before the delay ends, 1 when done); a repeating animation
    /// cycles, an autoreversing one goes back each odd cycle.
    var progress: Double { scrubsLinearly ? cycleFraction : curve.value(at: cycleFraction) }

    /// The linear position in the current cycle (0…1; back from 1 on an autoreversing odd cycle).
    var cycleFraction: Double {
        guard duration > 0 else { return elapsed >= delay ? 1 : 0 }
        let time = max(0, elapsed - delay)
        if isFinished { return autoreverses ? 0 : 1 }
        let cycle = time / duration
        var fraction = cycle - cycle.rounded(.down)
        if autoreverses, Int(cycle.rounded(.down)) % 2 == 1 { fraction = 1 - fraction }
        return min(1, max(0, fraction))
    }

    /// The whole run: the duration times the repeats (twice each when autoreversing).
    var totalDuration: Double {
        guard repeatCount.isFinite else { return .infinity }
        return duration * max(1, repeatCount) * (autoreverses ? 2 : 1)
    }

    var isFinished: Bool { elapsed >= delay + totalDuration }

    /// `UIView.animate`'s `.beginFromCurrentState`: a property already animating starts from
    /// its presented value rather than the model's.
    var beginsFromCurrentState = false
    /// Where entries recorded from now on start (an animator block added with a delay factor).
    var entryStart: Double = 0

    func record(_ layer: CALayer, _ property: AnimatableProperty, from: AnimatableValue, to: AnimatableValue) {
        if let index = entries.firstIndex(where: { $0.layer === layer && $0.property == property }) {
            entries[index].to = to
        } else {
            var start = from
            if beginsFromCurrentState, let running = layer.animatingGroups.last(where: { $0 !== self }), let presented = running.presented(layer, property, model: from) { start = presented }
            var entry = Entry(layer: layer, property: property, from: start, to: to)
            entry.start = entryStart
            entries.append(entry)
        }
        layer.animatingGroups.append(self)
    }

    /// Adds an entry with its own timing (a grouped Core Animation's child).
    func add(_ entry: Entry) {
        entries.append(entry)
        entry.layer?.animatingGroups.append(self)
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

    /// Scrubbing (`UIViewPropertyAnimator.fractionComplete`): the clock set to a fraction of the run.
    func setFraction(_ fraction: Double) {
        elapsed = delay + min(1, max(0, fraction)) * totalDuration
    }

    /// The linear fraction of the run played so far (before easing).
    var fraction: Double {
        guard totalDuration > 0, totalDuration.isFinite else { return isFinished ? 1 : 0 }
        return min(1, max(0, (elapsed - delay) / totalDuration))
    }

    /// Reverses the direction: the ends swap and the clock mirrors, so the presented value
    /// continues from where it is.
    func reverse() {
        isReversed.toggle()
        let played = fraction
        for index in entries.indices { let from = entries[index].from; entries[index].from = entries[index].to; entries[index].to = from }
        setFraction(1 - played)
    }

    /// Continues from the presented values with a new curve over `duration` seconds
    /// (`UIViewPropertyAnimator.continueAnimation`): the entries restart from where they show.
    func restart(curve: AnimationCurve, duration: Double) {
        for index in entries.indices {
            guard let layer = entries[index].layer, let value = presented(layer, entries[index].property, model: entries[index].additive ? layer.modelValue(entries[index].property) : nil) else { continue }
            entries[index].from = value
            entries[index].keyframes = nil
            entries[index].start = 0
            entries[index].end = 1
            entries[index].curve = nil
        }
        self.curve = curve
        self.duration = max(0.001, duration)
        elapsed = delay
        scrubsLinearly = false
    }

    /// Writes the presented values into the layers' models (a stopped animator holds where it is).
    func applyPresentedToModels() {
        let previous = UIViewAnimationContext.disabled
        UIViewAnimationContext.disabled = true
        defer { UIViewAnimationContext.disabled = previous }
        for entry in entries {
            guard let layer = entry.layer, let value = presented(layer, entry.property, model: entry.additive ? layer.modelValue(entry.property) : nil) else { continue }
            layer.apply(entry.property, value)
        }
    }

    /// The presented value of a layer's property, if this group animates it (`model` is the
    /// layer's own value, which an additive entry adds to).
    func presented(_ layer: CALayer, _ property: AnimatableProperty, model: AnimatableValue? = nil) -> AnimatableValue? {
        guard let entry = entries.first(where: { $0.layer === layer && $0.property == property }) else { return nil }
        // The entry's own window of the cycle, eased by its curve (or the group's).
        let cycle = cycleFraction
        let local = entry.end > entry.start ? min(1, max(0, (cycle - entry.start) / (entry.end - entry.start))) : 1
        let eased = scrubsLinearly ? local : (entry.curve ?? curve).value(at: local)
        let value: AnimatableValue
        if let keyframes = entry.keyframes, let first = keyframes.first, let last = keyframes.last {
            if local <= first.0 { value = first.1 } else if local >= last.0 { value = last.1 } else {
                var result = last.1
                for index in 1..<keyframes.count where local < keyframes[index].0 {
                    let (t0, v0) = keyframes[index - 1], (t1, v1) = keyframes[index]
                    result = entry.discrete ? v0 : v0.interpolated(to: v1, t1 > t0 ? (local - t0) / (t1 - t0) : 1)
                    break
                }
                value = result
            }
        } else {
            value = entry.from.interpolated(to: entry.to, eased)
        }
        if entry.additive, let model { return model.adding(value) }
        return value
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
        } else if layer.view == nil, layer.isCommitted, let group = CATransaction.implicitGroup() {
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
            if let value = group.presented(self, property, model: model) { return value }
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
