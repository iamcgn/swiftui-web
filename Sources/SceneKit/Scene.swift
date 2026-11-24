// SceneKit's scene graph (Docs/elements/SceneKit.md): a scene's root node and its tree of
// nodes, each with a transform (position, orientation, scale about its pivot), an optional
// geometry, camera and light, actions and Core Animation animations, and values kept by key.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI
import UIKit
#if canImport(QuartzCore)
import func QuartzCore.CACurrentMediaTime   // only the clock; the layer types are UIKit's
#endif

/// A container for the node hierarchy and global properties that together form a displayable 3D scene.
@preconcurrency @MainActor
open class SCNScene {
    public let rootNode = SCNNode()
    /// The background: a colour, or an image (drawn as its average, a mid grey).
    public let background = SCNMaterialProperty()
    public let lightingEnvironment = SCNMaterialProperty()
    open var fogColor: Any = UIColor.white
    open var fogStartDistance: CGFloat = 0
    open var fogEndDistance: CGFloat = 0
    open var isPaused = false
    private var attributes: [String: Any] = [:]

    public init() {}

    /// A scene from a file in the app's bundle: there is no scene file reader, so none.
    public convenience init?(named name: String) { return nil }
    public convenience init?(named name: String, inDirectory directory: String?, options: [String: Any]? = nil) { return nil }
    public convenience init(url: URL, options: [String: Any]? = nil) throws {
        throw NSError(domain: "SCNSceneErrorDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: "Scene files can't be read in a browser."])
    }

    open func attribute(forKey key: String) -> Any? { attributes[key] }
    open func setAttribute(_ attribute: Any?, forKey key: String) { attributes[key] = attribute }
}

/// A structural element of a scene graph, representing a position and transform in a 3D coordinate space.
@preconcurrency @MainActor
open class SCNNode {
    open var name: String?
    open var geometry: SCNGeometry? { didSet { _SceneClock.shared.touch() } }
    open var camera: SCNCamera? { didSet { _SceneClock.shared.touch() } }
    open var light: SCNLight? { didSet { _SceneClock.shared.touch() } }
    open var constraints: [SCNConstraint]?
    open var opacity: CGFloat = 1 { didSet { _SceneClock.shared.touch() } }
    open var isHidden = false { didSet { _SceneClock.shared.touch() } }
    open var castsShadow = true
    open var renderingOrder = 0
    open var categoryBitMask = 1
    open var movabilityHint = 0
    open var position = SCNVector3() { didSet { _SceneClock.shared.touch() } }
    open var scale = SCNVector3(1, 1, 1) { didSet { _SceneClock.shared.touch() } }
    open var pivot = SCNMatrix4Identity { didSet { _SceneClock.shared.touch() } }
    var quaternion = _Quaternion() { didSet { _SceneClock.shared.touch() } }
    public private(set) var childNodes: [SCNNode] = [] { didSet { _SceneClock.shared.touch() } }
    public private(set) weak var parent: SCNNode?
    var actions: [(key: String?, runner: _ActionRunner, completion: (@MainActor () -> Void)?)] = []
    var animations: [(key: String, animation: any SCNAnimationProtocol, start: Double)] = []
    private var values: [String: Any] = [:]

    public init() {}

    public convenience init(geometry: SCNGeometry?) {
        self.init()
        self.geometry = geometry
    }

    // MARK: Transform

    /// The node's orientation as a unit quaternion.
    open var orientation: SCNQuaternion {
        get { SCNVector4(quaternion.x, quaternion.y, quaternion.z, quaternion.w) }
        set { quaternion = _Quaternion(x: newValue.x, y: newValue.y, z: newValue.z, w: newValue.w).normalized }
    }

    /// The orientation as an axis and an angle in radians.
    open var rotation: SCNVector4 {
        get { quaternion.axisAngle }
        set { quaternion = _Quaternion(axis: SCNVector3(newValue.x, newValue.y, newValue.z), angle: newValue.w) }
    }

    /// The orientation as pitch, yaw and roll, applied roll first, then yaw, then pitch.
    open var eulerAngles: SCNVector3 {
        get { quaternion.euler }
        set { quaternion = _Quaternion(euler: newValue) }
    }

