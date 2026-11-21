// AES-GCM: the AES block cipher (FIPS 197) in Galois/Counter Mode (NIST SP 800-38D), Apple's
// `AES.GCM`. Pure Swift: the counter mode encrypts with the key's expanded schedule, GHASH
// multiplies in GF(2^128) bit by bit over two 64-bit halves. Keys of 128, 192 and 256 bits, a
// 12-byte nonce by default (longer ones are hashed into the first counter, as the standard
// says), and a 16-byte tag. The sealed boxes match Apple's byte for byte (the tests check the
// standard's vectors), so data sealed here opens on an iPhone and the other way round.

/// The Advanced Encryption Standard.
public enum AES {
    /// AES in Galois/Counter Mode, an authenticated cipher.
    public enum GCM {
        /// A value used once per message under a key: 12 bytes, or more.
        public struct Nonce: ContiguousBytes, Sequence, Sendable, Hashable {
            let bytes: [UInt8]

            /// A random 12-byte nonce.
            public init() {
                var generator = SystemRandomNumberGenerator()
                bytes = (0..<12).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
            }

            /// A nonce from data of at least 12 bytes.
            public init<D: Sequence>(data: D) throws where D.Element == UInt8 {
                let bytes = Array(data)
                guard bytes.count >= 12 else { throw CryptoKitError.incorrectParameterSize }
                self.bytes = bytes
            }

            public func makeIterator() -> IndexingIterator<[UInt8]> { bytes.makeIterator() }

            /// Calls the closure with the nonce's bytes.
            public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) rethrows -> R {
                try bytes.withUnsafeBytes(body)
            }
        }

        /// A message sealed with AES-GCM: its nonce, ciphertext and 16-byte tag.
        public struct SealedBox: Sendable {
            public let nonce: Nonce
            let cipherBytes: [UInt8]
            let tagBytes: [UInt8]

            /// The encrypted message.
            public var ciphertext: Data { Data(cipherBytes) }
            /// The authentication tag.
            public var tag: Data { Data(tagBytes) }
            /// The nonce, the ciphertext and the tag, one after another; nil when the nonce
            /// isn't the standard 12 bytes, since the combined form can't say where it ends.
            public var combined: Data? {
                nonce.bytes.count == 12 ? Data(nonce.bytes + cipherBytes + tagBytes) : nil
            }

            /// A sealed box from its combined form: a 12-byte nonce, the ciphertext, the tag.
            public init<D: Sequence>(combined: D) throws where D.Element == UInt8 {
                let bytes = Array(combined)
                guard bytes.count >= 12 + 16 else { throw CryptoKitError.incorrectParameterSize }
                nonce = try Nonce(data: bytes[..<12])
                cipherBytes = Array(bytes[12..<(bytes.count - 16)])
                tagBytes = Array(bytes[(bytes.count - 16)...])
            }

            /// A sealed box from its parts.
            public init<C: Sequence, T: Sequence>(nonce: Nonce, ciphertext: C, tag: T) throws
            where C.Element == UInt8, T.Element == UInt8 {
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
            let cipher = try _AESCipher(key: key.bytes)
            let nonce = nonce ?? Nonce()
            let hashKey = _GHash.Block(cipher.encrypt(_GHash.Block.zero.bytes))
            let first = counterBlock(nonce: nonce.bytes, hashKey: hashKey)
            let ciphertext = counterMode(Array(message), cipher: cipher, from: increment(first))
            let tag = tag(ciphertext: ciphertext, authenticatedData: Array(authenticatedData),
                          cipher: cipher, hashKey: hashKey, first: first)
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
            let cipher = try _AESCipher(key: key.bytes)
            let hashKey = _GHash.Block(cipher.encrypt(_GHash.Block.zero.bytes))
            let first = counterBlock(nonce: sealedBox.nonce.bytes, hashKey: hashKey)
            let expected = tag(ciphertext: sealedBox.cipherBytes, authenticatedData: Array(authenticatedData),
                               cipher: cipher, hashKey: hashKey, first: first)
            guard _constantTimeEqual(expected, sealedBox.tagBytes) else { throw CryptoKitError.authenticationFailure }
            return Data(counterMode(sealedBox.cipherBytes, cipher: cipher, from: increment(first)))
        }

        /// The first counter block, J0: a 12-byte nonce followed by a 32-bit 1, or any other
        /// nonce hashed with its length.
        static func counterBlock(nonce: [UInt8], hashKey: _GHash.Block) -> [UInt8] {
            if nonce.count == 12 { return nonce + [0, 0, 0, 1] }
            var input = nonce
            input += [UInt8](repeating: 0, count: (16 - nonce.count % 16) % 16)
            input += [UInt8](repeating: 0, count: 8)
            input += _GHash.bigEndian(UInt64(nonce.count) * 8)
            return _GHash.hash(input, key: hashKey).bytes
        }

        /// The block with its last 32 bits counted up by one, wrapping.
        static func increment(_ block: [UInt8]) -> [UInt8] {
            var out = block
            var index = 15
            while index >= 12 {
                out[index] &+= 1
                if out[index] != 0 { break }
                index -= 1
            }
            return out
        }

