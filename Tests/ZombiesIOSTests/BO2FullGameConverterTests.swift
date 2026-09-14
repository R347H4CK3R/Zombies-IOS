import XCTest
@testable import ZombiesIOS

final class BO2FullGameConverterTests: XCTestCase {
    func testPlannerIncludesAllModesAndContainerClasses() {
        let files = [
            scanned("sp_savannah.ff"),
            scanned("mp_hijacked.ipak"),
            scanned("zm_transit.sabs"),
            scanned("common.sabl"),
            scanned("common.ff")
        ]
        let report = ScanReport(
            createdAt: Date(), selectedFolderName: "PS3_GAME",
            totalFiles: files.count, totalBytes: 5, files: files
        )
        let units = BO2FullGameConverter.plan(report: report)
        XCTAssertEqual(units.count, 5)
        XCTAssertTrue(units.contains { $0.mode == .campaign && $0.stage == .zone })
        XCTAssertTrue(units.contains { $0.mode == .multiplayer && $0.stage == .images })
        XCTAssertTrue(units.contains { $0.mode == .zombies && $0.stage == .audio })
        XCTAssertTrue(units.contains { $0.mode == .common && $0.stage == .audio })
    }

    func testPlannerDoesNotTreatPlatformBinaryAsGameData() {
        let files = [scanned("PS3_GAME/USRDIR/EBOOT.BIN"), scanned("PS3_GAME/PARAM.SFO")]
        let report = ScanReport(
            createdAt: Date(), selectedFolderName: "PS3_GAME",
            totalFiles: files.count, totalBytes: 2, files: files
        )
        XCTAssertTrue(BO2FullGameConverter.plan(report: report).isEmpty)
    }

    private func scanned(_ path: String) -> ScannedFile {
        ScannedFile(
            relativePath: path,
            name: (path as NSString).lastPathComponent,
            fileExtension: (path as NSString).pathExtension.lowercased(),
            size: 1,
            category: .unknown,
            isLikelyZombiesContent: false,
            inspection: nil
        )
    }
}
