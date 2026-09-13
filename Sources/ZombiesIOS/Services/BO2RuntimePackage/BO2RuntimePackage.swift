import Foundation
import simd

struct BO2RuntimeVertex: Codable, Equatable, Sendable {
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

struct BO2RuntimeSurface: Codable, Equatable, Sendable {
    let firstIndex: UInt32
    let indexCount: UInt32
    let materialID: UInt32
}

struct BO2RuntimeEntity: Codable, Equatable, Sendable {
    let properties: [String: String]

    var classname: String { properties["classname"] ?? "" }
}

struct BO2RuntimeSpawn: Codable, Equatable, Sendable {
    let classname: String
    let origin: BO2RuntimeVertex
    let yawDegrees: Float
}

struct BO2RuntimeBounds: Codable, Equatable, Sendable {
    let min: BO2RuntimeVertex
    let max: BO2RuntimeVertex
}

struct BO2RuntimePackage: Equatable, Sendable {
    static let formatVersion: UInt32 = 1

    let sourceName: String
    let sourceSHA256: String
    let vertices: [BO2RuntimeVertex]
    let indices: [UInt32]
    let surfaces: [BO2RuntimeSurface]
    let entities: [BO2RuntimeEntity]
    let spawns: [BO2RuntimeSpawn]
    let bounds: BO2RuntimeBounds

    var triangleCount: Int { indices.count / 3 }

    /// Canonical BO2 (Z-up) to native runtime (Y-up) transform.
    /// This transform is also used for entity origins and collision geometry.
    static func bo2ToRuntime(_ value: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(value.x, value.z, -value.y)
    }

    static func bounds(for vertices: [BO2RuntimeVertex]) -> BO2RuntimeBounds? {
        guard let first = vertices.first else { return nil }
        var minV = first.simd
        var maxV = first.simd
        for vertex in vertices.dropFirst() {
            let v = vertex.simd
            minV = SIMD3<Float>(min(minV.x, v.x), min(minV.y, v.y), min(minV.z, v.z))
            maxV = SIMD3<Float>(max(maxV.x, v.x), max(maxV.y, v.y), max(maxV.z, v.z))
        }
        return BO2RuntimeBounds(min: BO2RuntimeVertex(minV), max: BO2RuntimeVertex(maxV))
    }
}

struct BO2RuntimePackageMetadata: Codable, Equatable, Sendable {
    let formatVersion: UInt32
    let sourceName: String
    let sourceSHA256: String
    let vertexCount: Int
    let indexCount: Int
    let triangleCount: Int
    let verticesFile: String
    let indicesFile: String
    let surfaces: [BO2RuntimeSurface]
    let entities: [BO2RuntimeEntity]
    let spawns: [BO2RuntimeSpawn]
    let bounds: BO2RuntimeBounds
}
