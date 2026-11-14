// ChaChaPoly: the ChaCha20-Poly1305 authenticated cipher (RFC 8439), Apple's `ChaChaPoly`.
// Pure Swift: ChaCha20 encrypts the message from block 1 of the key stream, block 0's first 32
// bytes key a one-time Poly1305 authenticator over the authenticated data and the ciphertext.
// The sealed boxes match Apple's byte for byte (the tests check the RFC's vector), so data sealed
// here opens on an iPhone and the other way round.

/// The ChaCha20-Poly1305 cipher.
public enum ChaChaPoly {
    /// A 12-byte value used once per message under a key.
    public struct Nonce: Sequence, Sendable, Hashable {
        let bytes: [UInt8]

        /// A random nonce.
        public init() {
            var generator = SystemRandomNumberGenerator()
            bytes = (0..<12).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        }

        /// A nonce from 12 bytes of data.
        public init<D: Sequence>(data: D) throws where D.Element == UInt8 {
            let bytes = Array(data)
            guard bytes.count == 12 else { throw CryptoKitError.incorrectParameterSize }
            self.bytes = bytes
        }

        public func makeIterator() -> IndexingIterator<[UInt8]> { bytes.makeIterator() }

        /// Calls the closure with the nonce's bytes.
        public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
            try bytes.withUnsafeBytes(body)
        }
    }

    /// A message sealed with ChaChaPoly: its nonce, ciphertext and 16-byte tag.
    public struct SealedBox: Sendable {
        public let nonce: Nonce
        let cipherBytes: [UInt8]
        let tagBytes: [UInt8]

        /// The encrypted message.
        public var ciphertext: Data { Data(cipherBytes) }
        /// The authentication tag.
        public var tag: Data { Data(tagBytes) }
        /// The nonce, the ciphertext and the tag, one after another.
        public var combined: Data { Data(nonce.bytes + cipherBytes + tagBytes) }

        /// A sealed box from its combined form (nonce, ciphertext, tag).
        public init<D: Sequence>(combined: D) throws where D.Element == UInt8 {
            let bytes = Array(combined)
            guard bytes.count >= 12 + 16 else { throw CryptoKitError.incorrectParameterSize }
            nonce = try Nonce(data: bytes[..<12])
            cipherBytes = Array(bytes[12..<(bytes.count - 16)])
            tagBytes = Array(bytes[(bytes.count - 16)...])
        }

        /// A sealed box from its parts.
        public init<C: Sequence, T: Sequence>(nonce: Nonce, ciphertext: C, tag: T) throws where C.Element == UInt8, T.Element == UInt8 {
            let tag = Array(tag)
            guard tag.count == 16 else { throw CryptoKitError.incorrectParameterSize }
            self.nonce = nonce
            cipherBytes = Array(ciphertext)
            tagBytes = tag
        }

        init(nonce: Nonce, cipherBytes: [UInt8], tagBytes: [UInt8]) {
            self.nonce = nonce
            self.cipherBytes = cipherBytes
            self.tagBytes = tagBytes
        }
    }

    /// Encrypts and authenticates `message`, with a random nonce unless one is given.
    public static func seal<Plaintext: Sequence>(_ message: Plaintext, using key: SymmetricKey, nonce: Nonce? = nil) throws -> SealedBox
    where Plaintext.Element == UInt8 {
        try seal(message, using: key, nonce: nonce, authenticating: [UInt8]())
    }

    /// Encrypts and authenticates `message`, also authenticating (not encrypting) `authenticatedData`.
    public static func seal<Plaintext: Sequence, AuthenticatedData: Sequence>(
        _ message: Plaintext, using key: SymmetricKey, nonce: Nonce? = nil, authenticating authenticatedData: AuthenticatedData
    ) throws -> SealedBox where Plaintext.Element == UInt8, AuthenticatedData.Element == UInt8 {
        guard key.bytes.count == 32 else { throw CryptoKitError.incorrectKeySize }
        let nonce = nonce ?? Nonce()
        let ciphertext = _ChaCha20.xor(Array(message), key: key.bytes, nonce: nonce.bytes, counter: 1)
        let tag = tag(ciphertext: ciphertext, authenticatedData: Array(authenticatedData), key: key.bytes, nonce: nonce.bytes)
        return SealedBox(nonce: nonce, cipherBytes: ciphertext, tagBytes: tag)
    }

    /// Checks the box's tag and decrypts its message; a tag that doesn't match throws
    /// `CryptoKitError.authenticationFailure`.
    public static func open(_ sealedBox: SealedBox, using key: SymmetricKey) throws -> Data {
        try open(sealedBox, using: key, authenticating: [UInt8]())
    }

    /// Checks the box's tag over it and `authenticatedData`, then decrypts its message.
    public static func open<AuthenticatedData: Sequence>(_ sealedBox: SealedBox, using key: SymmetricKey,
                                                         authenticating authenticatedData: AuthenticatedData) throws -> Data
    where AuthenticatedData.Element == UInt8 {
        guard key.bytes.count == 32 else { throw CryptoKitError.incorrectKeySize }
        let expected = tag(ciphertext: sealedBox.cipherBytes, authenticatedData: Array(authenticatedData),
                           key: key.bytes, nonce: sealedBox.nonce.bytes)
        guard _constantTimeEqual(expected, sealedBox.tagBytes) else { throw CryptoKitError.authenticationFailure }
        return Data(_ChaCha20.xor(sealedBox.cipherBytes, key: key.bytes, nonce: sealedBox.nonce.bytes, counter: 1))
    }

    /// The Poly1305 tag (RFC 8439 2.8): keyed by block 0 of the key stream, over the
    /// authenticated data and the ciphertext, each padded to 16 bytes, then their lengths.
    static func tag(ciphertext: [UInt8], authenticatedData: [UInt8], key: [UInt8], nonce: [UInt8]) -> [UInt8] {
        let oneTimeKey = Array(_ChaCha20.block(key: key, nonce: nonce, counter: 0)[..<32])
        var input = authenticatedData
        input += [UInt8](repeating: 0, count: (16 - authenticatedData.count % 16) % 16)
        input += ciphertext
        input += [UInt8](repeating: 0, count: (16 - ciphertext.count % 16) % 16)
        for length in [UInt64(authenticatedData.count), UInt64(ciphertext.count)] {
            for shift in stride(from: 0, to: 64, by: 8) { input.append(UInt8(truncatingIfNeeded: length >> UInt64(shift))) }
        }
        return _Poly1305.authenticate(input, key: oneTimeKey)
    }
}

