import Foundation
import simd

enum CIRuntimeMeshFixture {
    static func make() -> T6RuntimeMesh {
        let vertices: [SIMD3<Float>] = [
            SIMD3(-8, 0, -8), SIMD3(8, 0, -8), SIMD3(8, 0, 8), SIMD3(-8, 0, 8),
            SIMD3(-4, 6, -4), SIMD3(4, 6, -4), SIMD3(4, 6, 4), SIMD3(-4, 6, 4)
        ]
        let indices: [UInt16] = [
            0,2,1, 0,3,2,
            0,1,5, 0,5,4,
            1,2,6, 1,6,5,
            2,3,7, 2,7,6,
            3,0,4, 3,4,7,
            4,5,6, 4,6,7
        ]
        return T6RuntimeMesh(
            vertices: vertices,
            indices: indices,
            vertexStride: 12,
            vertexOffset: 0,
            positionOffset: 0,
            indexOffset: 0,
            byteOrder: "CI-FIXTURE"
        )
    }
}
