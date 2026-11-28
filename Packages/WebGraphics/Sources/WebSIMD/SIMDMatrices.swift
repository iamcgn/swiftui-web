// simd's matrix and quaternion types and their functions, over WebSIMD's vectors: column-major
// 3x3 and 4x4 float matrices, unit quaternions as (ix, iy, iz, r), and the functions SceneKit
// code calls on them (simd_mul, simd_inverse, simd_quaternion, simd_act, simd_slerp and the rest).
// They moved here from SceneKit (decision 0021's SceneKit element), so the `simd` shadow and
// SceneKit share one set: SceneKit re-exports this module where the platform has no simd.
import WebGraphics   // the platform-independent trigonometry

// MARK: Matrices

/// A 3x3 matrix of floats, stored as three columns.
public struct simd_float3x3: Sendable, Equatable, CustomStringConvertible {
    public var columns: (simd_float3, simd_float3, simd_float3)

    public init() { columns = (.zero, .zero, .zero) }
    public init(columns: (simd_float3, simd_float3, simd_float3)) { self.columns = columns }
    public init(_ c0: simd_float3, _ c1: simd_float3, _ c2: simd_float3) { columns = (c0, c1, c2) }
    public init(_ columns: [simd_float3]) { self.init(columns[0], columns[1], columns[2]) }
    public init(diagonal d: simd_float3) { self.init(simd_float3(d.x, 0, 0), simd_float3(0, d.y, 0), simd_float3(0, 0, d.z)) }
    public init(_ scalar: Float) { self.init(diagonal: simd_float3(repeating: scalar)) }
    public init(rows: [simd_float3]) { self = simd_float3x3(rows).transpose }
    /// The rotation a unit quaternion makes.
    public init(_ q: simd_quatf) {
        self.init(q.act(simd_float3(1, 0, 0)), q.act(simd_float3(0, 1, 0)), q.act(simd_float3(0, 0, 1)))
    }

    public subscript(column: Int) -> simd_float3 {
        get {
            switch column { case 0: return columns.0; case 1: return columns.1; default: return columns.2 }
        }
        set {
            switch column { case 0: columns.0 = newValue; case 1: columns.1 = newValue; default: columns.2 = newValue }
        }
    }

    public subscript(column: Int, row: Int) -> Float {
        get { self[column][row] }
        set { self[column][row] = newValue }
    }

    public var transpose: simd_float3x3 {
        simd_float3x3(simd_float3(columns.0.x, columns.1.x, columns.2.x),
                      simd_float3(columns.0.y, columns.1.y, columns.2.y),
                      simd_float3(columns.0.z, columns.1.z, columns.2.z))
    }

    public var determinant: Float { simd_dot(columns.0, simd_cross(columns.1, columns.2)) }

    public var inverse: simd_float3x3 {
        let (a, b, c) = columns
        let det = determinant
        guard det != 0 else { return simd_float3x3() }
        return simd_float3x3(rows: [simd_cross(b, c) / det, simd_cross(c, a) / det, simd_cross(a, b) / det])
    }

    public static func == (l: simd_float3x3, r: simd_float3x3) -> Bool {
        l.columns.0 == r.columns.0 && l.columns.1 == r.columns.1 && l.columns.2 == r.columns.2
    }

    public static func * (m: simd_float3x3, v: simd_float3) -> simd_float3 { m.columns.0 * v.x + m.columns.1 * v.y + m.columns.2 * v.z }
    public static func * (v: simd_float3, m: simd_float3x3) -> simd_float3 { m.transpose * v }
    public static func * (a: simd_float3x3, b: simd_float3x3) -> simd_float3x3 { simd_float3x3(a * b.columns.0, a * b.columns.1, a * b.columns.2) }
    public static func * (s: Float, m: simd_float3x3) -> simd_float3x3 { simd_float3x3(m.columns.0 * s, m.columns.1 * s, m.columns.2 * s) }
    public static func * (m: simd_float3x3, s: Float) -> simd_float3x3 { s * m }
    public static func + (a: simd_float3x3, b: simd_float3x3) -> simd_float3x3 { simd_float3x3(a.columns.0 + b.columns.0, a.columns.1 + b.columns.1, a.columns.2 + b.columns.2) }
    public static func - (a: simd_float3x3, b: simd_float3x3) -> simd_float3x3 { simd_float3x3(a.columns.0 - b.columns.0, a.columns.1 - b.columns.1, a.columns.2 - b.columns.2) }
    public static func *= (a: inout simd_float3x3, b: simd_float3x3) { a = a * b }

