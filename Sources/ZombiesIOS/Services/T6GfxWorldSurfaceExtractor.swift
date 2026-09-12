import Foundation

/// Typed GfxWorld surface extraction used by the certifiable render path.
/// Keeps each surface separate so material identity and UVs are not lost.
enum T6GfxWorldSurfaceExtractor {
    private static let surfaceStride = 0x50
    private static let vertexStride = 36
    private static let minimumRun = 6
    private static let maxScanBytes = 128 * 1024 * 1024
    private static let maxSurfaceCount = 8_000

    private struct SurfaceRecord {
        let mins: SIMD3<Float>
        let maxs: SIMD3<Float>
        let firstVertex: Int
        let vertexCount: Int
        let triCount: Int
        let baseIndex: Int
        let materialPointer: UInt32
    }

    private struct SurfaceRun {
        let offset: Int
        let count: Int
        let score: Float
    }

    static func extract(
        from data: Data,
        scanLimit: Int,
        materialAssets: [T6MaterialAsset]
    ) -> T6WorldSurfaceSet? {
        guard data.count >= surfaceStride * minimumRun else { return nil }
        let limit = min(data.count, min(max(4096, scanLimit), maxScanBytes))
        let materialIDsByPointer = Dictionary(
            materialAssets.map { ($0.record.rawPointer, $0.record.id) },
            uniquingKeysWith: { first, _ in first }
        )

        return data.withUnsafeBytes { raw -> T6WorldSurfaceSet? in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            let bytes = UnsafeBufferPointer(start: base, count: limit)
            guard let run = findBestSurfaceRun(bytes) else { return nil }

            var records: [SurfaceRecord] = []
            records.reserveCapacity(min(run.count, maxSurfaceCount))
            for index in 0..<min(run.count, maxSurfaceCount) {
                guard let record = parseSurface(bytes, offset: run.offset + index * surfaceStride) else { break }
                records.append(record)
            }
            guard records.count >= minimumRun,
                  let vertexBase = findVertexStreamBase(bytes, surfaces: records),
                  let indexBase = findIndexStreamBase(bytes, surfaces: records) else {
                return nil
            }

            var surfaces: [T6WorldSurface] = []
            surfaces.reserveCapacity(records.count)
            for (surfaceIndex, record) in records.enumerated() {
                guard let surface = buildSurface(
                    record,
                    sourceSurfaceIndex: surfaceIndex,
                    bytes: bytes,
                    vertexBase: vertexBase,
                    indexBase: indexBase,
                    materialID: materialIDsByPointer[record.materialPointer]
                ) else { continue }
                surfaces.append(surface)
            }

            guard surfaces.count >= 3 else { return nil }
            return T6WorldSurfaceSet(
                surfaces: surfaces,
                sourceSurfaceTableOffset: run.offset,
                vertexStreamOffset: vertexBase,
                indexStreamOffset: indexBase,
                usesDiagnosticGeometry: false
            )
        }
    }

    private static func parseSurface(_ bytes: UnsafeBufferPointer<UInt8>, offset: Int) -> SurfaceRecord? {
        guard offset >= 0, offset + surfaceStride <= bytes.count else { return nil }
        let mins = SIMD3<Float>(beFloat(bytes, offset), beFloat(bytes, offset + 4), beFloat(bytes, offset + 8))
        let maxs = SIMD3<Float>(beFloat(bytes, offset + 0x10), beFloat(bytes, offset + 0x14), beFloat(bytes, offset + 0x18))
        let firstVertex = Int(Int32(bitPattern: be32(bytes, offset + 0x1C)))
        let vertexCount = Int(be16(bytes, offset + 0x20))
        let triCount = Int(be16(bytes, offset + 0x22))
        let baseIndex = Int(Int32(bitPattern: be32(bytes, offset + 0x24)))
        let materialPointer = be32(bytes, offset + 0x30)

        guard finite(mins), finite(maxs),
              mins.x <= maxs.x, mins.y <= maxs.y, mins.z <= maxs.z,
              firstVertex >= 0, firstVertex < 8_000_000,
              vertexCount >= 3, vertexCount <= 32_768,
              triCount >= 1, triCount <= 32_768,
              baseIndex >= 0, baseIndex < 80_000_000 else { return nil }

        let span = maxs - mins
        let sorted = [span.x, span.y, span.z].sorted()
        let largest = max(span.x, max(span.y, span.z))
        guard largest > 0.0001, largest < 2_000_000, sorted[1] > 0.00001 else { return nil }

        return SurfaceRecord(
            mins: mins,
            maxs: maxs,
            firstVertex: firstVertex,
            vertexCount: vertexCount,
            triCount: triCount,
            baseIndex: baseIndex,
            materialPointer: materialPointer
        )
    }

