// SceneKit's actions and Core Animation animations on nodes (Docs/elements/SceneKit.md).
// Actions change the node's own properties a frame at a time, as SceneKit's do; animations
// are worked out when the scene is drawn and leave the node's properties alone.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI
import UIKit

public enum SCNActionTimingMode: Int, Sendable { case linear = 0, easeIn = 1, easeOut = 2, easeInEaseOut = 3 }

/// A simple, reusable animation that changes attributes of any node you attach it to.
@preconcurrency @MainActor
open class SCNAction {
    indirect enum Kind {
        case wait
        case run(@MainActor (SCNNode) -> Void)
        case custom(@MainActor (SCNNode, CGFloat) -> Void)
        case rotateBy(SCNVector3)
        case rotateAround(SCNVector3, Float)
        case rotateTo(SCNVector3)
        case moveBy(SCNVector3)
        case moveTo(SCNVector3)
        case scaleBy(Float)
        case scaleTo(Float)
        case fadeBy(CGFloat)
        case fadeTo(CGFloat)
        case hidden(Bool)
        case remove
        case sequence([SCNAction])
        case group([SCNAction])
        case repeatCount(SCNAction, Int)
        case forever(SCNAction)
        case playAudio
    }

    let kind: Kind
    /// Seconds; a sequence's is the sum of its actions', a group's the longest.
    open var duration: TimeInterval
    open var timingMode: SCNActionTimingMode = .linear
    open var timingFunction: (@Sendable (Float) -> Float)?
    open var speed: CGFloat = 1

    init(_ kind: Kind, duration: TimeInterval) {
        self.kind = kind
        self.duration = duration
    }

    public static func wait(duration: TimeInterval) -> SCNAction { SCNAction(.wait, duration: duration) }
    public static func wait(duration: TimeInterval, withRange range: TimeInterval) -> SCNAction {
        SCNAction(.wait, duration: max(0, duration + Double.random(in: -range / 2...range / 2)))
    }
    public static func run(_ block: @escaping @MainActor (SCNNode) -> Void) -> SCNAction { SCNAction(.run(block), duration: 0) }
    public static func run(_ block: @escaping @MainActor (SCNNode) -> Void, queue: DispatchQueue) -> SCNAction { run(block) }
    public static func customAction(duration seconds: CGFloat, action block: @escaping @MainActor (SCNNode, CGFloat) -> Void) -> SCNAction {
        SCNAction(.custom(block), duration: Double(seconds))
    }

    public static func rotateBy(x: CGFloat, y: CGFloat, z: CGFloat, duration: TimeInterval) -> SCNAction {
        SCNAction(.rotateBy(SCNVector3(Float(x), Float(y), Float(z))), duration: duration)
    }
    public static func rotate(by angle: CGFloat, around axis: SCNVector3, duration: TimeInterval) -> SCNAction {
        SCNAction(.rotateAround(axis, Float(angle)), duration: duration)
    }
    public static func rotateTo(x: CGFloat, y: CGFloat, z: CGFloat, duration: TimeInterval) -> SCNAction {
        SCNAction(.rotateTo(SCNVector3(Float(x), Float(y), Float(z))), duration: duration)
    }
    public static func rotateTo(x: CGFloat, y: CGFloat, z: CGFloat, duration: TimeInterval, usesShortestUnitArc: Bool) -> SCNAction {
        rotateTo(x: x, y: y, z: z, duration: duration)
    }
    public static func rotate(toAxisAngle axisAngle: SCNVector4, duration: TimeInterval) -> SCNAction {
        let euler = _Quaternion(axis: SCNVector3(axisAngle.x, axisAngle.y, axisAngle.z), angle: axisAngle.w).euler
        return SCNAction(.rotateTo(euler), duration: duration)
    }
    public static func moveBy(x: CGFloat, y: CGFloat, z: CGFloat, duration: TimeInterval) -> SCNAction {
        SCNAction(.moveBy(SCNVector3(Float(x), Float(y), Float(z))), duration: duration)
    }
    public static func move(by delta: SCNVector3, duration: TimeInterval) -> SCNAction { SCNAction(.moveBy(delta), duration: duration) }
    public static func move(to location: SCNVector3, duration: TimeInterval) -> SCNAction { SCNAction(.moveTo(location), duration: duration) }
    public static func scale(by scale: CGFloat, duration: TimeInterval) -> SCNAction { SCNAction(.scaleBy(Float(scale)), duration: duration) }
    public static func scale(to scale: CGFloat, duration: TimeInterval) -> SCNAction { SCNAction(.scaleTo(Float(scale)), duration: duration) }
    public static func fadeIn(duration: TimeInterval) -> SCNAction { SCNAction(.fadeTo(1), duration: duration) }
    public static func fadeOut(duration: TimeInterval) -> SCNAction { SCNAction(.fadeTo(0), duration: duration) }
    public static func fadeOpacity(by factor: CGFloat, duration: TimeInterval) -> SCNAction { SCNAction(.fadeBy(factor), duration: duration) }
    public static func fadeOpacity(to opacity: CGFloat, duration: TimeInterval) -> SCNAction { SCNAction(.fadeTo(opacity), duration: duration) }
    public static func hide() -> SCNAction { SCNAction(.hidden(true), duration: 0) }
    public static func unhide() -> SCNAction { SCNAction(.hidden(false), duration: 0) }
    public static func removeFromParentNode() -> SCNAction { SCNAction(.remove, duration: 0) }
    public static func playAudio(_ source: SCNAudioSource, waitForCompletion wait: Bool) -> SCNAction { SCNAction(.playAudio, duration: 0) }