    public var description: String { "simd_float3x3([\(columns.0), \(columns.1), \(columns.2)])" }
}

/// A 4x4 matrix of floats, stored as four columns (a transform's translation in the last).
public struct simd_float4x4: Sendable, Equatable, CustomStringConvertible {
    public var columns: (simd_float4, simd_float4, simd_float4, simd_float4)

    public init() { columns = (.zero, .zero, .zero, .zero) }
    public init(columns: (simd_float4, simd_float4, simd_float4, simd_float4)) { self.columns = columns }
    public init(_ c0: simd_float4, _ c1: simd_float4, _ c2: simd_float4, _ c3: simd_float4) { columns = (c0, c1, c2, c3) }
    public init(_ columns: [simd_float4]) { self.init(columns[0], columns[1], columns[2], columns[3]) }
    public init(diagonal d: simd_float4) {
        self.init(simd_float4(d.x, 0, 0, 0), simd_float4(0, d.y, 0, 0), simd_float4(0, 0, d.z, 0), simd_float4(0, 0, 0, d.w))
    }
    public init(_ scalar: Float) { self.init(diagonal: simd_float4(repeating: scalar)) }
    public init(rows: [simd_float4]) { self = simd_float4x4(rows).transpose }
    /// The rotation a unit quaternion makes.
    public init(_ q: simd_quatf) {
        let m = simd_float3x3(q)
        self.init(simd_float4(m.columns.0, 0), simd_float4(m.columns.1, 0), simd_float4(m.columns.2, 0), simd_float4(0, 0, 0, 1))
    }

    public subscript(column: Int) -> simd_float4 {
        get {
            switch column { case 0: return columns.0; case 1: return columns.1; case 2: return columns.2; default: return columns.3 }
        }
        set {
            switch column { case 0: columns.0 = newValue; case 1: columns.1 = newValue; case 2: columns.2 = newValue; default: columns.3 = newValue }
        }
    }

    public subscript(column: Int, row: Int) -> Float {
        get { self[column][row] }
        set { self[column][row] = newValue }
    }

    public var transpose: simd_float4x4 {
        var t = simd_float4x4()
        for c in 0..<4 { for r in 0..<4 { t[r, c] = self[c, r] } }
        return t
    }

    /// The inverse by cofactors (zero for a singular matrix).
    public var inverse: simd_float4x4 {
        var m = [Float](repeating: 0, count: 16)
        for c in 0..<4 { for r in 0..<4 { m[c * 4 + r] = self[c, r] } }
        var inv = [Float](repeating: 0, count: 16)
        inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] + m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10]
        inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] - m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10]
        inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] + m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9]
        inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] - m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9]
        inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] - m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10]
        inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] + m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10]
        inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] - m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9]
        inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] + m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9]
        inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] + m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6]
        inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] - m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6]
        inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] + m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5]
        inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] - m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5]
        inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] - m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6]
        inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] + m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6]
        inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] - m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5]
        inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] + m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5]
        let det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12]
        guard det != 0 else { return simd_float4x4() }
        var result = simd_float4x4()
        for c in 0..<4 { for r in 0..<4 { result[c, r] = inv[c * 4 + r] / det } }
        return result
    }

    public var determinant: Float {
        let m = self
        func minor(_ c0: Int, _ c1: Int, _ c2: Int) -> Float {
            simd_float3x3(simd_float3(m[c0, 1], m[c0, 2], m[c0, 3]), simd_float3(m[c1, 1], m[c1, 2], m[c1, 3]), simd_float3(m[c2, 1], m[c2, 2], m[c2, 3])).determinant
        }
        return m[0, 0] * minor(1, 2, 3) - m[1, 0] * minor(0, 2, 3) + m[2, 0] * minor(0, 1, 3) - m[3, 0] * minor(0, 1, 2)
    }

    public static func == (l: simd_float4x4, r: simd_float4x4) -> Bool {
        l.columns.0 == r.columns.0 && l.columns.1 == r.columns.1 && l.columns.2 == r.columns.2 && l.columns.3 == r.columns.3
    }

    public static func * (m: simd_float4x4, v: simd_float4) -> simd_float4 {
        m.columns.0 * v.x + m.columns.1 * v.y + m.columns.2 * v.z + m.columns.3 * v.w
    }
    public static func * (v: simd_float4, m: simd_float4x4) -> simd_float4 { m.transpose * v }
    public static func * (a: simd_float4x4, b: simd_float4x4) -> simd_float4x4 {
        simd_float4x4(a * b.columns.0, a * b.columns.1, a * b.columns.2, a * b.columns.3)
    }
    public static func * (s: Float, m: simd_float4x4) -> simd_float4x4 { simd_float4x4(m.columns.0 * s, m.columns.1 * s, m.columns.2 * s, m.columns.3 * s) }
    public static func * (m: simd_float4x4, s: Float) -> simd_float4x4 { s * m }
    public static func + (a: simd_float4x4, b: simd_float4x4) -> simd_float4x4 {
        simd_float4x4(a.columns.0 + b.columns.0, a.columns.1 + b.columns.1, a.columns.2 + b.columns.2, a.columns.3 + b.columns.3)
    }
    public static func - (a: simd_float4x4, b: simd_float4x4) -> simd_float4x4 {
        simd_float4x4(a.columns.0 - b.columns.0, a.columns.1 - b.columns.1, a.columns.2 - b.columns.2, a.columns.3 - b.columns.3)
    }
    public static func *= (a: inout simd_float4x4, b: simd_float4x4) { a = a * b }

    public var description: String { "simd_float4x4([\(columns.0), \(columns.1), \(columns.2), \(columns.3)])" }
}

