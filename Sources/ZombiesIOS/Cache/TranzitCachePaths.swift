import Foundation

struct TranzitCachePaths: Sendable {
    let root: URL
    let active: URL
    let staging: URL

    init(applicationSupportRoot: URL) {
        root = applicationSupportRoot.appendingPathComponent("TranzitCache", isDirectory: true)
        active = root.appendingPathComponent("active", isDirectory: true)
        staging = root.appendingPathComponent("staging", isDirectory: true)
    }

    static func defaultPaths(fileManager: FileManager = .default) throws -> TranzitCachePaths {
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return TranzitCachePaths(applicationSupportRoot: support)
    }

    var activeMesh: URL { active.appendingPathComponent("world.meshbin") }
    var activeMaterials: URL { active.appendingPathComponent("materials.json") }
    var activeTextures: URL { active.appendingPathComponent("textures", isDirectory: true) }
    var activeManifest: URL { active.appendingPathComponent("manifest.json") }

    var stagingMesh: URL { staging.appendingPathComponent("world.meshbin") }
    var stagingMaterials: URL { staging.appendingPathComponent("materials.json") }
    var stagingTextures: URL { staging.appendingPathComponent("textures", isDirectory: true) }
    var stagingManifest: URL { staging.appendingPathComponent("manifest.json") }
}