    private static func findBestSurfaceRun(_ bytes: UnsafeBufferPointer<UInt8>) -> SurfaceRun? {
        guard bytes.count >= surfaceStride * minimumRun else { return nil }
        var best: SurfaceRun?
        let lastStart = bytes.count - surfaceStride * minimumRun
        var offset = 0

        while offset <= lastStart {
            guard parseSurface(bytes, offset: offset) != nil else {
                offset += 4
                continue
            }

            var count = 0
            var cursor = offset
            var triTotal = 0
            var globalMin = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
            var globalMax = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
            while cursor + surfaceStride <= bytes.count,
                  count < maxSurfaceCount,
                  let record = parseSurface(bytes, offset: cursor) {
                globalMin = componentMin(globalMin, record.mins)
                globalMax = componentMax(globalMax, record.maxs)
                triTotal += record.triCount
                count += 1
                cursor += surfaceStride
            }

            if count >= minimumRun {
                let span = globalMax - globalMin
                let largest = max(span.x, max(span.y, span.z))
                let score = Float(count) * 22 + min(Float(triTotal), 750_000) * 0.002 + min(largest, 500_000) * 0.0005
                let candidate = SurfaceRun(offset: offset, count: count, score: score)
                if best == nil || candidate.score > best!.score { best = candidate }
                offset = cursor
            } else {
                offset += 4
            }
        }
        return best
    }

    private static func findVertexStreamBase(_ bytes: UnsafeBufferPointer<UInt8>, surfaces: [SurfaceRecord]) -> Int? {
        let anchors = surfaces
            .filter { $0.vertexCount >= 4 && $0.vertexCount <= 4096 }
            .sorted { boundsVolume($0) < boundsVolume($1) }
            .prefix(16)

        var scores: [Int: Int] = [:]
        for anchor in anchors {
            let margin = boundsMargin(anchor)
            var offset = 0
            var matches = 0
            while offset + 12 <= bytes.count && matches < 1024 {
                let point = SIMD3<Float>(beFloat(bytes, offset), beFloat(bytes, offset + 4), beFloat(bytes, offset + 8))
                if finite(point), contains(point, in: anchor, margin: margin) {
                    let base = offset - anchor.firstVertex * vertexStride
                    if base >= 0,
                       base + (anchor.firstVertex + anchor.vertexCount) * vertexStride <= bytes.count {
                        let score = validateVertexBase(base, bytes: bytes, surfaces: surfaces)
                        if score > 0 { scores[base] = max(scores[base] ?? 0, score) }
                    }
                    matches += 1
                }
                offset += 4
            }
        }
        return scores.max(by: { $0.value < $1.value }).flatMap { $0.value >= 6 ? $0.key : nil }
    }

    private static func validateVertexBase(_ base: Int, bytes: UnsafeBufferPointer<UInt8>, surfaces: [SurfaceRecord]) -> Int {
        var score = 0
        var checked = 0
        for surface in surfaces.prefix(160) {
            guard checked < 56 else { break }
            let last = base + (surface.firstVertex + surface.vertexCount - 1) * vertexStride
            guard last + 12 <= bytes.count else { continue }
            let margin = boundsMargin(surface) * 2
            let sample = [0, surface.vertexCount / 3, (surface.vertexCount * 2) / 3, surface.vertexCount - 1]
            var hits = 0
            for local in sample {
                let offset = base + (surface.firstVertex + local) * vertexStride
                let point = SIMD3<Float>(beFloat(bytes, offset), beFloat(bytes, offset + 4), beFloat(bytes, offset + 8))
                if finite(point), contains(point, in: surface, margin: margin) { hits += 1 }
            }
            if hits >= 2 { score += hits }
            checked += 1
        }
        return score
    }

