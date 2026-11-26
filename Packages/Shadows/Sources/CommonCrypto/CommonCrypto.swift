// Apple's `CommonCrypto` module for wasm: the C digest and HMAC functions (`CC_SHA256`,
// `CCHmac`) packages call to fingerprint data and sign requests (TelemetryDeck's user hash),
// over SwiftUIWeb's CryptoKit, so each digest matches Apple's byte for byte. The one-shot
// functions and the `_CTX` streaming ones are here for MD5, SHA-1, SHA-256, SHA-384 and SHA-512;
// PBKDF2 key derivation (`CCKeyDerivationPBKDF`) is too; not here: SHA-224 and the ciphers
// (`CCCrypt`).
#if os(WASI)
import CryptoKit

public typealias CC_LONG = UInt32
public typealias CCHmacAlgorithm = UInt32

public var CC_MD5_DIGEST_LENGTH: Int32 { 16 }
public var CC_SHA1_DIGEST_LENGTH: Int32 { 20 }
public var CC_SHA256_DIGEST_LENGTH: Int32 { 32 }
public var CC_SHA384_DIGEST_LENGTH: Int32 { 48 }
public var CC_SHA512_DIGEST_LENGTH: Int32 { 64 }
public var CC_MD5_BLOCK_BYTES: Int32 { 64 }
public var CC_SHA1_BLOCK_BYTES: Int32 { 64 }
public var CC_SHA256_BLOCK_BYTES: Int32 { 64 }
public var CC_SHA384_BLOCK_BYTES: Int32 { 128 }
public var CC_SHA512_BLOCK_BYTES: Int32 { 128 }

/// The digest of `len` bytes at `data`, written to `md` (which must hold the digest).
private func _digest<H: HashFunction>(_ hash: H.Type, _ data: UnsafeRawPointer?, _ len: CC_LONG, _ md: UnsafeMutablePointer<UInt8>?) -> UnsafeMutablePointer<UInt8>? {
    var function = H()
    function.update(bufferPointer: UnsafeRawBufferPointer(start: data, count: Int(len)))
    _write(function.finalize(), to: md)
    return md
}

private func _write<D: CryptoKit.Digest>(_ digest: D, to md: UnsafeMutablePointer<UInt8>?) {
    guard let md else { return }
    for (index, byte) in digest.enumerated() { md[index] = byte }
}

@discardableResult public func CC_MD5(_ data: UnsafeRawPointer!, _ len: CC_LONG, _ md: UnsafeMutablePointer<UInt8>!) -> UnsafeMutablePointer<UInt8>! { _digest(Insecure.MD5.self, data, len, md) }
@discardableResult public func CC_SHA1(_ data: UnsafeRawPointer!, _ len: CC_LONG, _ md: UnsafeMutablePointer<UInt8>!) -> UnsafeMutablePointer<UInt8>! { _digest(Insecure.SHA1.self, data, len, md) }
@discardableResult public func CC_SHA256(_ data: UnsafeRawPointer!, _ len: CC_LONG, _ md: UnsafeMutablePointer<UInt8>!) -> UnsafeMutablePointer<UInt8>! { _digest(SHA256.self, data, len, md) }
@discardableResult public func CC_SHA384(_ data: UnsafeRawPointer!, _ len: CC_LONG, _ md: UnsafeMutablePointer<UInt8>!) -> UnsafeMutablePointer<UInt8>! { _digest(SHA384.self, data, len, md) }
@discardableResult public func CC_SHA512(_ data: UnsafeRawPointer!, _ len: CC_LONG, _ md: UnsafeMutablePointer<UInt8>!) -> UnsafeMutablePointer<UInt8>! { _digest(SHA512.self, data, len, md) }

// MARK: - Streaming

