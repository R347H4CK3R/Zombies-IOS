import Foundation

struct T6ZonePointer: Hashable, Sendable, Codable {
    static let pointerBitCount = 32
    static let blockBitCount = 3
    static let blockShift = pointerBitCount - blockBitCount
    static let blockMask: UInt32 = 0xE000_0000
    static let offsetMask: UInt32 = 0x1FFF_FFFF

    let serializedValue: UInt32
    let blockIndex: Int
    let blockOffset: UInt32

    init?(serializedValue: UInt32) {
        guard serializedValue != 0 else { return nil }
        let encoded = serializedValue &- 1
        self.serializedValue = serializedValue
        self.blockIndex = Int((encoded & Self.blockMask) >> UInt32(Self.blockShift))
        self.blockOffset = encoded & Self.offsetMask
    }

    static func encode(blockIndex: Int, blockOffset: UInt32) -> UInt32? {
        guard (0..<8).contains(blockIndex), blockOffset <= offsetMask else { return nil }
        let encoded = (UInt32(blockIndex) << UInt32(blockShift)) | (blockOffset & offsetMask)
        guard encoded != UInt32.max else { return nil }
        return encoded &+ 1
    }
}

struct T6ZonePointerResolver: Sendable {
    enum ResolveError: LocalizedError, Equatable {
        case nullPointer
        case invalidBlock(Int)
        case offsetOutsideBlock(block: Int, offset: UInt32, size: UInt32)

        var errorDescription: String? {
            switch self {
            case .nullPointer:
                return "T6 zone pointer is null."
            case .invalidBlock(let block):
                return "T6 zone pointer references invalid XBlock \(block)."
            case .offsetOutsideBlock(let block, let offset, let size):
                return "T6 zone pointer offset \(offset) is outside XBlock \(block) size \(size)."
            }
        }
    }

    let blockSizes: [UInt32]

    init(blockSizes: [UInt32]) {
        self.blockSizes = blockSizes
    }

    func decode(_ serializedValue: UInt32) throws -> T6ZonePointer {
        guard let pointer = T6ZonePointer(serializedValue: serializedValue) else {
            throw ResolveError.nullPointer
        }
        guard pointer.blockIndex >= 0, pointer.blockIndex < blockSizes.count else {
            throw ResolveError.invalidBlock(pointer.blockIndex)
        }
        let size = blockSizes[pointer.blockIndex]
        guard pointer.blockOffset < size else {
            throw ResolveError.offsetOutsideBlock(block: pointer.blockIndex, offset: pointer.blockOffset, size: size)
        }
        return pointer
    }
}
