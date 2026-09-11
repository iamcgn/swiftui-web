// UIViewPropertyAnimator (Docs/elements/UIKit/Animation.md): an animation block that can be
// started, paused, scrubbed, reversed, stopped and finished, over the same animation group
// `UIView.animate` records into.

/// The timing curve a property animator plays.
public protocol UITimingCurveProvider {
    var animationCurve: AnimationCurveBox { get }
}

public final class UICubicTimingParameters: UITimingCurveProvider {
    public let animationCurve: AnimationCurveBox
    public init(animationCurve curve: UIView.AnimationCurve) { animationCurve = AnimationCurveBox(curve.animationCurve) }
    init(curve: AnimationCurve) { animationCurve = AnimationCurveBox(curve) }
    public init(controlPoint1 point1: CGPoint, controlPoint2 point2: CGPoint) {
        animationCurve = AnimationCurveBox(.cubic(Double(point1.x), Double(point1.y), Double(point2.x), Double(point2.y)))
    }
}

public final class UISpringTimingParameters: UITimingCurveProvider {
    public let animationCurve: AnimationCurveBox
    public init(dampingRatio ratio: CGFloat, initialVelocity velocity: CGVector = .zero) {
        animationCurve = AnimationCurveBox(.spring(damping: Double(ratio), velocity: Double(velocity.dy)))
    }
    public init() { animationCurve = AnimationCurveBox(.spring(damping: 1, velocity: 0)) }
}

/// The animator's position at the end of a run, for completions.
public enum UIViewAnimatingPosition: Int, Sendable { case end = 0, start, current }
public enum UIViewAnimatingState: Int, Sendable { case inactive = 0, active, stopped }

/// A class that animates changes to views and allows the dynamic modification of those animations.
@MainActor
open class UIViewPropertyAnimator {
    public let duration: Double
    public let timingParameters: (any UITimingCurveProvider)?
    open var delay: Double = 0
    open var isUserInteractionEnabled = true
    open var isManualHitTestingEnabled = false
    open var isInterruptible = true
    open var scrubsLinearly = false
    open var pausesOnCompletion = false
    public private(set) var state: UIViewAnimatingState = .inactive
    public private(set) var isRunning = false

    private var animations: [() -> Void] = []
    private var completions: [(UIViewAnimatingPosition) -> Void] = []
    private var group: UIViewAnimationGroup?
    private var reversed = false

    public init(duration: Double, timingParameters parameters: any UITimingCurveProvider) {
        self.duration = duration
        timingParameters = parameters
    }

    public convenience init(duration: Double, curve: UIView.AnimationCurve, animations: (() -> Void)? = nil) {
        self.init(duration: duration, timingParameters: UICubicTimingParameters(animationCurve: curve))
        if let animations { addAnimations(animations) }
    }

    public convenience init(duration: Double, controlPoint1 point1: CGPoint, controlPoint2 point2: CGPoint, animations: (() -> Void)? = nil) {
        self.init(duration: duration, timingParameters: UICubicTimingParameters(controlPoint1: point1, controlPoint2: point2))
        if let animations { addAnimations(animations) }
    }

    public convenience init(duration: Double, dampingRatio ratio: CGFloat, animations: (() -> Void)? = nil) {
        self.init(duration: duration, timingParameters: UISpringTimingParameters(dampingRatio: ratio))
        if let animations { addAnimations(animations) }
    }

    /// An animator already running.
    public class func runningPropertyAnimator(withDuration duration: Double, delay: Double, options: UIView.AnimationOptions = [],
                                              animations: @escaping () -> Void, completion: ((UIViewAnimatingPosition) -> Void)? = nil) -> UIViewPropertyAnimator {
        let animator = UIViewPropertyAnimator(duration: duration, timingParameters: UICubicTimingParameters(curve: options.curve))
        animator.addAnimations(animations)
        if let completion { animator.addCompletion(completion) }
        animator.startAnimation(afterDelay: delay)
        return animator
    }

    open func addAnimations(_ animation: @escaping () -> Void, delayFactor: CGFloat = 0) {
        animations.append(animation)
        // Added while running: the block joins the group from where it is.
        if let group, state == .active { record(animation, into: group) }
    }

    open func addCompletion(_ completion: @escaping (UIViewAnimatingPosition) -> Void) { completions.append(completion) }

    /// The linear fraction of the run played (0 at the start, 1 at the end); settable while paused.
    open var fractionComplete: CGFloat {
        get { CGFloat(group?.fraction ?? 0) }
        set {
            if group == nil { makeGroup() }
            group?.setFraction(Double(newValue))
            UIKitScene.shared.setNeedsFrame()
        }
    }

