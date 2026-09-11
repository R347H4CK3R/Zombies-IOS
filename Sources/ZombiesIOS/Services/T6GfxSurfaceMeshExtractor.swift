import Foundation

/// Reconstructs a coarse but spatially faithful Tranzit world directly from the
/// serialized T6 PS3 `GfxSurface` array. T6 world vertex streams are packed and
/// are not safely discoverable by treating arbitrary bytes as Float32 positions.
/// `GfxSurface`, however, contains per-surface world-space mins/maxs plus vertex
/// and triangle metadata. Those records are 80 bytes on 32-bit T6 and aligned to
/// 16 bytes. Building planes/boxes from those real bounds gives a recognizable
/// world layout immediately while the packed vertex decoder can remain a fallback.
enum T6GfxSurfaceMeshExtractor {
    private static let gfxSurfaceStride = 80
    private static let maxScanBytes = 96 * 1024 * 1024
    private static let minimumRun = 12
    private static let maxSurfaceCount = 4_500
    private static let maxVertices = 65_000

    private struct SurfaceRecord {
        let mins: SIMD3<Float>
        let maxs: SIMD3<Float>
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
            guard let run = findBestRun(bytes) else { return nil }

            var records: [SurfaceRecord] = []
            records.reserveCapacity(min(run.count, maxSurfaceCount))
            for i in 0..<min(run.count, maxSurfaceCount) {
                let offset = run.offset + i * gfxSurfaceStride
                guard let record = parseSurface(bytes, offset: offset) else { break }
                records.append(record)
            }

            guard records.count >= minimumRun else { return nil }

            // Remove obvious global outliers before constructing geometry. Real
            // GfxSurface runs normally form one coherent world-coordinate cloud.
            let filtered = rejectSpatialOutliers(records)
            guard filtered.count >= minimumRun else { return nil }

            var vertices: [SIMD3<Float>] = []
            var indices: [UInt16] = []
            vertices.reserveCapacity(min(maxVertices, filtered.count * 6))
            indices.reserveCapacity(filtered.count * 12)

            for surface in filtered {
                if vertices.count >= maxVertices - 8 { break }
                appendApproximation(for: surface, vertices: &vertices, indices: &indices)
            }

            guard vertices.count >= 24, indices.count >= 36 else { return nil }
            let normalized = normalizeForSceneKit(vertices)

