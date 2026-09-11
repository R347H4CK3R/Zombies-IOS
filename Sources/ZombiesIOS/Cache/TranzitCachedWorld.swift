import Foundation
import simd

struct TranzitCachedMaterial: Codable, Equatable, Sendable {
    let id: Int
    let name: String
    let diffuseTexture: String?
    let normalTexture: String?
    let specularTexture: String?
    let alphaCutout: Bool
}

struct TranzitCachedSubmesh: Codable, Equatable, Sendable {
    let firstIndex: Int
    let indexCount: Int
    let materialID: Int
}

struct TranzitCachedWorld: Equatable, Sendable {
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let uvs: [SIMD2<Float>]
    let indices: [UInt32]
    let submeshes: [TranzitCachedSubmesh]
    let materials: [TranzitCachedMaterial]

    var triangleCount: Int { indices.count / 3 }
    var surfaceCount: Int { submeshes.count }
}
