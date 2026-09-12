import CryptoKit
import Foundation

struct TranzitDependencyResolver {
    enum ResolverError: LocalizedError {
        case sourceUnavailable
        case requiredTranzitZoneMissing

        var errorDescription: String? {
            switch self {
            case .sourceUnavailable:
                return "The selected BO2 source folder is unavailable."
            case .requiredTranzitZoneMissing:
                return "The required Tranzit zone file zm_transit.ff was not found."
            }
        }
    }

    private struct Candidate {
        let fileName: String
        let role: TranzitDependencyRole
        let requirement: TranzitDependencyRequirement
    }

    private let candidates: [Candidate] = [
        Candidate(fileName: "zm_transit.ff", role: .zone, requirement: .required),
        Candidate(fileName: "common_zm.ff", role: .sharedZone, requirement: .optional),
        Candidate(fileName: "zm_transit_patch.ff", role: .zone, requirement: .optional),
        Candidate(fileName: "patch_zm.ff", role: .sharedZone, requirement: .optional)
    ]

    func initialManifest(sourceRoot: URL) async throws -> TranzitDependencyManifest {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: sourceRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ResolverError.sourceUnavailable
        }

        let discovered = try discoverCandidates(sourceRoot: sourceRoot, fileManager: fm)
        guard discovered["zm_transit.ff"] != nil else {
            throw ResolverError.requiredTranzitZoneMissing
        }

        var dependencies: [TranzitDependency] = []
        for candidate in candidates {
            guard let url = discovered[candidate.fileName.lowercased()] else { continue }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let hash = try sha256(of: url)
            let relativePath = relativePath(of: url, from: sourceRoot)
            dependencies.append(
                TranzitDependency(
                    relativePath: relativePath,
                    role: candidate.role,
                    requirement: candidate.requirement,
                    byteCount: Int64(values.fileSize ?? 0),
                    sha256: hash,
                    modifiedAt: values.contentModificationDate
                )
            )
        }

        return TranzitDependencyManifest(entries: dependencies)
    }

    private func discoverCandidates(sourceRoot: URL, fileManager: FileManager) throws -> [String: URL] {
        let wanted = Set(candidates.map { $0.fileName.lowercased() })
        let keys: [URLResourceKey] = [.isRegularFileKey, .nameKey]
        guard let enumerator = fileManager.enumerator(
            at: sourceRoot,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw ResolverError.sourceUnavailable
        }

        var matches: [String: URL] = [:]
        for case let url as URL in enumerator {
            let name = url.lastPathComponent.lowercased()
            guard wanted.contains(name), matches[name] == nil else { continue }
            let values = try url.resourceValues(forKeys: Set(keys))
            guard values.isRegularFile == true else { continue }
            matches[name] = url
            if matches.keys.count == wanted.count { break }
        }
        return matches
    }

    private func relativePath(of file: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath) else { return file.lastPathComponent }
        let suffix = filePath.dropFirst(rootPath.count)
        return String(suffix).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
