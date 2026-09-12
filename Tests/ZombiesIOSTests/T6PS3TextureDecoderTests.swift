import XCTest
@testable import ZombiesIOS

final class T6PS3TextureDecoderTests: XCTestCase {
    private let imageID = T6AssetID(zoneName: "fixture", typeID: 8, assetIndex: 0, tableOffset: 0x40)

    func testDecodesRGBA8MetadataAndPixels() throws {
        let pixels: [UInt8] = [
            255, 0, 0, 255,
            0, 255, 0, 128
        ]
        let loadDef = makeLoadDef(width: 2, height: 1, depth: 1, mipCount: 1, format: 28, resource: pixels)

        let texture = try T6PS3TextureDecoder().decode(imageID: imageID, loadDefData: loadDef)

        XCTAssertEqual(texture.width, 2)
        XCTAssertEqual(texture.height, 1)
        XCTAssertEqual(texture.depth, 1)
        XCTAssertEqual(texture.mipCount, 1)
        XCTAssertEqual(texture.format, .rgba8Unorm)
        XCTAssertTrue(texture.hasAlpha)
        XCTAssertEqual(Array(texture.rgba8), pixels)
    }

    func testDecodesOneBC1Block() throws {
        // BC1 block: color0 = red 565, color1 = black, all selectors use color0.
        let block: [UInt8] = [0x00, 0xF8, 0x00, 0x00, 0, 0, 0, 0]
        let loadDef = makeLoadDef(width: 4, height: 4, depth: 1, mipCount: 1, format: 71, resource: block)

        let texture = try T6PS3TextureDecoder().decode(imageID: imageID, loadDefData: loadDef)

        XCTAssertEqual(texture.format, .bc1Unorm)
        XCTAssertEqual(texture.rgba8.count, 4 * 4 * 4)
        XCTAssertEqual(Array(texture.rgba8.prefix(4)), [255, 0, 0, 255])
        XCTAssertFalse(texture.hasAlpha)
    }

    func testRejectsTruncatedResourceRange() throws {
        var loadDef = makeLoadDef(width: 2, height: 2, depth: 1, mipCount: 1, format: 28, resource: [0, 0, 0, 255])
        putLE32(16, at: 12, in: &loadDef)

        XCTAssertThrowsError(try T6PS3TextureDecoder().decode(imageID: imageID, loadDefData: loadDef)) { error in
            XCTAssertEqual(error as? T6PS3TextureDecoder.DecodeError, .truncatedResource(expected: 16, available: 4))
        }
    }

    func testRejectsUnsupportedDXGIFormatExplicitly() throws {
        let loadDef = makeLoadDef(width: 1, height: 1, depth: 1, mipCount: 1, format: 87, resource: [0, 0, 0, 255])

        XCTAssertThrowsError(try T6PS3TextureDecoder().decode(imageID: imageID, loadDefData: loadDef)) { error in
            XCTAssertEqual(error as? T6PS3TextureDecoder.DecodeError, .unsupportedFormat(87))
        }
    }

    private func makeLoadDef(
        width: UInt16,
        height: UInt16,
        depth: UInt16,
        mipCount: UInt8,
        format: UInt32,
        resource: [UInt8]
    ) -> Data {
        var data = Data(repeating: 0, count: 16 + resource.count)
        data[0] = mipCount
        data[1] = 0
        putLE16(width, at: 2, in: &data)
        putLE16(height, at: 4, in: &data)
        putLE16(depth, at: 6, in: &data)
        putLE32(format, at: 8, in: &data)
        putLE32(UInt32(resource.count), at: 12, in: &data)
        data.replaceSubrange(16..<(16 + resource.count), with: resource)
        return data
    }

    private func putLE16(_ value: UInt16, at offset: Int, in data: inout Data) {
        data[offset] = UInt8(value & 0xff)
        data[offset + 1] = UInt8((value >> 8) & 0xff)
    }

    private func putLE32(_ value: UInt32, at offset: Int, in data: inout Data) {
        data[offset] = UInt8(value & 0xff)
        data[offset + 1] = UInt8((value >> 8) & 0xff)
        data[offset + 2] = UInt8((value >> 16) & 0xff)
        data[offset + 3] = UInt8((value >> 24) & 0xff)
    }
}
