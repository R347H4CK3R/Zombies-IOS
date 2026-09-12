import Foundation

actor DirectFolderImporter {
    struct Result {
        let report: ScanReport
        let importedAssetsURL: URL?
    }

    enum ImportError: LocalizedError {
        case cannotAccessFolder
        case noManifestMatches

        var errorDescription: String? {
            switch self {
            case .cannotAccessFolder:
                return "The selected BO2 folder could not be accessed."
            case .noManifestMatches:
                return "No BO2 Zombies manifest files were found in the selected folder."
            }
        }
    }

    private let scanner = PS3DumpScanner()
    private let folderStore = ExternalGameFolderStore()
    private let dependencyResolver = TranzitDependencyResolver()

    /// Scans the user's selected dump, remembers the external source folder,
    /// then copies only manifest-selected Tranzit dependencies into the app's
    /// local SourceCache for faster repeat launches.
    func importFolder(_ folderURL: URL) async throws -> Result {
        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        guard FileManager.default.fileExists(atPath: folderURL.path) else {
            throw ImportError.cannotAccessFolder
        }

        do {
            let report = try await scanner.scan(folderURL: folderURL)
            let manifest = try await dependencyResolver.initialManifest(sourceRoot: folderURL)
            let sourceCache = try TranzitSourceCache()
            _ = try await sourceCache.prepare(manifest: manifest, sourceRoot: folderURL)
            try? folderStore.save(folderURL: folderURL)
            let cacheRoot = try RuntimeCachePolicy.tranzitSourceCacheRoot()
            return Result(report: report, importedAssetsURL: cacheRoot)
        } catch PS3DumpScanner.ScannerError.noManifestMatches {
            throw ImportError.noManifestMatches
        }
    }
}