    public static func sequence(_ actions: [SCNAction]) -> SCNAction {
        SCNAction(.sequence(actions), duration: actions.reduce(0) { $0 + $1.duration })
    }
    public static func group(_ actions: [SCNAction]) -> SCNAction {
        SCNAction(.group(actions), duration: actions.map(\.duration).max() ?? 0)
    }
    public static func `repeat`(_ action: SCNAction, count: Int) -> SCNAction {
        SCNAction(.repeatCount(action, count), duration: action.duration * Double(max(count, 0)))
    }
    public static func repeatForever(_ action: SCNAction) -> SCNAction { SCNAction(.forever(action), duration: .infinity) }

    /// The action played backwards (the relative ones undone; the absolute ones as they are).
    open func reversed() -> SCNAction {
        let reversed: SCNAction
        switch kind {
        case .rotateBy(let v): reversed = SCNAction(.rotateBy(v * -1), duration: duration)
        case .rotateAround(let axis, let angle): reversed = SCNAction(.rotateAround(axis, -angle), duration: duration)
        case .moveBy(let v): reversed = SCNAction(.moveBy(v * -1), duration: duration)
        case .scaleBy(let s): reversed = SCNAction(.scaleBy(s != 0 ? 1 / s : 1), duration: duration)
        case .fadeBy(let f): reversed = SCNAction(.fadeBy(-f), duration: duration)
        case .sequence(let actions): reversed = .sequence(actions.reversed().map { $0.reversed() })
        case .group(let actions): reversed = .group(actions.map { $0.reversed() })
        case .repeatCount(let action, let n): reversed = SCNAction.`repeat`(action.reversed(), count: n)
        case .forever(let action): reversed = .repeatForever(action.reversed())
        default: reversed = SCNAction(kind, duration: duration)
        }
        reversed.timingMode = timingMode
        reversed.speed = speed
        return reversed
    }

    open func copy() -> Any { self }

    /// The eased fraction for a linear one.
    func eased(_ t: Double) -> Double {
        let t = min(max(t, 0), 1)
        if let timingFunction { return Double(timingFunction(Float(t))) }
        switch timingMode {
        case .linear: return t
        case .easeIn: return t * t
        case .easeOut: return 1 - (1 - t) * (1 - t)
        case .easeInEaseOut: return t < 0.5 ? 2 * t * t : 1 - 2 * (1 - t) * (1 - t)
        }
    }

    func makeRunner() -> _ActionRunner { _ActionRunner(self) }
}

/// A sound for `playAudio(_:waitForCompletion:)`; a page plays none.
@preconcurrency @MainActor
open class SCNAudioSource {
    open var volume: Float = 1
    open var isPositional = true
    open var loops = false
    open var shouldStream = false
    public init?(fileNamed name: String) {}
    public init?(named name: String) {}
    public init(url: URL) {}
    open func load() {}
}