    /// Scale, then rotation, then translation, as one matrix.
    open var transform: SCNMatrix4 {
        get { Self.compose(position: position, rotation: quaternion, scale: scale) }
        set {
            position = SCNVector3(newValue.m41, newValue.m42, newValue.m43)
            let r = newValue.rows
            let sx = SCNVector3(r[0][0], r[0][1], r[0][2]).length
            let sy = SCNVector3(r[1][0], r[1][1], r[1][2]).length
            let sz = SCNVector3(r[2][0], r[2][1], r[2][2]).length
            scale = SCNVector3(sx, sy, sz)
            quaternion = Self.quaternion(fromRows: [[r[0][0] / max(sx, 1e-9), r[0][1] / max(sx, 1e-9), r[0][2] / max(sx, 1e-9)],
                                                    [r[1][0] / max(sy, 1e-9), r[1][1] / max(sy, 1e-9), r[1][2] / max(sy, 1e-9)],
                                                    [r[2][0] / max(sz, 1e-9), r[2][1] / max(sz, 1e-9), r[2][2] / max(sz, 1e-9)]])
        }
    }

    /// The transform in the scene's coordinates: the pivot undone, then this node's, then its parents'.
    open var worldTransform: SCNMatrix4 { worldTransform(at: nil) }

    open var worldPosition: SCNVector3 {
        get { let m = worldTransform; return SCNVector3(m.m41, m.m42, m.m43) }
        set {
            guard let parent else { position = newValue; return }
            position = SCNMatrix4Invert(parent.worldTransform).transformPoint(newValue)
        }
    }

    open var worldOrientation: SCNQuaternion {
        var q = quaternion
        var p = parent
        while let node = p { q = node.quaternion * q; p = node.parent }
        return SCNVector4(q.x, q.y, q.z, q.w)
    }

    /// The node as it is drawn: animations aren't applied to a copy, so the node itself.
    open var presentation: SCNNode { self }

    static func compose(position: SCNVector3, rotation: _Quaternion, scale: SCNVector3) -> SCNMatrix4 {
        var m = rotation.matrix
        m.m11 *= scale.x; m.m12 *= scale.x; m.m13 *= scale.x
        m.m21 *= scale.y; m.m22 *= scale.y; m.m23 *= scale.y
        m.m31 *= scale.z; m.m32 *= scale.z; m.m33 *= scale.z
        m.m41 = position.x; m.m42 = position.y; m.m43 = position.z
        return m
    }

    static func quaternion(fromRows m: [[Float]]) -> _Quaternion {
        // Row-vector matrix: the transpose of the usual one.
        let trace = m[0][0] + m[1][1] + m[2][2]
        if trace > 0 {
            let s = (trace + 1).squareRoot() * 2
            return _Quaternion(x: (m[1][2] - m[2][1]) / s, y: (m[2][0] - m[0][2]) / s, z: (m[0][1] - m[1][0]) / s, w: s / 4).normalized
        } else if m[0][0] > m[1][1] && m[0][0] > m[2][2] {
            let s = (1 + m[0][0] - m[1][1] - m[2][2]).squareRoot() * 2
            return _Quaternion(x: s / 4, y: (m[1][0] + m[0][1]) / s, z: (m[2][0] + m[0][2]) / s, w: (m[1][2] - m[2][1]) / s).normalized
        } else if m[1][1] > m[2][2] {
            let s = (1 + m[1][1] - m[0][0] - m[2][2]).squareRoot() * 2
            return _Quaternion(x: (m[1][0] + m[0][1]) / s, y: s / 4, z: (m[2][1] + m[1][2]) / s, w: (m[2][0] - m[0][2]) / s).normalized
        } else {
            let s = (1 + m[2][2] - m[0][0] - m[1][1]).squareRoot() * 2
            return _Quaternion(x: (m[2][0] + m[0][2]) / s, y: (m[2][1] + m[1][2]) / s, z: s / 4, w: (m[0][1] - m[1][0]) / s).normalized
        }
    }

    /// The local matrix with the animations playing at `time` (the model's at nil).
    func localTransform(at time: Double?) -> SCNMatrix4 {
        var position = self.position, scale = self.scale, rotation = quaternion
        if let time { _applyAnimations(of: self, at: time, position: &position, rotation: &rotation, scale: &scale) }
        let local = Self.compose(position: position, rotation: rotation, scale: scale)
        return pivot == SCNMatrix4Identity ? local : SCNMatrix4Mult(SCNMatrix4Invert(pivot), local)
    }

    func worldTransform(at time: Double?) -> SCNMatrix4 {
        let local = localTransform(at: time)
        guard let parent else { return local }
        return SCNMatrix4Mult(local, parent.worldTransform(at: time))
    }

    /// The opacity with the animations playing, times the parents'.
    func worldOpacity(at time: Double?) -> CGFloat {
        var own = opacity
        if let time { own = _animatedOpacity(of: self, at: time) ?? own }
        return own * (parent?.worldOpacity(at: time) ?? 1)
    }

