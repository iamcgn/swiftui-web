// Ed25519 signatures (RFC 8032) over Curve25519, as `Curve25519.Signing`: keys from their 32
// raw bytes, signing, and verifying, which is what a purchase library checks its server's
// responses with. Arithmetic after TweetNaCl (public domain): a field element is sixteen 16-bit
// limbs in Int64s, points are extended coordinates. Signatures are deterministic, as RFC 8032
// specifies, and match Apple's byte for byte.

/// Errors from CryptoKit's key and signature operations.
public enum CryptoKitError: Error, Equatable, Sendable {
    case incorrectKeySize
    case incorrectParameterSize
    case authenticationFailure
    case underlyingCoreCryptoError(error: Int32)
    case wrapFailure
    case unwrapFailure
    case invalidParameter
}

/// The elliptic curve Curve25519.
public enum Curve25519 {
    /// Ed25519 signing.
    public enum Signing {
        /// A key that checks Ed25519 signatures.
        public struct PublicKey: Sendable, Equatable {
            let bytes: [UInt8]

            /// A key from its 32 bytes.
            public init<D: Sequence>(rawRepresentation data: D) throws where D.Element == UInt8 {
                let bytes = Array(data)
                guard bytes.count == 32 else { throw CryptoKitError.incorrectKeySize }
                self.bytes = bytes
            }

            init(_bytes: [UInt8]) { bytes = _bytes }

            /// The key's 32 bytes.
            public var rawRepresentation: Data { Data(bytes) }

            /// Whether the 64-byte signature is the key's signature of the data.
            public func isValidSignature<S: Sequence, D: Sequence>(_ signature: S, for data: D) -> Bool
            where S.Element == UInt8, D.Element == UInt8 {
                _Ed25519.verify(signature: Array(signature), message: Array(data), publicKey: bytes)
            }
        }

        /// A key that makes Ed25519 signatures.
        public struct PrivateKey: Sendable {
            let seed: [UInt8]

            /// A new random key.
            public init() {
                var generator = SystemRandomNumberGenerator()
                seed = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
            }

            /// A key from its 32 bytes (the RFC 8032 seed).
            public init<D: Sequence>(rawRepresentation data: D) throws where D.Element == UInt8 {
                let bytes = Array(data)
                guard bytes.count == 32 else { throw CryptoKitError.incorrectKeySize }
                seed = bytes
            }

            /// The key's 32 bytes.
            public var rawRepresentation: Data { Data(seed) }

            /// The public key that checks this key's signatures.
            public var publicKey: PublicKey { PublicKey(_bytes: _Ed25519.publicKey(seed: seed)) }

            /// The 64-byte signature of the data.
            public func signature<D: Sequence>(for data: D) throws -> Data where D.Element == UInt8 {
                Data(_Ed25519.sign(message: Array(data), seed: seed))
            }
        }
    }
}

enum _Ed25519 {
    typealias GF = [Int64]

    static let gf0: GF = Array(repeating: 0, count: 16)
    static let gf1: GF = [1] + Array(repeating: 0, count: 15)
    static let D: GF = [0x78a3, 0x1359, 0x4dca, 0x75eb, 0xd8ab, 0x4141, 0x0a4d, 0x0070,
                        0xe898, 0x7779, 0x4079, 0x8cc7, 0xfe73, 0x2b6f, 0x6cee, 0x5203]
    static let D2: GF = [0xf159, 0x26b2, 0x9b94, 0xebd6, 0xb156, 0x8283, 0x149a, 0x00e0,
                         0xd130, 0xeef3, 0x80f2, 0x198e, 0xfce7, 0x56df, 0xd9dc, 0x2406]
    static let X: GF = [0xd51a, 0x8f25, 0x2d60, 0xc956, 0xa7b2, 0x9525, 0xc760, 0x692c,
                        0xdc5c, 0xfdd6, 0xe231, 0xc0a4, 0x53fe, 0xcd6e, 0x36d3, 0x2169]
    static let Y: GF = [0x6658] + Array(repeating: 0x6666, count: 15)
    static let I: GF = [0xa0b0, 0x4a0e, 0x1b27, 0xc4ee, 0xe478, 0xad2f, 0x1806, 0x2f43,
                        0xd7a7, 0x3dfb, 0x0099, 0x2b4d, 0xdf0b, 0x4fc1, 0x2480, 0x2b83]
    /// The order of the base point, little-endian.
    static let L: [Int64] = [0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14,
                             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x10]

    // MARK: Field arithmetic mod 2^255 - 19

