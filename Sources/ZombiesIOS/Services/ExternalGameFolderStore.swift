import Foundation

struct ExternalGameFolderStore {
    enum StoreError: LocalizedError {
        case bookmarkCreationFailed
        case noSavedFolder
        case staleBookmark
        case cannotAccessFolder

        var errorDescription: String? {
            switch self {
            case .bookmarkCreationFailed:
                return "The selected game folder could not be remembered."
            case .noSavedFolder:
                return "No game folder has been saved yet."
            case .staleBookmark:
                return "Game folder access expired. Select the folder again."
            case .cannotAccessFolder:
                return "The saved game folder is no longer available."
            }
        }
    }

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = "BO2GameFolderBookmark") {
        self.defaults = defaults
        self.key = key
    }

    func save(folderURL: URL) throws {
        let accessed = folderURL.startAccessingSecurityScopedResource()
        defer { if accessed { folderURL.stopAccessingSecurityScopedResource() } }

        do {
            let bookmark = try folderURL.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(bookmark, forKey: key)
        } catch {
            throw StoreError.bookmarkCreationFailed
        }
    }

    func resolve() throws -> URL {
        guard let data = defaults.data(forKey: key) else {
            throw StoreError.noSavedFolder
        }

        var stale = false
        let url: URL
        do {
            url = try URL(
                resolvingBookmarkData: data,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
        } catch {
            throw StoreError.cannotAccessFolder
        }

        guard !stale else { throw StoreError.staleBookmark }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StoreError.cannotAccessFolder
        }
        return url
    }

    func withScopedAccess<T>(_ operation: (URL) async throws -> T) async throws -> T {
        let url = try resolve()
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw StoreError.cannotAccessFolder
        }
        return try await operation(url)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
