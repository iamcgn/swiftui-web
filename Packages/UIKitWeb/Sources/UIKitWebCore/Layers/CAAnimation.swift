// Core Animation's explicit animations and transactions (Docs/elements/UIKit/Animation.md):
// `CABasicAnimation` / `CAKeyframeAnimation` added to a layer drive its presented value over
// the scene's animation groups without touching the model (removed on completion unless the
// fill mode keeps them); `CATransaction` groups a standalone layer's implicit property
// animations (0.25 s by default), disables them, and runs a completion block.

/// A timing function: the named curves or a cubic bezier's control points.
public final class CAMediaTimingFunction: @unchecked Sendable {
    public let curve: AnimationCurveBox

    public init(name: CAMediaTimingFunctionName) {
        switch name.rawValue {
        case "linear": curve = AnimationCurveBox(.linear)
        case "easeIn": curve = AnimationCurveBox(.easeIn)
        case "easeOut": curve = AnimationCurveBox(.easeOut)
        case "easeInEaseOut": curve = AnimationCurveBox(.easeInOut)
        default: curve = AnimationCurveBox(.cubic(0.25, 0.1, 0.25, 1))
        }
    }

    public init(controlPoints c1x: Float, _ c1y: Float, _ c2x: Float, _ c2y: Float) {
        curve = AnimationCurveBox(.cubic(Double(c1x), Double(c1y), Double(c2x), Double(c2y)))
    }
}

/// The curve behind a timing function (the enum stays internal).
public final class AnimationCurveBox: @unchecked Sendable {
    let curve: AnimationCurve
    init(_ curve: AnimationCurve) { self.curve = curve }
}

public struct CAMediaTimingFunctionName: Hashable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let linear = CAMediaTimingFunctionName(rawValue: "linear")
    public static let easeIn = CAMediaTimingFunctionName(rawValue: "easeIn")
    public static let easeOut = CAMediaTimingFunctionName(rawValue: "easeOut")
    public static let easeInEaseOut = CAMediaTimingFunctionName(rawValue: "easeInEaseOut")
    public static let `default` = CAMediaTimingFunctionName(rawValue: "default")
}

public struct CAMediaTimingFillMode: Hashable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let forwards = CAMediaTimingFillMode(rawValue: "forwards")
    public static let backwards = CAMediaTimingFillMode(rawValue: "backwards")
    public static let both = CAMediaTimingFillMode(rawValue: "both")
    public static let removed = CAMediaTimingFillMode(rawValue: "removed")
}

/// The methods an animation's delegate implements.
@MainActor
public protocol CAAnimationDelegate: AnyObject {
    func animationDidStart(_ anim: CAAnimation)
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool)
}

extension CAAnimationDelegate {
    public func animationDidStart(_ anim: CAAnimation) {}
    public func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {}
}

/// The abstract superclass for animations.
@MainActor
open class CAAnimation {
    open var duration: Double = 0.25
    open var beginTime: Double = 0
    open var timingFunction: CAMediaTimingFunction?
    open var isRemovedOnCompletion = true
    open var fillMode: CAMediaTimingFillMode = .removed
    open var repeatCount: Float = 0
    open var repeatDuration: Double = 0
    open var autoreverses = false
    open var speed: Float = 1
    open weak var delegate: (any CAAnimationDelegate)?

    public init() {}

    /// The group that plays this animation on `layer` (nil when nothing animates).
    func makeGroup(for layer: CALayer) -> UIViewAnimationGroup? { nil }

    /// The curve: the timing function's, else Core Animation's default.
    var curve: AnimationCurve { timingFunction?.curve.curve ?? .cubic(0.25, 0.1, 0.25, 1) }

    func configure(_ group: UIViewAnimationGroup) {
        group.repeatCount = repeatCount > 0 ? Double(repeatCount) : 1
        if repeatDuration > 0, duration > 0 { group.repeatCount = repeatDuration / duration }
        group.autoreverses = autoreverses
        group.retainsFinalValue = !isRemovedOnCompletion && (fillMode == .forwards || fillMode == .both)
    }
}

