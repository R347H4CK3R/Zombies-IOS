import Foundation

struct T6RuntimeMesh: Equatable {
    let vertices: [SIMD3<Float>]
    let indices: [UInt16]
    let vertexStride: Int
    let vertexOffset: Int
    let positionOffset: Int
    let indexOffset: Int
    let byteOrder: String

    var triangleCount: Int { indices.count / 3 }
}

enum T6MeshPreviewExtractor {
    private enum ByteOrder {
        case big
        case little
    }

    private struct PreviewCandidate {
        let score: Float
        let offset: Int
        let stride: Int
        let positionOffset: Int
        let order: ByteOrder
    }

    private struct VertexCandidate {
        let offset: Int
        let stride: Int
        let positionOffset: Int
        let order: ByteOrder
        let vertices: [SIMD3<Float>]
        let score: Float
    }

    private struct IndexCandidate {
        let offset: Int
        let indices: [UInt16]
        let score: Float
    }

    static func extract(from data: Data, scanLimit: Int = 12 * 1024 * 1024) -> T6RuntimeMesh? {
        guard data.count >= 4096 else { return nil }

        let bytes = Array(data.prefix(max(4096, min(scanLimit, data.count))))
        let strides = [20, 24, 28, 32, 36, 40, 44, 48, 52, 56]
        let positionOffsets = [0, 4, 8, 12, 16, 20]
        var previews: [PreviewCandidate] = []
        previews.reserveCapacity(24)

        // Stage 1: cheap coarse scan. Keep only the strongest vertex-layout candidates.
        for order in [ByteOrder.big, .little] {
            for stride in strides {
                guard bytes.count > stride * 20 else { continue }
                for positionOffset in positionOffsets where positionOffset + 12 <= stride {
                    let end = bytes.count - stride * 16 - positionOffset - 12
                    guard end > 0 else { continue }

                    var offset = 0
                    while offset <= end {
                        if let sample = sampleVertices(
                            bytes,
                            offset: offset,
                            stride: stride,
                            positionOffset: positionOffset,
                            order: order,
                            count: 16
                        ) {
                            let score = vertexScore(sample)
                            if score > 0 {
                                insertPreview(
                                    PreviewCandidate(
                                        score: score,
                                        offset: offset,
                                        stride: stride,
                                        positionOffset: positionOffset,
                                        order: order
                                    ),
                                    into: &previews,
                                    limit: 24
                                )
                            }
                        }
                        offset += 16
                    }
                }
            }
        }

        guard !previews.isEmpty else { return nil }

        // Stage 2: only the best layouts get the expensive index/triangle validation.
        var bestMesh: (score: Float, vertex: VertexCandidate, index: IndexCandidate)?
        for preview in previews {
            let vertices = collectVertices(
                bytes,
                offset: preview.offset,
                stride: preview.stride,
                positionOffset: preview.positionOffset,
                order: preview.order,
                maxCount: 2048
            )
            guard vertices.count >= 18 else { continue }

            let vertex = VertexCandidate(
                offset: preview.offset,
                stride: preview.stride,
                positionOffset: preview.positionOffset,
                order: preview.order,
                vertices: vertices,
                score: preview.score
            )

            let vertexBytesStart = preview.offset
            let vertexBytesEnd = min(bytes.count, preview.offset + preview.stride * vertices.count)
            let searchStart = max(0, vertexBytesStart - 512 * 1024)
            let searchEnd = min(bytes.count, vertexBytesEnd + 512 * 1024)

            guard let index = findBestIndices(
                bytes,
                start: searchStart,
                end: searchEnd,
                excludingStart: vertexBytesStart,
                excludingEnd: vertexBytesEnd,
                vertices: vertices,
                order: preview.order
            ) else { continue }

            let combined = vertex.score + index.score
            if bestMesh == nil || combined > bestMesh!.score {
                bestMesh = (combined, vertex, index)
            }
        }

        guard let bestMesh else { return nil }

        let safeVertexCount = min(bestMesh.vertex.vertices.count, Int(UInt16.max))
        let safeVertices = Array(bestMesh.vertex.vertices.prefix(safeVertexCount))
        let filteredIndices = sanitizeTriangles(bestMesh.index.indices, vertices: safeVertices)
        guard filteredIndices.count >= 18 else { return nil }

        return T6RuntimeMesh(
            vertices: normalize(safeVertices),
            indices: filteredIndices,
            vertexStride: bestMesh.vertex.stride,
            vertexOffset: bestMesh.vertex.offset,
            positionOffset: bestMesh.vertex.positionOffset,
            indexOffset: bestMesh.index.offset,
            byteOrder: bestMesh.vertex.order == .big ? "BE" : "LE"
        )
    }

    private static func insertPreview(_ candidate: PreviewCandidate, into list: inout [PreviewCandidate], limit: Int) {
        if let duplicate = list.firstIndex(where: {
            $0.offset == candidate.offset &&
            $0.stride == candidate.stride &&
            $0.positionOffset == candidate.positionOffset &&
            sameOrder($0.order, candidate.order)
        }) {
            if candidate.score > list[duplicate].score { list[duplicate] = candidate }
            return
        }

        list.append(candidate)
        list.sort { $0.score > $1.score }
        if list.count > limit { list.removeLast(list.count - limit) }
    }

