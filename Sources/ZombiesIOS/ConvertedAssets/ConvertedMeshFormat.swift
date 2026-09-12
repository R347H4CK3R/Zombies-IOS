import Foundation

struct ConvertedMaterialGroup: Equatable {
    let materialID: UInt32
    let firstIndex: UInt32
    let indexCount: UInt32
}

struct ConvertedMesh: Equatable {
    let positions: [SIMD3<Float>]
    let indices: [UInt32]
    let boundsMin: SIMD3<Float>
    let boundsMax: SIMD3<Float>
    let materialGroups: [ConvertedMaterialGroup]
}

struct ConvertedMeshHeader {
    static let magic: UInt32 = 0x5A4D5348 // ZMSH
    static let formatVersion: UInt16 = 1
    static let vertexStride: UInt16 = 12
    static let indexWidth: UInt16 = 4

    let vertexCount: UInt32
    let indexCount: UInt32
    let materialGroupCount: UInt16
    let boundsMin: SIMD3<Float>
    let boundsMax: SIMD3<Float>
}

enum ConvertedMeshFormatError: Error {
    case invalidMagic
    case unsupportedVersion
    case invalidVertexStride
    case invalidIndexWidth
    case truncated
    case emptyMesh
    case nonFiniteVertex
    case invalidBounds
    case indexOutOfRange
    case invalidMaterialGroup
}

enum ConvertedMeshFormat {
    static func validate(_ mesh: ConvertedMesh) throws {
        guard !mesh.positions.isEmpty, mesh.indices.count >= 3, mesh.indices.count % 3 == 0 else {
            throw ConvertedMeshFormatError.emptyMesh
        }
        guard mesh.positions.allSatisfy({ $0.x.isFinite && $0.y.isFinite && $0.z.isFinite }) else {
            throw ConvertedMeshFormatError.nonFiniteVertex
        }
        guard finite(mesh.boundsMin), finite(mesh.boundsMax),
              mesh.boundsMin.x <= mesh.boundsMax.x,
              mesh.boundsMin.y <= mesh.boundsMax.y,
              mesh.boundsMin.z <= mesh.boundsMax.z,
              mesh.boundsMin != mesh.boundsMax else {
            throw ConvertedMeshFormatError.invalidBounds
        }
        let count = UInt32(mesh.positions.count)
        guard mesh.indices.allSatisfy({ $0 < count }) else {
            throw ConvertedMeshFormatError.indexOutOfRange
        }
        for group in mesh.materialGroups {
            let end = UInt64(group.firstIndex) + UInt64(group.indexCount)
            guard group.indexCount > 0, end <= UInt64(mesh.indices.count) else {
                throw ConvertedMeshFormatError.invalidMaterialGroup
            }
        }
    }

    static func encode(_ mesh: ConvertedMesh) throws -> Data {
        try validate(mesh)
        var data = Data()
        append(ConvertedMeshHeader.magic, to: &data)
        append(ConvertedMeshHeader.formatVersion, to: &data)
        append(ConvertedMeshHeader.vertexStride, to: &data)
        append(UInt32(mesh.positions.count), to: &data)
        append(UInt32(mesh.indices.count), to: &data)
        append(ConvertedMeshHeader.indexWidth, to: &data)
        append(UInt16(mesh.materialGroups.count), to: &data)
        append(mesh.boundsMin, to: &data)
        append(mesh.boundsMax, to: &data)

        for position in mesh.positions { append(position, to: &data) }
        for index in mesh.indices { append(index, to: &data) }
        for group in mesh.materialGroups {
            append(group.materialID, to: &data)
            append(group.firstIndex, to: &data)
            append(group.indexCount, to: &data)
        }
        return data
    }