/// Plays one action on one node: the elapsed time, and the values an absolute action starts from.
@MainActor
final class _ActionRunner {
    let action: SCNAction
    private var elapsed: Double = 0
    private var started = false
    private var startEuler = SCNVector3(), startPosition = SCNVector3(), startScale = SCNVector3(1, 1, 1)
    private var startOpacity: CGFloat = 1
    private var children: [_ActionRunner] = []
    private var index = 0
    private var iteration = 0

    init(_ action: SCNAction) { self.action = action }

    /// Advances by `dt` seconds; the time left over once the action has finished, or nil while it runs.
    func step(_ node: SCNNode, _ dt: Double) -> Double? {
        let dt = dt * Double(action.speed)
        switch action.kind {
        case .sequence(let actions):
            var left = dt
            while index < actions.count {
                if children.count <= index { children.append(actions[index].makeRunner()) }
                guard let rest = children[index].step(node, left) else { return nil }
                left = rest
                index += 1
            }
            return left
        case .group(let actions):
            if children.isEmpty { children = actions.map { $0.makeRunner() } }
            var finished = true, left = dt
            for (i, child) in children.enumerated() where !(doneChildren.contains(i)) {
                if let rest = child.step(node, dt) { doneChildren.insert(i); left = min(left, rest) } else { finished = false }
            }
            return finished ? left : nil
        case .repeatCount(let inner, let count):
            var left = dt
            var passes = 0
            while iteration < count {
                if children.isEmpty { children = [inner.makeRunner()] }
                guard let rest = children[0].step(node, left) else { return nil }
                children.removeAll()
                iteration += 1
                passes += 1
                left = rest
                if inner.duration <= 0, passes > 1000 { break }
            }
            return left
        case .forever(let inner):
            var left = dt
            var passes = 0
            while true {
                if children.isEmpty { children = [inner.makeRunner()] }
                guard let rest = children[0].step(node, left) else { return nil }
                children.removeAll()
                passes += 1
                // An action that takes no time runs once a frame.
                if inner.duration <= 0 || passes > 1000 { return nil }
                left = rest
            }
        default:
            return stepLeaf(node, dt)
        }
    }

    private var doneChildren = Set<Int>()

    private func stepLeaf(_ node: SCNNode, _ dt: Double) -> Double? {
        if !started {
            started = true
            startEuler = node.eulerAngles; startPosition = node.position; startScale = node.scale; startOpacity = node.opacity
        }
        let duration = action.duration
        let before = duration > 0 ? action.eased(elapsed / duration) : 0
        let total = elapsed + dt
        elapsed = min(total, duration)
        let after = duration > 0 ? action.eased(elapsed / duration) : 1
        let delta = Float(after - before)
        switch action.kind {
        case .wait: break
        case .run(let block): block(node)
        case .custom(let block): block(node, CGFloat(elapsed))
        case .rotateBy(let v): node.quaternion = (_Quaternion(euler: v * delta) * node.quaternion).normalized
        case .rotateAround(let axis, let angle): node.quaternion = (_Quaternion(axis: axis, angle: angle * delta) * node.quaternion).normalized
        case .rotateTo(let v): node.eulerAngles = startEuler + (v - startEuler) * Float(after)
        case .moveBy(let v): node.position = node.position + v * delta
        case .moveTo(let v): node.position = startPosition + (v - startPosition) * Float(after)
        case .scaleBy(let s): node.scale = startScale * (1 + (s - 1) * Float(after))
        case .scaleTo(let s): node.scale = startScale + (SCNVector3(s, s, s) - startScale) * Float(after)
        case .fadeBy(let f): node.opacity += f * CGFloat(delta)
        case .fadeTo(let o): node.opacity = startOpacity + (o - startOpacity) * CGFloat(after)
        case .hidden(let hidden): node.isHidden = hidden
        case .remove: node.removeFromParentNode()
        case .playAudio: break
        case .sequence, .group, .repeatCount, .forever: break
        }
        return total >= duration ? total - duration : nil
    }
}

extension SCNNode {
    open func runAction(_ action: SCNAction) { runAction(action, forKey: nil, completionHandler: nil) }

    open func runAction(_ action: SCNAction, completionHandler block: (@MainActor () -> Void)?) {
        runAction(action, forKey: nil, completionHandler: block)
    }

    open func runAction(_ action: SCNAction, forKey key: String?) { runAction(action, forKey: key, completionHandler: nil) }

