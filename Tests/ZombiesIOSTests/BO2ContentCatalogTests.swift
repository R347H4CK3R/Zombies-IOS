import XCTest
@testable import ZombiesIOS

final class BO2ContentCatalogTests: XCTestCase {
    func testClassifiesCampaignFastFile() {
        XCTAssertEqual(BO2ContentClassifier.classify(path: "PS3_GAME/USRDIR/english/sp_savannah.ff"), .campaign)
    }

    func testClassifiesMultiplayerFastFile() {
        XCTAssertEqual(BO2ContentClassifier.classify(path: "PS3_GAME/USRDIR/english/mp_hijacked.ff"), .multiplayer)
    }

    func testClassifiesZombiesFastFile() {
        XCTAssertEqual(BO2ContentClassifier.classify(path: "PS3_GAME/USRDIR/english/zm_transit.ff"), .zombies)
    }

    func testClassifiesSharedContainersAsCommon() {
        XCTAssertEqual(BO2ContentClassifier.classify(path: "PS3_GAME/USRDIR/english/common.ff"), .common)
        XCTAssertEqual(BO2ContentClassifier.classify(path: "PS3_GAME/USRDIR/english/patch.ff"), .common)
    }

    func testClassifiesLocalizedModeResources() {
        XCTAssertEqual(BO2ContentClassifier.classify(path: "PS3_GAME/USRDIR/french/mp_hijacked.ipak"), .multiplayer)
        XCTAssertEqual(BO2ContentClassifier.classify(path: "PS3_GAME/USRDIR/french/zm_transit.sabs"), .zombies)
    }

    func testDoesNotTreatEveryUSRDIRFileAsZombies() {
        XCTAssertNotEqual(BO2ContentClassifier.classify(path: "PS3_GAME/USRDIR/english/sp_savannah.ff"), .zombies)
    }

    func testConvertibleSelectionIncludesAllGameModesAndContainers() {
        XCTAssertTrue(BO2ContentClassifier.isConvertibleResource(path: "PS3_GAME/USRDIR/english/sp_savannah.ff"))
        XCTAssertTrue(BO2ContentClassifier.isConvertibleResource(path: "PS3_GAME/USRDIR/english/mp_hijacked.ipak"))
        XCTAssertTrue(BO2ContentClassifier.isConvertibleResource(path: "PS3_GAME/USRDIR/english/zm_transit.sabs"))
        XCTAssertTrue(BO2ContentClassifier.isConvertibleResource(path: "PS3_GAME/USRDIR/english/common.sabl"))
    }

    func testConvertibleSelectionExcludesPS3ExecutableMetadata() {
        XCTAssertFalse(BO2ContentClassifier.isConvertibleResource(path: "PS3_GAME/USRDIR/EBOOT.BIN"))
        XCTAssertFalse(BO2ContentClassifier.isConvertibleResource(path: "PS3_GAME/PARAM.SFO"))
        XCTAssertFalse(BO2ContentClassifier.isConvertibleResource(path: "PS3_DISC.SFB"))
    }

    func testCatalogKeepsModesIndependent() {
        let catalog = BO2ContentCatalog(paths: [
            "PS3_GAME/USRDIR/english/sp_savannah.ff",
            "PS3_GAME/USRDIR/english/mp_hijacked.ff",
            "PS3_GAME/USRDIR/english/zm_transit.ff",
            "PS3_GAME/USRDIR/english/common.ff"
        ])
        XCTAssertEqual(catalog.count(for: .campaign), 1)
        XCTAssertEqual(catalog.count(for: .multiplayer), 1)
        XCTAssertEqual(catalog.count(for: .zombies), 1)
        XCTAssertEqual(catalog.count(for: .common), 1)
    }
}