    /// Reversing swaps the ends: the animation plays back to where it started.
    open var isReversed: Bool {
        get { reversed }
        set {
            guard newValue != reversed else { return }
            reversed = newValue
            group?.reverse()
            UIKitScene.shared.setNeedsFrame()
        }
    }

    open func startAnimation() { startAnimation(afterDelay: 0) }

    open func startAnimation(afterDelay delay: Double) {
        guard state != .stopped else { return }
        self.delay = delay
        if group == nil { makeGroup() }
        guard let group else { return }
        state = .active
        isRunning = true
        if !UIKitScene.shared.animationGroups.contains(where: { $0 === group }) { UIKitScene.shared.add(group) }
    }

    /// Pausing keeps the presented values on screen; `startAnimation` resumes.
    open func pauseAnimation() {
        guard let group, isRunning else { return }
        isRunning = false
        state = .active
        UIKitScene.shared.animationGroups.removeAll { $0 === group }
    }

    /// Stopping ends the run: `withoutFinishing` leaves the views where the animation had them
    /// (the models take the presented values) and the animator can be finished later.
    open func stopAnimation(_ withoutFinishing: Bool) {
        guard let group else { state = .inactive; return }
        UIKitScene.shared.animationGroups.removeAll { $0 === group }
        isRunning = false
        group.applyPresentedToModels()
        group.removeFromLayers()
        if withoutFinishing {
            state = .stopped
        } else {
            state = .inactive
            self.group = nil
            let completions = self.completions
            self.completions = []
            for completion in completions { completion(.current) }
        }
    }

    /// Finishing a stopped animator puts the views at the start, the end or where they are and runs the completions.
    open func finishAnimation(at finalPosition: UIViewAnimatingPosition) {
        guard let group else { return }
        let previous = UIViewAnimationContext.disabled
        UIViewAnimationContext.disabled = true
        switch finalPosition {
        case .end: group.setFraction(1)
        case .start: group.setFraction(0)
        case .current: break
        }
        UIViewAnimationContext.disabled = previous
        if finalPosition != .current {
            for entry in group.entries { entry.layer?.animatingGroups.append(group) }
            group.applyPresentedToModels()
            group.removeFromLayers()
        }
        self.group = nil
        state = .inactive
        isRunning = false
        let completions = self.completions
        self.completions = []
        let position: UIViewAnimatingPosition = finalPosition == .current ? .current : (reversed ? (finalPosition == .end ? .start : .end) : finalPosition)
        for completion in completions { completion(position) }
        UIKitScene.shared.setNeedsFrame()
    }

    /// Runs the blocks inside a fresh group (the models take the end values; painting interpolates).
    private func makeGroup() {
        let curve = timingParameters?.animationCurve.curve ?? .easeInOut
        let group = UIViewAnimationGroup(duration: duration, delay: delay, curve: curve)
        group.completion = { [weak self] _ in self?.didFinish() }
        for animation in animations { record(animation, into: group) }
        if reversed { group.reverse() }
        self.group = group
    }

    private func record(_ animation: () -> Void, into group: UIViewAnimationGroup) {
        let outer = UIViewAnimationContext.current
        UIViewAnimationContext.current = group
        animation()
        UIViewAnimationContext.current = outer
    }

    private func didFinish() {
        guard state == .active else { return }
        if pausesOnCompletion {
            isRunning = false
            return
        }
        state = .inactive
        isRunning = false
        group = nil
        let completions = self.completions
        self.completions = []
        for completion in completions { completion(reversed ? .start : .end) }
    }
}

extension UIView.AnimationCurve {
    var animationCurve: AnimationCurve {
        switch self {
        case .easeInOut: return .easeInOut
        case .easeIn: return .easeIn
        case .easeOut: return .easeOut
        case .linear: return .linear
        }
    }
}

extension CALayer {
    /// Writes an animatable property's value into the model.
    func apply(_ property: AnimatableProperty, _ value: AnimatableValue) {
        switch property {
        case .opacity: opacity = Float(value.scalar)
        case .position: position = value.point
        case .bounds: bounds = value.rect
        case .transform: transform = CATransform3DMakeAffineTransform(value.transform)
        case .cornerRadius: cornerRadius = CGFloat(value.scalar)
        case .borderWidth: borderWidth = CGFloat(value.scalar)
        case .backgroundColor: backgroundColor = value.color.map { $0.cgColor }
        case .borderColor: borderColor = value.color.map { $0.cgColor }
        case .shadowOpacity: shadowOpacity = Float(value.scalar)
        }
    }
}