    static func car(_ o: inout GF) {
        for i in 0..<16 {
            o[i] += 1 << 16
            let c = o[i] >> 16
            if i < 15 { o[i + 1] += c - 1 } else { o[0] += 38 * (c - 1) }
            o[i] -= c << 16
        }
    }

    static func sel(_ p: inout GF, _ q: inout GF, _ b: Int64) {
        let c = ~(b - 1)
        for i in 0..<16 {
            let t = c & (p[i] ^ q[i])
            p[i] ^= t
            q[i] ^= t
        }
    }

    static func pack(_ n: GF) -> [UInt8] {
        var t = n
        car(&t); car(&t); car(&t)
        var m = gf0
        for _ in 0..<2 {
            m[0] = t[0] - 0xffed
            for i in 1..<15 {
                m[i] = t[i] - 0xffff - ((m[i - 1] >> 16) & 1)
                m[i - 1] &= 0xffff
            }
            m[15] = t[15] - 0x7fff - ((m[14] >> 16) & 1)
            let b = (m[15] >> 16) & 1
            m[14] &= 0xffff
            sel(&t, &m, 1 - b)
        }
        var o = [UInt8](repeating: 0, count: 32)
        for i in 0..<16 {
            o[2 * i] = UInt8(truncatingIfNeeded: t[i] & 0xff)
            o[2 * i + 1] = UInt8(truncatingIfNeeded: t[i] >> 8)
        }
        return o
    }

    static func neq(_ a: GF, _ b: GF) -> Bool { pack(a) != pack(b) }
    static func par(_ a: GF) -> Int64 { Int64(pack(a)[0] & 1) }

    static func unpack(_ n: [UInt8]) -> GF {
        var o = gf0
        for i in 0..<16 { o[i] = Int64(n[2 * i]) + (Int64(n[2 * i + 1]) << 8) }
        o[15] &= 0x7fff
        return o
    }

    static func add(_ a: GF, _ b: GF) -> GF { (0..<16).map { a[$0] + b[$0] } }
    static func sub(_ a: GF, _ b: GF) -> GF { (0..<16).map { a[$0] - b[$0] } }

    static func mul(_ a: GF, _ b: GF) -> GF {
        var t = [Int64](repeating: 0, count: 31)
        for i in 0..<16 {
            for j in 0..<16 { t[i + j] += a[i] * b[j] }
        }
        for i in 0..<15 { t[i] += 38 * t[i + 16] }
        var o = Array(t[0..<16])
        car(&o); car(&o)
        return o
    }

    static func sq(_ a: GF) -> GF { mul(a, a) }

    static func inv(_ i: GF) -> GF {
        var c = i
        for a in stride(from: 253, through: 0, by: -1) {
            c = sq(c)
            if a != 2 && a != 4 { c = mul(c, i) }
        }
        return c
    }

    static func pow2523(_ i: GF) -> GF {
        var c = i
        for a in stride(from: 250, through: 0, by: -1) {
            c = sq(c)
            if a != 1 { c = mul(c, i) }
        }
        return c
    }

    // MARK: Points

    typealias Point = [GF]

    static func add(_ p: inout Point, _ q: Point) {
        var a = sub(p[1], p[0]), t = sub(q[1], q[0])
        a = mul(a, t)
        var b = add(p[0], p[1])
        t = add(q[0], q[1])
        b = mul(b, t)
        var c = mul(p[3], q[3])
        c = mul(c, D2)
        var d = mul(p[2], q[2])
        d = add(d, d)
        let e = sub(b, a), f = sub(d, c), g = add(d, c), h = add(b, a)
        p[0] = mul(e, f)
        p[1] = mul(h, g)
        p[2] = mul(g, f)
        p[3] = mul(e, h)
    }

    static func cswap(_ p: inout Point, _ q: inout Point, _ b: Int64) {
        for i in 0..<4 { sel(&p[i], &q[i], b) }
    }

    static func pack(point p: Point) -> [UInt8] {
        let zi = inv(p[2])
        let tx = mul(p[0], zi), ty = mul(p[1], zi)
        var r = pack(ty)
        r[31] ^= UInt8(par(tx) << 7)
        return r
    }

    static func scalarmult(_ q: Point, _ s: [UInt8]) -> Point {
        var p: Point = [gf0, gf1, gf1, gf0]
        var q = q
        for i in stride(from: 255, through: 0, by: -1) {
            let b = Int64((s[i / 8] >> UInt8(i & 7)) & 1)
            cswap(&p, &q, b)
            add(&q, p)
            add(&p, p)
            cswap(&p, &q, b)
        }
        return p
    }