    private static func sameOrder(_ lhs: ByteOrder, _ rhs: ByteOrder) -> Bool {
        switch (lhs, rhs) {
        case (.big, .big), (.little, .little): return true
        default: return false
        }
    }

    private static func sampleVertices(
        _ bytes: [UInt8],
        offset: Int,
        stride: Int,
        positionOffset: Int,
        order: ByteOrder,
        count: Int
    ) -> [SIMD3<Float>]? {
        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(count)
        for i in 0..<count {
            let base = offset + i * stride + positionOffset
            guard base + 12 <= bytes.count,
                  let vertex = readPosition(bytes, offset: base, order: order),
                  plausible(vertex) else { return nil }
            vertices.append(vertex)
        }
        return vertices
    }

    private static func collectVertices(
        _ bytes: [UInt8],
        offset: Int,
        stride: Int,
        positionOffset: Int,
        order: ByteOrder,
        maxCount: Int
    ) -> [SIMD3<Float>] {
        var result: [SIMD3<Float>] = []
        result.reserveCapacity(maxCount)
        var badStreak = 0

        for i in 0..<maxCount {
            let base = offset + i * stride + positionOffset
            guard base + 12 <= bytes.count else { break }
            if let vertex = readPosition(bytes, offset: base, order: order), plausible(vertex) {
                result.append(vertex)
                badStreak = 0
            } else {
                badStreak += 1
                if badStreak >= 3 { break }
            }
        }
        return result
    }

    private static func vertexScore(_ vertices: [SIMD3<Float>]) -> Float {
        guard vertices.count >= 12 else { return -1 }
        let bounds = boundsFor(vertices)
        let span = bounds.max - bounds.min
        let maxSpan = max(span.x, max(span.y, span.z))
        let activeAxes = [span.x, span.y, span.z].filter { $0 > 0.001 }.count
        guard activeAxes >= 2, maxSpan > 0.01, maxSpan < 1_000_000 else { return -1 }

        var stepSum: Float = 0
        var repeated = 0
        for i in 1..<vertices.count {
            let d = distance(vertices[i], vertices[i - 1])
            stepSum += d
            if d < maxSpan * 0.00001 { repeated += 1 }
        }

        let averageStep = stepSum / Float(max(1, vertices.count - 1))
        guard averageStep > 0.00001, averageStep < max(Float(10_000), maxSpan * 8) else { return -1 }
        guard repeated < vertices.count / 2 else { return -1 }

        let smallest = min(span.x, min(span.y, span.z))
        let balanced = smallest / max(Float(0.0001), maxSpan)
        return Float(activeAxes) * 100 + min(Float(200), balanced * 200)
    }

    private static func plausible(_ value: SIMD3<Float>) -> Bool {
        guard value.x.isFinite, value.y.isFinite, value.z.isFinite else { return false }
        let limit: Float = 1_000_000
        guard abs(value.x) <= limit, abs(value.y) <= limit, abs(value.z) <= limit else { return false }
        return abs(value.x) + abs(value.y) + abs(value.z) > 0.000001
    }

    private static func readPosition(_ bytes: [UInt8], offset: Int, order: ByteOrder) -> SIMD3<Float>? {
        guard offset >= 0, offset + 12 <= bytes.count else { return nil }
        let x = Float(bitPattern: u32(bytes, offset, order))
        let y = Float(bitPattern: u32(bytes, offset + 4, order))
        let z = Float(bitPattern: u32(bytes, offset + 8, order))
        guard x.isFinite, y.isFinite, z.isFinite else { return nil }
        return SIMD3<Float>(x, y, z)
    }

    private static func findBestIndices(
        _ bytes: [UInt8],
        start: Int,
        end: Int,
        excludingStart: Int,
        excludingEnd: Int,
        vertices: [SIMD3<Float>],
        order: ByteOrder
    ) -> IndexCandidate? {
        guard vertices.count >= 3, start < end else { return nil }
        let upper = min(end, bytes.count)
        var best: IndexCandidate?
        var offset = start + (start & 1)

        while offset + 36 <= upper {
            if offset >= excludingStart && offset < excludingEnd {
                offset = excludingEnd + (excludingEnd & 1)
                continue
            }

            var indices: [UInt16] = []
            indices.reserveCapacity(1536)
            var cursor = offset

            while cursor + 6 <= upper && indices.count < 1536 {
                if cursor >= excludingStart && cursor < excludingEnd { break }
                let a = u16(bytes, cursor, order)
                let b = u16(bytes, cursor + 2, order)
                let c = u16(bytes, cursor + 4, order)
                guard Int(a) < vertices.count,
                      Int(b) < vertices.count,
                      Int(c) < vertices.count,
                      a != b, b != c, a != c else { break }
                indices.append(a)
                indices.append(b)
                indices.append(c)
                cursor += 6
            }

            if indices.count >= 18 {
                let score = triangleScore(indices, vertices: vertices)
                if score > 0, best == nil || score > best!.score {
                    best = IndexCandidate(offset: offset, indices: indices, score: score)
                }
            }
            offset += 2
        }
        return best
    }

