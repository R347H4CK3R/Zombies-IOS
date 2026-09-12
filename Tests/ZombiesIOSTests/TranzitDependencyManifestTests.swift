import XCTest
@testable import ZombiesIOS

final class TranzitDependencyManifestTests: XCTestCase {
    func testManifestNormalizesAndDeduplicatesPaths() throws {
        let entries = [
            TranzitDependency(
                relativePath: "PS3_GAME/USRDIR/zone/all/zm_transit.ff",
                role: .zone,
                requirement: .required,
                byteCount: 10,
                sha256: "a",
                modifiedAt: nil
            ),
            TranzitDependency(
                relativePath: "PS3_GAME/USRDIR/zone/all/./zm_transit.ff",
                role: .zone,
                requirement: .optional,
                byteCount: 10,
                sha256: "a",
                modifiedAt: nil
            )
        ]

        let manifest = TranzitDependencyManifest(entries: entries)

        XCTAssertEqual(manifest.entries.count, 1)
        XCTAssertEqual(manifest.entries[0].requirement, .required)
        XCTAssertEqual(
            manifest.entries[0].normalizedRelativePath,
            "PS3_GAME/USRDIR/zone/all/zm_transit.ff"
        )
    }

    func testManifestCollapsesDotDotInsideRoot() throws {
        let entry = TranzitDependency(
            relativePath: "PS3_GAME/USRDIR/zone/all/../all/zm_transit.ff",
            role: .zone,
            requirement: .required,
            byteCount: 10,
            sha256: "a",
            modifiedAt: nil
        )

        let manifest = TranzitDependencyManifest(entries: [entry])

        XCTAssertEqual(manifest.entries.count, 1)
        XCTAssertEqual(
            manifest.entries[0].normalizedRelativePath,
            "PS3_GAME/USRDIR/zone/all/zm_transit.ff"
        )
    }

    func testManifestRejectsTraversalOutsideSelectedRoot() throws {
        let entry = TranzitDependency(
            relativePath: "../../outside.ff",
            role: .zone,
            requirement: .required,
            byteCount: 10,
            sha256: "a",
            modifiedAt: nil
        )

        let manifest = TranzitDependencyManifest(entries: [entry])

        XCTAssertTrue(manifest.entries.isEmpty)
    }

    func testRequirementPriorityIsRequiredThenOptionalThenDeferred() throws {
        let path = "PS3_GAME/USRDIR/zone/all/common_zm.ff"
        let manifest = TranzitDependencyManifest(entries: [
            TranzitDependency(relativePath: path, role: .sharedZone, requirement: .deferred, byteCount: 1, sha256: "c", modifiedAt: nil),
            TranzitDependency(relativePath: path, role: .sharedZone, requirement: .optional, byteCount: 1, sha256: "b", modifiedAt: nil),
            TranzitDependency(relativePath: path, role: .sharedZone, requirement: .required, byteCount: 1, sha256: "a", modifiedAt: nil)
        ])

        XCTAssertEqual(manifest.entries.count, 1)
        XCTAssertEqual(manifest.entries[0].requirement, .required)
    }

    func testManifestOrderingIsDeterministic() throws {
        let manifest = TranzitDependencyManifest(entries: [
            TranzitDependency(relativePath: "z.ff", role: .zone, requirement: .optional, byteCount: 1, sha256: "z", modifiedAt: nil),
            TranzitDependency(relativePath: "b.ff", role: .zone, requirement: .required, byteCount: 1, sha256: "b", modifiedAt: nil),
            TranzitDependency(relativePath: "a.ff", role: .zone, requirement: .required, byteCount: 1, sha256: "a", modifiedAt: nil)
        ])

        XCTAssertEqual(manifest.entries.map(\.normalizedRelativePath), ["a.ff", "b.ff", "z.ff"])
    }
}
