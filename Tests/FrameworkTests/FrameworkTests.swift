// The small frameworks against known answers: the hashes against FIPS 180-4 and RFC 1321's
// examples, HMAC against RFC 4231, and the behaviour the web stand-ins promise (no haptic
// hardware, no configured widgets). The same answers hold for Apple's frameworks.
import Testing
import CryptoKit
import CoreHaptics
import WidgetKit
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

@Suite struct HashTests {
    static let abc = Array("abc".utf8)
    static let twoBlocks = Array("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)
    /// 1,280 bytes: many blocks, and a final block that needs no extra padding block.
    static let long: [UInt8] = (0..<5).flatMap { _ in (0...255).map { UInt8($0) } }

    @Test func sha256() {
        #expect(hex(SHA256.hash(data: Self.abc)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(hex(SHA256.hash(data: [UInt8]())) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(hex(SHA256.hash(data: Self.twoBlocks)) == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        #expect(hex(SHA256.hash(data: Self.long)) == "d414b085826eb06778483ba35564dc849e643359f69ed9747878ba6e54985bed")
        #expect(SHA256.byteCount == 32)
        #expect(SHA256Digest.byteCount == 32)
    }

    @Test func sha384AndSHA512() {
        #expect(hex(SHA384.hash(data: Self.abc)) == "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7")
        #expect(hex(SHA512.hash(data: Self.abc)) == "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")
        #expect(hex(SHA384.hash(data: Self.long)) == "f5943b1fe9e4b5bd3b45c83ef1e748f5e0f095f405a67d11a37016e5e908a4c5033bf084186d1e352db6fdda24dda58c")
        #expect(hex(SHA512.hash(data: Self.long)) == "c93f55ccf2fa8c82699ff9b58afe3591242b135d908a6d865e17e38adb41c21d1d5359e51273036373d54d20b5659cc87e6e7b381ff027d33f971416cc590f90")
    }

    @Test func insecure() {
        #expect(hex(Insecure.SHA1.hash(data: Self.abc)) == "a9993e364706816aba3e25717850c26c9cd0d89d")
        #expect(hex(Insecure.SHA1.hash(data: Self.long)) == "e37a04cb2353309f5cff4ee036cfb91a5e31cefd")
        #expect(hex(Insecure.MD5.hash(data: Self.abc)) == "900150983cd24fb0d6963f7d28e17f72")
        #expect(hex(Insecure.MD5.hash(data: Self.twoBlocks)) == "8215ef0796a20bcaaae116d3876c664a")
        #expect(hex(Insecure.MD5.hash(data: Self.long)) == "82829f1f3f2bb0f18b25f278e5bba8bd")
    }

    /// Fed in uneven pieces, the hash is the hash of the whole.
    @Test func incremental() {
        var function = SHA256()
        var start = 0
        for size in [1, 63, 64, 65, 7, 500] {
            function.update(data: Self.long[start..<start + size])
            start += size
        }
        function.update(data: Self.long[start...])
        #expect(function.finalize() == SHA256.hash(data: Self.long))
    }

    @Test func description() {
        #expect(SHA256.hash(data: Self.abc).description == "SHA256 digest: ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(Array(SHA256.hash(data: Self.abc)).count == 32)
    }
}

@Suite struct HMACTests {
    static let message = Array("what do ya want for nothing?".utf8)

    @Test func rfc4231() {
        let jefe = SymmetricKey(data: Array("Jefe".utf8))
        #expect(hex(HMAC<SHA256>.authenticationCode(for: Self.message, using: jefe)) == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
        #expect(hex(HMAC<SHA512>.authenticationCode(for: Self.message, using: jefe)) == "164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea2505549758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737")
        // A key longer than the block is hashed first (test case 6).
        let long = SymmetricKey(data: [UInt8](repeating: 0xaa, count: 131))
        let text = Array("Test Using Larger Than Block-Size Key - Hash Key First".utf8)
        #expect(hex(HMAC<SHA256>.authenticationCode(for: text, using: long)) == "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54")
    }

    @Test func validation() {
        let key = SymmetricKey(size: .bits256)
        #expect(key.bitCount == 256)
        let code = HMAC<SHA256>.authenticationCode(for: Self.message, using: key)
        #expect(HMAC<SHA256>.isValidAuthenticationCode(code, authenticating: Self.message, using: key))
        #expect(HMAC<SHA256>.isValidAuthenticationCode(Array(code), authenticating: Self.message, using: key))
        #expect(!HMAC<SHA256>.isValidAuthenticationCode(code, authenticating: Array("other".utf8), using: key))
        #expect(!HMAC<SHA256>.isValidAuthenticationCode(code, authenticating: Self.message, using: SymmetricKey(size: .bits256)))
    }

