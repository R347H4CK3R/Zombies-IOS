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

    var incompleteReadFiles: [ScannedFile] {
        files.filter { file in
            guard file.size > 0, let inspection = file.inspection else { return false }
            return inspection.bytesInspected != file.size
        }
    }

    var uninspectedContainerFiles: [ScannedFile] {
        let deepInspectionExtensions: Set<String> = ["ff", "ipak", "sabs", "sabl"]
        return files.filter {
            $0.size > 0 && deepInspectionExtensions.contains($0.fileExtension) && $0.inspection == nil
        }
    }

    var formatMismatchFiles: [ScannedFile] {
        files.filter { file in
            guard let format = file.inspection?.detectedFormat.lowercased() else { return false }
            switch file.fileExtension {
            case "ff": return !format.contains("fastfile")
            case "ipak": return !format.contains("ipak")
            case "sabs": return !format.contains("sabs")
            case "sabl": return !format.contains("sabl")
            default: return false
            }
        }
    }

    var integrityIssueCount: Int {
        zeroByteFiles.count + incompleteReadFiles.count + uninspectedContainerFiles.count + formatMismatchFiles.count
    }

    var isBuildReady: Bool {
        missingManifestCount == 0 &&
        zeroByteFiles.isEmpty &&
        incompleteReadFiles.isEmpty &&
        uninspectedContainerFiles.isEmpty &&
        formatMismatchFiles.isEmpty
    }
}
