import Foundation

enum ConvertedCollisionImportError: LocalizedError {
    case collisionBoundsDoNotOverlap
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .collisionBoundsDoNotOverlap:
            return "Converted collision bounds do not overlap the rendered world."
        case .writeFailed(let reason):
            return "Converted collision could not be written: \(reason)"
        }
    }
}

struct ConvertedCollisionResult {
    let meshPath: String
    let vertexCount: Int
    let indexCount: Int
}

struct ConvertedCollisionImporter {
    func convert(worldMeshURL: URL, stagingURL: URL) throws -> ConvertedCollisionResult {
        let world = try ConvertedMeshFormat.decode(Data(contentsOf: worldMeshURL))

        // Phase one uses the already validated render triangles as deterministic
        // collision geometry. Keeping this in a separate file lets the runtime
        // build physics independently of render geometry and later replace it with
        // dedicated source collision data without changing the package contract.
        let collision = ConvertedMesh(
            positions: world.positions,
            indices: world.indices,
            boundsMin: world.boundsMin,
            boundsMax: world.boundsMax,
            materialGroups: []
        )

        guard boundsOverlap(
            minA: world.boundsMin,
            maxA: world.boundsMax,
            minB: collision.boundsMin,
            maxB: collision.boundsMax
        ) else {
            throw ConvertedCollisionImportError.collisionBoundsDoNotOverlap
        }

        let data = try ConvertedMeshFormat.encode(collision)
        _ = try ConvertedMeshFormat.decode(data)
        let path = "world/collision.mesh"
        let target = stagingURL.appendingPathComponent(path, isDirectory: false)
        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: target, options: .atomic)
        } catch {
            throw ConvertedCollisionImportError.writeFailed(error.localizedDescription)
        }

        return ConvertedCollisionResult(
            meshPath: path,
            vertexCount: collision.positions.count,
            indexCount: collision.indices.count
        )
    }

    private func boundsOverlap(
        minA: SIMD3<Float>,
        maxA: SIMD3<Float>,
        minB: SIMD3<Float>,
        maxB: SIMD3<Float>
    ) -> Bool {
        minA.x <= maxB.x && maxA.x >= minB.x
            && minA.y <= maxB.y && maxA.y >= minB.y
            && minA.z <= maxB.z && maxA.z >= minB.z
    }
}
