import Foundation

/// Last-resort Tranzit world reconstruction using serialized PS3 GfxSurface bounds.
///
/// This path is intentionally limited to data that is structurally validated as
/// a contiguous GfxSurface run. It never fabricates arena geometry. When the real
/// packed vertex/index stream cannot yet be rebased, these surfaces still expose
/// the map's real world-space bounds so the renderer can show recognizable layout
/// instead of dropping back to the debug floor.
enum T6GfxBoundsFallbackExtractor {
    private static let surfaceStride = 80
    private static let minimumRun = 6
    private static let maxScanBytes = 128 * 1024 * 1024
    private static let maxSurfaces = 6_000
    private static let maxVertices = 65_000

    private struct Surface {
        let mins: SIMD3<Float>
        let maxs: SIMD3<Float>
        let triCount: Int
        let baseIndex: Int
    }

    private struct Run {
        let offset: Int
        let count: Int
        let score: Float
    }

    static func extract(from data: Data, scanLimit: Int) -> T6RuntimeMesh? {
        guard data.count >= surfaceStride * minimumRun else { return nil }
        let limit = min(data.count, min(max(4096, scanLimit), maxScanBytes))

        return data.withUnsafeBytes { raw -> T6RuntimeMesh? in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            let bytes = UnsafeBufferPointer(start: base, count: limit)
            guard let run = bestRun(in: bytes) else { return nil }

            var surfaces: [Surface] = []
            surfaces.reserveCapacity(min(run.count, maxSurfaces))
            for i in 0..<min(run.count, maxSurfaces) {
                guard let surface = parse(bytes, at: run.offset + i * surfaceStride) else { break }
                surfaces.append(surface)
            }
            surfaces = rejectOutliers(surfaces)
            guard surfaces.count >= minimumRun else { return nil }

            var vertices: [SIMD3<Float>] = []
            var indices: [UInt16] = []
            vertices.reserveCapacity(min(maxVertices, surfaces.count * 4))
            indices.reserveCapacity(surfaces.count * 6)

            for surface in surfaces {
                guard vertices.count <= maxVertices - 4 else { break }
                appendRepresentativeQuad(surface, vertices: &vertices, indices: &indices)
            }

            guard vertices.count >= 24, indices.count >= 36 else { return nil }
            return T6RuntimeMesh(
                vertices: normalize(vertices),
                indices: indices,
                vertexStride: surfaceStride,
                vertexOffset: run.offset,
                positionOffset: 0,
                indexOffset: surfaces.first?.baseIndex ?? 0,
                byteOrder: "GFXWORLD:BE BOUNDS S:\(surfaces.count)"
            )
        }
    }

    private static func bestRun(in bytes: UnsafeBufferPointer<UInt8>) -> Run? {
        let last = bytes.count - surfaceStride * minimumRun
        guard last >= 0 else { return nil }

        var best: Run?
        var offset = 0
        while offset <= last {
            guard parse(bytes, at: offset) != nil else {
                offset += 4
                continue
            }

            var cursor = offset
            var count = 0
            var triTotal = 0
            var worldMin = SIMD3<Float>(repeating: Float.greatestFiniteMagnitude)
            var worldMax = SIMD3<Float>(repeating: -Float.greatestFiniteMagnitude)

            while cursor + surfaceStride <= bytes.count,
                  count < maxSurfaces,
                  let surface = parse(bytes, at: cursor) {
                worldMin = componentMin(worldMin, surface.mins)
                worldMax = componentMax(worldMax, surface.maxs)
                triTotal += min(surface.triCount, 32_768)
                count += 1
                cursor += surfaceStride
            }

            if count >= minimumRun {
                let span = worldMax - worldMin
                let sorted = [span.x, span.y, span.z].sorted()
                let score = Float(count) * 20
                    + min(Float(triTotal), 500_000) * 0.002
                    + min(sorted[2], 500_000) * 0.0005
                    + min(sorted[1], 250_000) * 0.0005
                let candidate = Run(offset: offset, count: count, score: score)
                if best == nil || candidate.score > best!.score { best = candidate }
                offset = cursor
            } else {
                offset += 4
            }
        }
        return best
    }

    private static func parse(_ bytes: UnsafeBufferPointer<UInt8>, at offset: Int) -> Surface? {
        guard offset >= 0, offset + surfaceStride <= bytes.count else { return nil }

        let mins = SIMD3<Float>(beFloat(bytes, offset), beFloat(bytes, offset + 4), beFloat(bytes, offset + 8))
        let maxs = SIMD3<Float>(beFloat(bytes, offset + 16), beFloat(bytes, offset + 20), beFloat(bytes, offset + 24))
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
        let sorted = [span.x, span.y, span.z].sorted()
        guard sorted[2] > 0.0001, sorted[2] < 2_000_000, sorted[1] > 0.00001 else { return nil }

        return Surface(mins: mins, maxs: maxs, triCount: triCount, baseIndex: baseIndex)
    }

    private static func appendRepresentativeQuad(
        _ surface: Surface,
        vertices: inout [SIMD3<Float>],
        indices: inout [UInt16]
    ) {
        let a = surface.mins
        let b = surface.maxs
        let span = b - a
        let base = UInt16(vertices.count)

        if span.x <= span.y && span.x <= span.z {
            let x = (a.x + b.x) * 0.5
            vertices.append(contentsOf: [
                SIMD3<Float>(x, a.y, a.z), SIMD3<Float>(x, b.y, a.z),
                SIMD3<Float>(x, b.y, b.z), SIMD3<Float>(x, a.y, b.z)
            ])
        } else if span.y <= span.z {
            let y = (a.y + b.y) * 0.5
            vertices.append(contentsOf: [
                SIMD3<Float>(a.x, y, a.z), SIMD3<Float>(b.x, y, a.z),
                SIMD3<Float>(b.x, y, b.z), SIMD3<Float>(a.x, y, b.z)
            ])
        } else {
            let z = (a.z + b.z) * 0.5
            vertices.append(contentsOf: [
                SIMD3<Float>(a.x, a.y, z), SIMD3<Float>(b.x, a.y, z),
                SIMD3<Float>(b.x, b.y, z), SIMD3<Float>(a.x, b.y, z)
            ])
        }

        indices.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
    }

    private static func rejectOutliers(_ input: [Surface]) -> [Surface] {
        guard input.count >= 24 else { return input }
        let centers = input.map { ($0.mins + $0.maxs) * 0.5 }
        let xs = centers.map(\.x).sorted()
        let ys = centers.map(\.y).sorted()
        let zs = centers.map(\.z).sorted()
        let mid = centers.count / 2
        let median = SIMD3<Float>(xs[mid], ys[mid], zs[mid])
        let distances = centers.map { length($0 - median) }.sorted()
        let p90 = distances[min(distances.count - 1, Int(Float(distances.count - 1) * 0.90))]
        let radius = max(1, p90 * 4)
        let filtered = zip(input, centers).compactMap { surface, center in
            length(center - median) <= radius ? surface : nil
        }
        return filtered.count >= minimumRun ? filtered : input
    }

    private static func normalize(_ vertices: [SIMD3<Float>]) -> [SIMD3<Float>] {
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

    private static func length(_ v: SIMD3<Float>) -> Float {
        sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    }
}
