// SceneKit's materials and geometries (Docs/elements/SceneKit.md): the primitives are
// triangle meshes built here (sphere, box, plane, cylinder, cone, tube, torus, capsule,
// pyramid), and text is a plane of glyphs drawn through the page's text engine.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI
import UIKit

/// A container for the color or texture of one of a material's visual properties.
@preconcurrency @MainActor
open class SCNMaterialProperty {
    /// A colour (`UIColor`, `CGColor`), an image, or a number; images draw as a mid grey.
    open var contents: Any? { didSet { _SceneClock.shared.touch() } }
    open var intensity: CGFloat = 1 { didSet { _SceneClock.shared.touch() } }
    open var contentsTransform = SCNMatrix4Identity
    open var wrapS: SCNWrapMode = .clamp
    open var wrapT: SCNWrapMode = .clamp
    open var minificationFilter: SCNFilterMode = .linear
    open var magnificationFilter: SCNFilterMode = .linear
    open var mipFilter: SCNFilterMode = .none
    open var maxAnisotropy: CGFloat = 1
    open var mappingChannel = 0
    open var borderColor: Any?
    open var textureComponents: SCNColorMask = .all

    public init() {}
    public init(contents: Any) { self.contents = contents }

    /// The contents as a colour, if they are one: a colour, a number as grey, an image as mid grey.
    var rgba: (r: Double, g: Double, b: Double, a: Double)? {
        switch contents {
        case let color as UIColor:
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            _ = color.getRed(&r, green: &g, blue: &b, alpha: &a)
            return (Double(r), Double(g), Double(b), Double(a))
        case let color as Color:
            return SCNMaterialProperty(contents: UIColor(color)).rgba
        case is UIImage:
            return (0.5, 0.5, 0.5, 1)
        case let value?:
            if let n = _number(value) { return (n, n, n, 1) }
            return nil
        case nil:
            return nil
        }
    }
}

public enum SCNWrapMode: Int, Sendable { case clamp = 1, `repeat` = 2, clampToBorder = 3, mirror = 4 }
public enum SCNFilterMode: Int, Sendable { case none = 0, nearest = 1, linear = 2 }
public enum SCNFillMode: UInt, Sendable { case fill = 0, lines = 1 }
public enum SCNCullMode: Int, Sendable { case back = 0, front = 1 }
public enum SCNTransparencyMode: Int, Sendable { case aOne = 0, rgbZero = 1, singleLayer = 2, dualLayer = 3, `default` = 4 }
public enum SCNBlendMode: Int, Sendable { case alpha = 0, add = 1, subtract = 2, multiply = 3, screen = 4, replace = 5, max = 6 }

public struct SCNColorMask: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let red = SCNColorMask(rawValue: 8)
    public static let green = SCNColorMask(rawValue: 4)
    public static let blue = SCNColorMask(rawValue: 2)
    public static let alpha = SCNColorMask(rawValue: 1)
    public static let all: SCNColorMask = [.red, .green, .blue, .alpha]
}