    static func decode(_ data: Data) throws -> ConvertedMesh {
        var cursor = 0
        let magic: UInt32 = try read(from: data, cursor: &cursor)
        guard magic == ConvertedMeshHeader.magic else { throw ConvertedMeshFormatError.invalidMagic }
        let version: UInt16 = try read(from: data, cursor: &cursor)
        guard version == ConvertedMeshHeader.formatVersion else { throw ConvertedMeshFormatError.unsupportedVersion }
        let stride: UInt16 = try read(from: data, cursor: &cursor)
        guard stride == ConvertedMeshHeader.vertexStride else { throw ConvertedMeshFormatError.invalidVertexStride }
        let vertexCount: UInt32 = try read(from: data, cursor: &cursor)
        let indexCount: UInt32 = try read(from: data, cursor: &cursor)
        let indexWidth: UInt16 = try read(from: data, cursor: &cursor)
        guard indexWidth == ConvertedMeshHeader.indexWidth else { throw ConvertedMeshFormatError.invalidIndexWidth }
        let materialGroupCount: UInt16 = try read(from: data, cursor: &cursor)
        let boundsMin = try readVector(from: data, cursor: &cursor)
        let boundsMax = try readVector(from: data, cursor: &cursor)

        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(Int(vertexCount))
        for _ in 0..<vertexCount { positions.append(try readVector(from: data, cursor: &cursor)) }

        var indices: [UInt32] = []
        indices.reserveCapacity(Int(indexCount))
        for _ in 0..<indexCount {
            let value: UInt32 = try read(from: data, cursor: &cursor)
            indices.append(value)
        }

        var groups: [ConvertedMaterialGroup] = []
        groups.reserveCapacity(Int(materialGroupCount))
        for _ in 0..<materialGroupCount {
            let materialID: UInt32 = try read(from: data, cursor: &cursor)
            let firstIndex: UInt32 = try read(from: data, cursor: &cursor)
            let groupIndexCount: UInt32 = try read(from: data, cursor: &cursor)
            groups.append(.init(materialID: materialID, firstIndex: firstIndex, indexCount: groupIndexCount))
        }

        let mesh = ConvertedMesh(
            positions: positions,
            indices: indices,
            boundsMin: boundsMin,
            boundsMax: boundsMax,
            materialGroups: groups
        )
        try validate(mesh)
        return mesh
    }

    static func roundTripSelfCheck() -> Bool {
        let mesh = ConvertedMesh(
            positions: [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0)],
            indices: [0, 1, 2],
            boundsMin: SIMD3<Float>(0, 0, 0),
            boundsMax: SIMD3<Float>(1, 1, 0),
            materialGroups: [.init(materialID: 0, firstIndex: 0, indexCount: 3)]
        )
        guard let data = try? encode(mesh), let decoded = try? decode(data) else { return false }
        return decoded == mesh
    }

    private static func finite(_ value: SIMD3<Float>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }

    private static func append(_ value: UInt16, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func append(_ value: UInt32, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }

    private static func append(_ value: Float, to data: inout Data) {
        append(value.bitPattern, to: &data)
    }

    private static func append(_ value: SIMD3<Float>, to data: inout Data) {
        append(value.x, to: &data)
        append(value.y, to: &data)
        append(value.z, to: &data)
    }

    private static func read<T: FixedWidthInteger>(from data: Data, cursor: inout Int) throws -> T {
        let size = MemoryLayout<T>.size
        guard cursor + size <= data.count else { throw ConvertedMeshFormatError.truncated }
        let value: T = data[cursor..<(cursor + size)].withUnsafeBytes { raw in
            raw.loadUnaligned(as: T.self)
        }
        cursor += size
        return T(littleEndian: value)
    }

    private static func readFloat(from data: Data, cursor: inout Int) throws -> Float {
        let bits: UInt32 = try read(from: data, cursor: &cursor)
        return Float(bitPattern: bits)
    }

    private static func readVector(from data: Data, cursor: inout Int) throws -> SIMD3<Float> {
        SIMD3<Float>(
            try readFloat(from: data, cursor: &cursor),
            try readFloat(from: data, cursor: &cursor),
            try readFloat(from: data, cursor: &cursor)
        )
    }
}
