// SceneKit through the browser's GPU: where the host draws meshes (DisplayMesh.hostRenders),
// SCNView packs the frame's camera, lights, meshes and materials as numbers in one drawMesh
// command, and the renderer in MeshScript.swift draws them with WebGL2 (depth buffer,
// multisampling, per-pixel lighting, textures), falling back to a painter's-algorithm canvas
// drawing without WebGL. Text and paths stay with the CPU path and are painted over the meshes.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI
import UIKit

/// A geometry's mesh packed once for the renderer: per vertex position, normal and texture
/// coordinate (8 numbers), and the triangles of each element as vertex indices.
struct _MeshPack {
    var key: [Float]
    var version: Int
    var vertices: [Double]
    var elements: [[Double]]

    @MainActor private static var counter = 0
    @MainActor static func nextID() -> Int { counter += 1; return counter }
    @MainActor private static var versions = 0
    @MainActor static func nextVersion() -> Int { versions += 1; return versions }
}

extension SCNGeometry {
    /// The packed mesh, rebuilt when the mesh changes.
    var meshPack: _MeshPack {
        let key = meshKey
        if let pack = _meshPack, pack.key == key { return pack }
        let (vertices, triangles) = mesh
        let normals = meshNormals(vertices, triangles)
        let uvs = meshUVs(vertices)
        var values: [Double] = []
        values.reserveCapacity(vertices.count * 8)
        for (k, v) in vertices.enumerated() {
            let n = normals[k], uv = uvs[k]
            values += [Double(v.x), Double(v.y), Double(v.z), Double(n.x), Double(n.y), Double(n.z), uv.0, uv.1]
        }
        let count = triangles.reduce(0) { max($0, $1.element + 1) }
        var elements = Array(repeating: [Double](), count: max(count, 1))
        for t in triangles { elements[t.element] += [Double(t.a), Double(t.b), Double(t.c)] }
        let pack = _MeshPack(key: key, version: _MeshPack.nextVersion(), vertices: values, elements: elements)
        _meshPack = pack
        return pack
    }

    /// Smooth normals: the sphere's are its directions; elsewhere each vertex averages the
    /// faces that share it (boxes and planes have their own vertices per face, so stay flat).
    func meshNormals(_ vertices: [SCNVector3], _ triangles: [_Triangle]) -> [SCNVector3] {
        if self is SCNSphere {
            return vertices.map { $0.length > 0 ? $0 * (1 / $0.length) : SCNVector3(0, 1, 0) }
        }
        var normals = Array(repeating: SCNVector3(0, 0, 0), count: vertices.count)
        for t in triangles {
            let n = (vertices[t.b] - vertices[t.a]).cross(vertices[t.c] - vertices[t.a])
            normals[t.a] = normals[t.a] + n; normals[t.b] = normals[t.b] + n; normals[t.c] = normals[t.c] + n
        }
        return normals.map { $0.length > 1e-12 ? $0 * (1 / $0.length) : SCNVector3(0, 0, 1) }
    }

    /// Texture coordinates, top-left origin: the sphere's grid, each box face whole, planes
    /// across their extent, anything else wrapped around the y axis.
    func meshUVs(_ vertices: [SCNVector3]) -> [(Double, Double)] {
        if let sphere = self as? SCNSphere {
            let around = max(sphere.segmentCount, 3)
            return vertices.indices.map { k in (Double(k % (around + 1)) / Double(around), Double(k / (around + 1)) / Double(max(around / 2, 2))) }
        }
        if self is SCNBox {
            let corners: [(Double, Double)] = [(0, 1), (1, 1), (1, 0), (0, 0)]
            return vertices.indices.map { corners[$0 % 4] }
        }
        let (lo, hi) = boundingBox
        let w = Double(max(hi.x - lo.x, 1e-6)), h = Double(max(hi.y - lo.y, 1e-6)), l = Double(max(hi.z - lo.z, 1e-6))
        if self is SCNFloor {
            return vertices.map { (Double($0.x - lo.x) / w, Double($0.z - lo.z) / l) }
        }
        if self is SCNPlane {
            return vertices.map { (Double($0.x - lo.x) / w, 1 - Double($0.y - lo.y) / h) }
        }
        return vertices.map { v in (Double(_atan2(Double(v.x), Double(v.z))) / (2 * Double.pi) + 0.5, 1 - Double(v.y - lo.y) / h) }
    }
}

/// Builds one frame's payload. The layout (read by MeshScript.swift):
/// header: version, orthographic, focal, near, far, eye x y z, the view matrix (16, row vectors),
/// light count, then per light: type (0 ambient, 1 directional, 2 positional), r g b, position,
/// direction; then the mesh count, and per mesh: geometry id, version, the world matrix (16),
/// vertex count, vertices (8 each), element count, and per element: the material (cull: 0 back,
/// 1 front, 2 none; lines; lit; diffuse r g b a; emission r g b; multiply r g b; opacity;
/// texture file index or -1; wrap s, t; rendering order), index count, indices.
@MainActor
struct _MeshWriter {
    var projection: _Projection
    var lights: [_FrameLight]
    var zFar: Double
    var wireframe: Bool
    var values: [Double] = []
    var files: [String] = []
    var meshCount = 0
    /// Text and shapes, painted by the CPU path.
    var flat: [(SCNNode, SCNMatrix4, Double)] = []
    private var meshes: [Double] = []

