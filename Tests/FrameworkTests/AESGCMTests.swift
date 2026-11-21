// AES-GCM against known answers: test cases 2 and 4 of the GCM specification (McGrew and Viega,
// as in NIST SP 800-38D's validation), the same message under 192- and 256-bit keys, and a
// 60-byte nonce, which the standard hashes into the first counter. The other answers were
// computed with OpenSSL (Python's cryptography package); Apple's CryptoKit gives the same.
import Testing
import CryptoKit
import WebFoundation

private func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
    let digits = Array("0123456789abcdef")
    var out = ""
    for byte in bytes {
        out.append(digits[Int(byte >> 4)])
        out.append(digits[Int(byte & 0xF)])
    }
    return out
}

private func bytes(_ hex: String) -> [UInt8] {
    var out: [UInt8] = []
    var index = hex.startIndex
    while index < hex.endIndex {
        let next = hex.index(index, offsetBy: 2)
        out.append(UInt8(hex[index..<next], radix: 16)!)
        index = next
    }
    return out
}

@Suite struct AESGCMTests {
    static let key128 = "feffe9928665731c6d6a8f9467308308"
    static let plaintext = "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39"
    static let aad = "feedfacedeadbeeffeedfacedeadbeefabaddad2"
    static let nonce = "cafebabefacedbaddecaf888"

    @Test func zeroKeyAndBlock() throws {
        let box = try AES.GCM.seal([UInt8](repeating: 0, count: 16), using: SymmetricKey(data: [UInt8](repeating: 0, count: 16)),
                                   nonce: AES.GCM.Nonce(data: [UInt8](repeating: 0, count: 12)))
        #expect(hex(box.ciphertext) == "0388dace60b6a392f328c2b971b2fe78")
        #expect(hex(box.tag) == "ab6e47d42cec13bdf53a67b21257bddf")
    }

    @Test(arguments: [
        ("feffe9928665731c6d6a8f9467308308", "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e091", "5bc94fbc3221a5db94fae95ae7121a47"),
        ("feffe9928665731c6d6a8f9467308308feffe9928665731c", "3980ca0b3c00e841eb06fac4872a2757859e1ceaa6efd984628593b40ca1e19c7d773d00c144c525ac619d18c84a3f4718e2448b2fe324d9ccda2710", "2519498e80f1478f37ba55bd6d27618c"),
    ])
    func sealsWithAuthenticatedData(key: String, ciphertext: String, tag: String) throws {
        let key = SymmetricKey(data: bytes(key))
        let box = try AES.GCM.seal(bytes(Self.plaintext), using: key, nonce: AES.GCM.Nonce(data: bytes(Self.nonce)),
                                   authenticating: bytes(Self.aad))
        #expect(hex(box.ciphertext) == ciphertext)
        #expect(hex(box.tag) == tag)
        #expect(hex(try AES.GCM.open(box, using: key, authenticating: bytes(Self.aad))) == Self.plaintext)
        let combined = try #require(box.combined)
        #expect(hex(combined) == Self.nonce + ciphertext + tag)
        let reopened = try AES.GCM.SealedBox(combined: combined)
        #expect(hex(try AES.GCM.open(reopened, using: key, authenticating: bytes(Self.aad))) == Self.plaintext)
    }

    @Test func hashesALongNonceIntoTheCounter() throws {
        let key = SymmetricKey(data: bytes(Self.key128 + Self.key128))
        let nonce = try AES.GCM.Nonce(data: bytes("9313225df88406e555909c5aff5269aa6a7a9538534f7da1e4c303d2a318a728c3c0c95156809539fcf0e2429a6b525416aedbf5a0de6a57a637b39b"))
        let box = try AES.GCM.seal(bytes(Self.plaintext), using: key, nonce: nonce, authenticating: bytes(Self.aad))
        #expect(hex(box.ciphertext) == "5a8def2f0c9e53f1f75d7853659e2a20eeb2b22aafde6419a058ab4f6f746bf40fc0c3b780f244452da3ebf1c5d82cdea2418997200ef82e44ae7e3f")
        #expect(hex(box.tag) == "a44a8266ee1c8eb0c8b5d4cf5ae9f19a")
        #expect(box.combined == nil)
        let parts = try AES.GCM.SealedBox(nonce: nonce, ciphertext: box.ciphertext, tag: box.tag)
        #expect(hex(try AES.GCM.open(parts, using: key, authenticating: bytes(Self.aad))) == Self.plaintext)
    }

    @Test func refusesATamperedBoxOrTheWrongKey() throws {
        let key = SymmetricKey(size: .bits256)
        let box = try AES.GCM.seal(Array("club code".utf8), using: key)
        #expect(String(decoding: try AES.GCM.open(box, using: key), as: UTF8.self) == "club code")
        var tampered = Array(try #require(box.combined))
        tampered[12] ^= 1
        #expect(throws: CryptoKitError.authenticationFailure) {
            try AES.GCM.open(try AES.GCM.SealedBox(combined: tampered), using: key)
        }
        #expect(throws: CryptoKitError.authenticationFailure) {
            try AES.GCM.open(box, using: SymmetricKey(size: .bits256))
        }
        #expect(throws: CryptoKitError.authenticationFailure) {
            try AES.GCM.open(box, using: key, authenticating: Array("header".utf8))
        }
    }

    @Test func noncesAndKeysAreContiguousBytes() {
        func byteCount<B: ContiguousBytes>(_ value: B) -> Int { value.withUnsafeBytes { $0.count } }
        #expect(byteCount(AES.GCM.Nonce()) == 12)
        #expect(byteCount(ChaChaPoly.Nonce()) == 12)
        #expect(byteCount(SymmetricKey(size: .bits128)) == 16)
    }

    @Test func checksSizes() {
        #expect(throws: CryptoKitError.incorrectKeySize) {
            try AES.GCM.seal([UInt8](), using: SymmetricKey(data: [UInt8](repeating: 1, count: 20)))
        }
        #expect(throws: CryptoKitError.incorrectParameterSize) { try AES.GCM.Nonce(data: [UInt8](repeating: 0, count: 11)) }
        #expect(throws: CryptoKitError.incorrectParameterSize) { try AES.GCM.SealedBox(combined: [UInt8](repeating: 0, count: 27)) }
        #expect(throws: CryptoKitError.incorrectParameterSize) {
            try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(), ciphertext: [UInt8](), tag: [UInt8](repeating: 0, count: 15))
        }
    }
}
