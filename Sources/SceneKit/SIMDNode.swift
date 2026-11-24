// SceneKit's simd forms (Docs/elements/SceneKit.md, "simd"): conversions between SceneKit's
// vectors and matrices and simd's, and each node property again in simd types
// (`simdPosition`, `simdOrientation`, `simdPivot`, ...), reading and writing the same state.
// A matrix's columns are SceneKit's rows: `columns.3` holds the translation SCNMatrix4 keeps
// in m41...m43.
import UIKit

extension SCNVector3 {
    public init(_ v: simd_float3) { self.init(v.x, v.y, v.z) }
    public init(_ v: simd_double3) { self.init(Float(v.x), Float(v.y), Float(v.z)) }
}

extension SCNVector4 {
    public init(_ v: simd_float4) { self.init(v.x, v.y, v.z, v.w) }
    public init(_ v: simd_double4) { self.init(Float(v.x), Float(v.y), Float(v.z), Float(v.w)) }
}

extension SCNMatrix4 {
    public init(_ m: simd_float4x4) {
        self.init(m11: m.columns.0.x, m12: m.columns.0.y, m13: m.columns.0.z, m14: m.columns.0.w,
                  m21: m.columns.1.x, m22: m.columns.1.y, m23: m.columns.1.z, m24: m.columns.1.w,
                  m31: m.columns.2.x, m32: m.columns.2.y, m33: m.columns.2.z, m34: m.columns.2.w,
                  m41: m.columns.3.x, m42: m.columns.3.y, m43: m.columns.3.z, m44: m.columns.3.w)
    }
}

extension SIMD3 where Scalar == Float {
    public init(_ v: SCNVector3) { self.init(v.x, v.y, v.z) }
}

extension SIMD4 where Scalar == Float {
    public init(_ v: SCNVector4) { self.init(v.x, v.y, v.z, v.w) }
}

extension simd_float4x4 {
    public init(_ m: SCNMatrix4) {
        self.init(SIMD4<Float>(m.m11, m.m12, m.m13, m.m14), SIMD4<Float>(m.m21, m.m22, m.m23, m.m24),
                  SIMD4<Float>(m.m31, m.m32, m.m33, m.m34), SIMD4<Float>(m.m41, m.m42, m.m43, m.m44))
    }
}

extension SCNNode {
    public var simdPosition: simd_float3 {
        get { simd_float3(position) }
        set { position = SCNVector3(newValue) }
    }

    public var simdScale: simd_float3 {
        get { simd_float3(scale) }
        set { scale = SCNVector3(newValue) }
    }

    public var simdEulerAngles: simd_float3 {
        get { simd_float3(eulerAngles) }
        set { eulerAngles = SCNVector3(newValue) }
    }

    /// The orientation as a unit quaternion, (ix, iy, iz, r) as SceneKit's (x, y, z, w).
    public var simdOrientation: simd_quatf {
        get { simd_quatf(vector: simd_float4(orientation)) }
        set { orientation = SCNVector4(newValue.vector) }
    }

    /// The orientation as an axis and an angle in radians (w).
    public var simdRotation: simd_float4 {
        get { simd_float4(rotation) }
        set { rotation = SCNVector4(newValue) }
    }

    public var simdTransform: simd_float4x4 {
        get { simd_float4x4(transform) }
        set { transform = SCNMatrix4(newValue) }
    }

    public var simdPivot: simd_float4x4 {
        get { simd_float4x4(pivot) }
        set { pivot = SCNMatrix4(newValue) }
    }

    public var simdWorldTransform: simd_float4x4 {
        get { simd_float4x4(worldTransform) }
        set {
            // The world transform is the pivot undone, then the local transform, then the
            // parents': so the local one is the pivot, then the world one, then the parents' undone.
            let world = SCNMatrix4(newValue)
            let local = parent.map { SCNMatrix4Mult(world, SCNMatrix4Invert($0.worldTransform)) } ?? world
            transform = pivot == SCNMatrix4Identity ? local : SCNMatrix4Mult(pivot, local)
        }
    }

    public var simdWorldPosition: simd_float3 {
        get { simd_float3(worldPosition) }
        set { worldPosition = SCNVector3(newValue) }
    }

    public var simdWorldOrientation: simd_quatf {
        get { simd_quatf(vector: simd_float4(worldOrientation)) }
        set {
            let parentWorld = parent.map { simd_quatf(vector: simd_float4($0.worldOrientation)) } ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
            simdOrientation = (parentWorld.inverse * newValue).normalized
        }
    }

    /// The node's front (-z), up (y) and right (x) in the scene's coordinates.
    public var simdWorldFront: simd_float3 { simd_normalize(simd_float3(convertVector(SCNVector3(0, 0, -1), to: nil))) }
    public var simdWorldUp: simd_float3 { simd_normalize(simd_float3(convertVector(SCNVector3(0, 1, 0), to: nil))) }
    public var simdWorldRight: simd_float3 { simd_normalize(simd_float3(convertVector(SCNVector3(1, 0, 0), to: nil))) }

    public static var simdLocalFront: simd_float3 { simd_float3(0, 0, -1) }
    public static var simdLocalUp: simd_float3 { simd_float3(0, 1, 0) }
    public static var simdLocalRight: simd_float3 { simd_float3(1, 0, 0) }

    public func simdConvertPosition(_ position: simd_float3, to node: SCNNode?) -> simd_float3 {
        simd_float3(convertPosition(SCNVector3(position), to: node))
    }

    public func simdConvertPosition(_ position: simd_float3, from node: SCNNode?) -> simd_float3 {
        simd_float3(convertPosition(SCNVector3(position), from: node))
    }

    public func simdConvertVector(_ vector: simd_float3, to node: SCNNode?) -> simd_float3 {
        simd_float3(convertVector(SCNVector3(vector), to: node))
    }

    public func simdConvertVector(_ vector: simd_float3, from node: SCNNode?) -> simd_float3 {
        simd_float3(convertVector(SCNVector3(vector), from: node))
    }

    public func simdLook(at target: simd_float3) { look(at: SCNVector3(target)) }

    public func simdLook(at target: simd_float3, up: simd_float3, localFront: simd_float3) {
        look(at: SCNVector3(target), up: SCNVector3(up), localFront: SCNVector3(localFront))
    }

    /// Moves the node by `translation` in its parent's coordinates.
    public func simdLocalTranslate(by translation: simd_float3) { simdPosition += simd_act(simdOrientation, translation) }
    public func simdLocalRotate(by rotation: simd_quatf) { simdOrientation = (simdOrientation * rotation).normalized }
}
