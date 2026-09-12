import Foundation

enum ConvertedImportStage: String, Codable, CaseIterable, Hashable {
    case scanning
    case decodingWorld
    case convertingGeometry
    case convertingTextures
    case buildingCollision
    case convertingWeapon
    case validating
    case ready
}

struct ConvertedImportReport: Codable {
    static let relativePath = "diagnostics/import-report.json"

    let sourceFingerprint: ConvertedSourceFingerprint
    var completedStages: [ConvertedImportStage]
    var stageMessages: [String: String]
    var worldSourceFile: String?
    var worldVertexCount: Int?
    var worldIndexCount: Int?
    var convertedTextureCount: Int
    var materialFullFidelity: Bool
    var weaponSourceName: String?
    var lastError: String?
    var updatedAt: Date
}

struct ConvertedStagingState: Codable {
    static let fileName = "staging-state.json"

    let sourceFingerprint: ConvertedSourceFingerprint
    var completedStages: [ConvertedImportStage]
}
