import Foundation

struct ConvertedTranzitLoader {
    enum LoadError: LocalizedError {
        case missingWeaponMaterial

        var errorDescription: String? {
            switch self {
            case .missingWeaponMaterial:
                return "Converted weapon material metadata is missing."
            }
        }
    }

    func load(rootURL: URL = ConvertedTranzitPaths.activeRoot) throws -> ConvertedRuntimePackage {
        let manifest = try ConvertedPackageValidator.validate(at: rootURL)
        let worldMesh = try loadMesh(manifest.worldMeshPath, rootURL: rootURL)
        let collisionMesh = try loadMesh(manifest.collisionMeshPath, rootURL: rootURL)
        let weaponMesh = try loadMesh(manifest.weaponMeshPath, rootURL: rootURL)

        let materialURL = rootURL.appendingPathComponent(manifest.materialManifestPath, isDirectory: false)
        let materialManifest = try JSONDecoder().decode(
            ConvertedMaterialManifest.self,
            from: Data(contentsOf: materialURL)
        )

        let weaponMaterialURL = rootURL.appendingPathComponent("weapons/primary.material.json", isDirectory: false)
        guard FileManager.default.fileExists(atPath: weaponMaterialURL.path) else {
            throw LoadError.missingWeaponMaterial
        }
        let weaponMaterial = try JSONDecoder().decode(
            ConvertedWeaponMaterialMetadata.self,
            from: Data(contentsOf: weaponMaterialURL)
        )

        return ConvertedRuntimePackage(
            rootURL: rootURL,
            manifest: manifest,
            worldMesh: worldMesh,
            collisionMesh: collisionMesh,
            materialManifest: materialManifest,
            weaponMesh: weaponMesh,
            weaponMaterial: weaponMaterial
        )
    }

    private func loadMesh(_ relativePath: String, rootURL: URL) throws -> ConvertedMesh {
        let url = rootURL.appendingPathComponent(relativePath, isDirectory: false)
        return try ConvertedMeshFormat.decode(Data(contentsOf: url))
    }
}
