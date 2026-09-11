import Foundation
import simd

enum TranzitMeshBinaryError: Error, Equatable {
    case invalidMagic
    case unsupportedVersion
    case truncated
    case invalidCount
    case invalidIndex
    case invalidSubmeshRange
}

enum TranzitMeshBinary {
    private static let magic = Array("TRNZMESH".utf8)
    private static let version: UInt32 = 1

    static func write(world: TranzitCachedWorld, to url: URL) throws {
        guard world.positions.count == world.normals.count,
              world.positions.count == world.uvs.count else { throw TranzitMeshBinaryError.invalidCount }
        guard world.indices.allSatisfy({ Int($0) < world.positions.count }) else { throw TranzitMeshBinaryError.invalidIndex }
        guard world.submeshes.allSatisfy({ $0.firstIndex >= 0 && $0.indexCount >= 0 && $0.firstIndex + $0.indexCount <= world.indices.count }) else {
            throw TranzitMeshBinaryError.invalidSubmeshRange
        }

        var data = Data(magic)
        append(version, to: &data)
        append(UInt32(world.positions.count), to: &data)
        append(UInt32(world.indices.count), to: &data)
        append(UInt32(world.submeshes.count), to: &data)

        for i in world.positions.indices {
            let p = world.positions[i], n = world.normals[i], uv = world.uvs[i]
            [p.x, p.y, p.z, n.x, n.y, n.z, uv.x, uv.y].forEach { append($0, to: &data) }
        }
        world.indices.forEach { append($0, to: &data) }
        for s in world.submeshes {
            append(UInt32(s.firstIndex), to: &data)
            append(UInt32(s.indexCount), to: &data)
            append(Int32(s.materialID), to: &data)
        }
        try data.write(to: url, options: .atomic)
    }

    static func read(from url: URL, materials: [TranzitCachedMaterial]) throws -> TranzitCachedWorld {
        let data = try Data(contentsOf: url)
        var cursor = 0
        guard data.count >= 24 else { throw TranzitMeshBinaryError.truncated }
        guard Array(data.prefix(8)) == magic else { throw TranzitMeshBinaryError.invalidMagic }
        cursor = 8
        let fileVersion: UInt32 = try read(&cursor, from: data)
        guard fileVersion == version else { throw TranzitMeshBinaryError.unsupportedVersion }
        let vertexCount = Int(try readUInt32(&cursor, data))
        let indexCount = Int(try readUInt32(&cursor, data))
        let submeshCount = Int(try readUInt32(&cursor, data))
        guard vertexCount >= 0, indexCount >= 0, submeshCount >= 0,
              vertexCount <= 5_000_000, indexCount <= 30_000_000, submeshCount <= 1_000_000 else {
            throw TranzitMeshBinaryError.invalidCount
        }
        let expected = 24 + vertexCount * 32 + indexCount * 4 + submeshCount * 12
        guard expected == data.count else { throw TranzitMeshBinaryError.truncated }

        var positions = [SIMD3<Float>](); positions.reserveCapacity(vertexCount)
        var normals = [SIMD3<Float>](); normals.reserveCapacity(vertexCount)
        var uvs = [SIMD2<Float>](); uvs.reserveCapacity(vertexCount)
        for _ in 0..<vertexCount {
            let px = try readFloat(&cursor, data), py = try readFloat(&cursor, data), pz = try readFloat(&cursor, data)
            let nx = try readFloat(&cursor, data), ny = try readFloat(&cursor, data), nz = try readFloat(&cursor, data)
            let u = try readFloat(&cursor, data), v = try readFloat(&cursor, data)
            positions.append(SIMD3(px, py, pz)); normals.append(SIMD3(nx, ny, nz)); uvs.append(SIMD2(u, v))
        }
        var indices = [UInt32](); indices.reserveCapacity(indexCount)
        for _ in 0..<indexCount {
            let value = try readUInt32(&cursor, data)
            guard Int(value) < vertexCount else { throw TranzitMeshBinaryError.invalidIndex }
            indices.append(value)
        }
        var submeshes = [TranzitCachedSubmesh](); submeshes.reserveCapacity(submeshCount)
        for _ in 0..<submeshCount {
            let first = Int(try readUInt32(&cursor, data))
            let count = Int(try readUInt32(&cursor, data))
            let materialID = Int(try readInt32(&cursor, data))
            guard first >= 0, count >= 0, first + count <= indexCount else { throw TranzitMeshBinaryError.invalidSubmeshRange }
            submeshes.append(.init(firstIndex: first, indexCount: count, materialID: materialID))
        }
        return TranzitCachedWorld(positions: positions, normals: normals, uvs: uvs, indices: indices, submeshes: submeshes, materials: materials)
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    private static func append(_ value: Float, to data: inout Data) {
        append(value.bitPattern, to: &data)
    }

    private static func read<T: FixedWidthInteger>(_ cursor: inout Int, from data: Data) throws -> T {
        guard cursor + MemoryLayout<T>.size <= data.count else { throw TranzitMeshBinaryError.truncated }
        let value: T = data.withUnsafeBytes { raw in
            raw.loadUnaligned(fromByteOffset: cursor, as: T.self)
        }
        cursor += MemoryLayout<T>.size
        return T(littleEndian: value)
    }

    private static func readUInt32(_ cursor: inout Int, _ data: Data) throws -> UInt32 { try read(&cursor, from: data) }
    private static func readInt32(_ cursor: inout Int, _ data: Data) throws -> Int32 { try read(&cursor, from: data) }
    private static func readFloat(_ cursor: inout Int, _ data: Data) throws -> Float { Float(bitPattern: try readUInt32(&cursor, data)) }
}