/// A set of shading attributes that define the appearance of a geometry's surface when rendered.
@preconcurrency @MainActor
open class SCNMaterial {
    public struct LightingModel: RawRepresentable, Hashable, Sendable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let phong = LightingModel(rawValue: "phong")
        public static let blinn = LightingModel(rawValue: "blinn")
        public static let lambert = LightingModel(rawValue: "lambert")
        public static let constant = LightingModel(rawValue: "constant")
        public static let physicallyBased = LightingModel(rawValue: "physicallyBased")
        public static let shadowOnly = LightingModel(rawValue: "shadowOnly")
    }

    open var name: String?
    public let diffuse = SCNMaterialProperty(contents: UIColor.white)
    public let ambient = SCNMaterialProperty()
    public let specular = SCNMaterialProperty()
    public let emission = SCNMaterialProperty()
    public let transparent = SCNMaterialProperty()
    public let reflective = SCNMaterialProperty()
    public let multiply = SCNMaterialProperty()
    public let normal = SCNMaterialProperty()
    public let displacement = SCNMaterialProperty()
    public let ambientOcclusion = SCNMaterialProperty()
    public let selfIllumination = SCNMaterialProperty()
    public let metalness = SCNMaterialProperty()
    public let roughness = SCNMaterialProperty()
    public let clearCoat = SCNMaterialProperty()
    public let clearCoatRoughness = SCNMaterialProperty()
    public let clearCoatNormal = SCNMaterialProperty()
    open var lightingModel: LightingModel = .blinn
    open var fillMode: SCNFillMode = .fill
    open var isDoubleSided = false
    open var cullMode: SCNCullMode = .back
    open var transparency: CGFloat = 1
    open var transparencyMode: SCNTransparencyMode = .default
    open var shininess: CGFloat = 1
    open var fresnelExponent: CGFloat = 0
    open var blendMode: SCNBlendMode = .alpha
    open var locksAmbientWithDiffuse = true
    open var writesToDepthBuffer = true
    open var readsFromDepthBuffer = true
    open var isLitPerPixel = true
    open var colorBufferWriteMask: SCNColorMask = .all

    public init() {}

    open func copy() -> Any {
        let m = SCNMaterial()
        for (a, b) in zip(m.properties, properties) {
            a.contents = b.contents; a.intensity = b.intensity; a.contentsTransform = b.contentsTransform
        }
        m.name = name; m.lightingModel = lightingModel; m.fillMode = fillMode; m.isDoubleSided = isDoubleSided
        m.cullMode = cullMode; m.transparency = transparency; m.shininess = shininess; m.blendMode = blendMode
        return m
    }

    private var properties: [SCNMaterialProperty] {
        [diffuse, ambient, specular, emission, transparent, reflective, multiply, normal, displacement, ambientOcclusion,
         selfIllumination, metalness, roughness]
    }
}

/// A triangle of a mesh: three vertex indices and the material it is drawn with.
struct _Triangle: Sendable {
    var a: Int, b: Int, c: Int
    var element: Int
}

/// A three-dimensional shape (also called a model or mesh) that can be displayed in a scene.
@preconcurrency @MainActor
open class SCNGeometry {
    open var name: String?
    open var materials: [SCNMaterial] = []
    open var subdivisionLevel = 0
    open var wantsAdaptiveSubdivision = false
    private var cachedMesh: (key: [Float], vertices: [SCNVector3], triangles: [_Triangle])?

    public init() {}

    /// The first material, made when there is none.
    open var firstMaterial: SCNMaterial? {
        get {
            if materials.isEmpty { materials = [SCNMaterial()] }
            return materials.first
        }
        set {
            guard let newValue else { if !materials.isEmpty { materials.removeFirst() }; return }
            if materials.isEmpty { materials = [newValue] } else { materials[0] = newValue }
        }
    }

    open func material(named name: String) -> SCNMaterial? { materials.first { $0.name == name } }

    open func copy() -> Any { self }

    open var boundingBox: (min: SCNVector3, max: SCNVector3) {
        get {
            let vertices = mesh.vertices
            guard var lo = vertices.first else { return (SCNVector3(), SCNVector3()) }
            var hi = lo
            for v in vertices {
                lo = SCNVector3(min(lo.x, v.x), min(lo.y, v.y), min(lo.z, v.z))
                hi = SCNVector3(max(hi.x, v.x), max(hi.y, v.y), max(hi.z, v.z))
            }
            return (lo, hi)
        }
        set {}
    }

    open var boundingSphere: (center: SCNVector3, radius: Float) {
        let (lo, hi) = boundingBox
        let center = (lo + hi) * 0.5
        return (center, (hi - center).length)
    }

    // MARK: Meshes

    /// What a mesh depends on: a change rebuilds it.
    var meshKey: [Float] { [] }

    /// The mesh in the geometry's coordinates: vertices and triangles counterclockwise from outside.
    func buildMesh() -> (vertices: [SCNVector3], triangles: [_Triangle]) { ([], []) }

