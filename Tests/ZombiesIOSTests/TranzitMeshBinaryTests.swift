import XCTest
@testable import ZombiesIOS

final class TranzitMeshBinaryTests: XCTestCase {
    private func sampleWorld() -> TranzitCachedWorld {
        let material = TranzitCachedMaterial(id: 0, name: "test", diffuseTexture: nil, normalTexture: nil, specularTexture: nil, alphaCutout: false)
        return TranzitCachedWorld(
            positions: [
                SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0),
                SIMD3<Float>(1, 0, 1), SIMD3<Float>(0, 0, 1)
            ],
            normals: Array(repeating: SIMD3<Float>(0, 1, 0), count: 4),
            uvs: [SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1)],
            indices: [0, 1, 2, 0, 2, 3],
            submeshes: [
                TranzitCachedSubmesh(firstIndex: 0, indexCount: 3, materialID: 0),
                TranzitCachedSubmesh(firstIndex: 3, indexCount: 3, materialID: 0)
            ],
            materials: [material]
        )
    }

    func testRoundTripIsExact() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let world = sampleWorld()
        try TranzitMeshBinary.write(world: world, to: url)
        let decoded = try TranzitMeshBinary.read(from: url, materials: world.materials)
        XCTAssertEqual(decoded, world)
        try? FileManager.default.removeItem(at: url)
    }

    func testRejectsInvalidSubmeshRange() throws {
        let world = sampleWorld()
        let invalid = TranzitCachedWorld(
            positions: world.positions,
            normals: world.normals,
            uvs: world.uvs,
            indices: world.indices,
            submeshes: [TranzitCachedSubmesh(firstIndex: 5, indexCount: 4, materialID: 0)],
            materials: world.materials
        )
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try TranzitMeshBinary.write(world: invalid, to: url)) { error in
            XCTAssertEqual(error as? TranzitMeshBinaryError, .invalidSubmeshRange)
        }
    }
}