    open func runAction(_ action: SCNAction, forKey key: String?, completionHandler block: (@MainActor () -> Void)?) {
        if let key { actions.removeAll { $0.key == key } }
        actions.append((key, action.makeRunner(), block))
        _SceneClock.shared.wake()
    }

    open func removeAction(forKey key: String) { actions.removeAll { $0.key == key } }
    open func removeAllActions() { actions.removeAll() }
    open func action(forKey key: String) -> SCNAction? { actions.first { $0.key == key }?.runner.action }
    open var hasActions: Bool { !actions.isEmpty }
    open var actionKeys: [String] { actions.compactMap(\.key) }

    /// Steps this node's actions and its subtree's by `dt` seconds.
    func stepActions(_ dt: Double) {
        if !actions.isEmpty {
            let running = actions
            var finished: [ObjectIdentifier] = []
            for entry in running {
                if entry.runner.step(self, dt) != nil {
                    finished.append(ObjectIdentifier(entry.runner))
                    entry.completion?()
                }
            }
            if !finished.isEmpty { actions.removeAll { finished.contains(ObjectIdentifier($0.runner)) } }
        }
        for child in childNodes { child.stepActions(dt) }
    }

    /// Whether anything below moves on its own: an action or an animation.
    var isAnimating: Bool {
        !actions.isEmpty || !animations.isEmpty || childNodes.contains { $0.isAnimating }
    }

    /// Applies the constraints, the parents' first.
    func applyConstraints() {
        for constraint in constraints ?? [] { constraint.apply(to: self) }
        for child in childNodes { child.applyConstraints() }
    }
}

// MARK: - Core Animation on nodes

/// The fraction through an animation at `time`, and whether it applies at all.
@MainActor
private func _progress(_ animation: CAAnimation, start: Double, time: Double) -> Double? {
    let local = (time - start - animation.beginTime) * Double(animation.speed)
    let duration = animation.duration > 0 ? animation.duration : 0.25
    guard local >= 0 else { return nil }
    let cycles = local / duration
    let repeats = animation.repeatDuration > 0 ? animation.repeatDuration / duration : Double(animation.repeatCount > 0 ? animation.repeatCount : 1)
    let total = animation.autoreverses ? repeats * 2 : repeats
    if cycles >= total {
        guard !animation.isRemovedOnCompletion else { return nil }
        return animation.autoreverses ? 0 : 1
    }
    var f = cycles - cycles.rounded(.down)
    if animation.autoreverses, Int(cycles.rounded(.down)) % 2 == 1 { f = 1 - f }
    return f
}

/// A value from an animation's from or to: a vector, a quaternion or a number, boxed or not.
private func _vector4(_ value: Any?) -> SCNVector4? {
    switch value {
    case let v as SCNVector4: return v
    case let v as NSValue: return v.scnVector4Value
    default: return nil
    }
}

private func _vector3(_ value: Any?) -> SCNVector3? {
    switch value {
    case let v as SCNVector3: return v
    case let v as NSValue: return v.scnVector3Value
    default: return nil
    }
}

/// The basic and keyframe animations of a node (a group's children, each in its window).
@MainActor
private func _flatten(_ animation: CAAnimation, start: Double, time: Double) -> [(CAPropertyAnimation, Double)] {
    if let group = animation as? CAAnimationGroup {
        guard let f = _progress(group, start: start, time: time) else { return [] }
        let groupTime = f * group.duration
        return (group.animations ?? []).flatMap { child -> [(CAPropertyAnimation, Double)] in
            guard let property = child as? CAPropertyAnimation, let g = _progress(child, start: 0, time: groupTime) else { return [] }
            return [(property, g)]
        }
    }
    guard let property = animation as? CAPropertyAnimation, let f = _progress(animation, start: start, time: time) else { return [] }
    return [(property, f)]
}

/// The from and to of a basic animation, or the two keyframes around `f` and the fraction between them.
@MainActor
private func _segment(_ animation: CAPropertyAnimation, _ f: Double) -> (from: Any?, to: Any?, by: Any?, t: Double) {
    if let basic = animation as? CABasicAnimation { return (basic.fromValue, basic.toValue, basic.byValue, f) }
    if let keyframes = animation as? CAKeyframeAnimation, let values = keyframes.values, !values.isEmpty {
        guard values.count > 1 else { return (values[0], values[0], nil, 0) }
        let times = keyframes.keyTimes?.count == values.count ? keyframes.keyTimes! : values.indices.map { Double($0) / Double(values.count - 1) }
        var i = 0
        while i < values.count - 2 && f > times[i + 1] { i += 1 }
        let span = times[i + 1] - times[i]
        let t = span > 0 ? (f - times[i]) / span : 1
        return (values[i], values[i + 1], nil, keyframes.calculationMode == "discrete" ? 0 : min(max(t, 0), 1))
    }
    return (nil, nil, nil, f)
}