            return T6RuntimeMesh(
                vertices: normalized,
                indices: indices,
                vertexStride: gfxSurfaceStride,
                vertexOffset: run.offset,
                positionOffset: 0,
                indexOffset: filtered.first?.baseIndex ?? 0,
                byteOrder: "GFXSURF:BE S:\(filtered.count) ZUP"
            )
        }
    }

    private static func findBestRun(_ bytes: UnsafeBufferPointer<UInt8>) -> Run? {
        guard bytes.count >= gfxSurfaceStride * minimumRun else { return nil }
        var best: Run?
        var offset = 0
        let lastStart = bytes.count - gfxSurfaceStride * minimumRun

        // type_align32(16) GfxSurface: scan only valid 16-byte alignment.
        while offset <= lastStart {
            guard parseSurface(bytes, offset: offset) != nil else {
                offset += 16
                continue
            }

            var count = 0
            var cursor = offset
            var globalMin = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
            var globalMax = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)
            var triTotal = 0

            while cursor + gfxSurfaceStride <= bytes.count, count < 12_000,
                  let surface = parseSurface(bytes, offset: cursor) {
                globalMin = componentMin(globalMin, surface.mins)
                globalMax = componentMax(globalMax, surface.maxs)
                triTotal += min(surface.triCount, 200_000)
                count += 1
                cursor += gfxSurfaceStride
            }

            if count >= minimumRun {
                let span = globalMax - globalMin
                let largest = max(span.x, max(span.y, span.z))
                let second = [span.x, span.y, span.z].sorted()[1]
                // Long contiguous runs, broad world coverage and actual triangle
                // metadata strongly distinguish GfxSurface from random bytes.
                let score = Float(count) * 20
                    + min(Float(triTotal), 500_000) * 0.002
                    + min(largest, 500_000) * 0.0005
                    + min(second, 250_000) * 0.0005

                let candidate = Run(offset: offset, count: count, score: score)
                if best == nil || candidate.score > best!.score { best = candidate }

                // Do not rescan the interior of a confirmed contiguous array.
                offset = cursor
            } else {
                offset += 16
            }
        }

        return best
    }

    private static func parseSurface(_ bytes: UnsafeBufferPointer<UInt8>, offset: Int) -> SurfaceRecord? {
        guard offset >= 0, offset + gfxSurfaceStride <= bytes.count else { return nil }

        let mins = SIMD3<Float>(
            beFloat(bytes, offset),
            beFloat(bytes, offset + 4),
            beFloat(bytes, offset + 8)
        )
        let maxs = SIMD3<Float>(
            beFloat(bytes, offset + 16),
            beFloat(bytes, offset + 20),
            beFloat(bytes, offset + 24)
        )
        let firstVertex = Int(Int32(bitPattern: be32(bytes, offset + 32)))
        let himip = beFloat(bytes, offset + 36)
        let vertexCount = Int(be16(bytes, offset + 40))
        let triCount = Int(be16(bytes, offset + 42))
        let baseIndex = Int(Int32(bitPattern: be32(bytes, offset + 44)))

        guard finite(mins), finite(maxs), himip.isFinite,
              mins.x <= maxs.x, mins.y <= maxs.y, mins.z <= maxs.z,
              firstVertex >= 0, firstVertex < 4_000_000,
              vertexCount >= 3,
              triCount >= 1,
              baseIndex >= 0, baseIndex < 30_000_000,
              baseIndex + triCount * 3 < 40_000_000 else { return nil }

        let span = maxs - mins
        let largest = max(span.x, max(span.y, span.z))
        let sorted = [span.x, span.y, span.z].sorted()
        guard largest > 0.0001, largest < 2_000_000,
              sorted[1] > 0.00001 else { return nil }

        // GfxSurface ends with vec3_t bounds[2]. These values provide another
        // strong validation signature without depending on their semantic use.
        let b0 = SIMD3<Float>(
            beFloat(bytes, offset + 56),
            beFloat(bytes, offset + 60),
            beFloat(bytes, offset + 64)
        )
        let b1 = SIMD3<Float>(
            beFloat(bytes, offset + 68),
            beFloat(bytes, offset + 72),
            beFloat(bytes, offset + 76)
        )
        guard finite(b0), finite(b1),
              abs(b0.x) < 4_000_000, abs(b0.y) < 4_000_000, abs(b0.z) < 4_000_000,
              abs(b1.x) < 4_000_000, abs(b1.y) < 4_000_000, abs(b1.z) < 4_000_000 else { return nil }

        return SurfaceRecord(
            mins: mins,
            maxs: maxs,
            firstVertex: firstVertex,
            vertexCount: vertexCount,
            triCount: triCount,
            baseIndex: baseIndex
        )
    }

    private static func rejectSpatialOutliers(_ input: [SurfaceRecord]) -> [SurfaceRecord] {
        guard input.count >= 24 else { return input }
        let centers = input.map { ($0.mins + $0.maxs) * 0.5 }
        let xs = centers.map(\.x).sorted()
        let ys = centers.map(\.y).sorted()
        let zs = centers.map(\.z).sorted()
        let middle = input.count / 2
        let median = SIMD3<Float>(xs[middle], ys[middle], zs[middle])

        let distances = centers.map { length($0 - median) }.sorted()
        let p90 = distances[min(distances.count - 1, Int(Float(distances.count - 1) * 0.90))]
        let radius = max(1, p90 * 4.0)

        let result = zip(input, centers).compactMap { surface, center in
            length(center - median) <= radius ? surface : nil
        }
        return result.count >= minimumRun ? result : input
    }

    private static func appendApproximation(
        for surface: SurfaceRecord,
        vertices: inout [SIMD3<Float>],
        indices: inout [UInt16]
    ) {
        var minV = surface.mins
        var maxV = surface.maxs
        let span = maxV - minV
        let largest = max(span.x, max(span.y, span.z))
        guard largest > 0 else { return }

        // Most brush/world surfaces are effectively planar. Recreate them as a
        // quad using the thinnest axis. Volumetric bounds become boxes.
        let thinThreshold = largest * 0.12
        let smallest = min(span.x, min(span.y, span.z))

        if smallest <= thinThreshold {
            let axis: Int
            if span.x <= span.y && span.x <= span.z { axis = 0 }
            else if span.y <= span.z { axis = 1 }
            else { axis = 2 }

            // Give zero-thickness planes a tiny thickness in their normal axis so
            // collision and double-sided rendering remain stable.
            let epsilon = max(0.02, largest * 0.001)
            switch axis {
            case 0:
                let x = (minV.x + maxV.x) * 0.5
                minV.x = x - epsilon
                maxV.x = x + epsilon
            case 1:
                let y = (minV.y + maxV.y) * 0.5
                minV.y = y - epsilon
                maxV.y = y + epsilon
            default:
                let z = (minV.z + maxV.z) * 0.5
                minV.z = z - epsilon
                maxV.z = z + epsilon
            }
        }

        appendBox(min: minV, max: maxV, vertices: &vertices, indices: &indices)
    }

    private static func appendBox(
        min a: SIMD3<Float>,
        max b: SIMD3<Float>,
        vertices: inout [SIMD3<Float>],
        indices: inout [UInt16]
    ) {
        guard vertices.count <= maxVertices - 8 else { return }
        let base = UInt16(vertices.count)
        vertices.append(contentsOf: [
            SIMD3<Float>(a.x, a.y, a.z),
            SIMD3<Float>(b.x, a.y, a.z),
            SIMD3<Float>(b.x, b.y, a.z),
            SIMD3<Float>(a.x, b.y, a.z),
            SIMD3<Float>(a.x, a.y, b.z),
            SIMD3<Float>(b.x, a.y, b.z),
            SIMD3<Float>(b.x, b.y, b.z),
            SIMD3<Float>(a.x, b.y, b.z)
        ])

        let local: [UInt16] = [
            0, 2, 1, 0, 3, 2,
            4, 5, 6, 4, 6, 7,
            0, 1, 5, 0, 5, 4,
            3, 7, 6, 3, 6, 2,
            0, 4, 7, 0, 7, 3,
            1, 2, 6, 1, 6, 5
        ]
        indices.append(contentsOf: local.map { base &+ $0 })
    }

    private static func normalizeForSceneKit(_ vertices: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard !vertices.isEmpty else { return vertices }
        // T6 uses Z-up; SceneKit uses Y-up.
        let converted = vertices.map { SIMD3<Float>($0.x, $0.z, -$0.y) }
        var minV = converted[0]
        var maxV = converted[0]
        for v in converted.dropFirst() {
            minV = componentMin(minV, v)
            maxV = componentMax(maxV, v)
        }

        let span = maxV - minV
        let largest = max(Float(0.0001), max(span.x, max(span.y, span.z)))
        // Tranzit is a large map; keep substantially more world scale than the
        // earlier 42-unit debug mesh while retaining sane SceneKit precision.
        let scale = 115.0 / largest
        let centerX = (minV.x + maxV.x) * 0.5
        let centerZ = (minV.z + maxV.z) * 0.5
        let groundY = minV.y

        return converted.map {
            SIMD3<Float>(
                ($0.x - centerX) * scale,
                ($0.y - groundY) * scale,
                ($0.z - centerZ) * scale
            )
        }
    }

    private static func beFloat(_ bytes: UnsafeBufferPointer<UInt8>, _ offset: Int) -> Float {
        Float(bitPattern: be32(bytes, offset))
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

    private static func length(_ v: SIMD3<Float>) -> Float {
        sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    }
}
