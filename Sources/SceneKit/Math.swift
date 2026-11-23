// SceneKit's vectors and matrices (sw-frameworks, Docs/elements/SceneKit.md). Matrices are
// Core Animation's: row vectors, so `SCNMatrix4Mult(a, b)` applies `a`, then `b`, and the
// translation sits in the fourth row. Rotations are kept as unit quaternions.
#if os(WASI)
import WebFoundation
#else
import Foundation
#endif
import SwiftUI
import UIKit

public typealias SCNFloat = Float

/// A three-component vector: a position, a direction or Euler angles.
public struct SCNVector3: Hashable, Sendable {
    public var x: Float
    public var y: Float
    public var z: Float
    public init() { x = 0; y = 0; z = 0 }
    public init(x: Float, y: Float, z: Float) { self.x = x; self.y = y; self.z = z }
    public init(_ x: Float, _ y: Float, _ z: Float) { self.init(x: x, y: y, z: z) }
    public init(x: CGFloat, y: CGFloat, z: CGFloat) { self.init(x: Float(x), y: Float(y), z: Float(z)) }
    public init(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) { self.init(x: Float(x), y: Float(y), z: Float(z)) }
    #if !os(WASI)   // CGFloat is Double there
    public init(_ x: Double, _ y: Double, _ z: Double) { self.init(x: Float(x), y: Float(y), z: Float(z)) }
    public init(x: Double, y: Double, z: Double) { self.init(x: Float(x), y: Float(y), z: Float(z)) }
    #endif
    public init(_ x: Int, _ y: Int, _ z: Int) { self.init(x: Float(x), y: Float(y), z: Float(z)) }
    public init(x: Int, y: Int, z: Int) { self.init(x: Float(x), y: Float(y), z: Float(z)) }
}

/// A four-component vector: an axis and an angle (`rotation`), or a quaternion (`orientation`).
public struct SCNVector4: Hashable, Sendable {
    public var x: Float
    public var y: Float
    public var z: Float
    public var w: Float
    public init() { x = 0; y = 0; z = 0; w = 0 }
    public init(x: Float, y: Float, z: Float, w: Float) { self.x = x; self.y = y; self.z = z; self.w = w }
    public init(_ x: Float, _ y: Float, _ z: Float, _ w: Float) { self.init(x: x, y: y, z: z, w: w) }
    public init(x: CGFloat, y: CGFloat, z: CGFloat, w: CGFloat) { self.init(x: Float(x), y: Float(y), z: Float(z), w: Float(w)) }
    public init(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat, _ w: CGFloat) { self.init(x: Float(x), y: Float(y), z: Float(z), w: Float(w)) }
    #if !os(WASI)   // CGFloat is Double there
    public init(_ x: Double, _ y: Double, _ z: Double, _ w: Double) { self.init(x: Float(x), y: Float(y), z: Float(z), w: Float(w)) }
    public init(x: Double, y: Double, z: Double, w: Double) { self.init(x: Float(x), y: Float(y), z: Float(z), w: Float(w)) }
    #endif
    public init(_ x: Int, _ y: Int, _ z: Int, _ w: Int) { self.init(x: Float(x), y: Float(y), z: Float(z), w: Float(w)) }
    public init(x: Int, y: Int, z: Int, w: Int) { self.init(x: Float(x), y: Float(y), z: Float(z), w: Float(w)) }
}

public typealias SCNQuaternion = SCNVector4

/// A 4x4 transform in Core Animation's layout (row vectors, translation in m41...m43).
public struct SCNMatrix4: Hashable, Sendable {
    public var m11: Float, m12: Float, m13: Float, m14: Float
    public var m21: Float, m22: Float, m23: Float, m24: Float
    public var m31: Float, m32: Float, m33: Float, m34: Float
    public var m41: Float, m42: Float, m43: Float, m44: Float

