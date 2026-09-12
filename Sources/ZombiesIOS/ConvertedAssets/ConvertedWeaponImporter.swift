import Foundation

struct ConvertedWeaponTransform: Codable, Equatable {
    let firstPersonPosition: ConvertedFloat3
    let firstPersonEulerAngles: ConvertedFloat3
    let scale: Float
}

struct ConvertedWeaponMaterialMetadata: Codable, Equatable {
    let name: String
    let diffuseTexturePath: String?
    let fallbackReason: String?
    let transform: ConvertedWeaponTransform
}

struct ConvertedWeaponResult {
    let meshPath: String
    let materialPath: String
    let vertexCount: Int
    let indexCount: Int
}

enum ConvertedWeaponImportError: LocalizedError {
    case missingSourceMesh
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingSourceMesh:
            return "A real BO2 weapon mesh could not be resolved; phase-one conversion cannot substitute placeholder geometry."
        case .writeFailed(let reason):
            return "Converted weapon could not be written: \(reason)"
        }
    }
}

struct ConvertedWeaponImporter {
    func convert(
        sourceMesh: T6RuntimeMesh?,
        sourceName: String,
        material: ConvertedMaterialRecord?,
        stagingURL: URL,
        transform: ConvertedWeaponTransform = .init(
            firstPersonPosition: ConvertedFloat3(SIMD3<Float>(0.28, -0.26, -0.58)),
            firstPersonEulerAngles: ConvertedFloat3(SIMD3<Float>(0, 0, 0)),
            scale: 1
        )
    ) throws -> ConvertedWeaponResult {
        guard let sourceMesh else { throw ConvertedWeaponImportError.missingSourceMesh }
        guard let first = sourceMesh.vertices.first else { throw ConvertedWeaponImportError.missingSourceMesh }

        var minV = first
        var maxV = first
        for v in sourceMesh.vertices.dropFirst() {
            minV = SIMD3<Float>(min(minV.x, v.x), min(minV.y, v.y), min(minV.z, v.z))
            maxV = SIMD3<Float>(max(maxV.x, v.x), max(maxV.y, v.y), max(maxV.z, v.z))
        }

        let mesh = ConvertedMesh(
            positions: sourceMesh.vertices,
            indices: sourceMesh.indices.map(UInt32.init),
            boundsMin: minV,
            boundsMax: maxV,
            materialGroups: [.init(materialID: UInt32(max(0, material?.id ?? 0)), firstIndex: 0, indexCount: UInt32(sourceMesh.indices.count))]
        )
        let meshData = try ConvertedMeshFormat.encode(mesh)
        _ = try ConvertedMeshFormat.decode(meshData)

        let meshPath = "weapons/primary.mesh"
        let materialPath = "weapons/primary.material.json"
        let weaponDirectory = stagingURL.appendingPathComponent("weapons", isDirectory: true)
        let meshURL = stagingURL.appendingPathComponent(meshPath, isDirectory: false)
        let materialURL = stagingURL.appendingPathComponent(materialPath, isDirectory: false)
        let metadata = ConvertedWeaponMaterialMetadata(
            name: sourceName,
            diffuseTexturePath: material?.diffuseTexturePath,
            fallbackReason: material?.fallbackReason,
            transform: transform
        )

        do {
            try FileManager.default.createDirectory(at: weaponDirectory, withIntermediateDirectories: true)
            try meshData.write(to: meshURL, options: .atomic)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(metadata).write(to: materialURL, options: .atomic)
        } catch {
            throw ConvertedWeaponImportError.writeFailed(error.localizedDescription)
        }

        return ConvertedWeaponResult(
            meshPath: meshPath,
            materialPath: materialPath,
            vertexCount: mesh.positions.count,
            indexCount: mesh.indices.count
        )
    }
}
