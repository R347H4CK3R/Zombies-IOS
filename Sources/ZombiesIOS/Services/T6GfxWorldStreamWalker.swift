import Foundation

struct T6GfxWorldWalkResult: Sendable {
    let vertexCount: Int
    let indexCount: Int
    let vertexData0: Data
    let vertexData1: Data
    let indices: Data
    let vertexData0SerializedOffset: Int
    let vertexData1SerializedOffset: Int
    let indicesSerializedOffset: Int
}

enum T6GfxWorldStreamWalker {
    enum WalkError: LocalizedError, Equatable {
        case truncatedStructure(String)
        case invalidCount(field: String, value: UInt32)
        case missingFollowingData(field: String, pointer: T6ZonePointer)
        case inlineAssetUnsupported(field: String)
        case recursiveCellUnsupported

        var errorDescription: String? {
            switch self {
            case .truncatedStructure(let field):
                return "T6 GfxWorld structure is truncated while reading \(field)."
            case .invalidCount(let field, let value):
                return "T6 GfxWorld field \(field) has implausible count \(value)."
            case .missingFollowingData(let field, let pointer):
                return "T6 GfxWorld field \(field) needs inline bytes but pointer is \(pointer)."
            case .inlineAssetUnsupported(let field):
                return "T6 GfxWorld field \(field) contains an inline asset that requires the typed asset loader."
            case .recursiveCellUnsupported:
                return "T6 GfxPortal contains an inline reusable GfxCell; recursive cell relocation is not yet safe."
            }
        }
    }

    private static let gfxWorldSize = 0x404
    private static let gfxLightSize = 352
    private static let gfxLightDefPointerOffset = 348
    private static let drawOffset = 0x18c
    private static let maximumCount: UInt32 = 16_000_000

    static func walk(
        zoneData: Data,
        gfxWorldSerializedOffset base: Int,
        tempBlockSize: UInt32
    ) throws -> T6GfxWorldWalkResult {
        guard base >= 0, base + gfxWorldSize <= zoneData.count else {
            throw WalkError.truncatedStructure("GfxWorld")
        }

        let raw = zoneData.subdata(in: base..<(base + gfxWorldSize))
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

        try consumeString(pointerAt: 0x000, field: "name", raw: raw, cursor: &cursor)
        try consumeString(pointerAt: 0x004, field: "baseName", raw: raw, cursor: &cursor)

        _ = try consumeArray(
            count: u32(raw, 0x014), pointer: pointer(raw, 0x018), elementSize: 48,
            alignment: 16, field: "streamInfo.aabbTrees", cursor: &cursor
        )
        _ = try consumeArray(
            count: u32(raw, 0x01c), pointer: pointer(raw, 0x020), elementSize: 4,
            alignment: 4, field: "streamInfo.leafRefs", cursor: &cursor
        )
        try consumeString(pointerAt: 0x024, field: "skyBoxModel", raw: raw, cursor: &cursor)

        let sunLight = pointer(raw, 0x100)
        if sunLight == .following {
            let light = try cursor.resolveFollowing(alignment: 16, length: gfxLightSize)
            let lightDef = pointer(light, gfxLightDefPointerOffset)
            if lightDef == .following || lightDef == .insert {
                throw WalkError.inlineAssetUnsupported(field: "sunLight.def")
            }
        }

        _ = try consumeArray(count: u32(raw, 0x10c), pointer: pointer(raw, 0x110), elementSize: 32, alignment: 4, field: "coronas", cursor: &cursor)
        _ = try consumeArray(count: u32(raw, 0x114), pointer: pointer(raw, 0x118), elementSize: 16, alignment: 4, field: "shadowMapVolumes", cursor: &cursor)
        _ = try consumeArray(count: u32(raw, 0x11c), pointer: pointer(raw, 0x120), elementSize: 16, alignment: 4, field: "shadowMapVolumePlanes", cursor: &cursor)
        _ = try consumeArray(count: u32(raw, 0x124), pointer: pointer(raw, 0x128), elementSize: 24, alignment: 4, field: "exposureVolumes", cursor: &cursor)
        _ = try consumeArray(count: u32(raw, 0x12c), pointer: pointer(raw, 0x130), elementSize: 16, alignment: 4, field: "exposureVolumePlanes", cursor: &cursor)
        _ = try consumeArray(count: u32(raw, 0x134), pointer: pointer(raw, 0x138), elementSize: 100, alignment: 4, field: "worldFogVolumes", cursor: &cursor)
        _ = try consumeArray(count: u32(raw, 0x13c), pointer: pointer(raw, 0x140), elementSize: 16, alignment: 4, field: "worldFogVolumePlanes", cursor: &cursor)
        _ = try consumeArray(count: u32(raw, 0x144), pointer: pointer(raw, 0x148), elementSize: 48, alignment: 4, field: "worldFogModifierVolumes", cursor: &cursor)
        _ = try consumeArray(count: u32(raw, 0x14c), pointer: pointer(raw, 0x150), elementSize: 16, alignment: 4, field: "worldFogModifierVolumePlanes", cursor: &cursor)
        _ = try consumeArray(count: u32(raw, 0x154), pointer: pointer(raw, 0x158), elementSize: 36, alignment: 4, field: "lutVolumes", cursor: &cursor)
        _ = try consumeArray(count: u32(raw, 0x15c), pointer: pointer(raw, 0x160), elementSize: 16, alignment: 4, field: "lutVolumePlanes", cursor: &cursor)

        let planeCount = u32(raw, 0x008)
        let nodeCount = u32(raw, 0x00c)
        _ = try consumeArray(count: planeCount, pointer: pointer(raw, 0x178), elementSize: 20, alignment: 4, field: "dpvsPlanes.planes", cursor: &cursor)
        _ = try consumeArray(count: nodeCount, pointer: pointer(raw, 0x17c), elementSize: 2, alignment: 2, field: "dpvsPlanes.nodes", cursor: &cursor)

        let cellCount = u32(raw, 0x174)
        let cells = try consumeArray(count: cellCount, pointer: pointer(raw, 0x188), elementSize: 48, alignment: 4, field: "cells", cursor: &cursor)
        if let cells {
            try walkCells(cells, count: Int(cellCount), cursor: &cursor)
        }

        return try walkDraw(raw: raw, cursor: &cursor)
    }