    public init() {
        m11 = 1; m12 = 0; m13 = 0; m14 = 0
        m21 = 0; m22 = 1; m23 = 0; m24 = 0
        m31 = 0; m32 = 0; m33 = 1; m34 = 0
        m41 = 0; m42 = 0; m43 = 0; m44 = 1
    }

    public init(m11: Float, m12: Float, m13: Float, m14: Float, m21: Float, m22: Float, m23: Float, m24: Float,
                m31: Float, m32: Float, m33: Float, m34: Float, m41: Float, m42: Float, m43: Float, m44: Float) {
        self.m11 = m11; self.m12 = m12; self.m13 = m13; self.m14 = m14
        self.m21 = m21; self.m22 = m22; self.m23 = m23; self.m24 = m24
        self.m31 = m31; self.m32 = m32; self.m33 = m33; self.m34 = m34
        self.m41 = m41; self.m42 = m42; self.m43 = m43; self.m44 = m44
    }

    /// The rows, for the arithmetic.
    var rows: [[Float]] {
        [[m11, m12, m13, m14], [m21, m22, m23, m24], [m31, m32, m33, m34], [m41, m42, m43, m44]]
    }

    init(rows r: [[Float]]) {
        self.init(m11: r[0][0], m12: r[0][1], m13: r[0][2], m14: r[0][3], m21: r[1][0], m22: r[1][1], m23: r[1][2], m24: r[1][3],
                  m31: r[2][0], m32: r[2][1], m33: r[2][2], m34: r[2][3], m41: r[3][0], m42: r[3][1], m43: r[3][2], m44: r[3][3])
    }

    /// A point (w = 1) through the transform, divided through by w.
    func transformPoint(_ v: SCNVector3) -> SCNVector3 {
        let x = v.x * m11 + v.y * m21 + v.z * m31 + m41
        let y = v.x * m12 + v.y * m22 + v.z * m32 + m42
        let z = v.x * m13 + v.y * m23 + v.z * m33 + m43
        let w = v.x * m14 + v.y * m24 + v.z * m34 + m44
        return w != 0 && w != 1 ? SCNVector3(x / w, y / w, z / w) : SCNVector3(x, y, z)
    }

    /// A direction (w = 0) through the transform.
    func transformDirection(_ v: SCNVector3) -> SCNVector3 {
        SCNVector3(v.x * m11 + v.y * m21 + v.z * m31, v.x * m12 + v.y * m22 + v.z * m32, v.x * m13 + v.y * m23 + v.z * m33)
    }
}

public let SCNMatrix4Identity = SCNMatrix4()
public let SCNVector3Zero = SCNVector3()
public let SCNVector4Zero = SCNVector4()

public func SCNVector3Make(_ x: Float, _ y: Float, _ z: Float) -> SCNVector3 { SCNVector3(x, y, z) }
public func SCNVector4Make(_ x: Float, _ y: Float, _ z: Float, _ w: Float) -> SCNVector4 { SCNVector4(x, y, z, w) }
public func SCNVector3EqualToVector3(_ a: SCNVector3, _ b: SCNVector3) -> Bool { a == b }
public func SCNVector4EqualToVector4(_ a: SCNVector4, _ b: SCNVector4) -> Bool { a == b }
public func SCNMatrix4IsIdentity(_ m: SCNMatrix4) -> Bool { m == SCNMatrix4Identity }
public func SCNMatrix4EqualToMatrix4(_ a: SCNMatrix4, _ b: SCNMatrix4) -> Bool { a == b }

public func SCNMatrix4MakeTranslation(_ tx: Float, _ ty: Float, _ tz: Float) -> SCNMatrix4 {
    var m = SCNMatrix4(); m.m41 = tx; m.m42 = ty; m.m43 = tz; return m
}

public func SCNMatrix4MakeScale(_ sx: Float, _ sy: Float, _ sz: Float) -> SCNMatrix4 {
    var m = SCNMatrix4(); m.m11 = sx; m.m22 = sy; m.m33 = sz; return m
}