/// A digest's running state: `Init`, then `Update` for each piece, then `Final`.
public struct _CCDigestContext<H: HashFunction> {
    var function = H()
    public init() {}
}
public typealias CC_MD5_CTX = _CCDigestContext<Insecure.MD5>
public typealias CC_SHA1_CTX = _CCDigestContext<Insecure.SHA1>
public typealias CC_SHA256_CTX = _CCDigestContext<SHA256>
public typealias CC_SHA512_CTX = _CCDigestContext<SHA512>
/// SHA-384's state, kept apart from SHA-512's (Apple's shares the struct; its functions don't).
public typealias CC_SHA384_CTX = _CCDigestContext<SHA384>

private func _start<H>(_ c: UnsafeMutablePointer<_CCDigestContext<H>>?) -> Int32 {
    c?.pointee = _CCDigestContext()
    return 1
}
private func _add<H>(_ c: UnsafeMutablePointer<_CCDigestContext<H>>?, _ data: UnsafeRawPointer?, _ len: CC_LONG) -> Int32 {
    c?.pointee.function.update(bufferPointer: UnsafeRawBufferPointer(start: data, count: Int(len)))
    return 1
}
private func _finish<H>(_ md: UnsafeMutablePointer<UInt8>?, _ c: UnsafeMutablePointer<_CCDigestContext<H>>?) -> Int32 {
    guard let c else { return 0 }
    _write(c.pointee.function.finalize(), to: md)
    return 1
}

@discardableResult public func CC_MD5_Init(_ c: UnsafeMutablePointer<CC_MD5_CTX>!) -> Int32 { _start(c) }
@discardableResult public func CC_MD5_Update(_ c: UnsafeMutablePointer<CC_MD5_CTX>!, _ data: UnsafeRawPointer!, _ len: CC_LONG) -> Int32 { _add(c, data, len) }
@discardableResult public func CC_MD5_Final(_ md: UnsafeMutablePointer<UInt8>!, _ c: UnsafeMutablePointer<CC_MD5_CTX>!) -> Int32 { _finish(md, c) }
@discardableResult public func CC_SHA1_Init(_ c: UnsafeMutablePointer<CC_SHA1_CTX>!) -> Int32 { _start(c) }
@discardableResult public func CC_SHA1_Update(_ c: UnsafeMutablePointer<CC_SHA1_CTX>!, _ data: UnsafeRawPointer!, _ len: CC_LONG) -> Int32 { _add(c, data, len) }
@discardableResult public func CC_SHA1_Final(_ md: UnsafeMutablePointer<UInt8>!, _ c: UnsafeMutablePointer<CC_SHA1_CTX>!) -> Int32 { _finish(md, c) }
@discardableResult public func CC_SHA256_Init(_ c: UnsafeMutablePointer<CC_SHA256_CTX>!) -> Int32 { _start(c) }
@discardableResult public func CC_SHA256_Update(_ c: UnsafeMutablePointer<CC_SHA256_CTX>!, _ data: UnsafeRawPointer!, _ len: CC_LONG) -> Int32 { _add(c, data, len) }
@discardableResult public func CC_SHA256_Final(_ md: UnsafeMutablePointer<UInt8>!, _ c: UnsafeMutablePointer<CC_SHA256_CTX>!) -> Int32 { _finish(md, c) }
@discardableResult public func CC_SHA384_Init(_ c: UnsafeMutablePointer<CC_SHA384_CTX>!) -> Int32 { _start(c) }
@discardableResult public func CC_SHA384_Update(_ c: UnsafeMutablePointer<CC_SHA384_CTX>!, _ data: UnsafeRawPointer!, _ len: CC_LONG) -> Int32 { _add(c, data, len) }
@discardableResult public func CC_SHA384_Final(_ md: UnsafeMutablePointer<UInt8>!, _ c: UnsafeMutablePointer<CC_SHA384_CTX>!) -> Int32 { _finish(md, c) }
@discardableResult public func CC_SHA512_Init(_ c: UnsafeMutablePointer<CC_SHA512_CTX>!) -> Int32 { _start(c) }
@discardableResult public func CC_SHA512_Update(_ c: UnsafeMutablePointer<CC_SHA512_CTX>!, _ data: UnsafeRawPointer!, _ len: CC_LONG) -> Int32 { _add(c, data, len) }
@discardableResult public func CC_SHA512_Final(_ md: UnsafeMutablePointer<UInt8>!, _ c: UnsafeMutablePointer<CC_SHA512_CTX>!) -> Int32 { _finish(md, c) }