    var mesh: (vertices: [SCNVector3], triangles: [_Triangle]) {
        let key = meshKey
        if let cachedMesh, cachedMesh.key == key { return (cachedMesh.vertices, cachedMesh.triangles) }
        let built = buildMesh()
        cachedMesh = (key, built.vertices, built.triangles)
        return built
    }
}

/// A grid of quads into triangles: `rows` + 1 by `columns` + 1 vertices, counterclockwise as laid out.
func _grid(rows: Int, columns: Int, element: Int = 0, offset: Int = 0, flip: Bool = false) -> [_Triangle] {
    var triangles: [_Triangle] = []
    for r in 0..<rows {
        for c in 0..<columns {
            let i = offset + r * (columns + 1) + c
            let j = i + columns + 1
            if flip {
                triangles.append(_Triangle(a: i, b: i + 1, c: j, element: element))
                triangles.append(_Triangle(a: i + 1, b: j + 1, c: j, element: element))
            } else {
                triangles.append(_Triangle(a: i, b: j, c: i + 1, element: element))
                triangles.append(_Triangle(a: i + 1, b: j, c: j + 1, element: element))
            }
        }
    }
    return triangles
}

/// A sphere: `segmentCount` slices around and half as many from pole to pole.
@preconcurrency @MainActor
open class SCNSphere: SCNGeometry {
    open var radius: CGFloat = 0.5
    open var segmentCount = 48
    open var isGeodesic = false
    public override init() { super.init() }
    public init(radius: CGFloat) { self.radius = radius; super.init() }

    override var meshKey: [Float] { [Float(radius), Float(segmentCount)] }

    override func buildMesh() -> (vertices: [SCNVector3], triangles: [_Triangle]) {
        let around = max(segmentCount, 3), down = max(segmentCount / 2, 2)
        var vertices: [SCNVector3] = []
        let r = Float(radius)
        for i in 0...down {
            let phi = Float.pi * Float(i) / Float(down)    // from the north pole
            for j in 0...around {
                let theta = 2 * Float.pi * Float(j) / Float(around)
                vertices.append(SCNVector3(r * _sinF(phi) * _sinF(theta), r * _cosF(phi), r * _sinF(phi) * _cosF(theta)))
            }
        }
        // Rows run north to south and columns east (counterclockwise seen from above): outward faces.
        return (vertices, _grid(rows: down, columns: around).filter { t in
            vertices[t.a] != vertices[t.b] && vertices[t.b] != vertices[t.c] && vertices[t.a] != vertices[t.c]
        })
    }
}

/// A six-sided box (its chamfer kept, not rounded).
@preconcurrency @MainActor
open class SCNBox: SCNGeometry {
    open var width: CGFloat = 1
    open var height: CGFloat = 1
    open var length: CGFloat = 1
    open var chamferRadius: CGFloat = 0
    open var widthSegmentCount = 1
    open var heightSegmentCount = 1
    open var lengthSegmentCount = 1
    open var chamferSegmentCount = 5
    public override init() { super.init() }
    public init(width: CGFloat, height: CGFloat, length: CGFloat, chamferRadius: CGFloat) {
        self.width = width; self.height = height; self.length = length; self.chamferRadius = chamferRadius
        super.init()
    }

    override var meshKey: [Float] { [Float(width), Float(height), Float(length)] }