@MainActor
func _applyAnimations(of node: SCNNode, at time: Double, position: inout SCNVector3, rotation: inout _Quaternion, scale: inout SCNVector3) {
    for entry in node.animations {
        guard let animation = entry.animation as? CAAnimation else { continue }
        for (property, f) in _flatten(animation, start: entry.start, time: time) {
            guard let keyPath = property.keyPath else { continue }
            let (from, to, by, t) = _segment(property, f)
            let parts = keyPath.split(separator: ".").map(String.init)
            switch parts[0] {
            case "rotation":
                let model = rotation.axisAngle
                let a = _vector4(from) ?? model
                let b = _vector4(to) ?? _vector4(by).map { SCNVector4(a.x, a.y, a.z, a.w + $0.w) } ?? model
                let axis = SCNVector3(b.x, b.y, b.z).length > 0 ? SCNVector3(b.x, b.y, b.z) : SCNVector3(a.x, a.y, a.z)
                let angle = a.w + (b.w - a.w) * Float(t)
                let q = _Quaternion(axis: axis, angle: angle)
                rotation = property.isAdditive ? (rotation * q).normalized : q
            case "orientation":
                let m = SCNVector4(rotation.x, rotation.y, rotation.z, rotation.w)
                let a = _vector4(from) ?? m, b = _vector4(to) ?? m
                let dot = a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w
                let s: Float = dot < 0 ? -1 : 1
                let u = Float(t)
                rotation = _Quaternion(x: a.x + (b.x * s - a.x) * u, y: a.y + (b.y * s - a.y) * u, z: a.z + (b.z * s - a.z) * u, w: a.w + (b.w * s - a.w) * u).normalized
            case "eulerAngles":
                var e = rotation.euler
                _blend(&e, parts: parts, from: from, to: to, by: by, t: t, additive: property.isAdditive)
                rotation = _Quaternion(euler: e)
            case "position":
                _blend(&position, parts: parts, from: from, to: to, by: by, t: t, additive: property.isAdditive)
            case "scale":
                _blend(&scale, parts: parts, from: from, to: to, by: by, t: t, additive: property.isAdditive)
            default:
                continue
            }
        }
    }
}

/// A vector, or one of its components (`position.y`), moved between two values.
private func _blend(_ v: inout SCNVector3, parts: [String], from: Any?, to: Any?, by: Any?, t: Double, additive: Bool) {
    if parts.count > 1 {
        let current: Float = parts[1] == "x" ? v.x : parts[1] == "y" ? v.y : v.z
        let a = _number(from).map(Float.init) ?? (additive ? 0 : current)
        let b = _number(to).map(Float.init) ?? _number(by).map { a + Float($0) } ?? (additive ? 0 : current)
        var value = a + (b - a) * Float(t)
        if additive { value += current }
        switch parts[1] {
        case "x": v.x = value
        case "y": v.y = value
        default: v.z = value
        }
        return
    }
    let zero = SCNVector3()
    let a = _vector3(from) ?? (additive ? zero : v)
    let b = _vector3(to) ?? _vector3(by).map { a + $0 } ?? (additive ? zero : v)
    let value = a + (b - a) * Float(t)
    v = additive ? v + value : value
}

@MainActor
func _animatedOpacity(of node: SCNNode, at time: Double) -> CGFloat? {
    var result: CGFloat?
    for entry in node.animations {
        guard let animation = entry.animation as? CAAnimation else { continue }
        for (property, f) in _flatten(animation, start: entry.start, time: time) where property.keyPath == "opacity" {
            let (from, to, by, t) = _segment(property, f)
            let a = _number(from) ?? Double(node.opacity)
            let b = _number(to) ?? _number(by).map { a + $0 } ?? Double(node.opacity)
            result = CGFloat(a + (b - a) * t)
        }
    }
    return result
}
