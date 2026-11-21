// NIST P-256 (secp256r1) key agreement, as `P256.KeyAgreement`: keys from their raw, X9.63 and
// compressed forms, and ECDH shared secrets, which an app that receives Web Push notifications
// (RFC 8291) uses to decrypt them, as IceCubes does. Field arithmetic is Montgomery
// multiplication over four 64-bit limbs; points are Jacobian coordinates. It isn't
// constant-time, so it suits keys an app keeps for itself, not a server's. Keys, public keys and
// shared secrets match Apple's byte for byte.

/// The NIST P-256 elliptic curve.
public enum P256 {
    /// Elliptic-curve Diffie-Hellman key agreement over P-256.
    public enum KeyAgreement {
        /// A public key, a point on the curve.
        public struct PublicKey: Sendable {
            let x: [UInt8]  // 32 big-endian bytes each
            let y: [UInt8]

            init(_trustedX x: [UInt8], y: [UInt8]) {
                self.x = x
                self.y = y
            }

            init(_x x: [UInt8], y: [UInt8]) throws {
                guard _P256.isOnCurve(x: x, y: y) else { throw CryptoKitError.invalidParameter }
                self.init(_trustedX: x, y: y)
            }

            /// A key from its 64 bytes: the point's x and then its y coordinate.
            public init<D: Sequence>(rawRepresentation data: D) throws where D.Element == UInt8 {
                let bytes = Array(data)
                guard bytes.count == 64 else { throw CryptoKitError.incorrectKeySize }
                try self.init(_x: Array(bytes[0..<32]), y: Array(bytes[32..<64]))
            }

            /// A key from its 65-byte uncompressed ANSI X9.63 form: 0x04, x, then y.
            public init<D: Sequence>(x963Representation data: D) throws where D.Element == UInt8 {
                let bytes = Array(data)
                guard bytes.count == 65 else { throw CryptoKitError.incorrectKeySize }
                guard bytes[0] == 4 else { throw CryptoKitError.invalidParameter }
                try self.init(_x: Array(bytes[1..<33]), y: Array(bytes[33..<65]))
            }

            /// A key from its 33-byte compressed form: 0x02 or 0x03 for y's parity, then x.
            public init<D: Sequence>(compressedRepresentation data: D) throws where D.Element == UInt8 {
                let bytes = Array(data)
                guard bytes.count == 33 else { throw CryptoKitError.incorrectKeySize }
                guard bytes[0] == 2 || bytes[0] == 3,
                      let y = _P256.y(forX: Array(bytes[1..<33]), odd: bytes[0] == 3)
                else { throw CryptoKitError.invalidParameter }
                self.init(_trustedX: Array(bytes[1..<33]), y: y)
            }

            /// The key's 64 bytes: x and then y.
            public var rawRepresentation: Data { Data(x + y) }

            /// The key's 65-byte uncompressed ANSI X9.63 form.
            public var x963Representation: Data { Data([4] + x + y) }

            /// The key's 33-byte compressed form.
            public var compressedRepresentation: Data { Data([2 | (y[31] & 1)] + x) }
        }

        /// A private key, a scalar between 1 and the curve's order.
        public struct PrivateKey: Sendable {
            let scalar: [UInt8]  // 32 big-endian bytes

            /// A new random key.
            public init() {
                var generator = SystemRandomNumberGenerator()
                var bytes: [UInt8]
                repeat {
                    bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
                } while !_P256.isValidScalar(bytes)
                scalar = bytes
            }

            /// A key from its 32 bytes.
            public init<D: Sequence>(rawRepresentation data: D) throws where D.Element == UInt8 {
                let bytes = Array(data)
                guard bytes.count == 32 else { throw CryptoKitError.incorrectKeySize }
                guard _P256.isValidScalar(bytes) else { throw CryptoKitError.invalidParameter }
                scalar = bytes
            }

            /// A key from its 97-byte ANSI X9.63 form: the public key's 65 bytes, then the scalar.
            public init<D: Sequence>(x963Representation data: D) throws where D.Element == UInt8 {
                let bytes = Array(data)
                guard bytes.count == 97 else { throw CryptoKitError.incorrectKeySize }
                try self.init(rawRepresentation: bytes[65..<97])
                guard Array(publicKey.x963Representation) == Array(bytes[0..<65]) else {
                    throw CryptoKitError.invalidParameter
                }
            }

            /// The key's 32 bytes.
            public var rawRepresentation: Data { Data(scalar) }

            /// The key's 97-byte ANSI X9.63 form.
            public var x963Representation: Data { Data(Array(publicKey.x963Representation) + scalar) }

            /// The public key that goes with this key.
            public var publicKey: PublicKey {
                // A valid scalar is below the order, so the product is never the point at infinity.
                let (x, y) = _P256.affine(_P256.scalarMultiply(scalar, _P256.generator))!
                return PublicKey(_trustedX: x, y: y)
            }

