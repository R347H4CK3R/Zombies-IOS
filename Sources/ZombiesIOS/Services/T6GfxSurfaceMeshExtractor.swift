import Foundation

/// Reconstructs real T6/BO2 GfxWorld triangles from a decoded PS3 zone payload.
///
/// The important PS3 detail here is that the decoded XFile payload is not
/// guaranteed to begin on the same 16-byte phase as the serialized GfxSurface
/// array.  The XFile header is commonly 0x28 bytes, so scanning only offsets
/// 0,16,32... can miss every real GfxSurface even though the asset table parsed.
enum T6GfxSurfaceMeshExtractor {
    private static let gfxSurfaceStride = 80
    private static let packedWorldVertexStride = 36
    private static let minimumRun = 8
    private static let maxScanBytes = 128 * 1024 * 1024
    private static let maxSurfaceCount = 8_000
    private static let maxOutputVertices = 65_000
    private static let maxOutputTriangles = 140_000

    private struct SurfaceRecord {
        let mins: SIMD3<Float>
        let maxs: SIMD3<Float>
        let vertexDataOffset0: Int
        let vertexDataOffset1: Int
        let firstVertex: Int
        let vertexCount: Int
        let triCount: Int
        let baseIndex: Int
    }

    private struct Run {
        let offset: Int
        let count: Int
        let score: Float
    }

    static func extract(from data: Data, scanLimit: Int) -> T6RuntimeMesh? {
        guard data.count >= gfxSurfaceStride * minimumRun else { return nil }
        let limit = min(data.count, min(max(4096, scanLimit), maxScanBytes))

        return data.withUnsafeBytes { raw -> T6RuntimeMesh? in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            let bytes = UnsafeBufferPointer(start: base, count: limit)
            guard let run = findBestSurfaceRun(bytes) else { return nil }

            var surfaces: [SurfaceRecord] = []
            surfaces.reserveCapacity(min(run.count, maxSurfaceCount))
            for i in 0..<min(run.count, maxSurfaceCount) {
                guard let s = parseSurface(bytes, offset: run.offset + i * gfxSurfaceStride) else { break }
                surfaces.append(s)
            }
            surfaces = rejectSpatialOutliers(surfaces)
            guard surfaces.count >= minimumRun else { return nil }

            guard let vertexBase = findVertexStreamBase(bytes, surfaces: surfaces) else { return nil }
            guard let indexBase = findIndexStreamBase(bytes, surfaces: surfaces) else { return nil }

            var vertices: [SIMD3<Float>] = []
            var indices: [UInt16] = []
            vertices.reserveCapacity(min(maxOutputVertices, 48_000))
            indices.reserveCapacity(min(maxOutputTriangles * 3, 240_000))

            var accepted = 0
            for surface in surfaces {
                if vertices.count + surface.vertexCount > maxOutputVertices { continue }
                if indices.count / 3 >= maxOutputTriangles { break }
                if appendRealSurface(
                    surface,
                    bytes: bytes,
                    vertexBase: vertexBase,
                    indexBase: indexBase,
                    vertices: &vertices,
                    indices: &indices
                ) {
                    accepted += 1
                }
            }

            guard accepted >= 3, vertices.count >= 32, indices.count >= 60 else { return nil }
            return T6RuntimeMesh(
                vertices: normalizeForSceneKit(vertices),
                indices: indices,
                vertexStride: packedWorldVertexStride,
                vertexOffset: vertexBase,
                positionOffset: 0,
                indexOffset: indexBase,
                byteOrder: "GFXWORLD:BE REAL S:\(accepted) V36 PS3"
            )
        }
    }

    // MARK: - GfxSurface discovery