    private static func findIndexStreamBase(_ bytes: UnsafeBufferPointer<UInt8>, surfaces: [SurfaceRecord]) -> Int? {
        let anchors = surfaces
            .filter { $0.vertexCount >= 6 && $0.vertexCount <= 8192 && $0.triCount >= 2 }
            .sorted { $0.vertexCount < $1.vertexCount }
            .prefix(20)

        var bestBase: Int?
        var bestScore = 0
        for anchor in anchors {
            var offset = 0
            var candidates = 0
            while offset + 24 <= bytes.count && candidates < 2048 {
                if looksLikeIndexWindow(bytes, offset: offset, surface: anchor) {
                    let base = offset - anchor.baseIndex * 2
                    if base >= 0 {
                        let score = validateIndexBase(base, bytes: bytes, surfaces: surfaces)
                        if score > bestScore {
                            bestScore = score
                            bestBase = base
                            if score >= 20 { return base }
                        }
                    }
                    candidates += 1
                }
                offset += 2
            }
        }
        return bestScore >= 7 ? bestBase : nil
    }

    private static func looksLikeIndexWindow(_ bytes: UnsafeBufferPointer<UInt8>, offset: Int, surface: SurfaceRecord) -> Bool {
        guard offset >= 0, offset + 24 <= bytes.count else { return false }
        var local = 0
        var global = 0
        var unique = Set<UInt16>()
        for index in 0..<12 {
            let value = be16(bytes, offset + index * 2)
            unique.insert(value)
            if Int(value) < surface.vertexCount { local += 1 }
            if Int(value) >= surface.firstVertex && Int(value) < surface.firstVertex + surface.vertexCount { global += 1 }
        }
        return unique.count >= 4 && max(local, global) >= 10
    }

    private static func validateIndexBase(_ base: Int, bytes: UnsafeBufferPointer<UInt8>, surfaces: [SurfaceRecord]) -> Int {
        var score = 0
        var checked = 0
        for surface in surfaces.prefix(160) {
            guard checked < 64 else { break }
            let offset = base + surface.baseIndex * 2
            guard offset >= 0, offset + min(surface.triCount * 6, 24) <= bytes.count else { continue }
            let count = min(surface.triCount * 3, 12)
            var local = 0
            var global = 0
            var unique = Set<UInt16>()
            for index in 0..<count {
                let value = be16(bytes, offset + index * 2)
                unique.insert(value)
                if Int(value) < surface.vertexCount { local += 1 }
                if Int(value) >= surface.firstVertex && Int(value) < surface.firstVertex + surface.vertexCount { global += 1 }
            }
            if unique.count >= 3 && max(local, global) >= max(5, count - 3) { score += 1 }
            checked += 1
        }
        return score
    }

