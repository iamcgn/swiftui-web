// CryptoKit on wasm and Linux (where Apple's is missing): the hash functions, HMAC and
// symmetric keys apps use to fingerprint data, sign requests (OAuth's PKCE challenge, a webhook
// signature) and derive identifiers. Pure Swift; the digests match Apple's byte for byte. Not
// here: ciphers (AES, ChaChaPoly), public-key signatures and key agreement (Curve25519, P256),
// HKDF, the Secure Enclave.
//
// Inputs are any sequence of bytes (`Data`, `[UInt8]`, a slice, `Data(string.utf8)`), which
// covers every `DataProtocol` value Apple's accepts.
// Apple's frameworks re-export Foundation: a file importing only this module names Data.
@_exported import WebFoundation

/// A type that represents the output of a hash.
public protocol Digest: Hashable, Sequence, CustomStringConvertible, Sendable where Element == UInt8 {
    /// The number of bytes in the digest.
    static var byteCount: Int { get }
    /// Calls the closure with the digest's bytes.
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R
}

extension Digest {
    /// The digest's bytes as lower-case hexadecimal.
    var _hex: String {
        var out = ""
        for byte in self {
            let digits = Array("0123456789abcdef")
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0xF)])
        }
        return out
    }
}

/// The bytes of a digest or authentication code, kept in an array.
public struct _DigestBytes: Hashable, Sendable {
    var bytes: [UInt8]
}

/// A type that performs cryptographically secure hashing.
public protocol HashFunction {
    associatedtype Digest: CryptoKit.Digest
    /// The number of bytes the function processes at a time.
    static var blockByteCount: Int { get }
    /// The number of bytes in the digest.
    static var byteCount: Int { get }
    /// Creates a hash function for incremental hashing.
    init()
    /// Adds the bytes to the hash.
    mutating func update(bufferPointer: UnsafeRawBufferPointer)
    /// Returns the digest of the bytes added so far.
    func finalize() -> Digest
}

extension HashFunction {
    public static var byteCount: Int { Digest.byteCount }

    /// The digest of the data.
    public static func hash<D: Sequence>(data: D) -> Digest where D.Element == UInt8 {
        var function = Self()
        function.update(data: data)
        return function.finalize()
    }

    /// Adds the data to the hash.
    public mutating func update<D: Sequence>(data: D) where D.Element == UInt8 {
        let bytes = Array(data)
        bytes.withUnsafeBytes { update(bufferPointer: $0) }
    }
}

/// Declares a digest type over `_DigestBytes`: equal, hashable, a sequence of its bytes, and
/// described as Apple's are (`SHA256 digest: 2cf24d…`).
public protocol _ByteDigest: Digest {
    var _storage: _DigestBytes { get }
    init(_storage: _DigestBytes)
    static var _name: String { get }
}

extension _ByteDigest {
    public func makeIterator() -> IndexingIterator<[UInt8]> { _storage.bytes.makeIterator() }
    public var description: String { "\(Self._name) digest: \(_hex)" }
    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try _storage.bytes.withUnsafeBytes(body)
    }
}
