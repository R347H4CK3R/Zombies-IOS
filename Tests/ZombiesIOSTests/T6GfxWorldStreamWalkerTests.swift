import XCTest
@testable import ZombiesIOS

final class T6GfxWorldStreamWalkerTests: XCTestCase {
    func testWorldFogVolumeUsesVerified100ByteSerializedLayout() throws {
        let gfxWorldSize = 0x404
        let drawOffset = 0x18c
        let fogVolumeSize = 100
        let vd0 = Data([0xA1, 0xA2, 0xA3, 0xA4])
        let vd1 = Data([0xB1, 0xB2, 0xB3, 0xB4])
        let indices = Data([0x00, 0x00])

        var zone = Data(repeating: 0, count: gfxWorldSize)
        putBE32(1, into: &zone, at: 0x134) // worldFogVolumeCount
        putBE32(0xFFFF_FFFF, into: &zone, at: 0x138) // worldFogVolumes FOLLOWING

        putBE32(1, into: &zone, at: drawOffset + 0x1c) // vertexCount
        putBE32(UInt32(vd0.count), into: &zone, at: drawOffset + 0x20)
        putBE32(0xFFFF_FFFF, into: &zone, at: drawOffset + 0x24)
        putBE32(UInt32(vd1.count), into: &zone, at: drawOffset + 0x2c)
        putBE32(0xFFFF_FFFF, into: &zone, at: drawOffset + 0x30)
        putBE32(1, into: &zone, at: drawOffset + 0x38) // one UInt16 index
        putBE32(0xFFFF_FFFF, into: &zone, at: drawOffset + 0x3c)

        zone.append(Data(repeating: 0xCC, count: fogVolumeSize))
        zone.append(vd0)
        zone.append(vd1)
        zone.append(indices)

        let result = try T6GfxWorldStreamWalker.walk(
            zoneData: zone,
            gfxWorldSerializedOffset: 0,
            tempBlockSize: UInt32(zone.count + 1024)
        )

        XCTAssertEqual(result.vertexData0SerializedOffset, gfxWorldSize + fogVolumeSize)
        XCTAssertEqual(result.vertexData0, vd0)
        XCTAssertEqual(result.vertexData1, vd1)
        XCTAssertEqual(result.indices, indices)
    }

    private func putBE32(_ value: UInt32, into data: inout Data, at offset: Int) {
        data[offset] = UInt8((value >> 24) & 0xFF)
        data[offset + 1] = UInt8((value >> 16) & 0xFF)
        data[offset + 2] = UInt8((value >> 8) & 0xFF)
        data[offset + 3] = UInt8(value & 0xFF)
    }
}