    override func buildMesh() -> (vertices: [SCNVector3], triangles: [_Triangle]) {
        let x = Float(width) / 2, y = Float(height) / 2, z = Float(length) / 2
        // Front, right, back, left, top, bottom: each face's corners counterclockwise from outside.
        let faces: [[SCNVector3]] = [
            [SCNVector3(-x, -y, z), SCNVector3(x, -y, z), SCNVector3(x, y, z), SCNVector3(-x, y, z)],
            [SCNVector3(x, -y, z), SCNVector3(x, -y, -z), SCNVector3(x, y, -z), SCNVector3(x, y, z)],
            [SCNVector3(x, -y, -z), SCNVector3(-x, -y, -z), SCNVector3(-x, y, -z), SCNVector3(x, y, -z)],
            [SCNVector3(-x, -y, -z), SCNVector3(-x, -y, z), SCNVector3(-x, y, z), SCNVector3(-x, y, -z)],
            [SCNVector3(-x, y, z), SCNVector3(x, y, z), SCNVector3(x, y, -z), SCNVector3(-x, y, -z)],
            [SCNVector3(-x, -y, -z), SCNVector3(x, -y, -z), SCNVector3(x, -y, z), SCNVector3(-x, -y, z)],
        ]
        var vertices: [SCNVector3] = [], triangles: [_Triangle] = []
        for (f, face) in faces.enumerated() {
            let base = vertices.count
            vertices += face
            // A box may have a material per face, in this order.
            triangles.append(_Triangle(a: base, b: base + 1, c: base + 2, element: f))
            triangles.append(_Triangle(a: base, b: base + 2, c: base + 3, element: f))
        }
        return (vertices, triangles)
    }
}

/// A rectangle in the xy plane facing +z, its corners rounded by `cornerRadius`.
@preconcurrency @MainActor
open class SCNPlane: SCNGeometry {
    open var width: CGFloat = 1
    open var height: CGFloat = 1
    open var cornerRadius: CGFloat = 0
    open var cornerSegmentCount = 10
    open var widthSegmentCount = 1
    open var heightSegmentCount = 1
    public override init() { super.init() }
    public init(width: CGFloat, height: CGFloat) { self.width = width; self.height = height; super.init() }

    override var meshKey: [Float] { [Float(width), Float(height), Float(cornerRadius), Float(cornerSegmentCount)] }

    override func buildMesh() -> (vertices: [SCNVector3], triangles: [_Triangle]) {
        let w = Float(width) / 2, h = Float(height) / 2
        let radius = min(Float(cornerRadius), w, h)
        guard radius > 0 else {
            return ([SCNVector3(-w, -h, 0), SCNVector3(w, -h, 0), SCNVector3(w, h, 0), SCNVector3(-w, h, 0)],
                    [_Triangle(a: 0, b: 1, c: 2, element: 0), _Triangle(a: 0, b: 2, c: 3, element: 0)])
        }
        // A fan around the centre through each rounded corner, counterclockwise from the bottom right.
        var vertices = [SCNVector3(0, 0, 0)]
        let steps = max(cornerSegmentCount, 1)
        let centres = [(w - radius, -h + radius, -Float.pi / 2), (w - radius, h - radius, 0), (-w + radius, h - radius, Float.pi / 2), (-w + radius, -h + radius, Float.pi)]
        for (cx, cy, start) in centres {
            for s in 0...steps {
                let a = start + Float.pi / 2 * Float(s) / Float(steps)
                vertices.append(SCNVector3(cx + radius * _cosF(a), cy + radius * _sinF(a), 0))
            }
        }
        var triangles: [_Triangle] = []
        let ring = vertices.count - 1
        for i in 0..<ring { triangles.append(_Triangle(a: 0, b: 1 + i, c: 1 + (i + 1) % ring, element: 0)) }
        return (vertices, triangles)
    }
}

/// A ring of `radialSegmentCount` around the y axis from -height/2 to height/2, its radius going
/// from `bottom` to `top`, with caps where the radius isn't zero.
@MainActor
func _lathe(bottom: Float, top: Float, height: Float, segments: Int, caps: Bool = true) -> (vertices: [SCNVector3], triangles: [_Triangle]) {
    let n = max(segments, 3)
    var vertices: [SCNVector3] = []
    for (radius, y) in [(top, height / 2), (bottom, -height / 2)] {
        for j in 0...n {
            let theta = 2 * Float.pi * Float(j) / Float(n)
            vertices.append(SCNVector3(radius * _sinF(theta), y, radius * _cosF(theta)))
        }
    }
    var triangles = _grid(rows: 1, columns: n)
    if caps {
        for (radius, y, element, up) in [(top, height / 2, 1, true), (bottom, -height / 2, 2, false)] where radius > 0 {
            let centre = vertices.count
            vertices.append(SCNVector3(0, y, 0))
            let start = vertices.count
            for j in 0..<n {
                let theta = 2 * Float.pi * Float(j) / Float(n)
                vertices.append(SCNVector3(radius * _sinF(theta), y, radius * _cosF(theta)))
            }
            for j in 0..<n {
                let a = start + j, b = start + (j + 1) % n
                triangles.append(up ? _Triangle(a: centre, b: a, c: b, element: element) : _Triangle(a: centre, b: b, c: a, element: element))
            }
        }
    }
    return (vertices, triangles)
}

