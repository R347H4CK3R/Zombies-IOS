import Foundation

enum ConvertedPackageStoreError: Error {
    case stagingMissing
}

struct ConvertedPackageStore {
    private let fileManager: FileManager
    private let activeRoot: URL
    private let stagingRoot: URL

    init(
        fileManager: FileManager = .default,
        activeRoot: URL = ConvertedTranzitPaths.activeRoot,
        stagingRoot: URL = ConvertedTranzitPaths.stagingRoot
    ) {
        self.fileManager = fileManager
        self.activeRoot = activeRoot
        self.stagingRoot = stagingRoot
    }

    func beginStaging() throws -> URL {
        if fileManager.fileExists(atPath: stagingRoot.path) {
            try fileManager.removeItem(at: stagingRoot)
        }
        try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        return stagingRoot
    }

    func promoteStaging() throws {
        guard fileManager.fileExists(atPath: stagingRoot.path) else {
            throw ConvertedPackageStoreError.stagingMissing
        }

        _ = try ConvertedPackageValidator.validate(at: stagingRoot)
        let backup = activeRoot.deletingLastPathComponent()
            .appendingPathComponent("ConvertedTranzit.backup", isDirectory: true)

        if fileManager.fileExists(atPath: backup.path) {
            try fileManager.removeItem(at: backup)
        }

        let hadActive = fileManager.fileExists(atPath: activeRoot.path)
        if hadActive {
            try fileManager.moveItem(at: activeRoot, to: backup)
        }

        do {
            try fileManager.moveItem(at: stagingRoot, to: activeRoot)
            if fileManager.fileExists(atPath: backup.path) {
                try fileManager.removeItem(at: backup)
            }
        } catch {
            if fileManager.fileExists(atPath: activeRoot.path) {
                try? fileManager.removeItem(at: activeRoot)
            }
            if hadActive, fileManager.fileExists(atPath: backup.path) {
                try? fileManager.moveItem(at: backup, to: activeRoot)
            }
            throw error
        }
    }

    func activeManifest() -> ConvertedTranzitManifest? {
        try? ConvertedPackageValidator.validate(at: activeRoot)
    }
}
