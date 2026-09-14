import XCTest
@testable import ZombiesIOS

final class T6GfxWorldDrawRelocatorTests: XCTestCase {
    func testRelocatesInlineVertexAndIndexPayloadsAfterRawGfxWorld() throws {
        let base = 40
        var zone = Data(repeating: 0, count: base + T6GfxWorldDrawRelocator.gfxWorldSize)
        let draw = base + T6GfxWorldDrawRelocator.drawOffset

        writeBE32(3, into: &zone, at: draw + 0x1c) // vertex count
        writeBE32(8, into: &zone, at: draw + 0x20)
        writeBE32(0xffff_ffff, into: &zone, at: draw + 0x24)
        writeBE32(12, into: &zone, at: draw + 0x2c)
        writeBE32(0xffff_ffff, into: &zone, at: draw + 0x30)
        writeBE32(6, into: &zone, at: draw + 0x38)
        writeBE32(0xffff_ffff, into: &zone, at: draw + 0x3c)

        let vd0 = Data([1,2,3,4,5,6,7,8])
        let vd1 = Data([9,10,11,12,13,14,15,16,17,18,19,20])
        let indices = Data([0,0, 0,1, 0,2, 0,2, 0,1, 0,0])
        zone.append(vd0)
        zone.append(vd1)
        zone.append(indices)

        let result = try T6GfxWorldDrawRelocator.relocate(
            zoneData: zone,
            gfxWorldSerializedOffset: base,
            tempBlockSize: UInt32(zone.count + 4096)
        )

        XCTAssertEqual(result.vertexCount, 3)
        XCTAssertEqual(result.indexCount, 6)
        XCTAssertEqual(result.vertexData0, vd0)
        XCTAssertEqual(result.vertexData1, vd1)
        XCTAssertEqual(result.indices, indices)
        XCTAssertEqual(result.vertexData0SerializedOffset, base + T6GfxWorldDrawRelocator.gfxWorldSize)
        XCTAssertEqual(result.vertexData1SerializedOffset, base + T6GfxWorldDrawRelocator.gfxWorldSize + vd0.count)
        XCTAssertEqual(result.indicesSerializedOffset, base + T6GfxWorldDrawRelocator.gfxWorldSize + vd0.count + vd1.count)
    }

    func testRejectsNonInlineVertexPayloadInsteadOfGuessing() throws {
        let base = 40
        var zone = Data(repeating: 0, count: base + T6GfxWorldDrawRelocator.gfxWorldSize + 32)
        let draw = base + T6GfxWorldDrawRelocator.drawOffset
        writeBE32(1, into: &zone, at: draw + 0x1c)
        writeBE32(4, into: &zone, at: draw + 0x20)
        writeBE32((5 << 29) + 0x20 + 1, into: &zone, at: draw + 0x24)
        XCTAssertThrowsError(try T6GfxWorldDrawRelocator.relocate(
            zoneData: zone,
            gfxWorldSerializedOffset: base,
            tempBlockSize: UInt32(zone.count + 4096)
        ))
    }

    private func writeBE32(_ value: UInt32, into data: inout Data, at offset: Int) {
        data[offset] = UInt8((value >> 24) & 0xff)
        data[offset + 1] = UInt8((value >> 16) & 0xff)
        data[offset + 2] = UInt8((value >> 8) & 0xff)
        data[offset + 3] = UInt8(value & 0xff)
    }
}
