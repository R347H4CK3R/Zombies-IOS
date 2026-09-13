import Foundation
import simd

final class WorldTriangleRaycaster: CombatRaycaster {
    private let positions: [SIMD3<Float>]
    private let indices: [UInt32]

    init(asset: WorldRuntimeAsset) {
        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(asset.metadata.vertexCount)
        for index in 0..<asset.metadata.vertexCount {
            let base = index * WorldRuntimeAsset.vertexStride
            positions.append(SIMD3<Float>(
                Self.readFloatLE(asset.vertexData, base),
                Self.readFloatLE(asset.vertexData, base + 4),
                Self.readFloatLE(asset.vertexData, base + 8)
            ))
        }
        self.positions = positions

        var indices: [UInt32] = []
        indices.reserveCapacity(asset.metadata.indexCount)
        for index in 0..<asset.metadata.indexCount {
            let raw: UInt32 = asset.indexData.withUnsafeBytes { bytes in
                bytes.loadUnaligned(fromByteOffset: index * 4, as: UInt32.self)
            }
            indices.append(UInt32(littleEndian: raw))
        }
        self.indices = indices
    }

    func raycast(origin: SIMD3<Float>, direction: SIMD3<Float>, range: Float) -> CombatHit? {
        guard range > 0, simd_length_squared(direction) > 0 else { return nil }
        let ray = simd_normalize(direction)
        var nearest = range
        var point: SIMD3<Float>?

        var i = 0
        while i + 2 < indices.count {
            let ia = Int(indices[i])
            let ib = Int(indices[i + 1])
            let ic = Int(indices[i + 2])
            i += 3
            guard ia < positions.count, ib < positions.count, ic < positions.count else { continue }
            if let t = Self.intersection(origin: origin, direction: ray, a: positions[ia], b: positions[ib], c: positions[ic]), t >= 0, t < nearest {
                nearest = t
                point = origin + ray * t
            }
        }
        guard let point else { return nil }
        return CombatHit(entityID: nil, position: point, distance: nearest)
    }

    private static func intersection(
        origin: SIMD3<Float>, direction: SIMD3<Float>,
        a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>
    ) -> Float? {
        let epsilon: Float = 0.00001
        let edge1 = b - a
        let edge2 = c - a
        let p = simd_cross(direction, edge2)
        let determinant = simd_dot(edge1, p)
        if abs(determinant) < epsilon { return nil }
        let inv = 1 / determinant
        let tvec = origin - a
        let u = simd_dot(tvec, p) * inv
        if u < 0 || u > 1 { return nil }
        let q = simd_cross(tvec, edge1)
        let v = simd_dot(direction, q) * inv
        if v < 0 || u + v > 1 { return nil }
        let t = simd_dot(edge2, q) * inv
        return t >= 0 ? t : nil
    }

    private static func readFloatLE(_ data: Data, _ offset: Int) -> Float {
        let raw: UInt32 = data.withUnsafeBytes { bytes in
            bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        }
        return Float(bitPattern: UInt32(littleEndian: raw))
    }
}
