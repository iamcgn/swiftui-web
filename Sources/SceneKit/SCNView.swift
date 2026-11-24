// SceneKit's views (Docs/elements/SceneKit.md): `SCNView` draws its scene each frame by
// projecting every triangle on the CPU and painting them far to near with flat shading, and
// SwiftUI's `SceneView` hosts one. A frame clock steps actions, applies constraints, and
// redraws while anything moves or a property changed.
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

public enum SCNAntialiasingMode: UInt, Sendable { case none = 0, multisampling2X, multisampling4X, multisampling8X, multisampling16X }

public struct SCNDebugOptions: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let showPhysicsShapes = SCNDebugOptions(rawValue: 1 << 0)
    public static let showBoundingBoxes = SCNDebugOptions(rawValue: 1 << 1)
    public static let showLightInfluences = SCNDebugOptions(rawValue: 1 << 2)
    public static let showLightExtents = SCNDebugOptions(rawValue: 1 << 3)
    public static let showPhysicsFields = SCNDebugOptions(rawValue: 1 << 4)
    public static let showWireframe = SCNDebugOptions(rawValue: 1 << 5)
    public static let renderAsWireframe = SCNDebugOptions(rawValue: 1 << 6)
    public static let showSkeletons = SCNDebugOptions(rawValue: 1 << 7)
    public static let showCreases = SCNDebugOptions(rawValue: 1 << 8)
    public static let showConstraints = SCNDebugOptions(rawValue: 1 << 9)
    public static let showCameras = SCNDebugOptions(rawValue: 1 << 10)
}

public enum SCNInteractionMode: Int, Sendable { case fly, orbitTurntable, orbitAngleMapping, orbitCenteredArcball, orbitArcball, pan, truck }

/// A shader-based rendering technique; a page has none to run.
@preconcurrency @MainActor
open class SCNTechnique {
    public init?(dictionary: [String: Any]) {}
}

/// What a hit test found: the node and where on it.
@preconcurrency @MainActor
open class SCNHitTestResult {
    public let node: SCNNode
    public let worldCoordinates: SCNVector3
    public let localCoordinates: SCNVector3
    public let geometryIndex: Int
    public let faceIndex: Int
    open var worldNormal: SCNVector3
    open var localNormal: SCNVector3
    init(node: SCNNode, world: SCNVector3, normal: SCNVector3, face: Int) {
        self.node = node
        worldCoordinates = world
        localCoordinates = SCNMatrix4Invert(node.worldTransform).transformPoint(world)
        geometryIndex = 0
        faceIndex = face
        worldNormal = normal
        localNormal = SCNMatrix4Invert(node.worldTransform).transformDirection(normal)
    }
}

public struct SCNHitTestOption: RawRepresentable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static let firstFoundOnly = SCNHitTestOption(rawValue: "firstFoundOnly")
    public static let sortResults = SCNHitTestOption(rawValue: "sortResults")
    public static let ignoreHiddenNodes = SCNHitTestOption(rawValue: "ignoreHiddenNodes")
    public static let boundingBoxOnly = SCNHitTestOption(rawValue: "boundingBoxOnly")
    public static let rootNode = SCNHitTestOption(rawValue: "rootNode")
    public static let searchMode = SCNHitTestOption(rawValue: "searchMode")
    public static let categoryBitMask = SCNHitTestOption(rawValue: "categoryBitMask")
}

/// Methods and properties common to the SceneKit renderers.
@preconcurrency @MainActor
public protocol SCNSceneRenderer: AnyObject {
    var scene: SCNScene? { get set }
    var pointOfView: SCNNode? { get set }
    var autoenablesDefaultLighting: Bool { get set }
    var sceneTime: TimeInterval { get set }
    var isPlaying: Bool { get set }
    var loops: Bool { get set }
    var showsStatistics: Bool { get set }
    var debugOptions: SCNDebugOptions { get set }
    func projectPoint(_ point: SCNVector3) -> SCNVector3
    func unprojectPoint(_ point: SCNVector3) -> SCNVector3
    func hitTest(_ point: CGPoint, options: [SCNHitTestOption: Any]?) -> [SCNHitTestResult]
    func isNode(_ node: SCNNode, insideFrustumOf pointOfView: SCNNode) -> Bool
    func nodesInsideFrustum(of pointOfView: SCNNode) -> [SCNNode]
}

/// Methods your app can implement to participate in SceneKit's animation loop.
@preconcurrency @MainActor
public protocol SCNSceneRendererDelegate: AnyObject {
    func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval)
    func renderer(_ renderer: any SCNSceneRenderer, didApplyAnimationsAtTime time: TimeInterval)
    func renderer(_ renderer: any SCNSceneRenderer, didSimulatePhysicsAtTime time: TimeInterval)
    func renderer(_ renderer: any SCNSceneRenderer, didApplyConstraintsAtTime time: TimeInterval)
    func renderer(_ renderer: any SCNSceneRenderer, willRenderScene scene: SCNScene, atTime time: TimeInterval)
    func renderer(_ renderer: any SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval)
}

