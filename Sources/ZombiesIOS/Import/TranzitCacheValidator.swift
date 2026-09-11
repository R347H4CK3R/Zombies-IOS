import Foundation

struct TranzitCacheValidationReport: Sendable {
    let isValid: Bool
    let errors: [String]
    let warnings: [String]
}

enum TranzitCacheValidator {
    static func validate(paths: TranzitCachePaths) -> TranzitCacheValidationReport {
        let fm = FileManager.default
        var errors: [String] = []
        var warnings: [String] = []

        guard fm.fileExists(atPath: paths.staging.path) else {
            return .init(isValid: false, errors: ["staging directory is missing"], warnings: [])
        }
        guard fm.fileExists(atPath: paths.stagingManifest.path) else {
            return .init(isValid: false, errors: ["manifest.json is missing"], warnings: [])
        }
        guard fm.fileExists(atPath: paths.stagingMesh.path) else {
            return .init(isValid: false, errors: ["world.meshbin is missing"], warnings: [])
        }
        guard fm.fileExists(atPath: paths.stagingMaterials.path) else {
            return .init(isValid: false, errors: ["materials.json is missing"], warnings: [])
        }

        do {
            let manifestData = try Data(contentsOf: paths.stagingManifest)
            let manifest = try JSONDecoder().decode(TranzitCacheManifest.self, from: manifestData)
            guard manifest.schemaVersion == TranzitCacheManifest.currentSchemaVersion else {
                return .init(isValid: false, errors: ["unsupported cache schema \(manifest.schemaVersion)"], warnings: manifest.warnings)
            }
            warnings.append(contentsOf: manifest.warnings)

            let materialData = try Data(contentsOf: paths.stagingMaterials)
            let materials = try JSONDecoder().decode([TranzitCachedMaterial].self, from: materialData)
            let world = try TranzitMeshBinary.read(from: paths.stagingMesh, materials: materials)

            if world.positions.isEmpty { errors.append("mesh contains no vertices") }
            if world.indices.count < 3 { errors.append("mesh contains no triangles") }
            if world.indices.count % 3 != 0 { errors.append("mesh index count is not divisible by 3") }
            if world.submeshes.isEmpty { errors.append("mesh contains no submeshes") }
            if manifest.vertexCount != world.positions.count { errors.append("manifest vertex count does not match mesh") }
            if manifest.triangleCount != world.triangleCount { errors.append("manifest triangle count does not match mesh") }
            if manifest.surfaceCount != world.submeshes.count { errors.append("manifest surface count does not match mesh") }
            if manifest.materialCount != materials.count { errors.append("manifest material count does not match materials.json") }
            if manifest.textureSucceeded + manifest.textureFailed != manifest.textureTotal { errors.append("manifest texture counts are inconsistent") }

            let ids = Set(materials.map(\.id))
            for submesh in world.submeshes where !ids.contains(submesh.materialID) {
                errors.append("submesh references missing material \(submesh.materialID)")
                break
            }

            if manifest.textureFailed > 0 {
                warnings.append("\(manifest.textureFailed) texture assets use renderer fallbacks")
            }
        } catch {
            errors.append(error.localizedDescription)
        }

        return .init(isValid: errors.isEmpty, errors: errors, warnings: warnings)
    }
}