    private static func triangleScore(_ indices: [UInt16], vertices: [SIMD3<Float>]) -> Float {
        guard indices.count >= 18 else { return -1 }
        let bounds = boundsFor(vertices)
        let span = bounds.max - bounds.min
        let extent = max(Float(0.0001), max(span.x, max(span.y, span.z)))

        var valid = 0
        var rejected = 0
        var normalizedEdgeSum: Float = 0
        var used = Set<UInt16>()

        var i = 0
        while i + 2 < indices.count {
            let ia = indices[i]
            let ib = indices[i + 1]
            let ic = indices[i + 2]
            i += 3

            let a = vertices[Int(ia)]
            let b = vertices[Int(ib)]
            let c = vertices[Int(ic)]
            let ab = distance(a, b)
            let bc = distance(b, c)
            let ca = distance(c, a)
            let longest = max(ab, max(bc, ca))
            let area2 = length(cross(b - a, c - a))

            if area2 <= extent * extent * 0.00000001 || longest > extent * 0.95 {
                rejected += 1
                continue
            }

            valid += 1
            normalizedEdgeSum += (ab + bc + ca) / (3 * extent)
            used.insert(ia); used.insert(ib); used.insert(ic)
        }

        guard valid >= 6 else { return -1 }
        let ratio = Float(valid) / Float(max(1, valid + rejected))
        guard ratio >= 0.70 else { return -1 }
        let averageEdge = normalizedEdgeSum / Float(valid)
        guard averageEdge < 0.45 else { return -1 }
        let usage = Float(used.count) / Float(max(1, vertices.count))
        return Float(valid) * 4 + ratio * 300 + min(usage, 0.75) * 220 - averageEdge * 120
    }

    private static func sanitizeTriangles(_ indices: [UInt16], vertices: [SIMD3<Float>]) -> [UInt16] {
        guard vertices.count >= 3 else { return [] }
        let bounds = boundsFor(vertices)
        let span = bounds.max - bounds.min
        let extent = max(Float(0.0001), max(span.x, max(span.y, span.z)))
        var result: [UInt16] = []
        result.reserveCapacity(indices.count)

        var i = 0
        while i + 2 < indices.count {
            let ia = indices[i]
            let ib = indices[i + 1]
            let ic = indices[i + 2]
            i += 3
            guard Int(ia) < vertices.count, Int(ib) < vertices.count, Int(ic) < vertices.count else { continue }

            let a = vertices[Int(ia)]
            let b = vertices[Int(ib)]
            let c = vertices[Int(ic)]
            let longest = max(distance(a, b), max(distance(b, c), distance(c, a)))
            let area2 = length(cross(b - a, c - a))
            guard area2 > extent * extent * 0.00000001, longest <= extent * 0.95 else { continue }
            result.append(ia); result.append(ib); result.append(ic)
        }
        return result
    }

    private static func normalize(_ vertices: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard !vertices.isEmpty else { return vertices }
        let bounds = boundsFor(vertices)
        let center = (bounds.min + bounds.max) * 0.5
        let span = bounds.max - bounds.min
        let largest = max(Float(0.001), max(span.x, max(span.y, span.z)))
        let scale = min(Float(1.0), 12.0 / largest)
        return vertices.map { ($0 - center) * scale }
    }

    private static func boundsFor(_ vertices: [SIMD3<Float>]) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        var minV = vertices[0]
        var maxV = vertices[0]
        for vertex in vertices.dropFirst() {
            minV = componentMin(minV, vertex)
            maxV = componentMax(maxV, vertex)
        }
        return (minV, maxV)
    }

    private static func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { length(a - b) }

    private static func length(_ v: SIMD3<Float>) -> Float {
        sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    }

    private static func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(
            a.y * b.z - a.z * b.y,
            a.z * b.x - a.x * b.z,
            a.x * b.y - a.y * b.x
        )
    }

    private static func componentMin(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(min(lhs.x, rhs.x), min(lhs.y, rhs.y), min(lhs.z, rhs.z))
    }

    private static func componentMax(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(max(lhs.x, rhs.x), max(lhs.y, rhs.y), max(lhs.z, rhs.z))
    }

    private static func u32(_ bytes: [UInt8], _ offset: Int, _ order: ByteOrder) -> UInt32 {
        switch order {
        case .big:
            return (UInt32(bytes[offset]) << 24) |
                (UInt32(bytes[offset + 1]) << 16) |
                (UInt32(bytes[offset + 2]) << 8) |
                UInt32(bytes[offset + 3])
        case .little:
            return UInt32(bytes[offset]) |
                (UInt32(bytes[offset + 1]) << 8) |
                (UInt32(bytes[offset + 2]) << 16) |
                (UInt32(bytes[offset + 3]) << 24)
        }
    }

    private static func u16(_ bytes: [UInt8], _ offset: Int, _ order: ByteOrder) -> UInt16 {
        switch order {
        case .big:
            return (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
        case .little:
            return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        }
    }
}
