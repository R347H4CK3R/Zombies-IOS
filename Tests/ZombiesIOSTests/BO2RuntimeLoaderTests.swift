import XCTest
@testable import ZombiesIOS

final class BO2RuntimeLoaderTests: XCTestCase {
    func testLoadsOnlyDescriptorResourcesInPlace() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let paths = ["common.ff", "mp_hijacked.ff", "mp_hijacked.ipak", "zm_transit.ff"]
        for path in paths {
            try Data(repeating: 1, count: 512).write(to: root.appendingPathComponent(path))
        }
        let files = paths.map { path in
            ScannedFile(relativePath: path, name: path, fileExtension: (path as NSString).pathExtension, size: 512, category: .unknown, isLikelyZombiesContent: false, inspection: nil)
        }
        let report = ScanReport(createdAt: Date(), selectedFolderName: "root", totalFiles: files.count, totalBytes: 2048, files: files)
        let descriptor = BO2ZoneDependencyResolver(catalog: report.bo2ContentCatalog).descriptor(mode: .multiplayer, zone: "mp_hijacked")

        let session = try await BO2RuntimeLoader().load(descriptor: descriptor, report: report, rootURL: root, validateFastFiles: false)
        XCTAssertEqual(session.descriptor.mode, .multiplayer)
        XCTAssertTrue(session.resources.contains { $0.relativePath == "common.ff" })
        XCTAssertTrue(session.resources.contains { $0.relativePath == "mp_hijacked.ff" })
        XCTAssertFalse(session.resources.contains { $0.relativePath == "zm_transit.ff" })
    }
}