    private static func findBestSurfaceRun(_ bytes: UnsafeBufferPointer<UInt8>) -> Run? {
        guard bytes.count >= gfxSurfaceStride * minimumRun else { return nil }
        var best: Run?
        let lastStart = bytes.count - gfxSurfaceStride * minimumRun

        // Do not assume the decoded payload is 16-byte phase aligned. The PS3
        // XFile content can start at 0x28 (8 mod 16), and individual streams can
        // also be rebased. Four-byte scanning still respects every field in the
        // structure while covering all legal phases.
        var offset = 0
        while offset <= lastStart {
            guard parseSurface(bytes, offset: offset) != nil else {
                offset += 4
                continue
            }

            var count = 0
            var cursor = offset
            var globalMin = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
            var globalMax = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
            var triTotal = 0

            while cursor + gfxSurfaceStride <= bytes.count,
                  count < 12_000,
                  let s = parseSurface(bytes, offset: cursor) {
                globalMin = componentMin(globalMin, s.mins)
                globalMax = componentMax(globalMax, s.maxs)
                triTotal += min(s.triCount, 200_000)
                count += 1
                cursor += gfxSurfaceStride
            }

            if count >= minimumRun {
                let span = globalMax - globalMin
                let largest = max(span.x, max(span.y, span.z))
                let second = [span.x, span.y, span.z].sorted()[1]
                let score = Float(count) * 22
                    + min(Float(triTotal), 750_000) * 0.002
                    + min(largest, 500_000) * 0.0005
                    + min(second, 250_000) * 0.0005
                let candidate = Run(offset: offset, count: count, score: score)
                if best == nil || candidate.score > best!.score { best = candidate }
                offset = cursor
            } else {
                offset += 4
            }
        }
        return best
    }

    private static func parseSurface(_ bytes: UnsafeBufferPointer<UInt8>, offset: Int) -> SurfaceRecord? {
        guard offset >= 0, offset + gfxSurfaceStride <= bytes.count else { return nil }

        let mins = SIMD3<Float>(beFloat(bytes, offset), beFloat(bytes, offset + 4), beFloat(bytes, offset + 8))
        let vdo0 = Int(Int32(bitPattern: be32(bytes, offset + 12)))
        let maxs = SIMD3<Float>(beFloat(bytes, offset + 16), beFloat(bytes, offset + 20), beFloat(bytes, offset + 24))
        let vdo1 = Int(Int32(bitPattern: be32(bytes, offset + 28)))
        let firstVertex = Int(Int32(bitPattern: be32(bytes, offset + 32)))
        let himip = beFloat(bytes, offset + 36)
        let vertexCount = Int(be16(bytes, offset + 40))
        let triCount = Int(be16(bytes, offset + 42))
        let baseIndex = Int(Int32(bitPattern: be32(bytes, offset + 44)))

        guard finite(mins), finite(maxs), himip.isFinite,
              mins.x <= maxs.x, mins.y <= maxs.y, mins.z <= maxs.z,
              firstVertex >= 0, firstVertex < 8_000_000,
              vertexCount >= 3, vertexCount <= 32_768,
              triCount >= 1, triCount <= 32_768,
              baseIndex >= 0, baseIndex < 80_000_000 else { return nil }

        let span = maxs - mins
        let largest = max(span.x, max(span.y, span.z))
        let sorted = [span.x, span.y, span.z].sorted()
        guard largest > 0.0001, largest < 2_000_000, sorted[1] > 0.00001 else { return nil }

        let b0 = SIMD3<Float>(beFloat(bytes, offset + 56), beFloat(bytes, offset + 60), beFloat(bytes, offset + 64))
        let b1 = SIMD3<Float>(beFloat(bytes, offset + 68), beFloat(bytes, offset + 72), beFloat(bytes, offset + 76))
        guard finite(b0), finite(b1),
              abs(b0.x) < 4_000_000, abs(b0.y) < 4_000_000, abs(b0.z) < 4_000_000,
              abs(b1.x) < 4_000_000, abs(b1.y) < 4_000_000, abs(b1.z) < 4_000_000 else { return nil }

        return SurfaceRecord(
            mins: mins,
            maxs: maxs,
            vertexDataOffset0: vdo0,
            vertexDataOffset1: vdo1,
            firstVertex: firstVertex,
            vertexCount: vertexCount,
            triCount: triCount,
            baseIndex: baseIndex
        )
    }

    // MARK: - GfxWorld vertex/index stream discovery

