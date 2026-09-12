import Foundation

enum RuntimeCachePolicy {
    enum CacheError: LocalizedError {
        case cachesDirectoryUnavailable

        var errorDescription: String? {
            switch self {
            case .cachesDirectoryUnavailable:
                return "The app cache directory is unavailable."
            }
        }
    }

    static func metadataDirectory(fileManager: FileManager = .default) throws -> URL {
        let root = try appRoot(fileManager: fileManager)
        let url = root.appendingPathComponent("metadata", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func expressiveDirectory(fileManager: FileManager = .default) throws -> URL {
        let root = try appRoot(fileManager: fileManager)
        let url = root.appendingPathComponent("runtime-expressive-cache", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func clearExpressiveCache(fileManager: FileManager = .default) throws {
        let root = try appRoot(fileManager: fileManager)
        let url = root.appendingPathComponent("runtime-expressive-cache", isDirectory: true)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private static func appRoot(fileManager: FileManager) throws -> URL {
        guard let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            throw CacheError.cachesDirectoryUnavailable
        }
        let root = caches.appendingPathComponent("ZombiesIOS", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
