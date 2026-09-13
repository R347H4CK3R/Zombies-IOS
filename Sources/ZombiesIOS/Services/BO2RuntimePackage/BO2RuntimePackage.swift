import Foundation

struct BO2RuntimeVertex: Codable, Equatable {
    let x: Float
    let y: Float
    let z: Float
}

struct BO2RuntimeSpawn: Codable, Equatable {
    let origin: BO2RuntimeVertex
    let yaw: Float
    let classname: String
}

struct BO2RuntimeEntity: Codable, Equatable {
    let classname: String
    let properties: [String: String]
}

struct BO2RuntimePackage: Codable, Equatable {
    static let formatVersion: UInt32 = 1

    let formatVersion: UInt32
    let sourceName: String
    let vertices: [BO2RuntimeVertex]
    let indices: [UInt32]
    let spawns: [BO2RuntimeSpawn]
    let entities: [BO2RuntimeEntity]

    init(sourceName: String, vertices: [BO2RuntimeVertex], indices: [UInt32], spawns: [BO2RuntimeSpawn] = [], entities: [BO2RuntimeEntity] = []) {
        self.formatVersion = Self.formatVersion
        self.sourceName = sourceName
        self.vertices = vertices
        self.indices = indices
        self.spawns = spawns
        self.entities = entities
    }
}