@preconcurrency @MainActor
open class SCNCylinder: SCNGeometry {
    open var radius: CGFloat = 0.5
    open var height: CGFloat = 1
    open var radialSegmentCount = 48
    open var heightSegmentCount = 1
    public override init() { super.init() }
    public init(radius: CGFloat, height: CGFloat) { self.radius = radius; self.height = height; super.init() }
    override var meshKey: [Float] { [Float(radius), Float(height), Float(radialSegmentCount)] }
    override func buildMesh() -> (vertices: [SCNVector3], triangles: [_Triangle]) {
        _lathe(bottom: Float(radius), top: Float(radius), height: Float(height), segments: radialSegmentCount)
    }
}

@preconcurrency @MainActor
open class SCNCone: SCNGeometry {
    open var topRadius: CGFloat = 0
    open var bottomRadius: CGFloat = 0.5
    open var height: CGFloat = 1
    open var radialSegmentCount = 48
    open var heightSegmentCount = 1
    public override init() { super.init() }
    public init(topRadius: CGFloat, bottomRadius: CGFloat, height: CGFloat) {
        self.topRadius = topRadius; self.bottomRadius = bottomRadius; self.height = height
        super.init()
    }
    override var meshKey: [Float] { [Float(topRadius), Float(bottomRadius), Float(height), Float(radialSegmentCount)] }
    override func buildMesh() -> (vertices: [SCNVector3], triangles: [_Triangle]) {
        _lathe(bottom: Float(bottomRadius), top: Float(topRadius), height: Float(height), segments: radialSegmentCount)
    }
}

/// A tube: the outer wall (its inner wall and rims are behind it from most angles, and drawn as the outer one's ends).
@preconcurrency @MainActor
open class SCNTube: SCNGeometry {
    open var innerRadius: CGFloat = 0.25
    open var outerRadius: CGFloat = 0.5
    open var height: CGFloat = 1
    open var radialSegmentCount = 48
    open var heightSegmentCount = 1
    public override init() { super.init() }
    public init(innerRadius: CGFloat, outerRadius: CGFloat, height: CGFloat) {
        self.innerRadius = innerRadius; self.outerRadius = outerRadius; self.height = height
        super.init()
    }
    override var meshKey: [Float] { [Float(innerRadius), Float(outerRadius), Float(height), Float(radialSegmentCount)] }
    override func buildMesh() -> (vertices: [SCNVector3], triangles: [_Triangle]) {
        var outer = _lathe(bottom: Float(outerRadius), top: Float(outerRadius), height: Float(height), segments: radialSegmentCount, caps: false)
        let inner = _lathe(bottom: Float(innerRadius), top: Float(innerRadius), height: Float(height), segments: radialSegmentCount, caps: false)
        let offset = outer.vertices.count
        outer.vertices += inner.vertices
        outer.triangles += inner.triangles.map { _Triangle(a: $0.a + offset, b: $0.c + offset, c: $0.b + offset, element: 0) }
        return outer
    }
}