/// A turn of `angle` radians about the axis (x, y, z), counterclockwise looking down the axis.
public func SCNMatrix4MakeRotation(_ angle: Float, _ x: Float, _ y: Float, _ z: Float) -> SCNMatrix4 {
    _Quaternion(axis: SCNVector3(x, y, z), angle: angle).matrix
}

/// `a` then `b`.
public func SCNMatrix4Mult(_ a: SCNMatrix4, _ b: SCNMatrix4) -> SCNMatrix4 {
    let x = a.rows, y = b.rows
    var r = [[Float]](repeating: [0, 0, 0, 0], count: 4)
    for i in 0..<4 { for j in 0..<4 { r[i][j] = x[i][0] * y[0][j] + x[i][1] * y[1][j] + x[i][2] * y[2][j] + x[i][3] * y[3][j] } }
    return SCNMatrix4(rows: r)
}

public func SCNMatrix4Translate(_ m: SCNMatrix4, _ tx: Float, _ ty: Float, _ tz: Float) -> SCNMatrix4 {
    SCNMatrix4Mult(m, SCNMatrix4MakeTranslation(tx, ty, tz))
}

public func SCNMatrix4Scale(_ m: SCNMatrix4, _ sx: Float, _ sy: Float, _ sz: Float) -> SCNMatrix4 {
    SCNMatrix4Mult(SCNMatrix4MakeScale(sx, sy, sz), m)
}

public func SCNMatrix4Rotate(_ m: SCNMatrix4, _ angle: Float, _ x: Float, _ y: Float, _ z: Float) -> SCNMatrix4 {
    SCNMatrix4Mult(SCNMatrix4MakeRotation(angle, x, y, z), m)
}

/// The inverse (the matrix itself when it has none).
public func SCNMatrix4Invert(_ m: SCNMatrix4) -> SCNMatrix4 {
    let a = m.rows.map { $0.map(Double.init) }
    var inv = [[Double]](repeating: [0, 0, 0, 0], count: 4)
    for i in 0..<4 { inv[i][i] = 1 }
    var w = a
    for col in 0..<4 {
        var pivot = col
        for r in col..<4 where abs(w[r][col]) > abs(w[pivot][col]) { pivot = r }
        guard abs(w[pivot][col]) > 1e-12 else { return m }
        w.swapAt(col, pivot); inv.swapAt(col, pivot)
        let p = w[col][col]
        for j in 0..<4 { w[col][j] /= p; inv[col][j] /= p }
        for r in 0..<4 where r != col {
            let f = w[r][col]
            guard f != 0 else { continue }
            for j in 0..<4 { w[r][j] -= f * w[col][j]; inv[r][j] -= f * inv[col][j] }
        }
    }
    return SCNMatrix4(rows: inv.map { $0.map(Float.init) })
}