/// An animation of one of a layer's properties, named by key path.
@MainActor
open class CAPropertyAnimation: CAAnimation {
    public let keyPath: String?
    open var isAdditive = false
    open var isCumulative = false

    public init(keyPath path: String?) {
        keyPath = path
        super.init()
    }
}

/// An animation from one value to another.
@MainActor
open class CABasicAnimation: CAPropertyAnimation {
    open var fromValue: Any?
    open var toValue: Any?
    open var byValue: Any?

    override func makeGroup(for layer: CALayer) -> UIViewAnimationGroup? {
        guard let keyPath, let property = LayerKeyPath(keyPath) else { return nil }
        let model = property.value(of: layer)
        let from = fromValue.flatMap { property.value(from: $0, model: model) } ?? property.current(of: layer)
        var to = toValue.flatMap { property.value(from: $0, model: model) } ?? model
        if toValue == nil, let by = byValue.flatMap({ property.value(from: $0, model: model) }) { to = from.adding(by) }
        let group = UIViewAnimationGroup(duration: duration, delay: max(0, beginTime), curve: curve)
        configure(group)
        group.record(layer, property.property, from: from, to: to)
        return group
    }
}

/// An animation through a series of values (approximate: the presented value runs from the
/// first to the last over the duration).
@MainActor
open class CAKeyframeAnimation: CAPropertyAnimation {
    open var values: [Any]?
    open var keyTimes: [Double]?
    open var path: Path?
    open var calculationMode = "linear"

    override func makeGroup(for layer: CALayer) -> UIViewAnimationGroup? {
        guard let keyPath, let property = LayerKeyPath(keyPath), let values, let first = values.first, let last = values.last else { return nil }
        let model = property.value(of: layer)
        guard let from = property.value(from: first, model: model), let to = property.value(from: last, model: model) else { return nil }
        let group = UIViewAnimationGroup(duration: duration, delay: max(0, beginTime), curve: curve)
        configure(group)
        group.record(layer, property.property, from: from, to: to)
        return group
    }
}

/// Several animations played together.
@MainActor
open class CAAnimationGroup: CAAnimation {
    open var animations: [CAAnimation]?
}

/// A layer property an animation names: `opacity`, `position`, `position.x` / `.y`, `bounds`,
/// `bounds.size.width` / `.height`, `transform`, `transform.scale`, `transform.rotation` (`.z`),
/// `cornerRadius`, `borderWidth`, `backgroundColor`, `borderColor`, `shadowOpacity`.
struct LayerKeyPath {
    enum Component { case whole, x, y, width, height, scale, rotation }
    let property: AnimatableProperty
    let component: Component

    init?(_ keyPath: String) {
        switch keyPath {
        case "opacity": property = .opacity; component = .whole
        case "position": property = .position; component = .whole
        case "position.x": property = .position; component = .x
        case "position.y": property = .position; component = .y
        case "bounds": property = .bounds; component = .whole
        case "bounds.size.width": property = .bounds; component = .width
        case "bounds.size.height": property = .bounds; component = .height
        case "transform": property = .transform; component = .whole
        case "transform.scale", "transform.scale.xy": property = .transform; component = .scale
        case "transform.rotation", "transform.rotation.z": property = .transform; component = .rotation
        case "cornerRadius": property = .cornerRadius; component = .whole
        case "borderWidth": property = .borderWidth; component = .whole
        case "backgroundColor": property = .backgroundColor; component = .whole
        case "borderColor": property = .borderColor; component = .whole
        case "shadowOpacity": property = .shadowOpacity; component = .whole
        default: return nil
        }
    }

