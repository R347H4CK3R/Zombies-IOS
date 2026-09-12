import Foundation

struct T6WorldSurface: Hashable, Sendable {
    let vertices: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let uvs: [SIMD2<Float>]
    let indices: [UInt32]
    let materialID: T6AssetID?
    let rawMaterialPointer: UInt32
    let sourceSurfaceIndex: Int
}

struct T6WorldSurfaceSet: Sendable {
    let surfaces: [T6WorldSurface]
    let sourceSurfaceTableOffset: Int
    let vertexStreamOffset: Int
    let indexStreamOffset: Int
    let usesDiagnosticGeometry: Bool

    var triangleCount: Int {
        surfaces.reduce(0) { $0 + ($1.indices.count / 3) }
    }

    var vertexCount: Int {
        surfaces.reduce(0) { $0 + $1.vertices.count }
    }

    var realMaterialSurfaceCount: Int {
        surfaces.reduce(0) { $0 + ($1.materialID == nil ? 0 : 1) }
    }
}
