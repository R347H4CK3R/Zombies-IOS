import Foundation

actor DirectFolderImporter {
    struct Result {
        let report: ScanReport
        let importedAssetsURL: URL?
    }

    enum ImportError: LocalizedError {
        case cannotAccessFolder
        case unableToEnumerate
        case noManifestMatches

        var errorDescription: String? {
            switch self {
            case .cannotAccessFolder:
                return "The selected BO2 folder could not be accessed."
            case .unableToEnumerate:
                return "The selected BO2 folder could not be enumerated."
            case .noManifestMatches:
                return "No BO2 Zombies manifest files were found in the selected folder."
            }
        }
    }

    private let scanner = PS3DumpScanner()

    func importFolder(_ folderURL: URL) async throws -> Result {
        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        let fm = FileManager.default
        guard fm.fileExists(atPath: folderURL.path) else {
            throw ImportError.cannotAccessFolder
        }

        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = appSupport.appendingPathComponent("ImportedAssets", isDirectory: true)
        let staging = root.appendingPathComponent("staging-\(UUID().uuidString)", isDirectory: true)
        let current = root.appendingPathComponent("current", isDirectory: true)

        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        let keys: [URLResourceKey] = [.isRegularFileKey, .nameKey]
        guard let enumerator = fm.enumerator(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            try? fm.removeItem(at: staging)
            throw ImportError.unableToEnumerate
        }

        var matchedCount = 0

        while let next = enumerator.nextObject() {
            guard let sourceURL = next as? URL else { continue }
            let values = try? sourceURL.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }

            let relative = relativePath(of: sourceURL, under: folderURL)
            guard let canonical = canonicalManifestPath(for: relative, fileName: sourceURL.lastPathComponent) else {
                continue
            }

            let destination = staging.appendingPathComponent(canonical)
            try fm.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let copiedBytes = coordinatedMaterialize(sourceURL, to: destination)

            // A manifest filename is not usable unless its payload was actually
            // materialized. Never manufacture zero-byte placeholders: they make
            // an incomplete BO2 dump look more complete than it really is.
            guard copiedBytes > 0 else {
                try? fm.removeItem(at: destination)
                continue
            }

            matchedCount += 1
        }

        guard matchedCount > 0 else {
            try? fm.removeItem(at: staging)
            throw ImportError.noManifestMatches
        }

        let report = try await scanner.scan(folderURL: staging)

        // Runtime imports are now progressive: once BO2 files were physically
        // materialized and inspected, keep them even when the legacy manifest
        // is not 100% complete. This lets native runtime work move forward with
        // the verified Tranzit payload already present instead of repeatedly
        // filtering/rescanning the same source dump.
        if fm.fileExists(atPath: current.path) {
            try fm.removeItem(at: current)
        }
        try fm.moveItem(at: staging, to: current)
        return Result(report: report, importedAssetsURL: current)
    }

    private func coordinatedMaterialize(_ sourceURL: URL, to destination: URL) -> Int64 {
        let fm = FileManager.default
        var bytesWritten: Int64 = 0
        var expectedBytes: Int64?
        var coordinationError: NSError?
        let coordinator = NSFileCoordinator()

        coordinator.coordinate(
            readingItemAt: sourceURL,
            options: [.withoutChanges],
            error: &coordinationError
        ) { coordinatedURL in
            do {
                if let attributes = try? fm.attributesOfItem(atPath: coordinatedURL.path),
                   let number = attributes[.size] as? NSNumber,
                   number.int64Value > 0 {
                    expectedBytes = number.int64Value
                }

                if fm.fileExists(atPath: destination.path) {
                    try fm.removeItem(at: destination)
                }
                fm.createFile(atPath: destination.path, contents: nil)

                let input = try FileHandle(forReadingFrom: coordinatedURL)
                let output = try FileHandle(forWritingTo: destination)
                defer {
                    try? input.close()
                    try? output.close()
                }

                while true {
                    let chunk = try input.read(upToCount: 1024 * 1024) ?? Data()
                    if chunk.isEmpty { break }
                    try output.write(contentsOf: chunk)
                    bytesWritten += Int64(chunk.count)
                }
                try output.synchronize()
            } catch {
                bytesWritten = 0
                try? fm.removeItem(at: destination)
            }
        }

        if coordinationError != nil && bytesWritten == 0 {
            try? fm.removeItem(at: destination)
        }

        if let expectedBytes, expectedBytes != bytesWritten {
            try? fm.removeItem(at: destination)
            return 0
        }

        return bytesWritten
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

    private func canonicalManifestPath(for path: String, fileName: String) -> String? {
        let normalized = normalize(path)

        if let range = normalized.range(of: "ps3_game/") {
            let candidate = String(normalized[range.lowerBound...])
            if let match = manifestMatch(candidate) { return match }
        }

        if normalized.hasPrefix("usrdir/"),
           let match = manifestMatch("ps3_game/" + normalized) {
            return match
        }

        if normalized.hasPrefix("english/"),
           let match = manifestMatch("ps3_game/usrdir/" + normalized) {
            return match
        }

        if let match = manifestMatch(normalized) {
            return match
        }

        // Also support selecting the english folder directly. Basename
        // fallback is safe only when that filename is unique in the manifest.
        let lowerName = fileName.lowercased()
        let byName = BO2ZombiesManifest.relativePaths.filter {
            ($0 as NSString).lastPathComponent.lowercased() == lowerName
        }
        return byName.count == 1 ? byName.first : nil
    }

    private func manifestMatch(_ candidate: String) -> String? {
        let normalizedCandidate = normalize(candidate)
        return BO2ZombiesManifest.relativePaths.first {
            normalize($0) == normalizedCandidate
        }
    }

    private func normalize(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }
}
