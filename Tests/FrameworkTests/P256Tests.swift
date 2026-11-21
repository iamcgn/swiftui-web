// P-256 key agreement and HKDF against known answers: the keys, ECDH secret and derived keys
// were computed with OpenSSL (Python's cryptography package), and HKDF against RFC 5869's
// test cases 1 and 3. The same answers hold for Apple's CryptoKit.
import Testing
import CryptoKit
import WebFoundation

private func hexString<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
    let digits = Array("0123456789abcdef")
    var out = ""
    for byte in bytes {
        out.append(digits[Int(byte >> 4)])
        out.append(digits[Int(byte & 0xF)])
    }
    return out
}

private func hexBytes(_ hex: String) -> [UInt8] {
    var out: [UInt8] = []
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        out.append(UInt8(hex[index..<next], radix: 16)!)
        index = next
    }
    return out
}

@Suite struct P256KeyAgreementTests {
    static let alice = "c88f01f510d9ac3f70a292daa2316de544e9aab8afe84049c62a9c57862d1433"
    static let alicePublic = "04dad0b65394221cf9b051e1feca5787d098dfe637fc90b9ef945d0c37725811805271a0461cdb8252d61f1c456fa3e59ab1f45b33accf5f58389e0577b8990bb3"
    static let bob = "c6ef9c5d78ae012a011164acb397ce2088685d8f06bf9be0b283ab46476bee53"
    static let bobPublic = "04d12dfb5289c8d4f81208b70270398c342296970a0bccb74c736fc7554494bf6356fbf3ca366cc23e8157854c13c58d6aac23f046ada30f8353e74f33039872ab"
    static let secret = "d6840f6b42f6edafd13116e0e12565202fef8e9ece7dce03812464d04b9442de"

    @Test func aKeysPublicKeyIsItsProductWithTheGenerator() throws {
        let key = try P256.KeyAgreement.PrivateKey(rawRepresentation: hexBytes(Self.alice))
        #expect(hexString(key.rawRepresentation) == Self.alice)
        #expect(hexString(key.publicKey.x963Representation) == Self.alicePublic)
        #expect(hexString(key.publicKey.rawRepresentation) == String(Self.alicePublic.dropFirst(2)))
        #expect(hexString(key.publicKey.compressedRepresentation) == "03dad0b65394221cf9b051e1feca5787d098dfe637fc90b9ef945d0c3772581180")
        #expect(hexString(key.x963Representation) == Self.alicePublic + Self.alice)
    }

    @Test func bothSidesAgreeOnTheSecret() throws {
        let alice = try P256.KeyAgreement.PrivateKey(rawRepresentation: hexBytes(Self.alice))
        let bob = try P256.KeyAgreement.PrivateKey(rawRepresentation: hexBytes(Self.bob))
        let bobPublic = try P256.KeyAgreement.PublicKey(x963Representation: hexBytes(Self.bobPublic))
        let fromAlice = try alice.sharedSecretFromKeyAgreement(with: bobPublic)
        let fromBob = try bob.sharedSecretFromKeyAgreement(with: alice.publicKey)
        #expect(fromAlice == fromBob)
        #expect(fromAlice.withUnsafeBytes { hexString($0) } == Self.secret)
        let key = fromAlice.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Array("salt".utf8),
                                                    sharedInfo: Array("info".utf8), outputByteCount: 32)
        #expect(key.withUnsafeBytes { hexString($0) } == "92a2cf6402e1ea7e13e18d94071217360535df1a67d81a70275fa3c8e6e20f99")
        let x963 = fromAlice.x963DerivedSymmetricKey(using: SHA256.self, sharedInfo: Array("info".utf8), outputByteCount: 48)
        #expect(x963.withUnsafeBytes { hexString($0) } == "1660bc357314e58d942a6546ef9cc0a1ce31f1960ca93a8d77d2a2838bfd69e97e30a832431c5310593e0ed7e17cb399")
    }

    @Test func aNewKeyAgreesWithItsPartner() throws {
        let one = P256.KeyAgreement.PrivateKey(), other = P256.KeyAgreement.PrivateKey()
        let copy = try P256.KeyAgreement.PrivateKey(rawRepresentation: one.rawRepresentation)
        #expect(Array(copy.publicKey.x963Representation) == Array(one.publicKey.x963Representation))
        let decompressed = try P256.KeyAgreement.PublicKey(compressedRepresentation: other.publicKey.compressedRepresentation)
        #expect(Array(decompressed.x963Representation) == Array(other.publicKey.x963Representation))
        #expect(try one.sharedSecretFromKeyAgreement(with: other.publicKey) == other.sharedSecretFromKeyAgreement(with: one.publicKey))
    }

    @Test func invalidKeysAreRefused() {
        #expect(throws: (any Error).self) { try P256.KeyAgreement.PrivateKey(rawRepresentation: [UInt8](repeating: 0, count: 32)) }
        #expect(throws: (any Error).self) { try P256.KeyAgreement.PrivateKey(rawRepresentation: [UInt8](repeating: 0xFF, count: 32)) }
        #expect(throws: (any Error).self) { try P256.KeyAgreement.PrivateKey(rawRepresentation: [UInt8](repeating: 1, count: 31)) }
        var offCurve = hexBytes(Self.bobPublic)
        offCurve[64] ^= 1
        #expect(throws: (any Error).self) { try P256.KeyAgreement.PublicKey(x963Representation: offCurve) }
        #expect(throws: (any Error).self) { try P256.KeyAgreement.PublicKey(rawRepresentation: offCurve.dropFirst()) }
    }
}

@Suite struct HKDFTests {
    @Test func rfc5869Vectors() {
        let ikm = SymmetricKey(data: [UInt8](repeating: 0x0B, count: 22))
        let one = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, salt: (0..<13).map { UInt8($0) },
                                         info: (0xF0..<0xFA).map { UInt8($0) }, outputByteCount: 42)
        #expect(one.withUnsafeBytes { hexString($0) } == "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865")
        let three = HKDF<SHA256>.deriveKey(inputKeyMaterial: ikm, outputByteCount: 42)
        #expect(three.withUnsafeBytes { hexString($0) } == "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8")
        let prk = HKDF<SHA256>.extract(inputKeyMaterial: ikm, salt: (0..<13).map { UInt8($0) })
        #expect(HKDF<SHA256>.expand(pseudoRandomKey: prk, info: (0xF0..<0xFA).map { UInt8($0) }, outputByteCount: 42) == one)
    }
}