extension SCNSceneRendererDelegate {
    public func renderer(_ renderer: any SCNSceneRenderer, updateAtTime time: TimeInterval) {}
    public func renderer(_ renderer: any SCNSceneRenderer, didApplyAnimationsAtTime time: TimeInterval) {}
    public func renderer(_ renderer: any SCNSceneRenderer, didSimulatePhysicsAtTime time: TimeInterval) {}
    public func renderer(_ renderer: any SCNSceneRenderer, didApplyConstraintsAtTime time: TimeInterval) {}
    public func renderer(_ renderer: any SCNSceneRenderer, willRenderScene scene: SCNScene, atTime time: TimeInterval) {}
    public func renderer(_ renderer: any SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {}
}

/// Orbits the point of view about a target, as the view's camera control does.
@preconcurrency @MainActor
open class SCNCameraController {
    open var pointOfView: SCNNode?
    open var target = SCNVector3()
    open var automaticTarget = false
    open var interactionMode: SCNInteractionMode = .orbitTurntable
    open var inertiaEnabled = false
    open var inertiaFriction: Float = 0.05
    open var worldUp = SCNVector3(0, 1, 0)
    open var minimumVerticalAngle: Float = 0
    open var maximumVerticalAngle: Float = 0
    open var minimumHorizontalAngle: Float = 0
    open var maximumHorizontalAngle: Float = 0
    open weak var delegate: AnyObject?
    init() {}

    /// Turns the point of view about the target by degrees across and up.
    open func rotateBy(x deltaX: Float, y deltaY: Float) {
        guard let pov = pointOfView else { return }
        let offset = pov.worldPosition - target
        let yaw = _Quaternion(axis: worldUp, angle: -deltaX * Float.pi / 180)
        var moved = yaw.matrix.transformDirection(offset)
        let right = worldUp.cross(moved)
        if right.length > 1e-6 {
            let pitched = _Quaternion(axis: right, angle: deltaY * Float.pi / 180).matrix.transformDirection(moved)
            // Stop short of the poles, where the up direction would flip.
            if abs(pitched.dot(worldUp)) / max(pitched.length, 1e-6) < 0.995 { moved = pitched }
        }
        pov.worldPosition = target + moved
        pov.look(at: target, up: worldUp, localFront: SCNVector3(0, 0, -1))
    }

    open func translateInCameraSpaceBy(x deltaX: Float, y deltaY: Float, z deltaZ: Float) {
        guard let pov = pointOfView else { return }
        let m = pov.worldTransform
        let move = m.transformDirection(SCNVector3(deltaX, deltaY, deltaZ))
        pov.worldPosition = pov.worldPosition + move
        target = target + move
    }

    /// Moves the point of view toward the target (a positive delta) or away.
    open func dolly(by delta: Float, onScreenPoint point: CGPoint, viewport: CGSize) {
        guard let pov = pointOfView else { return }
        let offset = pov.worldPosition - target
        let length = offset.length
        guard length > 1e-6 else { return }
        let next = max(length - delta, 0.01)
        pov.worldPosition = target + offset * (next / length)
    }

    open func dolly(toTarget delta: Float) { dolly(by: delta, onScreenPoint: .zero, viewport: .zero) }
    open func roll(by delta: Float, aroundScreenPoint point: CGPoint, viewport: CGSize) {}
    open func stopInertia() {}
    open func clearRoll() {}
    open func frameNodes(_ nodes: [SCNNode]) {
        guard !nodes.isEmpty else { return }
        let centers = nodes.map { $0.convertPosition($0.boundingSphere.center, to: nil) }
        target = centers.reduce(SCNVector3()) { $0 + $1 } * (1 / Float(centers.count))
    }
}

// MARK: - Frame clock

/// Steps the scenes of the live views each frame while anything moves, and redraws them.
@MainActor
final class _SceneClock {
    static let shared = _SceneClock()
    /// Bumped by every change to a node or a material's contents.
    private(set) var generation = 0
    private var views: [WeakSceneView] = []
    private var link: CADisplayLink?
    private var lastTimestamp: Double?

    private struct WeakSceneView { weak var view: SCNView? }

    func touch() {
        generation &+= 1
        wake()
    }

    func wake() {
        guard link == nil, views.contains(where: { $0.view != nil }) else { return }
        let link = CADisplayLink { [weak self] link in self?.tick(link) }
        self.link = link
        lastTimestamp = nil
        link.add(to: .main, forMode: .common)
    }

    func register(_ view: SCNView) {
        views.removeAll { $0.view == nil || $0.view === view }
        views.append(WeakSceneView(view: view))
        wake()
    }

    private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        let dt = lastTimestamp.map { min(max(now - $0, 0), 0.1) } ?? link.duration
        lastTimestamp = now
        let live = views.compactMap(\.view)
        views = live.map { WeakSceneView(view: $0) }
        var stepped = Set<ObjectIdentifier>()
        var running = false
        for view in live { view.delegate?.renderer(view, updateAtTime: CACurrentMediaTime()) }
        for view in live {
            guard let scene = view.scene, stepped.insert(ObjectIdentifier(scene)).inserted else { continue }
            if !scene.isPaused {
                scene.rootNode.stepActions(dt)
                scene.rootNode.pruneAnimations(at: CACurrentMediaTime())
            }
            scene.rootNode.applyConstraints()
            if scene.rootNode.isAnimating { running = true }
        }
        for view in live {
            if view.rendersContinuously || view.drawnGeneration != generation || (view.scene?.rootNode.isAnimating ?? false) {
                view.setNeedsDisplay()
            }
            if view.rendersContinuously { running = true }
        }
        if !running {
            link.invalidate()
            self.link = nil
        }
    }
}

