import Foundation
import simd

struct RuntimeBoneWeight: Codable, Hashable {
    let boneIndex: Int
    let weight: Float
}

struct RuntimeModelVertex: Codable {
    let position: SIMD3<Float>
    let normal: SIMD3<Float>
    let uv: SIMD2<Float>
    let boneWeights: [RuntimeBoneWeight]
}

struct RuntimeModelBone: Codable {
    let name: String
    let parentIndex: Int?
    let bindTranslation: SIMD3<Float>
    let bindRotation: SIMD4<Float>
}

struct RuntimeModelSurface: Codable {
    let firstIndex: Int
    let indexCount: Int
    let materialIndex: Int
}

struct RuntimeModel: Codable {
    let id: String
    let vertices: [RuntimeModelVertex]
    let indices: [UInt32]
    let bones: [RuntimeModelBone]
    let surfaces: [RuntimeModelSurface]
    let materialIDs: [String]

    func validate() throws {
        guard !id.isEmpty else { throw RuntimeModelError.invalidID }
        guard indices.allSatisfy({ Int($0) < vertices.count }) else { throw RuntimeModelError.indexOutOfRange }
        for vertex in vertices {
            let sum = vertex.boneWeights.reduce(Float.zero) { $0 + $1.weight }
            guard vertex.boneWeights.allSatisfy({ $0.boneIndex >= 0 && $0.boneIndex < bones.count && $0.weight >= 0 }) else {
                throw RuntimeModelError.invalidBoneWeight
            }
            if !vertex.boneWeights.isEmpty && abs(sum - 1) > 0.02 { throw RuntimeModelError.invalidBoneWeight }
        }
        guard surfaces.allSatisfy({ $0.firstIndex >= 0 && $0.indexCount >= 0 && $0.firstIndex + $0.indexCount <= indices.count && $0.materialIndex >= 0 && $0.materialIndex < materialIDs.count }) else {
            throw RuntimeModelError.invalidSurface
        }
    }
}

enum RuntimeModelError: Error {
    case invalidID
    case indexOutOfRange
    case invalidBoneWeight
    case invalidSurface
}