// MARK: - HMAC

public var kCCHmacAlgSHA1: Int { 0 }
public var kCCHmacAlgMD5: Int { 1 }
public var kCCHmacAlgSHA256: Int { 2 }
public var kCCHmacAlgSHA384: Int { 3 }
public var kCCHmacAlgSHA512: Int { 4 }
public var kCCHmacAlgSHA224: Int { 5 }

/// The code of `dataLength` bytes at `data` under the key, written to `macOut`. SHA-224, which
/// isn't here, writes nothing.
public func CCHmac(_ algorithm: CCHmacAlgorithm, _ key: UnsafeRawPointer!, _ keyLength: Int, _ data: UnsafeRawPointer!, _ dataLength: Int, _ macOut: UnsafeMutableRawPointer!) {
    var context = CCHmacContext()
    CCHmacInit(&context, algorithm, key, keyLength)
    CCHmacUpdate(&context, data, dataLength)
    CCHmacFinal(&context, macOut)
}

/// An HMAC's running state: the algorithm, the key and the bytes so far.
public struct CCHmacContext {
    var algorithm: CCHmacAlgorithm = 0
    var key: [UInt8] = []
    var data: [UInt8] = []
    public init() {}
}

public func CCHmacInit(_ ctx: UnsafeMutablePointer<CCHmacContext>!, _ algorithm: CCHmacAlgorithm, _ key: UnsafeRawPointer!, _ keyLength: Int) {
    ctx.pointee = CCHmacContext()
    ctx.pointee.algorithm = algorithm
    ctx.pointee.key = Array(UnsafeRawBufferPointer(start: key, count: keyLength))
}

public func CCHmacUpdate(_ ctx: UnsafeMutablePointer<CCHmacContext>!, _ data: UnsafeRawPointer!, _ dataLength: Int) {
    ctx.pointee.data += UnsafeRawBufferPointer(start: data, count: dataLength)
}

public func CCHmacFinal(_ ctx: UnsafeMutablePointer<CCHmacContext>!, _ macOut: UnsafeMutableRawPointer!) {
    let context = ctx.pointee
    let key = SymmetricKey(data: context.key)
    func code<H: HashFunction>(_ hash: H.Type) -> [UInt8] { Array(HMAC<H>.authenticationCode(for: context.data, using: key)) }
    let bytes: [UInt8]
    switch Int(context.algorithm) {
    case kCCHmacAlgSHA1: bytes = code(Insecure.SHA1.self)
    case kCCHmacAlgMD5: bytes = code(Insecure.MD5.self)
    case kCCHmacAlgSHA256: bytes = code(SHA256.self)
    case kCCHmacAlgSHA384: bytes = code(SHA384.self)
    case kCCHmacAlgSHA512: bytes = code(SHA512.self)
    default: return
    }
    guard let macOut else { return }
    for (index, byte) in bytes.enumerated() { macOut.storeBytes(of: byte, toByteOffset: index, as: UInt8.self) }
}

// MARK: - Key derivation

public typealias CCPBKDFAlgorithm = UInt32
public typealias CCPseudoRandomAlgorithm = UInt32
public typealias CCStatus = Int32

public var kCCPBKDF2: Int { 2 }
public var kCCPRFHmacAlgSHA1: Int { 1 }
public var kCCPRFHmacAlgSHA224: Int { 2 }
public var kCCPRFHmacAlgSHA256: Int { 3 }
public var kCCPRFHmacAlgSHA384: Int { 4 }
public var kCCPRFHmacAlgSHA512: Int { 5 }