public typealias float3x3 = simd_float3x3
public typealias float4x4 = simd_float4x4
public typealias matrix_float3x3 = simd_float3x3
public typealias matrix_float4x4 = simd_float4x4

public let matrix_identity_float3x3 = simd_float3x3(diagonal: simd_float3(1, 1, 1))
public let matrix_identity_float4x4 = simd_float4x4(diagonal: simd_float4(1, 1, 1, 1))

// MARK: Quaternions

/// A quaternion of floats: `vector` is (ix, iy, iz, r). A unit quaternion is a rotation.
public struct simd_quatf: Sendable, Equatable, CustomStringConvertible {
    public var vector: simd_float4

    public init() { vector = .zero }
    public init(vector: simd_float4) { self.vector = vector }
    public init(ix: Float, iy: Float, iz: Float, r: Float) { vector = simd_float4(ix, iy, iz, r) }
    public init(real: Float, imag: simd_float3) { vector = simd_float4(imag, real) }
    /// A turn of `angle` radians about `axis` (normalized here).
    public init(angle: Float, axis: simd_float3) {
        let n = simd_length(axis) > 0 ? simd_normalize(axis) : axis
        let half = angle / 2
        self.init(real: Float(_cos(Double(half))), imag: n * Float(_sin(Double(half))))
    }
    /// The shortest rotation taking the direction `from` to the direction `to`.
    public init(from: simd_float3, to: simd_float3) {
        let a = simd_normalize(from), b = simd_normalize(to)
        let d = simd_dot(a, b)
        if d < -0.999999 {
            // Opposite: half a turn about any axis at right angles to them.
            var axis = simd_cross(simd_float3(1, 0, 0), a)
            if simd_length(axis) < 1e-6 { axis = simd_cross(simd_float3(0, 1, 0), a) }
            self.init(angle: .pi, axis: axis)
            return
        }
        self = simd_quatf(real: 1 + d, imag: simd_cross(a, b)).normalized
    }
    /// The rotation a rotation matrix makes.
    public init(_ m: simd_float3x3) {
        // r(row, column) of the matrix that maps v to m * v.
        func r(_ row: Int, _ column: Int) -> Float { m[column, row] }
        let trace = r(0, 0) + r(1, 1) + r(2, 2)
        if trace > 0 {
            let s = (trace + 1).squareRoot() * 2
            self.init(ix: (r(2, 1) - r(1, 2)) / s, iy: (r(0, 2) - r(2, 0)) / s, iz: (r(1, 0) - r(0, 1)) / s, r: s / 4)
        } else if r(0, 0) > r(1, 1) && r(0, 0) > r(2, 2) {
            let s = (1 + r(0, 0) - r(1, 1) - r(2, 2)).squareRoot() * 2
            self.init(ix: s / 4, iy: (r(0, 1) + r(1, 0)) / s, iz: (r(0, 2) + r(2, 0)) / s, r: (r(2, 1) - r(1, 2)) / s)
        } else if r(1, 1) > r(2, 2) {
            let s = (1 + r(1, 1) - r(0, 0) - r(2, 2)).squareRoot() * 2
            self.init(ix: (r(0, 1) + r(1, 0)) / s, iy: s / 4, iz: (r(1, 2) + r(2, 1)) / s, r: (r(0, 2) - r(2, 0)) / s)
        } else {
            let s = (1 + r(2, 2) - r(0, 0) - r(1, 1)).squareRoot() * 2
            self.init(ix: (r(0, 2) + r(2, 0)) / s, iy: (r(1, 2) + r(2, 1)) / s, iz: s / 4, r: (r(1, 0) - r(0, 1)) / s)
        }
    }
    /// The rotation in a transform's upper 3x3.
    public init(_ m: simd_float4x4) {
        self.init(simd_float3x3(simd_float3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
                                simd_float3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                                simd_float3(m.columns.2.x, m.columns.2.y, m.columns.2.z)))
    }

