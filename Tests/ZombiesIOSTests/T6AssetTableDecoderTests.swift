import XCTest
@testable import ZombiesIOS

final class T6AssetTableDecoderTests: XCTestCase {
    func testMapsKnownRetailAssetTypes() {
        XCTAssertEqual(T6AssetType(rawValue: 5).name, "XModel")
        XCTAssertEqual(T6AssetType(rawValue: 6).name, "Material")
        XCTAssertEqual(T6AssetType(rawValue: 17).name, "GfxWorld")
        XCTAssertEqual(T6AssetType(rawValue: 25).name, "WeaponVariantDef")
        XCTAssertEqual(T6AssetType(rawValue: 48).name, "ScriptParseTree")
    }

    func testPreservesUnknownAssetType() {
        let type = T6AssetType(rawValue: 0x1234)
        XCTAssertNil(type.knownName)
        XCTAssertEqual(type.name, "Unknown(4660)")
    }

    func testConvertsZoneIndexEntriesWithoutDroppingUnknowns() {
        let entries = [
            T6ZoneAssetEntry(typeId: 5, pointer: .following),
            T6ZoneAssetEntry(typeId: 0x1234, pointer: .offset(block: 5, offset: 99))
        ]
        let typed = T6AssetTableDecoder.decode(entries)
        XCTAssertEqual(typed.count, 2)
        XCTAssertEqual(typed[0].type.name, "XModel")
        XCTAssertEqual(typed[1].type.rawValue, 0x1234)
    }
}
