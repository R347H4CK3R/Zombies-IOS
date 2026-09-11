import Foundation

struct T6RuntimeMesh: Equatable {
    let vertices: [SIMD3<Float>]
    let indices: [UInt16]
    let vertexStride: Int
    let vertexOffset: Int
    let indexOffset: Int
    let byteOrder: String

    var triangleCount: Int { indices.count / 3 }
}

enum T6MeshPreviewExtractor {
    private enum ByteOrder {
        case big
        case little
    }

    static func extract(from data: Data, scanLimit: Int = 8 * 1024 * 1024) -> T6RuntimeMesh? {
        guard data.count >= 4096 else { return nil }

        let bytes = Array(data.prefix(max(4096, min(scanLimit, data.count))))
        let strides = [32, 36, 40, 44, 48]

        var best: (score: Float, offset: Int, stride: Int, order: ByteOrder, vertices: [SIMD3<Float>])?

        for order in [ByteOrder.big, .little] {
            for stride in strides {
                guard bytes.count > stride * 32 else { continue }
                let end = bytes.count - stride * 24 - 12
                var offset = 0

                while offset <= end {
                    if let preview = sampleVertices(bytes, offset: offset, stride: stride, order: order, count: 24) {
                        let score = vertexScore(preview)
                        if score > 0, best == nil || score > best!.score {
                            let vertices = collectVertices(bytes, offset: offset, stride: stride, order: order, maxCount: 768)
                            if vertices.count >= 24 {
                                best = (score, offset, stride, order, vertices)
                            }
                        }
                    }
                    offset += 4
                }
            }
        }

        guard let best else { return nil }

        let searchStart = min(bytes.count, best.offset + best.stride * best.vertices.count)
        let searchEnd = min(bytes.count, searchStart + 512 * 1024)

        guard let indexResult = findIndices(
            bytes,
            start: searchStart,
            end: searchEnd,
            vertexCount: best.vertices.count,
            order: best.order
        ) else {
            return nil
        }

        let safeVertexCount = min(best.vertices.count, Int(UInt16.max))
        let safeVertices = Array(best.vertices.prefix(safeVertexCount))
        let safeIndices = indexResult.indices.filter { Int($0) < safeVertexCount }
        guard safeIndices.count >= 36 else { return nil }

        return T6RuntimeMesh(
            vertices: normalize(safeVertices),
            indices: safeIndices,
            vertexStride: best.stride,
            vertexOffset: best.offset,
            indexOffset: indexResult.offset,
            byteOrder: best.order == .big ? "BE" : "LE"
        )
    }

    private static func sampleVertices(
        _ bytes: [UInt8],
        offset: Int,
        stride: Int,
        order: ByteOrder,
        count: Int
    ) -> [SIMD3<Float>]? {
        var vertices: [SIMD3<Float>] = []
        vertices.reserveCapacity(count)
        for i in 0..<count {
            let base = offset + i * stride
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
        order: ByteOrder,
        maxCount: Int
    ) -> [SIMD3<Float>] {
        var result: [SIMD3<Float>] = []
        result.reserveCapacity(maxCount)
        var badStreak = 0

        for i in 0..<maxCount {
            let base = offset + i * stride
            guard base + 12 <= bytes.count else { break }
            if let vertex = readPosition(bytes, offset: base, order: order), plausible(vertex) {
                result.append(vertex)
                badStreak = 0
            } else {
                badStreak += 1
                if badStreak >= 2 { break }
            }
        }
        return result
    }

    private static func vertexScore(_ vertices: [SIMD3<Float>]) -> Float {
        guard vertices.count >= 12 else { return -1 }
        var minV = vertices[0]
        var maxV = vertices[0]
        var distanceSum: Float = 0

        for i in 1..<vertices.count {
            let vertex = vertices[i]
            minV = componentMin(minV, vertex)
            maxV = componentMax(maxV, vertex)
            let delta = vertex - vertices[i - 1]
            distanceSum += sqrt(delta.x * delta.x + delta.y * delta.y + delta.z * delta.z)
        }

        let span = maxV - minV
        let maxSpan = max(span.x, max(span.y, span.z))
        let minSpan = min(span.x, min(span.y, span.z))
        let averageStep = distanceSum / Float(max(1, vertices.count - 1))

        guard maxSpan > 0.05,
              maxSpan < 20_000,
              averageStep > 0.0001,
              averageStep < 10_000 else { return -1 }

        let dimensionScore = min(3, (span.x > 0.01 ? 1 : 0) + (span.y > 0.01 ? 1 : 0) + (span.z > 0.01 ? 1 : 0))
        guard dimensionScore >= 2 else { return -1 }

        return Float(dimensionScore) * 100 + min(maxSpan, 500) - min(minSpan, 0.001) * 10
    }

    private static func plausible(_ value: SIMD3<Float>) -> Bool {
        guard value.x.isFinite, value.y.isFinite, value.z.isFinite else { return false }
        let limit: Float = 65_536
        guard abs(value.x) <= limit, abs(value.y) <= limit, abs(value.z) <= limit else { return false }
        let magnitude = abs(value.x) + abs(value.y) + abs(value.z)
        return magnitude > 0.00001
    }

    private static func readPosition(_ bytes: [UInt8], offset: Int, order: ByteOrder) -> SIMD3<Float>? {
        guard offset >= 0, offset + 12 <= bytes.count else { return nil }
        let x = Float(bitPattern: u32(bytes, offset, order))
        let y = Float(bitPattern: u32(bytes, offset + 4, order))
        let z = Float(bitPattern: u32(bytes, offset + 8, order))
        guard x.isFinite, y.isFinite, z.isFinite else { return nil }
        return SIMD3<Float>(x, y, z)
    }

    private static func findIndices(
        _ bytes: [UInt8],
        start: Int,
        end: Int,
        vertexCount: Int,
        order: ByteOrder
    ) -> (offset: Int, indices: [UInt16])? {
        guard vertexCount >= 3, start < end else { return nil }
        let upper = min(end, bytes.count)
        var best: (offset: Int, indices: [UInt16])?
        var offset = start + (start & 1)

        while offset + 72 <= upper {
            var indices: [UInt16] = []
            indices.reserveCapacity(1536)
            var cursor = offset

            while cursor + 6 <= upper && indices.count < 1536 {
                let a = u16(bytes, cursor, order)
                let b = u16(bytes, cursor + 2, order)
                let c = u16(bytes, cursor + 4, order)
                guard Int(a) < vertexCount,
                      Int(b) < vertexCount,
                      Int(c) < vertexCount,
                      a != b, b != c, a != c else { break }
                indices.append(a)
                indices.append(b)
                indices.append(c)
                cursor += 6
            }

            if indices.count >= 36, best == nil || indices.count > best!.indices.count {
                best = (offset, indices)
            }
            offset += 2
        }
        return best
    }

    private static func normalize(_ vertices: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard let first = vertices.first else { return vertices }
        var minV = first
        var maxV = first
        for vertex in vertices.dropFirst() {
            minV = componentMin(minV, vertex)
            maxV = componentMax(maxV, vertex)
        }

        let center = (minV + maxV) * 0.5
        let span = maxV - minV
        let largest = max(0.001, max(span.x, max(span.y, span.z)))
        let scale = min(1.0, 10.0 / largest)

        return vertices.map { ($0 - center) * scale }
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