@preconcurrency @MainActor
open class SCNCapsule: SCNGeometry {
    open var capRadius: CGFloat = 0.5
    open var height: CGFloat = 2
    open var radialSegmentCount = 48
    open var heightSegmentCount = 1
    open var capSegmentCount = 24
    public override init() { super.init() }
    public init(capRadius: CGFloat, height: CGFloat) { self.capRadius = capRadius; self.height = height; super.init() }
    override var meshKey: [Float] { [Float(capRadius), Float(height), Float(radialSegmentCount), Float(capSegmentCount)] }
    override func buildMesh() -> (vertices: [SCNVector3], triangles: [_Triangle]) {
        // A sphere split at its equator, the halves moved apart by the straight part.
        let r = Float(capRadius), straight = max(Float(height) - 2 * r, 0) / 2
        let around = max(radialSegmentCount, 3), down = max(capSegmentCount, 2) & ~1
        var vertices: [SCNVector3] = []
        for i in 0...down {
            let phi = Float.pi * Float(i) / Float(down)
            let shift: Float = i <= down / 2 ? straight : -straight
            for j in 0...around {
                let theta = 2 * Float.pi * Float(j) / Float(around)
                vertices.append(SCNVector3(r * _sinF(phi) * _sinF(theta), r * _cosF(phi) + shift, r * _sinF(phi) * _cosF(theta)))
            }
            if i == down / 2 {
                for j in 0...around {
                    let theta = 2 * Float.pi * Float(j) / Float(around)
                    vertices.append(SCNVector3(r * _sinF(theta), -straight, r * _cosF(theta)))
                }
            }
        }
        return (vertices, _grid(rows: down + 1, columns: around))
    }
}

@preconcurrency @MainActor
open class SCNTorus: SCNGeometry {
    open var ringRadius: CGFloat = 0.5
    open var pipeRadius: CGFloat = 0.25
    open var ringSegmentCount = 48
    open var pipeSegmentCount = 24
    public override init() { super.init() }
    public init(ringRadius: CGFloat, pipeRadius: CGFloat) { self.ringRadius = ringRadius; self.pipeRadius = pipeRadius; super.init() }
    override var meshKey: [Float] { [Float(ringRadius), Float(pipeRadius), Float(ringSegmentCount), Float(pipeSegmentCount)] }
    override func buildMesh() -> (vertices: [SCNVector3], triangles: [_Triangle]) {
        let ring = max(ringSegmentCount, 3), pipe = max(pipeSegmentCount, 3)
        let R = Float(ringRadius), r = Float(pipeRadius)
        var vertices: [SCNVector3] = []
        for i in 0...pipe {
            let phi = 2 * Float.pi * Float(i) / Float(pipe)   // from the outer equator, up and over
            for j in 0...ring {
                let theta = 2 * Float.pi * Float(j) / Float(ring)
                let d = R + r * _cosF(phi)
                vertices.append(SCNVector3(d * _sinF(theta), r * _sinF(phi), d * _cosF(theta)))
            }
        }
        return (vertices, _grid(rows: pipe, columns: ring, flip: true))
    }
}

@preconcurrency @MainActor
open class SCNPyramid: SCNGeometry {
    open var width: CGFloat = 1
    open var height: CGFloat = 1
    open var length: CGFloat = 1
    public override init() { super.init() }
    public init(width: CGFloat, height: CGFloat, length: CGFloat) { self.width = width; self.height = height; self.length = length; super.init() }
    override var meshKey: [Float] { [Float(width), Float(height), Float(length)] }
    override func buildMesh() -> (vertices: [SCNVector3], triangles: [_Triangle]) {
        let x = Float(width) / 2, z = Float(length) / 2, h = Float(height)
        let vertices = [SCNVector3(-x, 0, z), SCNVector3(x, 0, z), SCNVector3(x, 0, -z), SCNVector3(-x, 0, -z), SCNVector3(0, h, 0)]
        let triangles = [
            _Triangle(a: 0, b: 1, c: 4, element: 0), _Triangle(a: 1, b: 2, c: 4, element: 0),
            _Triangle(a: 2, b: 3, c: 4, element: 0), _Triangle(a: 3, b: 0, c: 4, element: 0),
            _Triangle(a: 0, b: 3, c: 2, element: 0), _Triangle(a: 0, b: 2, c: 1, element: 0),
        ]
        return (vertices, triangles)
    }
}