    open func convertPosition(_ position: SCNVector3, to node: SCNNode?) -> SCNVector3 {
        let world = worldTransform.transformPoint(position)
        guard let node else { return world }
        return SCNMatrix4Invert(node.worldTransform).transformPoint(world)
    }

    open func convertPosition(_ position: SCNVector3, from node: SCNNode?) -> SCNVector3 {
        let world = node?.worldTransform.transformPoint(position) ?? position
        return SCNMatrix4Invert(worldTransform).transformPoint(world)
    }

    open func convertVector(_ vector: SCNVector3, to node: SCNNode?) -> SCNVector3 {
        let world = worldTransform.transformDirection(vector)
        guard let node else { return world }
        return SCNMatrix4Invert(node.worldTransform).transformDirection(world)
    }

    open func convertVector(_ vector: SCNVector3, from node: SCNNode?) -> SCNVector3 {
        let world = node?.worldTransform.transformDirection(vector) ?? vector
        return SCNMatrix4Invert(worldTransform).transformDirection(world)
    }

    /// Turns the node so its local front (-z) points at `target` in the scene's coordinates,
    /// with `up` (y) kept as near the world's up as it can be.
    open func look(at target: SCNVector3) { look(at: target, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1)) }

    open func look(at target: SCNVector3, up: SCNVector3, localFront: SCNVector3) {
        let here = parent.map { $0.worldTransform.transformPoint(position) } ?? position
        let forward = (target - here).normalized
        guard forward.length > 0 else { return }
        var right = forward.cross(up.normalized)
        if right.length < 1e-6 { right = forward.cross(SCNVector3(0, 0, 1)) }
        right = right.normalized
        let upward = right.cross(forward).normalized
        // Rows: x is right, y up, z backwards (the front is -z).
        let back = forward * -1
        var world = Self.quaternion(fromRows: [[right.x, right.y, right.z], [upward.x, upward.y, upward.z], [back.x, back.y, back.z]])
        if localFront != SCNVector3(0, 0, -1) {
            // Turn the given front onto -z first.
            let from = localFront.normalized, to = SCNVector3(0, 0, -1)
            let axis = from.cross(to)
            let angle = _acosF(from.dot(to))
            if axis.length > 1e-6 { world = world * _Quaternion(axis: axis, angle: angle) }
        }
        if let parent {
            let p = parent.worldOrientation
            let inverse = _Quaternion(x: -p.x, y: -p.y, z: -p.z, w: p.w)
            quaternion = (inverse * world).normalized
        } else {
            quaternion = world
        }
    }

    // MARK: Hierarchy

    open func addChildNode(_ child: SCNNode) {
        child.removeFromParentNode()
        childNodes.append(child)
        child.parent = self
    }

    open func insertChildNode(_ child: SCNNode, at index: Int) {
        child.removeFromParentNode()
        childNodes.insert(child, at: min(max(index, 0), childNodes.count))
        child.parent = self
    }

    open func replaceChildNode(_ oldChild: SCNNode, with newChild: SCNNode) {
        guard let i = childNodes.firstIndex(where: { $0 === oldChild }) else { return }
        oldChild.removeFromParentNode()
        insertChildNode(newChild, at: i)
    }

    open func removeFromParentNode() {
        guard let parent else { return }
        parent.childNodes.removeAll { $0 === self }
        self.parent = nil
    }

    open func childNode(withName name: String, recursively: Bool) -> SCNNode? {
        for child in childNodes where child.name == name { return child }
        guard recursively else { return nil }
        for child in childNodes { if let found = child.childNode(withName: name, recursively: true) { return found } }
        return nil
    }

    open func childNodes(passingTest predicate: (SCNNode, UnsafeMutablePointer<ObjCBool>) -> Bool) -> [SCNNode] {
        var found: [SCNNode] = []
        var stop = ObjCBool(false)
        func visit(_ node: SCNNode) {
            for child in node.childNodes {
                if stop.boolValue { return }
                if predicate(child, &stop) { found.append(child) }
                visit(child)
            }
        }
        visit(self)
        return found
    }

    open func enumerateChildNodes(_ block: (SCNNode, UnsafeMutablePointer<ObjCBool>) -> Void) {
        var stop = ObjCBool(false)
        func visit(_ node: SCNNode) {
            for child in node.childNodes {
                if stop.boolValue { return }
                block(child, &stop)
                visit(child)
            }
        }
        visit(self)
    }

    open func enumerateHierarchy(_ block: (SCNNode, UnsafeMutablePointer<ObjCBool>) -> Void) {
        var stop = ObjCBool(false)
        block(self, &stop)
        if !stop.boolValue { enumerateChildNodes(block) }
    }