    public var real: Float {
        get { vector.w }
        set { vector.w = newValue }
    }
    public var imag: simd_float3 {
        get { simd_float3(vector.x, vector.y, vector.z) }
        set { vector = simd_float4(newValue, vector.w) }
    }
    public var length: Float { simd_length(vector) }
    public var normalized: simd_quatf { length > 0 ? simd_quatf(vector: vector / length) : self }
    public var conjugate: simd_quatf { simd_quatf(real: real, imag: -imag) }
    public var inverse: simd_quatf {
        let l2 = simd_length_squared(vector)
        return l2 > 0 ? simd_quatf(vector: conjugate.vector / l2) : self
    }
    /// The turn's angle in radians, 0...2π.
    public var angle: Float { 2 * Float(_atan2(Double(simd_length(imag)), Double(real))) }
    /// The turn's axis (x when there is no turn).
    public var axis: simd_float3 {
        let l = simd_length(imag)
        return l > 0 ? imag / l : simd_float3(1, 0, 0)
    }

    /// `v` turned by the rotation.
    public func act(_ v: simd_float3) -> simd_float3 {
        let t = 2 * simd_cross(imag, v)
        return v + real * t + simd_cross(imag, t)
    }

    /// `a * b` turns by `b`, then `a` (the Hamilton product).
    public static func * (a: simd_quatf, b: simd_quatf) -> simd_quatf {
        simd_quatf(real: a.real * b.real - simd_dot(a.imag, b.imag),
                   imag: a.real * b.imag + b.real * a.imag + simd_cross(a.imag, b.imag))
    }
    public static func * (q: simd_quatf, s: Float) -> simd_quatf { simd_quatf(vector: q.vector * s) }
    public static func * (s: Float, q: simd_quatf) -> simd_quatf { q * s }
    public static func / (q: simd_quatf, s: Float) -> simd_quatf { simd_quatf(vector: q.vector / s) }
    public static func + (a: simd_quatf, b: simd_quatf) -> simd_quatf { simd_quatf(vector: a.vector + b.vector) }
    public static func - (a: simd_quatf, b: simd_quatf) -> simd_quatf { simd_quatf(vector: a.vector - b.vector) }
    public static prefix func - (q: simd_quatf) -> simd_quatf { simd_quatf(vector: -q.vector) }
    public static func *= (a: inout simd_quatf, b: simd_quatf) { a = a * b }

    public var description: String { "simd_quatf(real: \(real), imag: \(imag))" }
}

// MARK: Functions

public func simd_make_float3(_ x: Float, _ y: Float, _ z: Float) -> simd_float3 { simd_float3(x, y, z) }
public func simd_make_float3(_ v: simd_float4) -> simd_float3 { simd_float3(v.x, v.y, v.z) }
public func simd_make_float4(_ x: Float, _ y: Float, _ z: Float, _ w: Float) -> simd_float4 { simd_float4(x, y, z, w) }
public func simd_make_float4(_ v: simd_float3, _ w: Float) -> simd_float4 { simd_float4(v, w) }