#if os(WASI)
extension NSValue {
    public convenience init(scnVector3 v: SCNVector3) { self.init(_webValue: AnyHashable(v)) }
    public convenience init(scnVector4 v: SCNVector4) { self.init(_webValue: AnyHashable(v)) }
    public convenience init(scnMatrix4 v: SCNMatrix4) { self.init(_webValue: AnyHashable(v)) }
    public var scnVector3Value: SCNVector3 { (_webValue?.base as? SCNVector3) ?? SCNVector3() }
    public var scnVector4Value: SCNVector4 { (_webValue?.base as? SCNVector4) ?? SCNVector4() }
    public var scnMatrix4Value: SCNMatrix4 { (_webValue?.base as? SCNMatrix4) ?? SCNMatrix4Identity }
}
#elseif canImport(Darwin)
extension NSValue {
    public convenience init(scnVector3 v: SCNVector3) { var v = v; self.init(bytes: &v, objCType: "{SCNVector3=fff}") }
    public convenience init(scnVector4 v: SCNVector4) { var v = v; self.init(bytes: &v, objCType: "{SCNVector4=ffff}") }
    public convenience init(scnMatrix4 v: SCNMatrix4) { var v = v; self.init(bytes: &v, objCType: "{SCNMatrix4=ffffffffffffffff}") }
    public var scnVector3Value: SCNVector3 { var v = SCNVector3(); getValue(&v, size: MemoryLayout<SCNVector3>.size); return v }
    public var scnVector4Value: SCNVector4 { var v = SCNVector4(); getValue(&v, size: MemoryLayout<SCNVector4>.size); return v }
    public var scnMatrix4Value: SCNMatrix4 { var v = SCNMatrix4(); getValue(&v, size: MemoryLayout<SCNMatrix4>.size); return v }
}
#else
// Linux's Foundation boxes no structs of its own, so a vector rides in a rectangle's four
// numbers (a float fits a double exactly) and a matrix in a pointer to a copy kept alive.
extension NSValue {
    public convenience init(scnVector3 v: SCNVector3) { self.init(rect: .init(x: Double(v.x), y: Double(v.y), width: Double(v.z), height: 0)) }
    public convenience init(scnVector4 v: SCNVector4) { self.init(rect: .init(x: Double(v.x), y: Double(v.y), width: Double(v.z), height: Double(v.w))) }
    public convenience init(scnMatrix4 v: SCNMatrix4) {
        let box = UnsafeMutablePointer<SCNMatrix4>.allocate(capacity: 1)
        box.initialize(to: v)
        self.init(pointer: UnsafeRawPointer(box))
    }
    public var scnVector3Value: SCNVector3 {
        let r = rectValue
        return SCNVector3(x: Float(r.origin.x), y: Float(r.origin.y), z: Float(r.size.width))
    }
    public var scnVector4Value: SCNVector4 {
        let r = rectValue
        return SCNVector4(x: Float(r.origin.x), y: Float(r.origin.y), z: Float(r.size.width), w: Float(r.size.height))
    }
    public var scnMatrix4Value: SCNMatrix4 {
        guard let pointer = pointerValue else { return SCNMatrix4Identity }
        return pointer.assumingMemoryBound(to: SCNMatrix4.self).pointee
    }
}
#endif
        return v
    }
    public var scnVector4Value: SCNVector4 {
        var v = SCNVector4()
        #if canImport(Darwin)
        getValue(&v, size: MemoryLayout<SCNVector4>.size)
        #else
        getValue(&v)
        #endif
        return v
    }
    public var scnMatrix4Value: SCNMatrix4 {
        var v = SCNMatrix4()
        #if canImport(Darwin)
        getValue(&v, size: MemoryLayout<SCNMatrix4>.size)
        #else
        getValue(&v)
        #endif
        return v
    }
}
#endif

// MARK: - Internal arithmetic

extension SCNVector3 {
    static func + (a: SCNVector3, b: SCNVector3) -> SCNVector3 { SCNVector3(a.x + b.x, a.y + b.y, a.z + b.z) }
    static func - (a: SCNVector3, b: SCNVector3) -> SCNVector3 { SCNVector3(a.x - b.x, a.y - b.y, a.z - b.z) }
    static func * (a: SCNVector3, s: Float) -> SCNVector3 { SCNVector3(a.x * s, a.y * s, a.z * s) }
    func dot(_ b: SCNVector3) -> Float { x * b.x + y * b.y + z * b.z }
    func cross(_ b: SCNVector3) -> SCNVector3 { SCNVector3(y * b.z - z * b.y, z * b.x - x * b.z, x * b.y - y * b.x) }
    var length: Float { dot(self).squareRoot() }
    var normalized: SCNVector3 { let l = length; return l > 0 ? self * (1 / l) : self }
}