extension SCNNode {
    /// Takes off the animations that have finished and are removed on completion.
    func pruneAnimations(at time: Double) {
        if !animations.isEmpty {
            animations.removeAll { entry in
                guard let animation = entry.animation as? CAAnimation, animation.isRemovedOnCompletion else { return false }
                let duration = animation.duration > 0 ? animation.duration : 0.25
                let repeats = animation.repeatDuration > 0 ? animation.repeatDuration / duration : Double(animation.repeatCount > 0 ? animation.repeatCount : 1)
                guard repeats.isFinite else { return false }
                let span = duration * repeats * (animation.autoreverses ? 2 : 1) / Double(max(animation.speed, 1e-6))
                return time - entry.start - animation.beginTime > span
            }
        }
        for child in childNodes { child.pruneAnimations(at: time) }
    }
}

// MARK: - Rendering

/// One shape painted in a frame: a triangle, an edge, or a flat piece (text, a path) through an affine map.
struct _Painted {
    enum Kind {
        case fill([CGPoint])
        case lines([(CGPoint, CGPoint)])
        case text(String, UIFont, CGAffineTransform)
        case path(UIBezierPath, CGAffineTransform)
    }
    var kind: Kind
    var color: (r: Double, g: Double, b: Double, a: Double)
    var depth: Double
    var order: Int
    var node: SCNNode
    var world: [SCNVector3]
    var normal: SCNVector3
    var face: Int
}

/// The camera a frame is seen through: the matrices and the projection onto the view.
struct _Projection {
    var view: SCNMatrix4
    var eye: SCNVector3
    var forward: SCNVector3
    var orthographic: Bool
    var focal: Double
    var size: CGSize
    var near: Double

    /// A point in the scene's coordinates on the view, and its distance in front of the camera.
    func project(_ p: SCNVector3) -> (point: CGPoint, depth: Double)? {
        let c = view.transformPoint(p)
        let depth = -Double(c.z)
        if orthographic {
            return (CGPoint(x: size.width / 2 + CGFloat(Double(c.x) * focal), y: size.height / 2 - CGFloat(Double(c.y) * focal)), depth)
        }
        guard depth > near else { return nil }
        return (CGPoint(x: size.width / 2 + CGFloat(Double(c.x) / depth * focal), y: size.height / 2 - CGFloat(Double(c.y) / depth * focal)), depth)
    }

    func unproject(_ point: CGPoint, depth: Double) -> SCNVector3 {
        let x: Double, y: Double
        if orthographic {
            x = Double(point.x - size.width / 2) / focal
            y = Double(size.height / 2 - point.y) / focal
        } else {
            x = Double(point.x - size.width / 2) / focal * depth
            y = Double(size.height / 2 - point.y) / focal * depth
        }
        return SCNMatrix4Invert(view).transformPoint(SCNVector3(Float(x), Float(y), Float(-depth)))
    }
}

/// A light as it shines in a frame.
struct _FrameLight {
    var type: SCNLight.LightType
    var color: (r: Double, g: Double, b: Double)
    var position: SCNVector3
    var direction: SCNVector3
}

