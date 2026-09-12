import Foundation

struct ConvertedMaterialRecord: Codable, Equatable {
    let id: Int
    let name: String
    let diffuseTexturePath: String?
    let fallbackReason: String?
    let doubleSided: Bool
}

struct ConvertedMaterialManifest: Codable, Equatable {
    let materials: [ConvertedMaterialRecord]
    let fullFidelity: Bool

    var convertedTextureCount: Int {
        materials.compactMap(\.diffuseTexturePath).count
    }
}

struct ConvertedMaterialSource {
    let id: Int
    let name: String
    let encodedImageData: Data?
    let doubleSided: Bool
}
