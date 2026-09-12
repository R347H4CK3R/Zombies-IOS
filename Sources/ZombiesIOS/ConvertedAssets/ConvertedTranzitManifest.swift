import Foundation

struct ConvertedFloat3: Codable, Equatable {
    let x: Float
    let y: Float
    let z: Float

    init(_ value: SIMD3<Float>) {
        x = value.x
        y = value.y
        z = value.z
    }

    var simd: SIMD3<Float> { SIMD3<Float>(x, y, z) }
}

struct ConvertedTranzitManifest: Codable {
    static let packageFormatVersion = 1

    let formatVersion: Int
    let sourceFingerprint: ConvertedSourceFingerprint
    let sourceAreaName: String
    let createdAt: Date
    let converterBuild: String
    let worldMeshPath: String
    let collisionMeshPath: String
    let materialManifestPath: String
    let weaponMeshPath: String
    let convertedTextureCount: Int
    let vertexCount: Int
    let indexCount: Int
    let worldBoundsMin: ConvertedFloat3
    let worldBoundsMax: ConvertedFloat3
    let complete: Bool
    let stageDiagnostics: [String: String]
}
