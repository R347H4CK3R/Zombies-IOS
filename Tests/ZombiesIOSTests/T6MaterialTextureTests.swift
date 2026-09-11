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
}
