import Foundation

enum T6ZonePointer: Equatable, Sendable {
    case null
    case following
    case insert
    case offset(block: Int, offset: Int)

    static func decode(_ raw: UInt32) -> T6ZonePointer {
        if raw == 0 { return .null }
        if raw == 0xFFFF_FFFF { return .following }
        if raw == 0xFFFF_FFFE { return .insert }

        let value = raw &- 1
        let block = Int((value >> 29) & 0x7)
        let offset = Int(value & 0x1FFF_FFFF)
        return .offset(block: block, offset: offset)
    }
}

struct T6ZoneStreamCursor: Sendable {
    enum CursorError: LocalizedError, Equatable {
        case invalidBlockCount(Int)
        case invalidBlock(Int)
        case emptyBlockStack
        case delayedBlockUnsupported(Int)
        case blockOverflow(block: Int, requestedEnd: Int, size: Int)
        case serializedDataTruncated(offset: Int, length: Int, size: Int)

        var errorDescription: String? {
            switch self {
            case .invalidBlockCount(let value):
                return "T6 zone expected 8 XFile blocks, found \(value)."
            case .invalidBlock(let value):
                return "T6 zone block \(value) is invalid."
            case .emptyBlockStack:
                return "T6 zone stream block stack is empty."
            case .delayedBlockUnsupported(let block):
                return "T6 delayed XFile block \(block) is not supported by this converter."
            case .blockOverflow(let block, let end, let size):
                return "T6 block \(block) overflow: requested \(end) bytes, block size is \(size)."
            case .serializedDataTruncated(let offset, let length, let size):
                return "T6 serialized data is truncated at \(offset) for \(length) bytes (size \(size))."
            }
        }
    }

    private enum BlockKind: Sendable {
        case temp
        case runtime
        case delayed
        case normal
    }

    private let serializedData: Data
    private let blockSizes: [Int]
    private var blockOffsets: [Int]
    private var stack: [Int] = []
    private var tempSavedOffsets: [Int] = []
    private(set) var currentSerializedOffset: Int

    init(serializedData: Data, blockSizes: [UInt32], serializedOffset: Int) throws {
        guard blockSizes.count == 8 else { throw CursorError.invalidBlockCount(blockSizes.count) }
        self.serializedData = serializedData
        self.blockSizes = blockSizes.map(Int.init)
        self.blockOffsets = Array(repeating: 0, count: 8)
        self.currentSerializedOffset = serializedOffset
        guard serializedOffset >= 0, serializedOffset <= serializedData.count else {
            throw CursorError.serializedDataTruncated(
                offset: serializedOffset,
                length: 0,
                size: serializedData.count
            )
        }
    }

    mutating func pushBlock(_ block: Int) throws {
        guard block >= 0, block < blockSizes.count else { throw CursorError.invalidBlock(block) }
        stack.append(block)
        if kind(for: block) == .temp {
            tempSavedOffsets.append(blockOffsets[block])
        }
    }

    @discardableResult
    mutating func popBlock() throws -> Int {
        guard let block = stack.popLast() else { throw CursorError.emptyBlockStack }
        if kind(for: block) == .temp {
            guard let saved = tempSavedOffsets.popLast() else { throw CursorError.emptyBlockStack }
            blockOffsets[block] = saved
        }
        return block
    }

    func blockOffset(_ block: Int) -> Int {
        guard block >= 0, block < blockOffsets.count else { return -1 }
        return blockOffsets[block]
    }

    func currentBlock() -> Int? {
        stack.last
    }

    mutating func resolveFollowing(alignment: Int, length: Int) throws -> Data {
        guard let block = stack.last else { throw CursorError.emptyBlockStack }
        guard length >= 0 else {
            throw CursorError.blockOverflow(block: block, requestedEnd: length, size: blockSizes[block])
        }

        let aligned = Self.align(blockOffsets[block], to: max(1, alignment))
        let end = aligned + length
        guard end <= blockSizes[block] else {
            throw CursorError.blockOverflow(block: block, requestedEnd: end, size: blockSizes[block])
        }

        blockOffsets[block] = end
        switch kind(for: block) {
        case .runtime:
            return Data()
        case .delayed:
            throw CursorError.delayedBlockUnsupported(block)
        case .temp, .normal:
            let dataEnd = currentSerializedOffset + length
            guard currentSerializedOffset >= 0, dataEnd <= serializedData.count else {
                throw CursorError.serializedDataTruncated(
                    offset: currentSerializedOffset,
                    length: length,
                    size: serializedData.count
                )
            }
            let result = serializedData.subdata(in: currentSerializedOffset..<dataEnd)
            currentSerializedOffset = dataEnd
            return result
        }
    }

    mutating func skipSerialized(_ length: Int) throws {
        let end = currentSerializedOffset + length
        guard length >= 0, end <= serializedData.count else {
            throw CursorError.serializedDataTruncated(
                offset: currentSerializedOffset,
                length: length,
                size: serializedData.count
            )
        }
        currentSerializedOffset = end
    }

    private func kind(for block: Int) -> BlockKind {
        switch block {
        case 0: return .temp
        case 1, 2: return .runtime
        case 3, 4: return .delayed
        case 5, 6, 7: return .normal
        default: return .normal
        }
    }

    private static func align(_ value: Int, to alignment: Int) -> Int {
        guard alignment > 1 else { return value }
        let remainder = value % alignment
        return remainder == 0 ? value : value + (alignment - remainder)
    }
}