    /// The layer's model value of the property.
    @MainActor func value(of layer: CALayer) -> AnimatableValue {
        switch property {
        case .opacity: return .scalar(Double(layer.opacity))
        case .position: return .point(layer.position)
        case .bounds: return .rect(layer.bounds)
        case .transform: return .transform(layer.transform.affine)
        case .cornerRadius: return .scalar(Double(layer.cornerRadius))
        case .borderWidth: return .scalar(Double(layer.borderWidth))
        case .backgroundColor: return .color(layer.backgroundColor.flatMap { RGBA(cgColor: $0) })
        case .borderColor: return .color(layer.borderColor.flatMap { RGBA(cgColor: $0) })
        case .shadowOpacity: return .scalar(Double(layer.shadowOpacity))
        }
    }

    /// The value painting shows now (a running animation's, else the model's).
    @MainActor func current(of layer: CALayer) -> AnimatableValue {
        layer.presented(property, model: value(of: layer))
    }

    /// An animation value (a number, point, rect, colour or transform) as the property's value,
    /// a component (`position.x`, `transform.scale`) applied to the model.
    @MainActor func value(from any: Any, model: AnimatableValue) -> AnimatableValue? {
        let number: Double? = {
            switch any {
            case let value as Double: return value
            case let value as CGFloat: return Double(value)
            case let value as Float: return Double(value)
            case let value as Int: return Double(value)
            default: return nil
            }
        }()
        switch component {
        case .whole:
            switch property {
            case .opacity, .cornerRadius, .borderWidth, .shadowOpacity:
                return number.map { .scalar($0) }
            case .position:
                return (any as? CGPoint).map { .point($0) }
            case .bounds:
                return (any as? CGRect).map { .rect($0) }
            case .transform:
                if let transform = any as? CATransform3D { return .transform(transform.affine) }
                return (any as? CGAffineTransform).map { .transform($0) }
            case .backgroundColor, .borderColor:
                return Self.color(any).map { .color($0) }
            }
        case .x: return number.map { .point(CGPoint(x: CGFloat($0), y: model.point.y)) }
        case .y: return number.map { .point(CGPoint(x: model.point.x, y: CGFloat($0))) }
        case .width: return number.map { .rect(CGRect(origin: model.rect.origin, size: CGSize(width: CGFloat($0), height: model.rect.height))) }
        case .height: return number.map { .rect(CGRect(origin: model.rect.origin, size: CGSize(width: model.rect.width, height: CGFloat($0)))) }
        case .scale: return number.map { .transform(model.transform.scaledBy(x: CGFloat($0), y: CGFloat($0))) }
        case .rotation: return number.map { .transform(model.transform.rotated(by: CGFloat($0))) }
        }
    }
}

extension LayerKeyPath {
    /// A colour value: a `UIColor`, or a `CGColor` (a CoreFoundation type on Apple platforms,
    /// where `as?` cannot test it; the type id can).
    @MainActor static func color(_ any: Any) -> RGBA? {
        if let color = any as? UIColor { return color.rgba(for: .light) }
        #if canImport(CoreGraphics)
        if CFGetTypeID(any as CFTypeRef) == CGColor.typeID { return RGBA(cgColor: any as! CGColor) }
        return nil
        #else
        return (any as? CGColor).flatMap { RGBA(cgColor: $0) }
        #endif
    }
}

extension AnimatableValue {
    /// `byValue`: the sum with another value of the same kind.
    func adding(_ other: AnimatableValue) -> AnimatableValue {
        switch (self, other) {
        case (.scalar(let a), .scalar(let b)): return .scalar(a + b)
        case (.point(let a), .point(let b)): return .point(CGPoint(x: a.x + b.x, y: a.y + b.y))
        case (.rect(let a), .rect(let b)): return .rect(CGRect(x: a.minX + b.minX, y: a.minY + b.minY, width: a.width + b.width, height: a.height + b.height))
        default: return other
        }
    }
}

extension CALayer {
    /// Adds an explicit animation: its presented value runs from the start; the model stays.
    public func add(_ anim: CAAnimation, forKey key: String?) {
        guard let group = anim.makeGroup(for: self) else { return }
        let name = key ?? "animation\(explicitAnimations.count)"
        removeAnimation(forKey: name)
        explicitAnimations[name] = (anim, group)
        anim.delegate?.animationDidStart(anim)
        group.completion = { [weak self, weak anim, weak group] finished in
            guard let anim else { return }
            if let self, let group, self.explicitAnimations[name]?.group === group, !group.retainsFinalValue { self.explicitAnimations.removeValue(forKey: name) }
            anim.delegate?.animationDidStop(anim, finished: finished)
        }
        UIKitScene.shared.add(group)
    }