            /// The secret this key and the other party's public key share: the x coordinate of
            /// their product, as Apple's gives it.
            public func sharedSecretFromKeyAgreement(with publicKeyShare: PublicKey) throws -> SharedSecret {
                let point = _P256.Point(x: _P256.toMontgomery(_P256.limbs(publicKeyShare.x)),
                                        y: _P256.toMontgomery(_P256.limbs(publicKeyShare.y)), z: _P256.one)
                guard let product = _P256.affine(_P256.scalarMultiply(scalar, point)) else {
                    throw CryptoKitError.invalidParameter
                }
                return SharedSecret(bytes: product.0)
            }
        }
    }
}

/// The secret two parties' keys agree on, from which they derive symmetric keys.
public struct SharedSecret: Sendable, Equatable {
    let bytes: [UInt8]

    /// Calls the closure with the secret's bytes.
    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try bytes.withUnsafeBytes(body)
    }

    /// Compares secrets in constant time.
    public static func == (lhs: SharedSecret, rhs: SharedSecret) -> Bool { _constantTimeEqual(lhs.bytes, rhs.bytes) }

    /// A key derived from the secret with HKDF (RFC 5869).
    public func hkdfDerivedSymmetricKey<H: HashFunction, Salt: Sequence, Info: Sequence>(
        using hashFunction: H.Type, salt: Salt, sharedInfo: Info, outputByteCount: Int
    ) -> SymmetricKey where Salt.Element == UInt8, Info.Element == UInt8 {
        HKDF<H>.deriveKey(inputKeyMaterial: SymmetricKey(data: bytes), salt: salt, info: sharedInfo,
                          outputByteCount: outputByteCount)
    }

    /// A key derived from the secret with the ANSI X9.63 key derivation function.
    public func x963DerivedSymmetricKey<H: HashFunction, Info: Sequence>(
        using hashFunction: H.Type, sharedInfo: Info, outputByteCount: Int
    ) -> SymmetricKey where Info.Element == UInt8 {
        let info = Array(sharedInfo)
        var output: [UInt8] = []
        var counter: UInt32 = 1
        while output.count < outputByteCount {
            var hash = H()
            hash.update(data: bytes)
            let counterBytes: [UInt8] = [UInt8(truncatingIfNeeded: counter >> 24), UInt8(truncatingIfNeeded: counter >> 16),
                                         UInt8(truncatingIfNeeded: counter >> 8), UInt8(truncatingIfNeeded: counter)]
            hash.update(data: counterBytes)
            hash.update(data: info)
            output += Array(hash.finalize())
            counter &+= 1
        }
        return SymmetricKey(data: output.prefix(outputByteCount))
    }
}

/// P-256 arithmetic. A field element is four 64-bit limbs, least significant first, in
/// Montgomery form (times 2^256 mod p) wherever the curve arithmetic uses it.
enum _P256 {
    typealias Limbs = [UInt64]

    static let p: Limbs = [0xFFFF_FFFF_FFFF_FFFF, 0x0000_0000_FFFF_FFFF, 0, 0xFFFF_FFFF_0000_0001]
    /// -p⁻¹ mod 2^64, which is 1 for p.
    static let pInverse: UInt64 = 1
    /// 2^512 mod p, which takes a number into Montgomery form.
    static let r2: Limbs = [3, 0xFFFF_FFFB_FFFF_FFFF, 0xFFFF_FFFF_FFFF_FFFE, 0x0000_0004_FFFF_FFFD]
    static let pMinus2: Limbs = [0xFFFF_FFFF_FFFF_FFFD, 0x0000_0000_FFFF_FFFF, 0, 0xFFFF_FFFF_0000_0001]
    /// (p + 1) / 4: p is 3 mod 4, so a square's root is its power by this.
    static let sqrtExponent: Limbs = [0, 0x0000_0000_4000_0000, 0x4000_0000_0000_0000, 0x3FFF_FFFF_C000_0000]
    /// The order of the generator.
    static let n: Limbs = [0xF3B9_CAC2_FC63_2551, 0xBCE6_FAAD_A717_9E84, 0xFFFF_FFFF_FFFF_FFFF, 0xFFFF_FFFF_0000_0000]
    static let b: Limbs = toMontgomery([0x3BCE_3C3E_27D2_604B, 0x651D_06B0_CC53_B0F6, 0xB3EB_BD55_7698_86BC, 0x5AC6_35D8_AA3A_93E7])
    static let one: Limbs = toMontgomery([1, 0, 0, 0])
    static let zero: Limbs = [0, 0, 0, 0]
    static let generator = Point(
        x: toMontgomery([0xF4A1_3945_D898_C296, 0x7703_7D81_2DEB_33A0, 0xF8BC_E6E5_63A4_40F2, 0x6B17_D1F2_E12C_4247]),
        y: toMontgomery([0xCBB6_4068_37BF_51F5, 0x2BCE_3357_6B31_5ECE, 0x8EE7_EB4A_7C0F_9E16, 0x4FE3_42E2_FE1A_7F9B]),
        z: one)

