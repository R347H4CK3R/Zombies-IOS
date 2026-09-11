import XCTest
@testable import ZombiesIOS

final class T6MaterialTextureTests: XCTestCase {
    func testMaterialConverterProvidesDiagnosticFallback() {
        let index = T6ResolvedAssetIndex(records: [], tableOffset: 0, tableEntryCount: 0)
        let result = T6MaterialConverter.convert(payload: Data(), assets: index)
        XCTAssertEqual(result.materials.count, 1)
        XCTAssertEqual(result.materials[0].id, 0)
        XCTAssertEqual(result.materials[0].name, "diagnostic_world")
        XCTAssertFalse(result.warnings.isEmpty)
    }

    func testTextureConverterAllowsEmptyImageSet() throws {
        let index = T6ResolvedAssetIndex(records: [], tableOffset: 0, tableEntryCount: 0)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let report = try T6TextureConverter.convert(payload: Data(), assets: index, destination: destination)
        XCTAssertEqual(report.total, 0)
        XCTAssertEqual(report.succeeded, 0)
        XCTAssertEqual(report.failed, 0)
        try? FileManager.default.removeItem(at: destination)
    }

    func testTextureConverterDecodesEmbeddedBC1LoadDef() throws {
        var payload = Data(repeating: 0, count: 256)
        let imageOffset = 64
        let loadDefOffset = 128

        writeBE32(UInt32(loadDefOffset), to: &payload, at: imageOffset)
        writeBE16(4, to: &payload, at: imageOffset + 0x18)
        writeBE16(4, to: &payload, at: imageOffset + 0x1A)
        writeBE16(1, to: &payload, at: imageOffset + 0x1C)
        payload[imageOffset + 0x1E] = 1

        payload[loadDefOffset] = 1
        payload[loadDefOffset + 1] = 0
        writeBE32(71, to: &payload, at: loadDefOffset + 4) // DXGI_FORMAT_BC1_UNORM
        writeBE32(8, to: &payload, at: loadDefOffset + 8)
        // Solid red BC1 block: RGB565 0xF800 in the block's byte ordering,
        // second color zero, all selector bits choose color 0.
        payload[loadDefOffset + 12] = 0x00
        payload[loadDefOffset + 13] = 0xF8

        let record = T6AssetRecord(type: .gfxImage, tableOffset: 0, rawPointer: UInt32(imageOffset))
        let index = T6ResolvedAssetIndex(records: [record], tableOffset: 0, tableEntryCount: 1)
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)

        let report = try T6TextureConverter.convert(payload: payload, assets: index, destination: destination)
        XCTAssertEqual(report.total, 1)
        XCTAssertEqual(report.succeeded, 1)
        XCTAssertEqual(report.failed, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.appendingPathComponent("gfximage_00000.png").path))
        try? FileManager.default.removeItem(at: destination)
    }

    private func writeBE16(_ value: UInt16, to data: inout Data, at offset: Int) {
        data[offset] = UInt8((value >> 8) & 0xff)
        data[offset + 1] = UInt8(value & 0xff)
    }

    private func writeBE32(_ value: UInt32, to data: inout Data, at offset: Int) {
        data[offset] = UInt8((value >> 24) & 0xff)
        data[offset + 1] = UInt8((value >> 16) & 0xff)
        data[offset + 2] = UInt8((value >> 8) & 0xff)
        data[offset + 3] = UInt8(value & 0xff)
    }
}