    public func removeAnimation(forKey key: String) {
        guard let entry = explicitAnimations.removeValue(forKey: key) else { return }
        entry.group.removeFromLayers()
        entry.group.completion = nil
        UIKitScene.shared.animationGroups.removeAll { $0 === entry.group }
        entry.animation.delegate?.animationDidStop(entry.animation, finished: false)
        setNeedsDisplay()
    }

    public func removeAllAnimations() {
        for key in Array(explicitAnimations.keys) { removeAnimation(forKey: key) }
    }

    public func animation(forKey key: String) -> CAAnimation? { explicitAnimations[key]?.animation }
    public func animationKeys() -> [String]? { explicitAnimations.isEmpty ? nil : Array(explicitAnimations.keys) }
}

/// A grouping of Core Animation property changes: standalone layers' implicit animations run
/// with the transaction's duration (0.25 s by default) unless actions are disabled; the
/// completion block runs when they end. Changes outside any transaction join an implicit one
/// the scene commits at its next frame, as Core Animation commits at the end of the run loop.
@MainActor
public enum CATransaction {
    final class Transaction {
        var duration: Double = 0.25
        var disableActions = false
        var timingFunction: CAMediaTimingFunction?
        var completion: (() -> Void)?
        var group: UIViewAnimationGroup?
        var implicit = false
    }

    private static var stack: [Transaction] = []
    private static var pending: Transaction?

    public static func begin() { stack.append(Transaction()) }

    public static func commit() {
        guard let transaction = stack.popLast() else { return }
        finish(transaction)
    }

    /// Commits every open transaction (and the implicit one).
    public static func flush() {
        while !stack.isEmpty { commit() }
        commitImplicit()
    }

    public static func animationDuration() -> Double { stack.last?.duration ?? 0.25 }
    public static func setAnimationDuration(_ duration: Double) { stack.last?.duration = duration }
    public static func disableActions() -> Bool { stack.last?.disableActions ?? false }
    public static func setDisableActions(_ flag: Bool) { stack.last?.disableActions = flag }
    public static func animationTimingFunction() -> CAMediaTimingFunction? { stack.last?.timingFunction }
    public static func setAnimationTimingFunction(_ function: CAMediaTimingFunction?) { stack.last?.timingFunction = function }
    public static func completionBlock() -> (() -> Void)? { stack.last?.completion }
    public static func setCompletionBlock(_ block: (() -> Void)?) { stack.last?.completion = block }

    /// The group a standalone layer's property change joins now, if actions are enabled.
    static func implicitGroup() -> UIViewAnimationGroup? {
        let transaction: Transaction
        if let open = stack.last {
            transaction = open
        } else {
            if pending == nil {
                let implicit = Transaction()
                implicit.implicit = true
                pending = implicit
                UIKitScene.shared.setNeedsFrame()
            }
            transaction = pending!
        }
        guard !transaction.disableActions else { return nil }
        if transaction.group == nil {
            transaction.group = UIViewAnimationGroup(duration: transaction.duration, delay: 0, curve: transaction.timingFunction?.curve.curve ?? .cubic(0.25, 0.1, 0.25, 1))
        }
        return transaction.group
    }

    /// The scene commits the implicit transaction before advancing a frame.
    static func commitImplicit() {
        guard let transaction = pending else { return }
        pending = nil
        finish(transaction)
    }

    private static func finish(_ transaction: Transaction) {
        if let group = transaction.group, !group.entries.isEmpty {
            let completion = transaction.completion
            group.completion = { _ in completion?() }
            UIKitScene.shared.add(group)
        } else if let completion = transaction.completion {
            UIKitScene.shared.schedule(after: 0) { completion() }
        }
    }
}