    static func scalarbase(_ s: [UInt8]) -> Point {
        scalarmult([X, Y, gf1, mul(X, Y)], s)
    }

    /// The negated point the key's bytes encode, or nil when they encode none.
    static func unpackneg(_ p: [UInt8]) -> Point? {
        var r: Point = [gf0, gf0, gf1, gf0]
        r[1] = unpack(p)
        var num = sq(r[1])
        var den = mul(num, D)
        num = sub(num, r[2])
        den = add(r[2], den)
        let den2 = sq(den), den4 = sq(den2), den6 = mul(den4, den2)
        var t = mul(den6, num)
        t = mul(t, den)
        t = pow2523(t)
        t = mul(t, num)
        t = mul(t, den)
        t = mul(t, den)
        r[0] = mul(t, den)
        var chk = mul(sq(r[0]), den)
        if neq(chk, num) { r[0] = mul(r[0], I) }
        chk = mul(sq(r[0]), den)
        if neq(chk, num) { return nil }
        if par(r[0]) == Int64(p[31] >> 7) { r[0] = sub(gf0, r[0]) }
        r[3] = mul(r[0], r[1])
        return r
    }

    // MARK: Scalars mod L

    static func modL(_ x: inout [Int64]) -> [UInt8] {
        for i in stride(from: 63, through: 32, by: -1) {
            var carry: Int64 = 0
            var j = i - 32
            while j < i - 12 {
                x[j] += carry - 16 * x[i] * L[j - (i - 32)]
                carry = (x[j] + 128) >> 8
                x[j] -= carry << 8
                j += 1
            }
            x[j] += carry
            x[i] = 0
        }
        var carry: Int64 = 0
        for j in 0..<32 {
            x[j] += carry - (x[31] >> 4) * L[j]
            carry = x[j] >> 8
            x[j] &= 255
        }
        for j in 0..<32 { x[j] -= carry * L[j] }
        var r = [UInt8](repeating: 0, count: 32)
        for i in 0..<32 {
            x[i + 1] += x[i] >> 8
            r[i] = UInt8(truncatingIfNeeded: x[i] & 255)
        }
        return r
    }

    static func reduce(_ bytes: [UInt8]) -> [UInt8] {
        var x = bytes.map { Int64($0) }
        return modL(&x)
    }

    static func sha512(_ parts: [UInt8]...) -> [UInt8] {
        var hash = SHA512()
        for part in parts { hash.update(data: part) }
        return Array(hash.finalize())
    }

    static func expandedSecret(_ seed: [UInt8]) -> [UInt8] {
        var d = sha512(seed)
        d[0] &= 248
        d[31] &= 127
        d[31] |= 64
        return d
    }

    // MARK: Ed25519

    static func publicKey(seed: [UInt8]) -> [UInt8] {
        pack(point: scalarbase(Array(expandedSecret(seed)[0..<32])))
    }

    static func sign(message: [UInt8], seed: [UInt8]) -> [UInt8] {
        let d = expandedSecret(seed)
        let pk = publicKey(seed: seed)
        let r = reduce(sha512(Array(d[32..<64]), message))
        let rPoint = pack(point: scalarbase(r))
        let h = reduce(sha512(rPoint, pk, message))
        var x = [Int64](repeating: 0, count: 64)
        for i in 0..<32 { x[i] = Int64(r[i]) }
        for i in 0..<32 {
            for j in 0..<32 { x[i + j] += Int64(h[i]) * Int64(d[j]) }
        }
        return rPoint + modL(&x)
    }

    static func verify(signature: [UInt8], message: [UInt8], publicKey: [UInt8]) -> Bool {
        guard signature.count == 64, publicKey.count == 32, let q = unpackneg(publicKey) else { return false }
        let s = Array(signature[32..<64])
        // S must be below the group order, as RFC 8032 requires (no malleable signatures).
        guard isBelowL(s) else { return false }
        let h = reduce(sha512(Array(signature[0..<32]), publicKey, message))
        var p = scalarmult(q, h)
        add(&p, scalarbase(s))
        return pack(point: p) == Array(signature[0..<32])
    }

    static func isBelowL(_ s: [UInt8]) -> Bool {
        for i in stride(from: 31, through: 0, by: -1) {
            let l = UInt8(L[i])
            if s[i] < l { return true }
            if s[i] > l { return false }
        }
        return false
    }
}
