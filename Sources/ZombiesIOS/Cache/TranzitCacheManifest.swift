import Foundation

struct TranzitSourceFingerprint: Codable, Equatable, Hashable, Sendable {
    let relativePath: String
    let byteCount: Int64
    let modifiedAt: Date
}

enum TranzitCacheValidationState: String, Codable, Sendable {
    case staging
    case valid
    case invalid
}

struct TranzitCacheManifest: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let sourceFingerprints: [TranzitSourceFingerprint]
    let surfaceCount: Int
    let vertexCount: Int
    let triangleCount: Int
    let materialCount: Int
    let textureTotal: Int
    let textureSucceeded: Int
    let textureFailed: Int
    let warnings: [String]
    let validationState: TranzitCacheValidationState
}
