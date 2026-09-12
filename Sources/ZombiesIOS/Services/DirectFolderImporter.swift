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

    /// Progressive direct-folder import: scan and use the user's original folder
    /// in place. No BO2 files are copied into Documents, Library, Application
    /// Support, or any other app-container directory.
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
            try? folderStore.save(folderURL: folderURL)
            return Result(report: report, importedAssetsURL: folderURL)
        } catch PS3DumpScanner.ScannerError.noManifestMatches {
            throw ImportError.noManifestMatches
        }
    }
}
