import Foundation
import simd

enum CIRuntimeMeshFixture {
    static func make() -> T6RuntimeMesh {
        let vertices: [SIMD3<Float>] = [
            SIMD3(-256, 0, -256), SIMD3(256, 0, -256), SIMD3(256, 0, 256), SIMD3(-256, 0, 256),
            SIMD3(-256, 128, -256), SIMD3(256, 128, -256), SIMD3(256, 128, 256), SIMD3(-256, 128, 256)
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
            byteOrder: "CI-FIXTURE-BO2-SCALE"
        )
    }

    static func makePackage() -> BO2RuntimePackage {
        let mesh = make()
        return BO2RuntimePackage(
            sourceName: "CI-FIXTURE",
            vertices: mesh.vertices.map { BO2RuntimeVertex(x: $0.x, y: $0.y, z: $0.z) },
            indices: mesh.indices.map(UInt32.init),
            spawns: [BO2RuntimeSpawn(origin: BO2RuntimeVertex(x: 0, y: 64, z: 0), yaw: 0, classname: "mp_dm_spawn")],
            entities: [BO2RuntimeEntity(classname: "worldspawn", properties: ["classname": "worldspawn"])]
        )
    }
}
