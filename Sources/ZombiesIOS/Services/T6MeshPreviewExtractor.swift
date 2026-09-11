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
    private enum ByteOrder: CaseIterable {
        case big
        case little

        var label: String { self == .big ? "BE" : "LE" }
    }

    private struct VertexCandidate {
        let score: Float
        let offset: Int
        let stride: Int
        let positionOffset: Int
        let order: ByteOrder
        let vertices: [SIMD3<Float>]
    }

    private struct IndexCandidate {
        let score: Float
        let offset: Int
        let order: ByteOrder
        let baseIndex: UInt16
        let indices: [UInt16]
    }

    private struct MeshCandidate {
        let score: Float
        let vertex: VertexCandidate
        let index: IndexCandidate
    }

    static func extract(from data: Data, scanLimit: Int = 24 * 1024 * 1024) -> T6RuntimeMesh? {
        guard data.count >= 4096 else { return nil }

        let limit = max(4096, min(scanLimit, data.count))
        let bytes = Array(data.prefix(limit))
        let strides = [12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 60, 64, 68, 72, 80, 96]
        let positionOffsets = Array(stride(from: 0, through: 32, by: 4))

        var vertexCandidates: [VertexCandidate] = []
        vertexCandidates.reserveCapacity(96)

        for order in ByteOrder.allCases {
            for stride in strides {
                guard bytes.count > stride * 48 else { continue }
                for positionOffset in positionOffsets where positionOffset + 12 <= stride {
                    let last = bytes.count - stride * 32 - positionOffset - 12
                    guard last > 0 else { continue }

                    var offset = 0
                    while offset <= last {
                        if let sample = sampleVertices(bytes, offset: offset, stride: stride, positionOffset: positionOffset, order: order, count: 32) {
                            let score = vertexScore(sample)
                            if score > 0 {
                                let vertices = collectVertices(bytes, offset: offset, stride: stride, positionOffset: positionOffset, order: order, maxCount: 12_000)
                                if vertices.count >= 48 {
                                    insertVertex(
                                        VertexCandidate(
                                            score: score + min(Float(vertices.count), 6_000) * 0.12,
                                            offset: offset,
                                            stride: stride,
                                            positionOffset: positionOffset,
                                            order: order,
                                            vertices: vertices
                                        ),
                                        into: &vertexCandidates,
                                        limit: 96
                                    )
                                }
                            }
                        }
                        offset += 16
                    }
                }
            }

            if order == .big, vertexCandidates.count >= 24,
               vertexCandidates.prefix(8).allSatisfy({ $0.score > 500 }) {
                break
            }
        }

        guard !vertexCandidates.isEmpty else { return nil }

        var best: MeshCandidate?
        for vertex in vertexCandidates {
            let vertexBytesStart = vertex.offset
            let vertexBytesEnd = min(bytes.count, vertex.offset + vertex.stride * vertex.vertices.count)
            let searchStart = max(0, vertexBytesStart - 3 * 1024 * 1024)
            let searchEnd = min(bytes.count, vertexBytesEnd + 3 * 1024 * 1024)

            for indexOrder in ByteOrder.allCases {
                guard let index = findBestIndices(
                    bytes,
                    start: searchStart,
                    end: searchEnd,
                    excludingStart: vertexBytesStart,
                    excludingEnd: vertexBytesEnd,
                    vertices: vertex.vertices,
                    order: indexOrder
                ) else { continue }

                let endianBonus: Float = vertex.order == .big ? 120 : 0
                let matchingEndianBonus: Float = vertex.order == index.order ? 40 : 0
                let topologyBonus = min(Float(index.indices.count / 3), 8_000) * 1.4
                let vertexBonus = min(Float(vertex.vertices.count), 8_000) * 0.30
                let combined = vertex.score + index.score + endianBonus + matchingEndianBonus + topologyBonus + vertexBonus
                let candidate = MeshCandidate(score: combined, vertex: vertex, index: index)
                if best == nil || candidate.score > best!.score {
                    best = candidate
                }
            }
        }

        guard let best else { return nil }
        let safeVertexCount = min(best.vertex.vertices.count, Int(UInt16.max))
        let safeVertices = Array(best.vertex.vertices.prefix(safeVertexCount))
        let sanitized = sanitizeTriangles(best.index.indices, vertices: safeVertices)
        guard sanitized.count >= 270 else { return nil }

        let worldVertices = normalizeForSceneKit(safeVertices)
        return T6RuntimeMesh(
            vertices: worldVertices,
            indices: sanitized,
            vertexStride: best.vertex.stride,
            vertexOffset: best.vertex.offset,
            positionOffset: best.vertex.positionOffset,
            indexOffset: best.index.offset,
            byteOrder: "V:\(best.vertex.order.label) I:\(best.index.order.label) B:\(best.index.baseIndex) ZUP"
        )
    }

    private static func insertVertex(_ candidate: VertexCandidate, into list: inout [VertexCandidate], limit: Int) {
        if let i = list.firstIndex(where: {
            $0.offset == candidate.offset && $0.stride == candidate.stride && $0.positionOffset == candidate.positionOffset && $0.order == candidate.order
        }) {
            if candidate.score > list[i].score { list[i] = candidate }
        } else {
            list.append(candidate)
        }
        list.sort { $0.score > $1.score }
        if list.count > limit { list.removeLast(list.count - limit) }
    }

    private static func sampleVertices(_ bytes: [UInt8], offset: Int, stride: Int, positionOffset: Int, order: ByteOrder, count: Int) -> [SIMD3<Float>]? {
        var result: [SIMD3<Float>] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            let base = offset + i * stride + positionOffset
            guard base + 12 <= bytes.count,
                  let value = readPosition(bytes, offset: base, order: order),
                  plausible(value) else { return nil }
            result.append(value)
        }
        return result
    }

    private static func collectVertices(_ bytes: [UInt8], offset: Int, stride: Int, positionOffset: Int, order: ByteOrder, maxCount: Int) -> [SIMD3<Float>] {
        var result: [SIMD3<Float>] = []
        result.reserveCapacity(maxCount)
        var invalidRun = 0

        for i in 0..<maxCount {
            let base = offset + i * stride + positionOffset
            guard base + 12 <= bytes.count else { break }
            if let value = readPosition(bytes, offset: base, order: order), plausible(value) {
                result.append(value)
                invalidRun = 0
            } else {
                invalidRun += 1
                if invalidRun >= 3 { break }
            }
        }
        return result
    }

    private static func vertexScore(_ vertices: [SIMD3<Float>]) -> Float {
        guard vertices.count >= 24 else { return -1 }
        let bounds = boundsFor(vertices)
        let span = bounds.max - bounds.min
        let extent = max(span.x, max(span.y, span.z))
        guard extent > 0.001, extent < 2_000_000 else { return -1 }

        let activeAxes = [span.x, span.y, span.z].filter { $0 > max(0.0001, extent * 0.0001) }.count
        guard activeAxes >= 2 else { return -1 }

        var stepTotal: Float = 0
        var repeated = 0
        var hugeSteps = 0
        for i in 1..<vertices.count {
            let d = distance(vertices[i], vertices[i - 1])
            stepTotal += d
            if d < extent * 0.00001 { repeated += 1 }
            if d > extent * 0.92 { hugeSteps += 1 }
        }

        guard repeated < vertices.count / 3, hugeSteps < vertices.count / 3 else { return -1 }
        let averageStep = stepTotal / Float(max(1, vertices.count - 1))
        guard averageStep > 0.000001, averageStep < extent * 0.80 else { return -1 }

        let sortedSpans = [span.x, span.y, span.z].sorted()
        let secondAxisRatio = sortedSpans[1] / max(0.0001, sortedSpans[2])
        let smallestAxisRatio = sortedSpans[0] / max(0.0001, sortedSpans[2])

        return Float(activeAxes) * 100
            + min(240, secondAxisRatio * 240)
            + min(100, smallestAxisRatio * 100)
            - min(140, averageStep / extent * 180)
    }

    private static func findBestIndices(_ bytes: [UInt8], start: Int, end: Int, excludingStart: Int, excludingEnd: Int, vertices: [SIMD3<Float>], order: ByteOrder) -> IndexCandidate? {
        guard vertices.count >= 48, start < end else { return nil }
        let upper = min(end, bytes.count)
        var best: IndexCandidate?
        var offset = start + (start & 1)

        while offset + 180 <= upper {
            if offset >= excludingStart && offset < excludingEnd {
                offset = excludingEnd + (excludingEnd & 1)
                continue
            }

            var raw: [UInt16] = []
            raw.reserveCapacity(24_000)
            var cursor = offset
            var minIndex = UInt16.max
            var maxIndex: UInt16 = 0
            var bad = 0

            while cursor + 2 <= upper && raw.count < 24_000 {
                if cursor >= excludingStart && cursor < excludingEnd { break }
                let value = u16(bytes, cursor, order)
                raw.append(value)
                minIndex = min(minIndex, value)
                maxIndex = max(maxIndex, value)
                cursor += 2

                if raw.count >= 96 {
                    let range = Int(maxIndex) - Int(minIndex)
                    if range >= vertices.count {
                        bad += 1
                        if bad >= 4 { break }
                    } else {
                        bad = 0
                    }
                }
            }

            if raw.count >= 270, minIndex != UInt16.max, Int(maxIndex) - Int(minIndex) < vertices.count {
                let count = raw.count - raw.count % 3
                var rebased: [UInt16] = []
                rebased.reserveCapacity(count)
                for value in raw.prefix(count) { rebased.append(value &- minIndex) }

                let score = triangleScore(rebased, vertices: vertices)
                if score > 0 {
                    let candidate = IndexCandidate(score: score, offset: offset, order: order, baseIndex: minIndex, indices: rebased)
                    if best == nil || candidate.score > best!.score { best = candidate }
                }
            }

            offset += 2
        }
        return best
    }

    private static func triangleScore(_ indices: [UInt16], vertices: [SIMD3<Float>]) -> Float {
        guard indices.count >= 270 else { return -1 }
        let bounds = boundsFor(vertices)
        let span = bounds.max - bounds.min
        let extent = max(Float(0.0001), max(span.x, max(span.y, span.z)))

        var valid = 0
        var rejected = 0
        var used = Set<UInt16>()
        var edges = Set<UInt64>()
        var sharedEdges = 0
        var normalizedEdgeTotal: Float = 0

        var i = 0
        while i + 2 < indices.count {
            let ia = indices[i], ib = indices[i + 1], ic = indices[i + 2]
            i += 3
            guard ia != ib, ib != ic, ia != ic,
                  Int(ia) < vertices.count, Int(ib) < vertices.count, Int(ic) < vertices.count else {
                rejected += 1
                continue
            }

            let a = vertices[Int(ia)], b = vertices[Int(ib)], c = vertices[Int(ic)]
            let ab = distance(a, b), bc = distance(b, c), ca = distance(c, a)
            let longest = max(ab, max(bc, ca))
            let area2 = length(cross(b - a, c - a))
            if area2 <= extent * extent * 0.000000005 || longest > extent * 0.85 {
                rejected += 1
                continue
            }

            valid += 1
            normalizedEdgeTotal += (ab + bc + ca) / (3 * extent)
            used.insert(ia); used.insert(ib); used.insert(ic)
            for (u, v) in [(ia, ib), (ib, ic), (ic, ia)] {
                let lo = min(u, v), hi = max(u, v)
                let key = (UInt64(lo) << 32) | UInt64(hi)
                if !edges.insert(key).inserted { sharedEdges += 1 }
            }
        }

        guard valid >= 90 else { return -1 }
        let validity = Float(valid) / Float(max(1, valid + rejected))
        guard validity >= 0.70 else { return -1 }
        let usage = Float(used.count) / Float(max(1, vertices.count))
        guard used.count >= 36, usage >= 0.02 else { return -1 }
        let averageEdge = normalizedEdgeTotal / Float(valid)
        guard averageEdge < 0.36 else { return -1 }
        let sharedRatio = Float(sharedEdges) / Float(max(1, valid * 3))
        guard sharedRatio >= 0.04 else { return -1 }

        return Float(valid) * 5.0
            + validity * 650
            + min(usage, 0.90) * 420
            + min(sharedRatio, 0.70) * 650
            - averageEdge * 220
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
            let ia = indices[i], ib = indices[i + 1], ic = indices[i + 2]
            i += 3
            guard ia != ib, ib != ic, ia != ic,
                  Int(ia) < vertices.count, Int(ib) < vertices.count, Int(ic) < vertices.count else { continue }
            let a = vertices[Int(ia)], b = vertices[Int(ib)], c = vertices[Int(ic)]
            let longest = max(distance(a, b), max(distance(b, c), distance(c, a)))
            let area2 = length(cross(b - a, c - a))
            guard area2 > extent * extent * 0.000000005, longest <= extent * 0.85 else { continue }
            result.append(ia); result.append(ib); result.append(ic)
        }
        return result
    }

    private static func normalizeForSceneKit(_ vertices: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard !vertices.isEmpty else { return vertices }

        // T6/Call of Duty world coordinates are Z-up. SceneKit is Y-up.
        let converted = vertices.map { SIMD3<Float>($0.x, $0.z, -$0.y) }
        let bounds = boundsFor(converted)
        let span = bounds.max - bounds.min
        let largest = max(Float(0.0001), max(span.x, max(span.y, span.z)))
        let scale = 42.0 / largest
        let centerX = (bounds.min.x + bounds.max.x) * 0.5
        let centerZ = (bounds.min.z + bounds.max.z) * 0.5
        let groundY = bounds.min.y

        return converted.map {
            SIMD3<Float>(
                ($0.x - centerX) * scale,
                ($0.y - groundY) * scale,
                ($0.z - centerZ) * scale
            )
        }
    }

    private static func plausible(_ value: SIMD3<Float>) -> Bool {
        guard value.x.isFinite, value.y.isFinite, value.z.isFinite else { return false }
        let limit: Float = 2_000_000
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

    private static func boundsFor(_ vertices: [SIMD3<Float>]) -> (min: SIMD3<Float>, max: SIMD3<Float>) {
        var minV = vertices[0]
        var maxV = vertices[0]
        for v in vertices.dropFirst() {
            minV = SIMD3<Float>(min(minV.x, v.x), min(minV.y, v.y), min(minV.z, v.z))
            maxV = SIMD3<Float>(max(maxV.x, v.x), max(maxV.y, v.y), max(maxV.z, v.z))
        }
        return (minV, maxV)
    }

    private static func distance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float { length(a - b) }
    private static func length(_ v: SIMD3<Float>) -> Float { sqrt(v.x * v.x + v.y * v.y + v.z * v.z) }
    private static func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }

    private static func u32(_ bytes: [UInt8], _ offset: Int, _ order: ByteOrder) -> UInt32 {
        switch order {
        case .big:
            return (UInt32(bytes[offset]) << 24) | (UInt32(bytes[offset + 1]) << 16) | (UInt32(bytes[offset + 2]) << 8) | UInt32(bytes[offset + 3])
        case .little:
            return UInt32(bytes[offset]) | (UInt32(bytes[offset + 1]) << 8) | (UInt32(bytes[offset + 2]) << 16) | (UInt32(bytes[offset + 3]) << 24)
        }
    }

    private static func u16(_ bytes: [UInt8], _ offset: Int, _ order: ByteOrder) -> UInt16 {
        switch order {
        case .big: return (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
        case .little: return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
        }
    }
}
