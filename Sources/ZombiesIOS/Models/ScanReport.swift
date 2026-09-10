import Foundation

struct AssetReference: Codable, Hashable {
    let name: String
    let kind: String
    let offset: Int64
}

struct ContainerInspection: Codable, Hashable {
    let detectedFormat: String
    let headerHex: String
    let headerASCII: String
    let bytesInspected: Int64
    let embeddedAssetReferences: [AssetReference]

    var assetReferenceCount: Int { embeddedAssetReferences.count }
}

struct ScannedFile: Codable, Identifiable, Hashable {
    var id: String { relativePath }
    let relativePath: String
    let name: String
    let fileExtension: String
    let size: Int64
    let category: FileCategory
    let isLikelyZombiesContent: Bool
    let inspection: ContainerInspection?
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

    var zeroByteFiles: [ScannedFile] {
        files.filter { $0.size == 0 }
    }

    var missingManifestCount: Int {
        max(0, BO2ZombiesManifest.relativePaths.count - totalFiles)
    }

    var inspectedFileCount: Int {
        files.filter { $0.inspection != nil }.count
    }

    var embeddedAssetReferenceCount: Int {
        files.reduce(0) { $0 + ($1.inspection?.assetReferenceCount ?? 0) }
    }

    var isBuildReady: Bool {
        missingManifestCount == 0 && zeroByteFiles.isEmpty
    }
}
