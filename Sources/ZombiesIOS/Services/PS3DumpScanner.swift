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

        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .fileSizeKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .nameKey
        ]

        guard let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            throw ScannerError.unableToEnumerate
        }

        var results: [ScannedFile] = []
        var totalBytes: Int64 = 0

        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }

            let relative = relativePath(of: fileURL, under: folderURL)
            guard BO2ZombiesManifest.contains(relative) else { continue }

            // Coordinate the read. This is important for iCloud Drive and other
            // File Provider-backed folders because metadata can remain at zero
            // until the provider hydrates the child item.
            let size = coordinatedRobustFileSize(for: fileURL, resourceValues: values)
            totalBytes += size
            results.append(makeScannedFile(path: relative, size: size))
        }

        guard !results.isEmpty else { throw ScannerError.noManifestMatches }
        return makeReport(name: folderURL.lastPathComponent, results: results, totalBytes: totalBytes)
    }

    /// Scans ZIP metadata directly from the central directory.
    /// Zero-byte manifest entries are deliberately retained in the report so
    /// callers can mark the import as incomplete instead of silently treating
    /// missing payload bytes as a successful match.
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
        var resultsByPath: [String: ScannedFile] = [:]

        for entry in archive {
            guard entry.type == .file else { continue }
            sawAnyFile = true
            guard BO2ZombiesManifest.contains(entry.path) else { continue }

            let size = sanitizedSize(Int64(entry.uncompressedSize))
            let scanned = makeScannedFile(path: entry.path, size: size)

            // If a malformed ZIP contains duplicate manifest paths, retain the
            // largest logical entry rather than double-counting it.
            let key = normalizedManifestKey(entry.path)
            if let old = resultsByPath[key] {
                if scanned.size > old.size {
                    resultsByPath[key] = scanned
                }
            } else {
                resultsByPath[key] = scanned
            }
        }

        guard sawAnyFile else { throw ScannerError.emptyArchive }

        let results = Array(resultsByPath.values)
        guard !results.isEmpty else { throw ScannerError.noManifestMatches }

        let totalBytes = results.reduce(Int64(0)) { partial, file in
            let (sum, overflow) = partial.addingReportingOverflow(file.size)
            return overflow ? impossibleSizeThreshold : min(sum, impossibleSizeThreshold)
        }

        return makeReport(
            name: zipURL.deletingPathExtension().lastPathComponent,
            results: results,
            totalBytes: totalBytes
        )
    }

    private func relativePath(of fileURL: URL, under folderURL: URL) -> String {
        let base = folderURL.standardizedFileURL.path
        let file = fileURL.standardizedFileURL.path
        let prefix = base.hasSuffix("/") ? base : base + "/"

        if file.hasPrefix(prefix) {
            return String(file.dropFirst(prefix.count))
        }
        return fileURL.lastPathComponent
    }

    private func coordinatedRobustFileSize(
        for fileURL: URL,
        resourceValues: URLResourceValues?
    ) -> Int64 {
        var coordinatedSize: Int64 = 0
        var coordinationError: NSError?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            readingItemAt: fileURL,
            options: [.withoutChanges],
            error: &coordinationError
        ) { coordinatedURL in
            coordinatedSize = robustFileSize(for: coordinatedURL, resourceValues: resourceValues)
        }

        if coordinatedSize > 0 {
            return coordinatedSize
        }

        // If coordination failed or the provider still reported zero, retry
        // directly. Some local providers do not need coordination.
        return robustFileSize(for: fileURL, resourceValues: resourceValues)
    }

    /// File Provider / security-scoped URLs on iOS can report a missing or zero
    /// fileSize even when the file has data. Try progressively stronger
    /// metadata sources, then force a real provider-backed read/seek.
    private func robustFileSize(
        for fileURL: URL,
        resourceValues: URLResourceValues?
    ) -> Int64 {
        var candidates: [Int64] = []

        if let value = resourceValues?.fileSize {
            candidates.append(Int64(value))
        }
        if let value = resourceValues?.totalFileAllocatedSize {
            candidates.append(Int64(value))
        }
        if let value = resourceValues?.fileAllocatedSize {
            candidates.append(Int64(value))
        }

        if let freshValues = try? fileURL.resourceValues(forKeys: [
            .fileSizeKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey
        ]) {
            if let value = freshValues.fileSize { candidates.append(Int64(value)) }
            if let value = freshValues.totalFileAllocatedSize { candidates.append(Int64(value)) }
            if let value = freshValues.fileAllocatedSize { candidates.append(Int64(value)) }
        }

        if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let number = attributes[.size] as? NSNumber {
            candidates.append(number.int64Value)
        }

        if let size = candidates.first(where: { $0 > 0 && $0 < impossibleSizeThreshold }) {
            return size
        }

        // Opening and reading one byte is intentional: a seek alone is not
        // sufficient to hydrate every iOS File Provider item.
        if let handle = try? FileHandle(forReadingFrom: fileURL) {
            defer { try? handle.close() }

            if let firstByte = try? handle.read(upToCount: 1), firstByte?.isEmpty == false {
                if let end = try? handle.seekToEnd(),
                   end > 0,
                   end < UInt64(impossibleSizeThreshold) {
                    return Int64(end)
                }
            } else if let end = try? handle.seekToEnd(),
                      end > 0,
                      end < UInt64(impossibleSizeThreshold) {
                return Int64(end)
            }
        }

        return 0
    }

    private func sanitizedSize(_ size: Int64) -> Int64 {
        guard size >= 0, size < impossibleSizeThreshold else { return 0 }
        return size
    }

    private func normalizedManifestKey(_ path: String) -> String {
        let normalized = path.replacingOccurrences(of: "\\", with: "/").lowercased()
        if let range = normalized.range(of: "ps3_game/") {
            return String(normalized[range.lowerBound...])
        }
        return normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
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
