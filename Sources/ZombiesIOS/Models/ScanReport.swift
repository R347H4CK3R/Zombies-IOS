import Foundation

struct ScannedFile: Codable, Identifiable, Hashable {
    var id: String { relativePath }
    let relativePath: String
    let name: String
    let fileExtension: String
    let size: Int64
    let category: FileCategory
    let isLikelyZombiesContent: Bool
}

enum FileCategory: String, Codable, CaseIterable {
    case fastFile
    case script
    case executable
    case audio
    case texture
    case model
    case archive
    case localization
    case unknown
}

struct ScanReport: Codable {
    let createdAt: Date
    let selectedFolderName: String
    let totalFiles: Int
    let totalBytes: Int64
    let files: [ScannedFile]

    var zombiesCandidates: [ScannedFile] {
        files.filter(\.isLikelyZombiesContent)
    }
}
