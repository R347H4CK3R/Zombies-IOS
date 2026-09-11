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

    private struct VertexCandidate {
        let offset: Int
        let stride: Int
        let positionOffset: Int
        let order: ByteOrder
        let vertices: [SIMD3<Float>]
        let vertexScore: Float
    }

    private struct IndexCandidate {
        let offset: Int
        let indices: [UInt16]
        let score: Float
    }

    static func extract(from data: Data, scanLimit: Int = 12 * 1024 * 1024) -> T6RuntimeMesh? {
        guard data.count >= 4096 else { return nil }

        let bytes = Array(data.prefix(max(4096, min(scanLimit, data.count))))
        let strides = [16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 60, 64]
        let positionOffsets = [0, 4, 8, 12, 16, 20, 24]

        var bestMesh: (score: Float, vertex: VertexCandidate, index: IndexCandidate)?

        for order in [ByteOrder.big, .little] {
            for stride in strides {
                guard bytes.count > stride * 32 else { continue }

                for positionOffset in positionOffsets where positionOffset + 12 <= stride {
                    let end = bytes.count - stride * 24 - positionOffset - 12
                    guard end > 0 else { continue }

                    var offset = 0
                    while offset <= end {
                        guard let preview = sampleVertices(
                            bytes,
                            offset: offset,
                            stride: stride,
                            positionOffset: positionOffset,
                            order: order,
                            count: 24
                        ) else {
                            offset += 4
                            continue
                        }

                        let previewScore = vertexScore(preview)
                        guard previewScore > 0 else {
                            offset += 4
                            continue
                        }

                        let vertices = collectVertices(
                            bytes,
                            offset: offset,
                            stride: stride,
                            positionOffset: positionOffset,
                            order: order,
                            maxCount: 2048
                        )
                        guard vertices.count >= 24 else {
                            offset += 4
                            continue
                        }

                        let vertex = VertexCandidate(
                            offset: offset,
                            stride: stride,
                            positionOffset: positionOffset,
                            order: order,
                            vertices: vertices,
                            vertexScore: previewScore
                        )

                        let vertexBytesStart = offset
                        let vertexBytesEnd = min(bytes.count, offset + stride * vertices.count)
                        let searchStart = max(0, vertexBytesStart - 768 * 1024)
                        let searchEnd = min(bytes.count, vertexBytesEnd + 768 * 1024)

                        if let index = findBestIndices(
                            bytes,
                            start: searchStart,
                            end: searchEnd,
                            excludingStart: vertexBytesStart,
                            excludingEnd: vertexBytesEnd,
                            vertices: vertices,
                            order: order
                        ) {
                            let combined = previewScore + index.score
                            if bestMesh == nil || combined > bestMesh!.score {
                                bestMesh = (combined, vertex, index)
                            }
                        }

                        offset += 4
                    }
                }
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
        guard activeAxes >= 2, maxSpan > 0.01, maxSpan < 100_000 else { return -1 }

        var stepSum: Float = 0
        var repeated = 0
        for i in 1..<vertices.count {
            let d = distance(vertices[i], vertices[i - 1])
            stepSum += d
            if d < maxSpan * 0.00001 { repeated += 1 }
        }

        let averageStep = stepSum / Float(max(1, vertices.count - 1))
        guard averageStep > 0.00001, averageStep < max(10_000, maxSpan * 8) else { return -1 }
        guard repeated < vertices.count / 2 else { return -1 }

        let balanced = min(span.x, min(span.y, span.z)) / max(0.0001, maxSpan)
        return Float(activeAxes) * 100 + min(200, balanced * 200) + min(100, Float(vertices.count) / 8)
    }

    private static func plausible(_ value: SIMD3<Float>) -> Bool {
        guard value.x.isFinite, value.y.isFinite, value.z.isFinite else { return false }
        let limit: Float = 1_000_000
        guard abs(value.x) <= limit, abs(value.y) <= limit, abs(value.z) <= limit else { return false }
        let magnitude = abs(value.x) + abs(value.y) + abs(value.z)
        return magnitude > 0.000001
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
            indices.reserveCapacity(3072)
            var cursor = offset
            var invalidRun = 0

            while cursor + 6 <= upper && indices.count < 3072 {
                if cursor >= excludingStart && cursor < excludingEnd { break }

                let a = u16(bytes, cursor, order)
                let b = u16(bytes, cursor + 2, order)
                let c = u16(bytes, cursor + 4, order)

                if Int(a) < vertices.count,
                   Int(b) < vertices.count,
                   Int(c) < vertices.count,
                   a != b, b != c, a != c {
                    indices.append(a)
                    indices.append(b)
                    indices.append(c)
                    invalidRun = 0
                } else {
                    invalidRun += 1
                    if invalidRun >= 2 { break }
                }
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
        let extent = max(0.0001, max(span.x, max(span.y, span.z)))

        var validTriangles = 0
        var rejectedTriangles = 0
        var totalNormalizedEdge: Float = 0
        var used = Set<UInt16>()

        var i = 0
        while i + 2 < indices.count {
            let ia = indices[i]
            let ib = indices[i + 1]
            let ic = indices[i + 2]
            i += 3

            guard Int(ia) < vertices.count,
                  Int(ib) < vertices.count,
                  Int(ic) < vertices.count else {
                rejectedTriangles += 1
                continue
            }

            let a = vertices[Int(ia)]
            let b = vertices[Int(ib)]
            let c = vertices[Int(ic)]
            let ab = distance(a, b)
            let bc = distance(b, c)
            let ca = distance(c, a)
            let longest = max(ab, max(bc, ca))
            let area2 = length(cross(b - a, c - a))

            if area2 <= extent * extent * 0.00000001 || longest > extent * 0.95 {
                rejectedTriangles += 1
                continue
            }

            validTriangles += 1
            totalNormalizedEdge += (ab + bc + ca) / (3 * extent)
            used.insert(ia)
            used.insert(ib)
            used.insert(ic)
        }

        guard validTriangles >= 6 else { return -1 }
        let total = validTriangles + rejectedTriangles
        let validRatio = Float(validTriangles) / Float(max(1, total))
        guard validRatio >= 0.70 else { return -1 }

        let averageEdge = totalNormalizedEdge / Float(validTriangles)
        guard averageEdge < 0.45 else { return -1 }

        let usageRatio = Float(used.count) / Float(max(1, vertices.count))
        return Float(validTriangles) * 4 + validRatio * 300 + min(usageRatio, 0.75) * 220 - averageEdge * 120
    }

    private static func sanitizeTriangles(_ indices: [UInt16], vertices: [SIMD3<Float>]) -> [UInt16] {
        guard vertices.count >= 3 else { return [] }
        let bounds = boundsFor(vertices)
        let span = bounds.max - bounds.min
        let extent = max(0.0001, max(span.x, max(span.y, span.z)))
        var result: [UInt16] = []
        result.reserveCapacity(indices.count)

        var i = 0
        while i + 2 < indices.count {
            let ia = indices[i]
            let ib = indices[i + 1]
            let ic = indices[i + 2]
            i += 3

            guard Int(ia) < vertices.count,
                  Int(ib) < vertices.count,
                  Int(ic) < vertices.count else { continue }

            let a = vertices[Int(ia)]
            let b = vertices[Int(ib)]
            let c = vertices[Int(ic)]
            let ab = distance(a, b)
            let bc = distance(b, c)
            let ca = distance(c, a)
            let longest = max(ab, max(bc, ca))
            let area2 = length(cross(b - a, c - a))

            guard area2 > extent * extent * 0.00000001,
                  longest <= extent * 0.95 else { continue }

            result.append(ia)
            result.append(ib)
            result.append(ic)
        }
        return result
    }

    private static func normalize(_ vertices: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard !vertices.isEmpty else { return vertices }
        let bounds = boundsFor(vertices)
        let center = (bounds.min + bounds.max) * 0.5
        let span = bounds.max - bounds.min
        let largest = max(0.001, max(span.x, max(span.y, span.z)))
        let scale = min(1.0, 12.0 / largest)
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

    private static func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        length(a - b)
    }

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
