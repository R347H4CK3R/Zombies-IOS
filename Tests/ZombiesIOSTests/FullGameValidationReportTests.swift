import XCTest
@testable import ZombiesIOS

final class FullGameValidationReportTests: XCTestCase {
    func testReleaseGateRequiresAllModesAndNoPlaceholders() {
        var report = FullGameValidationReport()
        XCTAssertFalse(report.isPlayableRelease)

        report.record(mode: .campaign, zone: "sp_savannah", renderedRealGeometry: true, collision: true, weaponFire: true, audio: true, startup: true)
        report.record(mode: .multiplayer, zone: "mp_hijacked", renderedRealGeometry: true, collision: true, weaponFire: true, audio: true, startup: true)
        report.record(mode: .zombies, zone: "zm_transit", renderedRealGeometry: true, collision: true, weaponFire: true, audio: true, startup: true)
        report.requiredAssetClassesComplete = true
        report.unsignedIPABuilt = true
        report.fallbackGeometryUsed = false
        report.placeholderAssetClasses = []

        XCTAssertTrue(report.isPlayableRelease)
    }

    func testFallbackGeometryBlocksRelease() {
        var report = FullGameValidationReport()
        for mode in [BO2ContentMode.campaign, .multiplayer, .zombies] {
            report.record(mode: mode, zone: mode.rawValue, renderedRealGeometry: true, collision: true, weaponFire: true, audio: true, startup: true)
        }
        report.requiredAssetClassesComplete = true
        report.unsignedIPABuilt = true
        report.fallbackGeometryUsed = true
        XCTAssertFalse(report.isPlayableRelease)
    }
}
