import XCTest
@testable import ZombiesIOS

final class T6ZoneIndexDecoderTests: XCTestCase {
    func testDecodesFollowingStringsDependenciesAndAssetTable() throws {
        var data = Data(repeating: 0, count: 40)
        // XFile sizes: 8 block sizes begin at 0x08. Give virtual block enough logical space.
        writeBE32(1024, into: &data, at: 8 + 5 * 4)

        // XAssetList begins immediately after the 0x28 XFile header.
        appendBE32(2, to: &data)              // string count
        appendBE32(0xFFFF_FFFF, to: &data)    // strings following
        appendBE32(1, to: &data)              // dependency count
        appendBE32(0xFFFF_FFFF, to: &data)    // dependencies following
        appendBE32(2, to: &data)              // asset count
        appendBE32(0xFFFF_FFFF, to: &data)    // assets following

        // strings pointer array, both following
        appendBE32(0xFFFF_FFFF, to: &data)
        appendBE32(0xFFFF_FFFF, to: &data)
        data.append(contentsOf: Array("alpha\0".utf8))
        data.append(contentsOf: Array("beta\0".utf8))

        // dependency pointer array + following string
        appendBE32(0xFFFF_FFFF, to: &data)
        data.append(contentsOf: Array("common\0".utf8))

        // XAsset[type,pointer] x2
        appendBE32(17, to: &data)
        appendBE32(0xFFFF_FFFF, to: &data)
        appendBE32(5, to: &data)
        appendBE32((5 << 29) + 0x40 + 1, to: &data)

        let index = try T6ZoneIndexDecoder.decode(data)
        XCTAssertEqual(index.scriptStrings, ["alpha", "beta"])
        XCTAssertEqual(index.dependencies, ["common"])
        XCTAssertEqual(index.assets.count, 2)
        XCTAssertEqual(index.assets[0].typeId, 17)
        XCTAssertEqual(index.assets[0].pointer, .following)
        XCTAssertEqual(index.assets[1].typeId, 5)
        XCTAssertEqual(index.assets[1].pointer, .offset(block: 5, offset: 0x40))
    }

    func testRejectsTruncatedAssetTable() throws {
        var data = Data(repeating: 0, count: 40)
        writeBE32(256, into: &data, at: 8 + 5 * 4)
        appendBE32(0, to: &data)
        appendBE32(0, to: &data)
        appendBE32(0, to: &data)
        appendBE32(0, to: &data)
        appendBE32(2, to: &data)
        appendBE32(0xFFFF_FFFF, to: &data)
        appendBE32(17, to: &data) // only half an asset entry

        XCTAssertThrowsError(try T6ZoneIndexDecoder.decode(data))
    }

    private func appendBE32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8((value >> 24) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8(value & 0xff))
    }

    private func writeBE32(_ value: UInt32, into data: inout Data, at offset: Int) {
        data[offset] = UInt8((value >> 24) & 0xff)
        data[offset + 1] = UInt8((value >> 16) & 0xff)
        data[offset + 2] = UInt8((value >> 8) & 0xff)
        data[offset + 3] = UInt8(value & 0xff)
    }
}