    /// A copy of the node and its subtree, sharing geometries and materials.
    open func clone() -> SCNNode {
        let copy = SCNNode()
        copy.name = name; copy.geometry = geometry; copy.camera = camera; copy.light = light
        copy.constraints = constraints; copy.opacity = opacity; copy.isHidden = isHidden
        copy.castsShadow = castsShadow; copy.renderingOrder = renderingOrder; copy.categoryBitMask = categoryBitMask
        copy.position = position; copy.scale = scale; copy.pivot = pivot; copy.quaternion = quaternion
        copy.values = values
        for child in childNodes { copy.addChildNode(child.clone()) }
        return copy
    }

    open func flattenedClone() -> SCNNode { clone() }

    /// The corners of the box around the geometry, or around the children's in this node's coordinates.
    open var boundingBox: (min: SCNVector3, max: SCNVector3) {
        get {
            if let geometry { return geometry.boundingBox }
            var lo: SCNVector3?, hi: SCNVector3?
            for child in childNodes {
                let (a, b) = child.boundingBox
                guard a != b || child.geometry != nil else { continue }
                let m = child.localTransform(at: nil)
                for corner in [SCNVector3(a.x, a.y, a.z), SCNVector3(b.x, a.y, a.z), SCNVector3(a.x, b.y, a.z), SCNVector3(a.x, a.y, b.z),
                               SCNVector3(b.x, b.y, a.z), SCNVector3(b.x, a.y, b.z), SCNVector3(a.x, b.y, b.z), SCNVector3(b.x, b.y, b.z)] {
                    let p = m.transformPoint(corner)
                    lo = lo.map { SCNVector3(min($0.x, p.x), min($0.y, p.y), min($0.z, p.z)) } ?? p
                    hi = hi.map { SCNVector3(max($0.x, p.x), max($0.y, p.y), max($0.z, p.z)) } ?? p
                }
            }
            return (lo ?? SCNVector3(), hi ?? SCNVector3())
        }
        set {}
    }

    open var boundingSphere: (center: SCNVector3, radius: Float) {
        let (lo, hi) = boundingBox
        let center = (lo + hi) * 0.5
        return (center, (hi - center).length)
    }

    // MARK: Values by key

    open func setValue(_ value: Any?, forKey key: String) {
        switch key {
        case "opacity": if let v = _number(value) { opacity = CGFloat(v) }
        case "name": name = value as? String
        default: values[key] = value
        }
    }

    open func value(forKey key: String) -> Any? {
        switch key {
        case "opacity": return opacity
        case "name": return name
        default: return values[key]
        }
    }

    open func setValue(_ value: Any?, forKeyPath keyPath: String) { setValue(value, forKey: keyPath) }
    open func value(forKeyPath keyPath: String) -> Any? { value(forKey: keyPath) }

    // MARK: Animations

    open func addAnimation(_ animation: any SCNAnimationProtocol, forKey key: String?) {
        let key = key ?? "animation\(animations.count)"
        animations.removeAll { $0.key == key }
        animations.append((key, animation, CACurrentMediaTime()))
        _SceneClock.shared.wake()
    }

    open func removeAnimation(forKey key: String) { animations.removeAll { $0.key == key } }
    open func removeAnimation(forKey key: String, blendOutDuration duration: CGFloat) { removeAnimation(forKey: key) }
    open func removeAllAnimations() { animations.removeAll() }
    open var animationKeys: [String] { animations.map(\.key) }
    open func animationPlayer(forKey key: String) -> SCNAnimationPlayer? { nil }
    open func isAnimationPaused(forKey key: String) -> Bool { false }
}

/// A value Core Animation's values come in: a number, or a boxed one.
func _number(_ value: Any?) -> Double? {
    switch value {
    case let v as Double: return v
    case let v as Float: return Double(v)
    case let v as CGFloat: return Double(v)
    case let v as Int: return Double(v)
    case let v as NSNumber: return v.doubleValue
    default: return nil
    }
}