/// A view for displaying 3D SceneKit content.
@preconcurrency @MainActor
open class SCNView: UIView, SCNSceneRenderer {
    public struct Option: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let preferredRenderingAPI = Option(rawValue: "SCNPreferredRenderingAPIKey")
        public static let preferredDevice = Option(rawValue: "SCNPreferredDeviceKey")
        public static let preferLowPowerDevice = Option(rawValue: "SCNPreferLowPowerDeviceKey")
    }

    open var scene: SCNScene? { didSet { setNeedsDisplay(); _SceneClock.shared.wake() } }
    open var pointOfView: SCNNode? { didSet { setNeedsDisplay() } }
    open var autoenablesDefaultLighting = false { didSet { setNeedsDisplay() } }
    open var allowsCameraControl = false { didSet { updateCameraControl() } }
    open var antialiasingMode: SCNAntialiasingMode = .multisampling4X
    open var rendersContinuously = false { didSet { _SceneClock.shared.wake() } }
    open var preferredFramesPerSecond = 60
    open var isJitteringEnabled = false
    open var isTemporalAntialiasingEnabled = false
    open var sceneTime: TimeInterval = 0
    open var isPlaying = false { didSet { _SceneClock.shared.wake() } }
    open var loops = true
    open var showsStatistics = false
    open var debugOptions: SCNDebugOptions = [] { didSet { setNeedsDisplay() } }
    open weak var delegate: (any SCNSceneRendererDelegate)?
    open var technique: SCNTechnique?
    public let defaultCameraController = SCNCameraController()
    open var cameraControlConfiguration: Any?
    /// The generation of scene changes the last frame drew.
    var drawnGeneration = -1
    private var painted: [_Painted] = []
    private var lastProjection: _Projection?
    /// Set while a hit test or snapshot needs the triangles projected here.
    private var paintsOnCPU = false
    private var paintedOnCPU = true
    private var orbitNode: SCNNode?
    private var panRecognizer: UIPanGestureRecognizer?
    private var pinchRecognizer: UIPinchGestureRecognizer?
    private var lastPan = CGPoint.zero
    private var lastPinch: CGFloat = 1

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        _SceneClock.shared.register(self)
    }

    public convenience init(frame: CGRect, options: [String: Any]? = nil) {
        self.init(frame: frame)
    }

    public required init?(coder: NSCoder) { return nil }

    open func play(_ sender: Any?) { isPlaying = true }
    open func pause(_ sender: Any?) { isPlaying = false }
    open func stop(_ sender: Any?) { isPlaying = false; sceneTime = 0 }

    /// The view drawn into an image.
    open func snapshot() -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        paintsOnCPU = true
        defer { paintsOnCPU = false }
        return renderer.image { _ in self.draw(self.bounds) }
    }

    // MARK: Camera

    /// The node the scene is seen from: the view's point of view, the first camera in the
    /// scene, or a camera framing the whole scene from in front.
    func resolvedPointOfView() -> SCNNode? {
        if let orbitNode, allowsCameraControl { return orbitNode }
        if let pointOfView { return pointOfView }
        guard let scene else { return nil }
        if let found = Self.firstCamera(scene.rootNode) { return found }
        return defaultCamera(for: scene)
    }

    private static func firstCamera(_ node: SCNNode) -> SCNNode? {
        if node.camera != nil { return node }
        for child in node.childNodes { if let found = firstCamera(child) { return found } }
        return nil
    }

    private var fallbackCamera: SCNNode?

    private func defaultCamera(for scene: SCNScene) -> SCNNode {
        let node = fallbackCamera ?? SCNNode()
        if node.camera == nil { node.camera = SCNCamera() }
        let (center, radius) = Self.sceneSphere(scene.rootNode)
        let distance = max(radius, 0.5) / Float(_sin(Double.pi / 6)) * 1.1
        node.position = center + SCNVector3(0, 0, distance)
        node.quaternion = _Quaternion()
        fallbackCamera = node
        return node
    }

    /// The sphere around every geometry in the scene, in the scene's coordinates.
    static func sceneSphere(_ root: SCNNode) -> (SCNVector3, Float) {
        var points: [SCNVector3] = []
        func visit(_ node: SCNNode) {
            if let geometry = node.geometry {
                let (lo, hi) = geometry.boundingBox
                let m = node.worldTransform
                for x in [lo.x, hi.x] { for y in [lo.y, hi.y] { for z in [lo.z, hi.z] { points.append(m.transformPoint(SCNVector3(x, y, z))) } } }
            }
            for child in node.childNodes { visit(child) }
        }
        visit(root)
        guard var lo = points.first else { return (SCNVector3(), 1) }
        var hi = lo
        for p in points {
            lo = SCNVector3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
            hi = SCNVector3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
        }
        let center = (lo + hi) * 0.5
        return (center, (hi - center).length)
    }

    private func updateCameraControl() {
        if allowsCameraControl {
            guard panRecognizer == nil else { return }
            let pan = UIPanGestureRecognizer(handler: { [weak self] (recognizer: UIGestureRecognizer) in
                if let pan = recognizer as? UIPanGestureRecognizer { self?.handlePan(pan) }
            })
            addGestureRecognizer(pan)
            panRecognizer = pan
            let pinch = UIPinchGestureRecognizer(handler: { [weak self] (recognizer: UIGestureRecognizer) in
                if let pinch = recognizer as? UIPinchGestureRecognizer { self?.handlePinch(pinch) }
            })
            addGestureRecognizer(pinch)
            pinchRecognizer = pinch
        } else {
            if let panRecognizer { removeGestureRecognizer(panRecognizer) }
            if let pinchRecognizer { removeGestureRecognizer(pinchRecognizer) }
            panRecognizer = nil
            pinchRecognizer = nil
            orbitNode = nil
        }
    }

    /// The node the camera control moves: a copy of the point of view, so the scene's own camera stays put.
    private func controlNode() -> SCNNode? {
        if let orbitNode { return orbitNode }
        guard let source = resolvedPointOfView() else { return nil }
        let node = SCNNode()
        node.camera = source.camera ?? SCNCamera()
        node.transform = source.worldTransform
        if !defaultCameraController.automaticTarget, defaultCameraController.target == SCNVector3(), let scene {
            defaultCameraController.target = Self.sceneSphere(scene.rootNode).0
        }
        orbitNode = node
        defaultCameraController.pointOfView = node
        return node
    }

    private func handlePan(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: self)
        if pan.state == .began { lastPan = .zero }
        guard pan.state == .began || pan.state == .changed, controlNode() != nil else { return }
        let dx = Float(translation.x - lastPan.x), dy = Float(translation.y - lastPan.y)
        lastPan = translation
        defaultCameraController.rotateBy(x: dx * 0.5, y: dy * 0.5)
        setNeedsDisplay()
    }

    private func handlePinch(_ pinch: UIPinchGestureRecognizer) {
        if pinch.state == .began { lastPinch = 1 }
        guard pinch.state == .began || pinch.state == .changed, let node = controlNode() else { return }
        let ratio = Float(pinch.scale / max(lastPinch, 0.01))
        lastPinch = pinch.scale
        let distance = (node.worldPosition - defaultCameraController.target).length
        defaultCameraController.dolly(by: distance - distance / max(ratio, 0.01), onScreenPoint: .zero, viewport: bounds.size)
        setNeedsDisplay()
    }

    // MARK: Projection

    func projection(at time: Double?) -> _Projection? {
        guard let pov = resolvedPointOfView() else { return nil }
        let world = pov.worldTransform(at: time)
        let camera = pov.camera ?? SCNCamera()
        let size = bounds.size
        let orthographic = camera.usesOrthographicProjection
        let focal: Double
        if orthographic {
            focal = Double(size.height) / 2 / max(camera.orthographicScale, 1e-6)
        } else {
            let half = Double(camera.fieldOfView) * Double.pi / 360
            focal = Double(size.height) / 2 / max(_sin(half) / _cos(half), 1e-6)
        }
        let eye = SCNVector3(world.m41, world.m42, world.m43)
        var forward = world.transformDirection(SCNVector3(0, 0, -1))
        if forward.length > 0 { forward = forward * (1 / forward.length) }
        return _Projection(view: SCNMatrix4Invert(world), eye: eye, forward: forward, orthographic: orthographic,
                           focal: focal, size: size, near: max(camera.zNear, 0.001))
    }

    open func projectPoint(_ point: SCNVector3) -> SCNVector3 {
        guard let projection = projection(at: nil) else { return point }
        let c = projection.view.transformPoint(point)
        let depth = -Double(c.z)
        let p = projection.project(point)?.point ?? .zero
        return SCNVector3(Float(p.x), Float(p.y), Float(depth))
    }

    open func unprojectPoint(_ point: SCNVector3) -> SCNVector3 {
        guard let projection = projection(at: nil) else { return point }
        return projection.unproject(CGPoint(x: CGFloat(point.x), y: CGFloat(point.y)), depth: max(Double(point.z), projection.near))
    }

    /// The nodes drawn under a point in the last frame, nearest first.
    open func hitTest(_ point: CGPoint, options: [SCNHitTestOption: Any]? = nil) -> [SCNHitTestResult] {
        if drawnGeneration != _SceneClock.shared.generation || painted.isEmpty || !paintedOnCPU {
            let renderer = UIGraphicsImageRenderer(size: bounds.size)
            paintsOnCPU = true
            _ = renderer.image { _ in self.draw(self.bounds) }
            paintsOnCPU = false
        }
        var hits: [(Double, SCNHitTestResult)] = []
        var seen = Set<ObjectIdentifier>()
        for item in painted.reversed() {
            guard case .fill(let points) = item.kind, points.count == 3, Self.contains(points, point) else { continue }
            guard seen.insert(ObjectIdentifier(item.node)).inserted else { continue }
            let center = (item.world[0] + item.world[1] + item.world[2]) * (1 / 3)
            hits.append((item.depth, SCNHitTestResult(node: item.node, world: center, normal: item.normal, face: item.face)))
            if options?[.firstFoundOnly] as? Bool == true { break }
        }
        return hits.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private static func contains(_ t: [CGPoint], _ p: CGPoint) -> Bool {
        func side(_ a: CGPoint, _ b: CGPoint) -> CGFloat { (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x) }
        let s0 = side(t[0], t[1]), s1 = side(t[1], t[2]), s2 = side(t[2], t[0])
        return (s0 >= 0 && s1 >= 0 && s2 >= 0) || (s0 <= 0 && s1 <= 0 && s2 <= 0)
    }

    open func isNode(_ node: SCNNode, insideFrustumOf pointOfView: SCNNode) -> Bool {
        guard let projection = projection(at: nil) else { return false }
        guard let p = projection.project(node.worldPosition)?.point else { return false }
        return bounds.insetBy(dx: -bounds.width, dy: -bounds.height).contains(p)
    }

    open func nodesInsideFrustum(of pointOfView: SCNNode) -> [SCNNode] {
        var result: [SCNNode] = []
        func visit(_ node: SCNNode) {
            if node.geometry != nil, isNode(node, insideFrustumOf: pointOfView) { result.append(node) }
            for child in node.childNodes { visit(child) }
        }
        if let scene { visit(scene.rootNode) }
        return result
    }

    // MARK: Drawing

    open override func draw(_ rect: CGRect) {
        drawnGeneration = _SceneClock.shared.generation
        painted = []
        paintedOnCPU = !DisplayMesh.hostRenders || paintsOnCPU
        guard let scene, let context = UIGraphicsGetCurrentContext() else { return }
        let time = CACurrentMediaTime()
        delegate?.renderer(self, willRenderScene: scene, atTime: time)
        if let bg = scene.background.rgba {
            context.setFillColor(red: CGFloat(bg.r), green: CGFloat(bg.g), blue: CGFloat(bg.b), alpha: CGFloat(bg.a))
            context.fill(bounds)
        }
        guard let projection = projection(at: time) else { return }
        lastProjection = projection
        let lights = frameLights(scene, projection: projection, time: time)
        var items: [_Painted] = []
        if DisplayMesh.hostRenders && !paintsOnCPU {
            // The browser draws the triangles (WebGL, MeshScript.swift); text and paths are
            // still painted here, over them.
            DisplayMesh.script = _meshScript
            var mesh = _MeshWriter(projection: projection, lights: lights, zFar: (resolvedPointOfView()?.camera ?? SCNCamera()).zFar,
                                   wireframe: debugOptions.contains(.renderAsWireframe))
            mesh.collect(scene.rootNode, parentWorld: SCNMatrix4Identity, parentOpacity: 1, time: time)
            context._recordMesh(mesh.finish(), in: bounds)
            for (node, world, opacity) in mesh.flat {
                let geometry = node.geometry!
                let materials = geometry.materials.isEmpty ? [geometry.firstMaterial!] : geometry.materials
                collectFlat(geometry, node: node, world: world, material: materials[0], opacity: opacity,
                            projection: projection, lights: lights, into: &items)
            }
        } else {
            collect(scene.rootNode, parentWorld: SCNMatrix4Identity, parentOpacity: 1, time: time,
                    projection: projection, lights: lights, into: &items)
        }
        items.sort { $0.order != $1.order ? $0.order < $1.order : $0.depth > $1.depth }
        painted = items
        for item in items { paint(item, in: context) }
        delegate?.renderer(self, didRenderScene: scene, atTime: time)
    }

    func frameLights(_ scene: SCNScene, projection: _Projection, time: Double) -> [_FrameLight] {
        var lights: [_FrameLight] = []
        func visit(_ node: SCNNode, _ parent: SCNMatrix4) {
            let world = SCNMatrix4Mult(node.localTransform(at: time), parent)
            if let light = node.light, !node.isHidden {
                let rgb = SCNMaterialProperty(contents: light.color).rgba ?? (1, 1, 1, 1)
                let k = Double(light.intensity) / 1000
                var direction = world.transformDirection(SCNVector3(0, 0, -1))
                if direction.length > 0 { direction = direction * (1 / direction.length) }
                lights.append(_FrameLight(type: light.type, color: (rgb.r * k, rgb.g * k, rgb.b * k),
                                          position: SCNVector3(world.m41, world.m42, world.m43), direction: direction))
            }
            for child in node.childNodes { visit(child, world) }
        }
        visit(scene.rootNode, SCNMatrix4Identity)
        if lights.isEmpty, autoenablesDefaultLighting {
            lights.append(_FrameLight(type: .omni, color: (1, 1, 1), position: projection.eye, direction: projection.forward))
        }
        return lights
    }

    /// The colour of a face of a material: lit by the lights where the model takes light.
    private func shade(_ material: SCNMaterial, normal: SCNVector3, at point: SCNVector3, lights: [_FrameLight],
                       opacity: Double) -> (r: Double, g: Double, b: Double, a: Double) {
        let diffuse = material.diffuse.rgba ?? (1, 1, 1, 1)
        let k = Double(material.diffuse.intensity)
        var r = diffuse.r * k, g = diffuse.g * k, b = diffuse.b * k
        let emission = material.emission.contents == nil ? (0, 0, 0, 0) : (material.emission.rgba ?? (0, 0, 0, 0))
        let lit = material.lightingModel != .constant && !lights.isEmpty
        if lit {
            var lr = 0.0, lg = 0.0, lb = 0.0
            for light in lights {
                let amount: Double
                switch light.type {
                case .ambient: amount = 1
                case .directional:
                    amount = Double(max(0, normal.dot(light.direction * -1)))
                default:
                    var toLight = light.position - point
                    let length = toLight.length
                    if length > 1e-6 { toLight = toLight * (1 / length) }
                    amount = Double(max(0, normal.dot(toLight)))
                }
                lr += light.color.r * amount; lg += light.color.g * amount; lb += light.color.b * amount
            }
            r *= lr; g *= lg; b *= lb
        }
        let e = Double(material.emission.intensity)
        r += emission.0 * e; g += emission.1 * e; b += emission.2 * e
        if let multiply = material.multiply.contents == nil ? nil : material.multiply.rgba {
            r *= multiply.r; g *= multiply.g; b *= multiply.b
        }
        let a = diffuse.a * Double(material.transparency) * opacity
        return (min(max(r, 0), 1), min(max(g, 0), 1), min(max(b, 0), 1), min(max(a, 0), 1))
    }

    private func collect(_ node: SCNNode, parentWorld: SCNMatrix4, parentOpacity: CGFloat, time: Double,
                         projection: _Projection, lights: [_FrameLight], into items: inout [_Painted]) {
        guard !node.isHidden else { return }
        let world = SCNMatrix4Mult(node.localTransform(at: time), parentWorld)
        let opacity = (_animatedOpacity(of: node, at: time) ?? node.opacity) * parentOpacity
        guard opacity > 0.001 else { return }
        if let geometry = node.geometry {
            collect(geometry, node: node, world: world, opacity: Double(opacity), projection: projection, lights: lights, into: &items)
        }
        for child in node.childNodes {
            collect(child, parentWorld: world, parentOpacity: opacity, time: time, projection: projection, lights: lights, into: &items)
        }
    }

    private func collect(_ geometry: SCNGeometry, node: SCNNode, world: SCNMatrix4, opacity: Double,
                         projection: _Projection, lights: [_FrameLight], into items: inout [_Painted]) {
        let materials = geometry.materials.isEmpty ? [geometry.firstMaterial!] : geometry.materials
        if geometry is SCNText || geometry is SCNShape {
            collectFlat(geometry, node: node, world: world, material: materials[0], opacity: opacity,
                        projection: projection, lights: lights, into: &items)
            return
        }
        let mesh = geometry.mesh
        let vertices = mesh.vertices.map { world.transformPoint($0) }
        let wireframe = debugOptions.contains(.renderAsWireframe)
        var edges: [Int: [(CGPoint, CGPoint, Double)]] = [:]
        var edgeColor: [Int: (r: Double, g: Double, b: Double, a: Double)] = [:]
        var seenEdges = Set<Int64>()
        for (face, triangle) in mesh.triangles.enumerated() {
            let material = materials[triangle.element % materials.count]
            let a = vertices[triangle.a], b = vertices[triangle.b], c = vertices[triangle.c]
            var normal = (b - a).cross(c - a)
            let length = normal.length
            guard length > 1e-12 else { continue }
            normal = normal * (1 / length)
            let toEye = projection.orthographic ? projection.forward * -1 : projection.eye - a
            let front = normal.dot(toEye) > 0
            let doubleSided = material.isDoubleSided
            if !doubleSided {
                if material.cullMode == .back && !front { continue }
                if material.cullMode == .front && front { continue }
            }
            guard let pa = projection.project(a), let pb = projection.project(b), let pc = projection.project(c) else { continue }
            let shadingNormal = front ? normal : normal * -1
            let center = (a + b + c) * (1 / 3)
            let color = shade(material, normal: shadingNormal, at: center, lights: lights, opacity: opacity)
            guard color.a > 0.001 else { continue }
            let depth = (pa.depth + pb.depth + pc.depth) / 3
            if material.fillMode == .lines || wireframe {
                let index = triangle.element
                edgeColor[index] = color
                for (i, j, p, q) in [(triangle.a, triangle.b, pa, pb), (triangle.b, triangle.c, pb, pc), (triangle.c, triangle.a, pc, pa)] {
                    let key = Int64(min(i, j)) << 32 | Int64(max(i, j))
                    guard seenEdges.insert(key).inserted else { continue }
                    edges[index, default: []].append((p.point, q.point, (p.depth + q.depth) / 2))
                }
                continue
            }
            items.append(_Painted(kind: .fill([pa.point, pb.point, pc.point]), color: color, depth: depth, order: node.renderingOrder,
                                  node: node, world: [a, b, c], normal: shadingNormal, face: face))
        }
        for (element, list) in edges {
            // Each edge is its own item, so the wire sorts with the faces around it.
            for (p, q, depth) in list {
                items.append(_Painted(kind: .lines([(p, q)]), color: edgeColor[element]!, depth: depth, order: node.renderingOrder,
                                      node: node, world: [], normal: SCNVector3(), face: 0))
            }
        }
    }

    /// Text and paths: the flat piece drawn through the affine map that takes its plane onto the view.
    private func collectFlat(_ geometry: SCNGeometry, node: SCNNode, world: SCNMatrix4, material: SCNMaterial, opacity: Double,
                             projection: _Projection, lights: [_FrameLight], into items: inout [_Painted]) {
        let bounds: CGRect
        let kind: (CGAffineTransform) -> _Painted.Kind
        var z: Float = 0
        if let text = geometry as? SCNText {
            let size = text.measuredSize
            guard size.width > 0 else { return }
            let font = text.resolvedFont
            z = Float(text.extrusionDepth) / 2
            bounds = CGRect(x: 0, y: font.descender, width: size.width, height: size.height)
            let string = text.text
            kind = { .text(string, font, $0) }
        } else if let shape = geometry as? SCNShape, let path = shape.path {
            bounds = path.bounds
            z = Float(shape.extrusionDepth) / 2
            kind = { .path(path, $0) }
        } else {
            return
        }
        let o = world.transformPoint(SCNVector3(0, 0, z))
        let ex = world.transformPoint(SCNVector3(1, 0, z)), ey = world.transformPoint(SCNVector3(0, 1, z))
        // Projected about the piece's centre, so perspective is right where most of it is.
        let cx = Float(bounds.midX), cy = Float(bounds.midY)
        let center = world.transformPoint(SCNVector3(cx, cy, z))
        guard let pc = projection.project(center),
              let px = projection.project(center + (ex - o) * max(Float(bounds.width) / 2, 1)),
              let py = projection.project(center + (ey - o) * max(Float(bounds.height) / 2, 1)) else { return }
        let sx = max(Double(bounds.width) / 2, 1), sy = max(Double(bounds.height) / 2, 1)
        let a = Double(px.point.x - pc.point.x) / sx, b = Double(px.point.y - pc.point.y) / sx
        let c = Double(py.point.x - pc.point.x) / sy, d = Double(py.point.y - pc.point.y) / sy
        // local (x, y) → view: centre + A (x - cx, y - cy).
        let tx = Double(pc.point.x) - a * Double(cx) - c * Double(cy)
        let ty = Double(pc.point.y) - b * Double(cx) - d * Double(cy)
        let map = CGAffineTransform(a: CGFloat(a), b: CGFloat(b), c: CGFloat(c), d: CGFloat(d), tx: CGFloat(tx), ty: CGFloat(ty))
        var normal = (ex - o).cross(ey - o)
        if normal.length > 0 { normal = normal * (1 / normal.length) }
        let toEye = projection.orthographic ? projection.forward * -1 : projection.eye - center
        if normal.dot(toEye) < 0 { normal = normal * -1 }
        let color = shade(material, normal: normal, at: center, lights: lights, opacity: opacity)
        items.append(_Painted(kind: kind(map), color: color, depth: pc.depth, order: node.renderingOrder,
                              node: node, world: [], normal: normal, face: 0))
    }

    private func paint(_ item: _Painted, in context: UIGraphicsRecordingContext) {
        let (r, g, b, a) = (CGFloat(item.color.r), CGFloat(item.color.g), CGFloat(item.color.b), CGFloat(item.color.a))
        switch item.kind {
        case .fill(let points):
            context.beginPath()
            context.move(to: points[0])
            for p in points.dropFirst() { context.addLine(to: p) }
            context.closePath()
            context.setFillColor(red: r, green: g, blue: b, alpha: a)
            if a >= 0.999 {
                // A hairline in the same colour closes the seams antialiasing leaves between faces.
                context.setStrokeColor(red: r, green: g, blue: b, alpha: a)
                context.setLineWidth(0.5)
                context.drawPath(using: .fillStroke)
            } else {
                context.fillPath()
            }
        case .lines(let segments):
            context.beginPath()
            for (p, q) in segments { context.move(to: p); context.addLine(to: q) }
            context.setStrokeColor(red: r, green: g, blue: b, alpha: a)
            context.setLineWidth(1)
            context.strokePath()
        case .text(let string, let font, let map):
            context.saveGState()
            // Text lays out downward from its top; the plane's y goes up.
            context.concatenate(CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: 0).concatenating(map))
            let color = UIColor(red: r, green: g, blue: b, alpha: a)
            string.draw(at: CGPoint(x: 0, y: -font.ascender), withAttributes: [.font: font, .foregroundColor: color])
            context.restoreGState()
        case .path(let path, let map):
            context.saveGState()
            context.concatenate(map)
            context.beginPath()
            context.addPath(path.cgPath)
            context.setFillColor(red: r, green: g, blue: b, alpha: a)
            context.fillPath(using: path.usesEvenOddFillRule ? .evenOdd : .winding)
            context.restoreGState()
        }
    }
}