public func simd_mul(_ m: simd_float3x3, _ v: simd_float3) -> simd_float3 { m * v }
public func simd_mul(_ m: simd_float4x4, _ v: simd_float4) -> simd_float4 { m * v }
public func simd_mul(_ a: simd_float3x3, _ b: simd_float3x3) -> simd_float3x3 { a * b }
public func simd_mul(_ a: simd_float4x4, _ b: simd_float4x4) -> simd_float4x4 { a * b }
public func simd_mul(_ a: simd_quatf, _ b: simd_quatf) -> simd_quatf { a * b }
public func matrix_multiply(_ a: simd_float3x3, _ b: simd_float3x3) -> simd_float3x3 { a * b }
public func matrix_multiply(_ a: simd_float4x4, _ b: simd_float4x4) -> simd_float4x4 { a * b }
public func matrix_multiply(_ m: simd_float4x4, _ v: simd_float4) -> simd_float4 { m * v }
public func simd_transpose(_ m: simd_float3x3) -> simd_float3x3 { m.transpose }
public func simd_transpose(_ m: simd_float4x4) -> simd_float4x4 { m.transpose }
public func simd_inverse(_ m: simd_float3x3) -> simd_float3x3 { m.inverse }
public func simd_inverse(_ m: simd_float4x4) -> simd_float4x4 { m.inverse }
public func simd_determinant(_ m: simd_float3x3) -> Float { m.determinant }
public func simd_determinant(_ m: simd_float4x4) -> Float { m.determinant }
public func simd_matrix(_ c0: simd_float3, _ c1: simd_float3, _ c2: simd_float3) -> simd_float3x3 { simd_float3x3(c0, c1, c2) }
public func simd_matrix(_ c0: simd_float4, _ c1: simd_float4, _ c2: simd_float4, _ c3: simd_float4) -> simd_float4x4 { simd_float4x4(c0, c1, c2, c3) }
public func simd_matrix3x3(_ q: simd_quatf) -> simd_float3x3 { simd_float3x3(q) }
public func simd_matrix4x4(_ q: simd_quatf) -> simd_float4x4 { simd_float4x4(q) }

public func simd_quaternion(_ ix: Float, _ iy: Float, _ iz: Float, _ r: Float) -> simd_quatf { simd_quatf(ix: ix, iy: iy, iz: iz, r: r) }
public func simd_quaternion(_ angle: Float, _ axis: simd_float3) -> simd_quatf { simd_quatf(angle: angle, axis: axis) }
public func simd_quaternion(_ from: simd_float3, _ to: simd_float3) -> simd_quatf { simd_quatf(from: from, to: to) }
public func simd_quaternion(_ m: simd_float3x3) -> simd_quatf { simd_quatf(m) }
public func simd_quaternion(_ m: simd_float4x4) -> simd_quatf { simd_quatf(m) }
public func simd_act(_ q: simd_quatf, _ v: simd_float3) -> simd_float3 { q.act(v) }
public func simd_normalize(_ q: simd_quatf) -> simd_quatf { q.normalized }
public func simd_length(_ q: simd_quatf) -> Float { q.length }
public func simd_inverse(_ q: simd_quatf) -> simd_quatf { q.inverse }
public func simd_conjugate(_ q: simd_quatf) -> simd_quatf { q.conjugate }
public func simd_angle(_ q: simd_quatf) -> Float { q.angle }
public func simd_axis(_ q: simd_quatf) -> simd_float3 { q.axis }
public func simd_dot(_ a: simd_quatf, _ b: simd_quatf) -> Float { simd_dot(a.vector, b.vector) }
/// The rotation `t` of the way from `q0` to `q1` along the shorter arc.
public func simd_slerp(_ q0: simd_quatf, _ q1: simd_quatf, _ t: Float) -> simd_quatf {
    var b = q1
    var d = simd_dot(q0.vector, b.vector)
    if d < 0 { b = -b; d = -d }
    if d > 0.9995 { return simd_quatf(vector: q0.vector + (b.vector - q0.vector) * t).normalized }
    let theta = Float(_acos(Double(Swift.min(Swift.max(d, -1), 1))))
    let s = Float(_sin(Double(theta)))
    let w0 = Float(_sin(Double((1 - t) * theta))) / s, w1 = Float(_sin(Double(t * theta))) / s
    return simd_quatf(vector: q0.vector * w0 + b.vector * w1)
}
public func simd_slerp_longest(_ q0: simd_quatf, _ q1: simd_quatf, _ t: Float) -> simd_quatf { simd_slerp(q0, -q1, t) }