/// A camera attached to a node, with the projection a view draws the scene through.
@preconcurrency @MainActor
open class SCNCamera {
    open var name: String?
    /// The vertical field of view in degrees.
    open var fieldOfView: CGFloat = 60
    open var zNear: Double = 1
    open var zFar: Double = 100
    open var usesOrthographicProjection = false
    /// Half the visible height in scene units, for the orthographic projection.
    open var orthographicScale: Double = 1
    open var automaticallyAdjustsZRange = false
    open var wantsHDR = false
    open var wantsExposureAdaptation = true
    open var bloomIntensity: CGFloat = 0
    open var bloomThreshold: CGFloat = 1
    open var bloomBlurRadius: CGFloat = 4
    open var exposureOffset: CGFloat = 0
    open var focalLength: CGFloat = 50
    open var focusDistance: CGFloat = 2.5
    open var fStop: CGFloat = 5.6
    open var wantsDepthOfField = false
    open var motionBlurIntensity: CGFloat = 0
    open var vignettingIntensity: CGFloat = 0
    open var colorFringeStrength: CGFloat = 0
    open var saturation: CGFloat = 1
    open var contrast: CGFloat = 0
    open var screenSpaceAmbientOcclusionIntensity: CGFloat = 0
    public init() {}
}

/// A light source attached to a node.
@preconcurrency @MainActor
open class SCNLight {
    public struct LightType: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let ambient = LightType(rawValue: "ambient")
        public static let omni = LightType(rawValue: "omni")
        public static let directional = LightType(rawValue: "directional")
        public static let spot = LightType(rawValue: "spot")
        public static let IES = LightType(rawValue: "ies")
        public static let probe = LightType(rawValue: "probe")
        public static let area = LightType(rawValue: "area")
    }

    open var name: String?
    open var type: LightType = .omni
    open var color: Any = UIColor.white
    /// Lumens: 1000 is full strength.
    open var intensity: CGFloat = 1000
    open var temperature: CGFloat = 6500
    open var castsShadow = false
    open var shadowRadius: CGFloat = 3
    open var shadowColor: Any = UIColor(white: 0, alpha: 0.5)
    open var shadowMode = 0
    open var shadowSampleCount = 0
    open var shadowMapSize = CGSize.zero
    open var spotInnerAngle: CGFloat = 0
    open var spotOuterAngle: CGFloat = 45
    open var attenuationStartDistance: CGFloat = 0
    open var attenuationEndDistance: CGFloat = 0
    open var attenuationFalloffExponent: CGFloat = 2
    open var categoryBitMask = -1
    public init() {}
}

/// Changes grouped together (`begin` / `commit`): they take effect at once, with no implicit animation.
@preconcurrency @MainActor
public final class SCNTransaction {
    public static var animationDuration: TimeInterval = 0
    public static var animationTimingFunction: CAMediaTimingFunction?
    public static var disableActions = false
    public static var completionBlock: (@MainActor () -> Void)?
    private static var depth = 0

    public static func begin() { depth += 1 }

    public static func commit() {
        depth = max(depth - 1, 0)
        guard depth == 0 else { return }
        let completion = completionBlock
        completionBlock = nil
        animationDuration = 0
        completion?()
    }

    public static func flush() {}
    public static func lock() {}
    public static func unlock() {}
}

/// A constraint on a node's transform, applied as the scene is drawn.
@preconcurrency @MainActor
open class SCNConstraint {
    open var isEnabled = true
    open var influenceFactor: CGFloat = 1
    public init() {}
    func apply(to node: SCNNode) {}
}

/// Keeps a node pointed at a target node.
@preconcurrency @MainActor
open class SCNLookAtConstraint: SCNConstraint {
    open var target: SCNNode?
    open var isGimbalLockEnabled = false
    open var localFront = SCNVector3(0, 0, -1)
    open var worldUp = SCNVector3(0, 1, 0)
    public init(target: SCNNode?) { self.target = target; super.init() }
    override func apply(to node: SCNNode) {
        guard isEnabled, let target else { return }
        node.look(at: target.worldPosition, up: worldUp, localFront: localFront)
    }
}

/// Keeps a node facing the camera.
@preconcurrency @MainActor
open class SCNBillboardConstraint: SCNConstraint {
    public struct BillboardAxis: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let X = BillboardAxis(rawValue: 1)
        public static let Y = BillboardAxis(rawValue: 2)
        public static let Z = BillboardAxis(rawValue: 4)
        public static let all: BillboardAxis = [.X, .Y, .Z]
    }
    open var freeAxes: BillboardAxis = .all
    public override init() { super.init() }
}

/// A playable animation (Apple's wraps a Core Animation one); kept for source compatibility.
@preconcurrency @MainActor
open class SCNAnimationPlayer {
    open var speed: CGFloat = 1
    open var paused = false
    public init() {}
    open func play() {}
    open func stop() {}
}

/// What `addAnimation(_:forKey:)` takes: a Core Animation animation.
@preconcurrency @MainActor
public protocol SCNAnimationProtocol: AnyObject {}

extension CAAnimation: SCNAnimationProtocol {}
