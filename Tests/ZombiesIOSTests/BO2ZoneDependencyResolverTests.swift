import XCTest
@testable import ZombiesIOS

final class BO2ZoneDependencyResolverTests: XCTestCase {
    func testMultiplayerIncludesCommonModeAndTargetZone() {
        let paths = [
            "PS3_GAME/USRDIR/english/common.ff",
            "PS3_GAME/USRDIR/english/code_post_gfx_mp.ff",
            "PS3_GAME/USRDIR/english/common_mp.ff",
            "PS3_GAME/USRDIR/english/mp_hijacked.ff",
            "PS3_GAME/USRDIR/english/mp_hijacked.ipak",
            "PS3_GAME/USRDIR/english/zm_transit.ff"
        ]
        let resolver = BO2ZoneDependencyResolver(catalog: BO2ContentCatalog(paths: paths))
        let descriptor = resolver.descriptor(mode: .multiplayer, zone: "mp_hijacked")
        XCTAssertTrue(descriptor.resources.contains { $0.hasSuffix("common.ff") })
        XCTAssertTrue(descriptor.resources.contains { $0.hasSuffix("common_mp.ff") })
        XCTAssertTrue(descriptor.resources.contains { $0.hasSuffix("mp_hijacked.ff") })
        XCTAssertTrue(descriptor.resources.contains { $0.hasSuffix("mp_hijacked.ipak") })
        XCTAssertFalse(descriptor.resources.contains { $0.hasSuffix("zm_transit.ff") })
    }

    func testZombiesDoesNotPullCampaignOrMultiplayerZones() {
        let paths = [
            "common.ff", "common_zm.ff", "zm_transit.ff", "sp_savannah.ff", "mp_hijacked.ff"
        ]
        let resolver = BO2ZoneDependencyResolver(catalog: BO2ContentCatalog(paths: paths))
        let descriptor = resolver.descriptor(mode: .zombies, zone: "zm_transit")
        XCTAssertTrue(descriptor.resources.contains("common.ff"))
        XCTAssertTrue(descriptor.resources.contains("common_zm.ff"))
        XCTAssertTrue(descriptor.resources.contains("zm_transit.ff"))
        XCTAssertFalse(descriptor.resources.contains("sp_savannah.ff"))
        XCTAssertFalse(descriptor.resources.contains("mp_hijacked.ff"))
    }

    func testCampaignDescriptorCarriesModeAndZone() {
        let resolver = BO2ZoneDependencyResolver(catalog: BO2ContentCatalog(paths: ["common.ff", "sp_savannah.ff"]))
        let descriptor = resolver.descriptor(mode: .campaign, zone: "sp_savannah")
        XCTAssertEqual(descriptor.mode, .campaign)
        XCTAssertEqual(descriptor.zone, "sp_savannah")
    }
}
