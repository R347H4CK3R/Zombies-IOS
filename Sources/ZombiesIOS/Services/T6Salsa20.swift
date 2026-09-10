import Foundation
import CryptoKit

enum T6Salsa20 {
    static let pcKey = Data([
        0x64, 0x1D, 0x8A, 0x2F, 0xE3, 0x1D, 0x3A, 0xA6,
        0x36, 0x22, 0xBB, 0xC9, 0xCE, 0x85, 0x87, 0x22,
        0x9D, 0x42, 0xB0, 0xF8, 0xED, 0x9B, 0x92, 0x41,
        0x30, 0xBF, 0x88, 0xB6, 0x5E, 0xDC, 0x50, 0xBE,
    ])

    static let xenonKey = Data([
        0x0E, 0x50, 0xF4, 0x9F, 0x41, 0x23, 0x17, 0x09,
        0x60, 0x38, 0x66, 0x56, 0x22, 0xDD, 0x09, 0x13,
        0x32, 0xA2, 0x09, 0xBA, 0x0A, 0x05, 0xA0, 0x0E,
        0x13, 0x77, 0xCE, 0xDB, 0x0A, 0x3C, 0xB1, 0xD3,
    ])

    static func crypt(_ input: Data, key: Data, iv: Data) -> Data? {
        guard key.count == 32, iv.count == 8 else { return nil }

        let keyBytes = [UInt8](key)
        let ivBytes = [UInt8](iv)
        var output = Data(count: input.count)

        var blockCounter: UInt64 = 0
        var offset = 0
        let inputBytes = [UInt8](input)

        while offset < inputBytes.count {
            let stream = keystreamBlock(key: keyBytes, iv: ivBytes, counter: blockCounter)
            let count = min(64, inputBytes.count - offset)
            output.withUnsafeMutableBytes { raw in
                let out = raw.bindMemory(to: UInt8.self)
                for i in 0..<count {
                    out[offset + i] = inputBytes[offset + i] ^ stream[i]
                }
            }
            offset += count
            blockCounter &+= 1
        }

        return output
    }

    static func sha1(_ data: Data) -> Data {
        Data(Insecure.SHA1.hash(data: data))
    }

    private static func keystreamBlock(key: [UInt8], iv: [UInt8], counter: UInt64) -> [UInt8] {
        let sigma = Array("expand 32-byte k".utf8)
        var state = [UInt32](repeating: 0, count: 16)

        state[0] = u32le(sigma, 0)
        state[5] = u32le(sigma, 4)
        state[10] = u32le(sigma, 8)
        state[15] = u32le(sigma, 12)

        state[1] = u32le(key, 0)
        state[2] = u32le(key, 4)
        state[3] = u32le(key, 8)
        state[4] = u32le(key, 12)
        state[11] = u32le(key, 16)
        state[12] = u32le(key, 20)
        state[13] = u32le(key, 24)
        state[14] = u32le(key, 28)

        state[6] = u32le(iv, 0)
        state[7] = u32le(iv, 4)
        state[8] = UInt32(truncatingIfNeeded: counter)
        state[9] = UInt32(truncatingIfNeeded: counter >> 32)

        var x = state
        for _ in 0..<10 {
            x[4] ^= rotl(x[0] &+ x[12], 7)
            x[8] ^= rotl(x[4] &+ x[0], 9)
            x[12] ^= rotl(x[8] &+ x[4], 13)
            x[0] ^= rotl(x[12] &+ x[8], 18)

            x[9] ^= rotl(x[5] &+ x[1], 7)
            x[13] ^= rotl(x[9] &+ x[5], 9)
            x[1] ^= rotl(x[13] &+ x[9], 13)
            x[5] ^= rotl(x[1] &+ x[13], 18)

            x[14] ^= rotl(x[10] &+ x[6], 7)
            x[2] ^= rotl(x[14] &+ x[10], 9)
            x[6] ^= rotl(x[2] &+ x[14], 13)
            x[10] ^= rotl(x[6] &+ x[2], 18)

            x[3] ^= rotl(x[15] &+ x[11], 7)
            x[7] ^= rotl(x[3] &+ x[15], 9)
            x[11] ^= rotl(x[7] &+ x[3], 13)
            x[15] ^= rotl(x[11] &+ x[7], 18)

            x[1] ^= rotl(x[0] &+ x[3], 7)
            x[2] ^= rotl(x[1] &+ x[0], 9)
            x[3] ^= rotl(x[2] &+ x[1], 13)
            x[0] ^= rotl(x[3] &+ x[2], 18)

            x[6] ^= rotl(x[5] &+ x[4], 7)
            x[7] ^= rotl(x[6] &+ x[5], 9)
            x[4] ^= rotl(x[7] &+ x[6], 13)
            x[5] ^= rotl(x[4] &+ x[7], 18)

            x[11] ^= rotl(x[10] &+ x[9], 7)
            x[8] ^= rotl(x[11] &+ x[10], 9)
            x[9] ^= rotl(x[8] &+ x[11], 13)
            x[10] ^= rotl(x[9] &+ x[8], 18)

            x[12] ^= rotl(x[15] &+ x[14], 7)
            x[13] ^= rotl(x[12] &+ x[15], 9)
            x[14] ^= rotl(x[13] &+ x[12], 13)
            x[15] ^= rotl(x[14] &+ x[13], 18)
        }

        var out = [UInt8](repeating: 0, count: 64)
        for i in 0..<16 {
            putU32le(x[i] &+ state[i], into: &out, at: i * 4)
        }
        return out
    }

    private static func rotl(_ v: UInt32, _ n: UInt32) -> UInt32 {
        (v << n) | (v >> (32 - n))
    }

    private static func u32le(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset]) |
            (UInt32(bytes[offset + 1]) << 8) |
            (UInt32(bytes[offset + 2]) << 16) |
            (UInt32(bytes[offset + 3]) << 24)
    }

    private static func putU32le(_ value: UInt32, into bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8(truncatingIfNeeded: value)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        bytes[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
        bytes[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }
}

struct T6FastFileHashChain {
    private static let blockHashes = 200
    private static let streamCount = 4
    private static let sha1Size = 20
    private static let ivSize = 8

    private var storage: [UInt8]
    private var blockIndex = [Int](repeating: 0, count: streamCount)

    init?(zoneName: String) {
        let name = Array(zoneName.prefix(31).utf8)
        guard !name.isEmpty else { return nil }

        storage = [UInt8](repeating: 0, count: Self.blockHashes * Self.streamCount * Self.sha1Size)
        var nameOffset = 0
        var i = 0
        while i < storage.count {
            let value = name[nameOffset]
            storage[i] = value
            storage[i + 1] = value
            storage[i + 2] = value
            storage[i + 3] = value
            i += 4
            nameOffset = (nameOffset + 1) % name.count
        }
    }

    mutating func iv(for stream: Int) -> Data {
        let offset = slot(stream: stream, block: blockIndex[stream])
        return Data(storage[offset..<(offset + Self.ivSize)])
    }

    mutating func advance(stream: Int, decryptedChunk: Data) {
        let digest = [UInt8](T6Salsa20.sha1(decryptedChunk))
        blockIndex[stream] = (blockIndex[stream] + 1) % Self.blockHashes
        let offset = slot(stream: stream, block: blockIndex[stream])
        for i in 0..<Self.sha1Size {
            storage[offset + i] ^= digest[i]
        }
    }

    private func slot(stream: Int, block: Int) -> Int {
        (block * Self.streamCount + stream) * Self.sha1Size
    }
}
