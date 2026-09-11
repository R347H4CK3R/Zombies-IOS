import Foundation
import simd

struct T6WorldConversionResult: Sendable {
    let positions: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let uvs: [SIMD2<Float>]
    let indices: [UInt32]
    let submeshes: [TranzitCachedSubmesh]
    let warnings: [String]
}

enum T6WorldConverterError: LocalizedError {
    case missingGfxWorld
    case noRenderableGeometry

    var errorDescription: String? {
        switch self {
        case .missingGfxWorld: return "No GfxWorld asset exists in the decoded T6 XAsset index."
        case .noRenderableGeometry: return "The GfxWorld asset was indexed but no valid PS3 world geometry could be reconstructed."
        }
    }
}

enum T6WorldConverter {
    static func convert(payload: Data, assets: T6ResolvedAssetIndex) throws -> T6WorldConversionResult {
        guard assets.first(.gfxWorld) != nil else { throw T6WorldConverterError.missingGfxWorld }

        // The current PS3 decoder yields the serialized zone stream rather than a
        // fully pointer-fixed process image. Use the real GfxSurface decoder as the
        // geometry backend, but only after the typed XAsset index proves this zone
        // actually contains GfxWorld. This removes the old "any float stream is a map"
        // preview path from normal gameplay.
        guard let mesh = T6GfxSurfaceMeshExtractor.extract(from: payload, scanLimit: payload.count),
              mesh.vertices.count >= 3,
              mesh.indices.count >= 3 else {
            throw T6WorldConverterError.noRenderableGeometry
        }

        let positions = mesh.vertices
        let indices = mesh.indices.map(UInt32.init)

        // Packed T6 world normals/UVs require the surface stream metadata. Until every
        // serialized pointer variant is fixed up, generate stable geometric normals and
        // world-projected UVs rather than emitting an untexturable flat mesh. The cache
        // format is already capable of storing the exact attributes once resolved.
        var normals = Array(repeating: SIMD3<Float>(0, 1, 0), count: positions.count)
        normals = calculateNormals(positions: positions, indices: indices, fallback: normals)
        let uvs = projectedUVs(positions)

        let submesh = TranzitCachedSubmesh(firstIndex: 0, indexCount: indices.count, materialID: 0)
        return T6WorldConversionResult(
            positions: positions,
            normals: normals,
            uvs: uvs,
            indices: indices,
            submeshes: [submesh],
            warnings: ["GfxWorld geometry is real PS3 surface data; UVs currently use stable world projection until serialized T6 world-vertex pointer fixups are complete."]
        )
    }

    private static func projectedUVs(_ positions: [SIMD3<Float>]) -> [SIMD2<Float>] {
        guard let first = positions.first else { return [] }
        var minX = first.x, maxX = first.x, minZ = first.z, maxZ = first.z
        for p in positions.dropFirst() {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minZ = min(minZ, p.z); maxZ = max(maxZ, p.z)
        }
        let sx = max(maxX - minX, 0.001)
        let sz = max(maxZ - minZ, 0.001)
        return positions.map { SIMD2<Float>(($0.x - minX) / sx * 16, ($0.z - minZ) / sz * 16) }
    }

    private static func calculateNormals(
        positions: [SIMD3<Float>],
        indices: [UInt32],
        fallback: [SIMD3<Float>]
    ) -> [SIMD3<Float>] {
        var result = Array(repeating: SIMD3<Float>(repeating: 0), count: positions.count)
        var i = 0
        while i + 2 < indices.count {
            let ia = Int(indices[i]), ib = Int(indices[i + 1]), ic = Int(indices[i + 2])
            if ia < positions.count, ib < positions.count, ic < positions.count {
                let e1 = positions[ib] - positions[ia]
                let e2 = positions[ic] - positions[ia]
                let n = simd_cross(e1, e2)
                if simd_length_squared(n) > 0.0000001 {
                    result[ia] += n; result[ib] += n; result[ic] += n
                }
            }
            i += 3
        }
        for index in result.indices {
            let length2 = simd_length_squared(result[index])
            result[index] = length2 > 0.0000001 ? simd_normalize(result[index]) : fallback[index]
        }
        return result
    }
}
