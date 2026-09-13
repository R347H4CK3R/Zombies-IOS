import Foundation
import CryptoKit

struct BO2RuntimePackageWriter {
    enum PackageError: LocalizedError {
        case emptyGeometry
        case invalidIndex(UInt32)
        case incompatibleVersion(UInt32)
        case malformedBinary(String)

        var errorDescription: String? {
            switch self {
            case .emptyGeometry:
                return "BO2 runtime package contains no usable world geometry."
            case .invalidIndex(let index):
                return "BO2 runtime package contains out-of-range vertex index \(index)."
            case .incompatibleVersion(let version):
                return "BO2 runtime package version \(version) is not supported."
            case .malformedBinary(let file):
                return "BO2 runtime package binary is malformed: \(file)."
            }
        }
    }

    private static let verticesName = "world.vertices.bin"
    private static let indicesName = "world.indices.bin"
    private static let metadataName = "world.json"

    @discardableResult
    static func write(
        mesh: T6RuntimeMesh,
        entities: [BO2RuntimeEntity] = [],
        sourceName: String,
        sourceSHA256: String = ""
    ) throws -> URL {
        let vertices = mesh.vertices.map(BO2RuntimeVertex.init)
        let indices = mesh.indices.map(UInt32.init)
        guard vertices.count >= 3, indices.count >= 3 else { throw PackageError.emptyGeometry }
        guard indices.allSatisfy({ Int($0) < vertices.count }) else {
            throw PackageError.invalidIndex(indices.first(where: { Int($0) >= vertices.count }) ?? 0)
        }
        guard let bounds = BO2RuntimePackage.bounds(for: vertices) else { throw PackageError.emptyGeometry }

        let runtimeSpawns = BO2EntityParser.spawns(from: entities)
        let package = BO2RuntimePackage(
            sourceName: sourceName,
            sourceSHA256: sourceSHA256,
            vertices: vertices,
            indices: indices,
            surfaces: [BO2RuntimeSurface(firstIndex: 0, indexCount: UInt32(indices.count), materialID: 0)],
            entities: entities,
            spawns: runtimeSpawns,
            bounds: bounds
        )
        return try write(package)
    }

    @discardableResult
    static func write(_ package: BO2RuntimePackage) throws -> URL {
        guard package.vertices.count >= 3, package.indices.count >= 3 else { throw PackageError.emptyGeometry }
        guard package.indices.allSatisfy({ Int($0) < package.vertices.count }) else {
            throw PackageError.invalidIndex(package.indices.first(where: { Int($0) >= package.vertices.count }) ?? 0)
        }

        let root = try RuntimeCachePolicy.expressiveDirectory()
        let identity = package.sourceSHA256.isEmpty
            ? SHA256.hash(data: Data(package.sourceName.utf8)).map { String(format: "%02x", $0) }.joined()
            : package.sourceSHA256.lowercased()
        let directory = root.appendingPathComponent("bo2world-v1-\(identity.prefix(16))", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try vertexData(package.vertices).write(
            to: directory.appendingPathComponent("world.vertices.bin"),
            options: .atomic
        )
        try indexData(package.indices).write(
            to: directory.appendingPathComponent("world.indices.bin"),
            options: .atomic
        )

        let metadata = BO2RuntimePackageMetadata(
            formatVersion: BO2RuntimePackage.formatVersion,
            sourceName: package.sourceName,
            sourceSHA256: package.sourceSHA256,
            vertexCount: package.vertices.count,
            indexCount: package.indices.count,
            triangleCount: package.triangleCount,
            verticesFile: verticesName,
            indicesFile: indicesName,
            surfaces: package.surfaces,
            entities: package.entities,
            spawns: package.spawns,
            bounds: package.bounds
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(metadata).write(to: directory.appendingPathComponent(metadataName), options: .atomic)
        return directory
    }

    static func read(from directory: URL) throws -> BO2RuntimePackage {
        let metadataURL = directory.appendingPathComponent(metadataName)
        let metadata = try JSONDecoder().decode(BO2RuntimePackageMetadata.self, from: Data(contentsOf: metadataURL))
        guard metadata.formatVersion == BO2RuntimePackage.formatVersion else {
            throw PackageError.incompatibleVersion(metadata.formatVersion)
        }

        let vertices = try decodeVertices(Data(contentsOf: directory.appendingPathComponent(metadata.verticesFile)))
        let indices = try decodeIndices(Data(contentsOf: directory.appendingPathComponent(metadata.indicesFile)))
        guard vertices.count == metadata.vertexCount, indices.count == metadata.indexCount else {
            throw PackageError.malformedBinary("count mismatch")
        }
        guard indices.allSatisfy({ Int($0) < vertices.count }) else {
            throw PackageError.invalidIndex(indices.first(where: { Int($0) >= vertices.count }) ?? 0)
        }

        return BO2RuntimePackage(
            sourceName: metadata.sourceName,
            sourceSHA256: metadata.sourceSHA256,
            vertices: vertices,
            indices: indices,
            surfaces: metadata.surfaces,
            entities: metadata.entities,
            spawns: metadata.spawns,
            bounds: metadata.bounds
        )
    }

    private static func vertexData(_ vertices: [BO2RuntimeVertex]) -> Data {
        var data = Data(capacity: vertices.count * 12)
        for vertex in vertices {
            appendLittleEndian(vertex.x.bitPattern, to: &data)
            appendLittleEndian(vertex.y.bitPattern, to: &data)
            appendLittleEndian(vertex.z.bitPattern, to: &data)
        }
        return data
    }

    private static func indexData(_ indices: [UInt32]) -> Data {
        var data = Data(capacity: indices.count * 4)
        for index in indices { appendLittleEndian(index, to: &data) }
        return data
    }

    private static func decodeVertices(_ data: Data) throws -> [BO2RuntimeVertex] {
        guard data.count % 12 == 0 else { throw PackageError.malformedBinary(verticesName) }
        var vertices: [BO2RuntimeVertex] = []
        vertices.reserveCapacity(data.count / 12)
        var offset = 0
        while offset < data.count {
            let x = Float(bitPattern: readLittleEndianUInt32(data, offset))
            let y = Float(bitPattern: readLittleEndianUInt32(data, offset + 4))
            let z = Float(bitPattern: readLittleEndianUInt32(data, offset + 8))
            vertices.append(BO2RuntimeVertex(SIMD3<Float>(x, y, z)))
            offset += 12
        }
        return vertices
    }

    private static func decodeIndices(_ data: Data) throws -> [UInt32] {
        guard data.count % 4 == 0 else { throw PackageError.malformedBinary(indicesName) }
        var indices: [UInt32] = []
        indices.reserveCapacity(data.count / 4)
        var offset = 0
        while offset < data.count {
            indices.append(readLittleEndianUInt32(data, offset))
            offset += 4
        }
        return indices
    }

    private static func appendLittleEndian(_ value: UInt32, to data: inout Data) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
    }

    private static func readLittleEndianUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        UInt32(data[offset])
            | UInt32(data[offset + 1]) << 8
            | UInt32(data[offset + 2]) << 16
            | UInt32(data[offset + 3]) << 24
    }
}