func _sinF(_ x: Float) -> Float { Float(_sin(Double(x))) }
func _cosF(_ x: Float) -> Float { Float(_cos(Double(x))) }
func _atan2F(_ y: Float, _ x: Float) -> Float { Float(_atan2(Double(y), Double(x))) }
func _asinF(_ x: Float) -> Float { let c = Double(Swift.min(Swift.max(x, -1), 1)); return Float(_atan2(c, (1 - c * c).squareRoot())) }
func _acosF(_ x: Float) -> Float { Float(_acos(Double(Swift.min(Swift.max(x, -1), 1)))) }

/// A unit quaternion (x, y, z, w) for a node's rotation.
struct _Quaternion: Hashable, Sendable {
    var x: Float = 0, y: Float = 0, z: Float = 0, w: Float = 1

    init() {}
    init(x: Float, y: Float, z: Float, w: Float) { self.x = x; self.y = y; self.z = z; self.w = w }

    init(axis: SCNVector3, angle: Float) {
        let n = axis.normalized
        guard n.length > 0 else { self.init(); return }
        let s = _sinF(angle / 2)
        self.init(x: n.x * s, y: n.y * s, z: n.z * s, w: _cosF(angle / 2))
    }

    /// SceneKit's Euler angles: roll (z) first, then yaw (y), then pitch (x).
    init(euler e: SCNVector3) {
        let qx = _Quaternion(axis: SCNVector3(1, 0, 0), angle: e.x)
        let qy = _Quaternion(axis: SCNVector3(0, 1, 0), angle: e.y)
        let qz = _Quaternion(axis: SCNVector3(0, 0, 1), angle: e.z)
        self = qx * qy * qz
    }

    /// `a * b` rotates by `b`, then `a` (as the Hamilton product).
    static func * (a: _Quaternion, b: _Quaternion) -> _Quaternion {
        _Quaternion(x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
                    y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
                    z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
                    w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z)
    }

    var normalized: _Quaternion {
        let l = (x * x + y * y + z * z + w * w).squareRoot()
        return l > 0 ? _Quaternion(x: x / l, y: y / l, z: z / l, w: w / l) : _Quaternion()
    }

    /// The axis and angle (`rotation`).
    var axisAngle: SCNVector4 {
        let q = w < 0 ? _Quaternion(x: -x, y: -y, z: -z, w: -w) : self
        let angle = 2 * _acosF(q.w)
        let s = (1 - q.w * q.w).squareRoot()
        guard s > 1e-6 else { return SCNVector4(x: Float(0), y: 0, z: 0, w: 0) }
        return SCNVector4(q.x / s, q.y / s, q.z / s, angle)
    }

    /// The Euler angles that make this rotation (pitch, yaw, roll): the matrix is
    /// Rz * Ry * Rx in row vectors, so m31 is sin(yaw).
    var euler: SCNVector3 {
        let m = matrix
        if abs(m.m31) < 0.99999 {
            return SCNVector3(_atan2F(-m.m32, m.m33), _asinF(m.m31), _atan2F(-m.m21, m.m11))
        }
        // Yaw a quarter turn: the roll folds into the pitch.
        return SCNVector3(_atan2F(m.m23, m.m22), m.m31 > 0 ? Float.pi / 2 : -Float.pi / 2, 0)
    }

    /// The rotation as a row-vector matrix.
    var matrix: SCNMatrix4 {
        let q = normalized
        let xx = q.x * q.x, yy = q.y * q.y, zz = q.z * q.z
        let xy = q.x * q.y, xz = q.x * q.z, yz = q.y * q.z
        let wx = q.w * q.x, wy = q.w * q.y, wz = q.w * q.z
        var m = SCNMatrix4()
        m.m11 = 1 - 2 * (yy + zz); m.m12 = 2 * (xy + wz); m.m13 = 2 * (xz - wy)
        m.m21 = 2 * (xy - wz); m.m22 = 1 - 2 * (xx + zz); m.m23 = 2 * (yz + wx)
        m.m31 = 2 * (xz + wy); m.m32 = 2 * (yz - wx); m.m33 = 1 - 2 * (xx + yy)
        return m
    }
}