        /// `data` XORed with the encrypted counter blocks from `counter` on.
        static func counterMode(_ data: [UInt8], cipher: _AESCipher, from counter: [UInt8]) -> [UInt8] {
            var out = data
            var counter = counter
            var offset = 0
            while offset < data.count {
                let stream = cipher.encrypt(counter)
                for i in 0..<min(16, data.count - offset) { out[offset + i] ^= stream[i] }
                offset += 16
                counter = increment(counter)
            }
            return out
        }

        /// The tag: GHASH over the authenticated data and the ciphertext, each padded to 16
        /// bytes, then their lengths in bits, XORed with the encrypted first counter block.
        static func tag(ciphertext: [UInt8], authenticatedData: [UInt8], cipher: _AESCipher,
                        hashKey: _GHash.Block, first: [UInt8]) -> [UInt8] {
            var input = authenticatedData
            input += [UInt8](repeating: 0, count: (16 - authenticatedData.count % 16) % 16)
            input += ciphertext
            input += [UInt8](repeating: 0, count: (16 - ciphertext.count % 16) % 16)
            input += _GHash.bigEndian(UInt64(authenticatedData.count) * 8)
            input += _GHash.bigEndian(UInt64(ciphertext.count) * 8)
            let hash = _GHash.hash(input, key: hashKey).bytes
            let mask = cipher.encrypt(first)
            return (0..<16).map { hash[$0] ^ mask[$0] }
        }
    }
}

/// GHASH, GCM's hash: blocks multiplied in GF(2^128) by the hash key.
enum _GHash {
    /// A 128-bit block as its big-endian halves.
    struct Block {
        var high: UInt64
        var low: UInt64

        static let zero = Block(high: 0, low: 0)

        init(high: UInt64, low: UInt64) {
            self.high = high
            self.low = low
        }

        init(_ bytes: [UInt8], at offset: Int = 0) {
            var high: UInt64 = 0, low: UInt64 = 0
            for i in 0..<8 {
                high = high << 8 | UInt64(bytes[offset + i])
                low = low << 8 | UInt64(bytes[offset + 8 + i])
            }
            self.init(high: high, low: low)
        }

        var bytes: [UInt8] { bigEndian(high) + bigEndian(low) }

        /// The product in GF(2^128), as SP 800-38D's algorithm 1: bit 0 is the first byte's top bit.
        func times(_ other: Block) -> Block {
            var result = Block.zero
            var v = other
            for i in 0..<128 {
                let bit = i < 64 ? (high >> UInt64(63 - i)) & 1 : (low >> UInt64(127 - i)) & 1
                if bit == 1 {
                    result.high ^= v.high
                    result.low ^= v.low
                }
                let carry = v.low & 1
                v.low = v.low >> 1 | v.high << 63
                v.high >>= 1
                if carry == 1 { v.high ^= 0xE100_0000_0000_0000 }
            }
            return result
        }
    }

    static func bigEndian(_ value: UInt64) -> [UInt8] {
        stride(from: 56, through: 0, by: -8).map { UInt8(truncatingIfNeeded: value >> UInt64($0)) }
    }

    /// The hash of whole 16-byte blocks.
    static func hash(_ input: [UInt8], key: Block) -> Block {
        var y = Block.zero
        var offset = 0
        while offset < input.count {
            let x = Block(input, at: offset)
            y = Block(high: y.high ^ x.high, low: y.low ^ x.low).times(key)
            offset += 16
        }
        return y
    }
}

/// The AES block cipher's encryption direction, which is all that counter mode needs.
struct _AESCipher {
    private let roundKeys: [UInt8]
    private let rounds: Int

    init(key: [UInt8]) throws {
        let words: Int
        switch key.count {
        case 16: words = 4
        case 24: words = 6
        case 32: words = 8
        default: throw CryptoKitError.incorrectKeySize
        }
        rounds = words + 6
        // The key schedule (FIPS 197 5.2), four bytes to a word.
        var schedule = key
        let total = 4 * (rounds + 1)
        var rcon: UInt8 = 1
        for i in words..<total {
            var temp = Array(schedule[(i - 1) * 4..<i * 4])
            if i % words == 0 {
                temp = [Self.sbox[Int(temp[1])] ^ rcon, Self.sbox[Int(temp[2])], Self.sbox[Int(temp[3])], Self.sbox[Int(temp[0])]]
                rcon = Self.double(rcon)
            } else if words > 6 && i % words == 4 {
                temp = temp.map { Self.sbox[Int($0)] }
            }
            for j in 0..<4 { schedule.append(schedule[(i - words) * 4 + j] ^ temp[j]) }
        }
        roundKeys = schedule
    }

    /// Doubling in AES's field, GF(2^8) modulo x^8 + x^4 + x^3 + x + 1.
    private static func double(_ value: UInt8) -> UInt8 {
        value & 0x80 == 0 ? value << 1 : (value << 1) ^ 0x1B
    }