    init(projection: _Projection, lights: [_FrameLight], zFar: Double, wireframe: Bool) {
        self.projection = projection; self.lights = lights; self.zFar = zFar; self.wireframe = wireframe
    }

    mutating func collect(_ node: SCNNode, parentWorld: SCNMatrix4, parentOpacity: CGFloat, time: Double) {
        guard !node.isHidden else { return }
        let world = SCNMatrix4Mult(node.localTransform(at: time), parentWorld)
        let opacity = (_animatedOpacity(of: node, at: time) ?? node.opacity) * parentOpacity
        guard opacity > 0.001 else { return }
        if let geometry = node.geometry {
            if geometry is SCNText || geometry is SCNShape {
                flat.append((node, world, Double(opacity)))
            } else {
                add(geometry, node: node, world: world, opacity: Double(opacity))
            }
        }
        for child in node.childNodes { collect(child, parentWorld: world, parentOpacity: opacity, time: time) }
    }

    private mutating func add(_ geometry: SCNGeometry, node: SCNNode, world: SCNMatrix4, opacity: Double) {
        let pack = geometry.meshPack
        guard !pack.vertices.isEmpty else { return }
        let materials = geometry.materials.isEmpty ? [geometry.firstMaterial!] : geometry.materials
        meshCount += 1
        meshes += [Double(geometry._meshID), Double(pack.version)]
        meshes += Self.matrix(world)
        meshes.append(Double(pack.vertices.count / 8))
        meshes += pack.vertices
        let elements = pack.elements.enumerated().filter { !$0.element.isEmpty }
        meshes.append(Double(elements.count))
        for (index, indices) in elements {
            material(materials[index % materials.count], opacity: opacity, order: node.renderingOrder)
            meshes.append(Double(indices.count))
            meshes += indices
        }
    }

    private mutating func material(_ m: SCNMaterial, opacity: Double, order: Int) {
        let cull: Double = m.isDoubleSided ? 2 : (m.cullMode == .front ? 1 : 0)
        let lit = m.lightingModel != .constant && !lights.isEmpty
        let k = Double(m.diffuse.intensity)
        var texture = -1.0
        var diffuse = m.diffuse.rgba ?? (1, 1, 1, 1)
        if let file = Self.textureFile(m.diffuse.contents) {
            if let at = files.firstIndex(of: file) { texture = Double(at) } else { texture = Double(files.count); files.append(file) }
            diffuse = (1, 1, 1, 1)
        }
        let emission: (Double, Double, Double, Double) = m.emission.contents == nil ? (0, 0, 0, 0) : (m.emission.rgba.map { ($0.r, $0.g, $0.b, $0.a) } ?? (0, 0, 0, 0))
        let e = Double(m.emission.intensity)
        let multiply: (Double, Double, Double, Double) = m.multiply.contents == nil ? (1, 1, 1, 1) : (m.multiply.rgba.map { ($0.r, $0.g, $0.b, $0.a) } ?? (1, 1, 1, 1))
        meshes += [cull, m.fillMode == .lines || wireframe ? 1 : 0, lit ? 1 : 0,
                   diffuse.r * k, diffuse.g * k, diffuse.b * k, diffuse.a,
                   emission.0 * e, emission.1 * e, emission.2 * e,
                   multiply.0, multiply.1, multiply.2,
                   Double(m.transparency) * opacity, texture,
                   Double(m.diffuse.wrapS.rawValue), Double(m.diffuse.wrapT.rawValue), Double(order)]
    }

    /// The page file an image's contents draw from: its bytes as a data URL, the catalog's
    /// file, or a drawing rasterised to PNG (the last few kept, as images are often reused).
    static func textureFile(_ contents: Any?) -> String? {
        let image: UIImage
        switch contents {
        case let value as UIImage: image = value
        case let name as String: guard let value = UIImage(named: name) else { return nil }; image = value
        default: return nil
        }
        if let file = image._textureFile { return file }
        guard image.drawing != nil else { return nil }
        if let hit = rasterised.first(where: { $0.0 === image }) { return hit.1 }
        guard let png = image.pngData() else { return nil }
        let file = "data:image/png;base64," + png.base64EncodedString()
        rasterised.append((image, file))
        if rasterised.count > 4 { rasterised.removeFirst() }
        return file
    }
    private static var rasterised: [(UIImage, String)] = []

    static func matrix(_ m: SCNMatrix4) -> [Double] {
        [m.m11, m.m12, m.m13, m.m14, m.m21, m.m22, m.m23, m.m24, m.m31, m.m32, m.m33, m.m34, m.m41, m.m42, m.m43, m.m44].map { Double($0) }
    }

    func finish() -> DisplayMesh {
        var out: [Double] = [1, projection.orthographic ? 1 : 0, projection.focal, projection.near, max(zFar, projection.near * 2),
                             Double(projection.eye.x), Double(projection.eye.y), Double(projection.eye.z)]
        out += Self.matrix(projection.view)
        out.append(Double(lights.count))
        for light in lights {
            let type: Double = light.type == .ambient ? 0 : (light.type == .directional ? 1 : 2)
            out += [type, light.color.r, light.color.g, light.color.b,
                    Double(light.position.x), Double(light.position.y), Double(light.position.z),
                    Double(light.direction.x), Double(light.direction.y), Double(light.direction.z)]
        }
        out.append(Double(meshCount))
        out += meshes
        return DisplayMesh(values: out, files: files)
    }
}
