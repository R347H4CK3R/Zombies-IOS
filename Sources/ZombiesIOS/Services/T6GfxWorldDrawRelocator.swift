import Foundation

struct T6RelocatedGfxWorldDraw: Sendable {
    let vertexCount: Int
    let indexCount: Int
    let vertexData0: Data
    let vertexData1: Data
    let indices: Data
    let vertexData0SerializedOffset: Int
    let vertexData1SerializedOffset: Int
    let indicesSerializedOffset: Int
}

enum T6GfxWorldDrawRelocator {
    static let gfxWorldSize = 0x404
    static let drawOffset = 0x18c

    enum RelocationError: LocalizedError, Equatable {
        case truncatedGfxWorld
        case precedingInlinePayload(field: String)
        case unsupportedPointer(field: String, pointer: T6ZonePointer)
        case invalidCount(field: String, value: UInt32)

        var errorDescription: String? {
            switch self {
            case .truncatedGfxWorld:
                return "T6 GfxWorld structure is truncated."
            case .precedingInlinePayload(let field):
                return "T6 GfxWorld field \(field) has an inline payload before GfxWorldDraw; full nested relocation is required."
            case .unsupportedPointer(let field, let pointer):
                return "T6 GfxWorld field \(field) uses unsupported pointer \(pointer); refusing to guess a serialized offset."
            case .invalidCount(let field, let value):
                return "T6 GfxWorld field \(field) has implausible size/count \(value)."
            }
        }
    }

    static func relocate(
        zoneData: Data,
        gfxWorldSerializedOffset base: Int,
        tempBlockSize: UInt32
    ) throws -> T6RelocatedGfxWorldDraw {
        guard base >= 0, base + gfxWorldSize <= zoneData.count else {
            throw RelocationError.truncatedGfxWorld
        }

        // GfxWorld is serialized as one 0x404-byte raw structure, then pointer
        // payloads are emitted in generated loader order. Until the complete nested
        // walker is active, reject any preceding FOLLOWING payload rather than using
        // a heuristic buffer base. OFFSET/NULL pointers consume no new serialized bytes.
        try rejectUnsupportedPreDrawInlinePayloads(zoneData, base: base)

        let draw = base + drawOffset
        let reflectionProbeCount = be32(zoneData, draw + 0x00)
        let reflectionProbePointer = T6ZonePointer.decode(be32(zoneData, draw + 0x04))
        if reflectionProbeCount > 0, reflectionProbePointer == .following {
            throw RelocationError.precedingInlinePayload(field: "draw.reflectionProbes")
        }

        let lightmapCount = be32(zoneData, draw + 0x0c)
        let lightmapPointer = T6ZonePointer.decode(be32(zoneData, draw + 0x10))
        if lightmapCount > 0, lightmapPointer == .following {
            throw RelocationError.precedingInlinePayload(field: "draw.lightmaps")
        }

        let vertexCount = be32(zoneData, draw + 0x1c)
        let vertexDataSize0 = be32(zoneData, draw + 0x20)
        let vertexDataPointer0 = T6ZonePointer.decode(be32(zoneData, draw + 0x24))
        let vertexDataSize1 = be32(zoneData, draw + 0x2c)
        let vertexDataPointer1 = T6ZonePointer.decode(be32(zoneData, draw + 0x30))
        let indexCount = be32(zoneData, draw + 0x38)
        let indexPointer = T6ZonePointer.decode(be32(zoneData, draw + 0x3c))

        try validateSize("vertexDataSize0", vertexDataSize0)
        try validateSize("vertexDataSize1", vertexDataSize1)
        try validateSize("indexCount", indexCount)

        guard vertexDataSize0 == 0 || vertexDataPointer0 == .following else {
            throw RelocationError.unsupportedPointer(field: "draw.vd0.data", pointer: vertexDataPointer0)
        }
        guard vertexDataSize1 == 0 || vertexDataPointer1 == .following else {
            throw RelocationError.unsupportedPointer(field: "draw.vd1.data", pointer: vertexDataPointer1)
        }
        guard indexCount == 0 || indexPointer == .following else {
            throw RelocationError.unsupportedPointer(field: "draw.indices", pointer: indexPointer)
        }

        var blockSizes = Array(repeating: UInt32.max, count: 8)
        blockSizes[0] = tempBlockSize
        var cursor = try T6ZoneStreamCursor(
            serializedData: zoneData,
            blockSizes: blockSizes,
            serializedOffset: base + gfxWorldSize
        )
        try cursor.seedBlockOffset(0, offset: gfxWorldSize)
        try cursor.pushBlock(0)
        defer { try? cursor.popBlock() }

        let vd0Offset = cursor.currentSerializedOffset
        let vd0 = vertexDataSize0 > 0
            ? try cursor.resolveFollowing(alignment: 128, length: Int(vertexDataSize0))
            : Data()
        let vd1Offset = cursor.currentSerializedOffset
        let vd1 = vertexDataSize1 > 0
            ? try cursor.resolveFollowing(alignment: 128, length: Int(vertexDataSize1))
            : Data()
        let indicesOffset = cursor.currentSerializedOffset
        let indexBytes = try multipliedSize(indexCount, by: 2, field: "indexCount")
        let indices = indexBytes > 0
            ? try cursor.resolveFollowing(alignment: 2, length: indexBytes)
            : Data()

        return T6RelocatedGfxWorldDraw(
            vertexCount: Int(vertexCount),
            indexCount: Int(indexCount),
            vertexData0: vd0,
            vertexData1: vd1,
            indices: indices,
            vertexData0SerializedOffset: vd0Offset,
            vertexData1SerializedOffset: vd1Offset,
            indicesSerializedOffset: indicesOffset
        )
    }

    private static func rejectUnsupportedPreDrawInlinePayloads(_ data: Data, base: Int) throws {
        let pointerFields: [(String, Int)] = [
            ("name", 0x000), ("baseName", 0x004),
            ("streamInfo.aabbTrees", 0x018), ("streamInfo.leafRefs", 0x020),
            ("skyBoxModel", 0x024), ("sunLight", 0x100),
            ("coronas", 0x110), ("shadowMapVolumes", 0x118),
            ("shadowMapVolumePlanes", 0x120), ("exposureVolumes", 0x128),
            ("exposureVolumePlanes", 0x130), ("worldFogVolumes", 0x138),
            ("worldFogVolumePlanes", 0x140), ("worldFogModifierVolumes", 0x148),
            ("worldFogModifierVolumePlanes", 0x150), ("lutVolumes", 0x158),
            ("lutVolumePlanes", 0x160), ("dpvsPlanes.planes", 0x178),
            ("dpvsPlanes.nodes", 0x17c), ("cells", 0x188)
        ]
        for (name, offset) in pointerFields {
            if T6ZonePointer.decode(be32(data, base + offset)) == .following {
                throw RelocationError.precedingInlinePayload(field: name)
            }
        }
    }

    private static func validateSize(_ field: String, _ value: UInt32) throws {
        guard value <= 0x3c00_0000 else { throw RelocationError.invalidCount(field: field, value: value) }
    }

    private static func multipliedSize(_ value: UInt32, by multiplier: Int, field: String) throws -> Int {
        let wide = UInt64(value) * UInt64(multiplier)
        guard wide <= UInt64(Int.max), wide <= 0x3c00_0000 else {
            throw RelocationError.invalidCount(field: field, value: value)
        }
        return Int(wide)
    }

    private static func be32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
    }
}
