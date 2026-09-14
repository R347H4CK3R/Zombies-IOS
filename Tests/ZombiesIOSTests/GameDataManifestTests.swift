import XCTest
@testable import ZombiesIOS

final class GameDataManifestTests: XCTestCase {
    func testCompletedMatchingRecordCanResumeWithoutReconversion() throws {
        var manifest = GameDataManifest(converterVersion: "1")
        manifest.markCompleted(
            sourcePath: "PS3_GAME/USRDIR/english/mp_hijacked.ff",
            sourceHash: "abc123",
            stage: .zone,
            outputRelativePath: "zones/mp_hijacked.gdz",
            outputSize: 4096
        )

        XCTAssertFalse(manifest.needsConversion(
            sourcePath: "PS3_GAME/USRDIR/english/mp_hijacked.ff",
            sourceHash: "abc123",
            stage: .zone,
            converterVersion: "1"
        ))
    }

    func testSourceHashChangeInvalidatesCompletedRecord() throws {
        var manifest = GameDataManifest(converterVersion: "1")
        manifest.markCompleted(
            sourcePath: "PS3_GAME/USRDIR/english/mp_hijacked.ff",
            sourceHash: "old",
            stage: .zone,
            outputRelativePath: "zones/mp_hijacked.gdz",
            outputSize: 4096
        )

        XCTAssertTrue(manifest.needsConversion(
            sourcePath: "PS3_GAME/USRDIR/english/mp_hijacked.ff",
            sourceHash: "new",
            stage: .zone,
            converterVersion: "1"
        ))
    }

    func testConverterVersionChangeInvalidatesCompletedRecord() throws {
        var manifest = GameDataManifest(converterVersion: "1")
        manifest.markCompleted(
            sourcePath: "PS3_GAME/USRDIR/english/zm_transit.ff",
            sourceHash: "same",
            stage: .zone,
            outputRelativePath: "zones/zm_transit.gdz",
            outputSize: 100
        )

        XCTAssertTrue(manifest.needsConversion(
            sourcePath: "PS3_GAME/USRDIR/english/zm_transit.ff",
            sourceHash: "same",
            stage: .zone,
            converterVersion: "2"
        ))
    }

    func testInterruptedRecordIsRetried() {
        var manifest = GameDataManifest(converterVersion: "1")
        manifest.markInProgress(
            sourcePath: "PS3_GAME/USRDIR/english/sp_savannah.ff",
            sourceHash: "hash",
            stage: .zone
        )

        XCTAssertTrue(manifest.needsConversion(
            sourcePath: "PS3_GAME/USRDIR/english/sp_savannah.ff",
            sourceHash: "hash",
            stage: .zone,
            converterVersion: "1"
        ))
    }

    func testAtomicManifestWriteAndPartRecovery() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let store = try GameDataStore(rootURL: base, converterVersion: "1")
        var manifest = GameDataManifest(converterVersion: "1")
        manifest.markCompleted(
            sourcePath: "PS3_GAME/USRDIR/english/mp_hijacked.ff",
            sourceHash: "hash",
            stage: .zone,
            outputRelativePath: "zones/mp_hijacked.gdz",
            outputSize: 42
        )
        try store.saveManifest(manifest)

        XCTAssertTrue(FileManager.default.fileExists(atPath: store.manifestURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.manifestPartURL.path))

        let recovered = try store.loadManifest()
        XCTAssertEqual(recovered.records.count, 1)
        XCTAssertFalse(recovered.needsConversion(
            sourcePath: "PS3_GAME/USRDIR/english/mp_hijacked.ff",
            sourceHash: "hash",
            stage: .zone,
            converterVersion: "1"
        ))
    }
}