    private static func findVertexStreamBase(
        _ bytes: UnsafeBufferPointer<UInt8>,
        surfaces: [SurfaceRecord]
    ) -> Int? {
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
                let p = SIMD3<Float>(beFloat(bytes, offset), beFloat(bytes, offset + 4), beFloat(bytes, offset + 8))
                if finite(p), contains(p, in: anchor, margin: margin) {
                    let base = offset - anchor.firstVertex * packedWorldVertexStride
                    if base >= 0,
                       base + (anchor.firstVertex + anchor.vertexCount) * packedWorldVertexStride <= bytes.count {
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

    private static func validateVertexBase(
        _ base: Int,
        bytes: UnsafeBufferPointer<UInt8>,
        surfaces: [SurfaceRecord]
    ) -> Int {
        var score = 0
        var checked = 0
        for s in surfaces.prefix(160) {
            guard checked < 56 else { break }
            let last = base + (s.firstVertex + s.vertexCount - 1) * packedWorldVertexStride
            guard last + 12 <= bytes.count else { continue }
            let margin = boundsMargin(s) * 2
            let sample = [0, s.vertexCount / 3, (s.vertexCount * 2) / 3, s.vertexCount - 1]
            var hits = 0
            for local in sample {
                let off = base + (s.firstVertex + local) * packedWorldVertexStride
                let p = SIMD3<Float>(beFloat(bytes, off), beFloat(bytes, off + 4), beFloat(bytes, off + 8))
                if finite(p), contains(p, in: s, margin: margin) { hits += 1 }
            }
            if hits >= 2 { score += hits }
            checked += 1
        }
        return score
    }

    private static func findIndexStreamBase(
        _ bytes: UnsafeBufferPointer<UInt8>,
        surfaces: [SurfaceRecord]
    ) -> Int? {
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

    private static func looksLikeIndexWindow(
        _ bytes: UnsafeBufferPointer<UInt8>,
        offset: Int,
        surface: SurfaceRecord
    ) -> Bool {
        guard offset >= 0, offset + 24 <= bytes.count else { return false }
        var local = 0
        var global = 0
        var unique = Set<UInt16>()
        for i in 0..<12 {
            let v = be16(bytes, offset + i * 2)
            unique.insert(v)
            if Int(v) < surface.vertexCount { local += 1 }
            if Int(v) >= surface.firstVertex && Int(v) < surface.firstVertex + surface.vertexCount { global += 1 }
        }
        return unique.count >= 4 && max(local, global) >= 10
    }

    private static func validateIndexBase(
        _ base: Int,
        bytes: UnsafeBufferPointer<UInt8>,
        surfaces: [SurfaceRecord]
    ) -> Int {
        var score = 0
        var checked = 0
        for s in surfaces.prefix(160) {
            guard checked < 64 else { break }
            let off = base + s.baseIndex * 2
            guard off >= 0, off + min(s.triCount * 6, 24) <= bytes.count else { continue }
            let count = min(s.triCount * 3, 12)
            var local = 0
            var global = 0
            var unique = Set<UInt16>()
            for i in 0..<count {
                let v = be16(bytes, off + i * 2)
                unique.insert(v)
                if Int(v) < s.vertexCount { local += 1 }
                if Int(v) >= s.firstVertex && Int(v) < s.firstVertex + s.vertexCount { global += 1 }
            }
            if unique.count >= 3 && max(local, global) >= max(5, count - 3) { score += 1 }
            checked += 1
        }
        return score
    }

    private static func appendRealSurface(
        _ surface: SurfaceRecord,
        bytes: UnsafeBufferPointer<UInt8>,
        vertexBase: Int,
        indexBase: Int,
        vertices: inout [SIMD3<Float>],
        indices: inout [UInt16]
    ) -> Bool {
        guard vertices.count + surface.vertexCount <= maxOutputVertices else { return false }
        let oldVertexCount = vertices.count
        let baseOut = oldVertexCount
        let margin = boundsMargin(surface) * 6

        for local in 0..<surface.vertexCount {
            let off = vertexBase + (surface.firstVertex + local) * packedWorldVertexStride
            guard off >= 0, off + 12 <= bytes.count else {
                vertices.removeLast(vertices.count - oldVertexCount)
                return false
            }
            let p = SIMD3<Float>(beFloat(bytes, off), beFloat(bytes, off + 4), beFloat(bytes, off + 8))
            guard finite(p), contains(p, in: surface, margin: margin) else {
                vertices.removeLast(vertices.count - oldVertexCount)
                return false
            }
            vertices.append(p)
        }

        let indexStart = indexBase + surface.baseIndex * 2
        guard indexStart >= 0, indexStart + surface.triCount * 6 <= bytes.count else {
            vertices.removeLast(vertices.count - oldVertexCount)
            return false
        }

        var localIndices: [UInt16] = []
        localIndices.reserveCapacity(surface.triCount * 3)
        var validTriangles = 0
        for tri in 0..<surface.triCount {
            let off = indexStart + tri * 6
            let raw = [be16(bytes, off), be16(bytes, off + 2), be16(bytes, off + 4)]
            let mapped: [Int]
            if raw.allSatisfy({ Int($0) < surface.vertexCount }) {
                mapped = raw.map(Int.init)
            } else if raw.allSatisfy({ Int($0) >= surface.firstVertex && Int($0) < surface.firstVertex + surface.vertexCount }) {
                mapped = raw.map { Int($0) - surface.firstVertex }
            } else {
                continue
            }
            guard mapped[0] != mapped[1], mapped[1] != mapped[2], mapped[0] != mapped[2] else { continue }
            let a = vertices[baseOut + mapped[0]]
            let b = vertices[baseOut + mapped[1]]
            let c = vertices[baseOut + mapped[2]]
            let area2 = vectorLength(cross(b - a, c - a))
            guard area2.isFinite, area2 > 0.0000001 else { continue }
            localIndices.append(UInt16(baseOut + mapped[0]))
            localIndices.append(UInt16(baseOut + mapped[1]))
            localIndices.append(UInt16(baseOut + mapped[2]))
            validTriangles += 1
            if indices.count / 3 + validTriangles >= maxOutputTriangles { break }
        }

        guard validTriangles >= 1 else {
            vertices.removeLast(vertices.count - oldVertexCount)
            return false
        }
        indices.append(contentsOf: localIndices)
        return true
    }

    // MARK: - Helpers

    private static func rejectSpatialOutliers(_ input: [SurfaceRecord]) -> [SurfaceRecord] {
        guard input.count >= 24 else { return input }
        let centers = input.map { ($0.mins + $0.maxs) * 0.5 }
        let xs = centers.map(\.x).sorted()
        let ys = centers.map(\.y).sorted()
        let zs = centers.map(\.z).sorted()
        let middle = input.count / 2
        let median = SIMD3<Float>(xs[middle], ys[middle], zs[middle])
        let distances = centers.map { vectorLength($0 - median) }.sorted()
        let p90 = distances[min(distances.count - 1, Int(Float(distances.count - 1) * 0.90))]
        let radius = max(1, p90 * 4)
        let filtered = zip(input, centers).compactMap { s, c in vectorLength(c - median) <= radius ? s : nil }
        return filtered.count >= minimumRun ? filtered : input
    }

    private static func boundsVolume(_ s: SurfaceRecord) -> Float {
        let d = s.maxs - s.mins
        return max(0.0001, d.x) * max(0.0001, d.y) * max(0.0001, d.z)
    }

    private static func boundsMargin(_ s: SurfaceRecord) -> Float {
        let span = s.maxs - s.mins
        return max(0.05, max(span.x, max(span.y, span.z)) * 0.03)
    }

    private static func contains(_ p: SIMD3<Float>, in s: SurfaceRecord, margin: Float) -> Bool {
        p.x >= s.mins.x - margin && p.x <= s.maxs.x + margin
            && p.y >= s.mins.y - margin && p.y <= s.maxs.y + margin
            && p.z >= s.mins.z - margin && p.z <= s.maxs.z + margin
    }

    private static func normalizeForSceneKit(_ vertices: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard !vertices.isEmpty else { return vertices }
        let converted = vertices.map { SIMD3<Float>($0.x, $0.z, -$0.y) }
        var minV = converted[0]
        var maxV = converted[0]
        for v in converted.dropFirst() {
            minV = componentMin(minV, v)
            maxV = componentMax(maxV, v)
        }
        let span = maxV - minV
        let largest = max(Float(0.0001), max(span.x, max(span.y, span.z)))
        let scale = 115.0 / largest
        let centerX = (minV.x + maxV.x) * 0.5
        let centerZ = (minV.z + maxV.z) * 0.5
        let groundY = minV.y
        return converted.map {
            SIMD3<Float>(($0.x - centerX) * scale, ($0.y - groundY) * scale, ($0.z - centerZ) * scale)
        }
    }

    private static func beFloat(_ bytes: UnsafeBufferPointer<UInt8>, _ offset: Int) -> Float {
        guard offset >= 0, offset + 4 <= bytes.count else { return .nan }
        return Float(bitPattern: be32(bytes, offset))
    }

    private static func be32(_ bytes: UnsafeBufferPointer<UInt8>, _ offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }

    private static func be16(_ bytes: UnsafeBufferPointer<UInt8>, _ offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private static func finite(_ v: SIMD3<Float>) -> Bool {
        v.x.isFinite && v.y.isFinite && v.z.isFinite
    }

    private static func componentMin(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(min(a.x, b.x), min(a.y, b.y), min(a.z, b.z))
    }

    private static func componentMax(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(max(a.x, b.x), max(a.y, b.y), max(a.z, b.z))
    }

    private static func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }

    private static func vectorLength(_ v: SIMD3<Float>) -> Float {
        sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    }
}
