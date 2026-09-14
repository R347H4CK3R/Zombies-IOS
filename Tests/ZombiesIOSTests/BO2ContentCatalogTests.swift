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
}
