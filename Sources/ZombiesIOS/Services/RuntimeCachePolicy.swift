import Foundation

enum RuntimeCachePolicy {
    enum CacheError: LocalizedError {
        case cachesDirectoryUnavailable
        case applicationSupportDirectoryUnavailable

        var errorDescription: String? {
            switch self {
            case .cachesDirectoryUnavailable:
                return "The app cache directory is unavailable."
            case .applicationSupportDirectoryUnavailable:
                return "The app application-support directory is unavailable."
            }
        }
    }

    static let runtimeArtifactSchemaVersion = 1
    static let t6DecoderVersion = 1

    static func metadataDirectory(fileManager: FileManager = .default) throws -> URL {
        let root = try cacheRoot(fileManager: fileManager)
        let url = root.appendingPathComponent("metadata", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func expressiveDirectory(fileManager: FileManager = .default) throws -> URL {
        let root = try cacheRoot(fileManager: fileManager)
        let url = root.appendingPathComponent("runtime-expressive-cache", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func tranzitSourceCacheRoot(fileManager: FileManager = .default) throws -> URL {
        let root = try applicationSupportRoot(fileManager: fileManager)
        let url = root
            .appendingPathComponent("SourceCache", isDirectory: true)
            .appendingPathComponent("Tranzit", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func tranzitRuntimeCacheRoot(fileManager: FileManager = .default) throws -> URL {
        let root = try applicationSupportRoot(fileManager: fileManager)
        let url = root
            .appendingPathComponent("RuntimeCache", isDirectory: true)
            .appendingPathComponent("Tranzit", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func runtimeArtifactVersionKey(sourceSHA256: String) -> String {
        "\(sourceSHA256.lowercased())-decoder\(t6DecoderVersion)-schema\(runtimeArtifactSchemaVersion)"
    }

    static func clearExpressiveCache(fileManager: FileManager = .default) throws {
        let root = try cacheRoot(fileManager: fileManager)
        let url = root.appendingPathComponent("runtime-expressive-cache", isDirectory: true)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    static func clearTranzitRuntimeCache(fileManager: FileManager = .default) throws {
        let root = try applicationSupportRoot(fileManager: fileManager)
        let url = root
            .appendingPathComponent("RuntimeCache", isDirectory: true)
            .appendingPathComponent("Tranzit", isDirectory: true)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private static func cacheRoot(fileManager: FileManager) throws -> URL {
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw CacheError.cachesDirectoryUnavailable
        }
        let root = caches.appendingPathComponent("ZombiesIOS", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func applicationSupportRoot(fileManager: FileManager) throws -> URL {
        guard let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CacheError.applicationSupportDirectoryUnavailable
        }
        let root = support.appendingPathComponent("ZombiesIOS", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
