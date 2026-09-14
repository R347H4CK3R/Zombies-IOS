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

    static func relocate(
        zoneData: Data,
        gfxWorldSerializedOffset base: Int,
        tempBlockSize: UInt32
    ) throws -> T6RelocatedGfxWorldDraw {
        let walked = try T6GfxWorldStreamWalker.walk(
            zoneData: zoneData,
            gfxWorldSerializedOffset: base,
            tempBlockSize: tempBlockSize
        )
        return T6RelocatedGfxWorldDraw(
            vertexCount: walked.vertexCount,
            indexCount: walked.indexCount,
            vertexData0: walked.vertexData0,
            vertexData1: walked.vertexData1,
            indices: walked.indices,
            vertexData0SerializedOffset: walked.vertexData0SerializedOffset,
            vertexData1SerializedOffset: walked.vertexData1SerializedOffset,
            indicesSerializedOffset: walked.indicesSerializedOffset
        )
    }
}