    private static func walkCells(_ cells: Data, count: Int, cursor: inout T6ZoneStreamCursor) throws {
        guard cells.count == count * 48 else { throw WalkError.truncatedStructure("cells") }
        for cellIndex in 0..<count {
            let base = cellIndex * 48
            let treeCount = u32(cells, base + 24)
            if let trees = try consumeArray(
                count: treeCount, pointer: pointer(cells, base + 28), elementSize: 40,
                alignment: 4, field: "cells[\(cellIndex)].aabbTree", cursor: &cursor
            ) {
                try walkAabbTrees(trees, count: Int(treeCount), cellIndex: cellIndex, cursor: &cursor)
            }

            let portalCount = u32(cells, base + 32)
            if let portals = try consumeArray(
                count: portalCount, pointer: pointer(cells, base + 36), elementSize: 92,
                alignment: 4, field: "cells[\(cellIndex)].portals", cursor: &cursor
            ) {
                try walkPortals(portals, count: Int(portalCount), cellIndex: cellIndex, cursor: &cursor)
            }

            let probeCount = UInt32(cells[base + 40])
            _ = try consumeArray(
                count: probeCount, pointer: pointer(cells, base + 44), elementSize: 1,
                alignment: 1, field: "cells[\(cellIndex)].reflectionProbes", cursor: &cursor
            )
        }
    }

    private static func walkAabbTrees(
        _ trees: Data,
        count: Int,
        cellIndex: Int,
        cursor: inout T6ZoneStreamCursor
    ) throws {
        guard trees.count == count * 40 else { throw WalkError.truncatedStructure("GfxAabbTree") }
        for treeIndex in 0..<count {
            let base = treeIndex * 40
            let modelIndexCount = UInt32(u16(trees, base + 30))
            _ = try consumeArray(
                count: modelIndexCount,
                pointer: pointer(trees, base + 32),
                elementSize: 2,
                alignment: 2,
                field: "cells[\(cellIndex)].aabbTree[\(treeIndex)].smodelIndexes",
                cursor: &cursor
            )
        }
    }

    private static func walkPortals(
        _ portals: Data,
        count: Int,
        cellIndex: Int,
        cursor: inout T6ZoneStreamCursor
    ) throws {
        guard portals.count == count * 92 else { throw WalkError.truncatedStructure("GfxPortal") }
        for portalIndex in 0..<count {
            let base = portalIndex * 92
            let cellPointer = pointer(portals, base + 32)
            if cellPointer == .following || cellPointer == .insert {
                throw WalkError.recursiveCellUnsupported
            }
            let vertexCount = UInt32(portals[base + 40])
            _ = try consumeArray(
                count: vertexCount,
                pointer: pointer(portals, base + 36),
                elementSize: 12,
                alignment: 4,
                field: "cells[\(cellIndex)].portals[\(portalIndex)].vertices",
                cursor: &cursor
            )
        }
    }

