import CryptoKit
import XCTest
@testable import ZombiesIOS

final class TranzitSourceCacheTests: XCTestCase {
    func testPrepareCopiesOnlyManifestEntriesAndReusesUnchangedFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }

        try Data("A".utf8).write(to: fixture.source.appendingPathComponent("a.ff"))
        try Data("B".utf8).write(to: fixture.source.appendingPathComponent("b.ff"))

        let dependency = try fixture.dependency(path: "a.ff", requirement: .required)
        let manifest = TranzitDependencyManifest(entries: [dependency])
        let cache = try TranzitSourceCache(fileManager: .default, cacheRoot: fixture.cache)

        let first = try await cache.prepare(manifest: manifest, sourceRoot: fixture.source)
        XCTAssertEqual(first.copied.map { $0.normalizedRelativePath }, ["a.ff"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.cache.appendingPathComponent("b.ff").path))

        let second = try await cache.prepare(manifest: manifest, sourceRoot: fixture.source)
        XCTAssertEqual(second.copied.count, 0)
        XCTAssertEqual(second.reused.map { $0.normalizedRelativePath }, ["a.ff"])
    }

    func testPrepareRecopiesChangedSourceWhenManifestHashChanges() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let sourceFile = fixture.source.appendingPathComponent("a.ff")
        try Data("A".utf8).write(to: sourceFile)

        let cache = try TranzitSourceCache(fileManager: .default, cacheRoot: fixture.cache)
        let firstManifest = TranzitDependencyManifest(entries: [try fixture.dependency(path: "a.ff", requirement: .required)])
        _ = try await cache.prepare(manifest: firstManifest, sourceRoot: fixture.source)

        try Data("A2".utf8).write(to: sourceFile)
        let changedManifest = TranzitDependencyManifest(entries: [try fixture.dependency(path: "a.ff", requirement: .required)])
        let result = try await cache.prepare(manifest: changedManifest, sourceRoot: fixture.source)

        XCTAssertEqual(result.copied.map { $0.normalizedRelativePath }, ["a.ff"])
        XCTAssertEqual(try Data(contentsOf: fixture.cache.appendingPathComponent("a.ff")), Data("A2".utf8))
    }

    func testPrepareRemovesStaleCachedFiles() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        try Data("A".utf8).write(to: fixture.source.appendingPathComponent("a.ff"))
        try Data("stale".utf8).write(to: fixture.cache.appendingPathComponent("old.ff"))

        let cache = try TranzitSourceCache(fileManager: .default, cacheRoot: fixture.cache)
        let manifest = TranzitDependencyManifest(entries: [try fixture.dependency(path: "a.ff", requirement: .required)])
        let result = try await cache.prepare(manifest: manifest, sourceRoot: fixture.source)

        XCTAssertEqual(result.removedRelativePaths, ["old.ff"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.cache.appendingPathComponent("old.ff").path))
    }

    func testRequiredMissingFailsAndOptionalMissingIsReported() async throws {
        let fixture = try Fixture()
        defer { fixture.cleanup() }
        let cache = try TranzitSourceCache(fileManager: .default, cacheRoot: fixture.cache)

        let required = TranzitDependency(relativePath: "missing-required.ff", role: .zone, requirement: .required, byteCount: 1, sha256: "00", modifiedAt: nil)
        do {
            _ = try await cache.prepare(manifest: TranzitDependencyManifest(entries: [required]), sourceRoot: fixture.source)
            XCTFail("Expected missing required source to fail")
        } catch TranzitSourceCache.CacheError.requiredSourceMissing {
            // expected
        }

        let optional = TranzitDependency(relativePath: "missing-optional.ff", role: .sharedZone, requirement: .optional, byteCount: 1, sha256: "00", modifiedAt: nil)
        let result = try await cache.prepare(manifest: TranzitDependencyManifest(entries: [optional]), sourceRoot: fixture.source)
        XCTAssertEqual(result.missingOptional.map { $0.normalizedRelativePath }, ["missing-optional.ff"])
    }

    private struct Fixture {
        let root: URL
        let source: URL
        let cache: URL

        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            source = root.appendingPathComponent("source", isDirectory: true)
            cache = root.appendingPathComponent("cache", isDirectory: true)
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        }

        func dependency(path: String, requirement: TranzitDependencyRequirement) throws -> TranzitDependency {
            let url = source.appendingPathComponent(path)
            let data = try Data(contentsOf: url)
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return TranzitDependency(
                relativePath: path,
                role: .zone,
                requirement: requirement,
                byteCount: Int64(data.count),
                sha256: digest,
                modifiedAt: nil
            )
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
        }
    }
}
