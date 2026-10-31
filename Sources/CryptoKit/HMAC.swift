// Symmetric keys and HMAC (RFC 2104) over any of the hash functions.

/// The sizes that a symmetric cryptographic key can take.
public struct SymmetricKeySize: Sendable {
    /// The number of bits in the key.
    public let bitCount: Int
    public init(bitCount: Int) {
        precondition(bitCount > 0 && bitCount % 8 == 0, "a key size is a positive whole number of bytes")
        self.bitCount = bitCount
    }
    public static var bits128: SymmetricKeySize { SymmetricKeySize(bitCount: 128) }
    public static var bits192: SymmetricKeySize { SymmetricKeySize(bitCount: 192) }
    public static var bits256: SymmetricKeySize { SymmetricKeySize(bitCount: 256) }
}

/// A symmetric cryptographic key.
public struct SymmetricKey: Sendable, Equatable {
    let bytes: [UInt8]

    /// Creates a key from the data.
    public init<D: Sequence>(data: D) where D.Element == UInt8 { bytes = Array(data) }

    /// Generates a new random key of the given size.
    public init(size: SymmetricKeySize) {
        var generator = SystemRandomNumberGenerator()
        bytes = (0..<size.bitCount / 8).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
    }

    /// The number of bits in the key.
    public var bitCount: Int { bytes.count * 8 }

    /// Calls the closure with the key's bytes.
    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
        try bytes.withUnsafeBytes(body)
    }

    /// Compares keys in constant time.
    public static func == (lhs: SymmetricKey, rhs: SymmetricKey) -> Bool { _constantTimeEqual(lhs.bytes, rhs.bytes) }
}

func _constantTimeEqual(_ a: [UInt8], _ b: [UInt8]) -> Bool {
    guard a.count == b.count else { return false }
    var difference: UInt8 = 0
    for i in a.indices { difference |= a[i] ^ b[i] }
    return difference == 0
}

/// A message authentication code.
public protocol MessageAuthenticationCode: Hashable, Sequence, CustomStringConvertible, Sendable where Element == UInt8 {
    /// The number of bytes in the code.
    var byteCount: Int { get }
    /// Calls the closure with the code's bytes.
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R
}

/// A hash-based message authentication code.
public struct HashedAuthenticationCode<H: HashFunction>: MessageAuthenticationCode {
    let bytes: [UInt8]
    public var byteCount: Int { bytes.count }
    public func makeIterator() -> IndexingIterator<[UInt8]> { bytes.makeIterator() }
    public var description: String {
        let digits = Array("0123456789abcdef")
        let hex = String(bytes.flatMap { [digits[Int($0 >> 4)], digits[Int($0 & 0xF)]] })
        return "HMAC with \(H.self): \(hex)"
    }
    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R { try bytes.withUnsafeBytes(body) }
    public static func == (lhs: Self, rhs: Self) -> Bool { _constantTimeEqual(lhs.bytes, rhs.bytes) }
    public func hash(into hasher: inout Hasher) { hasher.combine(bytes) }
}

/// A hash-based message authentication algorithm.
public struct HMAC<H: HashFunction>: @unchecked Sendable {
    public typealias Key = SymmetricKey
    public typealias MAC = HashedAuthenticationCode<H>

    private var inner: H
    private let outerKey: [UInt8]

    /// Creates a message authentication code generator with the key.
    public init(key: SymmetricKey) {
        var block = key.bytes
        if block.count > H.blockByteCount { block = Array(H.hash(data: block)) }
        block += [UInt8](repeating: 0, count: H.blockByteCount - block.count)
        inner = H()
        inner.update(data: block.map { $0 ^ 0x36 })
        outerKey = block.map { $0 ^ 0x5c }
    }

    /// Adds data to be authenticated.
    public mutating func update<D: Sequence>(data: D) where D.Element == UInt8 { inner.update(data: data) }

    /// Finalizes the code over the data added so far.
    public func finalize() -> HashedAuthenticationCode<H> {
        var outer = H()
        outer.update(data: outerKey)
        outer.update(data: Array(inner.finalize()))
        return HashedAuthenticationCode(bytes: Array(outer.finalize()))
    }

    /// The authentication code of the data under the key.
    public static func authenticationCode<D: Sequence>(for data: D, using key: SymmetricKey) -> HashedAuthenticationCode<H> where D.Element == UInt8 {
        var hmac = HMAC(key: key)
        hmac.update(data: data)
        return hmac.finalize()
    }

    /// Whether the code authenticates the data under the key.
    public static func isValidAuthenticationCode<D: Sequence>(_ mac: HashedAuthenticationCode<H>, authenticating data: D, using key: SymmetricKey) -> Bool where D.Element == UInt8 {
        authenticationCode(for: data, using: key) == mac
    }

    /// Whether the bytes are the authentication code of the data under the key.
    public static func isValidAuthenticationCode<C: Sequence, D: Sequence>(_ authenticationCode: C, authenticating data: D, using key: SymmetricKey) -> Bool where C.Element == UInt8, D.Element == UInt8 {
        _constantTimeEqual(Array(Self.authenticationCode(for: data, using: key)), Array(authenticationCode))
    }
}