// MARK: - SwiftUI

/// A SwiftUI view for displaying 3D SceneKit content.
@preconcurrency @MainActor
public struct SceneView: UIViewRepresentable {
    public struct Options: OptionSet, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }
        public static let allowsCameraControl = Options(rawValue: 1 << 0)
        public static let autoenablesDefaultLighting = Options(rawValue: 1 << 1)
        public static let jitteringEnabled = Options(rawValue: 1 << 2)
        public static let rendersContinuously = Options(rawValue: 1 << 3)
        public static let temporalAntialiasingEnabled = Options(rawValue: 1 << 4)
    }

    let scene: SCNScene?
    let pointOfView: SCNNode?
    let options: Options
    let preferredFramesPerSecond: Int
    let antialiasingMode: SCNAntialiasingMode
    let delegate: (any SCNSceneRendererDelegate)?

    public init(scene: SCNScene? = nil, pointOfView: SCNNode? = nil, options: Options = [], preferredFramesPerSecond: Int = 60,
                antialiasingMode: SCNAntialiasingMode = .multisampling4X, delegate: (any SCNSceneRendererDelegate)? = nil,
                technique: SCNTechnique? = nil) {
        self.scene = scene
        self.pointOfView = pointOfView
        self.options = options
        self.preferredFramesPerSecond = preferredFramesPerSecond
        self.antialiasingMode = antialiasingMode
        self.delegate = delegate
    }

    public func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        updateUIView(view, context: context)
        return view
    }

    public func updateUIView(_ view: SCNView, context: Context) {
        if view.scene !== scene { view.scene = scene }
        if view.pointOfView !== pointOfView { view.pointOfView = pointOfView }
        view.allowsCameraControl = options.contains(.allowsCameraControl)
        view.autoenablesDefaultLighting = options.contains(.autoenablesDefaultLighting)
        view.isJitteringEnabled = options.contains(.jitteringEnabled)
        view.rendersContinuously = options.contains(.rendersContinuously)
        view.isTemporalAntialiasingEnabled = options.contains(.temporalAntialiasingEnabled)
        view.preferredFramesPerSecond = preferredFramesPerSecond
        view.antialiasingMode = antialiasingMode
        view.delegate = delegate
        view.setNeedsDisplay()
    }

    public func makeCoordinator() {}
}
