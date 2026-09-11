import XCTest
@testable import ZombiesIOS

final class T6WorldConverterTests: XCTestCase {
    func testTypedAssetResolverPreservesStableTableOrder() throws {
        var payload = Data(repeating: 0, count: 256)
        let contentOffset = 0x28
        writeBE32(5, to: &payload, at: contentOffset + 16)
        let table = contentOffset + 24
        let entries: [(UInt32, UInt32)] = [
            (17, 0x100),
            (6, 0x110),
            (8, 0x120),
            (6, 0x130),
            (8, 0x140)
        ]
        for (i, entry) in entries.enumerated() {
            writeBE32(entry.0, to: &payload, at: table + i * 8)
            writeBE32(entry.1, to: &payload, at: table + i * 8 + 4)
        }

        let index = try XCTUnwrap(T6AssetResolver.resolveIndex(in: payload))
        XCTAssertEqual(index.first(.gfxWorld)?.rawPointer, 0x100)
        XCTAssertEqual(index.all(.material).map(\.rawPointer), [0x110, 0x130])
        XCTAssertEqual(index.all(.gfxImage).map(\.rawPointer), [0x120, 0x140])
    }

    func testWorldConverterRequiresIndexedGfxWorld() {
        let index = T6ResolvedAssetIndex(records: [], tableOffset: 0, tableEntryCount: 0)
        XCTAssertThrowsError(try T6WorldConverter.convert(payload: Data(repeating: 0, count: 4096), assets: index)) { error in
            guard case T6WorldConverterError.missingGfxWorld = error else {
                return XCTFail("Expected missingGfxWorld, got \(error)")
            }
        }
    }

    private func writeBE32(_ value: UInt32, to data: inout Data, at offset: Int) {
        data[offset] = UInt8((value >> 24) & 0xff)
        data[offset + 1] = UInt8((value >> 16) & 0xff)
        data[offset + 2] = UInt8((value >> 8) & 0xff)
        data[offset + 3] = UInt8(value & 0xff)
    }
}