/// The ChaCha20 stream cipher (RFC 8439 2.3 and 2.4).
enum _ChaCha20 {
    private static func littleEndian(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
    }

    /// The 64-byte key-stream block at `counter`.
    static func block(key: [UInt8], nonce: [UInt8], counter: UInt32) -> [UInt8] {
        var state: [UInt32] = [0x6170_7865, 0x3320_646E, 0x7962_2D32, 0x6B20_6574]
        for i in 0..<8 { state.append(littleEndian(key, i * 4)) }
        state.append(counter)
        for i in 0..<3 { state.append(littleEndian(nonce, i * 4)) }
        var x = state
        func quarterRound(_ a: Int, _ b: Int, _ c: Int, _ d: Int) {
            x[a] = x[a] &+ x[b]; x[d] ^= x[a]; x[d] = x[d] << 16 | x[d] >> 16
            x[c] = x[c] &+ x[d]; x[b] ^= x[c]; x[b] = x[b] << 12 | x[b] >> 20
            x[a] = x[a] &+ x[b]; x[d] ^= x[a]; x[d] = x[d] << 8 | x[d] >> 24
            x[c] = x[c] &+ x[d]; x[b] ^= x[c]; x[b] = x[b] << 7 | x[b] >> 25
        }
        for _ in 0..<10 {
            quarterRound(0, 4, 8, 12); quarterRound(1, 5, 9, 13); quarterRound(2, 6, 10, 14); quarterRound(3, 7, 11, 15)
            quarterRound(0, 5, 10, 15); quarterRound(1, 6, 11, 12); quarterRound(2, 7, 8, 13); quarterRound(3, 4, 9, 14)
        }
        var out: [UInt8] = []
        out.reserveCapacity(64)
        for i in 0..<16 {
            let word = x[i] &+ state[i]
            out += [UInt8(truncatingIfNeeded: word), UInt8(truncatingIfNeeded: word >> 8),
                    UInt8(truncatingIfNeeded: word >> 16), UInt8(truncatingIfNeeded: word >> 24)]
        }
        return out
    }

    /// `data` XORed with the key stream from block `counter` on: encrypts and decrypts alike.
    static func xor(_ data: [UInt8], key: [UInt8], nonce: [UInt8], counter: UInt32) -> [UInt8] {
        var out = data
        var counter = counter
        var offset = 0
        while offset < data.count {
            let stream = block(key: key, nonce: nonce, counter: counter)
            for i in 0..<min(64, data.count - offset) { out[offset + i] ^= stream[i] }
            offset += 64
            counter &+= 1
        }
        return out
    }
}