/// An infinite plane: drawn as a large square at y = 0 facing up.
@preconcurrency @MainActor
open class SCNFloor: SCNGeometry {
    open var reflectivity: CGFloat = 0.25
    open var reflectionFalloffStart: CGFloat = 0
    open var reflectionFalloffEnd: CGFloat = 0
    open var width: CGFloat = 0
    open var length: CGFloat = 0
    public override init() { super.init() }
    override var meshKey: [Float] { [Float(width), Float(length)] }
    override func buildMesh() -> (vertices: [SCNVector3], triangles: [_Triangle]) {
        let x = width > 0 ? Float(width) / 2 : 100, z = length > 0 ? Float(length) / 2 : 100
        let n = 8
        var vertices: [SCNVector3] = []
        for i in 0...n { for j in 0...n { vertices.append(SCNVector3(-x + 2 * x * Float(j) / Float(n), 0, -z + 2 * z * Float(i) / Float(n))) } }
        return (vertices, _grid(rows: n, columns: n))
    }
}

/// Text in the xy plane, its baseline on y = 0, `font.pointSize` scene units tall per point
/// (the extrusion is kept, not drawn); the glyphs are drawn through the page's text engine.
@preconcurrency @MainActor
open class SCNText: SCNGeometry {
    open var string: Any?
    open var extrusionDepth: CGFloat = 1
    open var font: UIFont! = UIFont(name: "Helvetica", size: 36) ?? UIFont.systemFont(ofSize: 36)
    open var flatness: CGFloat = 0.6
    open var chamferRadius: CGFloat = 0
    open var isWrapped = false
    open var containerFrame: CGRect = .zero
    open var alignmentMode: String = "natural"
    open var truncationMode: String = "none"

    public override init() { super.init() }
    public init(string: Any?, extrusionDepth: CGFloat) { self.string = string; self.extrusionDepth = extrusionDepth; super.init() }

    /// The text as a plain string.
    var text: String {
        switch string {
        case let s as String: return s
        case let s as NSAttributedString: return s.string
        case let s?: return "\(s)"
        case nil: return ""
        }
    }

    var resolvedFont: UIFont { font ?? UIFont.systemFont(ofSize: 36) }

    /// The text's size in scene units, measured through the page's text engine.
    var measuredSize: CGSize {
        guard !text.isEmpty else { return .zero }
        return text.size(withAttributes: [.font: resolvedFont])
    }

    override var meshKey: [Float] {
        let size = measuredSize
        return [Float(size.width), Float(size.height), Float(extrusionDepth)]
    }

    /// The box the glyphs fill: their width, from the descender to the ascender, and the extrusion.
    override func buildMesh() -> (vertices: [SCNVector3], triangles: [_Triangle]) {
        let size = measuredSize
        let font = resolvedFont
        let lo = Float(font.descender), hi = lo + Float(size.height)
        let w = Float(size.width), d = Float(extrusionDepth)
        return ([SCNVector3(0, lo, 0), SCNVector3(w, lo, 0), SCNVector3(w, hi, d), SCNVector3(0, hi, d)], [])
    }
}

/// A shape extruded from a path in the xy plane: the path's outline drawn flat, facing +z.
@preconcurrency @MainActor
open class SCNShape: SCNGeometry {
    open var path: UIBezierPath?
    open var extrusionDepth: CGFloat = 1
    open var chamferRadius: CGFloat = 0
    public override init() { super.init() }
    public init(path: UIBezierPath?, extrusionDepth: CGFloat) { self.path = path; self.extrusionDepth = extrusionDepth; super.init() }
    override var meshKey: [Float] {
        let b = path?.bounds ?? .zero
        return [Float(b.minX), Float(b.minY), Float(b.width), Float(b.height), Float(extrusionDepth)]
    }
    override func buildMesh() -> (vertices: [SCNVector3], triangles: [_Triangle]) {
        let b = path?.bounds ?? .zero
        let d = Float(extrusionDepth) / 2
        return ([SCNVector3(Float(b.minX), Float(b.minY), -d), SCNVector3(Float(b.maxX), Float(b.maxY), d)], [])
    }
}