    /// Encrypts one 16-byte block (FIPS 197 5.1), the state held column by column.
    func encrypt(_ block: [UInt8]) -> [UInt8] {
        var state = block
        for i in 0..<16 { state[i] ^= roundKeys[i] }
        for round in 1...rounds {
            // SubBytes and ShiftRows: row r moves left by r columns.
            var shifted = [UInt8](repeating: 0, count: 16)
            for column in 0..<4 {
                for row in 0..<4 {
                    shifted[column * 4 + row] = Self.sbox[Int(state[((column + row) % 4) * 4 + row])]
                }
            }
            state = shifted
            if round != rounds {
                // MixColumns.
                for column in 0..<4 {
                    let a0 = state[column * 4], a1 = state[column * 4 + 1]
                    let a2 = state[column * 4 + 2], a3 = state[column * 4 + 3]
                    let all = a0 ^ a1 ^ a2 ^ a3
                    state[column * 4] = a0 ^ all ^ Self.double(a0 ^ a1)
                    state[column * 4 + 1] = a1 ^ all ^ Self.double(a1 ^ a2)
                    state[column * 4 + 2] = a2 ^ all ^ Self.double(a2 ^ a3)
                    state[column * 4 + 3] = a3 ^ all ^ Self.double(a3 ^ a0)
                }
            }
            for i in 0..<16 { state[i] ^= roundKeys[round * 16 + i] }
        }
        return state
    }

    private static let sbox: [UInt8] = [
        0x63, 0x7C, 0x77, 0x7B, 0xF2, 0x6B, 0x6F, 0xC5, 0x30, 0x01, 0x67, 0x2B, 0xFE, 0xD7, 0xAB, 0x76,
        0xCA, 0x82, 0xC9, 0x7D, 0xFA, 0x59, 0x47, 0xF0, 0xAD, 0xD4, 0xA2, 0xAF, 0x9C, 0xA4, 0x72, 0xC0,
        0xB7, 0xFD, 0x93, 0x26, 0x36, 0x3F, 0xF7, 0xCC, 0x34, 0xA5, 0xE5, 0xF1, 0x71, 0xD8, 0x31, 0x15,
        0x04, 0xC7, 0x23, 0xC3, 0x18, 0x96, 0x05, 0x9A, 0x07, 0x12, 0x80, 0xE2, 0xEB, 0x27, 0xB2, 0x75,
        0x09, 0x83, 0x2C, 0x1A, 0x1B, 0x6E, 0x5A, 0xA0, 0x52, 0x3B, 0xD6, 0xB3, 0x29, 0xE3, 0x2F, 0x84,
        0x53, 0xD1, 0x00, 0xED, 0x20, 0xFC, 0xB1, 0x5B, 0x6A, 0xCB, 0xBE, 0x39, 0x4A, 0x4C, 0x58, 0xCF,
        0xD0, 0xEF, 0xAA, 0xFB, 0x43, 0x4D, 0x33, 0x85, 0x45, 0xF9, 0x02, 0x7F, 0x50, 0x3C, 0x9F, 0xA8,
        0x51, 0xA3, 0x40, 0x8F, 0x92, 0x9D, 0x38, 0xF5, 0xBC, 0xB6, 0xDA, 0x21, 0x10, 0xFF, 0xF3, 0xD2,
        0xCD, 0x0C, 0x13, 0xEC, 0x5F, 0x97, 0x44, 0x17, 0xC4, 0xA7, 0x7E, 0x3D, 0x64, 0x5D, 0x19, 0x73,
        0x60, 0x81, 0x4F, 0xDC, 0x22, 0x2A, 0x90, 0x88, 0x46, 0xEE, 0xB8, 0x14, 0xDE, 0x5E, 0x0B, 0xDB,
        0xE0, 0x32, 0x3A, 0x0A, 0x49, 0x06, 0x24, 0x5C, 0xC2, 0xD3, 0xAC, 0x62, 0x91, 0x95, 0xE4, 0x79,
        0xE7, 0xC8, 0x37, 0x6D, 0x8D, 0xD5, 0x4E, 0xA9, 0x6C, 0x56, 0xF4, 0xEA, 0x65, 0x7A, 0xAE, 0x08,
        0xBA, 0x78, 0x25, 0x2E, 0x1C, 0xA6, 0xB4, 0xC6, 0xE8, 0xDD, 0x74, 0x1F, 0x4B, 0xBD, 0x8B, 0x8A,
        0x70, 0x3E, 0xB5, 0x66, 0x48, 0x03, 0xF6, 0x0E, 0x61, 0x35, 0x57, 0xB9, 0x86, 0xC1, 0x1D, 0x9E,
        0xE1, 0xF8, 0x98, 0x11, 0x69, 0xD9, 0x8E, 0x94, 0x9B, 0x1E, 0x87, 0xE9, 0xCE, 0x55, 0x28, 0xDF,
        0x8C, 0xA1, 0x89, 0x0D, 0xBF, 0xE6, 0x42, 0x68, 0x41, 0x99, 0x2D, 0x0F, 0xB0, 0x54, 0xBB, 0x16,
    ]
}