/// The Poly1305 one-time authenticator (RFC 8439 2.5), in five 26-bit limbs.
enum _Poly1305 {
    static func authenticate(_ message: [UInt8], key: [UInt8]) -> [UInt8] {
        func word(_ bytes: [UInt8], _ at: Int) -> UInt32 {
            UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
        }
        let mask: UInt32 = 0x3FF_FFFF
        // r, clamped.
        let r0 = word(key, 0) & 0x3FF_FFFF
        let r1 = (word(key, 3) >> 2) & 0x3FF_FF03
        let r2 = (word(key, 6) >> 4) & 0x3FF_C0FF
        let r3 = (word(key, 9) >> 6) & 0x3F0_3FFF
        let r4 = (word(key, 12) >> 8) & 0x00F_FFFF
        let s1 = r1 &* 5, s2 = r2 &* 5, s3 = r3 &* 5, s4 = r4 &* 5
        var h0: UInt32 = 0, h1: UInt32 = 0, h2: UInt32 = 0, h3: UInt32 = 0, h4: UInt32 = 0

        var offset = 0
        while offset < message.count {
            var block = [UInt8](repeating: 0, count: 17)
            let count = min(16, message.count - offset)
            for i in 0..<count { block[i] = message[offset + i] }
            // A full block's high bit is 2^128; a short one is padded with a 1 byte instead.
            let hibit: UInt32
            if count == 16 { hibit = 1 << 24 } else { block[count] = 1; hibit = 0 }
            h0 &+= word(block, 0) & mask
            h1 &+= (word(block, 3) >> 2) & mask
            h2 &+= (word(block, 6) >> 4) & mask
            h3 &+= (word(block, 9) >> 6) & mask
            h4 &+= (word(block, 12) >> 8) | hibit

            func m(_ a: UInt32, _ b: UInt32) -> UInt64 { UInt64(a) * UInt64(b) }
            let d0 = m(h0, r0) &+ m(h1, s4) &+ m(h2, s3) &+ m(h3, s2) &+ m(h4, s1)
            var d1 = m(h0, r1) &+ m(h1, r0) &+ m(h2, s4) &+ m(h3, s3) &+ m(h4, s2)
            var d2 = m(h0, r2) &+ m(h1, r1) &+ m(h2, r0) &+ m(h3, s4) &+ m(h4, s3)
            var d3 = m(h0, r3) &+ m(h1, r2) &+ m(h2, r1) &+ m(h3, r0) &+ m(h4, s4)
            var d4 = m(h0, r4) &+ m(h1, r3) &+ m(h2, r2) &+ m(h3, r1) &+ m(h4, r0)
            var c = d0 >> 26; h0 = UInt32(truncatingIfNeeded: d0) & mask
            d1 &+= c; c = d1 >> 26; h1 = UInt32(truncatingIfNeeded: d1) & mask
            d2 &+= c; c = d2 >> 26; h2 = UInt32(truncatingIfNeeded: d2) & mask
            d3 &+= c; c = d3 >> 26; h3 = UInt32(truncatingIfNeeded: d3) & mask
            d4 &+= c; c = d4 >> 26; h4 = UInt32(truncatingIfNeeded: d4) & mask
            h0 &+= UInt32(truncatingIfNeeded: c) &* 5
            let carry = h0 >> 26; h0 &= mask; h1 &+= carry
            offset += 16
        }

        // Fully carry h.
        var c = h1 >> 26; h1 &= mask
        h2 &+= c; c = h2 >> 26; h2 &= mask
        h3 &+= c; c = h3 >> 26; h3 &= mask
        h4 &+= c; c = h4 >> 26; h4 &= mask
        h0 &+= c &* 5; c = h0 >> 26; h0 &= mask
        h1 &+= c

        // h - p, chosen over h when it doesn't go below zero.
        var g0 = h0 &+ 5; c = g0 >> 26; g0 &= mask
        var g1 = h1 &+ c; c = g1 >> 26; g1 &= mask
        var g2 = h2 &+ c; c = g2 >> 26; g2 &= mask
        var g3 = h3 &+ c; c = g3 >> 26; g3 &= mask
        var g4 = h4 &+ c &- (1 << 26)
        var select = (g4 >> 31) &- 1
        g0 &= select; g1 &= select; g2 &= select; g3 &= select; g4 &= select
        select = ~select
        h0 = (h0 & select) | g0
        h1 = (h1 & select) | g1
        h2 = (h2 & select) | g2
        h3 = (h3 & select) | g3
        h4 = (h4 & select) | g4

        // h mod 2^128, plus s.
        let w0 = h0 | h1 << 26
        let w1 = h1 >> 6 | h2 << 20
        let w2 = h2 >> 12 | h3 << 14
        let w3 = h3 >> 18 | h4 << 8
        var f = UInt64(w0) &+ UInt64(word(key, 16))
        var out: [UInt8] = []
        func append(_ value: UInt64) {
            let v = UInt32(truncatingIfNeeded: value)
            out += [UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8), UInt8(truncatingIfNeeded: v >> 16), UInt8(truncatingIfNeeded: v >> 24)]
        }
        append(f)
        f = UInt64(w1) &+ UInt64(word(key, 20)) &+ (f >> 32); append(f)
        f = UInt64(w2) &+ UInt64(word(key, 24)) &+ (f >> 32); append(f)
        f = UInt64(w3) &+ UInt64(word(key, 28)) &+ (f >> 32); append(f)
        return out
    }
}
