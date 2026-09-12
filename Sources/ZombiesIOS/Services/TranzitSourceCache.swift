import CryptoKit
import Foundation

struct TranzitSourceCacheResult {
    let copied: [TranzitDependency]
    let reused: [TranzitDependency]
    let removedRelativePaths: [String]
    let missingOptional: [TranzitDependency]
}

struct TranzitSourceCache {
    enum CacheError: LocalizedError {
        case requiredSourceMissing(String)
        case sourceVerificationFailed(String)
        case unsafeRelativePath(String)

        var errorDescription: String? {
            switch self {
            case .requiredSourceMissing(let path):
                return "Required Tranzit source file is missing: \(path)"
            case .sourceVerificationFailed(let path):
                return "Copied Tranzit source file failed verification: \(path)"
            case .unsafeRelativePath(let path):
                return "Unsafe Tranzit dependency path was rejected: \(path)"
            }
        }
    }

    private let fileManager: FileManager
    private let cacheRoot: URL

    init(fileManager: FileManager = .default, cacheRoot: URL? = nil) throws {
        self.fileManager = fileManager
        if let cacheRoot {
            self.cacheRoot = cacheRoot
        } else {
            self.cacheRoot = try RuntimeCachePolicy.tranzitSourceCacheRoot(fileManager: fileManager)
        }
        try fileManager.createDirectory(at: self.cacheRoot, withIntermediateDirectories: true)
    }

    func prepare(manifest: TranzitDependencyManifest, sourceRoot: URL) async throws -> TranzitSourceCacheResult {
        var copied: [TranzitDependency] = []
        var reused: [TranzitDependency] = []
        var missingOptional: [TranzitDependency] = []

        let allowedPaths = Set(manifest.entries.map { $0.normalizedRelativePath })
        let removed = try removeStaleFiles(allowedRelativePaths: allowedPaths)

        for dependency in manifest.entries {
            guard !dependency.hasUnsafeAbsoluteOrTraversalPath else {
                throw CacheError.unsafeRelativePath(dependency.relativePath)
            }

            let relative = dependency.normalizedRelativePath
            let source = sourceRoot.appendingPathComponent(relative, isDirectory: false)
            let destination = cacheRoot.appendingPathComponent(relative, isDirectory: false)

            guard fileManager.fileExists(atPath: source.path) else {
                switch dependency.requirement {
                case .required:
                    throw CacheError.requiredSourceMissing(relative)
                case .optional, .deferred:
                    missingOptional.append(dependency)
                    continue
                }
            }

            if try isReusable(destination: destination, dependency: dependency) {
                reused.append(dependency)
                continue
            }

            try copyVerified(source: source, destination: destination, dependency: dependency)
            copied.append(dependency)
        }

        try persist(manifest: manifest)
        return TranzitSourceCacheResult(copied: copied, reused: reused, removedRelativePaths: removed, missingOptional: missingOptional)
    }

    private func isReusable(destination: URL, dependency: TranzitDependency) throws -> Bool {
        guard fileManager.fileExists(atPath: destination.path) else { return false }
        let values = try destination.resourceValues(forKeys: [.fileSizeKey])
        guard Int64(values.fileSize ?? -1) == dependency.byteCount else { return false }
        return try sha256(of: destination).caseInsensitiveCompare(dependency.sha256) == .orderedSame
    }

    private func copyVerified(source: URL, destination: URL, dependency: TranzitDependency) throws {
        let parent = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

        let temp = parent.appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        try? fileManager.removeItem(at: temp)
        try fileManager.copyItem(at: source, to: temp)

        do {
            let values = try temp.resourceValues(forKeys: [.fileSizeKey])
            let hash = try sha256(of: temp)
            guard Int64(values.fileSize ?? -1) == dependency.byteCount,
                  hash.caseInsensitiveCompare(dependency.sha256) == .orderedSame else {
                throw CacheError.sourceVerificationFailed(dependency.normalizedRelativePath)
            }

            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(destination, withItemAt: temp)
            } else {
                try fileManager.moveItem(at: temp, to: destination)
            }
        } catch {
            try? fileManager.removeItem(at: temp)
            throw error
        }
    }

    private func removeStaleFiles(allowedRelativePaths: Set<String>) throws -> [String] {
        guard let enumerator = fileManager.enumerator(at: cacheRoot, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        var removed: [String] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            let relative = relativePath(of: url, from: cacheRoot)
            guard relative != "manifest.json", !allowedRelativePaths.contains(relative) else { continue }
            try fileManager.removeItem(at: url)
            removed.append(relative)
        }
        return removed.sorted()
    }

    private func persist(manifest: TranzitDependencyManifest) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)
        let destination = cacheRoot.appendingPathComponent("manifest.json")
        let temp = cacheRoot.appendingPathComponent(".manifest.\(UUID().uuidString).tmp")
        try data.write(to: temp, options: .atomic)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temp)
        } else {
            try fileManager.moveItem(at: temp, to: destination)
        }
    }

    private func relativePath(of file: URL, from root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
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
