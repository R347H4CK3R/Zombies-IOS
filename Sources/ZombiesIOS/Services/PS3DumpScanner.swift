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
    private let readChunkSize = 1024 * 1024
    private let maxReferencesPerFile = 1000
    private let maxReferenceLength = 180

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

            let size = coordinatedRobustFileSize(for: fileURL, resourceValues: values)
            totalBytes += size
            let inspection = size > 0 ? inspectContainer(at: fileURL, size: size) : nil
            results.append(makeScannedFile(path: relative, size: size, inspection: inspection))
        }

        guard !results.isEmpty else { throw ScannerError.noManifestMatches }
        return makeReport(name: folderURL.lastPathComponent, results: results, totalBytes: totalBytes)
    }

    /// ZIP scanning remains metadata-only. Direct-folder imports are the preferred
    /// path for deep container inspection because the files are materialized locally.
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
            let scanned = makeScannedFile(path: entry.path, size: size, inspection: nil)

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

    private func inspectContainer(at fileURL: URL, size: Int64) -> ContainerInspection? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        var header = Data()
        var totalRead: Int64 = 0
        var refs: [AssetReference] = []
        var seen = Set<String>()
        var pending = [UInt8]()
        var pendingOffset: Int64 = 0
        var discardingOversizedToken = false

        func flushPending() {
            guard pending.count >= 4 else {
                pending.removeAll(keepingCapacity: true)
                return
            }

            let bytes = pending.prefix(maxReferenceLength)
            guard let token = String(bytes: bytes, encoding: .ascii)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  token.count >= 4,
                  looksLikeAssetReference(token) else {
                pending.removeAll(keepingCapacity: true)
                return
            }

            let normalized = token.replacingOccurrences(of: "\\", with: "/")
            let key = normalized.lowercased()
            if !seen.contains(key), refs.count < maxReferencesPerFile {
                seen.insert(key)
                refs.append(
                    AssetReference(
                        name: normalized,
                        kind: classifyAssetReference(normalized),
                        offset: pendingOffset
                    )
                )
            }
            pending.removeAll(keepingCapacity: true)
            discardingOversizedToken = false
        }

        while true {
            guard let chunk = try? handle.read(upToCount: readChunkSize), !chunk.isEmpty else {
                break
            }

            if header.count < 64 {
                header.append(chunk.prefix(64 - header.count))
            }

            let bytes = [UInt8](chunk)
            for (index, byte) in bytes.enumerated() {
                let absoluteOffset = totalRead + Int64(index)
                // Carve candidate identifiers on BO2-name characters instead of
                // every printable byte. The old logic merged valid names with nearby
                // spaces/punctuation into one rejected string, which hid references.
                if isAssetTokenByte(byte) {
                    if discardingOversizedToken { continue }
                    if pending.isEmpty { pendingOffset = absoluteOffset }
                    if pending.count < maxReferenceLength {
                        pending.append(byte)
                    } else {
                        // Ignore a clearly oversized printable/binary run until the
                        // next delimiter instead of emitting misleading fragments.
                        pending.removeAll(keepingCapacity: true)
                        discardingOversizedToken = true
                    }
                } else {
                    if discardingOversizedToken {
                        pending.removeAll(keepingCapacity: true)
                        discardingOversizedToken = false
                    } else {
                        flushPending()
                    }
                }
            }

            // BO2 metadata occasionally stores identifiers as UTF-16LE. The byte-wise
            // ASCII pass above cannot see those because every character is separated by
            // a zero byte, so carve wide-string candidates from both possible alignments.
            carveUTF16LEReferences(
                bytes: bytes,
                baseOffset: totalRead,
                refs: &refs,
                seen: &seen
            )

            totalRead += Int64(chunk.count)
        }

        flushPending()

        let headerHex = header.prefix(32).map { String(format: "%02X", $0) }.joined(separator: " ")
        let headerASCII = header.prefix(32).map { byte -> Character in
            if isPrintableASCII(byte) {
                return Character(UnicodeScalar(byte))
            }
            return "."
        }

        return ContainerInspection(
            detectedFormat: detectFormat(fileURL: fileURL, header: header),
            headerHex: headerHex,
            headerASCII: String(headerASCII),
            bytesInspected: totalRead,
            embeddedAssetReferences: refs
        )
    }

    private func detectFormat(fileURL: URL, header: Data) -> String {
        let ext = fileURL.pathExtension.lowercased()
        let bytes = [UInt8](header.prefix(16))
        let ascii = String(bytes: header.prefix(16), encoding: .ascii) ?? ""

        if bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]) { return "ZIP" }
        if ascii.hasPrefix("SABS") { return "SABS audio bank" }
        if ascii.hasPrefix("SABL") { return "SABL audio bank" }
        if ascii.uppercased().contains("IPAK") || ext == "ipak" { return "BO2 IPAK archive" }
        if ext == "ff" { return "BO2 FastFile" }
        if ext == "sabs" { return "BO2 SABS audio bank" }
        if ext == "sabl" { return "BO2 SABL audio bank" }
        return ext.isEmpty ? "unknown" : ext.uppercased()
    }

    private func carveUTF16LEReferences(
        bytes: [UInt8],
        baseOffset: Int64,
        refs: inout [AssetReference],
        seen: inout Set<String>
    ) {
        guard bytes.count >= 8, refs.count < maxReferencesPerFile else { return }

        for alignment in 0...1 {
            var token: [UInt8] = []
            var tokenOffset: Int64 = 0
            var i = alignment

            func flush() {
                defer { token.removeAll(keepingCapacity: true) }
                guard token.count >= 4,
                      let raw = String(bytes: token.prefix(maxReferenceLength), encoding: .ascii)?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                      looksLikeAssetReference(raw) else { return }

                let normalized = raw.replacingOccurrences(of: "\\", with: "/")
                let key = normalized.lowercased()
                guard !seen.contains(key), refs.count < maxReferencesPerFile else { return }
                seen.insert(key)
                refs.append(
                    AssetReference(
                        name: normalized,
                        kind: classifyAssetReference(normalized),
                        offset: tokenOffset
                    )
                )
            }

            while i + 1 < bytes.count {
                let lo = bytes[i]
                let hi = bytes[i + 1]

                if hi == 0 && isAssetTokenByte(lo) {
                    if token.isEmpty { tokenOffset = baseOffset + Int64(i) }
                    if token.count < maxReferenceLength {
                        token.append(lo)
                    } else {
                        token.removeAll(keepingCapacity: true)
                    }
                    i += 2
                    continue
                }

                flush()
                i += 2
            }
            flush()
        }
    }

    private func looksLikeAssetReference(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 4, trimmed.count <= maxReferenceLength else { return false }

        // BO2 asset identifiers in these containers are conventionally lowercase
        // ASCII paths/names. Requiring that shape eliminates printable binary noise
        // such as "zM_!XW", "W.ddS", "J.fF", and "?1.Ff".
        guard trimmed == trimmed.lowercased() else { return false }

        let value = trimmed.replacingOccurrences(of: "\\", with: "/")
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_./-")
        guard value.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        guard value.rangeOfCharacter(from: .letters) != nil else { return false }
        guard !value.contains(".."), !value.hasPrefix("."), !value.hasSuffix(".") else { return false }

        let extensions = [
            ".iwi", ".dds", ".png", ".jpg", ".tga",
            ".wav", ".mp3", ".xma", ".wem", ".sabs", ".sabl",
            ".gsc", ".csc", ".cfg", ".csv", ".str",
            ".xmodel_bin", ".xanim_bin", ".ff", ".ipak"
        ]

        if let ext = extensions.first(where: value.hasSuffix) {
            let stem = String(value.dropLast(ext.count))
            guard stem.count >= 4 else { return false }

            // Very short extension-bearing strings are common accidental matches
            // in compressed/binary payloads. Keep them only when their naming shape
            // clearly resembles a known BO2 asset family or contains a real path.
            if value.count < 9 && !value.contains("/") {
                let knownPrefixes = [
                    "zm_", "zmb_", "weapon_", "wpn_", "xmodel_", "xanim_",
                    "material_", "snd_", "sound_", "transit_", "ui_", "code_",
                    "common_", "patch_", "so_"
                ]
                guard knownPrefixes.contains(where: value.hasPrefix) else { return false }
            }
            return true
        }

        if value.contains("/") {
            let keywords = [
                "weapon", "xmodel", "xanim", "material", "image", "sound",
                "zombie", "zm_", "transit", "script", "maps/"
            ]
            return keywords.contains(where: value.contains)
        }

        // Bare identifiers are where compressed/binary payloads produce the most
        // accidental matches. Require enough structure to distinguish real BO2 names
        // from tiny fragments such as "zm_v", "zm_s", or "zm_h".
        guard value.count >= 6 else { return false }

        let keywords = [
            "weapon_", "wpn_", "xmodel_", "xanim_", "material_", "image_",
            "zombie_", "zmb_", "zm_", "transit_", "snd_", "sound_",
            "script_", "maps_", "ui_", "code_", "common_", "patch_", "so_"
        ]
        guard keywords.contains(where: value.hasPrefix) else { return false }

        if value.hasPrefix("zm_") {
            let remainder = String(value.dropFirst(3))
            guard remainder.count >= 3 else { return false }
        }
        return true
    }

    private func classifyAssetReference(_ raw: String) -> String {
        let value = raw.lowercased()
        if value.contains("weapon") || value.contains("/wpn") || value.hasPrefix("wpn_") { return "weapon" }
        if value.contains("xmodel") || value.hasSuffix(".xmodel_bin") { return "model" }
        if value.contains("xanim") || value.hasSuffix(".xanim_bin") { return "animation" }
        if value.contains("material") { return "material" }
        if [".iwi", ".dds", ".png", ".jpg", ".tga"].contains(where: value.hasSuffix) { return "texture" }
        if [".wav", ".mp3", ".xma", ".wem", ".sabs", ".sabl"].contains(where: value.hasSuffix) || value.contains("sound") || value.hasPrefix("snd_") { return "audio" }
        if [".gsc", ".csc", ".cfg"].contains(where: value.hasSuffix) || value.contains("script") { return "script" }
        if value.contains("zombie") || value.contains("zm_") || value.contains("transit") || value.contains("maps/") { return "map/gameplay" }
        if value.hasSuffix(".ff") || value.hasSuffix(".ipak") { return "container" }
        return "unknown"
    }

    private func isPrintableASCII(_ byte: UInt8) -> Bool {
        byte >= 0x20 && byte <= 0x7E
    }

    private func isAssetTokenByte(_ byte: UInt8) -> Bool {
        switch byte {
        case 0x61...0x7A, 0x30...0x39: // a-z, 0-9
            return true
        case 0x5F, 0x2E, 0x2F, 0x5C, 0x2D: // _ . / \\ -
            return true
        default:
            return false
        }
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

        return robustFileSize(for: fileURL, resourceValues: resourceValues)
    }

    private func robustFileSize(
        for fileURL: URL,
        resourceValues: URLResourceValues?
    ) -> Int64 {
        var candidates: [Int64] = []

        if let value = resourceValues?.fileSize { candidates.append(Int64(value)) }
        if let value = resourceValues?.totalFileAllocatedSize { candidates.append(Int64(value)) }
        if let value = resourceValues?.fileAllocatedSize { candidates.append(Int64(value)) }

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

        if let handle = try? FileHandle(forReadingFrom: fileURL) {
            defer { try? handle.close() }

            if let firstByte = try? handle.read(upToCount: 1), firstByte.isEmpty == false {
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

    private func makeScannedFile(path: String, size: Int64, inspection: ContainerInspection?) -> ScannedFile {
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
            isLikelyZombiesContent: true,
            inspection: inspection
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