    struct Point {
        var x: Limbs
        var y: Limbs
        var z: Limbs  // zero for the point at infinity
        static let infinity = Point(x: [0, 0, 0, 0], y: [0, 0, 0, 0], z: [0, 0, 0, 0])
    }

    // MARK: Bytes and limbs

    /// 32 big-endian bytes as limbs.
    static func limbs(_ bytes: [UInt8]) -> Limbs {
        var out = zero
        for k in 0..<32 {
            let limb: Int = 3 - k / 8
            out[limb] = out[limb] << 8 | UInt64(bytes[k])
        }
        return out
    }

    /// Limbs as 32 big-endian bytes.
    static func bytes(_ limbs: Limbs) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 32)
        for k in 0..<32 {
            let shift: UInt64 = UInt64(56 - (k % 8) * 8)
            out[k] = UInt8(truncatingIfNeeded: limbs[3 - k / 8] >> shift)
        }
        return out
    }

    static func isLess(_ a: Limbs, _ b: Limbs) -> Bool {
        for i in stride(from: 3, through: 0, by: -1) where a[i] != b[i] { return a[i] < b[i] }
        return false
    }

    static func isValidScalar(_ bytes: [UInt8]) -> Bool {
        let k = limbs(bytes)
        return k != zero && isLess(k, n)
    }

    // MARK: Field arithmetic

    static func addLimbs(_ a: Limbs, _ b: Limbs) -> (Limbs, Bool) {
        var out = zero
        var carry = false
        for i in 0..<4 {
            let (s1, o1) = a[i].addingReportingOverflow(b[i])
            let (s2, o2) = s1.addingReportingOverflow(carry ? 1 : 0)
            out[i] = s2
            carry = o1 || o2
        }
        return (out, carry)
    }

    static func subtractLimbs(_ a: Limbs, _ b: Limbs) -> (Limbs, Bool) {
        var out = zero
        var borrow = false
        for i in 0..<4 {
            let (d1, o1) = a[i].subtractingReportingOverflow(b[i])
            let (d2, o2) = d1.subtractingReportingOverflow(borrow ? 1 : 0)
            out[i] = d2
            borrow = o1 || o2
        }
        return (out, borrow)
    }

    static func add(_ a: Limbs, _ b: Limbs) -> Limbs {
        let (sum, carry) = addLimbs(a, b)
        return carry || !isLess(sum, p) ? subtractLimbs(sum, p).0 : sum
    }

    static func subtract(_ a: Limbs, _ b: Limbs) -> Limbs {
        let (difference, borrow) = subtractLimbs(a, b)
        return borrow ? addLimbs(difference, p).0 : difference
    }

    /// a·b + t + c as (high, low) words; it never overflows 128 bits.
    @inline(__always)
    static func multiplyAdd(_ t: UInt64, _ a: UInt64, _ b: UInt64, _ c: UInt64) -> (UInt64, UInt64) {
        let (high, low) = a.multipliedFullWidth(by: b)
        let (l1, o1) = low.addingReportingOverflow(t)
        let (l2, o2) = l1.addingReportingOverflow(c)
        return (high &+ (o1 ? 1 : 0) &+ (o2 ? 1 : 0), l2)
    }

    /// The Montgomery product a·b·2^-256 mod p (coarsely integrated operand scanning).
    static func multiply(_ a: Limbs, _ b: Limbs) -> Limbs {
        var t = [UInt64](repeating: 0, count: 6)
        for i in 0..<4 {
            var carry: UInt64 = 0
            for j in 0..<4 { (carry, t[j]) = multiplyAdd(t[j], a[j], b[i], carry) }
            let (s1, o1) = t[4].addingReportingOverflow(carry)
            t[4] = s1
            t[5] = o1 ? 1 : 0
            let q = t[0] &* pInverse
            carry = multiplyAdd(t[0], q, p[0], 0).0
            for j in 1..<4 { (carry, t[j - 1]) = multiplyAdd(t[j], q, p[j], carry) }
            let (s2, o2) = t[4].addingReportingOverflow(carry)
            t[3] = s2
            t[4] = t[5] &+ (o2 ? 1 : 0)
        }
        let result = Array(t[0..<4])
        return t[4] != 0 || !isLess(result, p) ? subtractLimbs(result, p).0 : result
    }

    static func toMontgomery(_ a: Limbs) -> Limbs { multiply(a, r2) }
    static func fromMontgomery(_ a: Limbs) -> Limbs { multiply(a, [1, 0, 0, 0]) }

    /// a to the power of the exponent, both in and out of Montgomery form as a is.
    static func power(_ a: Limbs, _ exponent: Limbs) -> Limbs {
        var result = one
        for bit in stride(from: 255, through: 0, by: -1) {
            result = multiply(result, result)
            if (exponent[bit / 64] >> UInt64(bit % 64)) & 1 == 1 { result = multiply(result, a) }
        }
        return result
    }

    static func inverse(_ a: Limbs) -> Limbs { power(a, pMinus2) }

    /// x³ - 3x + b, in Montgomery form.
    static func curveRight(_ x: Limbs) -> Limbs {
        let cube = multiply(multiply(x, x), x)
        return add(subtract(cube, add(add(x, x), x)), b)
    }

    static func isOnCurve(x: [UInt8], y: [UInt8]) -> Bool {
        let xl = limbs(x), yl = limbs(y)
        guard isLess(xl, p), isLess(yl, p) else { return false }
        let xm = toMontgomery(xl), ym = toMontgomery(yl)
        return multiply(ym, ym) == curveRight(xm)
    }

    /// The y coordinate of the point with this x and y's parity, if there is one.
    static func y(forX x: [UInt8], odd: Bool) -> [UInt8]? {
        let xl = limbs(x)
        guard isLess(xl, p) else { return nil }
        let right = curveRight(toMontgomery(xl))
        let root = power(right, sqrtExponent)
        guard multiply(root, root) == right else { return nil }
        var y = fromMontgomery(root)
        if (y[0] & 1 == 1) != odd { y = subtractLimbs(p, y).0 }
        return bytes(y)
    }

    // MARK: Points

    static func doublePoint(_ point: Point) -> Point {
        if point.z == zero { return point }
        let delta = multiply(point.z, point.z)
        let gamma = multiply(point.y, point.y)
        let beta = multiply(point.x, gamma)
        let t = multiply(subtract(point.x, delta), add(point.x, delta))
        let alpha = add(add(t, t), t)
        let beta4 = add(add(beta, beta), add(beta, beta))
        let x3 = subtract(multiply(alpha, alpha), add(beta4, beta4))
        let yz = add(point.y, point.z)
        let z3 = subtract(subtract(multiply(yz, yz), gamma), delta)
        let gamma2 = multiply(gamma, gamma)
        let gamma2x2 = add(gamma2, gamma2)
        let gamma2x4 = add(gamma2x2, gamma2x2)
        let gamma8 = add(gamma2x4, gamma2x4)
        let y3 = subtract(multiply(alpha, subtract(beta4, x3)), gamma8)
        return Point(x: x3, y: y3, z: z3)
    }

    static func addPoints(_ p1: Point, _ p2: Point) -> Point {
        if p1.z == zero { return p2 }
        if p2.z == zero { return p1 }
        let z1z1 = multiply(p1.z, p1.z), z2z2 = multiply(p2.z, p2.z)
        let u1 = multiply(p1.x, z2z2), u2 = multiply(p2.x, z1z1)
        let s1 = multiply(multiply(p1.y, p2.z), z2z2), s2 = multiply(multiply(p2.y, p1.z), z1z1)
        let h = subtract(u2, u1)
        let r = add(subtract(s2, s1), subtract(s2, s1))
        if h == zero { return r == zero ? doublePoint(p1) : .infinity }
        let i = multiply(add(h, h), add(h, h))
        let j = multiply(h, i)
        let v = multiply(u1, i)
        let x3 = subtract(subtract(multiply(r, r), j), add(v, v))
        let s1j = multiply(s1, j)
        let y3 = subtract(multiply(r, subtract(v, x3)), add(s1j, s1j))
        let z12 = add(p1.z, p2.z)
        let z3 = multiply(subtract(subtract(multiply(z12, z12), z1z1), z2z2), h)
        return Point(x: x3, y: y3, z: z3)
    }

    /// The point times the 32-byte big-endian scalar, by doubling and adding.
    static func scalarMultiply(_ scalar: [UInt8], _ point: Point) -> Point {
        var result = Point.infinity
        for byte in scalar {
            for bit in stride(from: 7, through: 0, by: -1) {
                result = doublePoint(result)
                if (byte >> UInt8(bit)) & 1 == 1 { result = addPoints(result, point) }
            }
        }
        return result
    }

    /// The point's x and y coordinates as 32 big-endian bytes each; nil at infinity.
    static func affine(_ point: Point) -> ([UInt8], [UInt8])? {
        if point.z == zero { return nil }
        let zInverse = inverse(point.z)
        let zInverse2 = multiply(zInverse, zInverse)
        let x = fromMontgomery(multiply(point.x, zInverse2))
        let y = fromMontgomery(multiply(point.y, multiply(zInverse2, zInverse)))
        return (bytes(x), bytes(y))
    }
}
