import Foundation

actor TranzitCacheManager {
    enum CacheError: LocalizedError {
        case stagingNotValidated
        case promotionFailed(String)

        var errorDescription: String? {
            switch self {
            case .stagingNotValidated:
                return "The staged Tranzit cache has not passed validation."
            case .promotionFailed(let message):
                return "Could not promote the staged Tranzit cache: \(message)"
            }
        }
    }

    let paths: TranzitCachePaths
    private let fileManager: FileManager

    init(applicationSupportRoot: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        if let applicationSupportRoot {
            self.paths = TranzitCachePaths(applicationSupportRoot: applicationSupportRoot)
        } else {
            self.paths = try TranzitCachePaths.defaultPaths(fileManager: fileManager)
        }
        try fileManager.createDirectory(at: paths.root, withIntermediateDirectories: true)
    }

    func sourceFingerprints(rootURL: URL, resources: [TranzitLoadedResource]) throws -> [TranzitSourceFingerprint] {
        try resources.map { resource in
            let url = rootURL.appendingPathComponent(resource.relativePath)
            let attrs = try fileManager.attributesOfItem(atPath: url.path)
            let size = (attrs[.size] as? NSNumber)?.int64Value ?? resource.byteCount
            let modified = (attrs[.modificationDate] as? Date) ?? .distantPast
            return TranzitSourceFingerprint(relativePath: resource.relativePath, byteCount: size, modifiedAt: modified)
        }
        .sorted { $0.relativePath.lowercased() < $1.relativePath.lowercased() }
    }

    func loadValidManifest(for fingerprints: [TranzitSourceFingerprint]) throws -> TranzitCacheManifest? {
        guard fileManager.fileExists(atPath: paths.activeManifest.path) else { return nil }
        let data = try Data(contentsOf: paths.activeManifest)
        let manifest = try JSONDecoder().decode(TranzitCacheManifest.self, from: data)
        guard manifest.schemaVersion == TranzitCacheManifest.currentSchemaVersion,
              manifest.validationState == .valid,
              manifest.sourceFingerprints == fingerprints,
              fileManager.fileExists(atPath: paths.activeMesh.path),
              fileManager.fileExists(atPath: paths.activeMaterials.path) else {
            return nil
        }
        return manifest
    }

    @discardableResult
    func prepareStaging() throws -> TranzitCachePaths {
        if fileManager.fileExists(atPath: paths.staging.path) {
            try fileManager.removeItem(at: paths.staging)
        }
        try fileManager.createDirectory(at: paths.stagingTextures, withIntermediateDirectories: true)
        return paths
    }

    func discardStaging() {
        try? fileManager.removeItem(at: paths.staging)
    }

    func promoteStaging() throws {
        guard fileManager.fileExists(atPath: paths.stagingManifest.path) else {
            throw CacheError.stagingNotValidated
        }
        let manifestData = try Data(contentsOf: paths.stagingManifest)
        let manifest = try JSONDecoder().decode(TranzitCacheManifest.self, from: manifestData)
        guard manifest.validationState == .valid else { throw CacheError.stagingNotValidated }

        let backup = paths.root.appendingPathComponent("active.backup", isDirectory: true)
        if fileManager.fileExists(atPath: backup.path) { try fileManager.removeItem(at: backup) }

        let hadActive = fileManager.fileExists(atPath: paths.active.path)
        if hadActive { try fileManager.moveItem(at: paths.active, to: backup) }

        do {
            try fileManager.moveItem(at: paths.staging, to: paths.active)
            guard fileManager.fileExists(atPath: paths.activeManifest.path) else {
                throw CacheError.promotionFailed("active manifest missing after move")
            }
            if fileManager.fileExists(atPath: backup.path) { try fileManager.removeItem(at: backup) }
        } catch {
            try? fileManager.removeItem(at: paths.active)
            if hadActive, fileManager.fileExists(atPath: backup.path) {
                try? fileManager.moveItem(at: backup, to: paths.active)
            }
            throw CacheError.promotionFailed(error.localizedDescription)
        }
    }
}