    @Test func incremental() {
        let key = SymmetricKey(data: Array("Jefe".utf8))
        var hmac = HMAC<SHA256>(key: key)
        hmac.update(data: Self.message.prefix(10))
        hmac.update(data: Self.message.dropFirst(10))
        #expect(hmac.finalize() == HMAC<SHA256>.authenticationCode(for: Self.message, using: key))
    }
}

@Suite struct HapticsAndWidgetsTests {
    /// A browser has no haptic engine; building and playing a pattern still works.
    @Test func hapticsPlayNothing() throws {
        #expect(!CHHapticEngine.capabilitiesForHardware().supportsHaptics)
        let engine = try CHHapticEngine()
        try engine.start()
        let tap = CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5),
        ], relativeTime: 0)
        let hum = CHHapticEvent(eventType: .hapticContinuous, parameters: [], relativeTime: 0.25, duration: 1)
        let pattern = try CHHapticPattern(events: [tap, hum], parameters: [])
        #expect(pattern.duration == 1.25)
        let player = try engine.makePlayer(with: pattern)
        try player.start(atTime: CHHapticTimeImmediate)
        engine.stop(completionHandler: nil)
    }

    struct Entry: TimelineEntry {
        let date: Date
    }

    @Test func widgetsAreNone() async throws {
        WidgetCenter.shared.reloadAllTimelines()
        WidgetCenter.shared.reloadTimelines(ofKind: "Counter")
        #expect(try await WidgetCenter.shared.currentConfigurations().isEmpty)
        let timeline = Timeline(entries: [Entry(date: Date(timeIntervalSince1970: 0))], policy: .atEnd)
        #expect(timeline.entries.count == 1)
        #expect(timeline.entries[0].relevance == nil)
        #expect(WidgetFamily.systemSmall.description == "systemSmall")
    }
}

@Suite struct ISO8601FormatterTests {
    static let instant = Date(timeIntervalSince1970: 1_793_450_096)

    @Test func internetDateTime() {
        let formatter = ISO8601DateFormatter()
        #expect(formatter.string(from: Self.instant) == "2026-10-31T12:34:56Z")
        #expect(formatter.date(from: "2026-10-31T12:34:56Z") == Self.instant)
        #expect(formatter.date(from: "2026-10-31T14:34:56+02:00") == Self.instant)
        #expect(formatter.date(from: "not a date") == nil)
        formatter.timeZone = TimeZone(secondsFromGMT: 7200)
        #expect(formatter.string(from: Self.instant) == "2026-10-31T14:34:56+02:00")
    }

    @Test func options() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        #expect(formatter.string(from: Self.instant.addingTimeInterval(0.25)) == "2026-10-31T12:34:56.250Z")
        formatter.formatOptions = [.withFullDate]
        #expect(formatter.string(from: Self.instant) == "2026-10-31")
        #expect(formatter.date(from: "2026-10-31") == Date(timeIntervalSince1970: 1_793_404_800))
    }
}

/// Ed25519 against RFC 8032's test vectors (section 7.1).
@Suite struct Curve25519SigningTests {
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

    @Test func rfc8032Vectors() throws {
        let vectors: [(secret: String, publicKey: String, message: String, signature: String)] = [
            ("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
             "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", "",
             "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"),
            ("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
             "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c", "72",
             "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"),
            ("c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7",
             "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025", "af82",
             "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a"),
        ]
        for vector in vectors {
            let key = try Curve25519.Signing.PrivateKey(rawRepresentation: bytes(vector.secret))
            #expect(hex(key.publicKey.rawRepresentation) == vector.publicKey)
            let message = bytes(vector.message)
            let signature = try key.signature(for: message)
            #expect(hex(signature) == vector.signature)
            let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: bytes(vector.publicKey))
            #expect(publicKey.isValidSignature(bytes(vector.signature), for: message))
        }
    }

    @Test func aChangedMessageOrSignatureFails() throws {
        let key = Curve25519.Signing.PrivateKey()
        let message = Array("receipt".utf8)
        let signature = Array(try key.signature(for: message))
        #expect(key.publicKey.isValidSignature(signature, for: message))
        #expect(!key.publicKey.isValidSignature(signature, for: Array("receipT".utf8)))
        var flipped = signature
        flipped[10] ^= 1
        #expect(!key.publicKey.isValidSignature(flipped, for: message))
        // S at or above the group order is rejected, even though it reduces to the same scalar.
        var malleable = signature
        let order: [UInt8] = [0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14,
                              0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x10]
        var carry = 0
        for i in 0..<32 {
            let sum = Int(malleable[32 + i]) + Int(order[i]) + carry
            malleable[32 + i] = UInt8(sum & 0xff)
            carry = sum >> 8
        }
        #expect(!key.publicKey.isValidSignature(malleable, for: message))
        #expect(!key.publicKey.isValidSignature(Array(signature.prefix(63)), for: message))
        #expect(throws: CryptoKitError.incorrectKeySize) { try Curve25519.Signing.PublicKey(rawRepresentation: [UInt8](repeating: 0, count: 31)) }
    }
}
