import XCTest
@testable import ZombiesIOS

final class TranzitCacheTests: XCTestCase {
    func testManifestRoundTrip() throws {
        let manifest = TranzitCacheManifest(
            schemaVersion: 1,
            sourceFingerprints: [TranzitSourceFingerprint(relativePath: "zone/zm_transit.ff", byteCount: 100, modifiedAt: Date(timeIntervalSince1970: 10))],
            surfaceCount: 12,
            vertexCount: 120,
            triangleCount: 80,
            materialCount: 4,
            textureTotal: 6,
            textureSucceeded: 5,
            textureFailed: 1,
            warnings: ["missing normal"],
            validationState: .valid
        )
        let data = try JSONEncoder().encode(manifest)
        XCTAssertEqual(try JSONDecoder().decode(TranzitCacheManifest.self, from: data), manifest)
    }

    func testPathsStayInsideApplicationSupportRoot() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = TranzitCachePaths(applicationSupportRoot: root)
        XCTAssertTrue(paths.active.path.contains("TranzitCache/active"))
        XCTAssertTrue(paths.staging.path.contains("TranzitCache/staging"))
        XCTAssertEqual(paths.activeMesh.lastPathComponent, "world.meshbin")
        XCTAssertEqual(paths.activeMaterials.lastPathComponent, "materials.json")
    }

    func testFingerprintChangesWhenSourceChanges() async throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let support = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: root.appendingPathComponent("zone", isDirectory: true), withIntermediateDirectories: true)
        let source = root.appendingPathComponent("zone/zm_transit.ff")
        try Data([1, 2, 3]).write(to: source)
        let resource = TranzitLoadedResource(relativePath: "zone/zm_transit.ff", byteCount: 3, header: Data([1]))
        let manager = try TranzitCacheManager(applicationSupportRoot: support)
        let first = try await manager.sourceFingerprints(rootURL: root, resources: [resource])
        try Data([1, 2, 3, 4, 5]).write(to: source)
        let second = try await manager.sourceFingerprints(rootURL: root, resources: [resource])
        XCTAssertNotEqual(first, second)
        try? fm.removeItem(at: root)
        try? fm.removeItem(at: support)
    }

    func testPromotionReplacesActiveOnlyAfterValidManifest() async throws {
        let fm = FileManager.default
        let support = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let manager = try TranzitCacheManager(applicationSupportRoot: support)
        let paths = await manager.paths
        try fm.createDirectory(at: paths.active, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: paths.active.appendingPathComponent("marker.txt"))
        _ = try await manager.prepareStaging()
        try Data("new".utf8).write(to: paths.staging.appendingPathComponent("new.txt"))
        let manifest = TranzitCacheManifest(
            schemaVersion: 1,
            sourceFingerprints: [],
            surfaceCount: 1,
            vertexCount: 3,
            triangleCount: 1,
            materialCount: 1,
            textureTotal: 0,
            textureSucceeded: 0,
            textureFailed: 0,
            warnings: [],
            validationState: .valid
        )
        try JSONEncoder().encode(manifest).write(to: paths.stagingManifest)
        try await manager.promoteStaging()
        XCTAssertTrue(fm.fileExists(atPath: paths.active.appendingPathComponent("new.txt").path))
        XCTAssertFalse(fm.fileExists(atPath: paths.active.appendingPathComponent("marker.txt").path))
        try? fm.removeItem(at: support)
    }
}
