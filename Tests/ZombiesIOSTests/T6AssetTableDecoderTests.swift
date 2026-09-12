import XCTest
@testable import ZombiesIOS

final class T6AssetTableDecoderTests: XCTestCase {
    func testDecodesDeclaredAssetTableIntoStableTypedRecords() throws {
        var payload = Data(repeating: 0, count: 0x80)
        let contentOffset = 0x28
        putBE32(0, at: contentOffset, in: &payload)
        putBE32(0, at: contentOffset + 8, in: &payload)
        putBE32(4, at: contentOffset + 16, in: &payload)

        let tableOffset = contentOffset + 24
        let entries: [(UInt32, UInt32)] = [
            (17, 0x1000),
            (6, 0x2000),
            (8, 0x3000),
            (5, 0x4000)
        ]
        for (index, entry) in entries.enumerated() {
            putBE32(entry.0, at: tableOffset + index * 8, in: &payload)
            putBE32(entry.1, at: tableOffset + index * 8 + 4, in: &payload)
        }

        let zone = try T6AssetTableDecoder().decode(zoneName: "zm_transit", payload: payload)

        XCTAssertEqual(zone.assetTableOffset, tableOffset)
        XCTAssertEqual(zone.records.count, 4)
        XCTAssertEqual(zone.gfxWorlds.count, 1)
        XCTAssertEqual(zone.materials.count, 1)
        XCTAssertEqual(zone.images.count, 1)
        XCTAssertEqual(zone.xModels.count, 1)
        XCTAssertEqual(zone.gfxWorlds[0].record.rawPointer, 0x1000)
        XCTAssertEqual(zone.materials[0].record.id.zoneName, "zm_transit")
        XCTAssertEqual(zone.images[0].record.id.assetIndex, 2)
    }

    func testUnknownKnownRangeTypeIsRetainedInsteadOfDropped() throws {
        var payload = Data(repeating: 0, count: 0x80)
        let contentOffset = 0x28
        putBE32(0, at: contentOffset, in: &payload)
        putBE32(0, at: contentOffset + 8, in: &payload)
        putBE32(1, at: contentOffset + 16, in: &payload)
        let tableOffset = contentOffset + 24
        putBE32(59, at: tableOffset, in: &payload)
        putBE32(0x1234, at: tableOffset + 4, in: &payload)

        let zone = try T6AssetTableDecoder().decode(zoneName: "fixture", payload: payload)

        XCTAssertEqual(zone.records.count, 1)
        if case .unknown(let typeID) = zone.records[0].kind {
            XCTAssertEqual(typeID, 59)
        } else {
            XCTFail("Expected unknown type to be retained")
        }
    }

    private func putBE32(_ value: UInt32, at offset: Int, in data: inout Data) {
        data[offset] = UInt8((value >> 24) & 0xff)
        data[offset + 1] = UInt8((value >> 16) & 0xff)
        data[offset + 2] = UInt8((value >> 8) & 0xff)
        data[offset + 3] = UInt8(value & 0xff)
    }
}
