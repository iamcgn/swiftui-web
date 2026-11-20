// HKDF (RFC 5869) over any of the hash functions: the extract-then-expand key derivation that
// key agreement feeds (a Web Push payload's content key and nonce, RFC 8291).

/// The HMAC-based key derivation function.
public struct HKDF<H: HashFunction>: Sendable {
    /// The pseudorandom key that the input key material and salt extract to. With no salt,
    /// a hash's length of zero bytes, as RFC 5869 specifies.
    public static func extract<Salt: Sequence>(inputKeyMaterial: SymmetricKey, salt: Salt?) -> HashedAuthenticationCode<H>
    where Salt.Element == UInt8 {
        let key = SymmetricKey(data: salt.map { Array($0) } ?? [UInt8](repeating: 0, count: H.byteCount))
        return HMAC<H>.authenticationCode(for: inputKeyMaterial.bytes, using: key)
    }

    /// The pseudorandom key expanded with the info to the byte count.
    public static func expand<PRK: Sequence, Info: Sequence>(pseudoRandomKey: PRK, info: Info?, outputByteCount: Int) -> SymmetricKey
    where PRK.Element == UInt8, Info.Element == UInt8 {
        let key = SymmetricKey(data: pseudoRandomKey)
        let info = info.map { Array($0) } ?? []
        var output: [UInt8] = []
        var previous: [UInt8] = []
        var counter: UInt8 = 1
        while output.count < outputByteCount {
            previous = Array(HMAC<H>.authenticationCode(for: previous + info + [counter], using: key))
            output += previous
            counter &+= 1
        }
        return SymmetricKey(data: output.prefix(outputByteCount))
    }

    /// A key derived from the input key material, salt and info.
    public static func deriveKey<Salt: Sequence, Info: Sequence>(
        inputKeyMaterial: SymmetricKey, salt: Salt, info: Info, outputByteCount: Int
    ) -> SymmetricKey where Salt.Element == UInt8, Info.Element == UInt8 {
        expand(pseudoRandomKey: extract(inputKeyMaterial: inputKeyMaterial, salt: salt), info: info,
               outputByteCount: outputByteCount)
    }

    /// A key derived from the input key material and info, with no salt.
    public static func deriveKey<Info: Sequence>(inputKeyMaterial: SymmetricKey, info: Info, outputByteCount: Int) -> SymmetricKey
    where Info.Element == UInt8 {
        expand(pseudoRandomKey: extract(inputKeyMaterial: inputKeyMaterial, salt: [UInt8]?.none), info: info,
               outputByteCount: outputByteCount)
    }

    /// A key derived from the input key material alone.
    public static func deriveKey(inputKeyMaterial: SymmetricKey, outputByteCount: Int) -> SymmetricKey {
        deriveKey(inputKeyMaterial: inputKeyMaterial, info: [UInt8](), outputByteCount: outputByteCount)
    }
}