public var kCCSuccess: Int { 0 }
public var kCCParamError: Int { -4300 }
public var kCCBufferTooSmall: Int { -4301 }
public var kCCMemoryFailure: Int { -4302 }
public var kCCAlignmentError: Int { -4303 }
public var kCCDecodeError: Int { -4304 }
public var kCCUnimplemented: Int { -4305 }

/// PBKDF2 (RFC 8018) over HMAC with `prf`'s hash: the first `count` bytes of the blocks
/// T_i = U_1 ^ … ^ U_rounds, U_1 = HMAC(password, salt || i), U_j = HMAC(password, U_j-1).
private func _pbkdf2<H: HashFunction>(_ hash: H.Type, password: [UInt8], salt: [UInt8], rounds: UInt32, count: Int) -> [UInt8] {
    let key = SymmetricKey(data: password)
    var out: [UInt8] = []
    var block: UInt32 = 1
    while out.count < count {
        let index = [UInt8(block >> 24), UInt8((block >> 16) & 0xFF), UInt8((block >> 8) & 0xFF), UInt8(block & 0xFF)]
        var u = Array(HMAC<H>.authenticationCode(for: salt + index, using: key))
        var t = u
        if rounds > 1 {
            for _ in 1..<rounds {
                u = Array(HMAC<H>.authenticationCode(for: u, using: key))
                for i in t.indices { t[i] ^= u[i] }
            }
        }
        out += t
        block += 1
    }
    return Array(out.prefix(count))
}

/// Derives `derivedKeyLen` bytes from a password and salt with PBKDF2 (the one algorithm
/// Core Crypto has); `kCCParamError` for another algorithm, no rounds or no output, and
/// `kCCUnimplemented` for HMAC-SHA-224.
public func CCKeyDerivationPBKDF(_ algorithm: CCPBKDFAlgorithm, _ password: UnsafePointer<CChar>!, _ passwordLen: Int,
                                 _ salt: UnsafePointer<UInt8>!, _ saltLen: Int, _ prf: CCPseudoRandomAlgorithm, _ rounds: UInt32,
                                 _ derivedKey: UnsafeMutablePointer<UInt8>!, _ derivedKeyLen: Int) -> Int32 {
    guard Int(algorithm) == kCCPBKDF2, rounds > 0, derivedKeyLen > 0, let derivedKey else { return Int32(kCCParamError) }
    let passwordBytes = password.map { Array(UnsafeRawBufferPointer(start: UnsafeRawPointer($0), count: passwordLen)) } ?? []
    let saltBytes = salt.map { Array(UnsafeBufferPointer(start: $0, count: saltLen)) } ?? []
    let bytes: [UInt8]
    switch Int(prf) {
    case kCCPRFHmacAlgSHA1: bytes = _pbkdf2(Insecure.SHA1.self, password: passwordBytes, salt: saltBytes, rounds: rounds, count: derivedKeyLen)
    case kCCPRFHmacAlgSHA256: bytes = _pbkdf2(SHA256.self, password: passwordBytes, salt: saltBytes, rounds: rounds, count: derivedKeyLen)
    case kCCPRFHmacAlgSHA384: bytes = _pbkdf2(SHA384.self, password: passwordBytes, salt: saltBytes, rounds: rounds, count: derivedKeyLen)
    case kCCPRFHmacAlgSHA512: bytes = _pbkdf2(SHA512.self, password: passwordBytes, salt: saltBytes, rounds: rounds, count: derivedKeyLen)
    case kCCPRFHmacAlgSHA224: return Int32(kCCUnimplemented)
    default: return Int32(kCCParamError)
    }
    for (offset, byte) in bytes.enumerated() { derivedKey[offset] = byte }
    return Int32(kCCSuccess)
}
#endif
