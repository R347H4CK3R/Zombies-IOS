import Foundation

struct BO2RuntimePackageWriter {
    enum WriterError: LocalizedError {
        case emptyGeometry

        var errorDescription: String? {
            switch self {
            case .emptyGeometry: return "The decoded BO2 world contained no renderable geometry."
            }
        }
    }

    func makePackage(mesh: T6RuntimeMesh, entities: [BO2RuntimeEntity] = [], spawns: [BO2RuntimeSpawn] = [], sourceName: String) throws -> BO2RuntimePackage {
        guard !mesh.vertices.isEmpty, mesh.indices.count >= 3 else { throw WriterError.emptyGeometry }
        let vertices = mesh.vertices.map { BO2RuntimeVertex(x: $0.x, y: $0.y, z: $0.z) }
        let indices = mesh.indices.map(UInt32.init)
        return BO2RuntimePackage(sourceName: sourceName, vertices: vertices, indices: indices, spawns: spawns, entities: entities)
    }

    func write(mesh: T6RuntimeMesh, entities: [BO2RuntimeEntity] = [], spawns: [BO2RuntimeSpawn] = [], sourceName: String) throws -> URL {
        let package = try makePackage(mesh: mesh, entities: entities, spawns: spawns, sourceName: sourceName)
        let root = try RuntimeCachePolicy.expressiveDirectory()
        let safeName = sourceName.replacingOccurrences(of: "/", with: "_")
        let directory = root.appendingPathComponent("bo2world-v1-\(safeName)", isDirectory: true)
        let fm = FileManager.default
        if fm.fileExists(atPath: directory.path) { try fm.removeItem(at: directory) }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let metadata = directory.appendingPathComponent("world.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(package).write(to: metadata, options: .atomic)
        return metadata
    }

    func read(from url: URL) throws -> BO2RuntimePackage {
        try JSONDecoder().decode(BO2RuntimePackage.self, from: Data(contentsOf: url))
    }
}
