import Foundation
import ZIPFoundation

actor PS3DumpScanner {
    enum ScannerError: LocalizedError {
        case cannotAccessFolder
        case unableToEnumerate
        case cannotOpenArchive
        case emptyArchive
        case noManifestMatches

        var errorDescription: String? {
            switch self {
            case .cannotAccessFolder: return "The selected folder could not be accessed."
            case .unableToEnumerate: return "The selected folder could not be enumerated."
            case .cannotOpenArchive: return "The ZIP archive could not be opened."
            case .emptyArchive: return "The ZIP archive contains no files."
            case .noManifestMatches: return "No BO2 Zombies files from the built-in manifest were found."
            }
        }
    }

    private let impossibleSizeThreshold: Int64 = 1 << 40 // 1 TiB

    func scan(folderURL: URL) throws -> ScanReport {
        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer { if accessed { folderURL.stopAccessingSecurityScopedResource() } }

        guard FileManager.default.fileExists(atPath: folderURL.path) else {
            throw ScannerError.cannotAccessFolder
        }

        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .nameKey]
        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw ScannerError.unableToEnumerate
        }

        var results: [ScannedFile] = []
        var totalBytes: Int64 = 0

        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }

            let relative = fileURL.path.replacingOccurrences(
                of: folderURL.path.hasSuffix("/") ? folderURL.path : folderURL.path + "/",
                with: ""
            )

            guard BO2ZombiesManifest.contains(relative) else { continue }

            let rawSize = Int64(values?.fileSize ?? 0)
            let size = sanitizedSize(rawSize)
            totalBytes += size
            results.append(makeScannedFile(path: relative, size: size))
        }

        guard !results.isEmpty else { throw ScannerError.noManifestMatches }
        return makeReport(name: folderURL.lastPathComponent, results: results, totalBytes: totalBytes)
    }

    /// Scans ZIP metadata directly from the central directory.
    /// Only BO2 Zombies files listed in BO2ZombiesManifest are retained.
    /// This intentionally does not decompress the archive.
    func scan(zipURL: URL) throws -> ScanReport {
        guard FileManager.default.fileExists(atPath: zipURL.path) else {
            throw ScannerError.cannotOpenArchive
        }

        let archive: Archive
        do {
            archive = try Archive(url: zipURL, accessMode: .read)
        } catch {
            throw ScannerError.cannotOpenArchive
        }

        var sawAnyFile = false
        var results: [ScannedFile] = []
        var totalBytes: Int64 = 0

        for entry in archive {
            guard entry.type == .file else { continue }
            sawAnyFile = true

            guard BO2ZombiesManifest.contains(entry.path) else { continue }

            let rawSize = Int64(entry.uncompressedSize)
            let size = sanitizedSize(rawSize)
            totalBytes += size
            results.append(makeScannedFile(path: entry.path, size: size))
        }

        guard sawAnyFile else { throw ScannerError.emptyArchive }
        guard !results.isEmpty else { throw ScannerError.noManifestMatches }

        return makeReport(
            name: zipURL.deletingPathExtension().lastPathComponent,
            results: results,
            totalBytes: totalBytes
        )
    }

    private func sanitizedSize(_ size: Int64) -> Int64 {
        guard size >= 0, size < impossibleSizeThreshold else { return 0 }
        return size
    }

    private func makeReport(name: String, results: [ScannedFile], totalBytes: Int64) -> ScanReport {
        ScanReport(
            createdAt: Date(),
            selectedFolderName: name,
            totalFiles: results.count,
            totalBytes: totalBytes,
            files: results.sorted {
                $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending
            }
        )
    }

    private func makeScannedFile(path: String, size: Int64) -> ScannedFile {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        let nsPath = normalized as NSString
        let name = nsPath.lastPathComponent
        let ext = (name as NSString).pathExtension.lowercased()

        return ScannedFile(
            relativePath: normalized,
            name: name,
            fileExtension: ext,
            size: size,
            category: classify(path: normalized),
            isLikelyZombiesContent: true
        )
    }

    private func classify(path: String) -> FileCategory {
        let name = (path as NSString).lastPathComponent.lowercased()
        let ext = (name as NSString).pathExtension.lowercased()

        if ext == "ff" { return .fastFile }
        if ["gsc", "csc", "cfg"].contains(ext) { return .script }
        if name == "eboot.bin" || ["self", "sprx"].contains(ext) { return .executable }
        if ["wav", "mp3", "at3", "at9", "wem", "xma", "sabs", "sabl"].contains(ext) { return .audio }
        if ["dds", "png", "jpg", "jpeg", "tga", "iwi"].contains(ext) { return .texture }
        if ["obj", "fbx", "dae", "xmodel_bin"].contains(ext) { return .model }
        if ["pak", "psarc", "zip", "ipak"].contains(ext) { return .archive }
        if ["str", "csv", "json", "txt"].contains(ext) { return .localization }
        return .unknown
    }
}
