import Foundation

actor PS3DumpScanner {
    enum ScannerError: Error {
        case cannotAccessFolder
        case unableToEnumerate
    }

    func scan(folderURL: URL) throws -> ScanReport {
        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { folderURL.stopAccessingSecurityScopedResource() }
        }

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

            let size = Int64(values?.fileSize ?? 0)
            totalBytes += size

            let relative = fileURL.path.replacingOccurrences(
                of: folderURL.path.hasSuffix("/") ? folderURL.path : folderURL.path + "/",
                with: ""
            )

            results.append(
                ScannedFile(
                    relativePath: relative,
                    name: fileURL.lastPathComponent,
                    fileExtension: fileURL.pathExtension.lowercased(),
                    size: size,
                    category: classify(fileURL),
                    isLikelyZombiesContent: isLikelyZombies(fileURL)
                )
            )
        }

        return ScanReport(
            createdAt: Date(),
            selectedFolderName: folderURL.lastPathComponent,
            totalFiles: results.count,
            totalBytes: totalBytes,
            files: results.sorted { $0.relativePath.localizedCaseInsensitiveCompare($1.relativePath) == .orderedAscending }
        )
    }

    private func classify(_ url: URL) -> FileCategory {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()

        if ext == "ff" { return .fastFile }
        if ["gsc", "csc", "cfg"].contains(ext) { return .script }
        if name == "eboot.bin" || ["self", "sprx"].contains(ext) { return .executable }
        if ["wav", "mp3", "at3", "at9", "wem", "xma"].contains(ext) { return .audio }
        if ["dds", "png", "jpg", "jpeg", "tga", "iwi"].contains(ext) { return .texture }
        if ["obj", "fbx", "dae", "xmodel_bin"].contains(ext) { return .model }
        if ["pak", "psarc", "zip"].contains(ext) { return .archive }
        if ["str", "csv", "json", "txt"].contains(ext) { return .localization }
        return .unknown
    }

    private func isLikelyZombies(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        let tokens = [
            "/zm_", "\\zm_", "zombie", "zombies", "tomb", "buried",
            "nuketown", "transit", "tranzit", "die_rise", "mob_of_the_dead",
            "origins", "greenrun", "town", "farm", "bus_depot"
        ]
        return tokens.contains { path.contains($0) }
    }
}