    private static func walkDraw(raw: Data, cursor: inout T6ZoneStreamCursor) throws -> T6GfxWorldWalkResult {
        let draw = drawOffset
        let probeCount = u32(raw, draw + 0x00)
        if let probes = try consumeArray(
            count: probeCount, pointer: pointer(raw, draw + 0x04), elementSize: 76,
            alignment: 4, field: "draw.reflectionProbes", cursor: &cursor
        ) {
            try walkReflectionProbes(probes, count: Int(probeCount), cursor: &cursor)
        }

        let lightmapCount = u32(raw, draw + 0x0c)
        if let lightmaps = try consumeArray(
            count: lightmapCount, pointer: pointer(raw, draw + 0x10), elementSize: 8,
            alignment: 4, field: "draw.lightmaps", cursor: &cursor
        ) {
            for i in 0..<Int(lightmapCount) {
                for imageField in 0..<2 {
                    let image = pointer(lightmaps, i * 8 + imageField * 4)
                    if image == .following || image == .insert {
                        throw WalkError.inlineAssetUnsupported(field: "draw.lightmaps[\(i)].image[\(imageField)]")
                    }
                }
            }
        }

        let vertexCount = u32(raw, draw + 0x1c)
        let vd0Size = u32(raw, draw + 0x20)
        let vd0Pointer = pointer(raw, draw + 0x24)
        let vd1Size = u32(raw, draw + 0x2c)
        let vd1Pointer = pointer(raw, draw + 0x30)
        let indexCount = u32(raw, draw + 0x38)
        let indexPointer = pointer(raw, draw + 0x3c)
        try validateCount("draw.vertexCount", vertexCount)
        try validateCount("draw.vertexDataSize0", vd0Size)
        try validateCount("draw.vertexDataSize1", vd1Size)
        try validateCount("draw.indexCount", indexCount)

        let vd0Offset = cursor.currentSerializedOffset
        let vd0 = try requireFollowingBytes(count: vd0Size, pointer: vd0Pointer, alignment: 128, field: "draw.vd0.data", cursor: &cursor)
        let vd1Offset = cursor.currentSerializedOffset
        let vd1 = try requireFollowingBytes(count: vd1Size, pointer: vd1Pointer, alignment: 128, field: "draw.vd1.data", cursor: &cursor)
        let indexOffset = cursor.currentSerializedOffset
        let indexBytes64 = UInt64(indexCount) * 2
        guard indexBytes64 <= UInt64(UInt32.max) else { throw WalkError.invalidCount(field: "draw.indexCount", value: indexCount) }
        let indices = try requireFollowingBytes(count: UInt32(indexBytes64), pointer: indexPointer, alignment: 2, field: "draw.indices", cursor: &cursor)

        return T6GfxWorldWalkResult(
            vertexCount: Int(vertexCount),
            indexCount: Int(indexCount),
            vertexData0: vd0,
            vertexData1: vd1,
            indices: indices,
            vertexData0SerializedOffset: vd0Offset,
            vertexData1SerializedOffset: vd1Offset,
            indicesSerializedOffset: indexOffset
        )
    }

    private static func walkReflectionProbes(_ probes: Data, count: Int, cursor: inout T6ZoneStreamCursor) throws {
        guard probes.count == count * 76 else { throw WalkError.truncatedStructure("GfxReflectionProbe") }
        for i in 0..<count {
            let base = i * 76
            let image = pointer(probes, base + 60)
            if image == .following || image == .insert {
                throw WalkError.inlineAssetUnsupported(field: "draw.reflectionProbes[\(i)].reflectionImage")
            }
            let volumeCount = u32(probes, base + 68)
            _ = try consumeArray(
                count: volumeCount,
                pointer: pointer(probes, base + 64),
                elementSize: 96,
                alignment: 4,
                field: "draw.reflectionProbes[\(i)].probeVolumes",
                cursor: &cursor
            )
        }
    }

    private static func consumeString(
        pointerAt offset: Int,
        field: String,
        raw: Data,
        cursor: inout T6ZoneStreamCursor
    ) throws {
        let value = pointer(raw, offset)
        if value == .following {
            _ = try cursor.resolveNullTerminatedString()
        }
    }

    private static func consumeArray(
        count: UInt32,
        pointer: T6ZonePointer,
        elementSize: Int,
        alignment: Int,
        field: String,
        cursor: inout T6ZoneStreamCursor
    ) throws -> Data? {
        try validateCount(field, count)
        if count == 0 { return nil }
        let bytes64 = UInt64(count) * UInt64(elementSize)
        guard bytes64 <= UInt64(Int.max), bytes64 <= 0x3c00_0000 else {
            throw WalkError.invalidCount(field: field, value: count)
        }
        switch pointer {
        case .following, .insert:
            return try cursor.resolveFollowing(alignment: alignment, length: Int(bytes64))
        case .null:
            throw WalkError.missingFollowingData(field: field, pointer: pointer)
        case .offset:
            return nil
        }
    }

    private static func requireFollowingBytes(
        count: UInt32,
        pointer: T6ZonePointer,
        alignment: Int,
        field: String,
        cursor: inout T6ZoneStreamCursor
    ) throws -> Data {
        if count == 0 { return Data() }
        guard pointer == .following || pointer == .insert else {
            throw WalkError.missingFollowingData(field: field, pointer: pointer)
        }
        return try cursor.resolveFollowing(alignment: alignment, length: Int(count))
    }

    private static func validateCount(_ field: String, _ value: UInt32) throws {
        guard value <= maximumCount else { throw WalkError.invalidCount(field: field, value: value) }
    }

    private static func pointer(_ data: Data, _ offset: Int) -> T6ZonePointer {
        T6ZonePointer.decode(u32(data, offset))
    }

    private static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        return (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return (UInt32(data[offset]) << 24)
            | (UInt32(data[offset + 1]) << 16)
            | (UInt32(data[offset + 2]) << 8)
            | UInt32(data[offset + 3])
    }
}