    private static func buildSurface(
        _ surface: SurfaceRecord,
        sourceSurfaceIndex: Int,
        bytes: UnsafeBufferPointer<UInt8>,
        vertexBase: Int,
        indexBase: Int,
        materialID: T6AssetID?
    ) -> T6WorldSurface? {
        var vertices: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        vertices.reserveCapacity(surface.vertexCount)
        uvs.reserveCapacity(surface.vertexCount)
        let margin = boundsMargin(surface) * 6

        for local in 0..<surface.vertexCount {
            let offset = vertexBase + (surface.firstVertex + local) * vertexStride
            guard offset >= 0, offset + vertexStride <= bytes.count else { return nil }
            let point = SIMD3<Float>(beFloat(bytes, offset), beFloat(bytes, offset + 4), beFloat(bytes, offset + 8))
            guard finite(point), contains(point, in: surface, margin: margin) else { return nil }
            vertices.append(point)
            uvs.append(unpackUV(be32(bytes, offset + 20)))
        }

        let indexStart = indexBase + surface.baseIndex * 2
        guard indexStart >= 0, indexStart + surface.triCount * 6 <= bytes.count else { return nil }
        var indices: [UInt32] = []
        indices.reserveCapacity(surface.triCount * 3)
        for triangle in 0..<surface.triCount {
            let offset = indexStart + triangle * 6
            let raw = [be16(bytes, offset), be16(bytes, offset + 2), be16(bytes, offset + 4)]
            let mapped: [Int]
            if raw.allSatisfy({ Int($0) < surface.vertexCount }) {
                mapped = raw.map(Int.init)
            } else if raw.allSatisfy({ Int($0) >= surface.firstVertex && Int($0) < surface.firstVertex + surface.vertexCount }) {
                mapped = raw.map { Int($0) - surface.firstVertex }
            } else {
                continue
            }
            guard mapped[0] != mapped[1], mapped[1] != mapped[2], mapped[0] != mapped[2] else { continue }
            indices.append(UInt32(mapped[0]))
            indices.append(UInt32(mapped[1]))
            indices.append(UInt32(mapped[2]))
        }
        guard indices.count >= 3 else { return nil }

        let normals = buildNormals(vertices: vertices, indices: indices)
        return T6WorldSurface(
            vertices: vertices,
            normals: normals,
            uvs: uvs,
            indices: indices,
            materialID: materialID,
            rawMaterialPointer: surface.materialPointer,
            sourceSurfaceIndex: sourceSurfaceIndex
        )
    }

    private static func buildNormals(vertices: [SIMD3<Float>], indices: [UInt32]) -> [SIMD3<Float>] {
        var normals = Array(repeating: SIMD3<Float>(repeating: 0), count: vertices.count)
        for offset in stride(from: 0, to: indices.count - 2, by: 3) {
            let ia = Int(indices[offset])
            let ib = Int(indices[offset + 1])
            let ic = Int(indices[offset + 2])
            guard ia < vertices.count, ib < vertices.count, ic < vertices.count else { continue }
            let normal = cross(vertices[ib] - vertices[ia], vertices[ic] - vertices[ia])
            normals[ia] += normal
            normals[ib] += normal
            normals[ic] += normal
        }
        return normals.map { vector in
            let length = sqrt(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
            return length > 0.000001 ? vector / length : SIMD3<Float>(0, 1, 0)
        }
    }

    private static func unpackUV(_ packed: UInt32) -> SIMD2<Float> {
        let u = Float(Float16(bitPattern: UInt16(packed & 0xFFFF)))
        let v = Float(Float16(bitPattern: UInt16((packed >> 16) & 0xFFFF)))
        return SIMD2<Float>(u, v)
    }

    private static func boundsVolume(_ surface: SurfaceRecord) -> Float {
        let delta = surface.maxs - surface.mins
        return max(0.0001, delta.x) * max(0.0001, delta.y) * max(0.0001, delta.z)
    }

    private static func boundsMargin(_ surface: SurfaceRecord) -> Float {
        let span = surface.maxs - surface.mins
        return max(0.05, max(span.x, max(span.y, span.z)) * 0.03)
    }

    private static func contains(_ point: SIMD3<Float>, in surface: SurfaceRecord, margin: Float) -> Bool {
        point.x >= surface.mins.x - margin && point.x <= surface.maxs.x + margin &&
        point.y >= surface.mins.y - margin && point.y <= surface.maxs.y + margin &&
        point.z >= surface.mins.z - margin && point.z <= surface.maxs.z + margin
    }

    private static func finite(_ vector: SIMD3<Float>) -> Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
    }

    private static func componentMin(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z))
    }

    private static func componentMax(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z))
    }

    private static func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(
            a.y * b.z - a.z * b.y,
            a.z * b.x - a.x * b.z,
            a.x * b.y - a.y * b.x
        )
    }

    private static func beFloat(_ bytes: UnsafeBufferPointer<UInt8>, _ offset: Int) -> Float {
        Float(bitPattern: be32(bytes, offset))
    }

    private static func be32(_ bytes: UnsafeBufferPointer<UInt8>, _ offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24) |
        (UInt32(bytes[offset + 1]) << 16) |
        (UInt32(bytes[offset + 2]) << 8) |
        UInt32(bytes[offset + 3])
    }

    private static func be16(_ bytes: UnsafeBufferPointer<UInt8>, _ offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }
}
